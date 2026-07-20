<template>
  <el-card v-loading="loading">
    <template #header>
      <div class="bar">
        <span>协议管理(客户端注册页强制同意时拉取)</span>
        <el-radio-group v-model="kind" size="small" @change="load">
          <el-radio-button value="user">用户协议</el-radio-button>
          <el-radio-button value="privacy">隐私政策</el-radio-button>
        </el-radio-group>
      </div>
    </template>

    <el-form label-width="60px" class="form">
      <el-form-item label="标题" required>
        <el-input v-model="title" maxlength="100" show-word-limit />
      </el-form-item>
      <el-form-item label="正文" required>
        <el-input v-model="content" type="textarea" :rows="18" placeholder="支持 Markdown/纯文本" />
      </el-form-item>
      <el-form-item>
        <el-button type="primary" :loading="saving" @click="save">保存并生效</el-button>
        <span v-if="updatedAt" class="sub">最近更新:{{ new Date(updatedAt).toLocaleString('zh-CN') }}</span>
      </el-form-item>
    </el-form>
  </el-card>
</template>

<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { ElMessage } from 'element-plus'
import { api } from '@/api/yiora'

const kind = ref<'user' | 'privacy'>('user')
const title = ref('')
const content = ref('')
const updatedAt = ref(0)
const loading = ref(false)
const saving = ref(false)

async function load() {
  loading.value = true
  try {
    const data = await api.agreement(kind.value)
    title.value = data.title
    content.value = data.content
    updatedAt.value = data.updatedAt
  } finally {
    loading.value = false
  }
}

async function save() {
  if (!title.value.trim() || !content.value.trim()) {
    ElMessage.warning('标题与正文必填')
    return
  }
  saving.value = true
  try {
    await api.saveAgreement(kind.value, title.value.trim(), content.value.trim())
    ElMessage.success('已保存,客户端即时可见')
    load()
  } finally {
    saving.value = false
  }
}

onMounted(load)
</script>

<style scoped>
.bar {
  display: flex;
  justify-content: space-between;
  align-items: center;
}
.form {
  max-width: 860px;
}
.sub {
  margin-left: 12px;
  color: var(--el-text-color-secondary);
  font-size: 12px;
}
</style>
