/**
 * 应用内检查更新（与 Android 版同一套逻辑）。
 *
 * 仓库已公开，所以可以直接匿名调 GitHub Releases API：
 *   GET https://api.github.com/repos/<owner>/<repo>/releases/latest
 *   → { tag_name, body, assets[{ name, browser_download_url }] }
 *
 * 若配置了自定义更新源（设置 → 调试），优先用它：
 *   { "versionName": "0.7.4", "versionCode": 32,
 *     "url": "https://…/scnet-agent-0.7.4.apk", "notes": "…" }
 */
import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG: string = 'SCNetLite';
const GITHUB_API: string =
  'https://api.github.com/repos/lql341/scnet-lite-harmonyos/releases/latest';

export interface UpdateInfo {
  versionName: string;
  notes: string;
  /** APK / HAP 下载地址 */
  url: string;
  /** 是否有更新 */
  newer: boolean;
  /** 失败原因（空 = 成功） */
  error: string;
  /** 来源：custom / github */
  source: string;
}

function parseVersion(text: string): number[] {
  const digits: string = (text ?? '').replace(/[^0-9.]/g, ' ').trim().split(' ')[0];
  const out: number[] = [0, 0, 0];
  const parts: string[] = digits.split('.');
  for (let i = 0; i < 3 && i < parts.length; i++) {
    const n: number = parseInt(parts[i], 10);
    out[i] = Number.isFinite(n) ? n : 0;
  }
  return out;
}

function isNewer(tag: string, current: string): boolean {
  const a: number[] = parseVersion(tag);
  const b: number[] = parseVersion(current);
  for (let i = 0; i < 3; i++) {
    if (a[i] !== b[i]) {
      return a[i] > b[i];
    }
  }
  return false;
}

async function fetchText(url: string): Promise<string> {
  const request: http.HttpRequest = http.createHttp();
  const options: http.HttpRequestOptions = {
    method: http.RequestMethod.GET,
    header: {
      'Accept': 'application/vnd.github+json',
      'User-Agent': 'SCNetAgent-HarmonyOS'
    } as Record<string, string>,
    expectDataType: http.HttpDataType.STRING,
    connectTimeout: 12000,
    readTimeout: 20000
  };
  try {
    const resp = await request.request(url, options);
    return typeof resp.result === 'string' ? resp.result as string : '';
  } catch (e) {
    const err = e as BusinessError;
    hilog.warn(0x0000, TAG, 'update fetch failed: %{public}s', err.message ?? '');
    return '';
  } finally {
    request.destroy();
  }
}

export async function checkUpdate(currentVersion: string, customUrl: string): Promise<UpdateInfo> {
  const info: UpdateInfo = { versionName: '', notes: '', url: '', newer: false, error: '', source: '' };

  if (customUrl.length > 0) {
    info.source = 'custom';
    const text: string = await fetchText(customUrl);
    if (text.length === 0) {
      info.error = '自定义更新源不可达';
      return info;
    }
    try {
      const json: Record<string, Object> = JSON.parse(text) as Record<string, Object>;
      info.versionName = String(json['versionName'] ?? json['tag_name'] ?? '');
      info.url = String(json['url'] ?? json['apk'] ?? '');
      info.notes = String(json['notes'] ?? json['body'] ?? '');
      info.newer = isNewer(info.versionName, currentVersion);
      if (info.url.length === 0) {
        info.error = '更新源 JSON 里没有 url 字段';
      }
      return info;
    } catch (e) {
      info.error = '更新源不是合法 JSON';
      return info;
    }
  }

  info.source = 'github';
  const body: string = await fetchText(GITHUB_API);
  if (body.length === 0) {
    info.error = '请求 GitHub 失败（网络或仓库不可达）';
    return info;
  }
  try {
    const release: Record<string, Object> = JSON.parse(body) as Record<string, Object>;
    info.versionName = String(release['tag_name'] ?? '');
    info.notes = String(release['body'] ?? '');
    const assets: Record<string, Object>[] = release['assets'] as Record<string, Object>[];
    if (Array.isArray(assets)) {
      for (let i = 0; i < assets.length; i++) {
        const name: string = String(assets[i]['name'] ?? '');
        if (name.endsWith('.hap') || name.endsWith('.apk')) {
          info.url = String(assets[i]['browser_download_url'] ?? '');
          break;
        }
      }
    }
    info.newer = isNewer(info.versionName, currentVersion);
    if (info.url.length === 0) {
      info.error = 'Release 里没有安装包';
    }
    return info;
  } catch (e) {
    info.error = '解析 GitHub 响应失败';
    return info;
  }
}
