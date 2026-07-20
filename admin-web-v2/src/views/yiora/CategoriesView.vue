<template>
  <el-card>
    <template #header>
      <div class="bar">
        <span>软件分类(应用/游戏两榜,停用后发布表单不再出现)</span>
        <el-button type="primary" @click="openEdit()">新增分类</el-button>
      </div>
    </template>

    <el-table :data="rows" v-loading="loading">
      <el-table-column prop="id" label="ID" width="70" />
      <el-table-column label="所属" width="90">
        <template #default="{ row }">
          <el-tag :type="row.type === 1 ? 'primary' : 'warning'" effect="plain">{{ row.type === 1 ? '应用' : '游戏' }}</el-tag>
        </template>
      </el-table-column>
      <el-table-column prop="name" label="分类名" min-width="140" />
      <el-table-column prop="sort" label="排序" width="80" />
      <el-table-column label="状态" width="90">
        <template #default="{ row }">
          <el-tag :type="row.status === 1 ? 'success' : 'info'">{{ row.status === 1 ? '启用' : '停用' }}</el-tag>
        </template>
      </el-table-column>
      <el-table-column label="操作" width="90" fixed="right">
        <template #default="{ row }">
          <el-button size="small" @click="openEdit(row)">编辑</el-button>
        </template>
      </el-table-column>
    </el-table>

    <el-dialog v-model="dialog" :title="form.id ? '编辑分类' : '新增分类'" width="420px">
      <el-form label-width="80px">
        <el-form-item label="所属">
          <el-select v-model="form.type" style="width: 100%">
            <el-option :value="1" label="应用" />
            <el-option :value="2" label="游戏" />
          </el-select>
        </el-form-item>
        <el-form-item label="分类名" required>
          <el-input v-model="form.name" maxlength="20" show-word-limit />
        </el-form-item>
        <el-form-item label="排序">
          <el-input-number v-model="form.sort" :min="0" />
          <span class="sub" style="margin-left: 8px">小的在前</span>
        </el-form-item>
        <el-form-item label="状态">
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
import { ElMessage } from 'element-plus'
import { api, type AdminCategoryItem } from '@/api/yiora'

const rows = ref<AdminCategoryItem[]>([])
const loading = ref(false)
const dialog = ref(false)
const saving = ref(false)
const enabled = ref(true)
const form = reactive<Partial<AdminCategoryItem>>({})

async function load() {
  loading.value = true
  try {
    rows.value = await api.categories()
  } finally {
    loading.value = false
  }
}

function openEdit(row?: AdminCategoryItem) {
  Object.assign(form, row ?? { id: 0, type: 1, name: '', sort: 0 })
  enabled.value = (row?.status ?? 1) === 1
  dialog.value = true
}

async function save() {
  if (!form.name?.trim()) {
    ElMessage.warning('请输入分类名')
    return
  }
  saving.value = true
  try {
    await api.saveCategory({ ...form, name: form.name.trim(), status: enabled.value ? 1 : 0 })
    ElMessage.success('已保存并生效')
    dialog.value = false
    load()
  } finally {
    saving.value = false
  }
}

onMounted(load)
</script>

<style scoped>
.bar {
  display: flex;
  justify-content: space-between;
  align-items: center;
}
.sub {
  color: #909399;
  font-size: 12px;
}
</style>
