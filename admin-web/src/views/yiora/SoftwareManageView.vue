<template>
  <el-card>
    <template #header>
      <div class="bar">
        <span>软件库管理(全状态检索,新软件/新版本审核在审核工作台)</span>
        <div class="filters">
          <el-select v-model="status" style="width: 130px" @change="load(1)">
            <el-option label="全部状态" :value="-1" />
            <el-option label="待审核" :value="0" />
            <el-option label="已上架" :value="1" />
            <el-option label="已驳回" :value="2" />
            <el-option label="已下架" :value="3" />
          </el-select>
          <el-input
            v-model="kw"
            placeholder="软件名/简介关键词"
            style="width: 220px"
            clearable
            @keyup.enter="load(1)"
          />
          <el-button type="primary" @click="load(1)">搜索</el-button>
        </div>
      </div>
    </template>

    <el-table :data="rows" v-loading="loading">
      <el-table-column label="软件" min-width="200">
        <template #default="{ row }">
          <div class="soft">
            <el-image :src="row.logo" fit="cover" class="logo" />
            <div>
              <div class="name">{{ row.name }}</div>
              <div class="sub">{{ row.type === 1 ? '应用' : '游戏' }} · {{ row.categoryName || '未分类' }}</div>
            </div>
          </div>
        </template>
      </el-table-column>
      <el-table-column prop="nickname" label="发布者" width="130" show-overflow-tooltip />
      <el-table-column prop="downloadCount" label="下载" width="80" />
      <el-table-column prop="commentCount" label="评论" width="80" />
      <el-table-column label="状态" width="100">
        <template #default="{ row }">
          <el-tag :type="statusTag(row.status)">{{ statusName(row.status) }}</el-tag>
        </template>
      </el-table-column>
      <el-table-column label="发布时间" width="170">
        <template #default="{ row }">{{ new Date(row.createdAt).toLocaleString('zh-CN') }}</template>
      </el-table-column>
      <el-table-column label="操作" width="220" fixed="right">
        <template #default="{ row }">
          <el-button size="small" @click="showVersions(row)">版本</el-button>
          <el-button v-if="row.status === 1" size="small" type="danger" @click="takedown(row)">下架</el-button>
          <el-button v-if="row.status === 3" size="small" type="success" @click="restore(row)">恢复上架</el-button>
        </template>
      </el-table-column>
    </el-table>

    <el-pagination
      v-model:current-page="page"
      class="pager"
      layout="total, prev, pager, next"
      :total="total"
      :page-size="20"
      @current-change="load"
    />

    <el-drawer v-model="drawer" :title="`版本历史 - ${current?.name ?? ''}`" size="420px">
      <el-table :data="versions" v-loading="vloading" size="small">
        <el-table-column prop="version" label="版本" width="90" />
        <el-table-column prop="size" label="大小" width="80" />
        <el-table-column prop="channel" label="渠道" width="80" />
        <el-table-column label="状态" width="80">
          <template #default="{ row }">
            <el-tag size="small" :type="row.status === 1 ? 'success' : row.status === 0 ? 'warning' : 'danger'">
              {{ { 0: '待审', 1: '发布', 2: '驳回' }[row.status as 0 | 1 | 2] ?? row.status }}
            </el-tag>
          </template>
        </el-table-column>
        <el-table-column label="提交时间" min-width="120">
          <template #default="{ row }">{{ new Date(row.createdAt).toLocaleDateString('zh-CN') }}</template>
        </el-table-column>
      </el-table>
    </el-drawer>
  </el-card>
</template>

<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { ElMessage, ElMessageBox } from 'element-plus'
import { api, type AdminSoftwareItem, type AdminSoftwareVersionItem } from '@/api/yiora'

const rows = ref<AdminSoftwareItem[]>([])
const total = ref(0)
const page = ref(1)
const kw = ref('')
const status = ref(-1)
const loading = ref(false)

const drawer = ref(false)
const current = ref<AdminSoftwareItem | null>(null)
const versions = ref<AdminSoftwareVersionItem[]>([])
const vloading = ref(false)

function statusName(s: number) {
  return { 0: '待审核', 1: '已上架', 2: '已驳回', 3: '已下架' }[s as 0 | 1 | 2 | 3] ?? `状态${s}`
}
function statusTag(s: number) {
  return ({ 0: 'warning', 1: 'success', 2: 'info', 3: 'danger' } as const)[s as 0 | 1 | 2 | 3] ?? 'info'
}

async function load(p: number) {
  page.value = p
  loading.value = true
  try {
    const data = await api.softwares({ kw: kw.value.trim(), status: status.value, page: p })
    rows.value = data.list
    total.value = data.total
  } finally {
    loading.value = false
  }
}

async function showVersions(row: AdminSoftwareItem) {
  current.value = row
  drawer.value = true
  vloading.value = true
  try {
    versions.value = await api.softwareVersions(row.id)
  } finally {
    vloading.value = false
  }
}

async function takedown(row: AdminSoftwareItem) {
  const input = await ElMessageBox.prompt(`下架「${row.name}」,原因将通知发布者:`, '下架软件', {
    inputPlaceholder: '如: 存在恶意行为 / 侵权投诉',
    inputValidator: (v: string) => (v?.trim() ? true : '原因必填'),
    type: 'warning',
  }).catch(() => null)
  if (!input) return
  await api.softwareOps(row.id, 1, input.value.trim())
  ElMessage.success('已下架并通知发布者')
  load(page.value)
}

async function restore(row: AdminSoftwareItem) {
  const ok = await ElMessageBox.confirm(`恢复上架「${row.name}」?`, '恢复', { type: 'info' }).catch(() => null)
  if (!ok) return
  await api.softwareOps(row.id, 0)
  ElMessage.success('已恢复上架')
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
.filters {
  display: flex;
  gap: 8px;
}
.soft {
  display: flex;
  align-items: center;
  gap: 10px;
}
.logo {
  width: 40px;
  height: 40px;
  border-radius: 10px;
  flex: none;
}
.name {
  font-weight: 600;
}
.sub {
  font-size: 12px;
  color: var(--el-text-color-secondary);
}
.pager {
  margin-top: 14px;
  justify-content: flex-end;
}
</style>
