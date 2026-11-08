import { http } from '@kit.NetworkKit';
import { common } from '@kit.AbilityKit';
import { store } from './Store';
import { credentials, httpClient, ApiError } from './Http';
import { ApiEnvelope, ChatConfig, ConversationPage, UserInfo } from '../model/Types';

/** 登录成功后的会话态。 */
export interface Session {
  token: string;
  cookie: string;
}

interface LoginBody {
  userName: string;
  password: string;
  captcha?: string;
  captchaId?: string;
}

interface SmsSendBody {
  mobilephoneNum: string;
}

interface SmsLoginBody {
  mobilephoneNum: string;
  verifyCode: string;
}

class Auth {
  /** 最近一次成功登录走的是哪条路径（排查用）。 */
  lastLoginRoute: string = '';

  /** 启动时恢复登录态。 */
  restore(context: common.UIAbilityContext): boolean {
    store.init(context);
    credentials.token = store.getCloudToken();
    credentials.cookie = store.getCloudCookie();
    return credentials.token.length > 0;
  }

  isLoggedIn(): boolean {
    return credentials.token.length > 0;
  }

  /**
   * 账号密码登录。接口来自 APK 字符串：/sso/login（网页表单）与
   * /ac/api/auth/loginDesktopClient.action（客户端）。手机上以后者为准，
   * 若返回未登录则回落到 /sso/login 表单提交。
   */
  async loginByPassword(userName: string, password: string): Promise<void> {
    // APK 里同时存在"客户端登录"和 SSO 表单两条路，依次试，把每条的错误都记住。
    const attempts: string[] = [];
    const body: LoginBody = { userName: userName, password: password };

    try {
      // 实测：这个 .action 端点只吃 form-urlencoded，字段名是小写 username/password。
      const form = `username=${encodeURIComponent(userName)}&password=${encodeURIComponent(password)}`;
      const raw = await httpClient.postForm('/ac/api/auth/loginDesktopClient.action', form);
      this.consumeResponse(raw);
      this.lastLoginRoute = 'loginDesktopClient';
      return;
    } catch (e) {
      const err = e as ApiError;
      attempts.push(`loginDesktopClient: ${err.code} ${err.message}`);
      if (err.code === '1014') {
        // 已经是明确的"账号或密码错误"，不用再试 SSO
        throw new ApiError('1014', '账号或密码错误');
      }
    }

    try {
      const form = `userName=${encodeURIComponent(userName)}&password=${encodeURIComponent(password)}&rememberMe=true`;
      const raw = await httpClient.postForm('/sso/login', form);
      this.consumeResponse(raw);
      this.lastLoginRoute = 'sso/login';
      return;
    } catch (e) {
      const err = e as ApiError;
      attempts.push(`sso/login: ${err.code} ${err.message}`);
    }

    throw new ApiError('', attempts.join(' | '));
  }

  /** 发送短信验证码。 */
  async sendSmsCode(phone: string): Promise<void> {
    const body: SmsSendBody = { mobilephoneNum: phone };
    const raw = await httpClient.postRaw('/acx/user/users/verify-code-send', JSON.stringify(body));
    this.expectOk(raw, '验证码发送失败');
  }

  /** 短信验证码登录。 */
  async loginBySmsCode(phone: string, code: string): Promise<void> {
    const body: SmsLoginBody = { mobilephoneNum: phone, verifyCode: code };
    const raw = await httpClient.postRaw('/acx/user/users/verify-code-check', JSON.stringify(body));
    this.consumeResponse(raw);
  }

  /** 拉用户信息，同时刷新 token（includeToken=true&refresh=true）。 */
  async refreshUser(): Promise<UserInfo> {
    const data = await httpClient.getData('/acx/user/users/current-user-info?includeToken=true&refresh=true');
    return data as UserInfo;
  }

  /** 对话页需要的模型目录 / 集群 / 能力开关。 */
  async chatConfig(): Promise<ChatConfig> {
    const data = await httpClient.getData('/acx/chatbot/config/list');
    return data as ChatConfig;
  }

  async conversationList(): Promise<ConversationPage> {
    const data = await httpClient.getData('/acx/chatbot/conversation/list?page=1&size=30');
    return data as ConversationPage;
  }

  async logout(): Promise<void> {
    try {
      await httpClient.getData('/acx/user/users/logout');
    } catch (e) {
      // 服务端登出失败也要清本地
    }
    credentials.token = '';
    credentials.cookie = '';
    store.clearCloudAuth();
  }

  /** 从响应头抓 Set-Cookie（jsessionid 是用户态接口的必需品）。 */
  private captureCookie(raw: http.HttpResponse): void {
    const setCookie: string = raw.header === undefined ? '' : this.headerValue(raw.header, 'set-cookie');
    if (setCookie.length === 0) {
      return;
    }
    const parts: string[] = setCookie.split(';');
    let cookie: string = '';
    for (let i = 0; i < parts.length; i++) {
      const piece: string = parts[i].trim();
      if (piece.startsWith('jsessionid=') || piece.startsWith('Token=') ||
        piece.startsWith('SKIP_SESSION_UPDATE=')) {
        cookie = cookie.length === 0 ? piece : `${cookie}; ${piece}`;
      }
    }
    if (cookie.length > 0) {
      credentials.cookie = cookie;
      store.setCloudCookie(cookie);
    }
  }

  private headerValue(header: object, key: string): string {
    const map = header as Record<string, string>;
    const value = map[key];
    return value === undefined ? '' : value;
  }

  private consumeResponse(raw: http.HttpResponse): void {
    const text: string = typeof raw.result === 'string' ? raw.result as string : '';
    const env = text.length > 0 ? JSON.parse(text) as ApiEnvelope : null;
    const code: string = env === null || env.code === undefined ? '' : env.code;
    if (code !== '0' && code !== '200' && code !== '') {
      const msg: string = env === null || env.msg === undefined ? '登录失败' : env.msg;
      throw new ApiError(code, msg);
    }
    // token 可能来自响应体（data.token/accessToken）或响应头
    if (env !== null && env.data !== undefined) {
      const data = env.data as Record<string, string>;
      const token = data['token'] ?? data['accessToken'] ?? '';
      if (token.length > 0) {
        credentials.token = token;
        store.setCloudToken(token);
      }
    }
    this.captureCookie(raw);
    if (credentials.token.length === 0) {
      throw new ApiError('', '登录响应里没有 token，接口契约待确认');
    }
  }

  private expectOk(raw: http.HttpResponse, fallback: string): void {
    const text: string = typeof raw.result === 'string' ? raw.result as string : '';
    const env = JSON.parse(text) as ApiEnvelope;
    const code: string = env.code === undefined ? '' : env.code;
    if (code !== '0' && code !== '200' && code !== '') {
      throw new ApiError(code, env.msg === undefined ? fallback : env.msg);
    }
  }
}

/** 平台错误码 → 中文文案（1003 参数缺失 / 1014 账号或密码错）。 */
export function describeAuthError(code: string, msg: string): string {
  if (code === '1003') {
    return '登录参数缺失（服务端契约变了，请反馈给开发者）';
  }
  if (code === '1014') {
    return '账号或密码错误';
  }
  return msg.length > 0 ? msg : `登录失败 (${code})`;
}

export const auth: Auth = new Auth();
