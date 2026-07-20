<template>
  <el-card v-loading="loading">
    <template #header>
      <div class="bar">
        <span>运营参数(保存即生效,多实例部署最迟 60 秒同步)</span>
        <el-button type="primary" :loading="saving" @click="save">保存全部修改</el-button>
      </div>
    </template>

    <el-alert
      type="info"
      :closable="false"
      class="hint"
      title="参数键由版本迁移管理(不可增删),这里只调值:非负整数,或逗号分隔的整数列表(如签到阶梯)。改动即刻作用于线上行为,谨慎操作,全部留痕。"
    />

    <el-table :data="rows" size="default">
      <el-table-column label="参数说明" min-width="240">
        <template #default="{ row }">
          <div>{{ row.remark }}</div>
          <div class="key">{{ row.k }}</div>
        </template>
      </el-table-column>
      <el-table-column label="值" width="260">
        <template #default="{ row }">
          <el-input v-model="row.v" :class="{ dirty: row.v !== row.orig }" />
        </template>
      </el-table-column>
      <el-table-column label="最近更新" width="180">
        <template #default="{ row }">{{ new Date(row.updatedAt).toLocaleString('zh-CN') }}</template>
      </el-table-column>
      <el-table-column label="" width="90">
        <template #default="{ row }">
          <el-tag v-if="row.v !== row.orig" type="warning" size="small">未保存</el-tag>
        </template>
      </el-table-column>
    </el-table>
  </el-card>
</template>

<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { ElMessage } from 'element-plus'
import { api } from '@/api/yiora'

interface Row {
  k: string
  v: string
  orig: string
  remark: string
  updatedAt: number
}
const rows = ref<Row[]>([])
const loading = ref(false)
const saving = ref(false)

async function load() {
  loading.value = true
  try {
    const data = await api.appConfigs('')
    rows.value = data.map((r) => ({ ...r, orig: r.v }))
  } finally {
    loading.value = false
  }
}

async function save() {
  const dirty = rows.value.filter((r) => r.v !== r.orig)
  if (dirty.length === 0) {
    ElMessage.info('没有修改')
    return
  }
  saving.value = true
  try {
    await api.saveAppConfigs(dirty.map((r) => ({ k: r.k, v: r.v.trim() })))
    ElMessage.success(`已保存 ${dirty.length} 项,即时生效`)
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
.hint {
  margin-bottom: 14px;
}
.key {
  font-size: 11px;
  color: var(--el-text-color-secondary);
  font-family: monospace;
}
.dirty :deep(.el-input__wrapper) {
  box-shadow: 0 0 0 1px var(--el-color-warning) inset;
}
</style>
