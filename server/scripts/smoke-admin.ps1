# Admin smoke: login + audit workbench (post/comment/software) + cert decide + appoint + oplogs
# Run AFTER smoke-p2 (has pending post from re-audit + b as circle owner)
$ErrorActionPreference = 'Stop'
$api = "http://localhost:8888/api/v1"
$adm = "http://localhost:8888/admin/v1"

function PostJson($uri, $obj, $headers) {
    $bytes = [Text.Encoding]::UTF8.GetBytes(($obj | ConvertTo-Json -Compress -Depth 5))
    if ($headers) { return Invoke-RestMethod -Method Post -Uri $uri -Headers $headers -ContentType 'application/json; charset=utf-8' -Body $bytes }
    return Invoke-RestMethod -Method Post -Uri $uri -ContentType 'application/json; charset=utf-8' -Body $bytes
}

# Get-Totp: RFC 6238 (SHA1/30s/6 digits) in pure PowerShell, mirrors server pkg/totp
function Get-Totp($secretB32) {
    $alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
    $bits = ""
    foreach ($c in $secretB32.ToUpper().ToCharArray()) { $bits += [Convert]::ToString($alphabet.IndexOf($c), 2).PadLeft(5, '0') }
    $keyLen = [Math]::Floor($bits.Length / 8)
    $key = New-Object byte[] $keyLen
    for ($i = 0; $i -lt $keyLen; $i++) { $key[$i] = [Convert]::ToByte($bits.Substring($i * 8, 8), 2) }
    $step = [int64][Math]::Floor([DateTimeOffset]::UtcNow.ToUnixTimeSeconds() / 30)
    $msg = [BitConverter]::GetBytes($step)
    [Array]::Reverse($msg)
    $hmac = New-Object System.Security.Cryptography.HMACSHA1 (, $key)
    $hash = $hmac.ComputeHash($msg)
    $off = $hash[$hash.Length - 1] -band 0x0f
    $bin = (($hash[$off] -band 0x7f) * 16777216) + ($hash[$off + 1] * 65536) + ($hash[$off + 2] * 256) + $hash[$off + 3]
    return ($bin % 1000000).ToString("D6")
}

$la = PostJson "$api/auth/login" @{email = "a@test.com"; password = "pass1234"} $null
$lb = PostJson "$api/auth/login" @{email = "b@test.com"; password = "pass1234"} $null
$h1 = @{Authorization = "Bearer $($la.data.token)"}
$h2 = @{Authorization = "Bearer $($lb.data.token)"}
$uidB = $lb.data.userId

# SolveCaptcha: fetch captcha then read the answer straight from redis (full real flow, no backdoor)
function SolveCaptcha() {
    $c = (Invoke-RestMethod "$adm/captcha").data
    $code = (docker exec yiora-redis-1 redis-cli GET "admin:captcha:$($c.captchaId)").Trim()
    return @{captchaId = $c.captchaId; captchaCode = $code}
}
function AdminLogin($username, $password) {
    $cap = SolveCaptcha
    return PostJson "$adm/login" @{username = $username; password = $password; captchaId = $cap.captchaId; captchaCode = $cap.captchaCode} $null
}

# 1. admin login: no/bad captcha rejected, bad pwd rejected
$noCaptcha = PostJson "$adm/login" @{username = "admin"; password = "admin123"} $null
$badLogin = AdminLogin "admin" "wrong"
$login = AdminLogin "admin" "admin123"
$ha = @{Authorization = "Bearer $($login.data.token)"}
$userTokenTry = Invoke-RestMethod "$adm/audits" -Headers $h1
Write-Output ("[1] noCaptcha=code$($noCaptcha.code) (expect 40000) badLogin=code$($badLogin.code) login=code$($login.code) perms=" + ($login.data.perms -join ',') + " userTokenOnAdmin=code$($userTokenTry.code) (expect 40100)")

# 1.5 password change + admin account management (create/assign role/disable/reset)
$weak = PostJson "$adm/password" @{oldPassword = "admin123"; newPassword = "short"} $ha
$chg = PostJson "$adm/password" @{oldPassword = "admin123"; newPassword = "Admin#2026pwd"} $ha
$reLogin = AdminLogin "admin" "Admin#2026pwd"
$ha = @{Authorization = "Bearer $($reLogin.data.token)"}
$roles = (Invoke-RestMethod "$adm/roles" -Headers $ha).data
$auditorRole = @($roles | Where-Object { $_.perms -contains 'audit' -and $_.perms -notcontains '*' })[0]
$mk = PostJson "$adm/admins" @{username = "auditor1"; password = "Auditor1pwd"; roleId = $auditorRole.id} $ha
$dupUser = PostJson "$adm/admins" @{username = "auditor1"; password = "Auditor1pwd"; roleId = $auditorRole.id} $ha
$la2 = AdminLogin "auditor1" "Auditor1pwd"
$ha2 = @{Authorization = "Bearer $($la2.data.token)"}
$permDeny = Invoke-RestMethod "$adm/admins" -Headers $ha2
$selfOp = PostJson "$adm/admins/1" @{status = 0} $ha  # initial admin (id=1) operating itself
$disable = PostJson "$adm/admins/$($mk.data.id)" @{status = 0} $ha
$disabledLogin = AdminLogin "auditor1" "Auditor1pwd"
PostJson "$adm/admins/$($mk.data.id)" @{status = 1; newPassword = "Auditor2pwd"} $ha | Out-Null
$resetLogin = AdminLogin "auditor1" "Auditor2pwd"
Write-Output "[1.5] weakPwd=code$($weak.code) (expect 40000) change=code$($chg.code) reLogin=code$($reLogin.code); roles=$(@($roles).Count) create=code$($mk.code) dup=code$($dupUser.code) (expect 42900) auditorLogin=code$($la2.code) permDeny=code$($permDeny.code) (expect 40300) selfOp=code$($selfOp.code) (expect 40300) disable=code$($disable.code) disabledLogin=code$($disabledLogin.code) (expect 40300) resetLogin=code$($resetLogin.code)"

