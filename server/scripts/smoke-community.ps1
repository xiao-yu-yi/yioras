# Yiora M2 全链路冒烟(全新数据卷):注册→发帖→互动→关注→IM/WS→撤回→举报→资料→删帖
# 所有 uid/postId/convId 动态获取,不依赖自增起点(bot 种子会抬高用户表 AUTO_INCREMENT)
$ErrorActionPreference = 'Stop'
$api = "http://localhost:8888/api/v1"

function PostJson($uri, $obj, $headers) {
    $json = $obj | ConvertTo-Json -Compress -Depth 5
    $bytes = [Text.Encoding]::UTF8.GetBytes($json)
    if ($headers) { return Invoke-RestMethod -Method Post -Uri $uri -Headers $headers -ContentType 'application/json; charset=utf-8' -Body $bytes }
    return Invoke-RestMethod -Method Post -Uri $uri -ContentType 'application/json; charset=utf-8' -Body $bytes
}

# 1. 验证码 + 注册(冷启动日志有延迟,轮询捕获)
PostJson "$api/auth/email-code" @{email = "a@test.com"; scene = "register"} $null | Out-Null
PostJson "$api/auth/email-code" @{email = "b@test.com"; scene = "register"} $null | Out-Null
$codeA = $null; $codeB = $null
for ($i = 0; $i -lt 10 -and (-not $codeA -or -not $codeB); $i++) {
    Start-Sleep -Seconds 1
    $codes = docker compose logs api 2>$null | Select-String "send code (\d{6}) to (\w)@test.com" | ForEach-Object { @{code = $_.Matches[0].Groups[1].Value; who = $_.Matches[0].Groups[2].Value} }
    $codeA = ($codes | Where-Object { $_.who -eq 'a' } | Select-Object -Last 1).code
    $codeB = ($codes | Where-Object { $_.who -eq 'b' } | Select-Object -Last 1).code
}
if (-not $codeA -or -not $codeB) { throw "email codes not captured from api logs" }
$r1 = PostJson "$api/auth/register" @{email = "a@test.com"; code = $codeA; password = "pass1234"; nickname = "AliceA"} $null
$r2 = PostJson "$api/auth/register" @{email = "b@test.com"; code = $codeB; password = "pass1234"; nickname = "BobB"} $null
$h1 = @{Authorization = "Bearer $($r1.data.token)"}
$h2 = @{Authorization = "Bearer $($r2.data.token)"}
$uidA = $r1.data.userId; $uidB = $r2.data.userId
Write-Output "[1] register U1=$uidA/$($r1.data.displayNo) U2=$uidB/$($r2.data.displayNo)"

# 2. 加圈 + 发帖(帖图先直传对象存储,业务侧强制域名白名单) + 推荐流
(PostJson "$api/circles/2/join" @{} $h1).code | Out-Null
$pre = PostJson "$api/upload/presign" @{kind = "post"; fileName = "1.png"; size = 256} $h1
$tmpImg = Join-Path ([IO.Path]::GetTempPath()) "smoke_c_img.png"
[IO.File]::WriteAllBytes($tmpImg, (New-Object byte[] 256))
Invoke-WebRequest -Method Put -Uri $pre.data.uploadUrl -InFile $tmpImg -UseBasicParsing | Out-Null
Remove-Item $tmpImg -ErrorAction SilentlyContinue
$extImg = PostJson "$api/posts" @{circleId = 2; content = "ext img"; images = @(@{url = "https://evil.example.com/x.jpg"})} $h1
$post = PostJson "$api/posts" @{circleId = 2; title = "Yiora first"; content = "hello community"; images = @(@{url = $pre.data.fileUrl; width = 800; height = 600})} $h1
$postId = $post.data.postId
$feed = (Invoke-RestMethod "$api/posts").data
Write-Output "[2] extImgReject=code$($extImg.code) (expect 40000) post id=$postId status=$($post.data.status); feed count=$($feed.Count) author=$($feed[0].author.nickname)"

# 3. 互动:U2 赞/藏/评,U1 回复,楼中楼
(PostJson "$api/posts/$postId/like" @{} $h2).code | Out-Null
(PostJson "$api/posts/$postId/favorite" @{} $h2).code | Out-Null
$c1 = PostJson "$api/comments" @{postId = $postId; content = "first comment"} $h2
$c2 = PostJson "$api/comments" @{postId = $postId; parentId = $c1.data.commentId; content = "reply to you"} $h1
$roots = (Invoke-RestMethod "$api/comments?postId=$postId").data
$replies = (Invoke-RestMethod "$api/comments?postId=$postId&rootId=$($c1.data.commentId)").data
$d = (Invoke-RestMethod "$api/posts/$postId" -Headers $h2).data
Write-Output "[3] comments: root=$($roots.Count) reply=$($replies.Count); detail likes=$($d.likeCount) cmts=$($d.commentCount) favs=$($d.favoriteCount) liked=$($d.liked)"

# 4. 关注 + 主页 + 通知
(PostJson "$api/users/$uidA/follow" @{} $h2).code | Out-Null
$p = (Invoke-RestMethod "$api/users/$uidA" -Headers $h2).data
$un = (Invoke-RestMethod "$api/notifications/unread" -Headers $h1).data
Write-Output "[4] U1 profile: fans=$($p.fans) posts=$($p.posts) likes=$($p.likes) followed=$($p.followed); U1 unread like=$($un.like) comment=$($un.comment) system=$($un.system)"

