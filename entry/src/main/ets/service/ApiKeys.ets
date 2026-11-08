import { http } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { httpClient, credentials } from './Http';
import { store } from './Store';

const TAG: string = 'SCNetLite';

/** 网关 key 的候选字段名（不同接口命名不一致，逐个试）。 */
const KEY_FIELDS: string[] = ['apiKey', 'key', 'secretKey', 'apiKeyValue', 'token'];

/** 创建 key 的请求体。 */
interface CreateKeyBody {
  apiKeyName: string;
  accountId: string;
  teamName: string;
}

export interface ApiKeyRecord {
  apiKey?: string;
  key?: string;
  secretKey?: string;
  apiKeyValue?: string;
  token?: string;
  apiKeyName?: string;
  name?: string;
  status?: string;
  accountId?: string;
  teamName?: string;
  accessibleModelScope?: string;
}

interface KeyListData {
  records?: ApiKeyRecord[];
  list?: ApiKeyRecord[];
  data?: ApiKeyRecord[];
}

function pickKey(record: ApiKeyRecord): string {
  const asMap = record as Record<string, string>;
  for (let i = 0; i < KEY_FIELDS.length; i++) {
    const value = asMap[KEY_FIELDS[i]];
    // 平台列表接口返回的是"打码"的 key（形如 sk-N****MTM=），跳过；
    // 完整 key 只在 create 响应里给一次。
    if (typeof value === 'string' && (value as string).length >= 20 && (value as string).indexOf('*') < 0) {
      hilog.info(0x0000, TAG, 'pickKey via %{public}s len=%{public}d', KEY_FIELDS[i],
        (value as string).length);
      return value;
    }
  }
  return '';
}

/**
 * 平台会给每个账号自动发一个网关 key（APK 里能看到 createUserApiKey / ensureOcrApiKey）。
 * 手机端对话走的是网关 https://api.scnet.cn/api/gw/v1（OpenAI 兼容），
 * 这解释了为什么手机能用、而平台 v2 agent 接口回「系统繁忙」。
 */
/** 把长字符串值替换成 <str:N>，只保留结构和字段名，避免把 key 写进日志。 */
function maskJson(text: string): string {
  try {
    const walk = (value: Object): Object => {
      if (typeof value === 'string') {
        const str = value as string;
        return str.length > 16 ? `<str:${str.length}>` : str;
      }
      if (Array.isArray(value)) {
        return (value as Object[]).map((v: Object): Object => walk(v));
      }
      if (value !== null && typeof value === 'object') {
        const src = value as Record<string, Object>;
        const keys: string[] = Object.keys(src);
        const pairs: string[] = [];
        for (let i = 0; i < keys.length; i++) {
          pairs.push(`${JSON.stringify(keys[i])}:${JSON.stringify(walk(src[keys[i]]))}`);
        }
        return `{${pairs.join(',')}}`;
      }
      return value;
    };
    return JSON.stringify(walk(JSON.parse(text) as Object));
  } catch (e) {
    return `<unparsable len=${text.length}>`;
  }
}

class ApiKeys {
  private teamAccountId: string = '';
  private teamName: string = '';

  /** 只露头尾，够判断是哪一版 key。 */
  private fingerprint(value: string): string {
    if (value.length === 0) {
      return '';
    }
    if (value.length <= 4) {
      return `*${value.length}`;
    }
    return `${value.substring(0, 2)}***${value.substring(value.length - 2)}`;
  }

  /** 查已有 key；没有就创建一个。返回值空表示失败（细节看 hilog）。 */
  async ensureKey(): Promise<string> {
    const cached: string = store.getAutoKey();
    hilog.info(0x0000, TAG, 'apiKey cached len=%{public}d %{public}s', cached.length, this.fingerprint(cached));
    // 网关 key 是 25 字符；比这短的一定是脏数据（之前误存过）
    if (cached.length >= 20) {
      return cached;
    }
    if (cached.length > 0) {
      store.setAutoKey('');
    }

    const found: string = await this.query();
    hilog.info(0x0000, TAG, 'apiKey query result len=%{public}d', found.length);
    if (found.length > 0) {
      store.setAutoKey(found);
      return found;
    }

    const created: string = await this.create();
    hilog.info(0x0000, TAG, 'apiKey create result len=%{public}d', created.length);
    if (created.length > 0) {
      store.setAutoKey(created);
      return created;
    }
    return '';
  }

