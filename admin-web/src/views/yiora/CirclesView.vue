<template>
  <el-card>
    <template #header>
      <div class="bar">
        <span>圈子管理(创建 / 排序 / 隐藏 / 圈主任命)</span>
        <el-button type="primary" @click="openEdit()">新建圈子</el-button>
      </div>
    </template>

    <el-form inline @submit.prevent="search">
      <el-form-item>
        <el-input v-model="keyword" placeholder="圈子名" clearable style="width: 200px" @keyup.enter="search" @clear="search" />
      </el-form-item>
      <el-button type="primary" @click="search">查询</el-button>
    </el-form>

    <el-table :data="rows" v-loading="loading">
      <el-table-column prop="id" label="ID" width="60" />
      <el-table-column label="圈子" min-width="180">
        <template #default="{ row }">
          <div class="circle-cell">
            <el-avatar :size="30" shape="square" :src="row.icon" />
            <div>
              <div>
                {{ row.name }}
                <el-tag v-if="row.isOfficial === 1" size="small" type="warning" effect="plain">官方</el-tag>
                <el-tag v-if="row.pinned === 1" size="small" type="primary" effect="plain">置顶</el-tag>
              </div>
              <div class="sub">{{ row.intro }}</div>
            </div>
          </div>
        </template>
      </el-table-column>
      <el-table-column label="成员/帖子" width="110">
        <template #default="{ row }">{{ row.memberCount }} / {{ row.postCount }}</template>
      </el-table-column>
      <el-table-column prop="sort" label="排序" width="70" />
      <el-table-column label="状态" width="90">
        <template #default="{ row }">
          <el-tag :type="(['', 'success', 'info', 'danger'] as const)[row.status] || 'info'">
            {{ ['', '正常', '隐藏', '解散'][row.status] ?? row.status }}
          </el-tag>
        </template>
      </el-table-column>
      <el-table-column label="操作" width="170" fixed="right">
        <template #default="{ row }">
          <el-button size="small" @click="openEdit(row)">编辑</el-button>
          <el-button size="small" type="warning" @click="openAppoint(row)">任命</el-button>
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

    <el-dialog v-model="dialog" :title="form.id ? '编辑圈子' : '新建圈子'" width="520px">
      <el-form label-width="90px">
        <el-form-item label="名称" required><el-input v-model="form.name" maxlength="30" /></el-form-item>
        <el-form-item label="图标" required>
          <UploadImage :model-value="form.icon ?? ''" kind="circle" @update:model-value="form.icon = $event" />
        </el-form-item>
        <el-form-item label="封面">
          <UploadImage :model-value="form.cover ?? ''" kind="circle" @update:model-value="form.cover = $event" />
        </el-form-item>
        <el-form-item label="一句话简介"><el-input v-model="form.intro" maxlength="100" /></el-form-item>
        <el-form-item label="详细介绍">
          <el-input v-model="form.description" type="textarea" :rows="3" maxlength="1000" />
        </el-form-item>
        <el-form-item label="官方圈"><el-switch v-model="isOfficial" /></el-form-item>
        <el-form-item label="发现页置顶"><el-switch v-model="pinned" /></el-form-item>
        <el-form-item label="排序"><el-input-number v-model="form.sort" :min="0" /></el-form-item>
        <el-form-item label="状态">
          <el-select v-model="form.status" style="width: 100%">
            <el-option :value="1" label="正常" />
            <el-option :value="2" label="隐藏(发现页不可见)" />
            <el-option :value="3" label="解散" />
          </el-select>
        </el-form-item>
      </el-form>
      <template #footer>
        <el-button @click="dialog = false">取消</el-button>
        <el-button type="primary" :loading="saving" @click="save">保存</el-button>
      </template>
    </el-dialog>

    <el-dialog v-model="appointDialog" :title="`任命「${current?.name}」管理员`" width="420px">
      <el-form label-width="90px">
        <el-form-item label="用户 UID" required>
          <el-input-number v-model="appointUid" :min="1" :controls="false" style="width: 100%" />
        </el-form-item>
        <el-form-item label="角色">
          <el-select v-model="appointRole" style="width: 100%">
            <el-option :value="2" label="圈子管理员" />
            <el-option :value="3" label="圈主" />
            <el-option :value="1" label="降为普通成员" />
          </el-select>
        </el-form-item>
      </el-form>
      <template #footer>
        <el-button @click="appointDialog = false">取消</el-button>
        <el-button type="primary" :loading="saving" @click="appoint">确认任命</el-button>
      </template>
    </el-dialog>
  </el-card>
</template>

<script setup lang="ts">
import { onMounted, reactive, ref } from 'vue'
import { ElMessage } from 'element-plus'
import { api, type AdminCircleItem } from '@/api/yiora'
import UploadImage from '@/components/UploadImage.vue'

const keyword = ref('')
const page = ref(1)
const size = 20
const total = ref(0)
const rows = ref<AdminCircleItem[]>([])
const loading = ref(false)

const dialog = ref(false)
const saving = ref(false)
const form = reactive<Partial<AdminCircleItem>>({})
const isOfficial = ref(false)
const pinned = ref(false)

const appointDialog = ref(false)
const current = ref<AdminCircleItem | null>(null)
const appointUid = ref<number>()
const appointRole = ref(2)

async function load() {
  loading.value = true
  try {
    const data = await api.circles({ keyword: keyword.value.trim(), page: page.value, size })
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

function openEdit(row?: AdminCircleItem) {
  Object.assign(form, row ?? { id: 0, name: '', icon: '', cover: '', intro: '', description: '', sort: 0, status: 1 })
  isOfficial.value = (row?.isOfficial ?? 0) === 1
  pinned.value = (row?.pinned ?? 0) === 1
  dialog.value = true
}

async function save() {
  if (!form.name?.trim() || !form.icon) {
    ElMessage.warning('名称与图标必填')
    return
  }
  saving.value = true
  try {
    await api.saveCircle({
      ...form,
      isOfficial: isOfficial.value ? 1 : 0,
      pinned: pinned.value ? 1 : 0,
    })
    ElMessage.success('已保存')
    dialog.value = false
    load()
  } finally {
    saving.value = false
  }
}

function openAppoint(row: AdminCircleItem) {
  current.value = row
  appointUid.value = undefined
  appointRole.value = 2
  appointDialog.value = true
}

async function appoint() {
  if (!current.value || !appointUid.value) {
    ElMessage.warning('请输入用户 UID')
    return
  }
  saving.value = true
  try {
    await api.appointCircle(current.value.id, appointUid.value, appointRole.value)
    ElMessage.success('任命已生效')
    appointDialog.value = false
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
.circle-cell {
  display: flex;
  align-items: center;
  gap: 8px;
}
.sub {
  color: var(--el-text-color-secondary);
  font-size: 12px;
}
.pager {
  margin-top: 14px;
}
</style>
