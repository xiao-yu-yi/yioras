# Content details smoke: topics + mentions + cocreators (run AFTER smoke-paid-ai; needs a/b/c users)
$ErrorActionPreference = 'Stop'
$api = "http://localhost:8888/api/v1"

function PostJson($uri, $obj, $headers) {
    $bytes = [Text.Encoding]::UTF8.GetBytes(($obj | ConvertTo-Json -Compress -Depth 5))
    if ($headers) { return Invoke-RestMethod -Method Post -Uri $uri -Headers $headers -ContentType 'application/json; charset=utf-8' -Body $bytes }
    return Invoke-RestMethod -Method Post -Uri $uri -ContentType 'application/json; charset=utf-8' -Body $bytes
}

$la = PostJson "$api/auth/login" @{email = "a@test.com"; password = "pass1234"} $null
$lb = PostJson "$api/auth/login" @{email = "b@test.com"; password = "pass1234"} $null
$h1 = @{Authorization = "Bearer $($la.data.token)"}
$h2 = @{Authorization = "Bearer $($lb.data.token)"}
$uidA = $la.data.userId; $uidB = $lb.data.userId

# 0. ensure mutual follow (cocreator precondition); smoke-community left b->a only
PostJson "$api/users/$uidB/follow" @{} $h1 | Out-Null
PostJson "$api/users/$uidA/follow" @{} $h2 | Out-Null

# 1. cocreator must be mutual: try invite stranger (bot uid impossible mutual) -> rejected
$bad = PostJson "$api/posts" @{circleId = 2; content = "x"; cocreators = @(999999)} $h1
Write-Output "[1] non-mutual cocreator: code=$($bad.code)"

# 2. publish with topics + mention + cocreator
$post = PostJson "$api/posts" @{circleId = 2; title = "content feature"; content = "topics mentions cocreate"; topics = @("GreenSoft", "#Tools#"); mentions = @($uidB); cocreators = @($uidB)} $h1
$postId = $post.data.postId
$detail = (Invoke-RestMethod "$api/posts/$postId").data
Write-Output ("[2] post=$postId topics=" + (($detail.topics | ForEach-Object { $_.name }) -join '/') + " cocreators(before confirm)=$($detail.cocreators.Count)")

# 3. b notifications: mention(type2) + cocreate invite(type3)
$n2 = (Invoke-RestMethod "$api/notifications?type=2" -Headers $h2).data | Select-Object -First 1
$n3 = (Invoke-RestMethod "$api/notifications?type=3" -Headers $h2).data | Select-Object -First 1
Write-Output "[3] mention notify=[$($n2.content)]; invite notify=[$($n3.content)]"

# 4. topic aggregation page (find topic id from detail)
$topicId = ($detail.topics | Where-Object { $_.name -eq 'GreenSoft' }).id
$tp = (Invoke-RestMethod "$api/topics/$topicId/posts?sort=new").data
Write-Output "[4] topic page: name=$($tp.topic.name) postCount=$($tp.topic.postCount) posts=$($tp.posts.Count)"

# 5. duplicate-topic dedupe + reuse: second post with same topic -> same id, count+1
$post2 = PostJson "$api/posts" @{circleId = 2; content = "another with same topic"; topics = @("GreenSoft", "GreenSoft")} $h2
$tp2 = (Invoke-RestMethod "$api/topics/$topicId/posts?sort=new").data
Write-Output "[5] post2=$($post2.data.postId) topic postCount=$($tp2.topic.postCount) posts=$($tp2.posts.Count)"

# 6. cocreate confirm by b -> appears in detail cocreators + both author pages
$cf = PostJson "$api/posts/$postId/cocreate/confirm" @{accept = $true} $h2
$cf2 = PostJson "$api/posts/$postId/cocreate/confirm" @{accept = $true} $h2
$detail2 = (Invoke-RestMethod "$api/posts/$postId").data
$bPosts = (Invoke-RestMethod "$api/users/$uidB/posts").data
$hasCocreated = @($bPosts | Where-Object { $_.id -eq $postId }).Count
Write-Output "[6] confirm=code$($cf.code) reconfirm=code$($cf2.code) cocreators=$($detail2.cocreators.Count)($($detail2.cocreators[0].nickname)) inBAuthorPage=$hasCocreated"

# 7. author a gets accept notification
$n3a = (Invoke-RestMethod "$api/notifications?type=3" -Headers $h1).data | Select-Object -First 1
Write-Output "[7] author notify=[$($n3a.content)]"

# 8. comment with mention -> b notified type2
PostJson "$api/comments" @{postId = $postId; content = "comment mention"; mentions = @($uidB)} $h1 | Out-Null
$n2b = (Invoke-RestMethod "$api/notifications?type=2" -Headers $h2).data | Select-Object -First 1
Write-Output "[8] comment mention notify=[$($n2b.content)]"

# 9. delete post -> topic count decrement
(Invoke-RestMethod -Method Delete -Uri "$api/posts/$postId" -Headers $h1).code | Out-Null
$tp3 = (Invoke-RestMethod "$api/topics/$topicId/posts?sort=new").data
Write-Output "[9] after delete: topic postCount=$($tp3.topic.postCount) posts=$($tp3.posts.Count)"

Write-Output "CONTENT_SMOKE_DONE"
