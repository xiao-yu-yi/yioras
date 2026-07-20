# Yiora 管理后台前端

Vue 3 + TypeScript + Vite + Element Plus + Pinia。对接 `server` 的 `/admin/v1` 接口。

## 页面

| 路由 | 页面 | 对接接口 |
| --- | --- | --- |
| `/login` | 登录 | `GET /admin/v1/captcha` + `POST /admin/v1/login`(初始 admin/admin123,图形验证码,首登强制改密) |
| `/change-password` | 改密 | `POST /admin/v1/password`;`mustChangePwd=true` 时路由守卫+后端双重拦截,改完才放行 |
| `/admins` | 账号管理 | `GET/POST /admin/v1/admins`、`POST /admin/v1/admins/:id`、`GET /admin/v1/roles`(建号/角色分配/停用/重置密码,不能操作自己) |
| `/dashboard` | 数据看板 | `GET /admin/v1/dashboard` 八项指标+积压告警;`GET /admin/v1/dashboard/trend` ECharts 近 7/30/90 日注册·发帖·忧珠四曲线 |
| `/audits` | 审核工作台 | `GET /admin/v1/audits`、`POST /admin/v1/audits/:id/decide`(帖/评/软件,驳回必填原因) |
| `/contents` | 内容管理 | `GET /admin/v1/contents`(帖/评关键词+全状态检索) + `POST /admin/v1/contents/takedown`(一键下架/恢复,计数自动回补) |
| `/reports` | 举报处理 | `GET /admin/v1/reports`(状态/类型筛选+目标摘要) + `POST /admin/v1/reports/:id/handle`;弹窗内快捷下架内容/处置用户后结单 |
| `/certs` | 认证审核 | `GET /admin/v1/certifications`、`POST /admin/v1/certifications/:id/decide` |
| `/users` | 用户管理 | `GET /admin/v1/users`(昵称/编号/邮箱搜索+状态筛选+分页) + `POST /admin/v1/users/:id/ban`(禁言/封禁/恢复,二次确认) |
| `/banners` | Banner 配置 | `GET/POST/DELETE /admin/v1/banners`(弹窗编辑,定时投放时段) |
| `/notices` | 公告群发 | `POST /admin/v1/notices`(全员推送,二次确认) |
| `/words` | 敏感词库 | `GET/POST /admin/v1/words`、`DELETE /admin/v1/words/:id`(词面/分类/等级/状态筛选,保存即热更新过滤器) |
| `/faqs` | AI 管家 FAQ | `GET/POST /admin/v1/faqs`、`DELETE /admin/v1/faqs/:id`(关键词竖线分隔,优先级升序命中,即时生效) |
| `/mall-config` | 商城/任务配置 | `GET/POST /admin/v1/mall/{decorations,prizes,tasks}`(装扮·奖池·任务三 tab CRUD,上下架控制,保存即生效) |
| `/categories` | 软件分类 | `GET/POST /admin/v1/software/categories`(应用/游戏两榜,重名 42900,停用后发布表单即隐藏) |
| `/oplogs` | 操作日志 | `GET /admin/v1/oplogs` |

token 存 localStorage,axios 拦截器统一注入 Authorization 与解包 `{code,msg,data}`;40100 自动跳登录。

## 本地开发

```bash
npm install --registry=https://registry.npmmirror.com
npm run dev          # http://localhost:5173,/admin/v1 代理到 localhost:8888(先起 server 的 docker compose)
npm run build        # 类型检查 + 产物 dist/
```

后续优化位:Element Plus 改按需引入收敛主包体积。
