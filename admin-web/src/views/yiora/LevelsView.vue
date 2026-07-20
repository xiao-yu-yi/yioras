<template>
  <!-- 成长参数:行为经验权重与每日上限(app_config,保存即生效) -->
  <el-card class="growth-card" v-loading="cfgLoading">
    <template #header>
      <div class="bar">
        <span>成长参数(行为经验权重,保存即生效)</span>
        <el-button type="primary" :loading="cfgSaving" @click="saveCfg">保存参数</el-button>
      </div>
    </template>
    <div class="cfg-grid">
      <div v-for="c in cfgs" :key="c.k" class="cfg-item">
        <div class="cfg-label">{{ c.remark }}</div>
        <el-input-number v-model="c.num" :min="0" :max="99999" controls-position="right" />
        <div class="cfg-key">{{ c.k }}</div>
      </div>
    </div>
  </el-card>

  <el-card v-loading="loading">
    <template #header>
      <div class="bar">
        <span>等级规则(经验阈值表)</span>
        <div>
          <el-button @click="addLevel">追加一级</el-button>
          <el-button type="primary" :loading="saving" @click="save">保存整表</el-button>
        </div>
      </div>
    </template>

    <el-alert
      type="info"
      :closable="false"
      class="hint"
      title="规则:Lv0 固定 0 经验(注册即 Lv0),经验阈值逐级严格递增;保存后对后续加经验行为即时生效,存量用户等级在其下次获得经验时按新表重算。"
    />

    <el-table :data="rules" size="default" class="tbl">
      <el-table-column label="等级" width="120">
        <template #default="{ $index }">
          <el-tag :type="$index === 0 ? 'info' : 'primary'">Lv{{ $index }}</el-tag>
        </template>
      </el-table-column>
      <el-table-column label="所需累计经验" width="260">
        <template #default="{ row, $index }">
          <el-input-number
            v-model="row.needExp"
            :disabled="$index === 0"
            :min="$index === 0 ? 0 : 1"
            :max="99999999"
            :step="100"
            controls-position="right"
          />
        </template>
      </el-table-column>
      <el-table-column label="与上一级差值" width="160">
        <template #default="{ row, $index }">
          <span class="sub">{{ $index === 0 ? '-' : row.needExp - rules[$index - 1].needExp }}</span>
        </template>
      </el-table-column>
      <el-table-column label="校验" min-width="160">
        <template #default="{ row, $index }">
          <el-tag v-if="rowError(row, $index)" type="danger" size="small">{{ rowError(row, $index) }}</el-tag>
          <el-tag v-else type="success" size="small">OK</el-tag>
        </template>
      </el-table-column>
      <el-table-column label="操作" width="100" fixed="right">
        <template #default="{ $index }">
          <el-button
            v-if="$index === rules.length - 1 && $index > 1"
            size="small"
            type="danger"
            @click="rules.pop()"
          >删除末级</el-button>
        </template>
      </el-table-column>
    </el-table>
  </el-card>
</template>

<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { ElMessage } from 'element-plus'
import { api, type LevelRuleItem } from '@/api/yiora'

const rules = ref<LevelRuleItem[]>([])
const loading = ref(false)
const saving = ref(false)

interface CfgRow {
  k: string
  remark: string
  num: number
}
const cfgs = ref<CfgRow[]>([])
const cfgLoading = ref(false)
const cfgSaving = ref(false)

async function loadCfg() {
  cfgLoading.value = true
  try {
    const rows = await api.appConfigs('exp.')
    cfgs.value = rows.map((r) => ({ k: r.k, remark: r.remark, num: Number(r.v) || 0 }))
  } finally {
    cfgLoading.value = false
  }
}

async function saveCfg() {
  cfgSaving.value = true
  try {
    await api.saveAppConfigs(cfgs.value.map((c) => ({ k: c.k, v: String(c.num) })))
    ElMessage.success('已保存,即时生效')
    loadCfg()
  } finally {
    cfgSaving.value = false
  }
}

function rowError(row: LevelRuleItem, idx: number) {
  if (idx === 0) return row.needExp === 0 ? '' : 'Lv0 必须为 0'
  if (row.needExp <= rules.value[idx - 1].needExp) return '需大于上一级'
  return ''
}

async function load() {
  loading.value = true
  try {
    rules.value = await api.levelRules()
  } finally {
    loading.value = false
  }
}

function addLevel() {
  if (rules.value.length >= 51) {
    ElMessage.warning('最多 51 档(Lv0-Lv50)')
    return
  }
  const last = rules.value[rules.value.length - 1]
  rules.value.push({ level: rules.value.length, needExp: (last?.needExp ?? 0) + 1000 })
}

async function save() {
  for (let i = 0; i < rules.value.length; i++) {
    if (rowError(rules.value[i], i)) {
      ElMessage.warning(`Lv${i} 校验未通过,请先修正`)
      return
    }
  }
  saving.value = true
  try {
    // level 按当前行序重排,与后端连续性校验对齐
    const payload = rules.value.map((r, i) => ({ level: i, needExp: r.needExp }))
    await api.saveLevelRules(payload)
    ElMessage.success('已保存,即时生效')
    load()
  } finally {
    saving.value = false
  }
}

onMounted(() => {
  load()
  loadCfg()
})
</script>

<style scoped>
.bar {
  display: flex;
  justify-content: space-between;
  align-items: center;
}
.hint {
  margin-bottom: 14px;
}
.tbl {
  max-width: 860px;
}
.sub {
  color: var(--el-text-color-secondary);
}
.growth-card {
  margin-bottom: 16px;
}
.cfg-grid {
  display: flex;
  flex-wrap: wrap;
  gap: 18px 28px;
}
.cfg-item {
  display: flex;
  flex-direction: column;
  gap: 6px;
}
.cfg-label {
  font-size: 13px;
  color: var(--el-text-color-regular);
}
.cfg-key {
  font-size: 11px;
  color: var(--el-text-color-secondary);
  font-family: monospace;
}
</style>
