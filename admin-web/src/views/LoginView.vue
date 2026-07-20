<template>
  <div class="login-wrap">
    <el-card class="login-card">
      <template #header>
        <div class="title">Yiora 管理后台</div>
      </template>
      <el-form v-if="!ticket" :model="form" label-width="0" @keyup.enter="submit">
        <el-form-item>
          <el-input v-model="form.username" placeholder="账号" size="large" />
        </el-form-item>
        <el-form-item>
          <el-input v-model="form.password" type="password" placeholder="密码" size="large" show-password />
        </el-form-item>
        <el-form-item>
          <div class="captcha-row">
            <el-input v-model="form.captchaCode" placeholder="验证码" size="large" maxlength="5" />
            <img
              v-if="captchaImg"
              class="captcha-img"
              :src="captchaImg"
              title="点击刷新验证码"
              @click="refreshCaptcha"
            />
          </div>
        </el-form-item>
        <el-button type="primary" size="large" style="width: 100%" :loading="loading" @click="submit">
          登 录
        </el-button>
      </el-form>

      <!-- 二步验证 -->
      <el-form v-else label-width="0" @keyup.enter="submitTotp">
        <el-alert class="totp-tip" type="info" :closable="false" title="该账号已启用二步验证,请输入验证器动态口令(或一次性恢复码)" show-icon />
        <el-form-item>
          <el-input v-model="totpCode" placeholder="6 位动态口令 / 恢复码" size="large" maxlength="10" autofocus />
        </el-form-item>
        <el-button type="primary" size="large" style="width: 100%" :loading="loading" @click="submitTotp">
          验 证
        </el-button>
        <el-button size="large" style="width: 100%; margin: 10px 0 0" @click="backToLogin">返回重新登录</el-button>
      </el-form>
    </el-card>
  </div>
</template>

<script setup lang="ts">
import { onMounted, reactive, ref } from 'vue'
import { useRouter } from 'vue-router'
import { ElMessage } from 'element-plus'
import { api } from '../api'

const router = useRouter()
const form = reactive({ username: 'admin', password: '', captchaCode: '' })
const captchaId = ref('')
const captchaImg = ref('')
const loading = ref(false)
const ticket = ref('')
const totpCode = ref('')

async function refreshCaptcha() {
  form.captchaCode = ''
  const data = await api.captcha()
  captchaId.value = data.captchaId
  captchaImg.value = data.image
}

function finishLogin(data: { token: string; username: string; mustChangePwd: boolean }) {
  localStorage.setItem('yiora_admin_token', data.token)
  localStorage.setItem('yiora_admin_name', data.username)
  if (data.mustChangePwd) {
    localStorage.setItem('yiora_admin_must_pwd', '1')
    ElMessage.warning('首次登录请先修改初始密码')
    router.push('/change-password')
    return
  }
  localStorage.removeItem('yiora_admin_must_pwd')
  router.push('/')
}

async function submit() {
  if (!form.username || !form.password || !form.captchaCode) {
    ElMessage.warning('请输入账号、密码与验证码')
    return
  }
  loading.value = true
  try {
    const data = await api.login(form.username, form.password, captchaId.value, form.captchaCode)
    if (data.totpRequired && data.ticket) {
      ticket.value = data.ticket
      totpCode.value = ''
      return
    }
    finishLogin(data)
  } catch {
    refreshCaptcha() // 验证码一次性,失败后必须换新
  } finally {
    loading.value = false
  }
}

async function submitTotp() {
  if (!totpCode.value.trim()) {
    ElMessage.warning('请输入动态口令')
    return
  }
  loading.value = true
  try {
    const data = await api.loginTotp(ticket.value, totpCode.value.trim())
    finishLogin(data)
  } catch (e: unknown) {
    // 票据过期回登录页,口令错误留在本页重试
    if ((e as Error).message?.includes('票据')) backToLogin()
  } finally {
    loading.value = false
  }
}

function backToLogin() {
  ticket.value = ''
  totpCode.value = ''
  refreshCaptcha()
}

onMounted(refreshCaptcha)
</script>

<style scoped>
.login-wrap {
  height: 100vh;
  display: flex;
  align-items: center;
  justify-content: center;
  background: linear-gradient(135deg, #1f2d3d 0%, #2f4056 100%);
}
.login-card {
  width: 360px;
}
.title {
  font-size: 18px;
  font-weight: 600;
  text-align: center;
}
.captcha-row {
  display: flex;
  gap: 8px;
  width: 100%;
}
.captcha-img {
  height: 40px;
  border-radius: 4px;
  cursor: pointer;
  flex-shrink: 0;
}
.totp-tip {
  margin-bottom: 14px;
}
</style>
