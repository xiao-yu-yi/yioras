<template>
  <el-card>
    <template #header>
      <div class="bar">
        <span>待人审队列</span>
        <el-radio-group v-model="bizType" @change="load(1)">
          <el-radio-button :value="0">全部</el-radio-button>
          <el-radio-button :value="1">帖子</el-radio-button>
          <el-radio-button :value="2">评论</el-radio-button>
          <el-radio-button :value="3">软件</el-radio-button>
        </el-radio-group>
      </div>
    </template>

    <el-table :data="rows" v-loading="loading">
      <el-table-column prop="id" label="单号" width="80" />
      <el-table-column label="类型" width="90">
        <template #default="{ row }">
          <el-tag :type="tagType(row.bizType)">{{ bizName(row.bizType) }}</el-tag>
        </template>
      </el-table-column>
      <el-table-column prop="bizId" label="业务ID" width="100" />
      <el-table-column label="机审" width="100">
        <template #default="{ row }">
          <el-tag v-if="row.machineResult === 3" type="danger">已拦截</el-tag>
          <el-tag v-else-if="row.machineResult === 2" type="warning">疑似</el-tag>
          <el-tag v-else type="info">常规</el-tag>
        </template>
      </el-table-column>
      <el-table-column label="机审明细" min-width="240">
        <template #default="{ row }">
          <!-- 图片机审结构化明细:命中图缩略 + 标签/分值;其余保持原文 -->
          <template v-if="imgDetail(row)">
            <div class="img-detail">
              <el-image
                :src="imgDetail(row)!.img"
                :preview-src-list="[imgDetail(row)!.img]"
                preview-teleported
                fit="cover"
                class="hit-img"
              />
              <div class="img-meta">
                <el-tag size="small" type="danger">{{ imgDetail(row)!.label }}</el-tag>
                <span class="score">置信 {{ (imgDetail(row)!.score * 100).toFixed(0) }}%</span>
              </div>
            </div>
          </template>
          <span v-else class="plain-detail">{{ row.machineDetail }}</span>
        </template>
      </el-table-column>
      <el-table-column label="提交时间" width="170">
        <template #default="{ row }">{{ fmtTime(row.createdAt) }}</template>
      </el-table-column>
      <el-table-column label="操作" width="230" fixed="right">
        <template #default="{ row }">
          <el-button size="small" @click="preview(row)">查看</el-button>
          <el-button size="small" type="success" @click="decide(row, true)">通过</el-button>
          <el-button size="small" type="danger" @click="decide(row, false)">驳回</el-button>
        </template>
      </el-table-column>
    </el-table>

    <!-- 内容回查:原文与图片看清楚再裁决 -->
    <el-drawer v-model="pvDrawer" :title="`内容回查 #${pvAudit?.id ?? ''}`" size="480px">
      <div v-loading="pvLoading">
        <template v-if="pv">
          <el-descriptions :column="1" border size="small" class="pv-meta">
            <el-descriptions-item label="类型">{{ { post: '帖子', comment: '评论', software: '软件' }[pv.kind] }}</el-descriptions-item>
            <el-descriptions-item label="作者">{{ pv.authorName }} (UID {{ pv.authorId }})</el-descriptions-item>
            <el-descriptions-item v-if="pv.title" label="标题">{{ pv.title }}</el-descriptions-item>
          </el-descriptions>
          <div v-if="pv.logo" class="pv-block">
            <div class="pv-label">Logo</div>
            <el-image :src="pv.logo" :preview-src-list="[pv.logo]" preview-teleported fit="cover" class="pv-logo" />
          </div>
          <div class="pv-block">
            <div class="pv-label">正文</div>
            <div class="pv-content">{{ pv.content || '(无文字内容)' }}</div>
          </div>
          <div v-if="pv.images.length" class="pv-block">
            <div class="pv-label">图片({{ pv.images.length }})</div>
            <div class="pv-imgs">
              <el-image
                v-for="img in pv.images"
                :key="img"
                :src="img"
                :preview-src-list="pv.images"
                preview-teleported
                fit="cover"
                class="pv-img"
              />
            </div>
          </div>
          <div class="pv-actions">
            <el-button type="success" @click="decideFromPreview(true)">通过</el-button>
            <el-button type="danger" @click="decideFromPreview(false)">驳回</el-button>
          </div>
        </template>
      </div>
    </el-drawer>

    <div class="pager">
      <el-button :disabled="page <= 1" @click="load(page - 1)">上一页</el-button>
      <span>第 {{ page }} 页</span>
      <el-button :disabled="rows.length < 20" @click="load(page + 1)">下一页</el-button>
    </div>
  </el-card>
