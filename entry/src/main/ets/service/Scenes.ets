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

/** config/list 的推荐位（banner）：{logo, name, url} */
export interface AdItem {
  logo: string;
  name: string;
  url: string;
}

export interface SceneBoard {
  /** 首页 banner（平台推荐位：商城商品 / Token Plan 等） */
  ads: AdItem[];
  tabs: SceneTab[];
  /** 各服务的推荐问题（按 identify 索引），智能体通道用 */
  byService: Map<string, string[]>;
}

interface RouterRow {
  identify?: string;
  question?: SceneQuestion[];
}

class Scenes {
  private board: SceneBoard = { ads: [], tabs: [], byService: new Map<string, string[]>() };

  /** 拉 config + recommend，按桌面端算法组装。 */
  async load(): Promise<SceneBoard> {
    const tabs: SceneTab[] = [];
    const ads: AdItem[] = [];
    const byService: Map<string, string[]> = new Map<string, string[]>();
    try {
      const configData = await httpClient.getData('/acx/chatbot/config/list');
      const recommendData = await httpClient.getData('/acx/chatbot/recommend/list?enable=true&position=all');

      const config = configData as Record<string, Object>;
      const rawAds = config['recommendAD'];
      if (Array.isArray(rawAds)) {
        const rows: Record<string, Object>[] = rawAds as Record<string, Object>[];
        for (let i = 0; i < rows.length; i++) {
          const ad: AdItem = {
            logo: String(rows[i]['logo'] ?? ''),
            name: String(rows[i]['name'] ?? ''),
            url: String(rows[i]['url'] ?? '')
          };
          if (ad.name.length > 0 && ad.url.length > 0) {
            ads.push(ad);
          }
        }
      }
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

      // 标签对齐桌面客户端（config 里的 label 与客户端显示不同）
      const LABELS: Map<string, string> = new Map<string, string>();
      LABELS.set('industry', '材料科学');
      LABELS.set('bioinformatics', '生物信息');
      LABELS.set('simulation', '工业仿真');
      LABELS.set('office', '办公创作');
      LABELS.set('general', '平台助手');
      for (let i = 0; i < tabs.length; i++) {
        const mapped: string | undefined = LABELS.get(tabs[i].id);
        if (mapped !== undefined) {
          tabs[i].title = mapped;
        }
      }

      // 客户端还有两个分类（文献阅读 / 学术写作），不是 config 里的 scene，
      // 而是从推荐问题里按主题分出的静态 tab —— 这里用真实问题按关键词归组。
      const reading: string[] = [];
      const writing: string[] = [];
      for (let i = 0; i < usable.length; i++) {
        const name: string = String(usable[i].name);
        if (/文献|论文|检索|综述|arXiv|Pubmed/i.test(name)) {
          reading.push(name);
        } else if (/写作|润色|报告|摘要|投稿|论证|写作/i.test(name)) {
          writing.push(name);
        }
      }
      if (reading.length > 0) {
        const tab: SceneTab = { id: 'literature', title: '文献阅读', questions: reading };
        tabs.push(tab);
      }
      if (writing.length > 0) {
        const tab: SceneTab = { id: 'writing', title: '学术写作', questions: writing };
        tabs.push(tab);
      }

      hilog.info(0x0000, TAG, 'scenes: tabs=%{public}d services=%{public}d reading=%{public}d writing=%{public}d',
        tabs.length, byService.size, reading.length, writing.length);
    } catch (e) {
      hilog.warn(0x0000, TAG, 'scenes load failed');
    }
    const board: SceneBoard = { ads: ads, tabs: tabs, byService: byService };
    this.board = board;
    return board;
  }

  current(): SceneBoard {
    return this.board;
  }
}

export const scenes: Scenes = new Scenes();
