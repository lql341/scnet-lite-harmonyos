/**
 * 文档解析（DOC_MIND）与格式转换（DOC_CONVERSION）—— 异步任务型接口。
 *
 * 契约来自平台自带的代码示例（`GET /acx/llm/api/console/model/detail?modelName=文档解析`
 * 的 `codeExamples`），本机已端到端验证：
 *
 *   POST {base}/ocrdoc/submit          multipart: file=@x.pdf  + ocr_type=DOC_PARING
 *        → data.output.task_id / task_status(pending|running|succeeded|failed)
 *   POST {base}/ocrdoc/result          JSON: {"task_ids":["<id>"]}
 *        → data[0].output.results = [ "<OSS 预签名 URL，指向结果 json>" ]
 *                                   task_status / submit_time / end_time / error_message
 *
 *   POST {base}/doc/convert/task       multipart: file=@x.pdf  + ocr_type=PDF_TO_WORD
 *        → 同 result 接口取结果（结果是产物文件 URL）
 *
 * 注意：
 * - `ocr_type` 是**表单字段**（与 OCR 的 `ocrType` 大小写不同，别混）；
 * - DOC_PARING 是平台拼写（少一个 S），照抄不要"修正"；
 * - 结果是 OSS 预签名 URL（有效期 3 天），要展示文本需再 GET 那个 json。
 */
import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG: string = 'SCNetLite';
const BASE: string = 'https://api.scnet.cn/api/llm/v1';

/** 文档解析的 ocr_type（平台拼写如此）。 */
export const DOC_PARSE_TYPE: string = 'DOC_PARING';
/** 常见格式转换方向。 */
export const CONVERT_PDF_TO_WORD: string = 'PDF_TO_WORD';
export const CONVERT_WORD_TO_PDF: string = 'WORD_TO_PDF';
export const CONVERT_PDF_TO_EXCEL: string = 'PDF_TO_EXCEL';
export const CONVERT_PDF_TO_PPT: string = 'PDF_TO_PPT';

export interface DocTask {
  taskId: string;
  status: string;
  /** 结果 URL 列表（解析=结果 json，转换=产物文件） */
  results: string[];
  errorMessage: string;
  submitTime: string;
  endTime: string;
}

interface TaskOut {
  task_id?: string;
  task_status?: string;
  results?: string[];
  error_message?: string;
  submit_time?: string;
  end_time?: string;
}

interface Envelope {
  code?: string;
  msg?: string;
  data?: object;
}

/** 单段 multipart 组装（file + ocr_type）。 */
function buildForm(boundary: string, fileName: string, mime: string, bytes: Uint8Array,
  ocrType: string): ArrayBuffer {
  const head: string = `--${boundary}\r\n` +
    `Content-Disposition: form-data; name="file"; filename="${fileName}"\r\n` +
    `Content-Type: ${mime}\r\n\r\n`;
  const mid: string = `\r\n--${boundary}\r\n` +
    `Content-Disposition: form-data; name="ocr_type"\r\n\r\n${ocrType}\r\n` +
    `--${boundary}--\r\n`;
  const enc = new util.TextEncoder();
  const headBytes: Uint8Array = enc.encodeInto(head);
  const midBytes: Uint8Array = enc.encodeInto(mid);
  const out: ArrayBuffer = new ArrayBuffer(headBytes.length + bytes.length + midBytes.length);
  const view: Uint8Array = new Uint8Array(out);
  let off: number = 0;
  for (let i = 0; i < headBytes.length; i++) {
    view[off++] = headBytes[i];
  }
  for (let i = 0; i < bytes.length; i++) {
    view[off++] = bytes[i];
  }
  for (let i = 0; i < midBytes.length; i++) {
    view[off++] = midBytes[i];
  }
  return out;
}

export class DocAi {
  private async postBytes(path: string, apiKey: string, body: ArrayBuffer,
    boundary: string): Promise<Envelope> {
    const head: Record<string, string> = {
      'Authorization': `Bearer ${apiKey}`,
      'Content-Type': `multipart/form-data; boundary=${boundary}`,
      'Accept': 'application/json'
    };
    const options: http.HttpRequestOptions = {
      method: http.RequestMethod.POST,
      header: head,
      extraData: body,
      expectDataType: http.HttpDataType.STRING,
      connectTimeout: 20000,
      readTimeout: 120000
    };
    const client: http.HttpRequest = http.createHttp();
    try {
      const resp = await client.request(BASE + path, options);
      const text: string = typeof resp.result === 'string' ? resp.result as string : '';
      return JSON.parse(text) as Envelope;
    } finally {
      client.destroy();
    }
  }

  /** 提交文档解析任务。 */
  async submitParse(apiKey: string, bytes: Uint8Array, fileName: string, mime: string): Promise<DocTask> {
    const boundary: string = `----scnet${Date.now()}`;
    const body: ArrayBuffer = buildForm(boundary, fileName, mime, bytes, DOC_PARSE_TYPE);
    const env: Envelope = await this.postBytes('/ocrdoc/submit', apiKey, body, boundary);
    return this.pickTask(env);
  }

