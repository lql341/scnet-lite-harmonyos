/**
 * 平台智能体通道（v2）。
 *
 * 与网关（Gateway.ets）并列的第二条通道：
 * - 网关：`{baseUrl}/chat/completions`，OpenAI 兼容，选的是 LLM（SCNet-Max 等）
 * - 智能体：`/acx/chatbot/v2/agent/stream`，选的是**平台服务**（aiagent-router / aiagent-science …），
 *   每个服务有自己的 `modelId`（来自 `/acx/chatbot/recommend/list?enable=true`）
 *
 * 帧是 43 字段的扁平对象，按 `type` 分派（2026-11-09 实测词表）：
 *   null(首帧，带 conversationId) · start · todolist · title_gen ·
 *   tool-input-start/delta/available · tool-output-available · tool-exec-progress ·
 *   heartbeat · text-start · text-delta · text-end · finish · history · error
 *
 * 只有 `text-delta` 的 `delta` 是正文；`tool-input-delta` 走的是 `inputTextDelta`（工具入参分片），
 * 当正文渲染会把工具 JSON 吐进气泡。没有 `data: [done]` 哨兵，`finish` 帧 + 连接关闭就是结束。
 */
import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { credentials } from './Http';
import { StreamHandlers } from './Gateway';
import { UploadedFile } from './Upload';

const TAG: string = 'SCNetLite';
const BASE: string = 'https://www.scnet.cn';
const STREAM_PATH: string = '/acx/chatbot/v2/agent/stream';
const STOP_PATH: string = '/acx/chatbot/v2/agent/stop';

interface AgentHeader {
  'Content-Type': string;
  Accept: string;
  Token?: string;
  Cookie?: string;
  source: string;
  version: string;
}

interface AgentResource {
  name: string;
  mimeType: string;
  /** KB（平台按 1024 字节折算） */
  size: number;
}

interface AgentInput {
  type: string;
  text?: string;
  resource?: AgentResource;
}

interface AgentBody {
  modelId: number;
  origin: string;
  inputs: AgentInput[];
  conversationId?: string;
}

interface StopBody {
  conversationId: string;
  modelId: number;
}

interface AgentFrame {
  type?: string;
  delta?: string;
  inputTextDelta?: string;
  errorText?: string;
  conversationId?: string;
  title?: string;
  progressText?: string;
  finishReason?: string;
  agentName?: string;
}

export class AgentChat {
  /** 当前会话 id（首帧带回；新对话时清空）。 */
  conversationId: string = '';
  /** 最近一次服务端回的标题（title_gen），用于给本地会话改名。 */
  lastTitle: string = '';

  private request: http.HttpRequest | null = null;

  cancel(): void {
    const current: http.HttpRequest | null = this.request;
    this.request = null;
    if (current !== null) {
      try {
        current.destroy();
      } catch (e) {
        hilog.warn(0x0000, TAG, 'agent cancel failed');
      }
    }
  }

  private header(): AgentHeader {
    const head: AgentHeader = {
      'Content-Type': 'application/json',
      Accept: 'text/event-stream',
      source: 'HarmonyOS',
      version: credentials.version
    };
    if (credentials.token.length > 0) {
      head.Token = credentials.token;
    }
    if (credentials.cookie.length > 0) {
      head.Cookie = credentials.cookie;
    }
    return head;
  }

  /**
   * 停服务端任务。仅断开本地连接不会让服务端停（会继续烧算力）。
   * 失败只记日志：本地已经停了，不该因为 stop 失败再弹错。
   */
  stop(modelId: number): void {
    if (this.conversationId.length === 0) {
      return;
    }
    const body: StopBody = { conversationId: this.conversationId, modelId: modelId };
    const options: http.HttpRequestOptions = {
      method: http.RequestMethod.POST,
      header: this.header(),
      extraData: JSON.stringify(body),
      expectDataType: http.HttpDataType.STRING,
      connectTimeout: 8000,
      readTimeout: 8000
    };
    const request: http.HttpRequest = http.createHttp();
    request.request(BASE + STOP_PATH, options).then(() => {
      hilog.info(0x0000, TAG, 'agent stop sent');
    }).catch((err: BusinessError) => {
      hilog.warn(0x0000, TAG, 'agent stop failed: %{public}s', err.message);
    }).finally(() => {
      request.destroy();
    });
  }

