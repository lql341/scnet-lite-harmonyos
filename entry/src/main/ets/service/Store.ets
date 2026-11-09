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

  getTheme(): string {
    return this.readString(KEY_THEME, 'ocean');
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
