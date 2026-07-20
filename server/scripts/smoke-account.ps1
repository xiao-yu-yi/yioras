# Account P0 smoke: reset password + favorites + history + deactivate (run AFTER smoke-content)
# 独立注册 e/d 两个临时账号,避免与其他套件的验证码频控互相干扰
$ErrorActionPreference = 'Stop'
$api = "http://localhost:8888/api/v1"

function PostJson($uri, $obj, $headers) {
    $bytes = [Text.Encoding]::UTF8.GetBytes(($obj | ConvertTo-Json -Compress -Depth 5))
    if ($headers) { return Invoke-RestMethod -Method Post -Uri $uri -Headers $headers -ContentType 'application/json; charset=utf-8' -Body $bytes }
    return Invoke-RestMethod -Method Post -Uri $uri -ContentType 'application/json; charset=utf-8' -Body $bytes
}

function Get-EmailCode($who) {
    $code = $null
    for ($i = 0; $i -lt 10 -and -not $code; $i++) {
        Start-Sleep -Seconds 1
        $hit = docker compose logs api 2>$null | Select-String "send code (\d{6}) to $who@test.com" | Select-Object -Last 1
        if ($hit) { $code = $hit.Matches[0].Groups[1].Value }
    }
    if (-not $code) { throw "email code for $who not captured" }
    return $code
}

# 1. reset password on temp user e: register -> reset-scene code -> reset -> old fails, new works
$ec = PostJson "$api/auth/email-code" @{email = "e@test.com"; scene = "register"} $null
$regCode = Get-EmailCode 'e'
$re = PostJson "$api/auth/register" @{email = "e@test.com"; code = $regCode; password = "pass1234"; nickname = "EveE"} $null
$rc = PostJson "$api/auth/email-code" @{email = "e@test.com"; scene = "reset"} $null
$resetCode = Get-EmailCode 'e'
$rp = PostJson "$api/auth/reset-password" @{email = "e@test.com"; code = $resetCode; password = "newpass99"} $null
$oldLogin = PostJson "$api/auth/login" @{email = "e@test.com"; password = "pass1234"} $null
$newLogin = PostJson "$api/auth/login" @{email = "e@test.com"; password = "newpass99"} $null
Write-Output "[1] resetCodeSend=code$($rc.code) reset=code$($rp.code) oldPwdLogin=code$($oldLogin.code) newPwdLogin=code$($newLogin.code)"

# 2. favorites: b favorites a post then lists it
$la = PostJson "$api/auth/login" @{email = "a@test.com"; password = "pass1234"} $null
$lb = PostJson "$api/auth/login" @{email = "b@test.com"; password = "pass1234"} $null
$h1 = @{Authorization = "Bearer $($la.data.token)"}
$h2 = @{Authorization = "Bearer $($lb.data.token)"}
$post = PostJson "$api/posts" @{circleId = 2; title = "fav target"; content = "favorite me"} $h1
$targetId = $post.data.postId
PostJson "$api/posts/$targetId/favorite" @{} $h2 | Out-Null
$favs = (Invoke-RestMethod "$api/user/favorites" -Headers $h2).data
Write-Output "[2] favorites=$(@($favs).Count) first=$($favs[0].title) favorited=$($favs[0].favorited)"

# 3. history: b views detail -> history contains it -> clear -> empty
(Invoke-RestMethod "$api/posts/$targetId" -Headers $h2) | Out-Null
$hist = (Invoke-RestMethod "$api/user/history" -Headers $h2).data
$histCount = @($hist).Count
Invoke-RestMethod -Method Delete -Uri "$api/user/history" -Headers $h2 | Out-Null
$hist2 = (Invoke-RestMethod "$api/user/history" -Headers $h2).data
Write-Output "[3] history=$histCount afterClear=$(@($hist2).Count) (expect >0 then 0)"

# 4. deactivate temp user d: wrong pwd rejected -> deactivate -> token revoked, login blocked, guest still browses
PostJson "$api/auth/email-code" @{email = "d@test.com"; scene = "register"} $null | Out-Null
$dcode = Get-EmailCode 'd'
$rd = PostJson "$api/auth/register" @{email = "d@test.com"; code = $dcode; password = "pass1234"; nickname = "DoomedD"} $null
$hd = @{Authorization = "Bearer $($rd.data.token)"}
$badpw = PostJson "$api/user/deactivate" @{password = "wrongpass"} $hd
$okDeact = PostJson "$api/user/deactivate" @{password = "pass1234"} $hd
$afterMe = Invoke-RestMethod "$api/user/me" -Headers $hd   # revoked token -> 40100
$afterLogin = PostJson "$api/auth/login" @{email = "d@test.com"; password = "pass1234"} $null
$guestFeed = (Invoke-RestMethod "$api/posts").code
Write-Output "[4] wrongPwd=code$($badpw.code) deactivate=code$($okDeact.code) revokedMe=code$($afterMe.code) loginBlocked=code$($afterLogin.code) guestFeed=code$guestFeed"

Write-Output "ACCOUNT_SMOKE_DONE"
