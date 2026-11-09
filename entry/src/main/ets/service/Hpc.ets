/**
 * SCNet HPC OpenAPI 客户端（AK/SK 签名）。
 *
 * 契约来自 `../scnet-cli` 的 `packages/scnet-agent/src/core/sci/openapi.mjs`（已跑通真作业），
 * 并在本机用真实 AK/SK 复验过标注「实测」的部分：
 *
 *   POST {api.scnet.cn}/api/user/v3/tokens
 *        headers: user / accessKey / timestamp / signature
 *        signature = hex(HMAC-SHA256(secretKey, JSON.stringify({accessKey,timestamp,user})))
 *        → [{clusterId, clusterName, token}]（每集群一个 JWT）
 *   GET  {www}/ac/openapi/v2/center            header: token
 *        → { hpcUrls[], efileUrls[], eshellUrls[], clusterUserInfo{userName,homePath} }
 *   GET  {hpc}/hpc/openapi/v2/cluster          → 调度器列表（SLURM，id 即 strJobManagerID）  实测
 *   GET  {hpc}/hpc/openapi/v2/queuenames/users/{user}?strJobManagerID=…   → 队列（含空闲核数）实测
 *   GET  {hpc}/hpc/openapi/v2/userquotas/userlimit?strJobManagerID=…      → 配额上限          实测
 *   GET  {hpc}/hpc/openapi/v2/jobs?strClusterIDList=…&start=0&limit=N     → 运行中作业（偶发 10001）
 *   POST {hpc}/hpc/openapi/v2/apptemplates/BASIC/BASE/job                 → 提交作业
 *   DELETE {hpc}/hpc/openapi/v2/jobs?strJobInfoMap=<scheduler>,<user>:<jobId>:  → 取消
 */
import { http } from '@kit.NetworkKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { store } from './Store';

const TAG: string = 'SCNetLite';
const API_BASE: string = 'https://api.scnet.cn';
const WEB_BASE: string = 'https://www.scnet.cn';

export interface HpcRegion {
  clusterId: string;
  clusterName: string;
  token: string;
}

export interface HpcScheduler {
  id?: number;
  text?: string;
  JobManagerType?: string;
}

export interface HpcQueue {
  name: string;
  freeCpus: string;
  totalCpus: string;
  maxPpn: string;
  nodes: string;
}

export interface HpcQuota {
  userName: string;
  accountMaxCpu: number;
  accountMaxDcu: number;
  accountMaxJob: number;
  accountMaxRun: number;
}

/** 某个集群 + 用户的完整执行上下文（拿一次缓存起来）。 */
export interface HpcContext {
  clusterId: string;
  clusterName: string;
  token: string;
  hpcUrl: string;
  efileUrl: string;
  userName: string;
  homePath: string;
  schedulerId: string;
}

export class HpcError extends Error {
  code: string;

  constructor(code: string, message: string) {
    super(message);
    this.code = code;
  }
}

function utf8(text: string): Uint8Array {
  return new util.TextEncoder().encodeInto(text);
}

/** SHA-256 摘要（走 cryptoFramework 的 Md，只做纯摘要，避开 HMAC 的密钥处理差异）。 */
function sha256(data: Uint8Array): Uint8Array {
  const md = cryptoFramework.createMd('SHA256');
  md.updateSync({ data: data });
  const out = md.digestSync();
  return out.data;
}

/**
 * 手写 HMAC-SHA256。
 *
 * 为什么不用 `createMac('SHA256')`：实测它产出的摘要与标准 HMAC-SHA256 不一致
 * （同一 key/message，Python 的 hmac 模块与它对不上），平台侧因此报
 * 「AK/SK签名校验失败」。这里按 RFC 2104 自己拼，行为可控：
 *   HMAC(K,m) = H((K' ^ opad) || H((K' ^ ipad) || m))
 */
