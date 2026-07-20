<template>
  <el-container class="layout">
    <el-aside width="220px" class="aside">
      <div class="brand">
        <div class="brand-logo">Y</div>
        <div class="brand-text">
          <div class="brand-name">Yiora</div>
          <div class="brand-sub">社区管理后台</div>
        </div>
      </div>
      <el-scrollbar class="menu-scroll">
        <el-menu
          :default-active="route.path"
          router
          class="menu"
          background-color="transparent"
          text-color="#9fb0c7"
          active-text-color="#ffffff"
        >
          <template v-for="group in menuGroups" :key="group.title">
            <div class="menu-group">{{ group.title }}</div>
            <el-menu-item v-for="item in group.items" :key="item.path" :index="item.path">
              <el-icon><component :is="item.icon" /></el-icon>
              <span>{{ item.label }}</span>
            </el-menu-item>
          </template>
        </el-menu>
      </el-scrollbar>
    </el-aside>

    <el-container class="body">
      <el-header class="header">
        <div class="page-title">{{ currentTitle }}</div>
        <el-dropdown trigger="click" @command="onCommand">
          <span class="user">
            <el-avatar :size="30" class="user-avatar">{{ adminName[0]?.toUpperCase() }}</el-avatar>
            <span class="user-name">{{ adminName }}</span>
            <el-icon><ArrowDown /></el-icon>
          </span>
          <template #dropdown>
            <el-dropdown-menu>
              <el-dropdown-item command="password">修改密码</el-dropdown-item>
              <el-dropdown-item command="security">安全设置</el-dropdown-item>
              <el-dropdown-item command="logout" divided>退出登录</el-dropdown-item>
            </el-dropdown-menu>
          </template>
        </el-dropdown>
      </el-header>
      <el-main class="main">
        <router-view />
      </el-main>
    </el-container>
  </el-container>
</template>

<script setup lang="ts">
import { computed } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import {
  ArrowDown,
  Bell,
  ChatLineSquare,
  Collection,
  DataAnalysis,
  Document,
  Files,
  Lock,
  Medal,
  Menu as MenuIcon,
  PictureRounded,
  ShoppingBag,
  User,
  UserFilled,
  View,
  Warning,
} from '@element-plus/icons-vue'

const route = useRoute()
const router = useRouter()
const adminName = localStorage.getItem('yiora_admin_name') || 'admin'

const menuGroups = [
  {
    title: '概览',
    items: [{ path: '/dashboard', label: '数据看板', icon: DataAnalysis }],
  },
  {
    title: '内容与审核',
    items: [
      { path: '/audits', label: '审核工作台', icon: View },
      { path: '/contents', label: '内容管理', icon: Files },
      { path: '/reports', label: '举报处理', icon: Warning },
      { path: '/certs', label: '认证审核', icon: Medal },
    ],
  },
  {
    title: '用户',
    items: [{ path: '/users', label: '用户管理', icon: User }],
  },
  {
    title: '运营',
    items: [
      { path: '/banners', label: 'Banner 配置', icon: PictureRounded },
      { path: '/notices', label: '公告群发', icon: Bell },
      { path: '/mall-config', label: '商城/任务配置', icon: ShoppingBag },
      { path: '/categories', label: '软件分类', icon: MenuIcon },
    ],
  },
  {
    title: '风控配置',
    items: [
      { path: '/words', label: '敏感词库', icon: Collection },
      { path: '/faqs', label: 'AI 管家 FAQ', icon: ChatLineSquare },
    ],
  },
  {
    title: '系统',
    items: [
      { path: '/admins', label: '账号管理', icon: UserFilled },
      { path: '/security', label: '安全设置', icon: Lock },
      { path: '/oplogs', label: '操作日志', icon: Document },
    ],
  },
]

const currentTitle = computed(() => {
  for (const g of menuGroups) {
    const hit = g.items.find((i) => i.path === route.path)
    if (hit) return hit.label
  }
  return 'Yiora 管理后台'
})

function onCommand(cmd: string) {
  if (cmd === 'password') router.push('/change-password')
  else if (cmd === 'security') router.push('/security')
  else if (cmd === 'logout') {
    localStorage.removeItem('yiora_admin_token')
    localStorage.removeItem('yiora_admin_name')
    router.push('/login')
  }
}
</script>

<style scoped>
.layout {
  height: 100vh;
}

/* ---- 侧边栏 ---- */
.aside {
  background: var(--yiora-sidebar);
  display: flex;
  flex-direction: column;
}
.brand {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 16px 18px;
}
.brand-logo {
  width: 36px;
  height: 36px;
  border-radius: 10px;
  background: linear-gradient(135deg, #409eff, #7a5af8);
  color: #fff;
  font-weight: 800;
  font-size: 20px;
  display: flex;
  align-items: center;
  justify-content: center;
  flex-shrink: 0;
}
.brand-name {
  color: #fff;
  font-weight: 700;
  font-size: 16px;
  line-height: 1.2;
}
.brand-sub {
  color: #7d8fa5;
  font-size: 12px;
}
.menu-scroll {
  flex: 1;
}
.menu {
  border-right: none;
  padding-bottom: 16px;
}
.menu-group {
  color: #5f7189;
  font-size: 12px;
  padding: 14px 20px 6px;
  letter-spacing: 1px;
}
.menu :deep(.el-menu-item) {
  height: 42px;
  line-height: 42px;
  margin: 2px 10px;
  border-radius: 8px;
}
.menu :deep(.el-menu-item:hover) {
  background: rgba(255, 255, 255, 0.06);
}
.menu :deep(.el-menu-item.is-active) {
  background: var(--yiora-accent);
  color: #fff;
}

/* ---- 顶栏与内容 ---- */
.body {
  background: #f5f7fa;
}
.header {
  height: 56px;
  background: #fff;
  display: flex;
  align-items: center;
  justify-content: space-between;
  box-shadow: 0 1px 4px rgba(31, 45, 61, 0.06);
  z-index: 5;
}
.page-title {
  font-size: 16px;
  font-weight: 600;
  color: #24334a;
}
.user {
  display: flex;
  align-items: center;
  gap: 8px;
  cursor: pointer;
  color: #5b6b81;
}
.user-avatar {
  background: linear-gradient(135deg, #409eff, #7a5af8);
  color: #fff;
  font-weight: 700;
}
.user-name {
  font-size: 14px;
}
.main {
  padding: 18px;
  overflow: auto;
}
</style>
