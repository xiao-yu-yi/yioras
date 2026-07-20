# Yiora Server（M2 骨架）

Go 模块化单体，两个可执行入口：业务 API（go-zero rest）与 IM WS 网关（独立部署）。需求见 `../docs/Yiora开发需求文档.md` v1.1。

## 目录

```
server/
├── cmd/
│   ├── api/main.go        # 业务 API :8888
│   └── ws/main.go         # IM 长连接网关 :8889（GET /ws?token=）
├── etc/                   # 配置（生产密钥走环境变量/密管）
├── sql/001_m2_schema.sql  # M2 全量建表（MySQL 8.0+）
└── internal/
    ├── config/            # 配置结构
    ├── svc/               # ServiceContext（DB/Redis/Email/Model 装配）
    ├── types/             # 请求/响应 DTO
    ├── handler/           # 路由 + HTTP 层（auth/post/comment/circle/im/notify 已注册）
    ├── logic/             # 业务逻辑（auth/post/comment/circle/im/notify/user 已实现）
    ├── model/             # 手写 sqlx 模型（user/post/circle/interact/im/notify/sensitive）
    ├── ws/                # WS Hub：鉴权/心跳/在线路由/Push
    └── pkg/               # resp 统一响应 / xerr 错误码 / jwtx / emailx
```

## 本地启动

```bash
# 1. 建库（MySQL 8.0+）
mysql -uroot -p < sql/001_m2_schema.sql

# 2. 起 Redis（验证码/频控/后续计数）
docker run -d -p 6379:6379 redis:7

# 3. 改 etc/yiora-api.yaml 的 MySQL/Redis 连接

# 4. 启动
go run ./cmd/api      # 业务 API
go run ./cmd/ws       # WS 网关
```

## 冒烟自测（邮箱认证闭环）

```bash
curl -X POST localhost:8888/api/v1/auth/email-code -H "Content-Type: application/json" \
  -d '{"email":"a@b.com","scene":"register"}'          # Mock 模式验证码在 api 日志里
curl -X POST localhost:8888/api/v1/auth/register -H "Content-Type: application/json" \
  -d '{"email":"a@b.com","code":"<日志中的码>","password":"12345678"}'
curl -X POST localhost:8888/api/v1/auth/login -H "Content-Type: application/json" \
  -d '{"email":"a@b.com","password":"12345678"}'        # 拿 token
curl localhost:8888/api/v1/user/me -H "Authorization: Bearer <token>"
```

## 冒烟自测（社区闭环，`$T` 为上一步 token）

