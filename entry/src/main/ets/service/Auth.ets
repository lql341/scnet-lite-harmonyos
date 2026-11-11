import { http } from '@kit.NetworkKit';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { store } from './Store';
import { credentials, httpClient, ApiError } from './Http';
import { ApiEnvelope, ChatConfig, ConversationPage, HistoryPage, UserInfo } from '../model/Types';
import { AgentService } from '../model/Pick';

/** 登录成功后的会话态。 */
export interface Session {
  token: string;
  cookie: string;
}

/**
 * 集群侧身份。`accountId` 是**集群账号**（≠ 用户 id），
 * `authorize` / 建团队 key 都用它（实测用用户 id 会 API010006 无权限访问）。
 */
export interface ClusterIdentity {
  accountId: string;
  groupId: string;
  createUser: string;
  clusterName: string;
}

/** 一个可用集群（`cluster-user-detail` 的一行，跨集群去重后）。 */
export interface ClusterInfo {
  clusterId: number;
  clusterName: string;
  accountId: string;
  groupId: string;
  createUser: string;
  status: string;
}

interface RenameBody {
  conversationId: string;
  title: string;
}

interface ClusterRow {
  clusterId?: number;
  accountId?: string;
  groupId?: string;
  userId?: string;
  status?: string;
  clusterName?: string;
  memberType?: string;
}

interface LoginBody {
  userName: string;
  password: string;
  captcha?: string;
  captchaId?: string;
}

interface SmsSendBody {
  phoneNum: string;
}

interface SmsLoginBody {
  phoneNum: string;
  messageCode: string;
}

class Auth {
  /** 最近一次成功登录走的是哪条路径（排查用）。 */
  lastLoginRoute: string = '';

  /**
   * 为什么会停在登录页——登录页据此给出说明，而不是让用户莫名回到登录。
   * 'expired' 登录过期 / 'unauthenticated' 需要登录 / 'manual' 主动退出
   */
  loginReason: string = 'unauthenticated';

  /** 标记登录态失效（token 过期 / 401 / cookie 失效都走这里）。 */
  noteSessionExpired(): void {
    credentials.token = '';
    credentials.cookie = '';
    store.clearCloudAuth();
    this.loginReason = 'expired';
    hilog.info(0x0000, 'SCNetLite', 'session expired, back to login');
  }

  /** 主动退出：不提示「已过期」。 */
  noteManualLogout(): void {
    store.setHadSession(false);
    this.loginReason = 'manual';
  }

  /** 首次使用（没有历史登录）。 */
  noteFirstRun(): void {
    this.loginReason = 'unauthenticated';
  }

  /** 启动时恢复登录态。 */
  restore(context: common.UIAbilityContext): boolean {
    store.init(context);
    credentials.token = store.getCloudToken();
    credentials.cookie = store.getCloudCookie();
    hilog.info(0x0000, 'SCNetLite', 'restore: token=%{public}d cookie=%{public}d hadSession=%{public}s',
      credentials.token.length, credentials.cookie.length, String(store.hadSession()));
    if (credentials.token.length > 0) {
      store.setHadSession(true);
      this.loginReason = '';
      return true;
    }
    // 有历史登录但凭据没了 → 明确告诉用户是"过期"，而不是当作首次使用
    this.loginReason = store.hadSession() ? 'expired' : 'unauthenticated';
    return false;
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
      this.markLoggedIn(userName.trim());
      return;
    } catch (e) {
      const err = e as ApiError;
      attempts.push(`loginDesktopClient: ${err.code} ${err.message}`);
      if (err.code === '1014') {
        // 有验证码门时 1014 也会出现，文案要说清楚否则很容易误判成密码错
        const need: boolean = await this.needCaptcha();
        throw new ApiError('1014', need ? '需要图形验证码（请先在网页端登录一次）或账号密码错误' : '账号或密码错误');
      }
    }

