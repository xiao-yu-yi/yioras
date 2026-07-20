<template>
  <el-card v-loading="loading">
    <template #header><span>安全设置</span></template>

    <el-descriptions :column="1" border class="status">
      <el-descriptions-item label="登录密码">
        <el-button size="small" @click="router.push('/change-password')">修改密码</el-button>
      </el-descriptions-item>
      <el-descriptions-item label="二步验证(TOTP)">
        <template v-if="status">
          <el-tag :type="status.enabled ? 'success' : 'info'">{{ status.enabled ? '已启用' : '未启用' }}</el-tag>
          <span v-if="status.enabled" class="sub" style="margin-left: 10px">
            剩余恢复码 {{ status.recoveryCodesLeft }} 个
          </span>
        </template>
      </el-descriptions-item>
    </el-descriptions>

    <!-- 未启用:发起绑定 -->
    <template v-if="status && !status.enabled">
      <el-button v-if="!setup" type="primary" @click="startSetup">启用二步验证</el-button>

      <div v-else class="setup-box">
        <el-alert
          type="warning"
          :closable="false"
          title="请把密钥录入验证器 App(Google Authenticator / 1Password 等),并妥善保存恢复码——明文仅显示这一次。"
          show-icon
        />
        <el-descriptions :column="1" border class="setup-info">
          <el-descriptions-item label="密钥(手动录入)">
            <code class="mono">{{ setup.secret }}</code>
          </el-descriptions-item>
          <el-descriptions-item label="otpauth URI(扫码导入)">
            <code class="mono small">{{ setup.uri }}</code>
          </el-descriptions-item>
          <el-descriptions-item label="恢复码(每个仅能用一次)">
            <div class="codes">
              <code v-for="c in setup.recoveryCodes" :key="c" class="mono">{{ c }}</code>
            </div>
          </el-descriptions-item>
        </el-descriptions>
        <el-form inline class="confirm-form" @submit.prevent="confirm">
          <el-form-item label="验证器当前口令">
            <el-input v-model="code" maxlength="6" style="width: 160px" @keyup.enter="confirm" />
          </el-form-item>
          <el-button type="primary" :loading="acting" @click="confirm">确认启用</el-button>
          <el-button @click="setup = null">取消</el-button>
        </el-form>
      </div>
    </template>

    <!-- 已启用:解绑 -->
    <template v-if="status?.enabled">
      <el-form inline class="confirm-form" @submit.prevent="disable">
        <el-form-item label="动态口令 / 恢复码">
          <el-input v-model="code" maxlength="10" style="width: 180px" @keyup.enter="disable" />
        </el-form-item>
        <el-button type="danger" :loading="acting" @click="disable">解绑二步验证</el-button>
      </el-form>
      <el-alert
        class="tip"
        type="info"
        :closable="false"
        title="验证器丢失时可用恢复码登录/解绑;两者都丢失请联系超级管理员在「账号管理」中强制重置二步验证。"
      />
    </template>
  </el-card>
</template>

<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { useRouter } from 'vue-router'
import { ElMessage, ElMessageBox } from 'element-plus'
import { api } from '../api'

const router = useRouter()
const loading = ref(false)
const acting = ref(false)
const status = ref<{ enabled: boolean; recoveryCodesLeft: number } | null>(null)
const setup = ref<{ secret: string; uri: string; recoveryCodes: string[] } | null>(null)
const code = ref('')

async function load() {
  loading.value = true
  try {
    status.value = await api.totpStatus()
  } finally {
    loading.value = false
  }
}

async function startSetup() {
  setup.value = await api.totpSetup()
  code.value = ''
}

async function confirm() {
  if (code.value.trim().length !== 6) {
    ElMessage.warning('请输入 6 位动态口令')
    return
  }
  acting.value = true
  try {
    await api.totpConfirm(code.value.trim())
    ElMessage.success('二步验证已启用,下次登录生效')
    setup.value = null
    code.value = ''
    load()
  } finally {
    acting.value = false
  }
}

async function disable() {
  if (!code.value.trim()) {
    ElMessage.warning('请输入动态口令或恢复码')
    return
  }
  const ok = await ElMessageBox.confirm('确认解绑二步验证?账号安全性将下降。', '解绑', { type: 'warning' }).catch(() => null)
  if (!ok) return
  acting.value = true
  try {
    await api.totpDisable(code.value.trim())
    ElMessage.success('已解绑')
    code.value = ''
    load()
  } finally {
    acting.value = false
  }
}

onMounted(load)
</script>

<style scoped>
.status {
  max-width: 720px;
  margin-bottom: 18px;
}
.setup-box {
  max-width: 720px;
}
.setup-info {
  margin: 14px 0;
}
.confirm-form {
  margin-top: 14px;
}
.codes {
  display: flex;
  flex-wrap: wrap;
  gap: 8px;
}
.mono {
  font-family: Consolas, monospace;
  background: #f4f6fa;
  padding: 2px 8px;
  border-radius: 4px;
}
.small {
  font-size: 12px;
  word-break: break-all;
}
.sub {
  color: #909399;
  font-size: 12px;
}
.tip {
  margin-top: 14px;
  max-width: 720px;
}
</style>