```bash
# 发帖 → 推荐流 → 详情 → 点赞收藏
curl -X POST localhost:8888/api/v1/posts -H "Authorization: Bearer $T" -H "Content-Type: application/json" \
  -d '{"circleId":2,"title":"第一帖","content":"大家好","images":[]}'
curl "localhost:8888/api/v1/posts?page=1&size=20"                      # 游客可看;带 token 返回 liked/favorited
curl localhost:8888/api/v1/posts/1 -H "Authorization: Bearer $T"
curl -X POST localhost:8888/api/v1/posts/1/like -H "Authorization: Bearer $T"
curl -X POST localhost:8888/api/v1/posts/1/favorite -H "Authorization: Bearer $T"

# 评论(两级)
curl -X POST localhost:8888/api/v1/comments -H "Authorization: Bearer $T" -H "Content-Type: application/json" \
  -d '{"postId":1,"content":"沙发"}'
curl "localhost:8888/api/v1/comments?postId=1"                          # rootId=<楼层id> 拉楼中楼
curl -X POST localhost:8888/api/v1/comments/1/like -H "Authorization: Bearer $T"

# 圈子
curl "localhost:8888/api/v1/circles?sort=hot"
curl "localhost:8888/api/v1/circles/2/posts?sort=new"
curl -X POST localhost:8888/api/v1/circles/2/join -H "Authorization: Bearer $T"

# 私信(先注册第二个账号拿 uid;WS 端连 ws://localhost:8889/ws?token=$T2 可收到 im.msg 推送)
curl -X POST localhost:8888/api/v1/im/messages -H "Authorization: Bearer $T" -H "Content-Type: application/json" \
  -d '{"targetUid":2,"msgType":1,"content":"你好"}'
curl localhost:8888/api/v1/im/conversations -H "Authorization: Bearer $T"
curl "localhost:8888/api/v1/im/messages?convId=1" -H "Authorization: Bearer $T"
curl -X POST localhost:8888/api/v1/im/read -H "Authorization: Bearer $T" -H "Content-Type: application/json" \
  -d '{"convId":1,"seq":1}'

# 通知与角标
curl "localhost:8888/api/v1/notifications?type=1" -H "Authorization: Bearer $T"
curl localhost:8888/api/v1/notifications/unread -H "Authorization: Bearer $T"

# 首页配置与用户主页
curl localhost:8888/api/v1/home/config                                  # Banner + 置顶精选
curl localhost:8888/api/v1/users/2 -H "Authorization: Bearer $T"        # 主页(数据栏/关系状态)
curl "localhost:8888/api/v1/users/2/posts?page=1"                       # 作品 Tab(本人含审核状态)
curl "localhost:8888/api/v1/users/2/fans"                               # 粉丝;/following 关注
curl -X POST localhost:8888/api/v1/users/2/follow -H "Authorization: Bearer $T"   # DELETE 取关
curl -X POST localhost:8888/api/v1/users/2/block -H "Authorization: Bearer $T"    # DELETE 解除拉黑

# 私信管理
curl -X POST localhost:8888/api/v1/im/messages/recall -H "Authorization: Bearer $T" \
  -H "Content-Type: application/json" -d '{"convId":1,"msgId":1}'       # 2 分钟内可撤回
curl -X DELETE localhost:8888/api/v1/im/conversations/1 -H "Authorization: Bearer $T"

# 账号进阶:找回密码/收藏/足迹/注销
curl -X POST localhost:8888/api/v1/auth/email-code -H "Content-Type: application/json" \
  -d '{"email":"a@b.com","scene":"reset"}'                              # 找回验证码(与注册码分场景频控)
curl -X POST localhost:8888/api/v1/auth/reset-password -H "Content-Type: application/json" \
  -d '{"email":"a@b.com","code":"<码>","password":"newpass99"}'
curl localhost:8888/api/v1/user/favorites -H "Authorization: Bearer $T" # 我的收藏
curl localhost:8888/api/v1/user/history -H "Authorization: Bearer $T"   # 我的足迹;DELETE 同路径清空
curl -X POST localhost:8888/api/v1/user/deactivate -H "Authorization: Bearer $T" \
  -H "Content-Type: application/json" -d '{"password":"pass1234"}'      # 注销:密码确认+存量token即时吊销

# 资料编辑(传哪个字段改哪个)与举报
curl -X PUT localhost:8888/api/v1/user/me -H "Authorization: Bearer $T" -H "Content-Type: application/json" \
  -d '{"nickname":"新昵称","signature":"个性签名"}'
curl -X POST localhost:8888/api/v1/reports -H "Authorization: Bearer $T" -H "Content-Type: application/json" \
  -d '{"targetType":1,"targetId":1,"category":3,"reason":"诈骗内容","images":["https://cdn.example.com/proof.jpg"]}'

# 搜索(M3):五类对象,MySQL LIKE 实现,可换 Meilisearch(pkg/search.Searcher)
curl "localhost:8888/api/v1/search?type=post&kw=你好"                   # type=post|user|circle|software|topic

# 任务与忧珠(M3):签到阶梯奖励;发帖/评论/点赞/浏览自动累进度;领取与签到均幂等入账
curl -X POST localhost:8888/api/v1/tasks/sign-in -H "Authorization: Bearer $T"
curl localhost:8888/api/v1/tasks -H "Authorization: Bearer $T"          # 任务列表+进度+签到状态
curl -X POST localhost:8888/api/v1/tasks/1/claim -H "Authorization: Bearer $T"
curl localhost:8888/api/v1/youzhu/account -H "Authorization: Bearer $T" # 忧珠余额
curl "localhost:8888/api/v1/youzhu/logs?bizType=0" -H "Authorization: Bearer $T"   # 收支流水

# 草稿箱与帖子编辑(P1)
curl -X POST localhost:8888/api/v1/drafts -H "Authorization: Bearer $T" -H "Content-Type: application/json" \
  -d '{"kind":1,"payload":"{\"title\":\"草稿\"}"}'                       # 传 id 覆盖保存;GET /drafts 列表;DELETE /drafts/:id
curl -X POST localhost:8888/api/v1/posts ... -d '{...,"draftId":1}'      # 由草稿发布,成功后自动删草稿
curl -X PUT localhost:8888/api/v1/posts/1 -H "Authorization: Bearer $T" -H "Content-Type: application/json" \
  -d '{"title":"新标题","content":"新正文","topics":["新话题"]}'          # 作者编辑,疑似词重回待审;付费段不可改

# 软件评论区(comment 表多业务对象:bizType 1帖子 2软件;postId 字段继续兼容)
curl -X POST localhost:8888/api/v1/comments -H "Authorization: Bearer $T" -H "Content-Type: application/json" \
  -d '{"bizType":2,"bizId":1,"content":"好用"}'
curl "localhost:8888/api/v1/comments?bizType=2&bizId=1"

# 等级/认证/圈子管理(P2)
curl -X POST localhost:8888/api/v1/certifications -H "Authorization: Bearer $T" -H "Content-Type: application/json" \
  -d '{"kind":2,"material":"作品链接与说明"}'                            # 1达人 2开发者;GET /certifications/mine 查状态
curl -X POST localhost:8888/api/v1/circles/2/admin/top -H "Authorization: Bearer $T" -H "Content-Type: application/json" \
  -d '{"postId":1,"on":true}'                                           # 圈主/管理员:top|essence|remove-post
curl -X POST localhost:8888/api/v1/circles/2/admin/mute -H "Authorization: Bearer $T" -H "Content-Type: application/json" \
  -d '{"userId":3,"days":1}'                                            # 圈内禁言,days=0 解除;发帖/评论被拦截
# 经验:发帖+5 评论+2 签到+5;等级按 level_rule 阈值自动升级(任务奖励经验同样生效)

# 内容进阶:话题/@好友/共创(发帖可带 topics/mentions/cocreators)
curl "localhost:8888/api/v1/topics/1/posts?sort=hot"                    # 话题聚合页
curl -X POST localhost:8888/api/v1/posts/1/cocreate/confirm -H "Authorization: Bearer $T" \
  -H "Content-Type: application/json" -d '{"accept":true}'              # 共创确认(需互关,双方主页展示)

# 忧珠商城(M4):装扮/靓号/抽奖,全部消耗单事务+幂等键记账
curl "localhost:8888/api/v1/mall/decorations?kind=1"                    # 装扮商城(登录返回 owned)
curl -X POST localhost:8888/api/v1/mall/decorations/1/exchange -H "Authorization: Bearer $T"
curl -X POST localhost:8888/api/v1/mall/decorations/1/wear -H "Authorization: Bearer $T"       # 佩戴,同类互斥;/take-off 卸下
curl localhost:8888/api/v1/mall/decorations/mine -H "Authorization: Bearer $T"                 # 我的仓库
curl localhost:8888/api/v1/mall/pretty-no                              # 靓号在售
curl -X POST localhost:8888/api/v1/mall/pretty-no/1/exchange -H "Authorization: Bearer $T"     # 兑换并替换展示编号
curl localhost:8888/api/v1/lottery/pools                               # 奖池+权重(概率公示)
curl -X POST localhost:8888/api/v1/lottery/draw -H "Authorization: Bearer $T"
curl localhost:8888/api/v1/exchange/records -H "Authorization: Bearer $T"                      # 兑换记录

# 软件库(M3):发布需人工审核,后台上架后公开可见
curl "localhost:8888/api/v1/software/categories?type=1"                 # 分类(发布器/筛选共用)
curl -X POST localhost:8888/api/v1/software -H "Authorization: Bearer $T" -H "Content-Type: application/json" \
  -d '{"name":"工具箱","logo":"https://cdn.example.com/logo.png","intro":"简介","images":["https://a/1.jpg","https://a/2.jpg","https://a/3.jpg"],"type":1,"categoryId":3,"tags":["免登录"],"version":"1.0.0","size":"10MB","channel":"自制","downloadUrl":"https://pan.example.com/x","extractCode":"abcd"}'
curl "localhost:8888/api/v1/software?type=1&sort=download"              # 列表:new|hot|download
curl localhost:8888/api/v1/software/1                                   # 详情(版本历史/标签/发布者)
curl -X POST localhost:8888/api/v1/software/1/download -H "Content-Type: application/json" -d '{}'   # 下载计数+取链接
curl localhost:8888/api/v1/software/mine -H "Authorization: Bearer $T"  # 我的发布(含审核状态)
curl -X POST localhost:8888/api/v1/software/1/versions -H "Authorization: Bearer $T" -H "Content-Type: application/json" \
  -d '{"version":"1.1.0","size":"11MB","downloadUrl":"https://pan.example.com/y"}'   # 版本更新同样过审
```

