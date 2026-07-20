<template>
  <el-card>
    <template #header>
      <div class="bar">
        <span>待人审队列</span>
        <el-radio-group v-model="bizType" @change="load(1)">
          <el-radio-button :value="0">全部</el-radio-button>
          <el-radio-button :value="1">帖子</el-radio-button>
          <el-radio-button :value="2">评论</el-radio-button>
          <el-radio-button :value="3">软件</el-radio-button>
        </el-radio-group>
      </div>
    </template>

    <el-table :data="rows" v-loading="loading">
      <el-table-column prop="id" label="单号" width="80" />
      <el-table-column label="类型" width="90">
        <template #default="{ row }">
          <el-tag :type="tagType(row.bizType)">{{ bizName(row.bizType) }}</el-tag>
        </template>
      </el-table-column>
      <el-table-column prop="bizId" label="业务ID" width="100" />
      <el-table-column label="机审" width="100">
        <template #default="{ row }">
          <el-tag v-if="row.machineResult === 2" type="warning">疑似</el-tag>
          <el-tag v-else type="info">常规</el-tag>
        </template>
      </el-table-column>
      <el-table-column prop="machineDetail" label="机审明细" show-overflow-tooltip />
      <el-table-column label="提交时间" width="170">
        <template #default="{ row }">{{ fmtTime(row.createdAt) }}</template>
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
import { api, type AuditItem } from '@/api/yiora'

const rows = ref<AuditItem[]>([])
const bizType = ref(0)
const page = ref(1)
const loading = ref(false)

function bizName(t: number) {
  return { 1: '帖子', 2: '评论', 3: '软件' }[t] ?? '未知'
}
function tagType(t: number) {
  return ({ 1: 'primary', 2: 'success', 3: 'warning' } as const)[t as 1 | 2 | 3] ?? 'info'
}
function fmtTime(ms: number) {
  return new Date(ms).toLocaleString('zh-CN')
}

async function load(p: number) {
  loading.value = true
  try {
    page.value = p
    rows.value = await api.audits(bizType.value, p)
  } finally {
    loading.value = false
  }
}

async function decide(row: AuditItem, approve: boolean) {
  let reason = ''
  if (!approve) {
    const input = await ElMessageBox.prompt('请填写驳回原因(将通知作者)', '驳回', {
      inputValidator: (v: string) => (v.trim() ? true : '驳回原因必填'),
    }).catch(() => null)
    if (!input) return
    reason = input.value.trim()
  }
  await api.decide(row.id, approve, reason)
  ElMessage.success(approve ? '已通过' : '已驳回')
  load(page.value)
}

onMounted(() => load(1))
</script>

<style scoped>
.bar {
  display: flex;
  justify-content: space-between;
  align-items: center;
}
.pager {
  margin-top: 12px;
  display: flex;
  gap: 12px;
  align-items: center;
  justify-content: flex-end;
}
</style>
