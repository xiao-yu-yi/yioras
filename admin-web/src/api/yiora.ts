import axios from 'axios'
import { ElMessage } from 'element-plus'
import router from '@/router'
import { removeToken } from '@/utils/auth'

// Yiora 管理接口客户端:统一响应包 {code,msg,data,traceId},code!=0 一律抛错并提示。
// 独立于模板的 PureHttp,鉴权走 yiora_admin_token(登录时与模板 token 双写)。
const http = axios.create({ baseURL: '/admin/v1', timeout: 10000 })

http.interceptors.request.use((config) => {
  const token = localStorage.getItem('yiora_admin_token')
  if (token) config.headers.Authorization = `Bearer ${token}`
  return config
})

http.interceptors.response.use(
  (resp) => {
    const body = resp.data
    if (body.code !== 0) {
      if (body.code === 40100) {
        localStorage.removeItem('yiora_admin_token')
        removeToken()
        router.push('/login')
      }
      ElMessage.error(body.msg || '请求失败')
      return Promise.reject(new Error(body.msg))
    }
    return body.data
  },
  (err) => {
    ElMessage.error(err.message || '网络错误')
    return Promise.reject(err)
  },
)

export interface AuditItem {
  id: number
  bizType: number
  bizId: number
  machineResult: number
  machineDetail: string
  createdAt: number
}

export interface CertItem {
  id: number
  userId: number
  kind: number
  material: string
  createdAt: number
}

export interface OpLogItem {
  id: number
  adminId: number
  action: string
  target: string
  ip: string
  createdAt: number
}

export interface Dashboard {
  users: number
  todayUsers: number
  todayActive: number
  posts: number
  todayPosts: number
  software: number
  pendingAudits: number
  youzhuIssued: number
  youzhuBurned: number
}

export interface BannerItem {
  id: number
  title: string
  image: string
  linkType: number
  linkValue: string
  sort: number
  status: number
  startAt: number
  endAt: number
}

export interface AdminUserItem {
  userId: number
  displayNo: string
  nickname: string
  avatar: string
  email: string
  level: number
  status: number
  createdAt: number
  lastLoginAt: number
}

export interface AdminUserList {
  total: number
  list: AdminUserItem[]
}

export interface AdminContentItem {
  id: number
  authorId: number
  authorName: string
  title: string
  content: string
  status: number
  circleId?: number
  bizType?: number
  bizId?: number
  isTop: number
  isEssence: number
  likeCount: number
  viewCount: number
  createdAt: number
}

export interface AdminContentList {
  total: number
  list: AdminContentItem[]
}

export interface AdminReportItem {
  id: number
  reporterId: number
  reporterName: string
  targetType: number
  targetId: number
  targetBrief: string
  targetStatus: number
  category: number
  reason: string
  images: string[]
  status: number
  handledBy: number
  handledAt: number
  createdAt: number
}

export interface AdminReportList {
  total: number
  list: AdminReportItem[]
}

export interface AdminAccountItem {
  id: number
  username: string
  roleId: number
  roleName: string
  status: number
  lastLoginAt: number
}

export interface AdminRoleItem {
  id: number
  name: string
  perms: string[]
}

export interface AdminWordItem {
  id: number
  word: string
  category: number
  level: number
  status: number
  createdAt: number
}

export interface AdminFaqItem {
  id: number
  keywords: string
  reply: string
  priority: number
  status: number
  createdAt: number
}

export interface AdminDecoItem {
  id: number
  kind: number
  name: string
  preview: string
  price: number
  durationDays: number
  sort: number
  status: number
}

export interface AdminPrizeItem {
  id: number
  name: string
  kind: number
  refId: number
  amount: number
  weight: number
  stock: number
  status: number
}

export interface AdminTaskCfgItem {
  id: number
  name: string
  type: number
  action: string
  targetCount: number
  rewardYouzhu: number
  rewardExp: number
  sort: number
  status: number
}

