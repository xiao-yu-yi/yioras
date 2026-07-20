import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'

// 开发代理直连本地 compose 的 api 服务
export default defineConfig({
  plugins: [vue()],
  server: {
    port: 5173,
    proxy: {
      '/admin/v1': {
        target: 'http://localhost:8888',
        changeOrigin: true,
      },
    },
  },
})