  /** 只有 POST 可用（GET 返回 "Request method 'GET' not supported"）。响应是三层编码的 JSON。 */
  private async query(): Promise<string> {
    let text: string = '';
    try {
      const raw = await httpClient.postRaw('/acx/llm/api-key/query', '{}');
      text = typeof raw.result === 'string' ? raw.result as string : '';
    } catch (e) {
      hilog.warn(0x0000, TAG, 'apiKey query request failed');
      return '';
    }
    if (text.length === 0) {
      return '';
    }
    let payload: object;
    try {
      const outer = JSON.parse(text) as Record<string, Object>;
      const data = outer['data'];
      payload = typeof data === 'string' ? JSON.parse(data as string) as object : data as object;
    } catch (e) {
      hilog.warn(0x0000, TAG, 'apiKey query parse failed');
      return '';
    }
    const list: ApiKeyRecord[] = this.asList(payload);
    hilog.info(0x0000, TAG, 'apiKey records=%{public}d', list.length);
    let key: string = '';
    for (let i = 0; i < list.length; i++) {
      const record: ApiKeyRecord = list[i];
      if (this.teamAccountId.length === 0) {
        const asMap = record as Record<string, Object>;
        const account = asMap['accountId'];
        if (typeof account === 'string') {
          this.teamAccountId = account as string;
          const team = asMap['teamName'];
          this.teamName = typeof team === 'string' ? team as string : '';
          hilog.info(0x0000, TAG, 'team captured: name=%{public}s idLen=%{public}d',
            this.teamName, this.teamAccountId.length);
        }
      }
      if (key.length === 0) {
        key = pickKey(record);
      }
    }
    return key;
  }

  private async create(): Promise<string> {
    try {
      if (this.teamAccountId.length === 0) {
        await this.query(); // 先查一次拿团队信息
      }
      const body: CreateKeyBody = {
        apiKeyName: 'harmonyos-lite',
        accountId: this.teamAccountId,
        teamName: this.teamName
      };
      hilog.info(0x0000, TAG, 'create with team=%{public}s accountLen=%{public}d',
        this.teamName, this.teamAccountId.length);
      const raw = await httpClient.postRaw('/acx/llm/api-key/create', JSON.stringify(body));
      const text: string = typeof raw.result === 'string' ? raw.result as string : '';
      hilog.info(0x0000, TAG, 'apiKey create raw: %{public}s',
        text.length > 400 ? text.substring(0, 400) : text);
      hilog.info(0x0000, TAG, 'apiKey create raw=%{public}s', text.length > 300 ? text.substring(0, 300) : text);
      if (text.length > 0) {
        const parsed = JSON.parse(text) as Record<string, Object>;
        const data = parsed['data'];
        if (data !== undefined) {
          const record = data as ApiKeyRecord;
          const key: string = pickKey(record);
          if (key.length > 0) {
            return key;
          }
        }
      }
    } catch (e) {
      hilog.warn(0x0000, TAG, 'apiKey create failed');
    }
    return '';
  }

  /** 探一次网关，返回是否可用与首个模型 id。 */
  async probeGateway(key: string): Promise<GatewayProbe> {
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
    const request = http.createHttp();
    try {
      // 手机端 APK 用的是 /api/llm/v1（出现 ocr/recognize），先试它，再试 gw/v1
      let resp = await request.request(LLM_BASE + '/models', options);
      hilog.info(0x0000, TAG, 'probe llm/v1/models -> %{public}d', resp.responseCode);
      if (resp.responseCode !== 200) {
        resp = await request.request(GW_BASE + '/models', options);
        hilog.info(0x0000, TAG, 'probe gw/v1/models -> %{public}d', resp.responseCode);
      }
      const text: string = typeof resp.result === 'string' ? resp.result as string : '';
      let models: string = '';
      try {
        const parsed = JSON.parse(text) as GatewayModelList;
        const list: GatewayModel[] = parsed.data ?? [];
        if (list.length > 0) {
          models = list[0].id ?? '';
        }
        hilog.info(0x0000, TAG, 'gateway models=%{public}d first=%{public}s', list.length, models);
      } catch (e) {
        hilog.warn(0x0000, TAG, 'gateway models parse failed');
      }
      const result: GatewayProbe = {
        ok: resp.responseCode === 200 && models.length > 0,
        status: resp.responseCode,
        models: models
      };
      return result;
    } catch (e) {
      const err = e as Error;
      hilog.warn(0x0000, TAG, 'gateway probe failed: %{public}s', err.message === undefined ? '?' : err.message);
      const failed: GatewayProbe = { ok: false, status: 0, models: '' };
      return failed;
    } finally {
      request.destroy();
    }
  }

