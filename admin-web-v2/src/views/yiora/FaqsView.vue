<template>
  <el-card>
    <template #header>
      <div class="bar">
        <span>AI 管家 FAQ 词条(按优先级升序命中,改动即时生效)</span>
        <el-button type="primary" @click="openEdit()">新增词条</el-button>
      </div>
    </template>

    <el-table :data="rows" v-loading="loading">
      <el-table-column prop="id" label="ID" width="70" />
      <el-table-column label="关键词" min-width="180">
        <template #default="{ row }">
          <el-tag v-for="kw in row.keywords.split('|')" :key="kw" size="small" class="kw">{{ kw }}</el-tag>
        </template>
      </el-table-column>
      <el-table-column prop="reply" label="回复内容" min-width="240" show-overflow-tooltip />
      <el-table-column prop="priority" label="优先级" width="80" />
      <el-table-column label="状态" width="90">
        <template #default="{ row }">
          <el-tag :type="row.status === 1 ? 'success' : 'info'">{{ row.status === 1 ? '启用' : '停用' }}</el-tag>
        </template>
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
      :page-size="20"
      @current-change="load"
    />

    <el-dialog v-model="dialog" :title="form.id ? '编辑词条' : '新增词条'" width="520px">
      <el-form label-width="80px">
        <el-form-item label="关键词" required>
          <el-input v-model="form.keywords" placeholder="竖线分隔,命中任一即回复,如: 签到|打卡" />
        </el-form-item>
        <el-form-item label="回复内容" required>
          <el-input v-model="form.reply" type="textarea" :rows="4" maxlength="1000" show-word-limit />
        </el-form-item>
        <el-form-item label="优先级">
          <el-input-number v-model="form.priority" :min="1" :max="9999" />
          <span class="sub" style="margin-left: 8px">数值小的先匹配</span>
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
import { api, type AdminFaqItem } from '@/api/yiora'

const page = ref(1)
const total = ref(0)
const rows = ref<AdminFaqItem[]>([])
const loading = ref(false)

const dialog = ref(false)
const saving = ref(false)
const enabled = ref(true)
const form = reactive<Partial<AdminFaqItem>>({})

async function load() {
  loading.value = true
  try {
    const data = await api.faqs(page.value)
    rows.value = data.list
    total.value = data.total
  } finally {
    loading.value = false
  }
}

function openEdit(row?: AdminFaqItem) {
  Object.assign(form, row ?? { id: 0, keywords: '', reply: '', priority: 100, status: 1 })
  enabled.value = (row?.status ?? 1) === 1
  dialog.value = true
}

async function save() {
  if (!form.keywords?.trim() || !form.reply?.trim()) {
    ElMessage.warning('关键词与回复内容必填')
    return
  }
  saving.value = true
  try {
    await api.saveFaq({ ...form, status: enabled.value ? 1 : 0 })
    ElMessage.success('已保存,机器人即时生效')
    dialog.value = false
    load()
  } finally {
    saving.value = false
  }
}

async function remove(row: AdminFaqItem) {
  const ok = await ElMessageBox.confirm('确认删除该词条?删除后该关键词将回落到兜底话术。', '删除', {
    type: 'warning',
  }).catch(() => null)
  if (!ok) return
  await api.deleteFaq(row.id)
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
.kw {
  margin-right: 4px;
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