export const api = {
  captcha: () => http.get('/captcha') as Promise<{ captchaId: string; image: string }>,
  login: (username: string, password: string, captchaId: string, captchaCode: string) =>
    http.post('/login', { username, password, captchaId, captchaCode }) as Promise<LoginResult>,
  loginTotp: (ticket: string, code: string) =>
    http.post('/login/totp', { ticket, code }) as Promise<LoginResult>,
  changePassword: (oldPassword: string, newPassword: string) =>
    http.post('/password', { oldPassword, newPassword }),
  totpStatus: () => http.get('/totp/status') as Promise<{ enabled: boolean; recoveryCodesLeft: number }>,
  totpSetup: () =>
    http.post('/totp/setup') as Promise<{ secret: string; uri: string; recoveryCodes: string[] }>,
  totpConfirm: (code: string) => http.post('/totp/confirm', { code }),
  totpDisable: (code: string) => http.post('/totp/disable', { code }),
  admins: () => http.get('/admins') as Promise<AdminAccountItem[]>,
  createAdmin: (username: string, password: string, roleId: number) =>
    http.post('/admins', { username, password, roleId }) as Promise<{ id: number }>,
  updateAdmin: (id: number, patch: { roleId?: number; status?: number; newPassword?: string; resetTotp?: boolean }) =>
    http.post(`/admins/${id}`, patch),
  roles: () => http.get('/roles') as Promise<AdminRoleItem[]>,
  audits: (bizType: number, page: number) =>
    http.get('/audits', { params: { bizType, page, size: 20 } }) as Promise<AuditItem[]>,
  decide: (id: number, approve: boolean, reason: string) =>
    http.post(`/audits/${id}/decide`, { approve, reason }),
  certs: (page: number) =>
    http.get('/certifications', { params: { page, size: 20 } }) as Promise<CertItem[]>,
  decideCert: (id: number, approve: boolean, reason: string) =>
    http.post(`/certifications/${id}/decide`, { approve, reason }),
  oplogs: (page: number) =>
    http.get('/oplogs', { params: { page, size: 20 } }) as Promise<OpLogItem[]>,
  dashboard: () => http.get('/dashboard') as Promise<Dashboard>,
  banners: () => http.get('/banners') as Promise<BannerItem[]>,
  saveBanner: (b: Partial<BannerItem>) => http.post('/banners', b) as Promise<{ id: number }>,
  deleteBanner: (id: number) => http.delete(`/banners/${id}`),
  users: (params: { keyword?: string; status?: number; page: number; size: number }) =>
    http.get('/users', { params }) as Promise<AdminUserList>,
  contents: (params: { type: number; keyword?: string; status: number; page: number; size: number }) =>
    http.get('/contents', { params }) as Promise<AdminContentList>,
  reports: (params: { status: number; targetType: number; page: number; size: number }) =>
    http.get('/reports', { params }) as Promise<AdminReportList>,
  handleReport: (id: number, action: number) => http.post(`/reports/${id}/handle`, { action }),
  takedownContent: (type: number, id: number, action: number, reason: string) =>
    http.post('/contents/takedown', { type, id, action, reason }),
  banUser: (userId: number, action: number, days: number) =>
    http.post(`/users/${userId}/ban`, { action, days }),
  publishNotice: (title: string, content: string) => http.post('/notices', { title, content }),
  words: (params: { keyword?: string; category: number; level: number; status: number; page: number; size: number }) =>
    http.get('/words', { params }) as Promise<{ total: number; list: AdminWordItem[] }>,
  saveWord: (w: Partial<AdminWordItem>) => http.post('/words', w) as Promise<{ id: number }>,
  deleteWord: (id: number) => http.delete(`/words/${id}`),
  faqs: (page: number) =>
    http.get('/faqs', { params: { page, size: 20 } }) as Promise<{ total: number; list: AdminFaqItem[] }>,
  saveFaq: (f: Partial<AdminFaqItem>) => http.post('/faqs', f) as Promise<{ id: number }>,
  deleteFaq: (id: number) => http.delete(`/faqs/${id}`),
  mallDecos: () => http.get('/mall/decorations') as Promise<AdminDecoItem[]>,
  saveMallDeco: (d: Partial<AdminDecoItem>) => http.post('/mall/decorations', d) as Promise<{ id: number }>,
  mallPrizes: () => http.get('/mall/prizes') as Promise<AdminPrizeItem[]>,
  saveMallPrize: (p: Partial<AdminPrizeItem>) => http.post('/mall/prizes', p) as Promise<{ id: number }>,
  mallTasks: () => http.get('/mall/tasks') as Promise<AdminTaskCfgItem[]>,
  saveMallTask: (t: Partial<AdminTaskCfgItem>) => http.post('/mall/tasks', t) as Promise<{ id: number }>,
  trend: (days: number) =>
    http.get('/dashboard/trend', { params: { days } }) as Promise<{
      dates: string[]
      users: number[]
      posts: number[]
      youzhuIssued: number[]
      youzhuBurned: number[]
    }>,
  categories: () => http.get('/software/categories') as Promise<AdminCategoryItem[]>,
  saveCategory: (c: Partial<AdminCategoryItem>) => http.post('/software/categories', c) as Promise<{ id: number }>,
  presign: (kind: string, fileName: string, size: number) =>
    http.post('/upload/presign', { kind, fileName, size }) as Promise<{ uploadUrl: string; fileUrl: string }>,
  // 圈子管理
  circles: (params: { keyword?: string; page: number; size: number }) =>
    http.get('/circles', { params }) as Promise<{ total: number; list: AdminCircleItem[] }>,
  saveCircle: (c: Partial<AdminCircleItem>) => http.post('/circles', c) as Promise<{ id: number }>,
  appointCircle: (circleId: number, userId: number, role: number) =>
    http.post(`/circles/${circleId}/appoint`, { userId, role }),
  // 帖子运营位
  postOps: (postId: number, patch: { isTop?: number; isEssence?: number }) =>
    http.post(`/posts/${postId}/ops`, patch),
  // 话题管理
  topics: (params: { keyword?: string; status: number; page: number; size: number }) =>
    http.get('/topics', { params }) as Promise<{ total: number; list: AdminTopicItem[] }>,
  updateTopic: (id: number, patch: { status?: number; hotScore?: number }) =>
    http.post(`/topics/${id}`, patch),
  // 忧珠运营
  grantYouzhu: (userId: number, amount: number, reason: string) =>
    http.post('/youzhu/grant', { userId, amount, reason }),
  youzhuLogs: (params: { userId?: number; bizType: number; page: number; size: number }) =>
    http.get('/youzhu/logs', { params }) as Promise<{ total: number; list: AdminYouzhuLogItem[] }>,
  // 靓号库
  prettyNos: (params: { keyword?: string; status: number; page: number; size: number }) =>
    http.get('/mall/prettynos', { params }) as Promise<{ total: number; list: AdminPrettyNoItem[] }>,
  savePrettyNo: (p: Partial<AdminPrettyNoItem>) => http.post('/mall/prettynos', p) as Promise<{ id: number }>,
  deletePrettyNo: (id: number) => http.delete(`/mall/prettynos/${id}`),
  // 用户等级/头衔
  setUserLevel: (userId: number, patch: { level?: number; exp?: number }) =>
    http.post(`/users/${userId}/level`, patch),
  grantUserTitle: (userId: number, kind: number, grant: boolean) =>
    http.post(`/users/${userId}/title`, { kind, grant }),
  // 协议管理
  agreement: (kind: string) =>
    http.get(`/agreements/${kind}`) as Promise<{ kind: string; title: string; content: string; updatedAt: number }>,
  saveAgreement: (kind: string, title: string, content: string) =>
    http.post(`/agreements/${kind}`, { title, content }),
}