  /** 把可能是"字符串里的 JSON"的元素解析成对象（实测平台把 records 每项也编码成字符串）。 */
  private normalize(items: Object[]): ApiKeyRecord[] {
    const out: ApiKeyRecord[] = [];
    for (let i = 0; i < items.length; i++) {
      const item = items[i];
      if (typeof item === 'string') {
        try {
          out.push(JSON.parse(item as string) as ApiKeyRecord);
        } catch (e) {
          // 跳过坏项
        }
      } else if (item !== null && typeof item === 'object') {
        out.push(item as ApiKeyRecord);
      }
    }
    return out;
  }

  /**
   * APK 里出现过 https://api.scnet.cn/api/llm/v1/ocr/recognize —— 说明手机端走的是
   * `api.scnet.cn/api/llm/v1`（不是 gw/v1），鉴权可能直接用登录 Token+Cookie。
   * 这条探一次就能确定手机端到底用什么凭据。
   */
  async probeMobileGateway(): Promise<number> {
    const header: GWHeader = {
      'Content-Type': 'application/json',
      Accept: 'application/json',
      source: 'HarmonyOS',
      version: '1.0.0'
    };
    if (credentials.token.length > 0) {
      header.Token = credentials.token;
    }
    if (credentials.cookie.length > 0) {
      header.Cookie = credentials.cookie;
    }
    const options: http.HttpRequestOptions = {
      method: http.RequestMethod.GET,
      header: header,
      expectDataType: http.HttpDataType.STRING,
      connectTimeout: 15000,
      readTimeout: 20000
    };
    const request = http.createHttp();
    try {
      const resp = await request.request('https://api.scnet.cn/api/llm/v1/models', options);
      const text: string = typeof resp.result === 'string' ? resp.result as string : '';
      hilog.info(0x0000, TAG, 'mobile gw /api/llm/v1/models -> %{public}d len=%{public}d',
        resp.responseCode, text.length);
      if (text.length > 0 && text.length < 300) {
        hilog.info(0x0000, TAG, 'mobile gw body: %{public}s', text);
      }
      return resp.responseCode;
    } catch (e) {
      hilog.warn(0x0000, TAG, 'mobile gw probe error');
      return 0;
    } finally {
      request.destroy();
    }
  }

  private asList(data: object): ApiKeyRecord[] {
    const asPage = data as KeyListData;
    if (asPage.records !== undefined) {
      return this.normalize(asPage.records as Object[]);
    }
    if (asPage.list !== undefined) {
      return this.normalize(asPage.list as Object[]);
    }
    if (asPage.data !== undefined) {
      return this.normalize(asPage.data as Object[]);
    }
    // 直接是数组时
    const maybe = data as Object;
    if (Array.isArray(maybe)) {
      return this.normalize(maybe as Object[]);
    }
    const single = data as ApiKeyRecord;
    return pickKey(single).length > 0 ? [single] : [];
  }
}

/** 网关 key 自检：能列出模型就说明 key 可用。 */
export interface GatewayProbe {
  ok: boolean;
  status: number;
  models: string;
}

interface GatewayModel {
  id?: string;
}

interface GatewayModelList {
  data?: GatewayModel[];
}

export const GW_BASE: string = 'https://api.scnet.cn/api/gw/v1';
export const LLM_BASE: string = 'https://api.scnet.cn/api/llm/v1';

interface GWHeader {
  'Content-Type': string;
  Accept: string;
  Authorization?: string;
  Token?: string;
  Cookie?: string;
  source?: string;
  version?: string;
}

export const apiKeys: ApiKeys = new ApiKeys();
