# Yiora App（Flutter 客户端）

Yiora 移动端综合兴趣社区 App 的 Flutter 工程，当前为 **M2 页面层齐套 + M3 软件库/搜索首批落地**：
登录注册（含找回密码）→ 首页（Banner/置顶条/推荐流 + 应用 Tab 软件库 + 全局搜索）→ 圈子（圈内流最新/最热双 Tab）→ 发布（动态/软件双通道，软件含提取码）→ 帖子详情（两级评论 + 举报）→ 软件详情（下载风险弹窗/版本记录）→ 消息/私信（WS）→ 个人/他人主页 → 设置，全链路 Mock 可跑通。

需求基线见 `../docs/Yiora开发需求文档.md`（v1.1，含修订 6：气泡商城/我的二维码已裁剪）。

**视觉基线（2026-07 设计图对齐改版）**：全站品牌红橙渐变语言——白卡 + 柔投影 + 胶囊按钮/徽章；
首页卡片（爱心点赞/浏览量互动栏）、圈子双列宫格、发布链路（面板/发动态/发软件/选择器）、
消息页（大标题 + 入口卡 + AI 管家高亮行）、我的页（大封面 + 骑缝头像 + 胶囊操作钮）均已按设计图重制，
实拍截图归档于 `../docs/screenshots/`。

## 环境

| 项 | 版本 |
| --- | --- |
| Flutter | 3.44.6（stable，SDK 位于 `F:\flutter_windows_3.44.6\flutter`） |
| Dart | 3.12.2 |
| 目标平台 | Android / iOS |

核心依赖：`flutter_riverpod` 3.x（状态管理）、`dio` 5.x（网络）、`go_router` 17.x（路由）、`flutter_secure_storage`（令牌安全存储）、`cached_network_image`（图片缓存）。

## 运行

```bash
# Mock 模式（默认）：无后端也能跑通 登录/注册 → 推荐流
flutter run

# 联调真实后端：关闭 Mock 并指定网关地址
flutter run --dart-define=USE_MOCK=false --dart-define=API_BASE_URL=https://api.example.com
```

Mock 登录约定：任意合法邮箱 + 密码 `12345678`；注册模式验证码任意填。

## 验证

```bash
flutter analyze     # 静态分析（当前 0 issue）
flutter test        # 单测 + Widget 测试（当前 82 个全过）
dart format lib test
flutter build apk --debug   # Android 构建链路已验证可产出 APK
```

### 本机离线构建适配（dl.google.com / pub.dev 直连不通）

| 适配项 | 位置 | 说明 |
| --- | --- | --- |
| Gradle 仓库镜像 | `~/.gradle/init.d/aliyun-mirror.gradle` + `android/settings.gradle.kts` | 官方仓库全部重写到阿里云镜像 |
| pub 镜像 | 环境变量 `PUB_HOSTED_URL=https://pub.flutter-io.cn`、`FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn` | pub get / SDK 资产下载 |
| Android Platform 34/36 | 从腾讯云镜像手动解压至 `%LOCALAPPDATA%\Android\sdk\platforms` | SDK Manager 不可用 |
| 规避 NDK 强制下载 | `android/app/build.gradle.kts` 清除 FGP 注入的空 CMake 工程；`flutter_secure_storage` 固定 9.x、`path_provider_android` 覆盖 2.2.x（10.x/2.3.x 经 jni 实现需 NDK） | 网络具备装好 NDK 后可全部还原 |
| Kotlin 增量缓存故障 | `android/gradle.properties` 关闭 `kotlin.incremental` | Windows 文件锁导致 "Could not close incremental caches" |

> debug APK 约 1.3GB 属正常（包含三个 ABI 的未裁剪调试引擎与 Vulkan 校验层）；日常真机调试用 `flutter run`，发布用 `flutter build apk --release`（AOT + strip，体积几十 MB）。

## 目录结构（feature-first）

```
lib/
├── main.dart                 # 入口：ProviderScope
├── app.dart                  # MaterialApp.router + 主题
├── core/                     # 与业务无关的基础设施
│   ├── cache/                # Hive JSON 键值缓存（SWR 层 + 草稿持久化）
│   ├── config/               # 环境配置（--dart-define 注入）
│   ├── network/              # dio 组装 / 统一响应包 / 统一异常 / 鉴权拦截器
│   ├── router/               # go_router + 登录三态 redirect（unknown/未登录/已登录）
│   ├── storage/              # Access/Refresh Token 安全存储
│   ├── theme/                # Material 3 主题（品牌色占位）
│   ├── utils/                # 相对时间、计数缩写等纯函数
│   └── ws/                   # IM 长连接：帧协议 / 心跳重连客户端 / Mock / 未读角标
└── features/                 # 按业务特性分包：data(API/仓库) / model / controller / view / widget
    ├── auth/                 # 邮箱登录/注册/验证码 + 找回密码页 + 全局登录态（M2）
    ├── home/                 # 首页运营位：公告 Banner 轮播 + 置顶精选横条（M2）
    ├── feed/                 # 首页推荐流：分页/刷新/骨架屏/SWR 缓存 + 全局点赞状态 + 顶部一级 Tab（首页/应用）（M2）
    ├── circle/               # 发现圈子（双列宫格 + 最热/最新胶囊）+ 圈子详情（信息卡 + 加入/退出 + 圈内流最新/最热双 Tab）（M2）
    ├── post_detail/          # 帖子详情：全文/大图预览/两级评论（点赞+回复+楼层展开分页+长按举报）/收藏/举报（M2）
    ├── publish/              # 发布面板（渐变主卡）+ 发动态页 + 发软件页（Logo/介绍图/分类/渠道/标签/提取码）（M2/M3）
    ├── software/             # 应用中心/软件库：列表（类型/分类/排序筛选）+ 详情（截图横滑/版本记录/发布者）+ 下载（风险弹窗/链接提取码复制）（M3）
    ├── search/               # 全局搜索：帖子/用户/圈子/话题/软件五类 + 防抖 + 分页 + 结果跳转（M3）
    ├── report/               # 通用举报：分类 chips + 补充说明底部面板，帖子/评论/用户共用（M2）
    ├── messages/             # 消息主页（入口卡 + AI 管家高亮 + 会话列表）+ 通知列表（M2）
    ├── chat/                 # 私信聊天：气泡/乐观发送/ack/失败重发（WS 驱动）（M2）
    ├── user/                 # 他人主页 + 关注/取关（全局乐观状态）+ 发起私信 + 举报入口（M2）
    ├── profile/              # 个人主页/编辑资料/设置（清缓存/注销账号）+ 侧边抽屉（M2）
    └── shell/                # 底部 5 Tab 主壳（悬浮胶囊 + 中央发布钮 + 消息未读角标）
```

