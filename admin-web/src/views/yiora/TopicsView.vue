<template>
  <el-card>
    <template #header><span>话题管理(封禁 / 恢复 / 热度调整)</span></template>

    <el-form inline @submit.prevent="search">
      <el-form-item>
        <el-input v-model="keyword" placeholder="话题名" clearable style="width: 200px" @keyup.enter="search" @clear="search" />
      </el-form-item>
      <el-form-item>
        <el-select v-model="status" style="width: 120px" @change="search">
          <el-option :value="0" label="全部状态" />
          <el-option :value="1" label="正常" />
          <el-option :value="2" label="已封禁" />
        </el-select>
      </el-form-item>
      <el-button type="primary" @click="search">查询</el-button>
    </el-form>

    <el-table :data="rows" v-loading="loading">
      <el-table-column prop="id" label="ID" width="70" />
      <el-table-column label="话题" min-width="160">
        <template #default="{ row }">#{{ row.name }}#</template>
      </el-table-column>
      <el-table-column prop="postCount" label="帖子数" width="90" />
      <el-table-column label="热度" width="150">
        <template #default="{ row }">
          <el-input-number
            v-model="row.hotScore"
            :min="0"
            size="small"
            :controls="false"
            style="width: 100px"
            @change="saveHot(row)"
          />
        </template>
      </el-table-column>
      <el-table-column label="状态" width="90">
        <template #default="{ row }">
          <el-tag :type="row.status === 1 ? 'success' : 'danger'">{{ row.status === 1 ? '正常' : '已封禁' }}</el-tag>
        </template>
      </el-table-column>
      <el-table-column label="创建时间" width="160">
        <template #default="{ row }">{{ new Date(row.createdAt).toLocaleString('zh-CN') }}</template>
      </el-table-column>
      <el-table-column label="操作" width="100" fixed="right">
        <template #default="{ row }">
          <el-button v-if="row.status === 1" size="small" type="danger" @click="toggle(row, 2)">封禁</el-button>
          <el-button v-else size="small" type="success" @click="toggle(row, 1)">恢复</el-button>
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
  </el-card>
</template>

<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { ElMessage } from 'element-plus'
import { api, type AdminTopicItem } from '@/api/yiora'

const keyword = ref('')
const status = ref(0)
const page = ref(1)
const size = 20
const total = ref(0)
const rows = ref<AdminTopicItem[]>([])
const loading = ref(false)

async function load() {
  loading.value = true
  try {
    const data = await api.topics({ keyword: keyword.value.trim(), status: status.value, page: page.value, size })
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

async function toggle(row: AdminTopicItem, to: number) {
  await api.updateTopic(row.id, { status: to })
  ElMessage.success(to === 2 ? '已封禁,新帖不可再挂该话题' : '已恢复')
  load()
}

async function saveHot(row: AdminTopicItem) {
  await api.updateTopic(row.id, { hotScore: row.hotScore })
  ElMessage.success('热度已更新')
}

onMounted(load)
</script>

<style scoped>
.pager {
  margin-top: 14px;
}
</style>
