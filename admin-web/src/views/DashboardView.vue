<template>
  <div v-loading="loading">
    <el-row :gutter="16">
      <el-col v-for="card in cards" :key="card.label" :span="6" class="col">
        <el-card shadow="hover">
          <div class="metric">
            <div class="metric-icon" :style="{ background: card.bg }">
              <el-icon :size="22" color="#fff"><component :is="card.icon" /></el-icon>
            </div>
            <div>
              <div class="value">{{ card.value }}</div>
              <div class="label">{{ card.label }}</div>
            </div>
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
import {
  ChatDotSquare,
  Coin,
  Files,
  Sunrise,
  TrendCharts,
  User,
  View,
  Warning,
} from '@element-plus/icons-vue'
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
    { label: '注册用户', value: d.users, icon: User, bg: 'linear-gradient(135deg,#409eff,#6db3ff)' },
    { label: '今日新增', value: d.todayUsers, icon: Sunrise, bg: 'linear-gradient(135deg,#7a5af8,#a18bff)' },
    { label: '今日活跃', value: d.todayActive, icon: TrendCharts, bg: 'linear-gradient(135deg,#00b578,#4cd8a6)' },
    { label: '待审积压', value: d.pendingAudits, icon: Warning, bg: 'linear-gradient(135deg,#ff8f1f,#ffb45e)' },
    { label: '已发布帖子', value: d.posts, icon: Files, bg: 'linear-gradient(135deg,#3ba3f8,#7cc4ff)' },
    { label: '今日发帖', value: d.todayPosts, icon: ChatDotSquare, bg: 'linear-gradient(135deg,#f65e8c,#ff9ab8)' },
    { label: '上架软件', value: d.software, icon: View, bg: 'linear-gradient(135deg,#00b8d9,#5cd6e8)' },
    { label: '忧珠发放/消耗', value: `${d.youzhuIssued} / ${d.youzhuBurned}`, icon: Coin, bg: 'linear-gradient(135deg,#f7b500,#ffd45e)' },
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
  display: flex;
  align-items: center;
  gap: 14px;
}
.metric-icon {
  width: 46px;
  height: 46px;
  border-radius: 12px;
  display: flex;
  align-items: center;
  justify-content: center;
  flex-shrink: 0;
}
.value {
  font-size: 24px;
  font-weight: 700;
  color: #24334a;
  line-height: 1.2;
}
.label {
  margin-top: 4px;
  color: #8a97a8;
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
