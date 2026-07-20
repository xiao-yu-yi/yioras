<template>
  <div class="wrap">
    <el-card class="card">
      <template #header>
        <div class="title">修改密码</div>
      </template>
      <el-alert
        v-if="forced"
        class="tip"
        type="warning"
        :closable="false"
        title="出于安全要求,首次登录(或密码被重置后)必须先修改密码才能使用后台。"
        show-icon
      />
      <el-form label-width="0" @keyup.enter="submit">
        <el-form-item>
          <el-input v-model="oldPwd" type="password" placeholder="当前密码" size="large" show-password />
        </el-form-item>
        <el-form-item>
          <el-input v-model="newPwd" type="password" placeholder="新密码(8-64 位,须含字母和数字)" size="large" show-password />
        </el-form-item>
        <el-form-item>
          <el-input v-model="confirmPwd" type="password" placeholder="确认新密码" size="large" show-password />
        </el-form-item>
        <el-button type="primary" size="large" style="width: 100%" :loading="loading" @click="submit">
          确认修改
        </el-button>
        <el-button v-if="!forced" size="large" style="width: 100%; margin: 10px 0 0" @click="router.back()">
          返 回
        </el-button>
      </el-form>
    </el-card>
  </div>
</template>

<script setup lang="ts">
import { computed, ref } from 'vue'
import { useRouter } from 'vue-router'
import { ElMessage } from 'element-plus'
import { api } from '../api'

const router = useRouter()
const oldPwd = ref('')
const newPwd = ref('')
const confirmPwd = ref('')
const loading = ref(false)
const forced = computed(() => localStorage.getItem('yiora_admin_must_pwd') === '1')

async function submit() {
  if (!oldPwd.value || !newPwd.value) {
    ElMessage.warning('请填写完整')
    return
  }
  if (newPwd.value !== confirmPwd.value) {
    ElMessage.warning('两次输入的新密码不一致')
    return
  }
  if (newPwd.value.length < 8 || !/[a-zA-Z]/.test(newPwd.value) || !/\d/.test(newPwd.value)) {
    ElMessage.warning('新密码需 8 位以上且同时包含字母和数字')
    return
  }
  loading.value = true
  try {
    await api.changePassword(oldPwd.value, newPwd.value)
    localStorage.removeItem('yiora_admin_must_pwd')
    ElMessage.success('密码已修改')
    router.push('/')
  } finally {
    loading.value = false
  }
}
</script>

<style scoped>
.wrap {
  height: 100vh;
  display: flex;
  align-items: center;
  justify-content: center;
  background: linear-gradient(135deg, #1f2d3d 0%, #2f4056 100%);
}
.card {
  width: 400px;
}
.title {
  font-size: 18px;
  font-weight: 600;
  text-align: center;
}
.tip {
  margin-bottom: 14px;
}
</style>
