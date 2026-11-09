/**
 * 网关（LLM）凭据获取 —— 对齐官方客户端 / scnet-cli 的链路：
 *
 *   GET  /acx/user/users/cluster-user-detail          → 集群身份（accountId / groupId / userId）
 *   GET  /acx/llm/account/config/status?accountId=…   → modelServiceEnabled（0 未授权 / 1 已授权）
 *   POST /acx/llm/account/config/authorize?accountId=…  → 开通平台模型服务（客户端登录时自动做）
 *   POST /acx/llm/api-key/createActivityApiKey         → 一把 sk- key + baseUrl + 默认模型（一条搞定）
 *   兜底：POST /acx/llm/api-key/query（团队维度查）→ POST /acx/llm/api-key/create
 *
 * 关键事实（2026-11-09 实测）：
 * - `authorize` / 团队 key 的 `accountId` 必须是**集群账号**（427416191724683264），
 *   用 `current-user-info.id`（11224910962）会 `API010006 无权限访问`；
 * - 授权成功（`modelServiceEnabled: 1`）后若账号**余额为 0**，chat 仍回 `402 Insufficient Balance`；
 * - 平台下发的 baseUrl 是 `https://api.scnet.cn/api/llm/v1`（不是 `/api/gw/v1`）；
 * - `/api-key/query` 只支持 POST（GET → `405 Request method 'GET' not supported`）；
 * - 列表里的 key 是打码的（含 `*`），明文只在 create / detail 里出现一次。
 */
import { http } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { httpClient } from './Http';
import { store } from './Store';
import { ClusterIdentity } from './Auth';

const TAG: string = 'SCNetLite';

/** 平台下发的 baseUrl 兜底值（`createActivityApiKey` 正常会带回来）。 */
export const LLM_BASE: string = 'https://api.scnet.cn/api/llm/v1';

const KEY_FIELDS: string[] = ['apiKey', 'key', 'secretKey', 'apiKeyValue', 'credential'];

export interface GatewayAccess {
  key: string;
  baseUrl: string;
  model: string;
  /** `activity` 一把到手 / `existing` 查到 / `created` 新建（带团队维度）/ `none` */
  source: string;
}

interface ConfigStatus {
  accountId?: string;
  modelServiceEnabled?: number;
  modelAllowOverdraft?: number;
  accessibleModelScope?: string;
  /** 1 = 有未结清账单，通常是 402 的直接原因 */
  unpaidStatus?: number;
  isVip?: boolean;
  overallQuota?: number;
  overallRpm?: number;
}

interface ActivityKeyData {
  apiKey?: string;
  key?: string;
  baseUrl?: string;
  anthropicBaseUrl?: string;
  model?: string;
}

interface CreateKeyBody {
  apiKeyName: string;
  serviceTypes: string[];
  accessibleModelScope: string;
  accountId: string;
  groupId: string;
  createUser: string;
}

function pickKey(data: ActivityKeyData): string {
  const asMap = data as Record<string, Object>;
  for (let i = 0; i < KEY_FIELDS.length; i++) {
    const value = asMap[KEY_FIELDS[i]];
    if (typeof value !== 'string') {
      continue;
    }
    const text: string = value as string;
    // 打码的 key 一律跳过
    if (text.length >= 20 && text.indexOf('*') < 0) {
      return text;
    }
  }
  return '';
}

/** `data` 常被再包一层字符串，统一拆开。 */
function unwrap(text: string): object {
  const parsed = JSON.parse(text) as Record<string, Object>;
  const data = parsed['data'];
  if (typeof data === 'string') {
    try {
      return JSON.parse(data as string) as object;
    } catch (e) {
      return parsed as object;
    }
  }
  return data === undefined ? parsed as object : data as object;
}

class ApiKeys {
  /** 平台要求验证码/未授权等需要人介入时的文案；空表示没这类问题。 */
  lastBlocked: string = '';

