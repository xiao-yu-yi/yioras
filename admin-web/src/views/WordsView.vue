<template>
  <el-card>
    <template #header>
      <div class="bar">
        <span>敏感词库(改动即时生效,无需重启)</span>
        <el-button type="primary" @click="openEdit()">新增敏感词</el-button>
      </div>
    </template>

    <el-form inline @submit.prevent="search">
      <el-form-item>
        <el-input v-model="keyword" placeholder="词面模糊搜索" clearable style="width: 200px" @keyup.enter="search" @clear="search" />
      </el-form-item>
      <el-form-item>
        <el-select v-model="category" style="width: 120px" @change="search">
          <el-option :value="0" label="全部分类" />
          <el-option v-for="(name, c) in catNames" :key="c" :value="Number(c)" :label="name" />
        </el-select>
      </el-form-item>
      <el-form-item>
        <el-select v-model="level" style="width: 130px" @change="search">
          <el-option :value="0" label="全部等级" />
          <el-option v-for="(m, lv) in levelMeta" :key="lv" :value="Number(lv)" :label="m.text" />
        </el-select>
      </el-form-item>
      <el-form-item>
        <el-select v-model="status" style="width: 110px" @change="search">
          <el-option :value="-1" label="全部状态" />
          <el-option :value="1" label="启用" />
          <el-option :value="0" label="停用" />
        </el-select>
      </el-form-item>
      <el-button type="primary" @click="search">查询</el-button>
    </el-form>

    <el-table :data="rows" v-loading="loading">
      <el-table-column prop="id" label="ID" width="70" />
      <el-table-column prop="word" label="敏感词" min-width="160" />
      <el-table-column label="分类" width="90">
        <template #default="{ row }">{{ catNames[row.category] ?? '其他' }}</template>
      </el-table-column>
      <el-table-column label="处置等级" width="110">
        <template #default="{ row }">
          <el-tag :type="levelMeta[row.level]?.tag ?? 'info'">{{ levelMeta[row.level]?.text ?? row.level }}</el-tag>
        </template>
      </el-table-column>
      <el-table-column label="状态" width="90">
        <template #default="{ row }">
          <el-tag :type="row.status === 1 ? 'success' : 'info'">{{ row.status === 1 ? '启用' : '停用' }}</el-tag>
        </template>
      </el-table-column>
      <el-table-column label="添加时间" width="160">
        <template #default="{ row }">{{ fmt(row.createdAt) }}</template>
      </el-table-column>
      <el-table-column label="操作" width="150" fixed="right">
        <template #default="{ row }">
          <el-button size="small" @click="openEdit(row)">编辑</el-button>
          <el-button size="small" type="danger" @click="remove(row)">删除</el-button>
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

    <el-dialog v-model="dialog" :title="form.id ? `编辑「${form.word}」` : '新增敏感词'" width="440px">
      <el-form label-width="90px">
        <el-form-item v-if="!form.id" label="敏感词" required>
          <el-input v-model="form.word" maxlength="64" placeholder="大小写不敏感,子串匹配" />
        </el-form-item>
        <el-form-item label="分类">
          <el-select v-model="form.category" style="width: 100%">
            <el-option v-for="(name, c) in catNames" :key="c" :value="Number(c)" :label="name" />
          </el-select>
        </el-form-item>
        <el-form-item label="处置等级">
          <el-select v-model="form.level" style="width: 100%">
            <el-option :value="1" label="直接拦截(发布失败)" />
            <el-option :value="2" label="转人工审核(先隐藏)" />
            <el-option :value="3" label="替换为 *(照常发布)" />
          </el-select>
        </el-form-item>
        <el-form-item v-if="form.id" label="状态">
          <el-switch v-model="enabled" active-text="启用" inactive-text="停用" />
        </el-form-item>
      </el-form>
      <template #footer>
        <el-button @click="dialog = false">取消</el-button>
        <el-button type="primary" :loading="saving" @click="save">保存并生效</el-button>
      </template>
    </el-dialog>
  </el-card>
</template>

<script setup lang="ts">
import { onMounted, reactive, ref } from 'vue'
import { ElMessage, ElMessageBox } from 'element-plus'
import { api, type AdminWordItem } from '../api'

type TagKind = 'success' | 'warning' | 'danger' | 'info'
const catNames: Record<number, string> = { 1: '政治', 2: '色情', 3: '辱骂', 4: '广告', 5: '其他' }
const levelMeta: Record<number, { text: string; tag: TagKind }> = {
  1: { text: '直接拦截', tag: 'danger' },
  2: { text: '转人审', tag: 'warning' },
  3: { text: '打码', tag: 'info' },
}

const keyword = ref('')
const category = ref(0)
const level = ref(0)
const status = ref(-1)
const page = ref(1)
const size = 20
const total = ref(0)
const rows = ref<AdminWordItem[]>([])
const loading = ref(false)

const dialog = ref(false)
const saving = ref(false)
const enabled = ref(true)
const form = reactive<Partial<AdminWordItem>>({})

function fmt(ms: number) {
  return new Date(ms).toLocaleString('zh-CN')
}

async function load() {
  loading.value = true
  try {
    const data = await api.words({
      keyword: keyword.value.trim(),
      category: category.value,
      level: level.value,
      status: status.value,
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

function openEdit(row?: AdminWordItem) {
  Object.assign(form, row ?? { id: 0, word: '', category: 5, level: 1, status: 1 })
  enabled.value = (row?.status ?? 1) === 1
  dialog.value = true
}

async function save() {
  if (!form.id && !form.word?.trim()) {
    ElMessage.warning('请输入敏感词')
    return
  }
  saving.value = true
  try {
    await api.saveWord({ ...form, word: form.word?.trim(), status: enabled.value ? 1 : 0 })
    ElMessage.success('已保存,过滤器即时生效')
    dialog.value = false
    load()
  } finally {
    saving.value = false
  }
}

async function remove(row: AdminWordItem) {
  const ok = await ElMessageBox.confirm(`确认删除敏感词「${row.word}」?删除后立即放行该词。`, '删除', {
    type: 'warning',
  }).catch(() => null)
  if (!ok) return
  await api.deleteWord(row.id)
  ElMessage.success('已删除并生效')
  load()
}

onMounted(load)
</script>

<style scoped>
.bar {
  display: flex;
  justify-content: space-between;
  align-items: center;
}
.pager {
  margin-top: 14px;
  justify-content: flex-end;
}
</style>
