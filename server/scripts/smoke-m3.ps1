# M3 smoke: search + tasks + sign-in + youzhu ledger (run AFTER smoke-community & smoke-software)
# Requires: fresh-db chain (a@test.com / b@test.com registered by smoke-community)
$ErrorActionPreference = 'Stop'
$api = "http://localhost:8888/api/v1"

function PostJson($uri, $obj, $headers) {
    $bytes = [Text.Encoding]::UTF8.GetBytes(($obj | ConvertTo-Json -Compress -Depth 5))
    if ($headers) { return Invoke-RestMethod -Method Post -Uri $uri -Headers $headers -ContentType 'application/json; charset=utf-8' -Body $bytes }
    return Invoke-RestMethod -Method Post -Uri $uri -ContentType 'application/json; charset=utf-8' -Body $bytes
}

$login = PostJson "$api/auth/login" @{email = "b@test.com"; password = "pass1234"} $null
$h2 = @{Authorization = "Bearer $($login.data.token)"}

# 1. sign-in: first ok, duplicate rejected (42900)
$s1 = PostJson "$api/tasks/sign-in" @{} $h2
$s2 = PostJson "$api/tasks/sign-in" @{} $h2
Write-Output "[1] sign1=code$($s1.code) reward=$($s1.data.reward) cont=$($s1.data.continuous); signDup=code$($s2.code)"

# 2. task actions: post x1(+newbie), comment x3, like x1
$post = PostJson "$api/posts" @{circleId = 2; title = "task post"; content = "for task progress"; images = @()} $h2
$postId = $post.data.postId
1..3 | ForEach-Object { PostJson "$api/comments" @{postId = $postId; content = "task comment $_"} $h2 | Out-Null }
PostJson "$api/posts/$postId/like" @{} $h2 | Out-Null
$t1 = (Invoke-RestMethod "$api/tasks" -Headers $h2).data
$t1.tasks | ForEach-Object { Write-Output "[2] task$($_.id) $($_.progress)/$($_.target) status=$($_.status)" }

# 3. claim: post task + newbie task; re-claim & undone-claim rejected
$c1 = PostJson "$api/tasks/1/claim" @{} $h2
$c2 = PostJson "$api/tasks/2/claim" @{} $h2
$c5 = PostJson "$api/tasks/5/claim" @{} $h2
$c1b = PostJson "$api/tasks/1/claim" @{} $h2
$c3 = PostJson "$api/tasks/3/claim" @{} $h2
Write-Output "[3] claim1=code$($c1.code)+$($c1.data.reward) claim2=code$($c2.code)+$($c2.data.reward) claim5=code$($c5.code)+$($c5.data.reward) reclaim=code$($c1b.code) undone=code$($c3.code)"

# 4. account + logs
$acct = (Invoke-RestMethod "$api/youzhu/account" -Headers $h2).data
$logs = (Invoke-RestMethod "$api/youzhu/logs" -Headers $h2).data
Write-Output "[4] balance=$($acct.balance) signedToday=$($acct.signedToday) logs=$($logs.Count)"

# 5. ledger reconcile: zero mismatch
$diff = (docker compose exec -T mysql sh -c "mysql -uroot -proot123 yiora -N -e 'SELECT COUNT(1) FROM youzhu_account a LEFT JOIN (SELECT user_id, SUM(amount) s FROM youzhu_log GROUP BY user_id) l ON l.user_id=a.user_id WHERE a.balance != COALESCE(l.s,0)' 2>/dev/null" | Out-String).Trim()
Write-Output "[5] reconcile mismatch rows=$diff (expect 0)"

# 6. search 5 types + LIKE escape + empty kw
$sp = (Invoke-RestMethod "$api/search?type=post&kw=task").data
$su = (Invoke-RestMethod "$api/search?type=user&kw=Alice").data
$ss = (Invoke-RestMethod "$api/search?type=software&kw=Toolbox").data
$esc = (Invoke-RestMethod "$api/search?type=post&kw=%25%25").data
$bad = Invoke-RestMethod "$api/search?type=post&kw="
Write-Output "[6] search post=$($sp.posts.Count) user=$($su.users.Count) software=$($ss.software.Count); escape=$($esc.posts.Count)(expect 0) emptyKw=code$($bad.code)"

Write-Output "M3_SMOKE_DONE"
