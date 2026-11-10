/**
 * 附件上传（平台 OSS 直传）。
 *
 * 流程（与桌面端一致，2026-11-09 本机 curl 端到端验证）：
 *   1) POST /acx/chatbot/file/upload/url  body: [{fileId, fileName, totalSize:"0"}]
 *        → [{fileName, fileId, uploadUrl}]（uploadUrl 是 OSS 预签名地址，5 分钟有效）
 *   2) PUT uploadUrl  （Content-Type + Content-Length + x-amz-meta-total-size: 0）
 *   3) 发消息时把「返回的 fileName」放进 inputs：
 *        { "type": "file"|"image",
 *          "resource": { "name": fileName, "mimeType": "...", "size": <KB> } }
 *      智能体侧会调用 download_oss_files 拉取（实测可用）。
 *
 * 注意：第 2 步必须直连预签名 URL，不能带我们的 Token/Cookie 头（OSS 会拒）。
 */
import { http } from '@kit.NetworkKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { credentials } from './Http';

const TAG: string = 'SCNetLite';
const BASE: string = 'https://www.scnet.cn';

/** 已上传到平台的文件，可直接放进 v2 的 inputs。 */
export interface UploadedFile {
  /** 平台返回的 fileName（**不是**本地文件名） */
  name: string;
  mimeType: string;
  /** KB（平台按 1024 字节折算） */
  sizeKb: number;
  localName: string;
}

interface UploadRequest {
  fileId: string;
  fileName: string;
  totalSize: string;
}

interface UploadTicket {
  fileName?: string;
  fileId?: string;
  uploadUrl?: string;
}

interface ApiEnvelope {
  code?: string;
  msg?: string;
  data?: object;
}

/** 按扩展名推断 MIME（与桌面端同一张表）。 */
export function mimeOf(name: string): string {
  const dot: number = name.lastIndexOf('.');
  const ext: string = dot >= 0 ? name.substring(dot).toLowerCase() : '';
  if (ext === '.csv') {
    return 'text/csv';
  }
  if (ext === '.txt' || ext === '.log' || ext === '.out' || ext === '.sh' || ext === '.py'
    || ext === '.js' || ext === '.ts' || ext === '.c' || ext === '.cpp' || ext === '.rs'
    || ext === '.yaml' || ext === '.yml' || ext === '.toml' || ext === '.html' || ext === '.htm') {
    return 'text/plain';
  }
  if (ext === '.md') {
    return 'text/markdown';
  }
  if (ext === '.json') {
    return 'application/json';
  }
  if (ext === '.pdf') {
    return 'application/pdf';
  }
  if (ext === '.png') {
    return 'image/png';
  }
  if (ext === '.jpg' || ext === '.jpeg') {
    return 'image/jpeg';
  }
  if (ext === '.gif') {
    return 'image/gif';
  }
  if (ext === '.webp') {
    return 'image/webp';
  }
  if (ext === '.docx') {
    return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
  }
  return 'application/octet-stream';
}

