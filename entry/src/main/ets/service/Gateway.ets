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

    request.on('dataReceive', (chunk: ArrayBuffer) => {
      buffer += decoder.decodeToString(new Uint8Array(chunk), { stream: true });
      let index: number = buffer.indexOf('\n');
      while (index >= 0) {
        const line: string = buffer.substring(0, index).trim();
        buffer = buffer.substring(index + 1);
        index = buffer.indexOf('\n');
        if (!line.startsWith('data:')) {
          continue;
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
              handlers.onDelta(content, reasoning);
            }
          }
        } catch (e) {
          hilog.warn(0x0000, TAG, 'skip unparsable SSE payload');
        }
      }
    });

    request.on('dataEnd', () => {
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
