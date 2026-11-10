import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';

const STORE_NAME: string = 'scnet_lite';
const KEY_API_KEY: string = 'apiKey';
const KEY_BASE_URL: string = 'baseUrl';
const KEY_MODEL: string = 'model';
/**
 * 默认模型。**必须是 `SCNet-Max`**：它是平台自营模型，账号无余额也能用；
 * 其余 32 个都是上游付费模型，余额为 0 时一律 `402 Insufficient Balance`。
 * （隔壁 scnet-cli 的 `pickDefaultModel()` 也是优先 SCNet-Max，所以它“不需要余额”。）
 */
export const DEFAULT_MODEL: string = 'SCNet-Max';
const KEY_THEME: string = 'themePalette';
const KEY_CLUSTER: string = 'clusterId';
const KEY_USER_NAME: string = 'platformUserName';
const KEY_HAD_SESSION: string = 'hadSession';
const KEY_AVATAR: string = 'avatar';
const KEY_CP_NAME: string = 'customProviderName';
const KEY_CP_URL: string = 'customProviderUrl';
const KEY_CP_KEY: string = 'customProviderKey';
const KEY_CP_MODEL: string = 'customProviderModel';
const KEY_MODEL_PROVIDER: string = 'modelProvider';
const KEY_HPC_AK: string = 'hpcAk';
const KEY_HPC_SK: string = 'hpcSk';
const KEY_HPC_USER: string = 'hpcUser';
const KEY_FONT_LEVEL: string = 'fontLevel';
const KEY_LANG: string = 'lang';
const KEY_CHANNEL: string = 'channel';
const KEY_AGENT: string = 'agentIdentify';
const KEY_CLOUD_TOKEN: string = 'cloudToken';
const KEY_CLOUD_COOKIE: string = 'cloudCookie';
const KEY_AUTO_KEY: string = 'autoGatewayKey';

/** 网关默认 base：平台 `createActivityApiKey` 下发的就是 /api/llm/v1（不是 /api/gw/v1）。 */
export const DEFAULT_BASE_URL: string = 'https://api.scnet.cn/api/llm/v1';

class Store {
  private prefs: preferences.Preferences | null = null;

  init(context: common.UIAbilityContext): void {
    try {
      this.prefs = preferences.getPreferencesSync(context, { name: STORE_NAME });
    } catch (e) {
      hilog.error(0x0000, 'SCNetLite', 'preferences init failed');
    }
  }

  getApiKey(): string {
    return this.readString(KEY_API_KEY, '');
  }

  setApiKey(value: string): void {
    this.writeString(KEY_API_KEY, value);
  }

  getBaseUrl(): string {
    return this.readString(KEY_BASE_URL, DEFAULT_BASE_URL);
  }

  setBaseUrl(value: string): void {
    this.writeString(KEY_BASE_URL, value);
  }

  getModel(): string {
    return this.readString(KEY_MODEL, DEFAULT_MODEL);
  }

  setModel(value: string): void {
    this.writeString(KEY_MODEL, value);
  }

  /** 当前选中的集群 id（0 = 还没选，用列表第一个）。 */
  getClusterId(): number {
    if (this.prefs === null) {
      return 0;
    }
    try {
      const value = this.prefs.getSync(KEY_CLUSTER, 0);
      return typeof value === 'number' ? value as number : 0;
    } catch (e) {
      return 0;
    }
  }

  setClusterId(value: number): void {
    if (this.prefs === null) {
      return;
    }
    try {
      this.prefs.putSync(KEY_CLUSTER, value);
      this.prefs.flush();
    } catch (e) {
      // 忽略
    }
  }

  /** 选中的 provider：'platform'（平台网关）或 'custom'（用户自配）。 */
  getModelProvider(): string {
    return this.readString(KEY_MODEL_PROVIDER, 'platform');
  }

  setModelProvider(value: string): void {
    this.writeString(KEY_MODEL_PROVIDER, value);
  }

  getCustomName(): string {
    return this.readString(KEY_CP_NAME, '');
  }

  getCustomBaseUrl(): string {
    return this.readString(KEY_CP_URL, '');
  }

  getCustomApiKey(): string {
    return this.readString(KEY_CP_KEY, '');
  }

  getCustomModel(): string {
    return this.readString(KEY_CP_MODEL, '');
  }

  setCustomProvider(name: string, baseUrl: string, apiKey: string, model: string): void {
    this.writeString(KEY_CP_NAME, name);
    this.writeString(KEY_CP_URL, baseUrl);
    this.writeString(KEY_CP_KEY, apiKey);
    this.writeString(KEY_CP_MODEL, model);
  }