# 5. IM + WS:U2 挂长连接,U1 发3条,第4条限频
# 冷启动时 Docker 端口代理先于容器内监听就绪,连接失败重试
$ws = $null
for ($i = 0; $i -lt 10; $i++) {
    $ws = [System.Net.WebSockets.ClientWebSocket]::new()
    try {
        $ws.ConnectAsync([Uri]"ws://localhost:8889/ws?token=$($r2.data.token)", [Threading.CancellationToken]::None).Wait()
        if ($ws.State -eq 'Open') { break }
    } catch { $ws.Dispose(); $ws = $null; Start-Sleep -Seconds 2 }
}
if (-not $ws -or $ws.State -ne 'Open') { throw "ws connect failed after retries" }
# 超时后复用未完成的 ReceiveAsync,避免并发二次 Receive 抛异常
$script:pendingRecv = $null
function Recv($ws, $ms) {
    $buf = New-Object byte[] 65536
    if (-not $script:pendingRecv) {
        $script:pendingRecv = @{task = $ws.ReceiveAsync([ArraySegment[byte]]::new($buf), [Threading.CancellationToken]::None); buf = $buf}
    }
    $p = $script:pendingRecv
    if (-not $p.task.Wait($ms)) { return $null }
    $script:pendingRecv = $null
    return [Text.Encoding]::UTF8.GetString($p.buf, 0, $p.task.Result.Count)
}
$sent = @()
1..3 | ForEach-Object { $sent += (PostJson "$api/im/messages" @{targetUid = $uidB; msgType = 1; content = "hello-$_"} $h1).data }
$convId = $sent[0].convId
$frames = @(); 1..3 | ForEach-Object { $frames += Recv $ws 5000 }
$ok = ($frames | Where-Object { $_ -match '"op":"im.msg"' }).Count
$lim = PostJson "$api/im/messages" @{targetUid = $uidB; msgType = 1; content = "hello-4"} $h1
Write-Output "[5] ws=$($ws.State) conv=$convId sent seq=$($sent.seq -join ',') recv_frames=$ok limit4=code$($lim.code)"

# 6. 撤回:U1 撤第1条 → U2 收 im.recall,历史里 content 清空
$rc = PostJson "$api/im/messages/recall" @{convId = $convId; msgId = $sent[0].id} $h1
$recallFrame = Recv $ws 5000
$hist = (Invoke-RestMethod "$api/im/messages?convId=$convId" -Headers $h2).data
$m1 = $hist | Where-Object { $_.seq -eq 1 }
Write-Output "[6] recall code=$($rc.code); frame=$(if ($recallFrame -match 'im.recall') {'im.recall OK'} else {$recallFrame}); msg1 status=$($m1.status) content=[$($m1.content)]"

# 7. 会话未读/已读/删除(列表含 AI 管家会话,按 convId 精确取)
$convs = (Invoke-RestMethod "$api/im/conversations" -Headers $h2).data
$conv = $convs | Where-Object { $_.convId -eq $convId }
(PostJson "$api/im/read" @{convId = $convId; seq = 3} $h2).code | Out-Null
$after = (Invoke-RestMethod "$api/notifications/unread" -Headers $h2).data
(Invoke-RestMethod -Method Delete -Uri "$api/im/conversations/$convId" -Headers $h2).code | Out-Null
$convs2 = (Invoke-RestMethod "$api/im/conversations" -Headers $h2).data
$remain = ($convs2 | Where-Object { $_.convId -eq $convId }).Count
Write-Output "[7] conv unread=$($conv.unread) preview=[$($conv.lastPreview)]; after read im=$($after.im); deleted conv still listed=$remain (expect 0)"

# 8. 举报:U2 举报帖子,重复举报拦截;举报对方私信合法
$rp1 = PostJson "$api/reports" @{targetType = 1; targetId = $postId; category = 3; reason = "scam suspect"; images = @("https://cdn.example.com/p.jpg")} $h2
$rp2 = PostJson "$api/reports" @{targetType = 1; targetId = $postId; category = 3} $h2
$rp3 = PostJson "$api/reports" @{targetType = 4; targetId = $sent[1].id; category = 1} $h2
Write-Output "[8] report=code$($rp1.code) dup=code$($rp2.code) reportMsg=code$($rp3.code)"

# 9. 资料编辑:改昵称+签名;非法性别拒绝
$up = Invoke-RestMethod -Method Put -Uri "$api/user/me" -Headers $h1 -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes('{"nickname":"AliceNew","signature":"hi yiora"}'))
$me = (Invoke-RestMethod "$api/user/me" -Headers $h1).data
$bad = Invoke-RestMethod -Method Put -Uri "$api/user/me" -Headers $h1 -ContentType 'application/json' -Body '{"gender":9}'
Write-Output "[9] update=code$($up.code) me.nickname=$($me.nickname) sig=$($me.signature) badGender=code$($bad.code)"

# 10. 删帖越权 + 本人删除
$del1 = Invoke-RestMethod -Method Delete -Uri "$api/posts/$postId" -Headers $h2
$del2 = Invoke-RestMethod -Method Delete -Uri "$api/posts/$postId" -Headers $h1
$feed2 = (Invoke-RestMethod "$api/posts").data
Write-Output "[10] delete byU2=code$($del1.code) byU1=code$($del2.code) feedAfter=$($feed2.Count)"

$ws.CloseAsync([System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure, "bye", [Threading.CancellationToken]::None).Wait(3000) | Out-Null
Write-Output "SMOKE_DONE"
