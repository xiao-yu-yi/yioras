<template>
  <el-card>
    <template #header>
      <div class="bar">
        <span>商城 / 任务运营配置(保存即生效;条目不物理删除,用上下架控制)</span>
        <el-button type="primary" @click="openEdit()">新增{{ tabNames[tab] }}</el-button>
      </div>
    </template>

    <el-radio-group v-model="tab" class="tabs" @change="load">
      <el-radio-button value="deco">装扮商品</el-radio-button>
      <el-radio-button value="prize">抽奖奖池</el-radio-button>
      <el-radio-button value="task">任务配置</el-radio-button>
    </el-radio-group>

    <!-- 装扮 -->
    <el-table v-if="tab === 'deco'" :data="decos" v-loading="loading">
      <el-table-column prop="id" label="ID" width="60" />
      <el-table-column label="类型" width="90">
        <template #default="{ row }">头像框</template>
      </el-table-column>
      <el-table-column prop="name" label="名称" min-width="130" />
      <el-table-column label="预览" width="80">
        <template #default="{ row }">
          <el-link :href="row.preview" target="_blank" type="primary">查看</el-link>
        </template>
      </el-table-column>
      <el-table-column label="价格" width="100">
        <template #default="{ row }">{{ row.price }} 忧珠</template>
      </el-table-column>
      <el-table-column label="时效" width="100">
        <template #default="{ row }">{{ row.durationDays === 0 ? '永久' : `${row.durationDays} 天` }}</template>
      </el-table-column>
      <el-table-column prop="sort" label="排序" width="70" />
      <el-table-column label="状态" width="90">
        <template #default="{ row }">
          <el-tag :type="row.status === 1 ? 'success' : 'info'">{{ row.status === 1 ? '上架' : '下架' }}</el-tag>
        </template>
      </el-table-column>
      <el-table-column label="操作" width="90" fixed="right">
        <template #default="{ row }">
          <el-button size="small" @click="openEdit(row)">编辑</el-button>
        </template>
      </el-table-column>
    </el-table>

    <!-- 奖池 -->
    <el-table v-if="tab === 'prize'" :data="prizes" v-loading="loading">
      <el-table-column prop="id" label="ID" width="60" />
      <el-table-column prop="name" label="奖品名" min-width="130" />
      <el-table-column label="内容" min-width="140">
        <template #default="{ row }">
          {{ row.kind === 1 ? `${row.amount} 忧珠` : `装扮 #${row.refId}` }}
        </template>
      </el-table-column>
      <el-table-column prop="weight" label="权重" width="80" />
      <el-table-column label="库存" width="90">
        <template #default="{ row }">{{ row.stock === -1 ? '不限' : row.stock }}</template>
      </el-table-column>
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

    <!-- 任务 -->
    <el-table v-if="tab === 'task'" :data="tasks" v-loading="loading">
      <el-table-column prop="id" label="ID" width="60" />
      <el-table-column prop="name" label="任务名" min-width="140" />
      <el-table-column label="类型" width="80">
        <template #default="{ row }">{{ row.type === 1 ? '每日' : '新手' }}</template>
      </el-table-column>
      <el-table-column label="行为" width="100">
        <template #default="{ row }">{{ actionNames[row.action] ?? row.action }} ×{{ row.targetCount }}</template>
      </el-table-column>
      <el-table-column label="奖励" width="150">
        <template #default="{ row }">{{ row.rewardYouzhu }} 忧珠 + {{ row.rewardExp }} 经验</template>
      </el-table-column>
      <el-table-column prop="sort" label="排序" width="70" />
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

    <!-- 装扮弹窗 -->
    <el-dialog v-model="decoDialog" :title="decoForm.id ? '编辑装扮' : '新增装扮'" width="460px">
      <el-form label-width="90px">
        <el-form-item label="类型">
          <el-select v-model="decoForm.kind" style="width: 100%">
            <el-option :value="1" label="头像框" />
          </el-select>
        </el-form-item>
        <el-form-item label="名称" required><el-input v-model="decoForm.name" maxlength="30" /></el-form-item>
        <el-form-item label="预览图" required>
          <UploadImage :model-value="decoForm.preview ?? ''" kind="deco" @update:model-value="decoForm.preview = $event" />
        </el-form-item>
        <el-form-item label="价格(忧珠)"><el-input-number v-model="decoForm.price" :min="0" /></el-form-item>
        <el-form-item label="时效(天)">
          <el-input-number v-model="decoForm.durationDays" :min="0" />
          <span class="sub" style="margin-left: 8px">0 = 永久</span>
        </el-form-item>
        <el-form-item label="排序"><el-input-number v-model="decoForm.sort" :min="0" /></el-form-item>
        <el-form-item label="状态"><el-switch v-model="enabled" active-text="上架" inactive-text="下架" /></el-form-item>
      </el-form>
      <template #footer>
        <el-button @click="decoDialog = false">取消</el-button>
        <el-button type="primary" :loading="saving" @click="saveDeco">保存并生效</el-button>
      </template>
    </el-dialog>

    <!-- 奖池弹窗 -->
    <el-dialog v-model="prizeDialog" :title="prizeForm.id ? '编辑奖品' : '新增奖品'" width="460px">
      <el-form label-width="90px">
        <el-form-item label="奖品名" required><el-input v-model="prizeForm.name" maxlength="30" /></el-form-item>
        <el-form-item label="奖品类型">
          <el-select v-model="prizeForm.kind" style="width: 100%">
            <el-option :value="1" label="忧珠" />
            <el-option :value="2" label="装扮" />
          </el-select>
        </el-form-item>
        <el-form-item v-if="prizeForm.kind === 1" label="忧珠数量">
          <el-input-number v-model="prizeForm.amount" :min="1" />
        </el-form-item>
        <el-form-item v-else label="装扮">
          <el-select v-model="prizeForm.refId" style="width: 100%" placeholder="选择装扮商品">
            <el-option v-for="d in decos" :key="d.id" :value="d.id" :label="`#${d.id} ${d.name}`" />
          </el-select>
        </el-form-item>
        <el-form-item label="抽取权重"><el-input-number v-model="prizeForm.weight" :min="1" /></el-form-item>
        <el-form-item label="库存">
          <el-input-number v-model="prizeForm.stock" :min="-1" />
          <span class="sub" style="margin-left: 8px">-1 = 不限量</span>
        </el-form-item>
        <el-form-item label="状态"><el-switch v-model="enabled" active-text="启用" inactive-text="停用" /></el-form-item>
      </el-form>
      <template #footer>
        <el-button @click="prizeDialog = false">取消</el-button>
        <el-button type="primary" :loading="saving" @click="savePrize">保存并生效</el-button>
      </template>
    </el-dialog>

    <!-- 任务弹窗 -->
    <el-dialog v-model="taskDialog" :title="taskForm.id ? '编辑任务' : '新增任务'" width="460px">
      <el-form label-width="100px">
        <el-form-item label="任务名" required><el-input v-model="taskForm.name" maxlength="30" /></el-form-item>
        <el-form-item label="类型">
          <el-select v-model="taskForm.type" style="width: 100%">
            <el-option :value="1" label="每日任务" />
            <el-option :value="2" label="新手任务" />
          </el-select>
        </el-form-item>
        <el-form-item label="触发行为">
          <el-select v-model="taskForm.action" style="width: 100%">
            <el-option v-for="(name, a) in actionNames" :key="a" :value="a" :label="name" />
          </el-select>
        </el-form-item>
        <el-form-item label="完成次数"><el-input-number v-model="taskForm.targetCount" :min="1" /></el-form-item>
        <el-form-item label="忧珠奖励"><el-input-number v-model="taskForm.rewardYouzhu" :min="0" /></el-form-item>
        <el-form-item label="经验奖励"><el-input-number v-model="taskForm.rewardExp" :min="0" /></el-form-item>
        <el-form-item label="排序"><el-input-number v-model="taskForm.sort" :min="0" /></el-form-item>
        <el-form-item label="状态"><el-switch v-model="enabled" active-text="启用" inactive-text="停用" /></el-form-item>
      </el-form>
      <template #footer>
        <el-button @click="taskDialog = false">取消</el-button>
        <el-button type="primary" :loading="saving" @click="saveTask">保存并生效</el-button>
      </template>
    </el-dialog>
  </el-card>
