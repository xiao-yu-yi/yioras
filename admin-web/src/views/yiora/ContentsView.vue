<template>
  <el-card>
    <template #header><span>内容管理(检索 / 下架 / 恢复)</span></template>

    <el-radio-group v-model="type" class="type-tabs" @change="search">
      <el-radio-button :value="1">帖子</el-radio-button>
      <el-radio-button :value="2">评论</el-radio-button>
    </el-radio-group>

    <el-form inline @submit.prevent="search">
      <el-form-item>
        <el-input
          v-model="keyword"
          :placeholder="type === 1 ? '标题 / 正文关键词' : '评论内容关键词'"
          clearable
          style="width: 240px"
          @keyup.enter="search"
          @clear="search"
        />
      </el-form-item>
      <el-form-item>
        <el-select v-model="status" style="width: 130px" @change="search">
          <el-option v-for="s in statusOptions" :key="s.value" :value="s.value" :label="s.label" />
        </el-select>
      </el-form-item>
      <el-button type="primary" @click="search">查询</el-button>
    </el-form>

    <el-table :data="rows" v-loading="loading">
      <el-table-column prop="id" label="ID" width="70" />
      <el-table-column label="作者" width="130">
        <template #default="{ row }">{{ row.authorName }} <span class="sub">#{{ row.authorId }}</span></template>
      </el-table-column>
      <el-table-column v-if="type === 1" prop="title" label="标题" min-width="140" show-overflow-tooltip />
      <el-table-column prop="content" label="内容" min-width="220" show-overflow-tooltip />
      <el-table-column v-if="type === 2" label="所属" width="110">
        <template #default="{ row }">{{ row.bizType === 2 ? '软件' : '帖子' }} #{{ row.bizId }}</template>
      </el-table-column>
      <el-table-column label="状态" width="90">
        <template #default="{ row }">
          <el-tag :type="meta[row.status]?.tag ?? 'info'">{{ meta[row.status]?.text ?? row.status }}</el-tag>
        </template>
      </el-table-column>
      <el-table-column label="数据" width="110">
        <template #default="{ row }">赞 {{ row.likeCount }}<template v-if="type === 1"> / 看 {{ row.viewCount }}</template></template>
      </el-table-column>
      <el-table-column label="发布时间" width="160">
        <template #default="{ row }">{{ fmt(row.createdAt) }}</template>
      </el-table-column>
      <el-table-column label="操作" width="100" fixed="right">
        <template #default="{ row }">
          <el-button v-if="canTakedown(row)" size="small" type="danger" @click="openTakedown(row)">下架</el-button>
          <el-button v-else-if="canRestore(row)" size="small" type="success" @click="restore(row)">恢复</el-button>
          <span v-else class="sub">-</span>
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

    <el-dialog v-model="dialog" :title="`下架${type === 1 ? '帖子' : '评论'} #${current?.id}`" width="440px">
      <el-form label-width="80px">
        <el-form-item label="下架原因" required>
          <el-input v-model="reason" type="textarea" :rows="3" maxlength="200" show-word-limit placeholder="将通过系统通知告知作者" />
        </el-form-item>
      </el-form>
      <template #footer>
        <el-button @click="dialog = false">取消</el-button>
        <el-button type="danger" :loading="submitting" @click="submitTakedown">确认下架</el-button>
      </template>
    </el-dialog>
  </el-card>
</template>

<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { ElMessage, ElMessageBox } from 'element-plus'
import { api, type AdminContentItem } from '@/api/yiora'

type TagKind = 'success' | 'warning' | 'danger' | 'info'
const postMeta: Record<number, { text: string; tag: TagKind }> = {
  0: { text: '待审', tag: 'warning' },
  1: { text: '已发布', tag: 'success' },
  2: { text: '已驳回', tag: 'info' },
  3: { text: '已下架', tag: 'danger' },
  4: { text: '已删除', tag: 'info' },
}
const commentMeta: Record<number, { text: string; tag: TagKind }> = {
  0: { text: '待审', tag: 'warning' },
  1: { text: '正常', tag: 'success' },
  2: { text: '已屏蔽', tag: 'danger' },
}

const type = ref(1)
const keyword = ref('')
const status = ref(-1)
const page = ref(1)
const size = 20
const total = ref(0)
const rows = ref<AdminContentItem[]>([])
const loading = ref(false)

const dialog = ref(false)
const current = ref<AdminContentItem | null>(null)
const reason = ref('')
const submitting = ref(false)

const meta = computed(() => (type.value === 1 ? postMeta : commentMeta))
const statusOptions = computed(() => [
  { value: -1, label: '全部状态' },
  ...Object.entries(meta.value).map(([v, m]) => ({ value: Number(v), label: m.text })),
])

function fmt(ms: number) {
  return new Date(ms).toLocaleString('zh-CN')
}
function canTakedown(row: AdminContentItem) {
  return row.status === 1
}
function canRestore(row: AdminContentItem) {
  return (type.value === 1 && row.status === 3) || (type.value === 2 && row.status === 2)
}

async function load() {
  loading.value = true
  try {
    const data = await api.contents({ type: type.value, keyword: keyword.value.trim(), status: status.value, page: page.value, size })
    rows.value = data.list
    total.value = data.total
  } finally {
    loading.value = false
  }
}

function search() {
  status.value = statusOptions.value.some((s) => s.value === status.value) ? status.value : -1
  page.value = 1
  load()
}

function openTakedown(row: AdminContentItem) {
  current.value = row
  reason.value = ''
  dialog.value = true
}

async function submitTakedown() {
  if (!current.value) return
  if (!reason.value.trim()) {
    ElMessage.warning('请填写下架原因')
    return
  }
  submitting.value = true
  try {
    await api.takedownContent(type.value, current.value.id, 1, reason.value.trim())
    ElMessage.success('已下架并通知作者')
    dialog.value = false
    load()
  } finally {
    submitting.value = false
  }
}

async function restore(row: AdminContentItem) {
  const ok = await ElMessageBox.confirm(`确认恢复展示 #${row.id}?`, '恢复', { type: 'warning' }).catch(() => null)
  if (!ok) return
  await api.takedownContent(type.value, row.id, 0, '')
  ElMessage.success('已恢复')
  load()
}

onMounted(load)
</script>

<style scoped>
.type-tabs {
  margin-bottom: 14px;
}
.sub {
  color: #909399;
  font-size: 12px;
}
.pager {
  margin-top: 14px;
  justify-content: flex-end;
}
</style>
