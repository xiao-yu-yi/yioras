import axios from "axios";

/** Yiora 后台登录结果(直连 /admin/v1,统一响应包已在此层解包) */
export type YioraLoginData = {
  token: string;
  expireAt: number;
  username: string;
  perms: string[];
  mustChangePwd: boolean;
  totpRequired?: boolean;
  ticket?: string;
};

type Wrapped<T> = { code: number; msg: string; data: T };

async function unwrap<T>(p: Promise<{ data: Wrapped<T> }>): Promise<T> {
  const { data: body } = await p;
  if (body.code !== 0) throw new Error(body.msg || "请求失败");
  return body.data;
}

/** 图形验证码 */
export const getCaptcha = () =>
  unwrap<{ captchaId: string; image: string }>(
    axios.get("/admin/v1/captcha")
  );

/** 第一步:账号密码 + 验证码 */
export const getLogin = (data: {
  username: string;
  password: string;
  captchaId: string;
  captchaCode: string;
}) => unwrap<YioraLoginData>(axios.post("/admin/v1/login", data));

/** 第二步:TOTP 动态口令 / 恢复码换正式令牌 */
export const getLoginTotp = (data: { ticket: string; code: string }) =>
  unwrap<YioraLoginData>(axios.post("/admin/v1/login/totp", data));
