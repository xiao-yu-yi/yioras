<template>
  <el-card>
    <template #header><span>举报处理(核实 / 快捷处置 / 结单)</span></template>

    <el-form inline>
      <el-form-item>
        <el-select v-model="status" style="width: 130px" @change="search">
          <el-option :value="0" label="待处理" />
          <el-option :value="1" label="已处理" />
          <el-option :value="2" label="已驳回" />
          <el-option :value="-1" label="全部" />
        </el-select>
      </el-form-item>
      <el-form-item>
        <el-select v-model="targetType" style="width: 130px" @change="search">
          <el-option :value="0" label="全部类型" />
          <el-option v-for="(name, t) in typeNames" :key="t" :value="Number(t)" :label="name" />
        </el-select>
      </el-form-item>
    </el-form>

    <el-table :data="rows" v-loading="loading">
      <el-table-column prop="id" label="ID" width="60" />
      <el-table-column label="举报人" width="120">
        <template #default="{ row }">{{ row.reporterName }} <span class="sub">#{{ row.reporterId }}</span></template>
      </el-table-column>
      <el-table-column label="分类" width="80">
        <template #default="{ row }">
          <el-tag type="danger" effect="plain">{{ catNames[row.category] ?? '其他' }}</el-tag>
        </template>
      </el-table-column>
      <el-table-column label="目标" min-width="220" show-overflow-tooltip>
        <template #default="{ row }">
          <el-tag size="small">{{ typeNames[row.targetType] }} #{{ row.targetId }}</el-tag>
          <span class="brief">{{ row.targetBrief }}</span>
        </template>
      </el-table-column>
      <el-table-column prop="reason" label="补充说明" min-width="150" show-overflow-tooltip />
      <el-table-column label="证据" width="70">
        <template #default="{ row }">
          <el-link v-if="row.images.length" type="primary" :href="row.images[0]" target="_blank">{{ row.images.length }} 图</el-link>
          <span v-else class="sub">-</span>
        </template>
      </el-table-column>
      <el-table-column label="状态" width="90">
        <template #default="{ row }">
          <el-tag :type="(['warning', 'success', 'info'] as const)[row.status]">{{ ['待处理', '已处理', '已驳回'][row.status] }}</el-tag>
        </template>
      </el-table-column>
      <el-table-column label="举报时间" width="160">
        <template #default="{ row }">{{ fmt(row.createdAt) }}</template>
      </el-table-column>
      <el-table-column label="操作" width="90" fixed="right">
        <template #default="{ row }">
          <el-button v-if="row.status === 0" size="small" type="primary" @click="open(row)">处理</el-button>
          <span v-else class="sub">已结单</span>
        </template>
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

    <el-dialog v-model="dialog" :title="`处理举报 #${current?.id}`" width="560px">
      <template v-if="current">
        <el-descriptions :column="1" border>
          <el-descriptions-item label="目标">
            {{ typeNames[current.targetType] }} #{{ current.targetId }} — {{ current.targetBrief }}
          </el-descriptions-item>
          <el-descriptions-item label="举报分类">{{ catNames[current.category] ?? '其他' }}</el-descriptions-item>
          <el-descriptions-item label="补充说明">{{ current.reason || '(无)' }}</el-descriptions-item>
          <el-descriptions-item v-if="current.images.length" label="证据图">
            <el-link v-for="(img, i) in current.images" :key="img" type="primary" :href="img" target="_blank" class="img-link">
              图{{ i + 1 }}
            </el-link>
          </el-descriptions-item>
        </el-descriptions>

        <div class="quick">
          <span class="quick-label">快捷处置:</span>
          <template v-if="current.targetType === 1 || current.targetType === 2">
            <el-button v-if="current.targetStatus === 1" size="small" type="danger" :loading="acting" @click="takedownTarget">
              下架该{{ typeNames[current.targetType] }}
            </el-button>
            <span v-else class="sub">目标当前不可下架(已下架/待审/已删)</span>
          </template>
          <template v-else-if="current.targetType === 3">
            <el-button size="small" type="warning" :loading="acting" @click="banTarget(2, 3)">禁言 3 天</el-button>
            <el-button size="small" type="danger" :loading="acting" @click="banTarget(3, 7)">封禁 7 天</el-button>
          </template>
          <span v-else class="sub">该类型无快捷动作,可在对应模块处置后结单</span>
        </div>
      </template>
      <template #footer>
        <el-button :loading="closing" @click="close(2)">不成立·驳回</el-button>
        <el-button type="primary" :loading="closing" @click="close(1)">违规成立·结单</el-button>
      </template>
    </el-dialog>
  </el-card>
</template>

<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { ElMessage } from 'element-plus'
import { api, type AdminReportItem } from '@/api/yiora'

const typeNames: Record<number, string> = { 1: '帖子', 2: '评论', 3: '用户', 4: '私信', 5: '软件' }
const catNames: Record<number, string> = { 1: '违法', 2: '色情', 3: '诈骗', 4: '侵权', 5: '其他' }

const status = ref(0)
const targetType = ref(0)
const page = ref(1)
const size = 20
const total = ref(0)
const rows = ref<AdminReportItem[]>([])
const loading = ref(false)

const dialog = ref(false)
const current = ref<AdminReportItem | null>(null)
const acting = ref(false)
const closing = ref(false)

function fmt(ms: number) {
  return new Date(ms).toLocaleString('zh-CN')
}

async function load() {
  loading.value = true
  try {
    const data = await api.reports({ status: status.value, targetType: targetType.value, page: page.value, size })
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

function open(row: AdminReportItem) {
  current.value = row
  dialog.value = true
}

// 快捷下架帖子/评论:下架原因带上举报分类,作者会收到通知
async function takedownTarget() {
  if (!current.value) return
  acting.value = true
  try {
    await api.takedownContent(
      current.value.targetType,
      current.value.targetId,
      1,
      `经举报核实违规(${catNames[current.value.category] ?? '其他'})`,
    )
    ElMessage.success('已下架,请继续结单')
    current.value.targetStatus = current.value.targetType === 1 ? 3 : 2
  } finally {
    acting.value = false
  }
}

async function banTarget(action: number, days: number) {
  if (!current.value) return
  acting.value = true
  try {
    await api.banUser(current.value.targetId, action, days)
    ElMessage.success(`${action === 2 ? '禁言' : '封禁'}已执行,请继续结单`)
  } finally {
    acting.value = false
  }
}

async function close(action: number) {
  if (!current.value) return
  closing.value = true
  try {
    await api.handleReport(current.value.id, action)
    ElMessage.success(action === 1 ? '已结单并通知举报人' : '已驳回并通知举报人')
    dialog.value = false
    load()
  } finally {
    closing.value = false
  }
}

onMounted(load)
</script>

<style scoped>
.sub {
  color: #909399;
  font-size: 12px;
}
.brief {
  margin-left: 6px;
}
.pager {
  margin-top: 14px;
  justify-content: flex-end;
}
.quick {
  margin-top: 16px;
  display: flex;
  align-items: center;
  gap: 8px;
}
.quick-label {
  font-weight: 600;
}
.img-link {
  margin-right: 10px;
}
</style>
