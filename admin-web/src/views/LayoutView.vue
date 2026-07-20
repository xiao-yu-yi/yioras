<template>
  <el-container class="layout">
    <el-aside width="200px">
      <div class="brand">Yiora Admin</div>
      <el-menu :default-active="route.path" router>
        <el-menu-item index="/dashboard">数据看板</el-menu-item>
        <el-menu-item index="/audits">审核工作台</el-menu-item>
        <el-menu-item index="/contents">内容管理</el-menu-item>
        <el-menu-item index="/reports">举报处理</el-menu-item>
        <el-menu-item index="/certs">认证审核</el-menu-item>
        <el-menu-item index="/users">用户处置</el-menu-item>
        <el-menu-item index="/banners">Banner 配置</el-menu-item>
        <el-menu-item index="/notices">公告群发</el-menu-item>
        <el-menu-item index="/words">敏感词库</el-menu-item>
        <el-menu-item index="/faqs">AI 管家 FAQ</el-menu-item>
        <el-menu-item index="/mall-config">商城/任务配置</el-menu-item>
        <el-menu-item index="/categories">软件分类</el-menu-item>
        <el-menu-item index="/admins">账号管理</el-menu-item>
        <el-menu-item index="/oplogs">操作日志</el-menu-item>
      </el-menu>
    </el-aside>
    <el-container>
      <el-header class="header">
        <span>{{ adminName }}</span>
        <el-button link type="danger" @click="logout">退出登录</el-button>
      </el-header>
      <el-main>
        <router-view />
      </el-main>
    </el-container>
  </el-container>
</template>

<script setup lang="ts">
import { useRoute, useRouter } from 'vue-router'

const route = useRoute()
const router = useRouter()
const adminName = localStorage.getItem('yiora_admin_name') || 'admin'

function logout() {
  localStorage.removeItem('yiora_admin_token')
  localStorage.removeItem('yiora_admin_name')
  router.push('/login')
}
</script>

<style scoped>
.layout {
  height: 100vh;
}
.brand {
  height: 56px;
  line-height: 56px;
  text-align: center;
  font-weight: 700;
  color: #409eff;
  border-bottom: 1px solid #eee;
}
.el-aside {
  border-right: 1px solid #eee;
}
.header {
  display: flex;
  align-items: center;
  justify-content: flex-end;
  gap: 12px;
  border-bottom: 1px solid #eee;
}
</style>