  /** 模型服务授权状态。null 表示没查到。 */
  async accountStatus(accountId: string): Promise<ConfigStatus | null> {
    if (accountId.length === 0) {
      return null;
    }
    try {
      const data = await httpClient.getData(`/acx/llm/account/config/status?accountId=${accountId}`);
      return data as ConfigStatus;
    } catch (e) {
      hilog.warn(0x0000, TAG, 'account/config/status failed');
      return null;
    }
  }

  /**
   * 开通平台模型服务。官方客户端在登录后自动做这一步；
   * 我们只在 status 明确是 0 时调用一次，失败不抛（只记日志）。
   */
  async authorize(accountId: string): Promise<boolean> {
    if (accountId.length === 0) {
      return false;
    }
    try {
      await httpClient.postForm(`/acx/llm/account/config/authorize?accountId=${accountId}`, '');
      const after: ConfigStatus | null = await this.accountStatus(accountId);
      const ok: boolean = after !== null && after.modelServiceEnabled === 1;
      hilog.info(0x0000, TAG, 'authorize -> modelServiceEnabled=%{public}s', String(ok));
      return ok;
    } catch (e) {
      hilog.warn(0x0000, TAG, 'authorize failed');
      return false;
    }
  }

  /** 一把到位：返回 key + baseUrl + 默认模型。 */
  private async activityKey(): Promise<GatewayAccess> {
    const empty: GatewayAccess = { key: '', baseUrl: '', model: '', source: 'none' };
    try {
      const raw = await httpClient.postRaw('/acx/llm/api-key/createActivityApiKey', '{}');
      const text: string = typeof raw.result === 'string' ? raw.result as string : '';
      if (text.length === 0) {
        return empty;
      }
      const data = unwrap(text) as ActivityKeyData;
      const key: string = pickKey(data);
      if (key.length === 0) {
        return empty;
      }
      const result: GatewayAccess = {
        key: key,
        baseUrl: (data.baseUrl ?? '').replace(/\/+$/, ''),
        model: data.model ?? '',
        source: 'activity'
      };
      hilog.info(0x0000, TAG, 'activity key len=%{public}d base=%{public}s model=%{public}s',
        key.length, result.baseUrl, result.model);
      return result;
    } catch (e) {
      hilog.warn(0x0000, TAG, 'createActivityApiKey failed');
      return empty;
    }
  }

  /** 兜底：按团队维度查一把已有的 key（列表里是打码的，能用的才行）。 */
  private async queryExisting(): Promise<GatewayAccess> {
    const empty: GatewayAccess = { key: '', baseUrl: LLM_BASE, model: '', source: 'none' };
    try {
      const raw = await httpClient.postRaw('/acx/llm/api-key/query', '{}');
      const text: string = typeof raw.result === 'string' ? raw.result as string : '';
      if (text.length === 0) {
        return empty;
      }
      const payload = unwrap(text);
      const rows: Object[] = Array.isArray(payload) ? payload as Object[] : [];
      for (let i = 0; i < rows.length; i++) {
        const item = rows[i];
        if (item === null || typeof item !== 'object') {
          continue;
        }
        const key: string = pickKey(item as ActivityKeyData);
        if (key.length > 0) {
          const found: GatewayAccess = { key: key, baseUrl: LLM_BASE, model: '', source: 'existing' };
          return found;
        }
      }
      return empty;
    } catch (e) {
      hilog.warn(0x0000, TAG, 'api-key/query failed');
      return empty;
    }
  }

