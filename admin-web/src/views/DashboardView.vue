<template>
  <div v-loading="loading">
    <el-row :gutter="16">
      <el-col v-for="card in cards" :key="card.label" :span="6" class="col">
        <el-card shadow="hover">
          <div class="metric">
            <div class="value">{{ card.value }}</div>
            <div class="label">{{ card.label }}</div>
          </div>
        </el-card>
      </el-col>
    </el-row>
    <el-alert
      v-if="data && data.pendingAudits > 0"
      class="alert"
      type="warning"
      :closable="false"
      :title="`当前有 ${data.pendingAudits} 条内容待人工审核,请及时处理`"
      show-icon
    />
    <el-card class="chart-card">
      <template #header>
        <div class="chart-bar">
          <span>运营趋势</span>
          <el-radio-group v-model="days" size="small" @change="loadTrend">
            <el-radio-button :value="7">近 7 天</el-radio-button>
            <el-radio-button :value="30">近 30 天</el-radio-button>
            <el-radio-button :value="90">近 90 天</el-radio-button>
          </el-radio-group>
        </div>
      </template>
      <div ref="chartEl" class="chart" />
    </el-card>
  </div>
</template>

<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref } from 'vue'
import * as echarts from 'echarts'
import { api, type Dashboard } from '../api'

const data = ref<Dashboard | null>(null)
const loading = ref(false)
const days = ref(30)
const chartEl = ref<HTMLDivElement>()
let chart: echarts.ECharts | null = null

const cards = computed(() => {
  const d = data.value
  if (!d) return []
  return [
    { label: '注册用户', value: d.users },
    { label: '今日新增', value: d.todayUsers },
    { label: '今日活跃', value: d.todayActive },
    { label: '待审积压', value: d.pendingAudits },
    { label: '已发布帖子', value: d.posts },
    { label: '今日发帖', value: d.todayPosts },
    { label: '上架软件', value: d.software },
    { label: '忧珠发放/消耗', value: `${d.youzhuIssued} / ${d.youzhuBurned}` },
  ]
})

async function loadTrend() {
  const t = await api.trend(days.value)
  if (!chart && chartEl.value) {
    chart = echarts.init(chartEl.value)
  }
  chart?.setOption({
    tooltip: { trigger: 'axis' },
    legend: { data: ['注册', '发帖', '忧珠发放', '忧珠消耗'] },
    grid: { left: 48, right: 24, top: 40, bottom: 28 },
    xAxis: { type: 'category', data: t.dates.map((d) => d.slice(5)) },
    yAxis: { type: 'value', minInterval: 1 },
    series: [
      { name: '注册', type: 'line', smooth: true, data: t.users },
      { name: '发帖', type: 'line', smooth: true, data: t.posts },
      { name: '忧珠发放', type: 'line', smooth: true, data: t.youzhuIssued },
      { name: '忧珠消耗', type: 'line', smooth: true, data: t.youzhuBurned },
    ],
  })
}

function onResize() {
  chart?.resize()
}

onMounted(async () => {
  loading.value = true
  try {
    data.value = await api.dashboard()
    await loadTrend()
    window.addEventListener('resize', onResize)
  } finally {
    loading.value = false
  }
})

onBeforeUnmount(() => {
  window.removeEventListener('resize', onResize)
  chart?.dispose()
  chart = null
})
</script>

<style scoped>
.col {
  margin-bottom: 16px;
}
.metric {
  text-align: center;
}
.value {
  font-size: 26px;
  font-weight: 700;
  color: #303133;
}
.label {
  margin-top: 6px;
  color: #909399;
  font-size: 13px;
}
.alert {
  margin-top: 4px;
}
.chart-card {
  margin-top: 16px;
}
.chart-bar {
  display: flex;
  justify-content: space-between;
  align-items: center;
}
.chart {
  height: 340px;
}
</style>
