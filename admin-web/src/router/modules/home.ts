const Layout = () => import("@/layout/index.vue");

export default {
  path: "/",
  name: "Home",
  component: Layout,
  redirect: "/dashboard",
  meta: {
    icon: "ep/data-analysis",
    title: "数据看板",
    rank: 0
  },
  children: [
    {
      path: "/dashboard",
      name: "Dashboard",
      component: () => import("@/views/yiora/DashboardView.vue"),
      meta: {
        title: "数据看板"
      }
    }
  ]
} satisfies RouteConfigsTable;
