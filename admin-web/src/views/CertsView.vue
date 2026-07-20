<template>
  <el-card>
    <template #header><span>认证审核</span></template>

    <el-table :data="rows" v-loading="loading">
      <el-table-column prop="id" label="申请单" width="90" />
      <el-table-column prop="userId" label="用户ID" width="120" />
      <el-table-column label="类型" width="110">
        <template #default="{ row }">
          <el-tag :type="row.kind === 1 ? 'success' : 'primary'">
            {{ row.kind === 1 ? '达人认证' : '开发者认证' }}
          </el-tag>
        </template>
      </el-table-column>
      <el-table-column prop="material" label="佐证材料" show-overflow-tooltip />
      <el-table-column label="提交时间" width="170">
        <template #default="{ row }">{{ new Date(row.createdAt).toLocaleString('zh-CN') }}</template>
      </el-table-column>
      <el-table-column label="操作" width="170" fixed="right">
        <template #default="{ row }">
          <el-button size="small" type="success" @click="decide(row, true)">通过</el-button>
          <el-button size="small" type="danger" @click="decide(row, false)">驳回</el-button>
        </template>
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
import { ElMessage, ElMessageBox } from 'element-plus'
import { api, type CertItem } from '../api'

const rows = ref<CertItem[]>([])
const page = ref(1)
const loading = ref(false)

async function load(p: number) {
  loading.value = true
  try {
    page.value = p
    rows.value = await api.certs(p)
  } finally {
    loading.value = false
  }
}

async function decide(row: CertItem, approve: boolean) {
  let reason = ''
  if (!approve) {
    const input = await ElMessageBox.prompt('请填写驳回原因(将通知申请人)', '驳回', {
      inputValidator: (v: string) => (v.trim() ? true : '驳回原因必填'),
    }).catch(() => null)
    if (!input) return
    reason = input.value.trim()
  }
  await api.decideCert(row.id, approve, reason)
  ElMessage.success(approve ? '已通过,头衔已授予' : '已驳回')
  load(page.value)
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
