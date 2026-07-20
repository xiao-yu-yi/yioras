# Yiora 管理后台(admin-web)

基于 [vue-pure-admin 精简版](https://github.com/pure-admin/pure-admin-thin) 模板:Vue3 + TypeScript + Vite + Element Plus + Pinia + Tailwind。
自带亮/暗主题、可收缩侧边栏、标签页、菜单搜索(Ctrl+K)、布局配置面板。

## 启动

```bash
pnpm install          # 首次;Windows 构建脚本白名单见 pnpm-workspace.yaml
pnpm dev              # http://localhost:8848,/admin/v1 代理到 localhost:8888
pnpm build            # 产物 dist/
```

先起后端:`cd ../server && docker compose up -d --build`(空库先跑 `scripts\smoke.ps1` 造演示数据)。
初始账号 admin / admin123(图形验证码;若开启 TOTP 登录页自动出现二步验证)。

## 页面(路由按侧边栏六组)

| 路由 | 页面 | 对接接口 |
| --- | --- | --- |
| `/login` | 登录 | `GET /admin/v1/captcha` + `POST /admin/v1/login`(+ `POST /admin/v1/login/totp` 二步) |
| `/dashboard` | 数据看板 | `GET /admin/v1/dashboard` 八项指标;`GET /admin/v1/dashboard/trend` ECharts 近 7/30/90 日四曲线 |
| `/audits` | 审核工作台 | `GET /admin/v1/audits`、`POST /admin/v1/audits/:id/decide`(帖/评/软件,驳回必填原因) |
| `/contents` | 内容管理 | `GET /admin/v1/contents` + `POST /admin/v1/contents/takedown`(一键下架/恢复,计数自动回补) |
| `/reports` | 举报处理 | `GET /admin/v1/reports` + `POST /admin/v1/reports/:id/handle`;弹窗内快捷下架/处置用户后结单 |
| `/certs` | 认证审核 | `GET /admin/v1/certifications`、`POST /admin/v1/certifications/:id/decide` |
| `/users` | 用户管理 | `GET /admin/v1/users` 搜索筛选 + `/users/:id/ban` 处置 + `/users/:id/level` 等级调整 + `/users/:id/title` 头衔授予撤销 |
| `/banners` | Banner 配置 | `GET/POST/DELETE /admin/v1/banners`(图片经 UploadImage 组件直传对象存储) |
| `/notices` | 公告群发 | `POST /admin/v1/notices`(全员推送,二次确认) |
| `/circles` | 圈子管理 | `GET/POST /admin/v1/circles`(创建/排序/官方标记/隐藏解散) + `/circles/:id/appoint` 圈主任命 |
| `/topics` | 话题管理 | `GET/POST /admin/v1/topics`(封禁/恢复/热度调整) |
| `/youzhu` | 忧珠运营 | `POST /admin/v1/youzhu/grant`(手动发放/回收,幂等账本+通知) + `GET /admin/v1/youzhu/logs`(全站流水查询) |
| `/mall-config` | 商城/任务配置 | `GET/POST /admin/v1/mall/{decorations,prizes,tasks,prettynos}`(四 tab CRUD,保存即生效;已售靓号锁定) |
| `/agreements` | 协议管理 | `GET/POST /admin/v1/agreements/:kind`(用户协议/隐私政策,客户端 `GET /api/v1/agreements/:kind` 拉取) |
| `/categories` | 软件分类 | `GET/POST /admin/v1/software/categories` |
| `/words` | 敏感词库 | `GET/POST/DELETE /admin/v1/words`(保存即热更新过滤器) |
| `/faqs` | AI 管家 FAQ | `GET/POST/DELETE /admin/v1/faqs`(即时生效) |
| `/admins` | 账号管理 | `GET/POST /admin/v1/admins`、`POST /admin/v1/admins/:id`、`GET /admin/v1/roles`(建号/角色/停用/重置密码/强制解绑二步验证) |
| `/security` | 安全设置 | `GET /admin/v1/totp/status`、`POST /admin/v1/totp/{setup,confirm,disable}`(TOTP 绑定+恢复码) |
| `/change-password` | 修改密码 | `POST /admin/v1/password`(头像下拉/安全设置进入) |
| `/oplogs` | 操作日志 | `GET /admin/v1/oplogs` |

## 结构说明

- 业务页面集中在 `src/views/yiora/`,业务接口封装在 `src/api/yiora.ts`(独立 axios 实例,统一解包 `{code,msg,data}`,40100 自动登出)。
- 登录桥接在 `src/store/modules/user.ts`:双 token 写入(模板路由守卫用 + 业务接口用);管理令牌 8h 无刷新,过期自动登出。
- 菜单/路由在 `src/router/modules/{home,yiora}.ts` 静态定义,新增页面在 `yiora.ts` 对应分组加一项即可。
- 对模板的本地化修改:Windows 兼容 dev/build 脚本、移除 vite-plugin-cdn-import、`pnpm-workspace.yaml` 构建脚本白名单、补 tippy.js/@element-plus/icons-vue 直接依赖。
