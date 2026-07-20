# Flutter 对接任务清单(按依赖与优先级排期用)

> 2026-07 整理。服务端能力全部就绪并经冒烟验证;协议细节见《接口变更公告-上传直传与安全.md》对应章节(下表标注)。
> 演示环境:compose 一键起栈,MinIO/Meili/mock 机审/mock 推送全内置,无外网依赖即可联调。

## P0 基础链路(其余任务的前置)

| # | 任务 | 接口/协议 | 公告章节 | 要点 | 预估 |
| --- | --- | --- | --- | --- | --- |
| 1 | 双令牌改造 | login/register 新字段,`POST /auth/refresh` | 6.1/6.2 | refreshToken+deviceId 安全存储;dio 拦截器 401→refresh 重放→再失败登出;**旧 rt 重放会 40100,刷新后必须原子覆盖本地存储** | 1.5d |
| 2 | 设备管理页 | `GET/DELETE /user/devices` | 6.3 | 个人中心「登录设备」列表+踢下线;被踢后收 40100 按登出处理 | 0.5d |
| 3 | 图片直传组件 | `POST /upload/presign` → PUT → fileUrl 回填 | 1-3 | 头像/封面/帖图/软件图统一走直传;**外链 URL 会被业务接口 40000 拒绝**;失败重试与压缩前置 | 1d |

## P1 核心功能对接

| # | 任务 | 接口/协议 | 公告章节 | 要点 | 预估 |
| --- | --- | --- | --- | --- | --- |
| 4 | 推送 token 上报 | `POST /user/push-token` | 11 | 各厂商 SDK 取 token 登录后上报;token 轮换回调重报;退出无需处理(服务端清) | 1d(不含厂商 SDK 集成) |
| 5 | 通知深链路由 | payload.deeplink | 11 | `yiora://im/conversation/{id}`、`yiora://post/{id}`、`yiora://notifications/{type}` 三类 scheme 冷启动/后台路由 | 0.5d |
| 6 | 推送开关设置页 | `GET/PUT /user/settings` | 11 | 三个 Switch(私信/互动/系统)直连接口,不做本地缓存 | 0.5d |
| 7 | APK 分片上传 | `/upload/multipart/*` 四接口 | 8 | 8MB 分片并发 3~4 路;本地持久化 uploadId/etag 位图;恢复先调 parts 补缺口;URL 过期走 parts 补签 | 2d |
| 8 | 帖子分享口令 | `POST /posts/:id/share`、`GET /share/:code` | 7.2 | 复制文案进剪贴板;回前台读剪贴板正则 `YR[2-9A-HJ-NP-Z]{8}` 命中弹确认卡跳详情 | 1d |

## P2 体验增强

| # | 任务 | 接口/协议 | 公告章节 | 要点 | 预估 |
| --- | --- | --- | --- | --- | --- |
| 9 | 搜索联想 | `GET /search/suggest?kw=` | 9 | 输入防抖 250ms;`highlighted` 的 `<em>` 解析为 TextSpan 高亮;按 type 跳转 | 0.5d |
| 10 | 青少年模式 | `PUT /user/settings {teenMode}` | 7.1 | 开启后隐藏消费入口(解锁/抽奖/兑换);40300 统一 toast 兜底 | 0.5d |
| 11 | 在线小红点 | WS 帧 `notify.new` | 11 | data.type=1/2/3 刷新消息页对应 tab 角标(可选,不接也有拉取兜底) | 0.5d |
| 12 | 协议页 | `GET /agreements/{user\|privacy}` | 6.4 | 注册页强制同意+设置页入口,纯文本/Markdown 渲染 | 0.5d |

## 零改动周知

- AI 管家应答升级(FAQ→大模型→兜底)对客户端透明,管家消息仍是普通 IM 文本(公告第 10 节);
- 搜索主接口 `/search` 协议不变,命中质量由服务端 Meilisearch 提升;
- 首登强制改密已移除,登录响应无 mustChangePwd 字段。

## 联调资源

- 演示栈:`server/ docker compose up -d --build`(mysql/redis/minio/meili/api/ws 六容器);
- 演示账号重置:`scripts/demo-reset.ps1`;全链路参考请求:`scripts/smoke-*.ps1`(每个接口都有可运行示例);
- mock 渠道推送断言:redis `mockpush:last:{token}`,便于客户端不接厂商 SDK 先验证服务端链路。