  /** 提交格式转换任务。 */
  async submitConvert(apiKey: string, bytes: Uint8Array, fileName: string, mime: string,
    target: string): Promise<DocTask> {
    const boundary: string = `----scnet${Date.now()}`;
    const body: ArrayBuffer = buildForm(boundary, fileName, mime, bytes, target);
    const env: Envelope = await this.postBytes('/doc/convert/task', apiKey, body, boundary);
    return this.pickTask(env);
  }

  private pickTask(env: Envelope): DocTask {
    if (env.code !== undefined && String(env.code) !== '0') {
      throw new Error(env.msg ?? '提交失败');
    }
    const data = env.data as Record<string, Object>;
    const out = (data !== undefined && data !== null ? data['output'] : undefined) as TaskOut;
    if (out === undefined || out === null || out.task_id === undefined) {
      throw new Error('提交后没有返回任务号');
    }
    const task: DocTask = {
      taskId: out.task_id ?? '',
      status: out.task_status ?? 'pending',
      results: out.results ?? [],
      errorMessage: out.error_message ?? '',
      submitTime: out.submit_time ?? '',
      endTime: out.end_time ?? ''
    };
    hilog.info(0x0000, TAG, 'doc task %{public}s status=%{public}s', task.taskId, task.status);
    return task;
  }

  /** 查询任务状态 / 结果。 */
  async query(apiKey: string, taskId: string): Promise<DocTask> {
    const head: Record<string, string> = {
      'Authorization': `Bearer ${apiKey}`,
      'Content-Type': 'application/json',
      'Accept': 'application/json'
    };
    const body: string = `{"task_ids":["${taskId}"]}`;
    const options: http.HttpRequestOptions = {
      method: http.RequestMethod.POST,
      header: head,
      extraData: body,
      expectDataType: http.HttpDataType.STRING,
      connectTimeout: 15000,
      readTimeout: 30000
    };
    const client: http.HttpRequest = http.createHttp();
    try {
      const resp = await client.request(BASE + '/ocrdoc/result', options);
      const text: string = typeof resp.result === 'string' ? resp.result as string : '';
      const env: Envelope = JSON.parse(text) as Envelope;
      if (env.code !== undefined && String(env.code) !== '0') {
        throw new Error(env.msg ?? '查询失败');
      }
      const rows = env.data as Record<string, Object>[];
      if (!Array.isArray(rows) || rows.length === 0) {
        throw new Error('查询结果为空');
      }
      const out = rows[0]['output'] as TaskOut;
      const task: DocTask = {
        taskId: out.task_id ?? taskId,
        status: out.task_status ?? '',
        results: out.results ?? [],
        errorMessage: out.error_message ?? '',
        submitTime: out.submit_time ?? '',
        endTime: out.end_time ?? ''
      };
      return task;
    } finally {
      client.destroy();
    }
  }

  /** 拉取结果文件（解析结果是 json；转换结果是产物，非文本时返回空）。 */
  async fetchResult(url: string): Promise<string> {
    const options: http.HttpRequestOptions = {
      method: http.RequestMethod.GET,
      header: { 'Accept': 'application/json, */*' } as Record<string, string>,
      expectDataType: http.HttpDataType.STRING,
      connectTimeout: 15000,
      readTimeout: 60000
    };
    const client: http.HttpRequest = http.createHttp();
    try {
      const resp = await client.request(url, options);
      return typeof resp.result === 'string' ? resp.result as string : '';
    } catch (e) {
      const err = e as BusinessError;
      hilog.warn(0x0000, TAG, 'fetch result failed: %{public}s', err.message ?? '');
      return '';
    } finally {
      client.destroy();
    }
  }

  /**
   * 从解析结果 json 里抽纯文本。
   * 结构随文档而异（版面块/表格/公式），这里做宽容遍历：抓所有 text/content 字段。
   */
  extractText(json: string): string {
    let parsed: Object;
    try {
      parsed = JSON.parse(json) as Object;
    } catch (e) {
      return json;
    }
    const parts: string[] = [];
    const walk = (node: Object): void => {
      if (node === null || node === undefined) {
        return;
      }
      if (Array.isArray(node)) {
        const arr: Object[] = node as Object[];
        for (let i = 0; i < arr.length; i++) {
          walk(arr[i]);
        }
        return;
      }
      if (typeof node !== 'object') {
        return;
      }
      const rec = node as Record<string, Object>;
      const keys: string[] = Object.keys(rec);
      for (let i = 0; i < keys.length; i++) {
        const key: string = keys[i];
        const value = rec[key];
        if ((key === 'text' || key === 'content' || key === 'html' || key === 'markdown')
          && typeof value === 'string') {
          const text: string = (value as string).trim();
          if (text.length > 0) {
            parts.push(text);
          }
        } else if (value !== null && typeof value === 'object') {
          walk(value as Object);
        }
      }
    };
    walk(parsed);
    return parts.join('\n');
  }
}

export const docAi: DocAi = new DocAi();
