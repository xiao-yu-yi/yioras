import { defineStore } from "pinia";
import {
  type userType,
  store,
  router,
  resetRouter,
  routerArrays,
  storageLocal
} from "../utils";
import {
  type YioraLoginData,
  getLogin,
  getLoginTotp
} from "@/api/user";
import { useMultiTagsStoreHook } from "./multiTags";
import { type DataInfo, setToken, removeToken, userKey } from "@/utils/auth";

export const useUserStore = defineStore("pure-user", {
  state: (): userType => ({
    avatar: storageLocal().getItem<DataInfo<number>>(userKey)?.avatar ?? "",
    username: storageLocal().getItem<DataInfo<number>>(userKey)?.username ?? "",
    nickname: storageLocal().getItem<DataInfo<number>>(userKey)?.nickname ?? "",
    roles: storageLocal().getItem<DataInfo<number>>(userKey)?.roles ?? [],
    permissions:
      storageLocal().getItem<DataInfo<number>>(userKey)?.permissions ?? [],
    isRemembered: false,
    loginDay: 7
  }),
  actions: {
    SET_AVATAR(avatar: string) {
      this.avatar = avatar;
    },
    SET_USERNAME(username: string) {
      this.username = username;
    },
    SET_NICKNAME(nickname: string) {
      this.nickname = nickname;
    },
    SET_ROLES(roles: Array<string>) {
      this.roles = roles;
    },
    SET_PERMS(permissions: Array<string>) {
      this.permissions = permissions;
    },
    SET_ISREMEMBERED(bool: boolean) {
      this.isRemembered = bool;
    },
    SET_LOGINDAY(value: number) {
      this.loginDay = Number(value);
    },

    /** 令牌落地:模板 token(路由守卫用)与 yiora token(业务接口用)双写 */
    applyLogin(res: YioraLoginData) {
      localStorage.setItem("yiora_admin_token", res.token);
      localStorage.setItem("yiora_admin_name", res.username);
      if (res.mustChangePwd) {
        localStorage.setItem("yiora_admin_must_pwd", "1");
      } else {
        localStorage.removeItem("yiora_admin_must_pwd");
      }
      setToken({
        accessToken: res.token,
        refreshToken: res.token,
        expires: new Date(res.expireAt),
        username: res.username,
        nickname: res.username,
        roles: ["admin"],
        permissions: ["*:*:*"],
        avatar: ""
      });
    },

    /** 第一步登录:密码+验证码;若已开二步验证只拿到 ticket,由登录页继续第二步 */
    async loginByUsername(data: {
      username: string;
      password: string;
      captchaId: string;
      captchaCode: string;
    }) {
      const res = await getLogin(data);
      if (!res.totpRequired) this.applyLogin(res);
      return res;
    },

    /** 第二步登录:TOTP 口令/恢复码换正式令牌 */
    async loginByTotp(data: { ticket: string; code: string }) {
      const res = await getLoginTotp(data);
      this.applyLogin(res);
      return res;
    },

    /** 前端登出(不调用接口) */
    logOut() {
      this.username = "";
      this.roles = [];
      this.permissions = [];
      localStorage.removeItem("yiora_admin_token");
      localStorage.removeItem("yiora_admin_name");
      localStorage.removeItem("yiora_admin_must_pwd");
      removeToken();
      useMultiTagsStoreHook().handleTags("equal", [...routerArrays]);
      resetRouter();
      router.push("/login");
    },

    /** 管理令牌 8h 无刷新机制:过期即登出重登(_data 兼容模板 http 层的调用签名) */
    async handRefreshToken(_data?: object) {
      this.logOut();
      return Promise.reject(new Error("登录已过期,请重新登录"));
    }
  }
});

export function useUserStoreHook() {
  return useUserStore(store);
}
