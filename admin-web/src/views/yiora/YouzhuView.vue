<template>
  <div>
    <el-card class="grant-card">
      <template #header><span>忧珠发放 / 回收(运营)</span></template>
      <el-form inline @submit.prevent="grant">
        <el-form-item label="用户 UID">
          <el-input-number v-model="grantUid" :min="1" :controls="false" style="width: 140px" />
        </el-form-item>
        <el-form-item label="数量">
          <el-input-number v-model="grantAmount" :min="-100000" :max="100000" style="width: 150px" />
          <span class="sub" style="margin-left: 6px">正=发放,负=回收</span>
        </el-form-item>
        <el-form-item label="原因">
          <el-input v-model="grantReason" placeholder="将写入流水并通知用户" style="width: 220px" />
        </el-form-item>
        <el-button type="primary" :loading="granting" @click="grant">执行</el-button>
      </el-form>
    </el-card>

    <el-card>
      <template #header><span>忧珠流水查询</span></template>
      <el-form inline @submit.prevent="search">
        <el-form-item label="UID">
          <el-input-number v-model="filterUid" :min="0" :controls="false" style="width: 130px" placeholder="0=全部" />
        </el-form-item>
        <el-form-item>
          <el-select v-model="bizType" style="width: 130px" @change="search">
            <el-option :value="0" label="全部类型" />
            <el-option v-for="(name, t) in bizNames" :key="t" :value="Number(t)" :label="name" />
          </el-select>
        </el-form-item>
        <el-button type="primary" @click="search">查询</el-button>
      </el-form>

      <el-table :data="rows" v-loading="loading">
        <el-table-column prop="id" label="流水号" width="90" />
        <el-table-column label="用户" min-width="130">
          <template #default="{ row }">{{ row.nickname }} <span class="sub">#{{ row.userId }}</span></template>
        </el-table-column>
        <el-table-column label="类型" width="90">
          <template #default="{ row }">
            <el-tag size="small" effect="plain">{{ bizNames[row.bizType] ?? row.bizType }}</el-tag>
          </template>
        </el-table-column>
        <el-table-column label="变动" width="100">
          <template #default="{ row }">
            <span :class="row.amount >= 0 ? 'plus' : 'minus'">{{ row.amount >= 0 ? '+' : '' }}{{ row.amount }}</span>
          </template>
        </el-table-column>
        <el-table-column prop="balanceAfter" label="余额" width="90" />
        <el-table-column prop="remark" label="备注" min-width="160" show-overflow-tooltip />
        <el-table-column label="时间" width="160">
          <template #default="{ row }">{{ new Date(row.createdAt).toLocaleString('zh-CN') }}</template>
        </el-table-column>
      </el-table>

      <el-pagination
        v-model:current-page="page"
        class="pager"
        layout="total, prev, pager, next"
        :total="total"
        :page-size="size"
        @current-change="load"
      />
    </el-card>
  </div>
</template>

<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { ElMessage, ElMessageBox } from 'element-plus'
import { api, type AdminYouzhuLogItem } from '@/api/yiora'

const bizNames: Record<number, string> = { 1: '任务', 2: '签到', 3: '运营', 4: '兑换', 5: '抽奖', 6: '解锁' }

const grantUid = ref<number>()
const grantAmount = ref(100)
const grantReason = ref('')
const granting = ref(false)

const filterUid = ref(0)
const bizType = ref(0)
const page = ref(1)
const size = 20
const total = ref(0)
const rows = ref<AdminYouzhuLogItem[]>([])
const loading = ref(false)

async function grant() {
  if (!grantUid.value || !grantAmount.value || !grantReason.value.trim()) {
    ElMessage.warning('UID、数量与原因均必填')
    return
  }
  const verb = grantAmount.value > 0 ? '发放' : '回收'
  const ok = await ElMessageBox.confirm(
    `确认给 UID ${grantUid.value} ${verb} ${Math.abs(grantAmount.value)} 忧珠?`,
    '资金操作确认',
    { type: 'warning' },
  ).catch(() => null)
  if (!ok) return
  granting.value = true
  try {
    await api.grantYouzhu(grantUid.value, grantAmount.value, grantReason.value.trim())
    ElMessage.success(`${verb}成功`)
    grantReason.value = ''
    load()
  } finally {
    granting.value = false
  }
}

async function load() {
  loading.value = true
  try {
    const data = await api.youzhuLogs({
      userId: filterUid.value || undefined,
      bizType: bizType.value,
      page: page.value,
      size,
    })
    rows.value = data.list
    total.value = data.total
  } finally {
    loading.value = false
  }
}

function search() {
  page.value = 1
  load()
}

onMounted(load)
</script>

<style scoped>
.grant-card {
  margin-bottom: 16px;
}
.sub {
  color: var(--el-text-color-secondary);
  font-size: 12px;
}
.plus {
  color: var(--el-color-success);
  font-weight: 600;
}
.minus {
  color: var(--el-color-danger);
  font-weight: 600;
}
.pager {
  margin-top: 14px;
}
</style>