# 1.8 login fail lockout: 5 wrong passwords (with valid captchas) lock the account for 15 min
for ($i = 0; $i -lt 5; $i++) { AdminLogin "auditor1" "definitely-wrong" | Out-Null }
$lockedRight = AdminLogin "auditor1" "Auditor2pwd"   # correct password but locked
$failTtl = (docker exec yiora-redis-1 redis-cli TTL "admin:login:fail:auditor1").Trim()
docker exec yiora-redis-1 redis-cli DEL "admin:login:fail:auditor1" | Out-Null
$unlocked = AdminLogin "auditor1" "Auditor2pwd"
Write-Output "[1.8] lockedEvenRightPwd=code$($lockedRight.code) (expect 40300) ttl=$failTtl(<=900) afterUnlock=code$($unlocked.code)"

# 1.95 TOTP two-factor: setup -> confirm -> re-login needs ticket+code -> replay blocked -> recovery code -> disable
$setup = (Invoke-RestMethod -Method Post -Uri "$adm/totp/setup" -Headers $ha).data
$cfm = PostJson "$adm/totp/confirm" @{code = (Get-Totp $setup.secret)} $ha
$l2 = AdminLogin "admin" "Admin#2026pwd"
$code2 = Get-Totp $setup.secret
$step2 = PostJson "$adm/login/totp" @{ticket = $l2.data.ticket; code = $code2} $null
$l3 = AdminLogin "admin" "Admin#2026pwd"
$replay = PostJson "$adm/login/totp" @{ticket = $l3.data.ticket; code = $code2} $null
$rec = PostJson "$adm/login/totp" @{ticket = $l3.data.ticket; code = $setup.recoveryCodes[0]} $null
$l4 = AdminLogin "admin" "Admin#2026pwd"
$recDup = PostJson "$adm/login/totp" @{ticket = $l4.data.ticket; code = $setup.recoveryCodes[0]} $null
$ha = @{Authorization = "Bearer $($rec.data.token)"}
$st = (Invoke-RestMethod "$adm/totp/status" -Headers $ha).data
$dis = PostJson "$adm/totp/disable" @{code = $setup.recoveryCodes[1]} $ha
$l5 = AdminLogin "admin" "Admin#2026pwd"
$ha = @{Authorization = "Bearer $($l5.data.token)"}
Write-Output "[1.95] confirm=code$($cfm.code) relogin ticket=$([bool]$l2.data.totpRequired) code=code$($step2.code) replaySameCode=code$($replay.code) (expect 41002) recovery=code$($rec.code) recoveryReuse=code$($recDup.code) (expect 41002) left=$($st.recoveryCodesLeft) (expect 9) disable=code$($dis.code) afterDisable direct=$([bool]$l5.data.token)"

# helper: upload a small real image and return its fileUrl (whitelist-compliant)
function New-UploadedImage($presignUri, $headers, $kind) {
    $p = PostJson $presignUri @{kind = $kind; fileName = "i.png"; size = 128} $headers
    $t = Join-Path ([IO.Path]::GetTempPath()) ("smoke_a_" + [Guid]::NewGuid().ToString("N") + ".png")
    [IO.File]::WriteAllBytes($t, (New-Object byte[] 128))
    Invoke-WebRequest -Method Put -Uri $p.data.uploadUrl -InFile $t -UseBasicParsing | Out-Null
    Remove-Item $t -ErrorAction SilentlyContinue
    return $p.data.fileUrl
}

# 2. seed pending items: post with REVIEW word by a; comment with REVIEW word by b; software+version by b
$pp = PostJson "$api/posts" @{circleId = 2; title = "audit me"; content = "hello REVIEWWORD_SAMPLE"} $h1
$target = PostJson "$api/posts" @{circleId = 2; content = "comment target"} $h1
$pc = PostJson "$api/comments" @{postId = $target.data.postId; content = "cmt REVIEWWORD_SAMPLE"} $h2
$cats = (Invoke-RestMethod "$api/software/categories?type=1").data
$simg = New-UploadedImage "$api/upload/presign" $h2 "software"
$ps = PostJson "$api/software" @{name = "AuditSoft"; logo = $simg; intro = "intro"; images = @($simg, $simg, $simg); type = 1; categoryId = $cats[0].id; version = "1.0"; size = "1MB"; downloadUrl = "https://pan/x"} $h2
Write-Output "[2] pendPost=$($pp.data.postId)/s$($pp.data.status) pendCmt=$($pc.data.commentId)/s$($pc.data.status) pendSoft=$($ps.data.softwareId)/s$($ps.data.status)"

# 3. audit queue lists all three
$audits = (Invoke-RestMethod "$adm/audits" -Headers $ha).data
Write-Output ("[3] queue=" + (($audits | ForEach-Object { "a$($_.id)t$($_.bizType)" }) -join ' '))

