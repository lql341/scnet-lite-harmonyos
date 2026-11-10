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

/**
 * 按扩展名推断 MIME。
 * 覆盖面按「常见办公/科研文档 + 图片 + 代码文本」来，未知类型退回 octet-stream
 * （服务端会拒，但至少能上传成功让智能体提示，而不是客户端先拦）。
 */
export function mimeOf(name: string): string {
  const dot: number = name.lastIndexOf('.');
  const ext: string = dot >= 0 ? name.substring(dot).toLowerCase() : '';
  const table: Map<string, string> = new Map<string, string>();
  // 文本 / 数据
  table.set('.txt', 'text/plain');
  table.set('.log', 'text/plain');
  table.set('.out', 'text/plain');
  table.set('.md', 'text/markdown');
  table.set('.markdown', 'text/markdown');
  table.set('.csv', 'text/csv');
  table.set('.tsv', 'text/tab-separated-values');
  table.set('.json', 'application/json');
  table.set('.xml', 'application/xml');
  table.set('.yaml', 'text/plain');
  table.set('.yml', 'text/plain');
  table.set('.toml', 'text/plain');
  table.set('.html', 'text/html');
  table.set('.htm', 'text/html');
  table.set('.tex', 'text/plain');
  table.set('.bib', 'text/plain');
  table.set('.srt', 'text/plain');
  // 代码
  table.set('.py', 'text/plain');
  table.set('.js', 'text/plain');
  table.set('.ts', 'text/plain');
  table.set('.sh', 'text/plain');
  table.set('.c', 'text/plain');
  table.set('.h', 'text/plain');
  table.set('.cpp', 'text/plain');
  table.set('.hpp', 'text/plain');
  table.set('.rs', 'text/plain');
  table.set('.go', 'text/plain');
  table.set('.java', 'text/plain');
  table.set('.r', 'text/plain');
  table.set('.m', 'text/plain');
  table.set('.f90', 'text/plain');
  table.set('.f', 'text/plain');
  table.set('.inp', 'text/plain');
  // 文档
  table.set('.pdf', 'application/pdf');
  table.set('.doc', 'application/msword');
  table.set('.docx', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document');
  table.set('.xls', 'application/vnd.ms-excel');
  table.set('.xlsx', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
  table.set('.ppt', 'application/vnd.ms-powerpoint');
  table.set('.pptx', 'application/vnd.openxmlformats-officedocument.presentationml.presentation');
  table.set('.rtf', 'application/rtf');
  table.set('.epub', 'application/epub+zip');
  // 图片
  table.set('.png', 'image/png');
  table.set('.jpg', 'image/jpeg');
  table.set('.jpeg', 'image/jpeg');
  table.set('.gif', 'image/gif');
  table.set('.webp', 'image/webp');
  table.set('.bmp', 'image/bmp');
  table.set('.svg', 'image/svg+xml');
  table.set('.heic', 'image/heic');
  table.set('.tif', 'image/tiff');
  table.set('.tiff', 'image/tiff');
  // 音视频 / 压缩包
  table.set('.mp3', 'audio/mpeg');
  table.set('.wav', 'audio/wav');
  table.set('.m4a', 'audio/mp4');
  table.set('.mp4', 'video/mp4');
  table.set('.mov', 'video/quicktime');
  table.set('.zip', 'application/zip');
  table.set('.tar', 'application/x-tar');
  table.set('.gz', 'application/gzip');
  const hit: string | undefined = table.get(ext);
  return hit !== undefined ? hit : 'application/octet-stream';
}

/** OCR 端点实测只接受「图片 + PDF」（docx/xlsx/pptx/md/csv 会报 File type cannot be supported）。 */
export function isOcrSupported(name: string): boolean {
  const mime: string = mimeOf(name);
  return mime.indexOf('image/') === 0 || mime === 'application/pdf';
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
