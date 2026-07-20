<template>
  <el-card>
    <template #header>
      <div class="bar">
        <span>首页公告 Banner</span>
        <el-button type="primary" @click="openEdit()">新建 Banner</el-button>
      </div>
    </template>

    <el-table :data="rows" v-loading="loading">
      <el-table-column prop="id" label="ID" width="70" />
      <el-table-column prop="title" label="标题" min-width="140" />
      <el-table-column label="图片" width="120">
        <template #default="{ row }">
          <el-link :href="row.image" target="_blank" type="primary">查看</el-link>
        </template>
      </el-table-column>
      <el-table-column label="跳转" width="130">
        <template #default="{ row }">{{ linkName(row.linkType) }} {{ row.linkValue }}</template>
      </el-table-column>
      <el-table-column prop="sort" label="排序" width="70" />
      <el-table-column label="状态" width="90">
        <template #default="{ row }">
          <el-tag :type="row.status === 1 ? 'success' : 'info'">{{ row.status === 1 ? '上线' : '下线' }}</el-tag>
        </template>
      </el-table-column>
      <el-table-column label="投放时段" min-width="200">
        <template #default="{ row }">{{ fmtRange(row.startAt, row.endAt) }}</template>
      </el-table-column>
      <el-table-column label="操作" width="150" fixed="right">
        <template #default="{ row }">
          <el-button size="small" @click="openEdit(row)">编辑</el-button>
          <el-button size="small" type="danger" @click="remove(row)">删除</el-button>
        </template>
      </el-table-column>
    </el-table>

    <el-dialog v-model="dialog" :title="form.id ? '编辑 Banner' : '新建 Banner'" width="520px">
      <el-form :model="form" label-width="80px">
        <el-form-item label="标题" required>
          <el-input v-model="form.title" maxlength="50" show-word-limit />
        </el-form-item>
        <el-form-item label="图片" required>
          <UploadImage :model-value="form.image ?? ''" kind="banner" @update:model-value="form.image = $event" />
        </el-form-item>
        <el-form-item label="跳转类型">
          <el-select v-model="form.linkType" style="width: 100%">
            <el-option :value="0" label="无跳转" />
            <el-option :value="1" label="帖子" />
            <el-option :value="2" label="H5 链接" />
            <el-option :value="3" label="圈子" />
          </el-select>
        </el-form-item>
        <el-form-item v-if="form.linkType !== 0" label="跳转值">
          <el-input v-model="form.linkValue" placeholder="帖子ID / URL / 圈子ID" />
        </el-form-item>
        <el-form-item label="排序">
          <el-input-number v-model="form.sort" :min="0" />
        </el-form-item>
        <el-form-item label="状态">
          <el-switch v-model="online" active-text="上线" inactive-text="下线" />
        </el-form-item>
        <el-form-item label="投放时段">
          <el-date-picker
            v-model="range"
            type="datetimerange"
            start-placeholder="开始(可空)"
            end-placeholder="结束(可空)"
            style="width: 100%"
          />
        </el-form-item>
      </el-form>
      <template #footer>
        <el-button @click="dialog = false">取消</el-button>
        <el-button type="primary" :loading="saving" @click="save">保存</el-button>
      </template>
    </el-dialog>
  </el-card>
</template>

<script setup lang="ts">
import { onMounted, reactive, ref } from 'vue'
import { ElMessage, ElMessageBox } from 'element-plus'
import { api, type BannerItem } from '@/api/yiora'
import UploadImage from '@/components/UploadImage.vue'

const rows = ref<BannerItem[]>([])
const loading = ref(false)
const dialog = ref(false)
const saving = ref(false)
const online = ref(true)
const range = ref<[Date, Date] | null>(null)
const form = reactive<Partial<BannerItem>>({})

function linkName(t: number) {
  return { 0: '无', 1: '帖子', 2: 'H5', 3: '圈子' }[t] ?? '?'
}
function fmtRange(s: number, e: number) {
  const f = (ms: number) => (ms ? new Date(ms).toLocaleString('zh-CN') : '不限')
  return `${f(s)} ~ ${f(e)}`
}

async function load() {
  loading.value = true
  try {
    rows.value = await api.banners()
  } finally {
    loading.value = false
  }
}

function openEdit(row?: BannerItem) {
  Object.assign(form, row ?? { id: 0, title: '', image: '', linkType: 0, linkValue: '', sort: 0, status: 1 })
  online.value = (row?.status ?? 1) === 1
  range.value = row?.startAt && row?.endAt ? [new Date(row.startAt), new Date(row.endAt)] : null
  dialog.value = true
}

async function save() {
  if (!form.title?.trim() || !form.image) {
    ElMessage.warning('标题与图片必填')
    return
  }
  saving.value = true
  try {
    await api.saveBanner({
      ...form,
      status: online.value ? 1 : 0,
      startAt: range.value?.[0]?.getTime() ?? 0,
      endAt: range.value?.[1]?.getTime() ?? 0,
    })
    ElMessage.success('已保存')
    dialog.value = false
    load()
  } finally {
    saving.value = false
  }
}

async function remove(row: BannerItem) {
  const ok = await ElMessageBox.confirm(`确认删除 Banner「${row.title}」?`, '删除', { type: 'warning' }).catch(() => null)
  if (!ok) return
  await api.deleteBanner(row.id)
  ElMessage.success('已删除')
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
</style>