# 4. approve post -> guest visible + circle count; reject comment -> stays hidden; approve software -> online + latest_version_id
$aPost = @($audits | Where-Object { $_.bizType -eq 1 -and $_.bizId -eq $pp.data.postId })[0]
$aCmt = @($audits | Where-Object { $_.bizType -eq 2 -and $_.bizId -eq $pc.data.commentId })[0]
$aSoft = @($audits | Where-Object { $_.bizType -eq 3 -and $_.bizId -eq $ps.data.softwareId })[0]
if (-not $aPost -or -not $aCmt -or -not $aSoft) { throw "expected audits missing from queue" }
$d1 = PostJson "$adm/audits/$($aPost.id)/decide" @{approve = $true} $ha
$d1b = PostJson "$adm/audits/$($aPost.id)/decide" @{approve = $true} $ha
$d2 = PostJson "$adm/audits/$($aCmt.id)/decide" @{approve = $false; reason = "violation"} $ha
$d3 = PostJson "$adm/audits/$($aSoft.id)/decide" @{approve = $true} $ha
$gp = Invoke-RestMethod "$api/posts/$($pp.data.postId)"
$cl = (Invoke-RestMethod "$api/comments?postId=$($target.data.postId)").data
$sd = (Invoke-RestMethod "$api/software/$($ps.data.softwareId)").data
Write-Output "[4] post=code$($d1.code) redecide=code$($d1b.code) cmtReject=code$($d2.code) soft=code$($d3.code); guestPost=code$($gp.code) hiddenCmt=$(@($cl).Count) softVer=$($sd.version) softStatus=$($sd.status)"

# 5. author notifications for audit results
$n1 = (Invoke-RestMethod "$api/notifications?type=3" -Headers $h1).data | Select-Object -First 1
Write-Output "[5] author notify=[$($n1.content)]"

# 6. cert workbench: b submits -> admin approves -> b profile certs
PostJson "$api/certifications" @{kind = 1; material = "portfolio links"} $h2 | Out-Null
$certs = (Invoke-RestMethod "$adm/certifications" -Headers $ha).data
$cid = ($certs | Where-Object { $_.userId -eq $uidB })[0].id
$dc = PostJson "$adm/certifications/$cid/decide" @{approve = $true} $ha
$profB = (Invoke-RestMethod "$api/users/$uidB").data
Write-Output ("[6] certQueue=$(@($certs).Count) decide=code$($dc.code) bCerts=" + ($profB.certs -join ','))

# 7. appoint: admin makes b member of circle 3 owner -> b can manage circle 3
$ap = PostJson "$adm/circles/3/appoint" @{userId = $uidB; role = 2} $ha
$c3post = PostJson "$api/posts" @{circleId = 3; content = "circle3 post"} $h1
$adminTop = PostJson "$api/circles/3/admin/top" @{postId = $c3post.data.postId; on = $true} $h2
Write-Output "[7] appoint=code$($ap.code) bManageCircle3=code$($adminTop.code)"

# 8. notice broadcast: every active user gets system notification
$beforeN = (Invoke-RestMethod "$api/notifications/unread" -Headers $h1).data.system
PostJson "$adm/notices" @{title = "maintenance tonight"; content = "server upgrade at 2am"} $ha | Out-Null
$afterN = (Invoke-RestMethod "$api/notifications/unread" -Headers $h1).data.system
Write-Output "[8] notice fanout: a.system $beforeN -> $afterN (expect +1)"

# 8.5 user search list: keyword by nickname/email + status filter + paging total
$us1 = (Invoke-RestMethod "$adm/users?keyword=BobB" -Headers $ha).data
$us2 = (Invoke-RestMethod "$adm/users?keyword=b%40test.com" -Headers $ha).data
$usAll = (Invoke-RestMethod "$adm/users?page=1&size=2" -Headers $ha).data
Write-Output "[8.5] userSearch nick=$($us1.total) email=$($us2.total) (expect 1/1) all.total=$($usAll.total) page1=$(@($usAll.list).Count)"

# 9. mute user b globally -> post/comment/im blocked, browse ok, status visible in list -> restore
$mute = PostJson "$adm/users/$uidB/ban" @{action = 2; days = 1} $ha
$mp = PostJson "$api/posts" @{circleId = 2; content = "muted global"} $h2
$mc = PostJson "$api/comments" @{postId = $target.data.postId; content = "muted cmt"} $h2
$browse = (Invoke-RestMethod "$api/posts" -Headers $h2).code
$mutedList = (Invoke-RestMethod "$adm/users?status=2" -Headers $ha).data
PostJson "$adm/users/$uidB/ban" @{action = 0} $ha | Out-Null
$mp2 = PostJson "$api/posts" @{circleId = 2; content = "recovered"} $h2
Write-Output "[9] mute=code$($mute.code) post=code$($mp.code) cmt=code$($mc.code) (expect 40300x2) browse=code$browse statusFilter=$($mutedList.total)(expect 1) restorePost=code$($mp2.code)"

# 10. ban user b -> existing token rejected + login blocked -> restore
PostJson "$adm/users/$uidB/ban" @{action = 3; days = 0} $ha | Out-Null
$bannedMe = Invoke-RestMethod "$api/user/me" -Headers $h2
$bannedLogin = PostJson "$api/auth/login" @{email = "b@test.com"; password = "pass1234"} $null
PostJson "$adm/users/$uidB/ban" @{action = 0} $ha | Out-Null
$restoredLogin = PostJson "$api/auth/login" @{email = "b@test.com"; password = "pass1234"} $null
Write-Output "[10] banned me=code$($bannedMe.code) login=code$($bannedLogin.code) restoredLogin=code$($restoredLogin.code)"

