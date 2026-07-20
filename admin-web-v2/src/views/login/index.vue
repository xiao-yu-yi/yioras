<script setup lang="ts">
import Motion from "./utils/motion";
import { useRouter } from "vue-router";
import { message } from "@/utils/message";
import { loginRules } from "./utils/rule";
import { ref, reactive, toRaw, onMounted } from "vue";
import { debounce } from "@pureadmin/utils";
import { useNav } from "@/layout/hooks/useNav";
import { useEventListener } from "@vueuse/core";
import type { FormInstance } from "element-plus";
import { useLayout } from "@/layout/hooks/useLayout";
import { useUserStoreHook } from "@/store/modules/user";
import { getCaptcha } from "@/api/user";
import { initRouter, getTopMenu } from "@/router/utils";
import { bg, avatar, illustration } from "./utils/static";
import { useRenderIcon } from "@/components/ReIcon/src/hooks";
import { useDataThemeChange } from "@/layout/hooks/useDataThemeChange";

import dayIcon from "@/assets/svg/day.svg?component";
import darkIcon from "@/assets/svg/dark.svg?component";
import Lock from "~icons/ri/lock-fill";
import User from "~icons/ri/user-3-fill";
import ShieldKeyhole from "~icons/ri/shield-keyhole-fill";

defineOptions({
  name: "Login"
});

const router = useRouter();
const loading = ref(false);
const disabled = ref(false);
const ruleFormRef = ref<FormInstance>();

const { initStorage } = useLayout();
initStorage();

const { dataTheme, overallStyle, dataThemeChange } = useDataThemeChange();
dataThemeChange(overallStyle.value);
const { title } = useNav();

const ruleForm = reactive({
  username: "admin",
  password: "",
  captchaCode: ""
});
const captchaId = ref("");
const captchaImg = ref("");

/** 二步验证态:密码通过后持 ticket 输入动态口令 */
const totpTicket = ref("");
const totpCode = ref("");

async function refreshCaptcha() {
  ruleForm.captchaCode = "";
  try {
    const data = await getCaptcha();
    captchaId.value = data.captchaId;
    captchaImg.value = data.image;
  } catch {
    message("验证码加载失败,点击图片重试", { type: "warning" });
  }
}

/** 登录成功后的统一去向:强制改密页或首页 */
function afterLogin(mustChangePwd: boolean) {
  if (mustChangePwd) {
    message("首次登录请先修改初始密码", { type: "warning" });
    router.push("/change-password");
    return;
  }
  initRouter().then(() => {
    disabled.value = true;
    router
      .push(getTopMenu(true).path)
      .then(() => message("登录成功", { type: "success" }))
      .finally(() => (disabled.value = false));
  });
}

const onLogin = async (formEl: FormInstance | undefined) => {
  if (!formEl) return;
  await formEl.validate(valid => {
    if (!valid) return;
    if (!ruleForm.captchaCode.trim()) {
      message("请输入验证码", { type: "warning" });
      return;
    }
    loading.value = true;
    useUserStoreHook()
      .loginByUsername({
        username: ruleForm.username,
        password: ruleForm.password,
        captchaId: captchaId.value,
        captchaCode: ruleForm.captchaCode.trim()
      })
      .then(res => {
        if (res.totpRequired && res.ticket) {
          totpTicket.value = res.ticket;
          totpCode.value = "";
          return;
        }
        afterLogin(res.mustChangePwd);
      })
      .catch((e: Error) => {
        message(e.message || "登录失败", { type: "error" });
        refreshCaptcha(); // 验证码一次性,失败必须换新
      })
      .finally(() => (loading.value = false));
  });
};

const onLoginTotp = () => {
  if (!totpCode.value.trim()) {
    message("请输入动态口令或恢复码", { type: "warning" });
    return;
  }
  loading.value = true;
  useUserStoreHook()
    .loginByTotp({ ticket: totpTicket.value, code: totpCode.value.trim() })
    .then(res => afterLogin(res.mustChangePwd))
    .catch((e: Error) => {
      message(e.message || "校验失败", { type: "error" });
      if (e.message?.includes("票据")) backToLogin();
    })
    .finally(() => (loading.value = false));
};

function backToLogin() {
  totpTicket.value = "";
  totpCode.value = "";
  refreshCaptcha();
}