## 关键设计

- **统一响应包**：`{code, msg, data, traceId}`，`code==0` 成功；`ApiResponse.unwrap()` 失败抛 `ApiException`，UI 只消费可展示文案。
- **令牌链路**：登录后 Access/Refresh 双令牌写入安全存储；`AuthInterceptor`（QueuedInterceptor 串行）负责请求注入与 401 刷新单飞 + 原请求重放；刷新失败清令牌并广播登录失效，路由自动回登录页。
- **登录三态**：`AuthUnknown / AuthUnauthenticated / AuthAuthenticated`，冷启动停在启动页恢复会话，避免闪跳登录页。
- **推荐流状态**：首屏 loading/error 由 `AsyncValue` 表达；`FeedState` 承载列表 + 游标 + `loadingMore` + 分页错误，加载更多失败不清已有数据。
- **SWR 缓存**：推荐流首页命中 Hive 缓存先渲染再后台刷新回写（`stale-while-revalidate`），后台刷新失败静默保留缓存；发布草稿同走 Hive 持久化，杀进程可恢复。
- **IM 长连接**：`YioraWsClient` 抽象 + 双实现——真实版（`WSS /ws?token=` 鉴权、30s 心跳 + 10s pong 超时判死、1→30s 指数退避重连、登录建连/登出断开）与 Mock 版（ack 回执 + Yo酱自动回复）。聊天消息乐观插入（sending→ack 置 sent，10s 超时置 failed 可点重发）；未读角标由 WS badge/msg 帧增量驱动 + 消息页快照校正。
- **Mock 层**：`AuthRepository` / `FeedRepository` / `CircleRepository` / `PublishRepository` / `MessagesRepository` / `ChatRepository` 均为接口 + HTTP/Mock 双实现，由 `USE_MOCK` 编译期开关选择，联调时无需改业务代码。

## 新增接口约定（联调时服务端需对齐）

- `POST /comments/{id}/like` 评论点赞（body `{like: bool}`，幂等）
- `GET /comments/{id}/replies?cursor=&size=` 楼层回复全量分页
- 软件库/搜索/举报客户端已按 server `types.go` 契约实现：
  `POST /software`（`categoryId`/`extractCode`）、`GET /software`（页码分页 + `sort=new|hot|download`）、
  `GET /software/:id`、`POST /software/:id/download`、`GET /software/categories?type=`（`CategoryItem` 数组）、
  `GET /search?type=&kw=&page=&size=`、`POST /reports`（targetType 1帖/2评/3用户）、
  `GET /circles/:id/posts?sort=new|hot`、`POST /auth/reset-password`

## 裁剪记录（v1.1 修订 6，2026-07-20）

- 气泡商城：客户端抽屉入口、服务端 `DecoKindBubble`/SQL 种子/AI 话术、管理端类型选项均已删除，装扮仅保留头像框
- 我的二维码：客户端入口删除（后端本无实现）；我的页扫一扫图标同步删除
- 开通 VIP、商品橱窗、群聊：按文档 1.5 裁剪未实现

## 待办（当前未含）

- WS 真实网关联调（协议细节按服务端微调）、离线消息补拉、已读回执（last_read_seq）、消息撤回、图片/分享卡片消息
- 帖子详情的付费解锁、@解析、外链卡片、分享
- 发动态的 @好友、共创者（入口占位）、付费查看（开关占位）、附加链接（悬浮入口占位）、图片拖拽排序与上传前压缩
- 更换封面（占位）、性别/生日编辑、账号安全与通知设置（占位）、粉丝/关注列表页
- M3 余量：软件库 Banner 推荐位与运营合集、软件评论区、话题聚合页（搜索话题结果暂提示开发中）、任务中心/签到/忧珠
- 全站真实后端联调：M2 早期域（feed/circle 游标分页、Post 字段）与 server 契约存在差异，联调时需按 `types.go` 收口
- iOS 联调 http 明文需配置 ATS 例外（Mock 模式无此问题）