function hmacSha256(key: Uint8Array, message: Uint8Array): Uint8Array {
  const BLOCK: number = 64;
  const k: Uint8Array = new Uint8Array(BLOCK);
  if (key.length > BLOCK) {
    const hashed: Uint8Array = sha256(key);
    for (let i = 0; i < hashed.length; i++) {
      k[i] = hashed[i];
    }
  } else {
    for (let i = 0; i < key.length; i++) {
      k[i] = key[i];
    }
  }
  const ipad: Uint8Array = new Uint8Array(BLOCK + message.length);
  const opad: Uint8Array = new Uint8Array(BLOCK + 32);
  for (let i = 0; i < BLOCK; i++) {
    ipad[i] = k[i] ^ 0x36;
    opad[i] = k[i] ^ 0x5c;
  }
  for (let i = 0; i < message.length; i++) {
    ipad[BLOCK + i] = message[i];
  }
  const inner: Uint8Array = sha256(ipad);
  for (let i = 0; i < inner.length; i++) {
    opad[BLOCK + i] = inner[i];
  }
  return sha256(opad);
}

function toHex(bytes: Uint8Array): string {
  let hex: string = '';
  for (let i = 0; i < bytes.length; i++) {
    const h: string = bytes[i].toString(16);
    hex += h.length === 1 ? `0${h}` : h;
  }
  return hex;
}

/** hex(HMAC-SHA256(secret, message)) —— 平台签名用。 */
function hmacHex(secret: string, message: string): string {
  return toHex(hmacSha256(utf8(secret), utf8(message)));
}

function nowSeconds(): string {
  return `${Math.floor(Date.now() / 1000)}`;
}

interface Envelope {
  code?: string;
  msg?: string;
  data?: object;
}

/** 已知向量自检（日志里比对），用于确认 SHA-256 / HMAC 实现与标准一致。 */
export function cryptoSelfCheck(): boolean {
  const sha: string = toHex(sha256(utf8('abc')));
  const shaOk: boolean = sha === 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad';
  const mac: string = hmacHex('key', 'The quick brown fox jumps over the lazy dog');
  const macOk: boolean = mac === 'f7bc83f430538424b13298e6aa6fb143ef4d59a14946175997479dbc2d1a3cd8';
  hilog.info(0x0000, TAG, 'crypto selfcheck sha=%{public}s hmac=%{public}s',
    String(shaOk), String(macOk));
  return shaOk && macOk;
}

class Hpc {
  private regionCache: HpcRegion[] = [];
  private regionsAt: number = 0;
  private contexts: Map<string, HpcContext> = new Map<string, HpcContext>();

  hasCredentials(): boolean {
    return store.getHpcAk().length > 0 && store.getHpcSk().length > 0;
  }

  /** AK/SK 都是 32 位十六进制，长度不对直接拒（避免重复粘贴导致签名失败）。 */
  validateCreds(ak: string, sk: string): string {
    const hex: RegExp = new RegExp('^[0-9a-fA-F]{32}$');
    if (!hex.test(ak)) {
      return 'AccessKey 应为 32 位十六进制';
    }
    if (!hex.test(sk)) {
      return 'SecretKey 应为 32 位十六进制';
    }
    return '';
  }

