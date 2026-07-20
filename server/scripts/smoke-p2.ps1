# P2 smoke: level/exp + certification + circle admin (run AFTER smoke-p1)
$ErrorActionPreference = 'Stop'
$api = "http://localhost:8888/api/v1"

function PostJson($uri, $obj, $headers) {
    $bytes = [Text.Encoding]::UTF8.GetBytes(($obj | ConvertTo-Json -Compress -Depth 5))
    if ($headers) { return Invoke-RestMethod -Method Post -Uri $uri -Headers $headers -ContentType 'application/json; charset=utf-8' -Body $bytes }
    return Invoke-RestMethod -Method Post -Uri $uri -ContentType 'application/json; charset=utf-8' -Body $bytes
}
# Windows 下 docker exec 参数内嵌引号会被重编码破坏,SQL 一律走临时文件拷贝执行
# 临时目录用 GetTempPath():Windows=%TEMP%,Linux CI=/tmp(env:TEMP 在 Linux 为空)
function MySqlN($sql) {
    $tmp = Join-Path ([IO.Path]::GetTempPath()) "yiora_p2.sql"
    Set-Content -Path $tmp -Value $sql -Encoding ASCII
    docker cp $tmp yiora-mysql-1:/tmp/p2.sql | Out-Null
    return (docker compose exec -T mysql sh -c "mysql -uroot -proot123 -N yiora < /tmp/p2.sql 2>/dev/null" | Out-String).Trim()
}

$la = PostJson "$api/auth/login" @{email = "a@test.com"; password = "pass1234"} $null
$lb = PostJson "$api/auth/login" @{email = "b@test.com"; password = "pass1234"} $null
$h1 = @{Authorization = "Bearer $($la.data.token)"}
$h2 = @{Authorization = "Bearer $($lb.data.token)"}
$uidA = $la.data.userId; $uidB = $lb.data.userId

# 1. exp & level-up: set A exp=96 via SQL, publish a post (+5 exp) -> level becomes 1 (need 100)
MySqlN "UPDATE user SET exp=96, level=0 WHERE id=$uidA;" | Out-Null
$post = PostJson "$api/posts" @{circleId = 2; title = "level up"; content = "exp test"} $h1
$expLevel = MySqlN "SELECT CONCAT(exp,'/',level) FROM user WHERE id=$uidA;"
$profile = (Invoke-RestMethod "$api/users/$uidA").data
Write-Output "[1] post=$($post.data.postId) exp/level=$expLevel (expect 101/1) profileLevel=$($profile.level)"

# 2. certification: submit -> duplicate rejected -> SQL approve -> profile certs + resubmit still rejected
$c1 = PostJson "$api/certifications" @{kind = 2; material = "github.com/alice repos"} $h1
$c2 = PostJson "$api/certifications" @{kind = 2; material = "again"} $h1
MySqlN "UPDATE certification SET status=1 WHERE user_id=$uidA AND kind=2;" | Out-Null
$mine = (Invoke-RestMethod "$api/certifications/mine" -Headers $h1).data
$prof2 = (Invoke-RestMethod "$api/users/$uidA").data
Write-Output ("[2] submit=code$($c1.code) dup=code$($c2.code) mineStatus=$($mine[0].status) profileCerts=" + ($prof2.certs -join ','))

# 3. circle admin permission: plain member B rejected; SQL appoint B as owner of circle 2
$postId = $post.data.postId
$deny = PostJson "$api/circles/2/admin/top" @{postId = $postId; on = $true} $h2
MySqlN "INSERT INTO circle_member (circle_id,user_id,role) VALUES (2,$uidB,2) ON DUPLICATE KEY UPDATE role=2;" | Out-Null
$top = PostJson "$api/circles/2/admin/top" @{postId = $postId; on = $true} $h2
$ess = PostJson "$api/circles/2/admin/essence" @{postId = $postId; on = $true} $h2
$feed = (Invoke-RestMethod "$api/circles/2/posts?sort=new").data
Write-Output "[3] deny=code$($deny.code) top=code$($top.code) essence=code$($ess.code) circleFeedFirst=$($feed[0].id) (expect $postId)"

# 4. mute: B mutes A 1 day -> A cannot post/comment in circle 2 -> unmute -> can post again
$mute = PostJson "$api/circles/2/admin/mute" @{userId = $uidA; days = 1} $h2
$blockedPost = PostJson "$api/posts" @{circleId = 2; content = "muted try"} $h1
$blockedCmt = PostJson "$api/comments" @{postId = $postId; content = "muted comment"} $h1
$unmute = PostJson "$api/circles/2/admin/mute" @{userId = $uidA; days = 0} $h2
$okPost = PostJson "$api/posts" @{circleId = 2; content = "after unmute"} $h1
Write-Output "[4] mute=code$($mute.code) post=code$($blockedPost.code) comment=code$($blockedCmt.code) (expect 40300x2) unmute=code$($unmute.code) afterPost=code$($okPost.code)"

# 5. remove-post by admin -> guest 40400 + author notified; mute admin rejected
$rm = PostJson "$api/circles/2/admin/remove-post" @{postId = $postId} $h2
$gone = Invoke-RestMethod "$api/posts/$postId"
$n = (Invoke-RestMethod "$api/notifications?type=3" -Headers $h1).data | Select-Object -First 1
$muteAdmin = PostJson "$api/circles/2/admin/mute" @{userId = $uidB; days = 1} $h2
Write-Output "[5] remove=code$($rm.code) guestView=code$($gone.code) notify=[$($n.content)] muteAdmin=code$($muteAdmin.code) (expect 40300)"

Write-Output "P2_SMOKE_DONE"