</template>

<script setup lang="ts">
import { onMounted, reactive, ref } from 'vue'
import { ElMessage } from 'element-plus'
import { api, type AdminDecoItem, type AdminPrizeItem, type AdminTaskCfgItem } from '@/api/yiora'
import UploadImage from '@/components/UploadImage.vue'

const tabNames: Record<string, string> = { deco: '装扮', prize: '奖品', task: '任务' }
const actionNames: Record<string, string> = { post: '发帖', comment: '评论', like: '点赞', browse: '浏览' }

const tab = ref<'deco' | 'prize' | 'task'>('deco')
const decos = ref<AdminDecoItem[]>([])
const prizes = ref<AdminPrizeItem[]>([])
const tasks = ref<AdminTaskCfgItem[]>([])
const loading = ref(false)
const saving = ref(false)
const enabled = ref(true)

const decoDialog = ref(false)
const prizeDialog = ref(false)
const taskDialog = ref(false)
const decoForm = reactive<Partial<AdminDecoItem>>({})
const prizeForm = reactive<Partial<AdminPrizeItem>>({})
const taskForm = reactive<Partial<AdminTaskCfgItem>>({})

async function load() {
  loading.value = true
  try {
    if (tab.value === 'deco') decos.value = await api.mallDecos()
    else if (tab.value === 'prize') {
      // 奖池弹窗选装扮需要装扮清单
      ;[prizes.value, decos.value] = await Promise.all([api.mallPrizes(), api.mallDecos()])
    } else tasks.value = await api.mallTasks()
  } finally {
    loading.value = false
  }
}

