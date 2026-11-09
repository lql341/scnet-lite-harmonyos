/**
 * 领域智能体 / 场景模板。
 *
 * 桌面端把它叫 home-scenarios：一份本地目录（4 类 × 若干场景），
 * 每个场景带 `prompt`（预置指令）、`workflowIntent`、`skillName`。
 * 我们把它打包进 rawfile（23 KB），离线可用、不用等接口。
 *
 * 证据来源：`~/.config/scnet-client/home-scenarios/catalog.json`
 * （schemaVersion 2；由桌面端 `home-scenarios.read/refresh` 维护）。
 */
import { resourceManager } from '@kit.LocalizationKit';
import { util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG: string = 'SCNetLite';

export interface ScenarioItem {
  id: string;
  title: string;
  summary: string;
  prompt: string;
  tier: string;
  skills: string[];
  executionMode: string;
  skillName: string;
  capabilities: string[];
  /** 该场景需要附件（CSV/图片等）。当前还没做上传，需要先提示用户。 */
  inputCount: number;
}

export interface ScenarioCategory {
  id: string;
  title: string;
  icon: string;
  items: ScenarioItem[];
}

interface CatalogFile {
  schemaVersion?: number;
  updatedAt?: string;
  categories?: ScenarioCategory[];
}

class Scenarios {
  private categories: ScenarioCategory[] = [];
  private loaded: boolean = false;

  async load(context: resourceManager.ResourceManager): Promise<void> {
    if (this.loaded) {
      return;
    }
    try {
      const bytes: Uint8Array = context.getRawFileContentSync('scenarios.json');
      const text: string = util.TextDecoder.create('utf-8').decodeToString(bytes);
      const file: CatalogFile = JSON.parse(text) as CatalogFile;
      this.categories = file.categories ?? [];
      this.loaded = true;
      let total: number = 0;
      for (let i = 0; i < this.categories.length; i++) {
        total += this.categories[i].items.length;
      }
      hilog.info(0x0000, TAG, 'scenarios: %{public}d categories, %{public}d items',
        this.categories.length, total);
    } catch (e) {
      hilog.warn(0x0000, TAG, 'scenarios load failed');
    }
  }

  list(): ScenarioCategory[] {
    return this.categories;
  }

  /** 某个分类的前 n 个场景（空状态用）。 */
  top(categoryId: string, count: number): ScenarioItem[] {
    for (let i = 0; i < this.categories.length; i++) {
      if (this.categories[i].id === categoryId) {
        return this.categories[i].items.slice(0, count);
      }
    }
    return [];
  }

  /** 换一批：按 offset 轮转，保证能刷出不同场景。 */
  rotate(categoryId: string, count: number, offset: number): ScenarioItem[] {
    let all: ScenarioItem[] = [];
    for (let i = 0; i < this.categories.length; i++) {
      if (this.categories[i].id === categoryId) {
        all = this.categories[i].items;
        break;
      }
    }
    if (all.length === 0) {
      return [];
    }
    const out: ScenarioItem[] = [];
    for (let i = 0; i < count && i < all.length; i++) {
      out.push(all[(offset + i) % all.length]);
    }
    return out;
  }

  find(categoryId: string, scenarioId: string): ScenarioItem | null {
    for (let i = 0; i < this.categories.length; i++) {
      const category: ScenarioCategory = this.categories[i];
      if (category.id !== categoryId) {
        continue;
      }
      for (let j = 0; j < category.items.length; j++) {
        if (category.items[j].id === scenarioId) {
          return category.items[j];
        }
      }
    }
    return null;
  }
}

export const scenarios: Scenarios = new Scenarios();
