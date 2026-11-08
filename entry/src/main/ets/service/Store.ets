import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';

const STORE_NAME: string = 'scnet_lite';
const KEY_API_KEY: string = 'apiKey';
const KEY_BASE_URL: string = 'baseUrl';
const KEY_MODEL: string = 'model';

export const DEFAULT_BASE_URL: string = 'https://api.scnet.cn/api/gw/v1';

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
    return this.readString(KEY_MODEL, 'glm-5.3-flash');
  }

  setModel(value: string): void {
    this.writeString(KEY_MODEL, value);
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
