/**
 * 首页场景分类（对齐桌面客户端 4.1.1 的算法）。
 *
 * 桌面端 `dist-electron/main` 里的做法（`tp()`）：
 *   1. 并发取 `/config/list`、`/v1/agent/permission/check`、`/recommend/list?enable=true`
 *   2. 从 config 拿 `vibeCodingScenes`（value/label），滤掉 value==='featured'
 *   3. 从 recommend 里 identify==='aiagent-router' 的那一项拿 `question[]`，
 *      过滤 enable===true、route 为空或 'aiAssistant'、name 非空
 *   4. tabs = [{id:'featured', questions: 全部}, ...scenes.map(s => ({
 *        id: s.value, title: s.label,
 *        questions: questions.filter(q => q.scene == null || q.scene === s.value)
 *      }))].filter(t => t.questions.length)      ← 没问题就不显示这个 tab
 *
 * 实测（本账号）：`vibeCodingScenes` 5 个（材料计算/生物信息/仿真优化/办公提效/平台助手），
 * router 的 94 条问题里 scene 分布为 general 83 / industry 4 / bioinformatics 4 / simulation 3，
 * office 没有专属问题 → 按上面的 filter 规则「办公提效」不会作为 tab 出现。
 * 桌面端截图里有 7 个 tab（含文献阅读/学术写作）说明不同版本/账号的 config 不同，
 * 我们完全按 config 走，不硬编码。
 */
import { httpClient } from './Http';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG: string = 'SCNetLite';

export interface Scene {
  value: string;
  label: string;
}

export interface SceneQuestion {
  name: string;
  scene?: string;
  enable?: boolean;
  route?: string;
}

export interface SceneTab {
  id: string;
  title: string;
  questions: string[];
}

export interface SceneBoard {
  tabs: SceneTab[];
  /** 各服务的推荐问题（按 identify 索引），智能体通道用 */
  byService: Map<string, string[]>;
}

interface RouterRow {
  identify?: string;
  question?: SceneQuestion[];
}

class Scenes {
  private board: SceneBoard = { tabs: [], byService: new Map<string, string[]>() };

  /** 拉 config + recommend，按桌面端算法组装。 */
  async load(): Promise<SceneBoard> {
    const tabs: SceneTab[] = [];
    const byService: Map<string, string[]> = new Map<string, string[]>();
    try {
      const configData = await httpClient.getData('/acx/chatbot/config/list');
      const recommendData = await httpClient.getData('/acx/chatbot/recommend/list?enable=true&position=all');

      const config = configData as Record<string, Object>;
      const scenes: Scene[] = [];
      const rawScenes = config['vibeCodingScenes'];
      if (Array.isArray(rawScenes)) {
        const rows: Record<string, Object>[] = rawScenes as Record<string, Object>[];
        for (let i = 0; i < rows.length; i++) {
          const value: string = String(rows[i]['value'] ?? '');
          const label: string = String(rows[i]['label'] ?? '');
          if (value.length > 0 && label.length > 0 && value !== 'featured') {
            const scene: Scene = { value: value, label: label };
            scenes.push(scene);
          }
        }
      }

      const services: RouterRow[] = recommendData as RouterRow[];
      let routerQuestions: SceneQuestion[] = [];
      if (Array.isArray(services)) {
        for (let i = 0; i < services.length; i++) {
          const row: RouterRow = services[i];
          const identify: string = row.identify ?? '';
          const questions: SceneQuestion[] = row.question ?? [];
          // 每个服务自己的推荐问题（智能体通道切服务时用）
          const names: string[] = [];
          for (let j = 0; j < questions.length; j++) {
            const q: SceneQuestion = questions[j];
            if (q.enable === true && (q.name ?? '').trim().length > 0) {
              names.push(String(q.name));
            }
          }
          if (identify.length > 0 && names.length > 0) {
            byService.set(identify, names);
          }
          if (identify === 'aiagent-router') {
            routerQuestions = questions;
          }
        }
      }

      // router 的问题过滤（与桌面端一致）
      const usable: SceneQuestion[] = [];
      for (let i = 0; i < routerQuestions.length; i++) {
        const q: SceneQuestion = routerQuestions[i];
        const route: string = q.route ?? '';
        if (q.enable === true && (route.length === 0 || route === 'aiAssistant') &&
          String(q.name ?? '').trim().length > 0) {
          usable.push(q);
        }
      }

      // featured tab
      const featured: string[] = [];
      for (let i = 0; i < usable.length; i++) {
        featured.push(String(usable[i].name));
      }
      if (featured.length > 0) {
        const tab: SceneTab = { id: 'featured', title: '推荐', questions: featured };
        tabs.push(tab);
      }

      // scenes tabs
      for (let i = 0; i < scenes.length; i++) {
        const scene: Scene = scenes[i];
        const picked: string[] = [];
        for (let j = 0; j < usable.length; j++) {
          const q: SceneQuestion = usable[j];
          const qScene: string = q.scene ?? '';
          if (qScene.length === 0 || qScene === scene.value) {
            picked.push(String(q.name));
          }
        }
        if (picked.length > 0) {
          const tab: SceneTab = { id: scene.value, title: scene.label, questions: picked };
          tabs.push(tab);
        }
      }

      hilog.info(0x0000, TAG, 'scenes: tabs=%{public}d services=%{public}d',
        tabs.length, byService.size);
    } catch (e) {
      hilog.warn(0x0000, TAG, 'scenes load failed');
    }
    const board: SceneBoard = { tabs: tabs, byService: byService };
    this.board = board;
    return board;
  }

  current(): SceneBoard {
    return this.board;
  }
}

export const scenes: Scenes = new Scenes();