# 11. banner CRUD (image uploaded via admin presign) -> home config reflects online banner
$bimg = New-UploadedImage "$adm/upload/presign" $ha "banner"
$extBanner = PostJson "$adm/banners" @{title = "ext"; image = "https://evil.example.com/b.png"; linkType = 0; status = 1} $ha
$nb = PostJson "$adm/banners" @{title = "welcome"; image = $bimg; linkType = 0; sort = 1; status = 1} $ha
$blist = (Invoke-RestMethod "$adm/banners" -Headers $ha).data
$homeCfg = (Invoke-RestMethod "$api/home/config").data
Invoke-RestMethod -Method Delete -Uri "$adm/banners/$($nb.data.id)" -Headers $ha | Out-Null
$homeCfg2 = (Invoke-RestMethod "$api/home/config").data
Write-Output "[11] extBanner=code$($extBanner.code) (expect 40000) banner id=$($nb.data.id) adminList=$(@($blist).Count) homeBanners=$(@($homeCfg.banners).Count) afterDelete=$(@($homeCfg2.banners).Count)"

# 11.5 content search + one-click takedown/restore with counter rollback
$cs = (Invoke-RestMethod "$adm/contents?type=1&keyword=circle3" -Headers $ha).data
$cid5 = $cs.list[0].id
$countBefore = (Invoke-RestMethod "$api/circles/3" -Headers $h1).data.postCount
$ctd = PostJson "$adm/contents/takedown" @{type = 1; id = $cid5; action = 1; reason = "smoke takedown"} $ha
$gone = (Invoke-RestMethod "$api/posts/$cid5" -Headers $h1).code
$countMid = (Invoke-RestMethod "$api/circles/3" -Headers $h1).data.postCount
$crs = PostJson "$adm/contents/takedown" @{type = 1; id = $cid5; action = 0} $ha
$back = (Invoke-RestMethod "$api/posts/$cid5" -Headers $h1).code
$countAfter = (Invoke-RestMethod "$api/circles/3" -Headers $h1).data.postCount
Write-Output "[11.5] contentSearch=$($cs.total) takedown=code$($ctd.code) guest=code$gone (expect 40400) circleCount $countBefore->$countMid->$countAfter restore=code$($crs.code) visible=code$back"

# 11.8 report workflow: pending list with target brief -> handle/reject with CAS + reporter notified
$rp = (Invoke-RestMethod "$adm/reports" -Headers $ha).data
$rid = $rp.list[0].id
$hr = if ($rp.list[0].reporterId -eq $uidB) { $h2 } else { $h1 }
$beforeRN = (Invoke-RestMethod "$api/notifications/unread" -Headers $hr).data.system
$rh = PostJson "$adm/reports/$rid/handle" @{action = 1} $ha
$rDup = PostJson "$adm/reports/$rid/handle" @{action = 1} $ha
$afterRN = (Invoke-RestMethod "$api/notifications/unread" -Headers $hr).data.system
$rLeft = (Invoke-RestMethod "$adm/reports" -Headers $ha).data.total
Write-Output "[11.8] reports pending=$($rp.total) brief='$($rp.list[0].targetBrief)' handle=code$($rh.code) dup=code$($rDup.code) (expect 42900) reporterNotify $beforeRN->$afterRN (expect +1) left=$rLeft"

# 11.9 sensitive word hot-reload: add block word -> post blocked; switch to mask -> masked; delete -> clean
$nw = PostJson "$adm/words" @{word = "HOTRELOADWORD"; category = 5; level = 1} $ha
$hb = PostJson "$api/posts" @{circleId = 2; content = "say HOTRELOADWORD now"} $h1
PostJson "$adm/words" @{id = $nw.data.id; category = 5; level = 3; status = 1} $ha | Out-Null
$hm = PostJson "$api/posts" @{circleId = 2; content = "say HOTRELOADWORD again"} $h1
$hmDetail = (Invoke-RestMethod "$api/posts/$($hm.data.postId)" -Headers $h1).data
Invoke-RestMethod -Method Delete -Uri "$adm/words/$($nw.data.id)" -Headers $ha | Out-Null
$hc = PostJson "$api/posts" @{circleId = 2; content = "say HOTRELOADWORD clean"} $h1
$hcDetail = (Invoke-RestMethod "$api/posts/$($hc.data.postId)" -Headers $h1).data
$masked = $hmDetail.content.Contains('*') -and -not $hmDetail.content.Contains('HOTRELOADWORD')
$clean = $hcDetail.content.Contains('HOTRELOADWORD')
Write-Output "[11.9] word add=code$($nw.code) blocked=code$($hb.code) (expect 42200) masked=$masked (expect True) afterDelete clean=$clean (expect True)"

# 11.95 faq crud: new rule answers instantly via bot conversation
$nf = PostJson "$adm/faqs" @{keywords = "SMOKEFAQKEY"; reply = "SMOKE FAQ REPLY"; priority = 1} $ha
PostJson "$api/im/messages" @{targetUid = 999999; msgType = 1; content = "ask SMOKEFAQKEY here"} $h1 | Out-Null
Start-Sleep -Milliseconds 400
$bconvs = (Invoke-RestMethod "$api/im/conversations" -Headers $h1).data
$bconv = @($bconvs | Where-Object { $_.isBot })[0]
$bhist = (Invoke-RestMethod "$api/im/messages?convId=$($bconv.convId)&size=3" -Headers $h1).data
$blast = ($bhist | Sort-Object seq | Select-Object -Last 1)
Invoke-RestMethod -Method Delete -Uri "$adm/faqs/$($nf.data.id)" -Headers $ha | Out-Null
Write-Output "[11.95] faq create=code$($nf.code) botReply=[$($blast.content)] (expect SMOKE FAQ REPLY)"

