import { http } from '@kit.NetworkKit';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
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
    hilog.info(0x0000, 'SCNetLite', 'restore: token=%{public}d cookie=%{public}d',
      credentials.token.length, credentials.cookie.length);
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

  /**
   * 从响应头抓 cookie。ArkTS 的 HttpResponse.header 是 Object，直接按 key 取值
   * 在不同版本上行为不一致（踩过 "split is undefined"），这里统一 stringify 后提取。
   */
  private captureCookie(raw: http.HttpResponse): void {
    let dump: string = '';
    try {
      dump = raw.header === undefined ? '' : JSON.stringify(raw.header);
    } catch (e) {
      dump = '';
    }
    if (dump.length === 0) {
      return;
    }
    hilog.info(0x0000, 'SCNetLite', 'resp headers: %{public}s', dump.length > 400 ? dump.substring(0, 400) : dump);
    const picked: string[] = [];
    const names: string[] = ['jsessionid', 'Token', 'SKIP_SESSION_UPDATE'];
    for (let i = 0; i < names.length; i++) {
      const name: string = names[i];
      const idx: number = dump.indexOf(`${name}=`);
      if (idx < 0) {
        continue;
      }
      let end: number = idx;
      while (end < dump.length) {
        const ch: string = dump.charAt(end);
        if (ch === '"' || ch === ';' || ch === '\n') {
          break;
        }
        end++;
      }
      picked.push(dump.substring(idx, end));
    }
    if (picked.length > 0) {
      const cookie: string = picked.join('; ');
      credentials.cookie = cookie;
      store.setCloudCookie(cookie);
    }
  }

  private consumeResponse(raw: http.HttpResponse): void {
    const text: string = typeof raw.result === 'string' ? raw.result as string : '';
    this.captureCookie(raw);
    const trimmed: string = text.trim();

    // SSO 成功时返回 HTML 页面，不是 JSON；只有 JSON 才解析
    if (trimmed.startsWith('{')) {
      let env: ApiEnvelope;
      try {
        env = JSON.parse(trimmed) as ApiEnvelope;
      } catch (e) {
        throw new ApiError('', '登录响应不是合法 JSON');
      }
      const code: string = env.code === undefined ? '' : env.code;
      if (code !== '0' && code !== '200' && code !== '') {
        const msg: string = env.msg === undefined ? '登录失败' : env.msg;
        throw new ApiError(code, msg);
      }
      if (env.data !== undefined) {
        const data = env.data as Record<string, string>;
        const token = data['token'] ?? data['accessToken'] ?? '';
        if (token.length > 0) {
          credentials.token = token;
          store.setCloudToken(token);
        }
      }
    }

    // 响应体里没 token 时，看 cookie 里的 Token=（平台把 SSO token 放在 cookie 里）
    if (credentials.token.length === 0 && credentials.cookie.length > 0) {
      const idx: number = credentials.cookie.indexOf('Token=');
      if (idx >= 0) {
        const rest: string = credentials.cookie.substring(idx + 6);
        const end: number = rest.indexOf(';');
        const token: string = end >= 0 ? rest.substring(0, end) : rest;
        if (token.length > 0) {
          credentials.token = token;
          store.setCloudToken(token);
        }
      }
    }

    if (credentials.token.length === 0) {
      const tail: string = trimmed.length > 120 ? trimmed.substring(0, 120) : trimmed;
      throw new ApiError('', `登录成功但没拿到 token（响应：${tail}）`);
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