  clearCustomProvider(): void {
    this.writeString(KEY_CP_NAME, '');
    this.writeString(KEY_CP_URL, '');
    this.writeString(KEY_CP_KEY, '');
    this.writeString(KEY_CP_MODEL, '');
    this.writeString(KEY_MODEL_PROVIDER, 'platform');
  }

  /** 头像：'' = 用姓名首字；'preset:<id>' = 内置；'file:<uri>' = 用户选的图片 */
  getAvatar(): string {
    return this.readString(KEY_AVATAR, '');
  }

  setAvatar(value: string): void {
    this.writeString(KEY_AVATAR, value);
  }

  /** 曾经成功登录过（用于区分「首次使用」和「登录已过期」）。 */
  hadSession(): boolean {
    return this.readString(KEY_HAD_SESSION, '') === '1';
  }

  setHadSession(value: boolean): void {
    this.writeString(KEY_HAD_SESSION, value ? '1' : '');
  }

  getPlatformUserName(): string {
    return this.readString(KEY_USER_NAME, '');
  }

  setPlatformUserName(value: string): void {
    this.writeString(KEY_USER_NAME, value);
  }

  getHpcAk(): string {
    return this.readString(KEY_HPC_AK, '');
  }

  setHpcAk(value: string): void {
    this.writeString(KEY_HPC_AK, value);
  }

  getHpcSk(): string {
    return this.readString(KEY_HPC_SK, '');
  }

  setHpcSk(value: string): void {
    this.writeString(KEY_HPC_SK, value);
  }

  getHpcUser(): string {
    return this.readString(KEY_HPC_USER, '');
  }

  setHpcUser(value: string): void {
    this.writeString(KEY_HPC_USER, value);
  }

  getFontLevel(): number {
    if (this.prefs === null) {
      return 1;
    }
    try {
      const value = this.prefs.getSync(KEY_FONT_LEVEL, 1);
      return typeof value === 'number' ? value as number : 1;
    } catch (e) {
      return 1;
    }
  }

  setFontLevel(value: number): void {
    if (this.prefs === null) {
      return;
    }
    try {
      this.prefs.putSync(KEY_FONT_LEVEL, value);
      this.prefs.flush();
    } catch (e) {
      // 忽略
    }
  }

  /** 'zh' 或 'en' */
  getLang(): string {
    return this.readString(KEY_LANG, 'zh');
  }

  setLang(value: string): void {
    this.writeString(KEY_LANG, value);
  }

  getTheme(): string {
    return this.readString(KEY_THEME, 'claude');
  }

  setTheme(value: string): void {
    this.writeString(KEY_THEME, value);
  }

  /** 'agent'（平台服务）或 'llm'（网关模型）。 */
  getChannel(): string {
    return this.readString(KEY_CHANNEL, 'agent');
  }

  setChannel(value: string): void {
    this.writeString(KEY_CHANNEL, value);
  }

  getAgent(): string {
    return this.readString(KEY_AGENT, 'aiagent-router');
  }

  setAgent(value: string): void {
    this.writeString(KEY_AGENT, value);
  }

  getCloudToken(): string {
    return this.readString(KEY_CLOUD_TOKEN, '');
  }

  setCloudToken(value: string): void {
    this.writeString(KEY_CLOUD_TOKEN, value);
  }

  getCloudCookie(): string {
    return this.readString(KEY_CLOUD_COOKIE, '');
  }

  setCloudCookie(value: string): void {
    this.writeString(KEY_CLOUD_COOKIE, value);
  }

  getAutoKey(): string {
    return this.readString(KEY_AUTO_KEY, '');
  }

  setAutoKey(value: string): void {
    this.writeString(KEY_AUTO_KEY, value);
  }

  clearCloudAuth(): void {
    this.writeString(KEY_CLOUD_TOKEN, '');
    this.writeString(KEY_CLOUD_COOKIE, '');
  }

  private readString(key: string, fallback: string): string {
    if (this.prefs === null) {
      return fallback;
    }
    try {
      const value = this.prefs.getSync(key, fallback);
      return typeof value === 'string' ? value as string : fallback;
    } catch (e) {
      return fallback;
    }
  }

  private writeString(key: string, value: string): void {
    if (this.prefs === null) {
      return;
    }
    try {
      this.prefs.putSync(key, value);
      this.prefs.flush();
    } catch (e) {
      hilog.error(0x0000, 'SCNetLite', 'preferences write failed');
    }
  }
}

export const store: Store = new Store();