# 11.96 bot prompt ops + reply-source stats: bot_prompt editable by admin, hidden from user side; faq counter grew
$bp = PostJson "$adm/agreements/bot_prompt" @{title = "BotPrompt"; content = "You are Yo, a test prompt."} $ha
$bpRead = Invoke-RestMethod "$adm/agreements/bot_prompt" -Headers $ha
$bpUser = Invoke-RestMethod "$api/agreements/bot_prompt"
$bstats = (Invoke-RestMethod "$adm/bot/stats?days=7" -Headers $ha).data
$faqSum = ($bstats.days | Measure-Object -Property faq -Sum).Sum
Write-Output "[11.96] promptSave=code$($bp.code) adminRead=code$($bpRead.code) userSideHidden=code$($bpUser.code) (expect 40400); statFaq=$faqSum (>=1)"

# 11.97 mall/task ops config: create deco (preview via admin presign) -> visible in shop -> offline -> gone; prize + task validation
$dimg = New-UploadedImage "$adm/upload/presign" $ha "deco"
$ndc = PostJson "$adm/mall/decorations" @{kind = 1; name = "SmokeFrame"; preview = $dimg; price = 5; durationDays = 7} $ha
$shopSeen = @(((Invoke-RestMethod "$api/mall/decorations?kind=1" -Headers $h1).data) | Where-Object { $_.name -eq 'SmokeFrame' }).Count
PostJson "$adm/mall/decorations" @{id = $ndc.data.id; kind = 1; name = "SmokeFrame"; preview = $dimg; price = 5; durationDays = 7; status = 0} $ha | Out-Null
$shopGone = @(((Invoke-RestMethod "$api/mall/decorations?kind=1" -Headers $h1).data) | Where-Object { $_.name -eq 'SmokeFrame' }).Count
$npz = PostJson "$adm/mall/prizes" @{name = "SmokePrize"; kind = 1; amount = 3; weight = 5; stock = 2} $ha
$badPz = PostJson "$adm/mall/prizes" @{name = "BadRef"; kind = 2; refId = 99999; weight = 5} $ha
$poolSeen = @(((Invoke-RestMethod "$api/lottery/pools" -Headers $h1).data.prizes) | Where-Object { $_.name -eq 'SmokePrize' }).Count
$ntk = PostJson "$adm/mall/tasks" @{name = "SmokeTask"; type = 1; action = "like"; targetCount = 2; rewardYouzhu = 2} $ha
$taskSeen = @(((Invoke-RestMethod "$api/tasks" -Headers $h1).data.tasks) | Where-Object { $_.name -eq 'SmokeTask' }).Count
$badTk = PostJson "$adm/mall/tasks" @{name = "NoReward"; type = 1; action = "like"; targetCount = 1} $ha
Write-Output "[11.97] deco add=code$($ndc.code) shop=$shopSeen->$shopGone (expect 1->0); prize=code$($npz.code) badRef=code$($badPz.code) (expect 40000) pool=$poolSeen (expect 1); task=code$($ntk.code) visible=$taskSeen (expect 1) noReward=code$($badTk.code) (expect 40000)"

# 11.98 dashboard trend + software category management
$tr = (Invoke-RestMethod "$adm/dashboard/trend?days=30" -Headers $ha).data
$ncat = PostJson "$adm/software/categories" @{type = 1; name = "SmokeCat"; sort = 9} $ha
$catSeen = @(((Invoke-RestMethod "$api/software/categories?type=1").data) | Where-Object { $_.name -eq 'SmokeCat' }).Count
$dupCat = PostJson "$adm/software/categories" @{type = 1; name = "SmokeCat"} $ha
PostJson "$adm/software/categories" @{id = $ncat.data.id; type = 1; name = "SmokeCat"; sort = 9; status = 0} $ha | Out-Null
$catGone = @(((Invoke-RestMethod "$api/software/categories?type=1").data) | Where-Object { $_.name -eq 'SmokeCat' }).Count
Write-Output "[11.98] trend days=$(@($tr.dates).Count) todayUsers=$($tr.users[-1]) (expect 5) todayPosts=$($tr.posts[-1]) (>0); category add=code$($ncat.code) seen=$catSeen->$catGone (expect 1->0) dup=code$($dupCat.code) (expect 42900)"

# 11.99 presigned upload: sign -> real PUT to MinIO -> fetch back and compare; invalid ext/size rejected
$tmp = Join-Path ([IO.Path]::GetTempPath()) "yiora_upload_test.png"
$payload = New-Object byte[] 2048
(New-Object Random).NextBytes($payload)
[IO.File]::WriteAllBytes($tmp, $payload)
$pre = PostJson "$api/upload/presign" @{kind = "post"; fileName = "shot.png"; size = 2048} $h1
Invoke-WebRequest -Method Put -Uri $pre.data.uploadUrl -InFile $tmp -UseBasicParsing | Out-Null
$back = Invoke-WebRequest -Uri $pre.data.fileUrl -UseBasicParsing
$same = ($back.Content.Length -eq 2048)
$badExt = PostJson "$api/upload/presign" @{kind = "post"; fileName = "evil.exe"; size = 100} $h1
$badSize = PostJson "$api/upload/presign" @{kind = "avatar"; fileName = "big.png"; size = 999999999} $h1
$extAvatar = Invoke-RestMethod -Method Put -Uri "$api/user/me" -Headers $h1 -ContentType 'application/json' -Body '{"avatar":"https://evil.example.com/a.png"}'
$okAvatar = Invoke-RestMethod -Method Put -Uri "$api/user/me" -Headers $h1 -ContentType 'application/json' -Body (@{avatar = $pre.data.fileUrl} | ConvertTo-Json -Compress)
Write-Output "[11.99] presign=code$($pre.code) putAndFetch same2KB=$same (expect True) badExt=code$($badExt.code) badSize=code$($badSize.code) (expect 40000x2) extAvatar=code$($extAvatar.code) (expect 40000) okAvatar=code$($okAvatar.code)"
Remove-Item $tmp -ErrorAction SilentlyContinue