export interface AdminCircleItem {
  id: number
  name: string
  icon: string
  cover: string
  intro: string
  description: string
  memberCount: number
  postCount: number
  isOfficial: number
  pinned: number
  sort: number
  status: number
}

export interface AdminTopicItem {
  id: number
  name: string
  postCount: number
  hotScore: number
  status: number
  createdAt: number
}

export interface AdminYouzhuLogItem {
  id: number
  userId: number
  nickname: string
  bizType: number
  bizKey: string
  amount: number
  balanceAfter: number
  remark: string
  createdAt: number
}

export interface AdminPrettyNoItem {
  id: number
  no: string
  rarity: number
  price: number
  status: number
  soldTo: number
  soldAt: number
}

// uploadFile 预签名直传:签名 → 裸 PUT 文件到对象存储 → 返回可落库的公开 URL
export async function uploadFile(kind: string, file: File): Promise<string> {
  const { uploadUrl, fileUrl } = await api.presign(kind, file.name, file.size)
  await axios.put(uploadUrl, file, { headers: { 'Content-Type': file.type || 'application/octet-stream' } })
  return fileUrl
}

export interface AdminCategoryItem {
  id: number
  type: number
  name: string
  sort: number
  status: number
}

export interface LoginResult {
  token: string
  username: string
  perms: string[]
  totpRequired?: boolean
  ticket?: string
}
