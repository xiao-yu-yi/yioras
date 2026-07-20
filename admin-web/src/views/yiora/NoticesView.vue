<template>
  <el-card>
    <template #header><span>系统公告群发</span></template>

    <el-form :model="form" label-width="60px" class="form">
      <el-form-item label="标题" required>
        <el-input v-model="form.title" maxlength="100" show-word-limit placeholder="公告标题(将作为通知内容展示)" />
      </el-form-item>
      <el-form-item label="内容" required>
        <el-input
          v-model="form.content"
          type="textarea"
          :rows="8"
          maxlength="5000"
          show-word-limit
          placeholder="公告正文"
        />
      </el-form-item>
      <el-form-item>
        <el-button type="primary" :loading="sending" @click="publish">发布并全员推送</el-button>
      </el-form-item>
    </el-form>

    <el-alert
      type="warning"
      :closable="false"
      title="发布后将立即向全体正常用户的「系统通知」推送一条公告,操作不可撤回,请仔细核对内容。"
    />
  </el-card>
</template>

<script setup lang="ts">
import { reactive, ref } from 'vue'
import { ElMessage, ElMessageBox } from 'element-plus'
import { api } from '@/api/yiora'

const form = reactive({ title: '', content: '' })
const sending = ref(false)

async function publish() {
  if (!form.title.trim() || !form.content.trim()) {
    ElMessage.warning('标题与内容不能为空')
    return
  }
  const ok = await ElMessageBox.confirm(`确认向全体用户推送公告「${form.title}」?`, '全员群发确认', {
    type: 'warning',
    confirmButtonText: '确认发布',
  }).catch(() => null)
  if (!ok) return
  sending.value = true
  try {
    await api.publishNotice(form.title.trim(), form.content.trim())
    ElMessage.success('公告已发布并全员推送')
    form.title = ''
    form.content = ''
  } finally {
    sending.value = false
  }
}
</script>

<style scoped>
.form {
  max-width: 720px;
}
</style>