const immediateDebounce: any = debounce(
  formRef => (totpTicket.value ? onLoginTotp() : onLogin(formRef)),
  1000,
  true
);

useEventListener(document, "keydown", ({ code }) => {
  if (
    ["Enter", "NumpadEnter"].includes(code) &&
    !disabled.value &&
    !loading.value
  )
    immediateDebounce(ruleFormRef.value);
});

onMounted(refreshCaptcha);
</script>

<template>
  <div class="select-none">
    <img :src="bg" class="wave" />
    <div class="flex-c absolute right-5 top-3">
      <!-- 主题 -->
      <el-switch
        v-model="dataTheme"
        inline-prompt
        :active-icon="dayIcon"
        :inactive-icon="darkIcon"
        @change="dataThemeChange"
      />
    </div>
    <div class="login-container">
      <div class="img">
        <component :is="toRaw(illustration)" />
      </div>
      <div class="login-box">
        <div class="login-form">
          <avatar class="avatar" />
          <Motion>
            <h2 class="outline-hidden">{{ title }}</h2>
          </Motion>

          <!-- 第一步:账号密码 + 图形验证码 -->
          <el-form
            v-if="!totpTicket"
            ref="ruleFormRef"
            :model="ruleForm"
            :rules="loginRules"
            size="large"
          >
            <Motion :delay="100">
              <el-form-item
                :rules="[
                  {
                    required: true,
                    message: '请输入账号',
                    trigger: 'blur'
                  }
                ]"
                prop="username"
              >
                <el-input
                  v-model="ruleForm.username"
                  clearable
                  placeholder="账号"
                  :prefix-icon="useRenderIcon(User)"
                />
              </el-form-item>
            </Motion>

            <Motion :delay="150">
              <el-form-item prop="password">
                <el-input
                  v-model="ruleForm.password"
                  clearable
                  show-password
                  placeholder="密码"
                  :prefix-icon="useRenderIcon(Lock)"
                />
              </el-form-item>
            </Motion>

            <Motion :delay="200">
              <el-form-item prop="captchaCode">
                <div class="captcha-row">
                  <el-input
                    v-model="ruleForm.captchaCode"
                    clearable
                    placeholder="验证码"
                    maxlength="5"
                    :prefix-icon="useRenderIcon(ShieldKeyhole)"
                  />
                  <img
                    v-if="captchaImg"
                    :src="captchaImg"
                    class="captcha-img"
                    title="点击刷新验证码"
                    @click="refreshCaptcha"
                  />
                </div>
              </el-form-item>
            </Motion>

            <Motion :delay="250">
              <el-button
                class="w-full mt-4!"
                size="default"
                type="primary"
                :loading="loading"
                :disabled="disabled"
                @click="onLogin(ruleFormRef)"
              >
                登录
              </el-button>
            </Motion>
          </el-form>

          <!-- 第二步:TOTP 动态口令 / 恢复码 -->
          <el-form v-else size="large">
            <Motion>
              <el-alert
                class="mb-4"
                type="info"
                :closable="false"
                title="该账号已启用二步验证,请输入验证器动态口令(或一次性恢复码)"
                show-icon
              />
            </Motion>
            <Motion :delay="100">
              <el-form-item>
                <el-input
                  v-model="totpCode"
                  clearable
                  placeholder="6 位动态口令 / 恢复码"
                  maxlength="10"
                  :prefix-icon="useRenderIcon(ShieldKeyhole)"
                />
              </el-form-item>
            </Motion>
            <Motion :delay="150">
              <el-button
                class="w-full mt-4!"
                size="default"
                type="primary"
                :loading="loading"
                @click="onLoginTotp"
              >
                验证并登录
              </el-button>
            </Motion>
            <Motion :delay="200">
              <el-button class="w-full mt-2!" size="default" @click="backToLogin">
                返回重新登录
              </el-button>
            </Motion>
          </el-form>
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
@import url("@/style/login.css");
</style>

<style lang="scss" scoped>
:deep(.el-input-group__append, .el-input-group__prepend) {
  padding: 0;
}

.captcha-row {
  display: flex;
  gap: 8px;
  width: 100%;

  .captcha-img {
    height: 40px;
    border-radius: 4px;
    cursor: pointer;
    flex-shrink: 0;
  }
}
</style>
