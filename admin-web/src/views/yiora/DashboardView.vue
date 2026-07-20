<template>
  <div v-loading="loading">
    <!-- 欢迎条 -->
    <el-card class="hello-card">
      <div class="hello">
        <div class="hello-avatar">{{ adminName[0]?.toUpperCase() }}</div>
        <div>
          <div class="hello-title">{{ greeting }},{{ adminName }}</div>
          <div class="hello-sub">{{ today }} · 祝你工作顺利,社区一切平稳</div>
        </div>
        <div class="hello-actions">
          <el-button v-if="data && data.pendingAudits > 0" type="warning" plain round @click="$router.push('/audits')">
            {{ data.pendingAudits }} 条内容待审核,去处理
          </el-button>
          <el-tag v-else type="success" effect="light" round>审核队列已清空</el-tag>
        </div>
      </div>
    </el-card>

    <!-- 指标卡 -->
    <el-row :gutter="16">
      <el-col v-for="card in cards" :key="card.label" :xs="12" :sm="12" :md="6" class="col">
        <el-card shadow="hover">
          <div class="yiora-metric">
            <div class="metric-icon" :style="{ background: card.bg }">
              <el-icon :size="24" :color="card.color"><component :is="card.icon" /></el-icon>
            </div>
            <div>
              <div class="metric-value">{{ card.value }}</div>
              <div class="metric-label">{{ card.label }}</div>
            </div>
          </div>
        </el-card>
      </el-col>
    </el-row>

    <!-- 趋势图 -->
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

    <!-- 推送渠道(离线推送发送量/失败率,apppush 渠道计数) -->
    <el-card v-if="pushStats.length" class="chart-card">
      <template #header>
        <div class="chart-bar">
          <span>推送渠道(近 7 日)</span>
          <span class="push-hint">离线推送各系统级通道健康度;未配置渠道不显示</span>
        </div>
      </template>
      <el-table :data="pushStats" size="small">
        <el-table-column prop="channel" label="渠道" width="140">
          <template #default="{ row }">
            <el-tag size="small">{{ row.channel }}</el-tag>
          </template>
        </el-table-column>
        <el-table-column prop="ok" label="发送成功" width="120" />
        <el-table-column prop="fail" label="失败" width="120" />
        <el-table-column label="失败率" width="120">
          <template #default="{ row }">
            <span :class="{ 'fail-high': failRate(row) >= 5 }">{{ failRate(row).toFixed(1) }}%</span>
          </template>
        </el-table-column>
        <el-table-column label="每日走势" min-width="200">
          <template #default="{ row }">
            <span class="spark">{{ row.days.map((d: { ok: number }) => d.ok).join(' / ') }}</span>
          </template>
        </el-table-column>
      </el-table>
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
import { api, type Dashboard } from '@/api/yiora'

const adminName = localStorage.getItem('yiora_admin_name') || 'admin'
const data = ref<Dashboard | null>(null)
const loading = ref(false)
const days = ref(30)
const chartEl = ref<HTMLDivElement>()
let chart: echarts.ECharts | null = null

interface PushChannelStat {
  channel: string
  ok: number
  fail: number
  days: { date: string; ok: number; fail: number }[]
}
const pushStats = ref<PushChannelStat[]>([])

function failRate(row: PushChannelStat) {
  const total = row.ok + row.fail
  return total === 0 ? 0 : (row.fail / total) * 100
}

const greeting = computed(() => {
  const h = new Date().getHours()
  if (h < 6) return '夜深了'
  if (h < 12) return '早上好'
  if (h < 14) return '中午好'
  if (h < 18) return '下午好'
  return '晚上好'
})
const today = new Date().toLocaleDateString('zh-CN', {
  year: 'numeric',
  month: 'long',
  day: 'numeric',
  weekday: 'long',
})

