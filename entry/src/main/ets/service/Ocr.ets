/**
 * OCR 识别（平台 OCR 模型）。
 *
 * 契约（2026-11-09 本机实测，**不是** JSON 接口）：
 *   POST https://api.scnet.cn/api/llm/v1/ocr/recognize
 *        Authorization: Bearer <sk-…>
 *        Content-Type: multipart/form-data
 *        fields: file=<图片字节>, ocrType=<枚举>
 *   → { code:"0", data:[{ traceId, originalFilename, cosPath,
 *                        result:[{ status, coordinate[], confidence, elements{} }] }] }
 *
 * ⚠️ 踩坑记录：
 * - `ocrType` 必须是**表单字段**；放 JSON body 会被忽略并报
 *   `Field 'ocrType' cannot be null`（更容易误判成"参数名不对"）。
 * - 查询参数 `ocr_type` 不参与校验，只有表单字段生效。
 * - 值是**大写枚举**，小写（general/basic）会报 `ocr_type ：{x} is not support`。
 */
import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG: string = 'SCNetLite';
const URL: string = 'https://api.scnet.cn/api/llm/v1/ocr/recognize';

/** 平台支持的识别类型（实测全部可用）。 */
export interface OcrType {
  code: string;
  label: string;
}

export const OCR_TYPES: OcrType[] = [
  { code: 'GENERAL', label: '通用识别' },
  { code: 'PRINTED_TEXT', label: '印刷文字' },
  { code: 'HANDWRITING', label: '手写体' },
  { code: 'ID_CARD', label: '身份证' },
  { code: 'BANK_CARD', label: '银行卡' },
  { code: 'DRIVER_LICENSE', label: '驾驶证' },
  { code: 'VEHICLE_LICENSE', label: '行驶证' },
  { code: 'VEHICLE_VIN', label: '车架号' },
  { code: 'BUSINESS_LICENSE', label: '营业执照' },
  { code: 'INVOICE', label: '发票' },
  { code: 'TAXI_RECEIPT', label: '出租车票' },
  { code: 'SOCIAL_SECURITY', label: '社保卡' }
];

export interface OcrElement {
  text?: string;
}

export interface OcrResult {
  /** 识别出的文字行（按 elements 展开） */
  lines: string[];
  traceId: string;
  /** 原始结果，调试用 */
  raw: string;
}

interface Envelope {
  code?: string;
  msg?: string;
  data?: object;
}

/** 多段 multipart 拼装（不引三方库）。 */
function buildMultipart(boundary: string, fileName: string, mime: string, bytes: Uint8Array,
  fieldName: string, fieldValue: string): ArrayBuffer {
  const head: string = `--${boundary}\r\n` +
    `Content-Disposition: form-data; name="${fieldName}"\r\n\r\n${fieldValue}\r\n` +
    `--${boundary}\r\n` +
    `Content-Disposition: form-data; name="file"; filename="${fileName}"\r\n` +
    `Content-Type: ${mime}\r\n\r\n`;
  const tail: string = `\r\n--${boundary}--\r\n`;
  const enc = new util.TextEncoder();
  const headBytes: Uint8Array = enc.encodeInto(head);
  const tailBytes: Uint8Array = enc.encodeInto(tail);
  const total: number = headBytes.length + bytes.length + tailBytes.length;
  const out: ArrayBuffer = new ArrayBuffer(total);
  const view: Uint8Array = new Uint8Array(out);
  let offset: number = 0;
  for (let i = 0; i < headBytes.length; i++) {
    view[offset++] = headBytes[i];
  }
  for (let i = 0; i < bytes.length; i++) {
    view[offset++] = bytes[i];
  }
  for (let i = 0; i < tailBytes.length; i++) {
    view[offset++] = tailBytes[i];
  }
  return out;
}

class Ocr {
  async recognize(apiKey: string, bytes: Uint8Array, fileName: string, mime: string,
    ocrType: string): Promise<OcrResult> {
    const boundary: string = `----scnet${Date.now()}`;
    const body: ArrayBuffer = buildMultipart(boundary, fileName, mime, bytes, 'ocrType', ocrType);
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
      const resp = await client.request(URL, options);
      const text: string = typeof resp.result === 'string' ? resp.result as string : '';
      const env: Envelope = JSON.parse(text) as Envelope;
      if (env.code !== '0') {
        throw new Error(env.msg ?? `识别失败（HTTP ${resp.responseCode}）`);
      }
      const rows: Record<string, Object>[] = env.data as Record<string, Object>[];
      const lines: string[] = [];
      let traceId: string = '';
      if (Array.isArray(rows)) {
        for (let i = 0; i < rows.length; i++) {
          const row = rows[i];
          if (traceId.length === 0) {
            traceId = String(row['traceId'] ?? '');
          }
          const results: Record<string, Object>[] = row['result'] as Record<string, Object>[];
          if (!Array.isArray(results)) {
            continue;
          }
          for (let j = 0; j < results.length; j++) {
            const elements = results[j]['elements'] as Record<string, Object> | undefined;
            if (elements === undefined || elements === null) {
              continue;
            }
            this.collect(elements, lines);
          }
        }
      }
      hilog.info(0x0000, TAG, 'ocr ok lines=%{public}d trace=%{public}s', lines.length, traceId);
      const out: OcrResult = { lines: lines, traceId: traceId, raw: text };
      return out;
    } catch (e) {
      if (e instanceof Error) {
        throw e as Error;
      }
      const err = e as BusinessError;
      throw new Error(err.message ?? 'OCR 请求失败');
    } finally {
      client.destroy();
    }
  }

  /** elements 是嵌套结构，递归抓所有 text 字段。 */
  private collect(node: Record<string, Object>, out: string[]): void {
    const keys: string[] = Object.keys(node);
    for (let i = 0; i < keys.length; i++) {
      const value = node[keys[i]];
      if (keys[i] === 'text' && typeof value === 'string') {
        const text: string = (value as string).trim();
        if (text.length > 0) {
          out.push(text);
        }
        continue;
      }
      if (Array.isArray(value)) {
        const items: Object[] = value as Object[];
        for (let j = 0; j < items.length; j++) {
          if (items[j] !== null && typeof items[j] === 'object') {
            this.collect(items[j] as Record<string, Object>, out);
          }
        }
      } else if (value !== null && typeof value === 'object') {
        this.collect(value as Record<string, Object>, out);
      }
    }
  }
}

export const ocr: Ocr = new Ocr();
