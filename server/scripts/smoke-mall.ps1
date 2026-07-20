# M4 smoke: decoration mall + wardrobe/wear + pretty-no + lottery + exchange records
# Requires: run AFTER smoke-m3 (b@test.com has some youzhu)
$ErrorActionPreference = 'Stop'
$api = "http://localhost:8888/api/v1"

function PostJson($uri, $obj, $headers) {
    $bytes = [Text.Encoding]::UTF8.GetBytes(($obj | ConvertTo-Json -Compress -Depth 5))
    if ($headers) { return Invoke-RestMethod -Method Post -Uri $uri -Headers $headers -ContentType 'application/json; charset=utf-8' -Body $bytes }
    return Invoke-RestMethod -Method Post -Uri $uri -ContentType 'application/json; charset=utf-8' -Body $bytes
}

$login = PostJson "$api/auth/login" @{email = "b@test.com"; password = "pass1234"} $null
$h2 = @{Authorization = "Bearer $($login.data.token)"}
$uidB = $login.data.userId
$loginA = PostJson "$api/auth/login" @{email = "a@test.com"; password = "pass1234"} $null
$h1 = @{Authorization = "Bearer $($loginA.data.token)"}

# 0. ops grant: simulate admin issuing 500 youzhu to b (log + balance updated together, ledger stays balanced)
$grantSql = @"
INSERT INTO youzhu_account (user_id, balance) VALUES ($uidB,0) ON DUPLICATE KEY UPDATE user_id=user_id;
INSERT INTO youzhu_log (user_id,biz_type,biz_key,amount,balance_after,remark)
SELECT $uidB,3,'ops:seed:$uidB',500,balance+500,'ops grant' FROM youzhu_account WHERE user_id=$uidB;
UPDATE youzhu_account SET balance=balance+500 WHERE user_id=$uidB;
"@
$grantTmp = Join-Path ([IO.Path]::GetTempPath()) "yiora_grant.sql"
Set-Content -Path $grantTmp -Value $grantSql -Encoding ASCII
docker cp $grantTmp yiora-mysql-1:/tmp/grant.sql | Out-Null
docker compose exec -T mysql sh -c "mysql -uroot -proot123 yiora < /tmp/grant.sql 2>/dev/null" | Out-Null
$acct0 = (Invoke-RestMethod "$api/youzhu/account" -Headers $h2).data
Write-Output "[0] ops grant done, balance=$($acct0.balance)"

# 1. mall list (guest & logged-in owned flag)
$mall = (Invoke-RestMethod "$api/mall/decorations" -Headers $h2).data
$mall | ForEach-Object { Write-Output "[1] deco$($_.id) kind=$($_.kind) price=$($_.price) days=$($_.durationDays) owned=$($_.owned)" }

# 2. exchange star frame (id=1, permanent) + duplicate exchange rejected
$e1 = PostJson "$api/mall/decorations/1/exchange" @{} $h2
$e1b = PostJson "$api/mall/decorations/1/exchange" @{} $h2
Write-Output "[2] exchange=code$($e1.code) duplicate=code$($e1b.code)"

# 3. wear frame -> feed author.avatarFrame takes effect site-wide
PostJson "$api/mall/decorations/1/wear" @{} $h2 | Out-Null
$feed = (Invoke-RestMethod "$api/posts").data
$bPost = $feed | Where-Object { $_.author.userId -eq $uidB } | Select-Object -First 1
Write-Output "[3] wear ok; feed author frame=[$($bPost.author.avatarFrame)]"

# 4. exchange sakura frame (id=2, 7-day) then wear -> star frame auto taken off (same kind exclusive)
PostJson "$api/mall/decorations/2/exchange" @{} $h2 | Out-Null
PostJson "$api/mall/decorations/2/wear" @{} $h2 | Out-Null
$mine = (Invoke-RestMethod "$api/mall/decorations/mine" -Headers $h2).data
$mine | ForEach-Object { Write-Output "[4] mine deco$($_.decorationId) worn=$($_.worn) expireAt=$($_.expireAt)" }

# 5. take off
PostJson "$api/mall/decorations/2/take-off" @{} $h2 | Out-Null
$mine2 = (Invoke-RestMethod "$api/mall/decorations/mine" -Headers $h2).data
Write-Output "[5] after take-off worn count=$(($mine2 | Where-Object { $_.worn }).Count) (expect 0)"

# 6. pretty-no: exchange cheapest (N12321, 50) -> displayNo replaced; re-exchange sold out
$skus = (Invoke-RestMethod "$api/mall/pretty-no").data
$sku = $skus | Where-Object { $_.no -eq 'N12321' }
$n1 = PostJson "$api/mall/pretty-no/$($sku.id)/exchange" @{} $h2
$me = (Invoke-RestMethod "$api/user/me" -Headers $h2).data
$n2 = PostJson "$api/mall/pretty-no/$($sku.id)/exchange" @{} $h1
Write-Output "[6] exchangeNo=code$($n1.code) no=$($n1.data.no) me.displayNo=$($me.displayNo); soldOutRetry=code$($n2.code)"

# 7. lottery: pools with weights; draw x3; balance & records consistent
$pools = (Invoke-RestMethod "$api/lottery/pools").data
Write-Output ("[7] pools cost=$($pools.cost): " + (($pools.prizes | ForEach-Object { "$($_.name)/w$($_.weight)" }) -join ' '))
1..3 | ForEach-Object {
    $d = PostJson "$api/lottery/draw" @{} $h2
    Write-Output "[7] draw$_ code=$($d.code) prize=$($d.data.prize.name) balance=$($d.data.balance)"
}

# 8. poor account (a) draw -> insufficient
$pd = PostJson "$api/lottery/draw" @{} $h1
Write-Output "[8] poor draw=code$($pd.code) msg=$($pd.msg)"

# 9. exchange records + ledger reconcile
$recs = (Invoke-RestMethod "$api/exchange/records" -Headers $h2).data
Write-Output "[9] exchange records=$($recs.Count)"
$recs | Select-Object -First 5 | ForEach-Object { Write-Output "    rec kind=$($_.kind) name=$($_.name) cost=$($_.cost)" }
$diff = (docker compose exec -T mysql sh -c "mysql -uroot -proot123 yiora -N -e 'SELECT COUNT(1) FROM youzhu_account a LEFT JOIN (SELECT user_id, SUM(amount) s FROM youzhu_log GROUP BY user_id) l ON l.user_id=a.user_id WHERE a.balance != COALESCE(l.s,0)' 2>/dev/null" | Out-String).Trim()
Write-Output "[10] reconcile mismatch rows=$diff (expect 0)"

Write-Output "MALL_SMOKE_DONE"
