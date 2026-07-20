# M3 software library smoke (ASCII only for PS5.1 compatibility)
$ErrorActionPreference = 'Stop'
$api = "http://localhost:8888/api/v1"

function PostJson($uri, $obj, $headers) {
    $bytes = [Text.Encoding]::UTF8.GetBytes(($obj | ConvertTo-Json -Compress -Depth 5))
    if ($headers) { return Invoke-RestMethod -Method Post -Uri $uri -Headers $headers -ContentType 'application/json; charset=utf-8' -Body $bytes }
    return Invoke-RestMethod -Method Post -Uri $uri -ContentType 'application/json; charset=utf-8' -Body $bytes
}

$login = PostJson "$api/auth/login" @{email = "a@test.com"; password = "pass1234"} $null
$h1 = @{Authorization = "Bearer $($login.data.token)"}
$login2 = PostJson "$api/auth/login" @{email = "b@test.com"; password = "pass1234"} $null
$h2 = @{Authorization = "Bearer $($login2.data.token)"}

# 1. categories
$cats = (Invoke-RestMethod "$api/software/categories?type=1").data
Write-Output ("[1] categories(type=1): " + (($cats | ForEach-Object { "$($_.id):$($_.name)" }) -join ' '))
$catId = $cats[0].id

# upload one real image via presign (logo/screenshots must come from our storage now)
$preS = PostJson "$api/upload/presign" @{kind = "software"; fileName = "s.png"; size = 256} $h1
$tmpS = Join-Path ([IO.Path]::GetTempPath()) "smoke_s_img.png"
[IO.File]::WriteAllBytes($tmpS, (New-Object byte[] 256))
Invoke-WebRequest -Method Put -Uri $preS.data.uploadUrl -InFile $tmpS -UseBasicParsing | Out-Null
Remove-Item $tmpS -ErrorAction SilentlyContinue
$img = $preS.data.fileUrl

# 2. image count violation (2 images) must be rejected; external logo also rejected
$bad = PostJson "$api/software" @{name = "BadApp"; logo = $img; intro = "x"; images = @($img, $img); type = 1; categoryId = $catId; version = "1.0"; size = "10MB"; downloadUrl = "https://pan.example.com/x"} $h1
$extLogo = PostJson "$api/software" @{name = "ExtApp"; logo = "https://evil.example.com/l.png"; intro = "x"; images = @($img, $img, $img); type = 1; categoryId = $catId; version = "1.0"; size = "10MB"; downloadUrl = "https://pan.example.com/x"} $h1
Write-Output "[2] 2-images reject: code=$($bad.code); extLogo reject: code=$($extLogo.code) (expect 40000x2)"

# 3. normal publish (3 images + tags + extract code)
$soft = PostJson "$api/software" @{name = "YioraToolbox"; logo = $img; intro = "all-in-one toolbox, clean and adfree"; images = @($img, $img, $img); type = 1; categoryId = $catId; tags = @("NoLogin", "AdFree"); version = "2.3.1"; size = "128MB"; channel = "custom"; downloadUrl = "https://pan.example.com/yiora"; extractCode = "y1r4"} $h1
$sid = $soft.data.softwareId; $vid = $soft.data.versionId
Write-Output "[3] publish: code=$($soft.code) softwareId=$sid versionId=$vid status=$($soft.data.status)"

# 4. guest list empty (pending), mine shows status
$pub = (Invoke-RestMethod "$api/software?type=1").data
$mine = (Invoke-RestMethod "$api/software/mine" -Headers $h1).data
Write-Output "[4] public list=$($pub.Count) mine=$($mine.Count) mineStatus=$($mine[0].status)"

# 5. audit queue row exists + simulate manual approval (admin action)
$ErrorActionPreference = 'Continue'
$aq = (docker compose exec -T mysql mysql -uroot -proot123 yiora -N -e "SELECT COUNT(1) FROM audit_queue WHERE biz_type=3 AND biz_id=$sid" 2>$null | Out-String).Trim()
docker compose exec -T mysql mysql -uroot -proot123 yiora -e "UPDATE software SET status=1, latest_version_id=$vid WHERE id=$sid; UPDATE software_version SET status=1 WHERE id=$vid;" 2>$null | Out-Null
$ErrorActionPreference = 'Stop'
Write-Output "[5] audit_queue rows=$aq; simulated approval done"

# 6. guest list/detail
$listItem = ((Invoke-RestMethod "$api/software?type=1&sort=download").data)[0]
Write-Output ("[6a] list: name=$($listItem.name) ver=$($listItem.version) tags=" + ($listItem.tags -join '/') + " dl=$($listItem.downloadCount)")
$detail = (Invoke-RestMethod "$api/software/$sid").data
Write-Output "[6b] detail: name=$($detail.name) imgs=$($detail.images.Count) publisher=$($detail.publisher.nickname) versions=$($detail.versions.Count) ver0=$($detail.versions[0].version)"

# 7. guest download -> count+1
$dl = PostJson "$api/software/$sid/download" @{} $null
$after = ((Invoke-RestMethod "$api/software?type=1").data)[0].downloadCount
Write-Output "[7] download: url=$($dl.data.downloadUrl) extract=$($dl.data.extractCode) count_after=$after"

# 8. new version -> pending; guest sees 1 version, owner sees 2
$v2 = PostJson "$api/software/$sid/versions" @{version = "2.4.0"; size = "130MB"; channel = "custom"; downloadUrl = "https://pan.example.com/yiora24"} $h1
$detail2 = (Invoke-RestMethod "$api/software/$sid").data
$mineDetail = (Invoke-RestMethod "$api/software/$sid" -Headers $h1).data
Write-Output "[8] newVersion code=$($v2.code) vid=$($v2.data.versionId); guestVersions=$($detail2.versions.Count) ownerVersions=$($mineDetail.versions.Count)"

# 9. duplicate version rejected; non-owner version update forbidden
$dup = PostJson "$api/software/$sid/versions" @{version = "2.4.0"; size = "1MB"; downloadUrl = "https://x.com/1"} $h1
$forbid = PostJson "$api/software/$sid/versions" @{version = "9.9.9"; size = "1MB"; downloadUrl = "https://x.com/1"} $h2
Write-Output "[9] dup=code$($dup.code) nonOwner=code$($forbid.code)"

Write-Output "SOFT_SMOKE_DONE"