# 12.1 batch1 ops loop: circle CRUD via admin, post feature toggle, topic ban
$cicon = New-UploadedImage "$adm/upload/presign" $ha "circle"
$nc1 = PostJson "$adm/circles" @{name = "OpsCircle"; icon = $cicon; intro = "made by admin"} $ha
$discover = (Invoke-RestMethod "$api/circles").data
$cSeen = @($discover | Where-Object { $_.name -eq 'OpsCircle' }).Count
PostJson "$adm/circles" @{id = $nc1.data.id; name = "OpsCircle"; icon = $cicon; status = 2} $ha | Out-Null
$discover2 = (Invoke-RestMethod "$api/circles").data
$cGone = @($discover2 | Where-Object { $_.name -eq 'OpsCircle' }).Count
$featured = PostJson "$adm/posts/$($target.data.postId)/ops" @{isTop = 1} $ha
$homeTop = (Invoke-RestMethod "$api/home/config").data
$topSeen = @($homeTop.topPosts | Where-Object { $_.postId -eq $target.data.postId }).Count
PostJson "$adm/posts/$($target.data.postId)/ops" @{isTop = 0} $ha | Out-Null
$tps = (Invoke-RestMethod "$adm/topics" -Headers $ha).data
Write-Output "[12.1] circle add=code$($nc1.code) seen=$cSeen->$cGone (expect 1->0); postTop=code$($featured.code) homeTop=$topSeen (expect 1); topics=$($tps.total)"

# 12.2 batch2 mall ops: youzhu grant + admin ledger, pretty-no sku CRUD
$grant = PostJson "$adm/youzhu/grant" @{userId = $uidB; amount = 300; reason = "smoke bonus"} $ha
$ylogs = (Invoke-RestMethod "$adm/youzhu/logs?userId=$uidB&bizType=3" -Headers $ha).data
$np2 = PostJson "$adm/mall/prettynos" @{no = "N10001"; rarity = 1; price = 20} $ha
$dupNo = PostJson "$adm/mall/prettynos" @{no = "N10001"; rarity = 1; price = 20} $ha
$userNos = (Invoke-RestMethod "$api/mall/pretty-no" -Headers $h1).data
$noSeen = @($userNos | Where-Object { $_.no -eq 'N10001' }).Count
PostJson "$adm/mall/prettynos" @{id = $np2.data.id; no = "N10001"; rarity = 1; price = 20; status = 0} $ha | Out-Null
$userNos2 = (Invoke-RestMethod "$api/mall/pretty-no" -Headers $h1).data
$noGone = @($userNos2 | Where-Object { $_.no -eq 'N10001' }).Count
Write-Output "[12.2] grant=code$($grant.code) opsLedger=$($ylogs.total) (>=1); prettyNo add=code$($np2.code) dup=code$($dupNo.code) (expect 42900) shop=$noSeen->$noGone (expect 1->0)"

# 12.3 batch3 dual token: refresh rotation, replay reject, device kick
$reg3 = PostJson "$api/auth/login" @{email = "a@test.com"; password = "pass1234"; deviceName = "PhoneA"} $null
$ref3 = PostJson "$api/auth/refresh" @{refreshToken = $reg3.data.refreshToken; deviceId = $reg3.data.deviceId} $null
$replay3 = PostJson "$api/auth/refresh" @{refreshToken = $reg3.data.refreshToken; deviceId = $reg3.data.deviceId} $null
$hA3 = @{Authorization = "Bearer $($ref3.data.token)"}
$devs3 = (Invoke-RestMethod "$api/user/devices" -Headers $hA3).data
$lg4 = PostJson "$api/auth/login" @{email = "a@test.com"; password = "pass1234"; deviceName = "PadB"} $null
Invoke-RestMethod -Method Delete -Uri "$api/user/devices/$($lg4.data.deviceId)" -Headers $hA3 | Out-Null
$kicked3 = Invoke-RestMethod "$api/user/me" -Headers @{Authorization = "Bearer $($lg4.data.token)"}
Write-Output "[12.3] refresh=code$($ref3.code) rotated=$($ref3.data.refreshToken -ne $reg3.data.refreshToken) replay=code$($replay3.code) (expect 40100) devices=$(@($devs3).Count) kickedAccess=code$($kicked3.code) (expect 40100)"

# 12.35 P-level wrap: teen mode blocks spending, share code round trip, pretty-no delete
Invoke-RestMethod -Method Put -Uri "$api/user/settings" -Headers $h2 -ContentType 'application/json' -Body '{"teenMode":true}' | Out-Null
$teenSet = (Invoke-RestMethod "$api/user/settings" -Headers $h2).data
$teenDraw = PostJson "$api/lottery/draw" @{} $h2
Invoke-RestMethod -Method Put -Uri "$api/user/settings" -Headers $h2 -ContentType 'application/json' -Body '{"teenMode":false}' | Out-Null
$share = PostJson "$api/posts/$($target.data.postId)/share" @{} $h1
$share2 = PostJson "$api/posts/$($target.data.postId)/share" @{} $h1
$resolved = (Invoke-RestMethod "$api/share/$($share.data.code)").data
$badCode = Invoke-RestMethod "$api/share/YRNOTEXIST1"
$delOk = Invoke-RestMethod -Method Delete -Uri "$adm/mall/prettynos/$($np2.data.id)" -Headers $ha
$soldDel = Invoke-RestMethod -Method Delete -Uri "$adm/mall/prettynos/999" -Headers $ha
Write-Output "[12.35] teenOn=$($teenSet.teenMode) draw=code$($teenDraw.code) (expect 40300); shareCode=$($share.data.code) reuse=$($share.data.code -eq $share2.data.code) resolvePost=$($resolved.postId) (expect $($target.data.postId)) badCode=code$($badCode.code) (expect 40400); prettyDel=code$($delOk.code) missingDel=code$($soldDel.code) (expect 40300)"

