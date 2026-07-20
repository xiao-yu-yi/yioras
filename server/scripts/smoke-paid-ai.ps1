# M4 smoke: paid-unlock posts + AI butler FAQ (run AFTER smoke-mall)
$ErrorActionPreference = 'Stop'
$api = "http://localhost:8888/api/v1"

function PostJson($uri, $obj, $headers) {
    $bytes = [Text.Encoding]::UTF8.GetBytes(($obj | ConvertTo-Json -Compress -Depth 5))
    if ($headers) { return Invoke-RestMethod -Method Post -Uri $uri -Headers $headers -ContentType 'application/json; charset=utf-8' -Body $bytes }
    return Invoke-RestMethod -Method Post -Uri $uri -ContentType 'application/json; charset=utf-8' -Body $bytes
}

$la = PostJson "$api/auth/login" @{email = "a@test.com"; password = "pass1234"} $null
$h1 = @{Authorization = "Bearer $($la.data.token)"}
$lb = PostJson "$api/auth/login" @{email = "b@test.com"; password = "pass1234"} $null
$h2 = @{Authorization = "Bearer $($lb.data.token)"}

# 1. paid post validation: price without content rejected
$bad = PostJson "$api/posts" @{circleId = 2; title = "paid"; content = "free part"; paidPrice = 10} $h1
Write-Output "[1] paid without content: code=$($bad.code)"

# 2. author(a) publishes paid post (price 20)
$pp = PostJson "$api/posts" @{circleId = 2; title = "paid post"; content = "free summary"; paidPrice = 20; paidContent = "SECRET FULL TEXT"} $h1
$ppid = $pp.data.postId
Write-Output "[2] paid post id=$ppid status=$($pp.data.status)"

# 3. gating: guest/buyer detail shows price but NO paid content; author sees full
$gd = (Invoke-RestMethod "$api/posts/$ppid").data
$bd = (Invoke-RestMethod "$api/posts/$ppid" -Headers $h2).data
$ad = (Invoke-RestMethod "$api/posts/$ppid" -Headers $h1).data
Write-Output "[3] guest price=$($gd.paidPrice) unlocked=$($gd.unlocked) content=[$($gd.paidContent)]; buyer unlocked=$($bd.unlocked); author unlocked=$($ad.unlocked) content=[$($ad.paidContent)]"

# 4. b unlocks: balance -20, author +18 (10% fee); repeat unlock idempotent
$bal0 = ((Invoke-RestMethod "$api/youzhu/account" -Headers $h2).data).balance
$abal0 = ((Invoke-RestMethod "$api/youzhu/account" -Headers $h1).data).balance
$u1 = PostJson "$api/posts/$ppid/unlock" @{} $h2
$u2 = PostJson "$api/posts/$ppid/unlock" @{} $h2
$bal1 = ((Invoke-RestMethod "$api/youzhu/account" -Headers $h2).data).balance
$abal1 = ((Invoke-RestMethod "$api/youzhu/account" -Headers $h1).data).balance
Write-Output "[4] unlock=code$($u1.code) content=[$($u1.data.paidContent)]; repeat=code$($u2.code); buyer $bal0->$bal1 author $abal0->$abal1"

# 5. after unlock: buyer detail carries paid content
$bd2 = (Invoke-RestMethod "$api/posts/$ppid" -Headers $h2).data
Write-Output "[5] buyer after unlock: unlocked=$($bd2.unlocked) content=[$($bd2.paidContent)]"

# 6. self unlock rejected; author notified
$su = PostJson "$api/posts/$ppid/unlock" @{} $h1
$n = (Invoke-RestMethod "$api/notifications?type=3" -Headers $h1).data | Select-Object -First 1
Write-Output "[6] self unlock=code$($su.code); author notify=[$($n.content)]"

# 7. ledger reconcile still zero
$diff = (docker compose exec -T mysql sh -c "mysql -uroot -proot123 yiora -N -e 'SELECT COUNT(1) FROM youzhu_account a LEFT JOIN (SELECT user_id, SUM(amount) s FROM youzhu_log GROUP BY user_id) l ON l.user_id=a.user_id WHERE a.balance != COALESCE(l.s,0)' 2>/dev/null" | Out-String).Trim()
Write-Output "[7] reconcile mismatch=$diff (expect 0)"

# 8. AI butler: register c -> welcome conversation appears pinned with isBot
PostJson "$api/auth/email-code" @{email = "c@test.com"; scene = "register"} $null | Out-Null
$code = $null
for ($i = 0; $i -lt 10 -and -not $code; $i++) {
    Start-Sleep -Seconds 1
    $hit = docker compose logs api 2>$null | Select-String "send code (\d{6}) to c@test.com" | Select-Object -Last 1
    if ($hit) { $code = $hit.Matches[0].Groups[1].Value }
}
if (-not $code) { throw "email code for c not captured" }
$rc = PostJson "$api/auth/register" @{email = "c@test.com"; code = $code; password = "pass1234"; nickname = "CarolC"} $null
$h3 = @{Authorization = "Bearer $($rc.data.token)"}
$convs = (Invoke-RestMethod "$api/im/conversations" -Headers $h3).data
Write-Output "[8] new user convs=$($convs.Count) first isBot=$($convs[0].isBot) peer=$($convs[0].peer.nickname) preview=[$($convs[0].lastPreview)]"

# 9. FAQ: keyword hit + fallback; bot exempt from non-mutual daily limit (>3 msgs)
$botUid = $convs[0].peer.userId
PostJson "$api/im/messages" @{targetUid = $botUid; msgType = 1; content = "怎么签到?"} $h3 | Out-Null
PostJson "$api/im/messages" @{targetUid = $botUid; msgType = 1; content = "xyzabc"} $h3 | Out-Null
PostJson "$api/im/messages" @{targetUid = $botUid; msgType = 1; content = "忧珠是什么"} $h3 | Out-Null
$m4 = PostJson "$api/im/messages" @{targetUid = $botUid; msgType = 1; content = "抽奖在哪"} $h3
$hist = (Invoke-RestMethod "$api/im/messages?convId=$($convs[0].convId)&size=20" -Headers $h3).data
Write-Output "[9] 4th msg to bot=code$($m4.code) (no rate limit); history=$($hist.Count) msgs"
$hist | Sort-Object seq | ForEach-Object { $who = if ($_.senderId -eq $botUid) { 'BOT' } else { 'ME ' }; Write-Output "    $who seq$($_.seq): $($_.content.Substring(0, [Math]::Min(40, $_.content.Length)))" }

Write-Output "PAID_AI_SMOKE_DONE"