function openEdit(row?: AdminDecoItem | AdminPrizeItem | AdminTaskCfgItem) {
  enabled.value = (row?.status ?? 1) === 1
  if (tab.value === 'deco') {
    Object.assign(decoForm, row ?? { id: 0, kind: 1, name: '', preview: '', price: 0, durationDays: 0, sort: 0 })
    decoDialog.value = true
  } else if (tab.value === 'prize') {
    Object.assign(prizeForm, row ?? { id: 0, name: '', kind: 1, refId: undefined, amount: 5, weight: 10, stock: -1 })
    prizeDialog.value = true
  } else {
    Object.assign(taskForm, row ?? { id: 0, name: '', type: 1, action: 'post', targetCount: 1, rewardYouzhu: 5, rewardExp: 5, sort: 0 })
    taskDialog.value = true
  }
}

async function saveDeco() {
  if (!decoForm.name?.trim() || !decoForm.preview) {
    ElMessage.warning('名称与预览图必填')
    return
  }
  saving.value = true
  try {
    await api.saveMallDeco({ ...decoForm, status: enabled.value ? 1 : 0 })
    ElMessage.success('已保存,商城即时生效')
    decoDialog.value = false
    load()
  } finally {
    saving.value = false
  }
}

async function savePrize() {
  if (!prizeForm.name?.trim()) {
    ElMessage.warning('奖品名必填')
    return
  }
  if (prizeForm.kind === 2 && !prizeForm.refId) {
    ElMessage.warning('请选择装扮')
    return
  }
  saving.value = true
  try {
    await api.saveMallPrize({ ...prizeForm, status: enabled.value ? 1 : 0 })
    ElMessage.success('已保存,奖池即时生效')
    prizeDialog.value = false
    load()
  } finally {
    saving.value = false
  }
}

async function saveTask() {
  if (!taskForm.name?.trim()) {
    ElMessage.warning('任务名必填')
    return
  }
  if (!taskForm.rewardYouzhu && !taskForm.rewardExp) {
    ElMessage.warning('忧珠与经验奖励至少配置一项')
    return
  }
  saving.value = true
  try {
    await api.saveMallTask({ ...taskForm, status: enabled.value ? 1 : 0 })
    ElMessage.success('已保存,任务中心即时生效')
    taskDialog.value = false
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
.tabs {
  margin-bottom: 14px;
}
.sub {
  color: #909399;
  font-size: 12px;
}
</style>