# 12.36 imgscan (mock driver): review image -> human audit queue; block image -> auto reject + author system notice
$imgRev = PostJson "$api/posts" @{circleId = 2; content = "imgscan review case"; images = @(@{url = "http://localhost:9000/yiora/smoke/mock-review.png"})} $h1
$imgBlk = PostJson "$api/posts" @{circleId = 2; content = "imgscan block case"; images = @(@{url = "http://localhost:9000/yiora/smoke/mock-block.png"})} $h1
Start-Sleep -Seconds 2
$aq2 = (Invoke-RestMethod "$adm/audits" -Headers $ha).data
$revQueued = @($aq2 | Where-Object { $_.bizType -eq 1 -and $_.bizId -eq $imgRev.data.postId }).Count
$revVisible = (Invoke-RestMethod "$api/posts/$($imgRev.data.postId)").code
$blkGone = (Invoke-RestMethod "$api/posts/$($imgBlk.data.postId)").code
$blkNotice = @((Invoke-RestMethod "$api/notifications?type=3" -Headers $h1).data | Where-Object { $_.targetId -eq $imgBlk.data.postId }).Count
Write-Output "[12.36] reviewImg posted=$($imgRev.data.status) queued=$revQueued (expect 1) stillVisible=code$revVisible (expect 0); blockImg gone=code$blkGone (expect 40400) authorNotified=$blkNotice (expect 1)"

# 12.37 offline push (mock channel): B registers token, A DMs offline B twice -> exactly one deduped mock push in redis
PostJson "$api/users/$uidB/follow" @{} $h1 | Out-Null # ensure mutual follow so DM daily cap does not interfere
Invoke-RestMethod -Method Post -Uri "$api/user/push-token" -Headers $h2 -ContentType 'application/json' -Body (@{deviceId = $lb.data.deviceId; platform = "android"; channel = "mock"; token = "smoketok-b"} | ConvertTo-Json -Compress) | Out-Null
PostJson "$api/im/messages" @{targetUid = $uidB; msgType = 1; content = "offline ping 1"} $h1 | Out-Null
PostJson "$api/im/messages" @{targetUid = $uidB; msgType = 1; content = "offline ping 2"} $h1 | Out-Null
$pushCnt = (docker compose exec -T redis redis-cli GET mockpush:count:smoketok-b | Out-String).Trim()
$pushLast = (docker compose exec -T redis redis-cli GET mockpush:last:smoketok-b | Out-String).Trim()
$pushHasLink = $pushLast.Contains('yiora://im/conversation/')
Write-Output "[12.37] offlinePush count=$pushCnt (expect 1, 60s dedup) deeplink=$pushHasLink (expect True)"

# 12.38 notification offline push: B posts, A likes+comments while B offline -> one merged interaction push (5min dedup)
docker compose exec -T redis redis-cli DEL push:ntf:i:$uidB | Out-Null # earlier suites may have consumed the merge window
$bp2 = PostJson "$api/posts" @{circleId = 2; content = "notify push target"} $h2
PostJson "$api/posts/$($bp2.data.postId)/like" @{} $h1 | Out-Null
PostJson "$api/comments" @{postId = $bp2.data.postId; content = "notify push comment"} $h1 | Out-Null
Start-Sleep -Milliseconds 500
$pushCnt2 = (docker compose exec -T redis redis-cli GET mockpush:count:smoketok-b | Out-String).Trim()
$pushLast2 = (docker compose exec -T redis redis-cli GET mockpush:last:smoketok-b | Out-String).Trim()
$ntfLink = $pushLast2.Contains('yiora://notifications/')
Write-Output "[12.38] notifyPush count=$pushCnt2 (expect 2 = DM push + one merged interaction) deeplink=$ntfLink (expect True)"

# 12.39 push preference switches: B turns interaction push off -> like triggers nothing even with a fresh window
Invoke-RestMethod -Method Put -Uri "$api/user/settings" -Headers $h2 -ContentType 'application/json' -Body '{"pushInteract":false}' | Out-Null
$setRead = (Invoke-RestMethod "$api/user/settings" -Headers $h2).data
docker compose exec -T redis redis-cli DEL push:ntf:i:$uidB | Out-Null
$bp3 = PostJson "$api/posts" @{circleId = 2; content = "push pref target"} $h2
PostJson "$api/posts/$($bp3.data.postId)/like" @{} $h1 | Out-Null
Start-Sleep -Milliseconds 500
$pushCnt3 = (docker compose exec -T redis redis-cli GET mockpush:count:smoketok-b | Out-String).Trim()
Invoke-RestMethod -Method Put -Uri "$api/user/settings" -Headers $h2 -ContentType 'application/json' -Body '{"pushInteract":true}' | Out-Null
$setBack = (Invoke-RestMethod "$api/user/settings" -Headers $h2).data
Write-Output "[12.39] prefOff read=$($setRead.pushInteract) (expect False) dmStillOn=$($setRead.pushDm) (expect True); likeWhileOff count=$pushCnt3 (expect 2, unchanged); restored=$($setBack.pushInteract) (expect True)"

