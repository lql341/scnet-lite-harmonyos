import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG: string = 'SCNetLite';

export interface ChatMessage {
  role: string;
  content: string;
}

export interface StreamHandlers {
  onDelta: (content: string, reasoning: string) => void;
  onDone: () => void;
  onError: (message: string) => void;
  /** 会话标题（服务端 `title_gen` 帧，v2 才有）。 */
  onTitle?: (title: string) => void;
  /** 进度文案（`tool-exec-progress` / `todolist`），用于“正在处理…”那行。 */
  onProgress?: (text: string) => void;
}

interface DeltaBody {
  content?: string;
  reasoning_content?: string;
}

interface StreamChoice {
  delta?: DeltaBody;
}

interface StreamChunk {
  choices?: StreamChoice[];
}

/** 网关报错是普通 JSON（不是 SSE）：402 余额不足 / 401 key 无效 */
interface GatewayErrorBody {
  error?: GatewayError;
  message?: string;
  code?: string;
}

interface GatewayError {
  message?: string;
  type?: string;
  code?: string;
}

/** 把网关错误翻译成能读的文案（402 是最常见的：账号没余额/没开通模型服务）。 */
function describeGatewayError(body: GatewayErrorBody, httpCode: number): string {
  const err: GatewayError | undefined = body.error;
  const raw: string = err !== undefined && err.message !== undefined ? err.message :
    (body.message !== undefined ? body.message : '');
  const code: string = err !== undefined && err.code !== undefined ? err.code : String(httpCode);
  if (code === '402' || raw.indexOf('Insufficient Balance') >= 0) {
    return '该模型需要余额（402 Insufficient Balance）。改用 SCNet-Max 可免费使用，或到控制台充值';
  }
  if (code === '401' || raw.indexOf('Authentication') >= 0 || raw.indexOf('token_not_found') >= 0) {
    return '网关 key 无效 (401)：请重新登录以重新获取 key';
  }
  return raw.length > 0 ? `网关报错 (${code})：${raw}` : `网关报错 (HTTP ${httpCode})`;
}

interface ChatRequestBody {
  model: string;
  stream: boolean;
  messages: ChatMessage[];
}

interface RequestHeaders {
  'Content-Type': string;
  Authorization: string;
}

function trimSlash(value: string): string {
  let out = value.trim();
  while (out.endsWith('/')) {
    out = out.substring(0, out.length - 1);
  }
  return out;
}

function readDelta(chunk: StreamChunk): DeltaBody | null {
  const choices: StreamChoice[] | undefined = chunk.choices;
  if (choices === undefined || choices.length === 0) {
    return null;
  }
  const delta: DeltaBody | undefined = choices[0].delta;
  return delta === undefined ? null : delta;
}

/**
 * Minimal OpenAI-compatible SSE client for the SCNet gateway.
 * Uses http.http requestInStream so deltas render while the model is talking.
 */
export class Gateway {
  private request: http.HttpRequest | null = null;

  cancel(): void {
    const request: http.HttpRequest | null = this.request;
    this.request = null;
    if (request !== null) {
      try {
        request.destroy();
      } catch (e) {
        hilog.warn(0x0000, TAG, 'destroy failed');
      }
    }
  }

  stream(baseUrl: string, apiKey: string, model: string, messages: ChatMessage[],
    handlers: StreamHandlers): void {
    this.cancel();

    const request: http.HttpRequest = http.createHttp();
    this.request = request;

    const decoder: util.TextDecoder = util.TextDecoder.create('utf-8', { ignoreBOM: true });
    let buffer: string = '';
    let finished: boolean = false;

    const finish = (error: string): void => {
      if (finished) {
        return;
      }
      finished = true;
      this.request = null;
      try {
        request.destroy();
      } catch (e) {
        hilog.warn(0x0000, TAG, 'destroy failed');
      }
      if (error.length > 0) {
        handlers.onError(error);
      } else {
        handlers.onDone();
      }
    };

    let serverError: string = '';
    let gotDelta: boolean = false;

    /**
     * 处理一行。⚠️ 网关的错误体（402/401）是**单行 JSON 且不带换行**，
     * 所以流结束时必须把残留 buffer 再冲一遍（见 dataEnd），否则永远解析不到。
     */
    const handleLine = (rawLine: string): void => {
      const line: string = rawLine.trim();
      if (line.length === 0) {
        return;
      }
      if (!line.startsWith('data:')) {
        // 非 SSE：普通 JSON 错误体
        if (line.startsWith('{') && line.indexOf('"error"') >= 0) {
          try {
            const errBody: GatewayErrorBody = JSON.parse(line) as GatewayErrorBody;
            serverError = describeGatewayError(errBody, 0);
            hilog.warn(0x0000, TAG, 'gateway error body: %{public}s', serverError);
          } catch (e) {
            hilog.warn(0x0000, TAG, 'unparsable gateway error body');
          }
        }
        return;
      }
      const payload: string = line.substring(5).trim();
      if (payload === '[DONE]') {
        finish('');
        return;
      }
      try {
        const chunkObj: StreamChunk = JSON.parse(payload) as StreamChunk;
        const delta: DeltaBody | null = readDelta(chunkObj);
        if (delta !== null) {
          const content: string = delta.content === undefined ? '' : delta.content;
          const reasoning: string = delta.reasoning_content === undefined ? '' : delta.reasoning_content;
          if (content.length > 0 || reasoning.length > 0) {
            gotDelta = true;
            handlers.onDelta(content, reasoning);
          }
        }
      } catch (e) {
        hilog.warn(0x0000, TAG, 'skip unparsable SSE payload');
      }
    };

    request.on('dataReceive', (chunk: ArrayBuffer) => {
      buffer += decoder.decodeToString(new Uint8Array(chunk), { stream: true });
      let index: number = buffer.indexOf('\n');
      while (index >= 0) {
        const line: string = buffer.substring(0, index);
        buffer = buffer.substring(index + 1);
        handleLine(line);
        index = buffer.indexOf('\n');
      }
    });

    request.on('dataEnd', () => {
      // 冲刷残留：单行 JSON 错误体没有换行，只会在 buffer 里
      if (buffer.length > 0) {
        handleLine(buffer);
        buffer = '';
      }
      if (serverError.length > 0) {
        finish(serverError);
        return;
      }
      if (!gotDelta) {
        finish('网关没有返回内容，也没给错误体：换个模型或检查 Base URL');
        return;
      }
      finish('');
    });

    const url: string = `${trimSlash(baseUrl)}/chat/completions`;
    const payload: ChatRequestBody = { model: model, stream: true, messages: messages };
    const body: string = JSON.stringify(payload);

    const headerSet: RequestHeaders = {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${apiKey}`
    };
    const options: http.HttpRequestOptions = {
      method: http.RequestMethod.POST,
      header: headerSet,
      extraData: body,
      expectDataType: http.HttpDataType.STRING,
      connectTimeout: 20000,
      readTimeout: 300000
    };

    try {
      request.requestInStream(url, options).then(() => {
        hilog.info(0x0000, TAG, 'stream started');
      }).catch((err: BusinessError) => {
        finish(`请求失败：${err.code} ${err.message}`);
      });
    } catch (e) {
      finish('请求无法发出（检查网络权限或 Base URL）');
    }
  }
}
