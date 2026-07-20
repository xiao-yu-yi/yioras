<template>
  <div class="upload-image">
    <el-input :model-value="modelValue" placeholder="点击右侧按钮上传图片" readonly>
      <template #append>
        <el-button :loading="uploading" @click="pick">{{ modelValue ? '重新上传' : '上传图片' }}</el-button>
      </template>
    </el-input>
    <el-image v-if="modelValue" class="preview" :src="modelValue" fit="cover" :preview-src-list="[modelValue]" />
    <input ref="fileEl" type="file" accept=".jpg,.jpeg,.png,.webp,.gif" class="hidden" @change="onPick" />
  </div>
</template>

<script setup lang="ts">
import { ref } from 'vue'
import { ElMessage } from 'element-plus'
import { uploadFile } from '../api'

const props = defineProps<{ modelValue: string; kind: string }>()
const emit = defineEmits<{ 'update:modelValue': [string] }>()

const fileEl = ref<HTMLInputElement>()
const uploading = ref(false)

function pick() {
  fileEl.value?.click()
}

async function onPick(e: Event) {
  const input = e.target as HTMLInputElement
  const file = input.files?.[0]
  input.value = '' // 允许重复选择同一文件
  if (!file) return
  if (file.size > 10 << 20) {
    ElMessage.warning('图片不能超过 10MB')
    return
  }
  uploading.value = true
  try {
    const url = await uploadFile(props.kind, file)
    emit('update:modelValue', url)
    ElMessage.success('上传成功')
  } catch {
    ElMessage.error('上传失败,请重试')
  } finally {
    uploading.value = false
  }
}
</script>

<style scoped>
.upload-image {
  display: flex;
  align-items: center;
  gap: 10px;
  width: 100%;
}
.preview {
  width: 40px;
  height: 40px;
  border-radius: 4px;
  flex-shrink: 0;
  border: 1px solid #dcdfe6;
}
.hidden {
  display: none;
}
</style>