# 管理后台(/admin/v1):独立管理令牌+RBAC,初始账号 admin/admin123 首登强制改密
# 防护:图形验证码 + 同账号 5 次错密锁 15 分钟(Redis admin:login:fail:{user},DEL 可手动解锁)
#      + IP 白名单(配置 Admin.IPAllowlist 逗号分隔 IP/CIDR,空=不限;prod 经 YIORA_ADMIN_IP_ALLOWLIST 注入)
#      + TOTP 二步验证(RFC 6238):/totp/setup→confirm 绑定(10 恢复码),开启后 login 返回 ticket,
#        POST /admin/v1/login/totp {ticket,code} 换正式令牌;同码防重放;丢失验证器用恢复码或超管在账号管理强制解绑
curl localhost:8888/admin/v1/captcha                                                # 图形验证码(SVG,一次性 5 分钟)
curl -X POST localhost:8888/admin/v1/login -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"admin123","captchaId":"...","captchaCode":"..."}' # 拿管理 token($A);mustChangePwd=true 时其他接口 40300
curl -X POST localhost:8888/admin/v1/password -H "Authorization: Bearer $A" \
  -H "Content-Type: application/json" -d '{"oldPassword":"...","newPassword":"..."}'    # 改密(8-64 位含字母数字)
curl localhost:8888/admin/v1/admins -H "Authorization: Bearer $A"                   # 账号管理(admin.manage):列表/建号/角色/停用/重置密
curl localhost:8888/admin/v1/roles -H "Authorization: Bearer $A"                    # 角色下拉(超管/审核员/运营种子)
curl "localhost:8888/admin/v1/audits?bizType=0" -H "Authorization: Bearer $A"       # 待人审队列(帖/评/软件)
curl -X POST localhost:8888/admin/v1/audits/1/decide -H "Authorization: Bearer $A" \
  -H "Content-Type: application/json" -d '{"approve":true}'              # 过审落地:发布+计数补记+latest_version_id;驳回需 reason
