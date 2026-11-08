import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ApiEnvelope } from '../model/Types';

const TAG: string = 'SCNetLite';

/** 平台主域。业务接口都在 /acx 下（与网关 api.scnet.cn/api/gw/v1 是两套）。 */
export const CLOUD_BASE: string = 'https://www.scnet.cn';

/** 请求头。ArkTS 要求显式类型，不能用裸字面量。 */
interface RequestHeaders {
  'Content-Type': string;
  Accept: string;
  Token?: string;
  Cookie?: string;
  source: string;
  version: string;
}

export class ApiError extends Error {
  code: string;

  constructor(code: string, message: string) {
    super(message);
    this.code = code;
  }
}

/** 凭据：平台用 Token 头 + SSO cookie 双头，缺一个就 401。 */
class Credentials {
  token: string = '';
  cookie: string = '';
  version: string = '1.0.0';

  isEmpty(): boolean {
    return this.token.length === 0;
  }
}

export const credentials: Credentials = new Credentials();

/** 401 时的统一回调，由 UI 层注册（跳登录页）。 */
let onUnauthorized: () => void = () => {
};

export function setUnauthorizedHandler(handler: () => void): void {
  onUnauthorized = handler;
}

class Http {
  private buildHeader(json: boolean): RequestHeaders {
    const header: RequestHeaders = {
      'Content-Type': json ? 'application/json' : 'application/x-www-form-urlencoded',
      Accept: 'application/json',
      source: 'HarmonyOS',
      version: credentials.version
    };
    if (credentials.token.length > 0) {
      header.Token = credentials.token;
    }
    if (credentials.cookie.length > 0) {
      header.Cookie = credentials.cookie;
    }
    return header;
  }

  private async send(path: string, method: http.RequestMethod, body: string): Promise<ApiEnvelope> {
    const options: http.HttpRequestOptions = {
      method: method,
      header: this.buildHeader(true),
      expectDataType: http.HttpDataType.STRING,
      connectTimeout: 15000,
      readTimeout: 30000
    };
    if (method === http.RequestMethod.POST) {
      options.extraData = body;
    }
    const request = http.createHttp();
    try {
      const resp = await request.request(CLOUD_BASE + path, options);
      const raw: string = typeof resp.result === 'string' ? resp.result as string : '';
      if (raw.length === 0) {
        throw new ApiError(String(resp.responseCode), `空响应 (HTTP ${resp.responseCode})`);
      }
      const env = JSON.parse(raw) as ApiEnvelope;
      const code: string = env.code === undefined ? '' : env.code;
      if (code === '401' || resp.responseCode === 401) {
        credentials.token = '';
        credentials.cookie = '';
        onUnauthorized();
        throw new ApiError('401', '登录已过期，请重新登录');
      }
      if (resp.responseCode !== 200) {
        throw new ApiError(code.length > 0 ? code : String(resp.responseCode),
          env.msg === undefined ? `HTTP ${resp.responseCode}` : env.msg);
      }
      if (code !== '0' && code !== '200' && code !== '') {
        throw new ApiError(code, env.msg === undefined ? '请求失败' : env.msg);
      }
      return env;
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

  async getData(path: string): Promise<object> {
    const env = await this.send(path, http.RequestMethod.GET, '');
    return env.data === undefined ? new EmptyData() : env.data;
  }

  /** 表单 POST（SSO 那套是 x-www-form-urlencoded，不是 JSON）。 */
  async postForm(path: string, form: string): Promise<http.HttpResponse> {
    const header: RequestHeaders = {
      'Content-Type': 'application/x-www-form-urlencoded',
      Accept: 'application/json, text/plain, */*',
      source: 'HarmonyOS',
      version: credentials.version
    };
    if (credentials.cookie.length > 0) {
      header.Cookie = credentials.cookie;
    }
    const options: http.HttpRequestOptions = {
      method: http.RequestMethod.POST,
      header: header,
      extraData: form,
      expectDataType: http.HttpDataType.STRING,
      connectTimeout: 15000,
      readTimeout: 30000
    };
    const request = http.createHttp();
    try {
      return await request.request(CLOUD_BASE + path, options);
    } catch (e) {
      const err = e as BusinessError;
      throw new ApiError(String(err.code), err.message === undefined ? '网络错误' : err.message);
    } finally {
      request.destroy();
    }
  }

  /** 登录类接口要拿响应头里的 Set-Cookie，所以单独返回原始响应。 */
  async postRaw(path: string, body: string): Promise<http.HttpResponse> {
    const options: http.HttpRequestOptions = {
      method: http.RequestMethod.POST,
      header: this.buildHeader(true),
      extraData: body,
      expectDataType: http.HttpDataType.STRING,
      connectTimeout: 15000,
      readTimeout: 30000
    };
    const request = http.createHttp();
    try {
      return await request.request(CLOUD_BASE + path, options);
    } catch (e) {
      const err = e as BusinessError;
      hilog.error(0x0000, TAG, 'postRaw failed: %{public}s', err.message);
      throw new ApiError(String(err.code), err.message === undefined ? '网络错误' : err.message);
    } finally {
      request.destroy();
    }
  }
}

/** 空 payload 占位（ArkTS 不允许裸 `{}`）。 */
export class EmptyData {
}

export const httpClient: Http = new Http();
