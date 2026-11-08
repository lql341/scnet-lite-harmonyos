import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { credentials } from './Http';
import { StreamFrame } from '../model/Types';
import { StreamHandlers } from './Gateway';

const TAG: string = 'SCNetLite';
const STREAM_PATH: string = '/acx/chatbot/v2/agent/stream';

interface ChatHeader {
  'Content-Type': string;
  Accept: string;
  Token?: string;
  Cookie?: string;
  source: string;
  version: string;
}

interface StreamInput {
  type: string;
  text: string;
}

interface StreamBody {
  modelId: number;
  origin: string;
  inputs: StreamInput[];
  conversationId?: string;
}

/**
 * 平台 v2 智能体对话（SSE）。
 * 帧是 43 个字段的扁平对象（见 docs/PROTOCOL.md §8.2），不是 OpenAI 的 choices[].delta。
 * 结束哨兵是 `data: [done]`；首帧带回 conversationId。
 */
export class Chat {
  private request: http.HttpRequest | null = null;
  conversationId: string = '';

  cancel(): void {
    const current: http.HttpRequest | null = this.request;
    this.request = null;
    if (current !== null) {
      try {
        current.destroy();
      } catch (e) {
        hilog.warn(0x0000, TAG, 'destroy failed');
      }
    }
  }

  stream(modelId: number, text: string, handlers: StreamHandlers): void {
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
        if (payload.length === 0) {
          continue;
        }
        if (payload === '[done]' || payload === '[DONE]') {
          finish('');
          return;
        }
        let frame: StreamFrame;
        try {
          frame = JSON.parse(payload) as StreamFrame;
        } catch (e) {
          hilog.warn(0x0000, TAG, 'skip unparsable frame');
          continue;
        }
        if (frame.conversationId !== undefined && frame.conversationId !== null) {
          this.conversationId = frame.conversationId;
        }
        const type: string = frame.type === undefined || frame.type === null ? '' : frame.type;
        if (type === 'error') {
          finish(frame.errorText === undefined ? '服务端返回错误' : frame.errorText);
          return;
        }
        const delta: string = frame.delta === undefined || frame.delta === null ? '' : frame.delta;
        if (delta.length > 0) {
          handlers.onDelta(delta, '');
        }
      }
    });

    request.on('dataEnd', () => {
      finish('');
    });

    const inputs: StreamInput[] = [{ type: 'text', text: text }];
    const bodyObj: StreamBody = { modelId: modelId, origin: 'user', inputs: inputs };
    if (this.conversationId.length > 0) {
      bodyObj.conversationId = this.conversationId;
    }
    const header: ChatHeader = {
      'Content-Type': 'application/json',
      Accept: 'text/event-stream',
      source: 'HarmonyOS',
      version: credentials.version
    };
    if (credentials.token.length > 0) {
      header.Token = credentials.token;
    }
    if (credentials.cookie.length > 0) {
      header.Cookie = credentials.cookie;
    }
    const options: http.HttpRequestOptions = {
      method: http.RequestMethod.POST,
      header: header,
      extraData: JSON.stringify(bodyObj),
      expectDataType: http.HttpDataType.STRING,
      connectTimeout: 20000,
      readTimeout: 300000
    };

    try {
      request.requestInStream('https://www.scnet.cn' + STREAM_PATH, options).then((code: number) => {
        hilog.info(0x0000, TAG, 'platform stream http %{public}d', code);
      }).catch((err: BusinessError) => {
        finish(`请求失败：${err.code} ${err.message}`);
      });
    } catch (e) {
      finish('请求无法发出（检查网络权限）');
    }
  }
}

export const chat: Chat = new Chat();