  /** 第 1 步：AK/SK → 各集群 token（缓存 3.5 小时）。 */
  async regions(refresh: boolean): Promise<HpcRegion[]> {
    if (!refresh && this.regionCache.length > 0 && Date.now() - this.regionsAt < 3.5 * 3600 * 1000) {
      return this.regionCache;
    }
    const ak: string = store.getHpcAk();
    const sk: string = store.getHpcSk();
    // 签名里的 user 就是平台用户名；不让用户手填，避免填错。
    let user: string = store.getHpcUser();
    if (user.length === 0) {
      user = store.getPlatformUserName();
    }
    if (ak.length === 0 || sk.length === 0) {
      throw new HpcError('no-creds', '未配置 AK/SK');
    }
    const ts: string = nowSeconds();
    // 注意：key 顺序必须是 accessKey,timestamp,user（JSON.stringify 保持插入顺序）
    const message: string = `{"accessKey":"${ak}","timestamp":"${ts}","user":"${user}"}`;
    const signature: string = hmacHex(sk, message);
    hilog.info(0x0000, TAG, 'hpc sign msg=%{public}s sig=%{public}s', message, signature);
    const head: Record<string, string> = {
      'user': user,
      'accessKey': ak,
      'signature': signature,
      'timestamp': ts
    };
    const options: http.HttpRequestOptions = {
      method: http.RequestMethod.POST,
      header: head,
      expectDataType: http.HttpDataType.STRING,
      connectTimeout: 15000,
      readTimeout: 30000
    };
    const client: http.HttpRequest = http.createHttp();
    try {
      const resp = await client.request(`${API_BASE}/api/user/v3/tokens`, options);
      const text: string = typeof resp.result === 'string' ? resp.result as string : '';
      if (resp.responseCode !== 200) {
        throw new HpcError(`${resp.responseCode}`, `签名/凭据被拒：${text.substring(0, 120)}`);
      }
      hilog.info(0x0000, TAG, 'hpc token http=%{public}d len=%{public}d head=%{public}s',
        resp.responseCode, text.length, text.substring(0, 120));
      const parsed: Envelope | HpcRegion[] = JSON.parse(text) as Envelope | HpcRegion[];
      const list: HpcRegion[] = Array.isArray(parsed) ? parsed as HpcRegion[] : (parsed as Envelope).data as HpcRegion[];
      this.regionCache = Array.isArray(list) ? list : [];
      this.regionsAt = Date.now();
      hilog.info(0x0000, TAG, 'hpc regions: %{public}d', this.regionCache.length);
      return this.regionCache;
    } catch (e) {
      if (e instanceof HpcError) {
        throw e as HpcError;
      }
      const err = e as BusinessError;
      throw new HpcError(String(err.code), err.message ?? '获取集群令牌失败');
    } finally {
      client.destroy();
    }
  }

  private async getJson(url: string, token: string): Promise<Envelope> {
    const head: Record<string, string> = {
      'token': token,
      'Content-Type': 'application/json',
      'Accept': 'application/json'
    };
    const options: http.HttpRequestOptions = {
      method: http.RequestMethod.GET,
      header: head,
      expectDataType: http.HttpDataType.STRING,
      connectTimeout: 15000,
      readTimeout: 45000
    };
    const client: http.HttpRequest = http.createHttp();
    try {
      const resp = await client.request(url, options);
      const text: string = typeof resp.result === 'string' ? resp.result as string : '';
      return JSON.parse(text) as Envelope;
    } finally {
      client.destroy();
    }
  }

  /** 第 2 + 3 步：区域中心（hpc/efile 域名、home、用户名）+ 调度器 id。 */
  async context(clusterId: string, refresh: boolean): Promise<HpcContext> {
    const cached: HpcContext | undefined = this.contexts.get(clusterId);
    if (!refresh && cached !== undefined) {
      return cached;
    }
    const regions: HpcRegion[] = await this.regions(refresh);
    let picked: HpcRegion | null = null;
    for (let i = 0; i < regions.length; i++) {
      if (String(regions[i].clusterId) === clusterId) {
        picked = regions[i];
        break;
      }
    }
    if (picked === null) {
      throw new HpcError('no-region', `集群 ${clusterId} 没有可用令牌`);
    }
    const centerResp: Envelope = await this.getJson(`${WEB_BASE}/ac/openapi/v2/center`, picked.token);
    const center = centerResp.data as Record<string, Object>;
    const hpcUrls = center['hpcUrls'] as Record<string, Object>[];
    const efileUrls = center['efileUrls'] as Record<string, Object>[];
    const clusterUser = center['clusterUserInfo'] as Record<string, Object> | undefined;
    let hpcUrl: string = '';
    if (Array.isArray(hpcUrls)) {
      for (let i = 0; i < hpcUrls.length; i++) {
        if (String(hpcUrls[i]['enable']) === 'true') {
          hpcUrl = String(hpcUrls[i]['url']);
          break;
        }
      }
    }
    let efileUrl: string = '';
    if (Array.isArray(efileUrls) && efileUrls.length > 0) {
      efileUrl = String(efileUrls[0]['url']);
    }
    if (hpcUrl.length === 0) {
      throw new HpcError('no-hpc', '区域中心没有返回 hpc 地址');
    }
    const schedulerResp: Envelope = await this.getJson(`${hpcUrl}/hpc/openapi/v2/cluster`, picked.token);
    const schedulers: HpcScheduler[] = schedulerResp.data as HpcScheduler[];
    let schedulerId: string = '';
    if (Array.isArray(schedulers) && schedulers.length > 0) {
      schedulerId = String(schedulers[0].id ?? '');
    }
    const ctx: HpcContext = {
      clusterId: String(picked.clusterId),
      clusterName: picked.clusterName,
      token: picked.token,
      hpcUrl: hpcUrl,
      efileUrl: efileUrl,
      userName: clusterUser !== undefined ? String(clusterUser['userName'] ?? '') : '',
      homePath: clusterUser !== undefined ? String(clusterUser['homePath'] ?? '') : '',
      schedulerId: schedulerId
    };
    this.contexts.set(clusterId, ctx);
    hilog.info(0x0000, TAG, 'hpc ctx %{public}s scheduler=%{public}s user=%{public}s',
      clusterId, schedulerId, ctx.userName);
    return ctx;
  }