</template>

<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { ElMessage, ElMessageBox } from 'element-plus'
import { api, type AuditItem } from '@/api/yiora'

const rows = ref<AuditItem[]>([])
const bizType = ref(0)
const page = ref(1)
const loading = ref(false)

function bizName(t: number) {
  return { 1: '帖子', 2: '评论', 3: '软件' }[t] ?? '未知'
}

interface ImgScanDetail {
  img: string
  label: string
  score: number
  scanner?: string
}

// 图片机审明细(imgscan 写入的 JSON:{img,label,score,scanner})解析,非该结构返回 null 走原文展示
function imgDetail(row: AuditItem): ImgScanDetail | null {
  if (!row.machineDetail) return null
  try {
    const d = JSON.parse(row.machineDetail)
    if (d && typeof d.img === 'string' && d.img && typeof d.label === 'string') {
      return { img: d.img, label: d.label, score: Number(d.score) || 0, scanner: d.scanner }
    }
  } catch { /* 非 JSON 明细走原文 */ }
  return null
}
function tagType(t: number) {
  return ({ 1: 'primary', 2: 'success', 3: 'warning' } as const)[t as 1 | 2 | 3] ?? 'info'
}
function fmtTime(ms: number) {
  return new Date(ms).toLocaleString('zh-CN')
}

interface AuditPreview {
  kind: 'post' | 'comment' | 'software'
  title: string
  content: string
  logo?: string
  images: string[]
  authorId: number
  authorName: string
}
const pvDrawer = ref(false)
const pvLoading = ref(false)
const pvAudit = ref<AuditItem | null>(null)
const pv = ref<AuditPreview | null>(null)

async function preview(row: AuditItem) {
  pvAudit.value = row
  pv.value = null
  pvDrawer.value = true
  pvLoading.value = true
  try {
    pv.value = await api.auditPreview(row.id)
  } finally {
    pvLoading.value = false
  }
}

async function decideFromPreview(approve: boolean) {
  if (!pvAudit.value) return
  await decide(pvAudit.value, approve)
  pvDrawer.value = false
}

async function load(p: number) {
  loading.value = true
  try {
    page.value = p
    rows.value = await api.audits(bizType.value, p)
  } finally {
    loading.value = false
  }
}

async function decide(row: AuditItem, approve: boolean) {
  let reason = ''
  if (!approve) {
    const input = await ElMessageBox.prompt('请填写驳回原因(将通知作者)', '驳回', {
      inputValidator: (v: string) => (v.trim() ? true : '驳回原因必填'),
    }).catch(() => null)
    if (!input) return
    reason = input.value.trim()
  }
  await api.decide(row.id, approve, reason)
  ElMessage.success(approve ? '已通过' : '已驳回')
  load(page.value)
}

onMounted(() => load(1))
</script>

<style scoped>
.bar {
  display: flex;
  justify-content: space-between;
  align-items: center;
}
.pager {
  margin-top: 12px;
  display: flex;
  gap: 12px;
  align-items: center;
  justify-content: flex-end;
}
.img-detail {
  display: flex;
  align-items: center;
  gap: 10px;
}
.hit-img {
  width: 44px;
  height: 44px;
  border-radius: 8px;
  flex: none;
}
.img-meta {
  display: flex;
  align-items: center;
  gap: 8px;
}
.score {
  color: var(--el-text-color-secondary);
  font-size: 12px;
}
.plain-detail {
  color: var(--el-text-color-regular);
}
.pv-meta {
  margin-bottom: 14px;
}
.pv-block {
  margin-bottom: 14px;
}
.pv-label {
  font-size: 12px;
  color: var(--el-text-color-secondary);
  margin-bottom: 6px;
}
.pv-content {
  white-space: pre-wrap;
  line-height: 1.7;
  color: var(--el-text-color-primary);
  background: var(--el-fill-color-lighter);
  border-radius: 10px;
  padding: 10px 12px;
}
.pv-logo {
  width: 64px;
  height: 64px;
  border-radius: 12px;
}
.pv-imgs {
  display: flex;
  flex-wrap: wrap;
  gap: 8px;
}
.pv-img {
  width: 96px;
  height: 96px;
  border-radius: 10px;
}
.pv-actions {
  margin-top: 18px;
  display: flex;
  gap: 10px;
}
</style>
