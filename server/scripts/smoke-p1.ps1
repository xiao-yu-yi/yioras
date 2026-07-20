# P1 smoke: drafts + post edit + software comments (run AFTER smoke-account)
$ErrorActionPreference = 'Stop'
$api = "http://localhost:8888/api/v1"

function PostJson($uri, $obj, $headers) {
    $bytes = [Text.Encoding]::UTF8.GetBytes(($obj | ConvertTo-Json -Compress -Depth 5))
    if ($headers) { return Invoke-RestMethod -Method Post -Uri $uri -Headers $headers -ContentType 'application/json; charset=utf-8' -Body $bytes }
    return Invoke-RestMethod -Method Post -Uri $uri -ContentType 'application/json; charset=utf-8' -Body $bytes
}
function PutJson($uri, $obj, $headers) {
    $bytes = [Text.Encoding]::UTF8.GetBytes(($obj | ConvertTo-Json -Compress -Depth 5))
    return Invoke-RestMethod -Method Put -Uri $uri -Headers $headers -ContentType 'application/json; charset=utf-8' -Body $bytes
}

$la = PostJson "$api/auth/login" @{email = "a@test.com"; password = "pass1234"} $null
$lb = PostJson "$api/auth/login" @{email = "b@test.com"; password = "pass1234"} $null
$h1 = @{Authorization = "Bearer $($la.data.token)"}
$h2 = @{Authorization = "Bearer $($lb.data.token)"}

# 1. drafts: save -> update -> list -> publish with draftId auto-deletes
$d1 = PostJson "$api/drafts" @{kind = 1; payload = '{"title":"draft v1","content":"wip"}'} $h1
$did = $d1.data.id
$d2 = PostJson "$api/drafts" @{id = $did; kind = 1; payload = '{"title":"draft v2","content":"wip2"}'} $h1
$list1 = (Invoke-RestMethod "$api/drafts?kind=1" -Headers $h1).data
$pub = PostJson "$api/posts" @{circleId = 2; title = "from draft"; content = "published from draft"; draftId = $did} $h1
$list2 = (Invoke-RestMethod "$api/drafts?kind=1" -Headers $h1).data
Write-Output "[1] draft save=$did update=$($d2.data.id) listBefore=$(@($list1).Count) postId=$($pub.data.postId) listAfterPublish=$(@($list2).Count)"

# 2. draft payload validation: invalid json rejected
$bad = PostJson "$api/drafts" @{kind = 1; payload = 'not-json{'} $h1
Write-Output "[2] invalid payload=code$($bad.code)"

# 3. edit post: change title/content/topics -> detail updated, still published
$postId = $pub.data.postId
$ed = PutJson "$api/posts/$postId" @{title = "edited title"; content = "edited body"; topics = @("EditedTopic")} $h1
$detail = (Invoke-RestMethod "$api/posts/$postId").data
Write-Output ("[3] edit=code$($ed.code) status=$($ed.data.status) title=$($detail.title) topics=" + (($detail.topics | ForEach-Object { $_.name }) -join '/'))

# 4. edit permission & re-audit: non-author 40300; review-level word (seeded by 006) -> back to pending & hidden
$forbid = PutJson "$api/posts/$postId" @{content = "hijack"} $h2
$ed2 = PutJson "$api/posts/$postId" @{content = "contains REVIEWWORD_SAMPLE here"} $h1
$guestDetail = Invoke-RestMethod "$api/posts/$postId"
$blocked = PostJson "$api/posts" @{circleId = 2; content = "has BLOCKWORD_SAMPLE inside"} $h1
Write-Output "[4] nonAuthor=code$($forbid.code) reAudit status=$($ed2.data.status) (expect 0) guestView=code$($guestDetail.code) (expect 40400) blockPublish=code$($blocked.code) (expect 42200)"

# 5. software comments: comment on online software (id from mall suite = YioraToolbox)
$soft = ((Invoke-RestMethod "$api/software?type=1").data)[0]
$sc1 = PostJson "$api/comments" @{bizType = 2; bizId = $soft.id; content = "works great"} $h2
$sc2 = PostJson "$api/comments" @{bizType = 2; bizId = $soft.id; parentId = $sc1.data.commentId; content = "agree"} $h1
$clist = (Invoke-RestMethod "$api/comments?bizType=2&bizId=$($soft.id)").data
$soft2 = (Invoke-RestMethod "$api/software/$($soft.id)").data
Write-Output "[5] softComment=$($sc1.data.commentId) reply=$($sc2.data.commentId) list=$(@($clist).Count) commentCount=$($soft2.commentCount)"

# 6. software publisher got comment notification
$n = (Invoke-RestMethod "$api/notifications?type=2" -Headers $h1).data | Select-Object -First 1
Write-Output "[6] publisher notify=[$($n.content)]"

# 7. cross-biz guard: pulling software comment replies with post bizType fails
$badList = Invoke-RestMethod "$api/comments?bizType=1&bizId=$($soft.id)&rootId=$($sc1.data.commentId)"
Write-Output "[7] crossBiz replies=code$($badList.code) (expect 40400)"

# 8. legacy postId contract still works
$legacy = PostJson "$api/comments" @{postId = $postId; content = "legacy field"} $h1   # post is pending -> 40400 expected
Write-Output "[8] legacy postId on pending post=code$($legacy.code) (expect 40400)"

Write-Output "P1_SMOKE_DONE"