curl localhost:8888/admin/v1/certifications -H "Authorization: Bearer $A"           # 认证审核队列;/:id/decide 裁决
curl -X POST localhost:8888/admin/v1/circles/2/appoint -H "Authorization: Bearer $A" \
  -H "Content-Type: application/json" -d '{"userId":3,"role":2}'         # 圈主/管理员任命
curl "localhost:8888/admin/v1/reports?status=0" -H "Authorization: Bearer $A"       # 举报队列(待处理 FIFO,含目标摘要)
curl -X POST localhost:8888/admin/v1/reports/1/handle -H "Authorization: Bearer $A" \
  -H "Content-Type: application/json" -d '{"action":1}'                   # 结单:1违规成立 2不成立;CAS 防重,通知举报人
curl "localhost:8888/admin/v1/contents?type=1&keyword=xx&status=-1" -H "Authorization: Bearer $A" # 内容检索(1帖 2评,关键词+全状态)
curl -X POST localhost:8888/admin/v1/contents/takedown -H "Authorization: Bearer $A" \
  -H "Content-Type: application/json" -d '{"type":1,"id":2,"action":1,"reason":"违规"}' # 一键下架(action=0 恢复),圈子/话题/评论计数自动回补
curl "localhost:8888/admin/v1/users?keyword=bob&status=1" -H "Authorization: Bearer $A" # 用户搜索(昵称/编号/邮箱模糊+状态筛选,带 total 分页)
curl -X POST localhost:8888/admin/v1/users/3/ban -H "Authorization: Bearer $A" \
  -H "Content-Type: application/json" -d '{"action":2,"days":1}'          # 处置:0恢复 2禁言 3封禁(Redis 标记即时生效)