/* 浅底 + 彩色图标,亮暗主题下都柔和 */
const cards = computed(() => {
  const d = data.value
  if (!d) return []
  return [
    { label: '注册用户', value: d.users, icon: User, color: '#409eff', bg: 'rgba(64,158,255,.12)' },
    { label: '今日新增', value: d.todayUsers, icon: Sunrise, color: '#7a5af8', bg: 'rgba(122,90,248,.12)' },
    { label: '今日活跃', value: d.todayActive, icon: TrendCharts, color: '#00b578', bg: 'rgba(0,181,120,.12)' },
    { label: '待审积压', value: d.pendingAudits, icon: Warning, color: '#ff8f1f', bg: 'rgba(255,143,31,.14)' },
    { label: '已发布帖子', value: d.posts, icon: Files, color: '#3ba3f8', bg: 'rgba(59,163,248,.12)' },
    { label: '今日发帖', value: d.todayPosts, icon: ChatDotSquare, color: '#f65e8c', bg: 'rgba(246,94,140,.12)' },
    { label: '上架软件', value: d.software, icon: View, color: '#00b8d9', bg: 'rgba(0,184,217,.12)' },
    { label: '忧珠发放/消耗', value: `${d.youzhuIssued} / ${d.youzhuBurned}`, icon: Coin, color: '#f7b500', bg: 'rgba(247,181,0,.14)' },
  ]
})

/* 渐变面积折线,四指标同图 */
const palette = ['#409eff', '#00b578', '#f7b500', '#f65e8c']

function areaGradient(hex: string) {
  return new echarts.graphic.LinearGradient(0, 0, 0, 1, [
    { offset: 0, color: hex + '33' },
    { offset: 1, color: hex + '00' },
  ])
}

async function loadTrend() {
  const t = await api.trend(days.value)
  if (!chart && chartEl.value) {
    chart = echarts.init(chartEl.value)
  }
  const mk = (name: string, values: number[], i: number) => ({
    name,
    type: 'line' as const,
    smooth: true,
    symbol: 'circle',
    symbolSize: 5,
    showSymbol: false,
    lineStyle: { width: 2.5, color: palette[i] },
    itemStyle: { color: palette[i] },
    areaStyle: { color: areaGradient(palette[i]) },
    emphasis: { focus: 'series' as const },
    data: values,
  })
  chart?.setOption({
    tooltip: {
      trigger: 'axis',
      borderWidth: 0,
      backgroundColor: 'rgba(30,40,60,.85)',
      textStyle: { color: '#fff', fontSize: 12 },
      axisPointer: { type: 'line', lineStyle: { color: '#c0c4cc', type: 'dashed' } },
    },
    legend: { right: 8, top: 0, icon: 'roundRect', itemWidth: 12, itemHeight: 4 },
    grid: { left: 48, right: 24, top: 40, bottom: 28 },
    xAxis: {
      type: 'category',
      boundaryGap: false,
      data: t.dates.map((d) => d.slice(5)),
      axisLine: { lineStyle: { color: '#e4e7ed' } },
      axisTick: { show: false },
      axisLabel: { color: '#8a97a8' },
    },
    yAxis: {
      type: 'value',
      minInterval: 1,
      splitLine: { lineStyle: { color: '#f0f2f5', type: 'dashed' } },
      axisLabel: { color: '#8a97a8' },
    },
    series: [
      mk('注册', t.users, 0),
      mk('发帖', t.posts, 1),
      mk('忧珠发放', t.youzhuIssued, 2),
      mk('忧珠消耗', t.youzhuBurned, 3),
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
    pushStats.value = (await api.pushStats(7)).channels
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
.hello-card {
  margin-bottom: 16px;
}
.hello {
  display: flex;
  align-items: center;
  gap: 14px;
}
.hello-avatar {
  width: 52px;
  height: 52px;
  border-radius: 14px;
  background: linear-gradient(135deg, #409eff, #7a5af8);
  color: #fff;
  font-size: 26px;
  font-weight: 800;
  display: flex;
  align-items: center;
  justify-content: center;
  flex-shrink: 0;
}
.hello-title {
  font-size: 18px;
  font-weight: 700;
  color: var(--el-text-color-primary);
}
.hello-sub {
  margin-top: 4px;
  font-size: 13px;
  color: var(--el-text-color-secondary);
}
.hello-actions {
  margin-left: auto;
}
.push-hint {
  font-size: 12px;
  font-weight: 400;
  color: var(--el-text-color-secondary);
}
.fail-high {
  color: var(--el-color-danger);
  font-weight: 600;
}
.spark {
  color: var(--el-text-color-secondary);
  font-size: 12px;
  letter-spacing: 0.5px;
}
.col {
  margin-bottom: 16px;
}
.chart-card {
  margin-top: 2px;
}
.chart-bar {
  display: flex;
  justify-content: space-between;
  align-items: center;
}
.chart {
  height: 360px;
}
</style>