  async queues(ctx: HpcContext): Promise<HpcQueue[]> {
    const url: string = `${ctx.hpcUrl}/hpc/openapi/v2/queuenames/users/${encodeURIComponent(ctx.userName)}` +
      `?strJobManagerID=${encodeURIComponent(ctx.schedulerId)}`;
    const resp: Envelope = await this.getJson(url, ctx.token);
    const rows: Record<string, Object>[] = resp.data as Record<string, Object>[];
    const out: HpcQueue[] = [];
    if (!Array.isArray(rows)) {
      return out;
    }
    for (let i = 0; i < rows.length; i++) {
      const row = rows[i];
      const queue: HpcQueue = {
        name: String(row['queueName'] ?? row['name'] ?? ''),
        freeCpus: String(row['queFreeNcpus'] ?? ''),
        totalCpus: String(row['queNcpus'] ?? ''),
        maxPpn: String(row['queMaxPPN'] ?? ''),
        nodes: String(row['queNodes'] ?? '')
      };
      if (queue.name.length > 0) {
        out.push(queue);
      }
    }
    hilog.info(0x0000, TAG, 'hpc queues: %{public}d', out.length);
    return out;
  }

  async quota(ctx: HpcContext): Promise<HpcQuota | null> {
    const url: string = `${ctx.hpcUrl}/hpc/openapi/v2/userquotas/userlimit` +
      `?strJobManagerID=${encodeURIComponent(ctx.schedulerId)}`;
    try {
      const resp: Envelope = await this.getJson(url, ctx.token);
      const d = resp.data as Record<string, Object>;
      const quota: HpcQuota = {
        userName: String(d['userName'] ?? ''),
        accountMaxCpu: Number(d['accountMaxCpu'] ?? 0),
        accountMaxDcu: Number(d['accountMaxDcu'] ?? 0),
        accountMaxJob: Number(d['accountMaxSubmitJob'] ?? 0),
        accountMaxRun: Number(d['accountMaxRunJob'] ?? 0)
      };
      return quota;
    } catch (e) {
      return null;
    }
  }

  /** 运行中作业。平台侧偶发 10001（internal_error），这里向上抛由 UI 展示。 */
  async jobs(ctx: HpcContext, limit: number): Promise<Record<string, Object>[]> {
    const url: string = `${ctx.hpcUrl}/hpc/openapi/v2/jobs?strClusterIDList=${encodeURIComponent(ctx.schedulerId)}` +
      `&start=0&limit=${limit}`;
    const resp: Envelope = await this.getJson(url, ctx.token);
    if (resp.code !== undefined && resp.code !== '0') {
      throw new HpcError(resp.code, resp.msg ?? '查询作业失败');
    }
    const data = resp.data as Record<string, Object>;
    if (Array.isArray(data)) {
      return data as Record<string, Object>[];
    }
    const list = data !== undefined && data !== null ? data['list'] : undefined;
    return Array.isArray(list) ? list as Record<string, Object>[] : [];
  }
}

export const hpc: Hpc = new Hpc();
