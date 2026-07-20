<template>
  <el-card>
    <template #header>
      <div class="bar">
        <span>后台账号管理</span>
        <el-button type="primary" @click="openCreate">新建账号</el-button>
      </div>
    </template>

    <el-table :data="rows" v-loading="loading">
      <el-table-column prop="id" label="ID" width="70" />
      <el-table-column prop="username" label="用户名" min-width="130" />
      <el-table-column prop="roleName" label="角色" width="130" />
      <el-table-column label="状态" width="90">
        <template #default="{ row }">
          <el-tag :type="row.status === 1 ? 'success' : 'info'">{{ row.status === 1 ? '正常' : '已停用' }}</el-tag>
        </template>
      </el-table-column>
      <el-table-column label="待改密" width="90">
        <template #default="{ row }">
          <el-tag v-if="row.mustChangePwd" type="warning">是</el-tag>
          <span v-else class="sub">否</span>
        </template>
      </el-table-column>
      <el-table-column label="最近登录" width="170">
        <template #default="{ row }">{{ row.lastLoginAt ? fmt(row.lastLoginAt) : '从未登录' }}</template>
      </el-table-column>
      <el-table-column label="操作" width="100" fixed="right">
        <template #default="{ row }">
          <el-button v-if="row.username !== myName" size="small" @click="openEdit(row)">管理</el-button>
          <span v-else class="sub">当前账号</span>
        </template>
      </el-table-column>
    </el-table>

    <el-dialog v-model="createDialog" title="新建后台账号" width="440px">
      <el-form label-width="90px">
        <el-form-item label="用户名" required>
          <el-input v-model="createForm.username" maxlength="30" />
        </el-form-item>
        <el-form-item label="初始密码" required>
          <el-input v-model="createForm.password" placeholder="8-64 位,含字母和数字;对方首登强制改密" show-password />
        </el-form-item>
        <el-form-item label="角色" required>
          <el-select v-model="createForm.roleId" style="width: 100%">
            <el-option v-for="r in roles" :key="r.id" :value="r.id" :label="`${r.name}(${r.perms.join('/')})`" />
          </el-select>
        </el-form-item>
      </el-form>
      <template #footer>
        <el-button @click="createDialog = false">取消</el-button>
        <el-button type="primary" :loading="saving" @click="create">创建</el-button>
      </template>
    </el-dialog>

    <el-dialog v-model="editDialog" :title="`管理账号「${current?.username}」`" width="440px">
      <el-form label-width="90px">
        <el-form-item label="角色">
          <el-select v-model="editForm.roleId" style="width: 100%">
            <el-option v-for="r in roles" :key="r.id" :value="r.id" :label="`${r.name}(${r.perms.join('/')})`" />
          </el-select>
        </el-form-item>
        <el-form-item label="状态">
          <el-switch v-model="editEnabled" active-text="正常" inactive-text="停用" />
        </el-form-item>
        <el-form-item label="重置密码">
          <el-input v-model="editForm.newPassword" placeholder="留空不重置;重置后对方首登强制改密" show-password />
        </el-form-item>
        <el-form-item label="二步验证">
          <el-checkbox v-model="editForm.resetTotp">强制解绑(对方验证器丢失时使用)</el-checkbox>
        </el-form-item>
      </el-form>
      <template #footer>
        <el-button @click="editDialog = false">取消</el-button>
        <el-button type="primary" :loading="saving" @click="save">保存</el-button>
      </template>
    </el-dialog>
  </el-card>
</template>

<script setup lang="ts">
import { onMounted, reactive, ref } from 'vue'
import { ElMessage } from 'element-plus'
import { api, type AdminAccountItem, type AdminRoleItem } from '@/api/yiora'

const myName = localStorage.getItem('yiora_admin_name') ?? ''
const rows = ref<AdminAccountItem[]>([])
const roles = ref<AdminRoleItem[]>([])
const loading = ref(false)
const saving = ref(false)

const createDialog = ref(false)
const createForm = reactive({ username: '', password: '', roleId: 0 })

const editDialog = ref(false)
const current = ref<AdminAccountItem | null>(null)
const editForm = reactive({ roleId: 0, newPassword: '', resetTotp: false })
const editEnabled = ref(true)

function fmt(ms: number) {
  return new Date(ms).toLocaleString('zh-CN')
}

async function load() {
  loading.value = true
  try {
    rows.value = await api.admins()
  } finally {
    loading.value = false
  }
}

function openCreate() {
  Object.assign(createForm, { username: '', password: '', roleId: roles.value[0]?.id ?? 0 })
  createDialog.value = true
}

async function create() {
  if (!createForm.username.trim() || !createForm.password || !createForm.roleId) {
    ElMessage.warning('请填写完整')
    return
  }
  saving.value = true
  try {
    await api.createAdmin(createForm.username.trim(), createForm.password, createForm.roleId)
    ElMessage.success('已创建,对方首次登录需修改密码')
    createDialog.value = false
    load()
  } finally {
    saving.value = false
  }
}

function openEdit(row: AdminAccountItem) {
  current.value = row
  Object.assign(editForm, { roleId: row.roleId, newPassword: '', resetTotp: false })
  editEnabled.value = row.status === 1
  editDialog.value = true
}

async function save() {
  if (!current.value) return
  saving.value = true
  try {
    await api.updateAdmin(current.value.id, {
      roleId: editForm.roleId,
      status: editEnabled.value ? 1 : 0,
      newPassword: editForm.newPassword || undefined,
      resetTotp: editForm.resetTotp || undefined,
    })
    ElMessage.success('已保存')
    editDialog.value = false
    load()
  } finally {
    saving.value = false
  }
}

onMounted(async () => {
  load()
  roles.value = await api.roles()
})
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