    try {
      const form = `userName=${encodeURIComponent(userName)}&password=${encodeURIComponent(password)}&rememberMe=true`;
      const raw = await httpClient.postForm('/sso/login', form);
      this.consumeResponse(raw);
      this.lastLoginRoute = 'sso/login';
      this.markLoggedIn(userName.trim());
      return;
    } catch (e) {
      const err = e as ApiError;
      attempts.push(`sso/login: ${err.code} ${err.message}`);
    }

    throw new ApiError('', attempts.join(' | '));
  }

  /**
   * 发送短信验证码。
   * 实测（2026-11-09）：正确的端点是 DesktopClient 这套，字段名是 phoneNum；
   * `/acx/user/users/verify-code-send` 是"绑定手机"用的，未登录会 401。
   * 错误码：1016 发送失败（频控/通道） · 1022 手机号不存在。
   */
  async sendSmsCode(phone: string): Promise<void> {
    const body: SmsSendBody = { phoneNum: phone };
    const raw = await httpClient.postForm('/ac/api/auth/sendDesktopClientPhoneCode.action',
      `phoneNum=${encodeURIComponent(body.phoneNum)}`);
    this.expectOk(raw, '验证码发送失败');
  }

  /**
   * 短信验证码登录。字段是 phoneNum + messageCode（不是 mobilephoneNum/verifyCode）。
   * 错误码：1006 验证码错误或过期。
   */
  async loginBySmsCode(phone: string, code: string): Promise<void> {
    const body: SmsLoginBody = { phoneNum: phone, messageCode: code };
    const raw = await httpClient.postForm('/ac/api/auth/loginDesktopClientByPhoneCode.action',
      `phoneNum=${encodeURIComponent(body.phoneNum)}&messageCode=${encodeURIComponent(body.messageCode)}`);
    this.consumeResponse(raw);
    this.markLoggedIn('');
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

  /**
   * 集群身份（`cluster-user-detail`）。
   * ⚠️ `authorize` / 团队 key 用的是这里的 `accountId`（集群账号，如 <集群账号ID>），
   * **不是** `current-user-info` 里的 `id`（<用户ID>）—— 用后者会 `API010006 无权限访问`。
   * 该接口按集群返回多行（一台集群一行），同一账号的 accountId/groupId/userId 是重复的，取第一行即可。
   */
  /**
   * 全部可用集群（去重）。平台按"账号 × 集群"返回多行，
   * 本账号实测 13 个（华东一区昆山 / 西北二区甘肃 / 华北二区太原 …），
   * 其中 status=inactive 的排在后面。
   */
  async clusters(): Promise<ClusterInfo[]> {
    const out: ClusterInfo[] = [];
    try {
      const data = await httpClient.getData('/acx/user/users/cluster-user-detail');
      const rows: ClusterRow[] = data as ClusterRow[];
      if (!Array.isArray(rows)) {
        return out;
      }
      const seen: number[] = [];
      for (let i = 0; i < rows.length; i++) {
        const row: ClusterRow = rows[i];
        const id: number = row.clusterId ?? 0;
        if (id <= 0 || seen.indexOf(id) >= 0) {
          continue;
        }
        seen.push(id);
        const info: ClusterInfo = {
          clusterId: id,
          clusterName: row.clusterName ?? `集群 ${id}`,
          accountId: row.accountId ?? '',
          groupId: row.groupId ?? '',
          createUser: row.userId ?? '',
          status: row.status ?? ''
        };
        out.push(info);
      }
      out.sort((a: ClusterInfo, b: ClusterInfo) => {
        const ax: number = a.status === 'inactive' ? 1 : 0;
        const bx: number = b.status === 'inactive' ? 1 : 0;
        return ax - bx;
      });
      hilog.info(0x0000, 'SCNetLite', 'clusters: %{public}d', out.length);
    } catch (e) {
      hilog.warn(0x0000, 'SCNetLite', 'clusters failed');
    }
    return out;
  }

  async clusterIdentity(): Promise<ClusterIdentity> {
    const empty: ClusterIdentity = { accountId: '', groupId: '', createUser: '', clusterName: '' };
    try {
      const data = await httpClient.getData('/acx/user/users/cluster-user-detail');
      const rows: ClusterRow[] = data as ClusterRow[];
      if (!Array.isArray(rows)) {
        return empty;
      }
      for (let i = 0; i < rows.length; i++) {
        const row: ClusterRow = rows[i];
        const accountId: string = row.accountId ?? '';
        const groupId: string = row.groupId ?? '';
        const userId: string = row.userId ?? '';
        const status: string = row.status ?? '';
        if (accountId.length > 0 && groupId.length > 0 && userId.length > 0 && status !== 'inactive') {
          const identity: ClusterIdentity = {
            accountId: accountId,
            groupId: groupId,
            createUser: userId,
            clusterName: row.clusterName ?? ''
          };
          hilog.info(0x0000, 'SCNetLite', 'cluster identity: account=%{public}s group=%{public}s',
            accountId, groupId);
          return identity;
        }
      }
      return empty;
    } catch (e) {
      hilog.warn(0x0000, 'SCNetLite', 'cluster-user-detail failed');
      return empty;
    }
  }

  /**
   * 平台智能体服务表。智能体通道的 modelId 只能从这里拿
   * （`aiagent-router` = 600，见 docs/PROTOCOL.md §0）。
   */
  async agentServices(): Promise<AgentService[]> {
    const data = await httpClient.getData('/acx/chatbot/recommend/list?enable=true');
    return data as AgentService[];
  }

  /** 某个会话的历史消息（v2）。 */
  async loadHistory(conversationId: string): Promise<HistoryPage> {
    const data = await httpClient.getData(
      `/acx/chatbot/v2/agent/conversation/${conversationId}/history?page=1&size=50`);
    return data as HistoryPage;
  }

  /** 平台会话重命名（`PUT /acx/chatbot/conversation/rename`）。 */
  async renameConversation(conversationId: string, title: string): Promise<boolean> {
    try {
      const body: RenameBody = { conversationId: conversationId, title: title };
      await httpClient.postJson('/acx/chatbot/conversation/rename', JSON.stringify(body));
      return true;
    } catch (e) {
      hilog.warn(0x0000, 'SCNetLite', 'rename conversation failed');
      return false;
    }
  }

  async conversationList(): Promise<ConversationPage> {
    const data = await httpClient.getData('/acx/chatbot/conversation/list?page=1&size=30');
    return data as ConversationPage;
  }

  async logout(): Promise<void> {
    // 平台侧登出：桌面客户端用 POST /ac/api/auth/logoutDesktopClient.action
    try {
      await httpClient.postForm('/ac/api/auth/logoutDesktopClient.action', '');
    } catch (e) {
      try {
        await httpClient.getData('/acx/user/users/logout');
      } catch (e2) {
        // 服务端登出失败也要清本地
      }
    }
    credentials.token = '';
    credentials.cookie = '';
    store.clearCloudAuth();
    this.noteManualLogout();
  }

  /**
   * 平台是否要求图形验证码（厂商拼写就是 isNeedCpatcha）。
   * 实测平时返回 `data:false`（不需要）；真需要时拿图走 `getClientCaptcha.action`，
   * 登录表单字段是 `username/password/captcha/captchaKey`（全小写 username）。
   * 本版只用它把错误文案说清楚，还没做验证码输入 UI（见 docs/PROTOCOL.md §10.2）。
   */
  async needCaptcha(): Promise<boolean> {
    try {
      const data = await httpClient.getData('/ac/api/auth/isNeedCpatcha.action');
      return String(data) === 'true';
    } catch (e) {
      return false;
    }
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

  /** 登录成功后统一收口：记住账号、标记曾登录、清掉登录页提示。 */
  private markLoggedIn(userName: string): void {
    if (userName.length > 0) {
      store.setPlatformUserName(userName);
    }
    store.setHadSession(true);
    this.loginReason = '';
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
  if (code === '1006') {
    return '验证码错误或已过期';
  }
  if (code === '1016') {
    return '验证码发送失败（可能是频率限制，稍后再试）';
  }
  if (code === '1022') {
    return '该手机号未注册';
  }
  return msg.length > 0 ? msg : `登录失败 (${code})`;
}

export const auth: Auth = new Auth();
