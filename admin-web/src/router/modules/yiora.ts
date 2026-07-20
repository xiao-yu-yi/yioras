// Yiora 业务菜单:内容审核 / 用户 / 运营 / 风控 / 系统
export default [
  {
    path: "/moderation",
    redirect: "/audits",
    meta: {
      icon: "ep/view",
      title: "内容与审核",
      rank: 1
    },
    children: [
      {
        path: "/audits",
        name: "Audits",
        component: () => import("@/views/yiora/AuditsView.vue"),
        meta: { title: "审核工作台", icon: "ep/view" }
      },
      {
        path: "/contents",
        name: "Contents",
        component: () => import("@/views/yiora/ContentsView.vue"),
        meta: { title: "内容管理", icon: "ep/files" }
      },
      {
        path: "/reports",
        name: "Reports",
        component: () => import("@/views/yiora/ReportsView.vue"),
        meta: { title: "举报处理", icon: "ep/warning" }
      },
      {
        path: "/certs",
        name: "Certs",
        component: () => import("@/views/yiora/CertsView.vue"),
        meta: { title: "认证审核", icon: "ep/medal" }
      },
      {
        path: "/topics",
        name: "Topics",
        component: () => import("@/views/yiora/TopicsView.vue"),
        meta: { title: "话题管理", icon: "ep/collection-tag" }
      }
    ]
  },
  {
    path: "/user-manage",
    redirect: "/users",
    meta: {
      icon: "ep/user",
      title: "用户",
      rank: 2
    },
    children: [
      {
        path: "/users",
        name: "Users",
        component: () => import("@/views/yiora/UsersView.vue"),
        meta: { title: "用户管理", icon: "ep/user" }
      }
    ]
  },
  {
    path: "/ops",
    redirect: "/banners",
    meta: {
      icon: "ep/shopping-bag",
      title: "运营",
      rank: 3
    },
    children: [
      {
        path: "/circles",
        name: "Circles",
        component: () => import("@/views/yiora/CirclesView.vue"),
        meta: { title: "圈子管理", icon: "ep/place" }
      },
      {
        path: "/banners",
        name: "Banners",
        component: () => import("@/views/yiora/BannersView.vue"),
        meta: { title: "Banner 配置", icon: "ep/picture-rounded" }
      },
      {
        path: "/notices",
        name: "Notices",
        component: () => import("@/views/yiora/NoticesView.vue"),
        meta: { title: "公告群发", icon: "ep/bell" }
      },
      {
        path: "/mall-config",
        name: "MallConfig",
        component: () => import("@/views/yiora/MallConfigView.vue"),
        meta: { title: "商城/任务配置", icon: "ep/shopping-bag" }
      },
      {
        path: "/categories",
        name: "Categories",
        component: () => import("@/views/yiora/CategoriesView.vue"),
        meta: { title: "软件分类", icon: "ep/menu" }
      },
      {
        path: "/youzhu",
        name: "Youzhu",
        component: () => import("@/views/yiora/YouzhuView.vue"),
        meta: { title: "忧珠运营", icon: "ep/coin" }
      }
    ]
  },
  {
    path: "/risk",
    redirect: "/words",
    meta: {
      icon: "ep/collection",
      title: "风控配置",
      rank: 4
    },
    children: [
      {
        path: "/words",
        name: "Words",
        component: () => import("@/views/yiora/WordsView.vue"),
        meta: { title: "敏感词库", icon: "ep/collection" }
      },
      {
        path: "/faqs",
        name: "Faqs",
        component: () => import("@/views/yiora/FaqsView.vue"),
        meta: { title: "AI 管家 FAQ", icon: "ep/chat-line-square" }
      }
    ]
  },
  {
    path: "/system",
    redirect: "/admins",
    meta: {
      icon: "ep/setting",
      title: "系统",
      rank: 5
    },
    children: [
      {
        path: "/admins",
        name: "Admins",
        component: () => import("@/views/yiora/AdminsView.vue"),
        meta: { title: "账号管理", icon: "ep/user-filled" }
      },
      {
        path: "/security",
        name: "Security",
        component: () => import("@/views/yiora/SecurityView.vue"),
        meta: { title: "安全设置", icon: "ep/lock" }
      },
      {
        path: "/agreements",
        name: "Agreements",
        component: () => import("@/views/yiora/AgreementsView.vue"),
        meta: { title: "协议管理", icon: "ep/reading" }
      },
      {
        path: "/oplogs",
        name: "OpLogs",
        component: () => import("@/views/yiora/OpLogsView.vue"),
        meta: { title: "操作日志", icon: "ep/document" }
      }
    ]
  }
] satisfies Array<RouteConfigsTable>;