  /**
   * 全链路：status → 必要时 authorize → activity key → 兜底 query。
   * 结果（key/baseUrl/model）落到 preferences，下次启动直接用缓存的 key。
   */
  async ensureAccess(identity: ClusterIdentity): Promise<GatewayAccess> {
    const accountId: string = identity.accountId;
    this.lastBlocked = '';

    const cached: string = store.getAutoKey();
    if (cached.length >= 20) {
      const hit: GatewayAccess = {
        key: cached,
        baseUrl: store.getBaseUrl(),
        model: store.getModel(),
        source: 'cached'
      };
      return hit;
    }

    if (accountId.length === 0) {
      this.lastBlocked = '拿不到集群身份（cluster-user-detail），无法授权/取 key';
      return { key: '', baseUrl: LLM_BASE, model: '', source: 'none' };
    }

    const status: ConfigStatus | null = await this.accountStatus(accountId);
    if (status !== null) {
      hilog.info(0x0000, TAG, 'modelServiceEnabled=%{public}d unpaidStatus=%{public}d scope=%{public}s',
        status.modelServiceEnabled ?? -1, status.unpaidStatus ?? -1, status.accessibleModelScope ?? '');
      if (status.modelServiceEnabled !== 1) {
        // 只在账号没有未结清账单时自动开通（官方客户端登录后就是这个行为）；
        // 有欠费时不要替用户动计费相关的开关。
        if (status.unpaidStatus === 1) {
          this.lastBlocked = '账号有未结清账单，模型服务被暂停（网关会返回 402）';
        } else {
          const ok: boolean = await this.authorize(accountId);
          if (!ok) {
            this.lastBlocked = '模型服务未开通（authorize 未生效）';
          }
        }
      } else if (status.unpaidStatus === 1) {
        this.lastBlocked = '账号有未结清账单，模型服务可能被限（网关可能返回 402）';
      }
    }

    let access: GatewayAccess = await this.activityKey();
    if (access.key.length === 0) {
      access = await this.queryExisting();
    }
    if (access.key.length === 0) {
      if (this.lastBlocked.length === 0) {
        this.lastBlocked = '拿不到网关 key（授权未开通或接口变更）';
      }
      return access;
    }

    const baseUrl: string = access.baseUrl.length > 0 ? access.baseUrl : LLM_BASE;
    const fixed: GatewayAccess = {
      key: access.key,
      baseUrl: baseUrl,
      model: access.model,
      source: access.source
    };
    store.setAutoKey(fixed.key);
    store.setBaseUrl(fixed.baseUrl);
    // ⚠️ 不要在这里写 model：
    // - 接口回带的 `model` 是 MiniMax-M2.5（付费上游），拿它当默认会直接 402；
    // - 也不要用 DEFAULT_MODEL 覆盖用户上次的选择（会每条启动都被重置）。
    // 默认模型的选取交给 Index.pickModel()（上次选择 → SCNet-Max → 列表首个）。
    hilog.info(0x0000, TAG, 'gateway access ready: source=%{public}s keyLen=%{public}d base=%{public}s',
      fixed.source, fixed.key.length, fixed.baseUrl);
    return fixed;
  }

  /** 拉网关模型 id 列表。 */
  async listModels(baseUrl: string, key: string): Promise<string[]> {
    const header: GWHeader = {
      'Content-Type': 'application/json',
      Accept: 'application/json',
      Authorization: `Bearer ${key}`
    };
    const options: http.HttpRequestOptions = {
      method: http.RequestMethod.GET,
      header: header,
      expectDataType: http.HttpDataType.STRING,
      connectTimeout: 15000,
      readTimeout: 20000
    };
    const request: http.HttpRequest = http.createHttp();
    try {
      const base: string = baseUrl.length > 0 ? baseUrl : LLM_BASE;
      const resp = await request.request(`${base}/models`, options);
      const text: string = typeof resp.result === 'string' ? resp.result as string : '';
      const parsed = JSON.parse(text) as GatewayModelList;
      const list: GatewayModel[] = parsed.data ?? [];
      const out: string[] = [];
      for (let i = 0; i < list.length; i++) {
        const id: string = list[i].id ?? '';
        if (id.length > 0) {
          out.push(id);
        }
      }
      hilog.info(0x0000, TAG, 'gateway models: %{public}d', out.length);
      return out;
    } catch (e) {
      hilog.warn(0x0000, TAG, 'gateway models load failed');
      return [];
    } finally {
      request.destroy();
    }
  }
}

interface GatewayModel {
  id?: string;
}

interface GatewayModelList {
  data?: GatewayModel[];
}

interface GWHeader {
  'Content-Type': string;
  Accept: string;
  Authorization?: string;
}

export const apiKeys: ApiKeys = new ApiKeys();
