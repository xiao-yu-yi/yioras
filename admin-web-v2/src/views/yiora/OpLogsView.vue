<template>
  <el-card>
    <template #header><span>操作日志(敏感操作留痕)</span></template>

    <el-table :data="rows" v-loading="loading">
      <el-table-column prop="id" label="ID" width="80" />
      <el-table-column prop="adminId" label="管理员" width="100" />
      <el-table-column prop="action" label="动作" width="180">
        <template #default="{ row }">
          <el-tag :type="row.action.includes('reject') || row.action.includes('ban') ? 'danger' : 'success'">
            {{ row.action }}
          </el-tag>
        </template>
      </el-table-column>
      <el-table-column prop="target" label="操作对象" show-overflow-tooltip />
      <el-table-column prop="ip" label="IP" width="150" />
      <el-table-column label="时间" width="170">
        <template #default="{ row }">{{ new Date(row.createdAt).toLocaleString('zh-CN') }}</template>
      </el-table-column>
    </el-table>

    <div class="pager">
      <el-button :disabled="page <= 1" @click="load(page - 1)">上一页</el-button>
      <span>第 {{ page }} 页</span>
      <el-button :disabled="rows.length < 20" @click="load(page + 1)">下一页</el-button>
    </div>
  </el-card>
</template>

<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { api, type OpLogItem } from '@/api/yiora'

const rows = ref<OpLogItem[]>([])
const page = ref(1)
const loading = ref(false)

async function load(p: number) {
  loading.value = true
  try {
    page.value = p
    rows.value = await api.oplogs(p)
  } finally {
    loading.value = false
  }
}

onMounted(() => load(1))
</script>

<style scoped>
.pager {
  margin-top: 12px;
  display: flex;
  gap: 12px;
  align-items: center;
  justify-content: flex-end;
}
</style>