class Uploader {
  /** 申请上传地址。 */
  private async ticket(name: string): Promise<UploadTicket | null> {
    const head: Record<string, string> = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'source': 'HarmonyOS',
      'version': credentials.version
    };
    if (credentials.token.length > 0) {
      head['Token'] = credentials.token;
    }
    if (credentials.cookie.length > 0) {
      head['Cookie'] = credentials.cookie;
    }
    const request: UploadRequest = {
      fileId: `${Date.now()}-${Math.floor(Math.random() * 100000)}`,
      fileName: name,
      totalSize: '0'
    };
    const bodies: UploadRequest[] = [request];
    const options: http.HttpRequestOptions = {
      method: http.RequestMethod.POST,
      header: head as Record<string, string>,
      extraData: JSON.stringify(bodies),
      expectDataType: http.HttpDataType.STRING,
      connectTimeout: 15000,
      readTimeout: 30000
    };
    const client: http.HttpRequest = http.createHttp();
    try {
      const resp = await client.request(`${BASE}/acx/chatbot/file/upload/url`, options);
      const text: string = typeof resp.result === 'string' ? resp.result as string : '';
      const env: ApiEnvelope = JSON.parse(text) as ApiEnvelope;
      const list: UploadTicket[] = env.data as UploadTicket[];
      if (Array.isArray(list) && list.length > 0) {
        return list[0];
      }
      hilog.warn(0x0000, TAG, 'upload ticket empty: %{public}s', env.msg ?? '');
      this.lastError = `申请上传地址失败：${env.msg ?? '空响应'}`;
      return null;
    } catch (e) {
      const err = e as BusinessError;
      hilog.warn(0x0000, TAG, 'upload ticket failed: %{public}s', err.message ?? '');
      this.lastError = `申请上传地址异常：${err.message ?? ''}`;
      return null;
    } finally {
      client.destroy();
    }
  }

  /** 把字节 PUT 到预签名地址（不能带平台鉴权头）。 */
  private async put(url: string, data: ArrayBuffer, mime: string, size: number): Promise<boolean> {
    const head: Record<string, string> = {
      'Content-Type': mime,
      'Content-Length': `${size}`,
      'x-amz-meta-total-size': '0'
    };
    const options: http.HttpRequestOptions = {
      method: http.RequestMethod.PUT,
      header: head as Record<string, string>,
      extraData: data,
      expectDataType: http.HttpDataType.STRING,
      connectTimeout: 20000,
      readTimeout: 120000
    };
    const client: http.HttpRequest = http.createHttp();
    try {
      const resp = await client.request(url, options);
      hilog.info(0x0000, TAG, 'oss put http %{public}d', resp.responseCode);
      if (resp.responseCode !== 200) {
        this.lastError = `OSS 上传返回 HTTP ${resp.responseCode}`;
      }
      return resp.responseCode === 200;
    } catch (e) {
      const err = e as BusinessError;
      hilog.warn(0x0000, TAG, 'oss put failed: %{public}s', err.message ?? '');
      return false;
    } finally {
      client.destroy();
    }
  }

  /** 最近一次失败原因（UI 直接展示，避免"上传失败"四个字说不清）。 */
  lastError: string = '';

  /** 读本地文件（picker 给的 uri）并上传。 */
  async uploadFile(uri: string, displayName: string): Promise<UploadedFile | null> {
    this.lastError = '';
    let size: number = 0;
    let data: ArrayBuffer | null = null;
    let file: fs.File | null = null;
    try {
      file = fs.openSync(uri, fs.OpenMode.READ_ONLY);
      const stat = fs.statSync(file.fd);
      size = stat.size;
      if (size <= 0) {
        this.lastError = `文件为空（0 字节）：${displayName}`;
        return null;
      }
      if (size > 40 * 1024 * 1024) {
        this.lastError = `文件超过 40MB：${Math.round(size / 1048576)}MB`;
        return null;
      }
      const buffer = new ArrayBuffer(size);
      fs.readSync(file.fd, buffer);
      data = buffer;
    } catch (e) {
      const err = e as BusinessError;
      // picker 返回的 uri 拿不到读权限时最常见；把 code 带出来便于判断
      this.lastError = `读取失败(${err.code ?? '?'})：${err.message ?? displayName}`;
      hilog.warn(0x0000, TAG, 'read file failed code=%{public}s', String(err.code ?? '?'));
      return null;
    } finally {
      if (file !== null) {
        try {
          fs.closeSync(file);
        } catch (e) {
          // 忽略
        }
      }
    }
    if (data === null) {
      return null;
    }
    const uploaded: UploadedFile | null = await this.uploadBytes(data, displayName, size);
    if (uploaded === null && this.lastError.length === 0) {
      this.lastError = '上传到平台失败（检查网络或登录态）';
    }
    return uploaded;
  }

  /** 直接上传内存里的字节（自检/粘贴文本用）。 */
  async uploadBytes(data: ArrayBuffer, displayName: string, size: number): Promise<UploadedFile | null> {
    const mime: string = mimeOf(displayName);
    const ticket: UploadTicket | null = await this.ticket(displayName);
    if (ticket === null || ticket.uploadUrl === undefined || ticket.fileName === undefined) {
      return null;
    }
    const ok: boolean = await this.put(ticket.uploadUrl, data, mime, size);
    if (!ok) {
      return null;
    }
    const uploaded: UploadedFile = {
      name: ticket.fileName,
      mimeType: mime,
      sizeKb: size / 1024,
      localName: displayName
    };
    hilog.info(0x0000, TAG, 'uploaded %{public}s size=%{public}d', uploaded.name, size);
    return uploaded;
  }

  /** 自检：上传一段固定 CSV，验证整条链路（长按 ＋ 触发）。 */
  async selfTest(): Promise<UploadedFile | null> {
    const csv: string = 'site,value\na,1\nb,2\nc,3\n';
    const data: ArrayBuffer = new util.TextEncoder().encodeInto(csv).buffer as ArrayBuffer;
    return await this.uploadBytes(data, `scnet-selftest-${Date.now() % 100000}.csv`, csv.length);
  }
}

export const uploader: Uploader = new Uploader();