curl "localhost:8888/admin/v1/words?status=-1" -H "Authorization: Bearer $A"        # 敏感词库(增删改即热更新过滤器,无需重启)
curl -X POST localhost:8888/admin/v1/words -H "Authorization: Bearer $A" \
  -H "Content-Type: application/json" -d '{"word":"xx","category":5,"level":1}'     # level: 1拦截 2人审 3打码
curl localhost:8888/admin/v1/faqs -H "Authorization: Bearer $A"                     # AI 管家 FAQ 词条(botReply 实时查库即时生效)
curl "localhost:8888/admin/v1/dashboard/trend?days=30" -H "Authorization: Bearer $A" # 近 N 日趋势(注册/发帖/忧珠,7-90 天,按日补零)
curl localhost:8888/admin/v1/software/categories -H "Authorization: Bearer $A"      # 软件分类管理(重名 42900;停用后发布表单隐藏)
curl localhost:8888/admin/v1/mall/decorations -H "Authorization: Bearer $A"         # 运营配置(ops.mall):装扮/奖池(/mall/prizes)/任务(/mall/tasks)
curl -X POST localhost:8888/admin/v1/mall/tasks -H "Authorization: Bearer $A" \
  -H "Content-Type: application/json" \
  -d '{"name":"每日点赞","type":1,"action":"like","targetCount":3,"rewardYouzhu":5}' # id>0 更新;条目不物理删,用 status 上下架
curl localhost:8888/admin/v1/oplogs -H "Authorization: Bearer $A"                   # 敏感操作留痕

# 对象存储直传(S3 兼容,dev 用 compose 内 MinIO,控制台 localhost:9001)
curl -X POST localhost:8888/api/v1/upload/presign -H "Authorization: Bearer $T" \
  -H "Content-Type: application/json" -d '{"kind":"post","fileName":"shot.png","size":2048}'
# → {uploadUrl, fileUrl}:对 uploadUrl 发 PUT(body=文件原文,10 分钟内有效),fileUrl 回填业务接口
# kind: avatar(5MB)/cover/post/software(10MB,图片) apk(500MB);类型/大小服务端白名单校验
# 业务侧强制域名白名单:头像/封面/帖图/软件 logo·截图/Banner/装扮预览必须来自我方存储前缀,
# 外链一律 40000(未配置 Storage 的部署退化为 http(s) 前缀检查);下载地址(网盘外链)不受限
# 管理端同能力:POST /admin/v1/upload/presign(kind 另有 banner/deco)

# 演示态一键重置(admin 回 admin123+强制改密,TOTP/锁定/票据全清,业务数据不动):
#   powershell -File .\scripts\demo-reset.ps1

