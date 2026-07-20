<template>
  <el-card>
    <template #header><span>用户管理(搜索 / 禁言 / 封禁 / 恢复)</span></template>

    <el-form inline @submit.prevent="search">
      <el-form-item>
        <el-input
          v-model="keyword"
          placeholder="昵称 / 展示编号 / 邮箱"
          clearable
          style="width: 240px"
          @keyup.enter="search"
          @clear="search"
        />
      </el-form-item>
      <el-form-item>
        <el-select v-model="status" style="width: 130px" @change="search">
          <el-option :value="0" label="全部状态" />
          <el-option :value="1" label="正常" />
          <el-option :value="2" label="禁言中" />
          <el-option :value="3" label="封禁中" />
          <el-option :value="4" label="已注销" />
        </el-select>
      </el-form-item>
      <el-button type="primary" @click="search">查询</el-button>
    </el-form>

    <el-table :data="rows" v-loading="loading">
      <el-table-column prop="userId" label="UID" width="80" />
      <el-table-column label="用户" min-width="160">
        <template #default="{ row }">
          <div class="user-cell">
            <el-avatar :size="28" :src="row.avatar">{{ row.nickname[0] }}</el-avatar>
            <div>
              <div>{{ row.nickname }}</div>
              <div class="sub">{{ row.displayNo }}</div>
            </div>
          </div>
        </template>
      </el-table-column>
      <el-table-column prop="email" label="邮箱" min-width="170" />
      <el-table-column label="等级" width="70">
        <template #default="{ row }">Lv.{{ row.level }}</template>
      </el-table-column>
      <el-table-column label="状态" width="90">
        <template #default="{ row }">
          <el-tag :type="statusMeta[row.status]?.tag ?? 'info'">{{ statusMeta[row.status]?.text ?? row.status }}</el-tag>
        </template>
      </el-table-column>
      <el-table-column label="注册时间" width="160">
        <template #default="{ row }">{{ fmt(row.createdAt) }}</template>
      </el-table-column>
      <el-table-column label="最近登录" width="160">
        <template #default="{ row }">{{ row.lastLoginAt ? fmt(row.lastLoginAt) : '从未登录' }}</template>
      </el-table-column>
      <el-table-column label="操作" width="100" fixed="right">
        <template #default="{ row }">
          <el-button v-if="row.status !== 4" size="small" type="warning" @click="openBan(row)">处置</el-button>
          <span v-else class="sub">不可操作</span>
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

    <el-dialog v-model="dialog" :title="`处置用户「${current?.nickname}」(UID ${current?.userId})`" width="440px">
      <el-form label-width="90px">
        <el-form-item label="处置动作">
          <el-select v-model="action" style="width: 100%">
            <el-option :value="2" label="禁言(不能发帖/评论/私信,可浏览)" />
            <el-option :value="3" label="封禁(全站不可用,吊销登录态)" />
            <el-option :value="0" label="恢复正常" />
          </el-select>
        </el-form-item>
        <el-form-item v-if="action !== 0" label="时长(天)">
          <el-input-number v-model="days" :min="0" :max="3650" />
          <span class="sub" style="margin-left: 8px">0 = 永久</span>
        </el-form-item>
      </el-form>
      <template #footer>
        <el-button @click="dialog = false">取消</el-button>
        <el-button type="danger" :loading="submitting" @click="submit">确认执行</el-button>
      </template>
    </el-dialog>
  </el-card>
</template>

<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { ElMessage, ElMessageBox } from 'element-plus'
import { api, type AdminUserItem } from '@/api/yiora'

const statusMeta: Record<number, { text: string; tag: 'success' | 'warning' | 'danger' | 'info' }> = {
  1: { text: '正常', tag: 'success' },
  2: { text: '禁言中', tag: 'warning' },
  3: { text: '封禁中', tag: 'danger' },
  4: { text: '已注销', tag: 'info' },
}

const keyword = ref('')
const status = ref(0)
const page = ref(1)
const size = 20
const total = ref(0)
const rows = ref<AdminUserItem[]>([])
const loading = ref(false)

const dialog = ref(false)
const current = ref<AdminUserItem | null>(null)
const action = ref(2)
const days = ref(1)
const submitting = ref(false)

function fmt(ms: number) {
  return new Date(ms).toLocaleString('zh-CN')
}

async function load() {
  loading.value = true
  try {
    const data = await api.users({ keyword: keyword.value.trim(), status: status.value, page: page.value, size })
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

function openBan(row: AdminUserItem) {
  current.value = row
  action.value = row.status === 1 ? 2 : 0
  days.value = 1
  dialog.value = true
}

async function submit() {
  if (!current.value) return
  const names: Record<number, string> = { 0: '恢复', 2: '禁言', 3: '封禁' }
  const ok = await ElMessageBox.confirm(
    `确认对「${current.value.nickname}」执行${names[action.value]}?`,
    '二次确认',
    { type: 'warning' },
  ).catch(() => null)
  if (!ok) return
  submitting.value = true
  try {
    await api.banUser(current.value.userId, action.value, action.value === 0 ? 0 : days.value)
    ElMessage.success(`${names[action.value]}已执行`)
    dialog.value = false
    load()
  } finally {
    submitting.value = false
  }
}

onMounted(load)
</script>

<style scoped>
.user-cell {
  display: flex;
  align-items: center;
  gap: 8px;
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