# 12.40 push channel dashboard: mock channel counted the sends made in 12.37/12.38
$pstats = (Invoke-RestMethod "$adm/push/stats?days=7" -Headers $ha).data
$mockCh = @($pstats.channels | Where-Object { $_.channel -eq 'mock' })[0]
Write-Output "[12.40] pushStats channels=$($pstats.channels.Count) mockOk=$($mockCh.ok) (expect >=2) mockFail=$($mockCh.fail) (expect 0)"

# 12.41 level rule table: read 11 seeded rows, bad save rejected, valid save applied then restored
$lv = (Invoke-RestMethod "$adm/levels" -Headers $ha).data
$lvBadRules = @($lv | ForEach-Object { @{level = $_.level; needExp = $_.needExp} }); $lvBadRules[2].needExp = 1
$lvBad = PostJson "$adm/levels" @{rules = $lvBadRules} $ha
$lvNewRules = @($lv | ForEach-Object { @{level = $_.level; needExp = $_.needExp} }) + , @{level = $lv.Count; needExp = ($lv[-1].needExp + 1000)}
$lvSave = PostJson "$adm/levels" @{rules = $lvNewRules} $ha
$lvAfter = (Invoke-RestMethod "$adm/levels" -Headers $ha).data
PostJson "$adm/levels" @{rules = @($lv | ForEach-Object { @{level = $_.level; needExp = $_.needExp} })} $ha | Out-Null
Write-Output "[12.41] levels=$($lv.Count) (expect 11) badSave=code$($lvBad.code) (expect 40000) addLevel=code$($lvSave.code) after=$($lvAfter.Count) (expect 12)"

# 12.42 software library manage: search all-status, takedown hides from public list, restore brings it back
$swList = (Invoke-RestMethod "$adm/software?kw=Toolbox&status=-1" -Headers $ha).data
$swId = $swList.list[0].id
$swVers = (Invoke-RestMethod "$adm/software/$swId/versions" -Headers $ha).data
$swDown = PostJson "$adm/software/$swId/ops" @{action = 1; reason = "smoke takedown"} $ha
$pubGone = @(((Invoke-RestMethod "$api/software?type=1").data) | Where-Object { $_.id -eq $swId }).Count
$swBadDown = PostJson "$adm/software/$swId/ops" @{action = 1} $ha
$swUp = PostJson "$adm/software/$swId/ops" @{action = 0} $ha
$pubBack = @(((Invoke-RestMethod "$api/software?type=1").data) | Where-Object { $_.id -eq $swId }).Count
Write-Output "[12.42] swSearch total=$($swList.total) (>=1) versions=$($swVers.Count) (>=2); takedown=code$($swDown.code) pubGone=$pubGone (expect 0) noReason=code$($swBadDown.code) (expect 40000); restore=code$($swUp.code) pubBack=$pubBack (expect 1)"

# 12.43 admin device management: list user devices, force-kick the exact device behind $h2 -> its token dies instantly
$devs = (Invoke-RestMethod "$adm/users/$uidB/devices" -Headers $ha).data
$kick = PostJson "$adm/users/$uidB/devices/kick" @{deviceId = $lb.data.deviceId} $ha
$deadMe = Invoke-RestMethod "$api/user/me" -Headers $h2
Write-Output "[12.43] devices=$(@($devs).Count) (>=1) kick=code$($kick.code) kickedToken=code$($deadMe.code) (expect 40100)"

# 12.44 audit content preview + contents first-image: reviewer can see original text/images before deciding
$aq3 = (Invoke-RestMethod "$adm/audits" -Headers $ha).data
$pvOk = 0; $pvImgs = 0
if (@($aq3).Count -gt 0) {
    $pvResp = Invoke-RestMethod "$adm/audits/$($aq3[0].id)/preview" -Headers $ha
    $pvOk = $pvResp.code
    $pvImgs = @($pvResp.data.images).Count
}
$csImg = (Invoke-RestMethod "$adm/contents?type=1&keyword=imgscan" -Headers $ha).data
$firstImg = @($csImg.list | Where-Object { $_.firstImage -ne '' }).Count
Write-Output "[12.44] preview=code$pvOk (expect 0) previewImgs=$pvImgs; contentsWithFirstImage=$firstImg (>=1)"

# 12.4 batch4 compliance: agreement read/edit, user level/title adjust
$agr = (Invoke-RestMethod "$api/agreements/privacy").data
PostJson "$adm/users/$uidB/level" @{level = 9} $ha | Out-Null
$profB2 = (Invoke-RestMethod "$api/users/$uidB").data
$ttl = PostJson "$adm/users/$uidB/title" @{kind = 1; grant = $true} $ha
$profB3 = (Invoke-RestMethod "$api/users/$uidB").data
Write-Output "[12.4] agreement=$([bool]$agr.title) level9=$($profB2.level) (expect 9) title=code$($ttl.code) certs=$(($profB3.certs -join ',')) (contains 1)"

# 12. dashboard + op logs recorded
$dash = (Invoke-RestMethod "$adm/dashboard" -Headers $ha).data
$logs = (Invoke-RestMethod "$adm/oplogs" -Headers $ha).data
Write-Output "[12] dashboard users=$($dash.users) posts=$($dash.posts) pendingAudits=$($dash.pendingAudits) youzhu=$($dash.youzhuIssued)/$($dash.youzhuBurned); oplogs=$(@($logs).Count)"

Write-Output "ADMIN_SMOKE_DONE"

