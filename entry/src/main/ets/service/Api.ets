import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG: string = 'SCNetLite';

/** 平台主域。APK 里的所有业务接口都在这里（`/acx/*`），与网关 `api.scnet.cn/api/gw/v1` 是两套。 */
export const CLOUD_BASE: string = 'https://www.scnet.cn';

interface HttpHeaders {
  'Content-Type': string;
  Accept: string;
  Authorization: string;
}

interface RequestOptions {
  method: http.RequestMethod;
  header: HttpHeaders;
  extraData?: string;
  expectDataType: http.HttpDataType;
  connectTimeout: number;
  readTimeout: number;
}

/** 平台统一响应信封：{ code: "0", msg: "success", data: … }。code 是字符串，不是数字。 */
export interface Envelope {
  code?: string;
  msg?: string;
  data?: object;
}

export interface ConversationSummary {
  conversationId?: string;
  title?: string;
  updateTime?: string;
}

interface ConversationListData {
  records?: ConversationSummary[];
  end?: number;
}

/** 空 payload 占位（ArkTS 不允许裸 `{}` 字面量）。 */
class EmptyData {
}

export class ApiError extends Error {
  code: string;

  constructor(code: string, message: string) {
    super(message);
    this.code = code;
  }
}

class Api {
  private token: string = '';

  setToken(token: string): void {
    this.token = token;
  }

  hasToken(): boolean {
    return this.token.length > 0;
  }

  /** POST/GET JSON，返回 data 字段。失败抛 ApiError。 */
  async call(path: string, method: http.RequestMethod, body?: string): Promise<object> {
    const header: HttpHeaders = {
      'Content-Type': 'application/json',
      Accept: 'application/json',
      Authorization: `Bearer ${this.token}`
    };
    const options: RequestOptions = {
      method: method,
      header: header,
      expectDataType: http.HttpDataType.STRING,
      connectTimeout: 15000,
      readTimeout: 30000
    };
    if (body !== undefined) {
      options.extraData = body;
    }

    const request = http.createHttp();
    try {
      const resp = await request.request(CLOUD_BASE + path, options);
      const raw: string = typeof resp.result === 'string' ? resp.result as string : '';
      hilog.info(0x0000, TAG, 'cloud %{public}s -> %{public}d', path, resp.responseCode);
      if (raw.length === 0) {
        throw new ApiError(String(resp.responseCode), `空响应 (HTTP ${resp.responseCode})`);
      }
      const env = JSON.parse(raw) as Envelope;
      const code: string = env.code === undefined ? '' : env.code;
      if (resp.responseCode !== 200 || (code !== '0' && code !== '200')) {
        throw new ApiError(code.length > 0 ? code : String(resp.responseCode),
          env.msg === undefined ? `HTTP ${resp.responseCode}` : env.msg);
      }
      return env.data === undefined ? new EmptyData() : env.data;
    } catch (e) {
      if (e instanceof ApiError) {
        throw e as ApiError;
      }
      const err = e as BusinessError;
      throw new ApiError(String(err.code), err.message === undefined ? '网络错误' : err.message);
    } finally {
      request.destroy();
    }
  }

  /** 会话列表（实测：Bearer accessToken 可用，未登录返回 records=[]）。 */
  async conversationList(): Promise<ConversationSummary[]> {
    const data = await this.call('/acx/chatbot/conversation/list', http.RequestMethod.GET);
    const list = data as ConversationListData;
    return list.records === undefined ? [] : list.records;
  }

  /** 首页推荐问题/广告位（公开接口，无需登录也能拿到）。 */
  async chatConfig(): Promise<object> {
    return await this.call('/acx/chatbot/config/list', http.RequestMethod.GET);
  }
}

export const api: Api = new Api();