# 双令牌与设备管理(3.1):登录/注册可传 deviceName,响应含 refreshToken(30 天)/deviceId
curl -X POST localhost:8888/api/v1/auth/refresh -H "Content-Type: application/json" \
  -d '{"refreshToken":"...","deviceId":"..."}'   # 轮换刷新:旧 RT 一次性作废,发新 access+refresh 对
curl localhost:8888/api/v1/user/devices -H "Authorization: Bearer $T"        # 登录设备列表(current 标记)
curl -X DELETE localhost:8888/api/v1/user/devices/<did> -H "Authorization: Bearer $T" # 踢设备:存量 access+refresh 即时失效
# 设备上限 Auth.MaxDevices(默认 5),超出自动踢最久未活跃;协议静态页 GET /api/v1/agreements/{user|privacy}

## 回归冒烟基线(发版前必跑)

```powershell
# 重置数据卷 → 起 mysql/redis/minio/api/ws → 依次跑 community/software/m3/mall/paid-ai/content/account/p1/p2/admin 十个套件
powershell -ExecutionPolicy Bypass -File scripts/smoke.ps1
# 期望输出:SMOKE RESULT: ALL PASSED
```

单个套件可独立执行(有依赖顺序:community 注册账号,后续套件复用账号与忧珠),
需要真实 WS 收包验证时看 community 套件的 im.msg/im.recall 帧输出。
脚本兼容 Windows PowerShell 5.1 与 pwsh 7;CI(GitHub Actions `smoke` job)在 ubuntu runner
上用 pwsh 跑同一份基线,PR 与主干推进自动执行,与本地结果一致。

## 忧珠账务集成测试(真 MySQL 并发安全)

```powershell
# testcontainers 拉起 mysql:8.0 跑迁移,验证幂等键防重放/余额禁负/解锁双账户/抽奖库存防超卖
go test -tags integration ./internal/model/ -run TestIntegration -v -count=1 -timeout 20m
# 本机 Docker Hub 不可达时,先通过镜像源准备 mysql:8.0 与 testcontainers/ryuk:0.14.0 本地镜像
```

## 生产部署(docker-compose.prod.yml)

```powershell
cp .env.prod.example .env            # 填写镜像/域名/全部密钥,.env 不入库
docker compose -f docker-compose.prod.yml up -d
```

- 镜像来自 CI 发布的 GHCR(`ghcr.io/<owner>/yiora-server`),一镜像含 api+ws,compose 用 command 区分入口
- 密钥全部走环境变量注入(`conf.UseEnv()` 解析 `etc/prod/*.yaml` 里的 `${VAR}` 占位),仓库不落任何真实密钥
- 对外仅暴露 Caddy 80/443(自动 Let's Encrypt);mysql/redis/api/ws 全部只在内部网络,WS 网关 `/internal/*` 在反代层拒绝公网访问
- 首次启动空数据卷自动执行 sql/ 全量迁移;版本升级的增量迁移手动执行:
  `docker compose -f docker-compose.prod.yml exec -T mysql sh -c "mysql -uroot -p\"$MYSQL_ROOT_PASSWORD\" yiora < /docker-entrypoint-initdb.d/00X_xxx.sql"`

## 扩展约定

- 新模块照抄 auth 链路：`types` 定义 DTO → `model` 手写 SQL → `logic` 业务 → `handler` 绑定 → `routes.go` 注册。
- 错误一律 `xerr.BizError` 或 `%w` 包装后由 `resp.Error` 收口；不向客户端泄漏内部错误。
- WS 只做下行推送与心跳；客户端发消息走 HTTP 落库后由消息服务调 `Hub.Push` 下行（多实例时在线路由表迁 Redis）。
- M3/M4 表（软件库/忧珠/装扮/靓号/抽奖）按需求文档 4.4 建 `002_m3_*.sql` 增量迁移，不改已上线文件。