  stream(modelId: number, text: string, files: UploadedFile[], handlers: StreamHandlers): void {
    this.cancel();
    if (credentials.token.length === 0) {
      handlers.onError('未登录，无法使用智能体服务');
      return;
    }

    const request: http.HttpRequest = http.createHttp();
    this.request = request;

    const decoder: util.TextDecoder = util.TextDecoder.create('utf-8', { ignoreBOM: true });
    let buffer: string = '';
    let finished: boolean = false;
    let gotText: boolean = false;

    const finish = (error: string): void => {
      if (finished) {
        return;
      }
      finished = true;
      this.request = null;
      try {
        request.destroy();
      } catch (e) {
        hilog.warn(0x0000, TAG, 'agent destroy failed');
      }
      if (error.length > 0) {
        handlers.onError(error);
      } else {
        handlers.onDone();
      }
    };

    const handleLine = (raw: string): void => {
      const line: string = raw.trim();
      if (line.length === 0 || !line.startsWith('data:')) {
        return;
      }
      const payload: string = line.substring(5).trim();
      if (payload === '[done]' || payload === '[DONE]') {
        finish('');
        return;
      }
      let frame: AgentFrame;
      try {
        frame = JSON.parse(payload) as AgentFrame;
      } catch (e) {
        return;
      }
      const type: string = frame.type === undefined || frame.type === null ? '' : frame.type;
      if (frame.conversationId !== undefined && frame.conversationId !== null &&
        frame.conversationId.length > 0) {
        this.conversationId = frame.conversationId;
      }
      if (type === 'error') {
        finish(frame.errorText ?? '智能体返回错误');
        return;
      }
      if (type === 'finish') {
        finish('');
        return;
      }
      if (type === 'title_gen') {
        const title: string = frame.title ?? '';
        if (title.length > 0) {
          this.lastTitle = title;
          if (handlers.onTitle !== undefined) {
            handlers.onTitle(title);
          }
        }
        return;
      }
      if (type === 'tool-exec-progress' || type === 'todolist') {
        const progress: string = frame.progressText ?? '';
        if (progress.length > 0 && handlers.onProgress !== undefined) {
          handlers.onProgress(progress);
        }
        return;
      }
      if (type !== 'text-delta') {
        return;
      }
      const delta: string = frame.delta ?? '';
      if (delta.length > 0) {
        gotText = true;
        handlers.onDelta(delta, '');
      }
    };

    request.on('dataReceive', (chunk: ArrayBuffer) => {
      buffer += decoder.decodeToString(new Uint8Array(chunk), { stream: true });
      let index: number = buffer.indexOf('\n');
      while (index >= 0) {
        handleLine(buffer.substring(0, index));
        buffer = buffer.substring(index + 1);
        index = buffer.indexOf('\n');
      }
    });

    request.on('dataEnd', () => {
      // 残留 buffer（无换行的末帧）也要过一遍
      if (buffer.length > 0) {
        handleLine(buffer);
        buffer = '';
      }
      if (!gotText) {
        finish(this.conversationId.length > 0 ? '智能体没有返回内容，请重试' : '智能体没有响应，请稍后重试');
        return;
      }
      finish('');
    });

    const inputs: AgentInput[] = [{ type: 'text', text: text }];
    for (let i = 0; i < files.length; i++) {
      const resource: AgentResource = {
        name: files[i].name,
        mimeType: files[i].mimeType,
        size: files[i].sizeKb
      };
      const isImage: boolean = files[i].mimeType.indexOf('image/') === 0;
      inputs.push({ type: isImage ? 'image' : 'file', resource: resource });
    }
    const body: AgentBody = { modelId: modelId, origin: 'user', inputs: inputs };
    if (this.conversationId.length > 0) {
      body.conversationId = this.conversationId;
    }
    const options: http.HttpRequestOptions = {
      method: http.RequestMethod.POST,
      header: this.header(),
      extraData: JSON.stringify(body),
      expectDataType: http.HttpDataType.STRING,
      connectTimeout: 20000,
      readTimeout: 300000
    };

    try {
      request.requestInStream(BASE + STREAM_PATH, options).then((code: number) => {
        hilog.info(0x0000, TAG, 'agent stream http %{public}d', code);
      }).catch((err: BusinessError) => {
        finish(`智能体请求失败：${err.code} ${err.message}`);
      });
    } catch (e) {
      finish('智能体请求无法发出（检查网络权限）');
    }
  }
}

export const agentChat: AgentChat = new AgentChat();
