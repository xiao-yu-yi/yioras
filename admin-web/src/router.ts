import { createRouter, createWebHashHistory } from 'vue-router'

const router = createRouter({
  history: createWebHashHistory(),
  routes: [
    { path: '/login', component: () => import('./views/LoginView.vue') },
    { path: '/change-password', component: () => import('./views/ChangePasswordView.vue') },
    {
      path: '/',
      component: () => import('./views/LayoutView.vue'),
      redirect: '/dashboard',
      children: [
        { path: 'dashboard', component: () => import('./views/DashboardView.vue') },
        { path: 'audits', component: () => import('./views/AuditsView.vue') },
        { path: 'contents', component: () => import('./views/ContentsView.vue') },
        { path: 'reports', component: () => import('./views/ReportsView.vue') },
        { path: 'certs', component: () => import('./views/CertsView.vue') },
        { path: 'users', component: () => import('./views/UsersView.vue') },
        { path: 'banners', component: () => import('./views/BannersView.vue') },
        { path: 'notices', component: () => import('./views/NoticesView.vue') },
        { path: 'words', component: () => import('./views/WordsView.vue') },
        { path: 'faqs', component: () => import('./views/FaqsView.vue') },
        { path: 'mall-config', component: () => import('./views/MallConfigView.vue') },
        { path: 'categories', component: () => import('./views/CategoriesView.vue') },
        { path: 'admins', component: () => import('./views/AdminsView.vue') },
        { path: 'oplogs', component: () => import('./views/OpLogsView.vue') },
      ],
    },
  ],
})

router.beforeEach((to) => {
  const authed = !!localStorage.getItem('yiora_admin_token')
  if (!authed && to.path !== '/login') return '/login'
  if (authed && to.path === '/login') return '/'
  // 首登强制改密:未完成前只允许停留在改密页(后端接口同样硬拦截)
  if (authed && localStorage.getItem('yiora_admin_must_pwd') === '1' && to.path !== '/change-password') {
    return '/change-password'
  }
})

export default router
