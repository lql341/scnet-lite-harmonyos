/**
 * AIHub 社区市场（连接器 MCP / 技能 Skills）。
 *
 * 契约（2026-11-09 实测，与桌面端 4.1.1 的 `dist-electron/main` 一致）：
 *   POST /acx/search/dolphin/mcp/full-text
 *        {"query":{keyWords,pageSize,pageNum},"sort":{"<字段>":"desc"}}
 *   POST /acx/search/dolphin/skills/full-text      同上
 *   → data{ total, pages, records[{ id,nameCn,nameEn,desc,avatarUrl/createUser,
 *                                   browseCount,downloadCount,favoriteCount,
 *                                   updateTime,tags[] }] }
 *
 * 实测要点（别再试错）：
 * - `sort` 必须是**对象/Map**（`{"browseCount":"desc"}`）；传数组会 400
 *   （`Cannot deserialize value of type LinkedHashMap`）。
 * - 字段名是**驼峰**：`updateTime` / `browseCount` / `downloadCount`；snake_case 静默返回 0 条。
 * - 不带 sort 直接 400「字段sort不能为空」。
 * - `criterion` 过滤暂未生效（传 category/suggestType 结果不变），先用搜索替代。
 */
import { httpClient } from './Http';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG: string = 'SCNetLite';

export const SORT_HOT: string = 'browseCount';
export const SORT_NEW: string = 'updateTime';
export const SORT_DOWNLOAD: string = 'downloadCount';

export interface MarketItem {
  id: string;
  name: string;
  desc: string;
  iconUrl: string;
  owner: string;
  author: string;
  browseCount: number;
  downloadCount: number;
  updateTime: string;
  category: string;
  /** 打开详情用的 web 地址 */
  detailUrl: string;
}

export interface MarketResult {
  total: number;
  pages: number;
  items: MarketItem[];
}

interface TagRow {
  nameCn?: string;
  name?: string;
}

interface MarketRow {
  id?: string;
  nameCn?: string;
  nameEn?: string;
  name?: string;
  desc?: string;
  description?: string;
  avatarUrl?: string;
  imageUrl?: string;
  createUser?: string;
  authenticatedName?: string;
  browseCount?: number;
  downloadCount?: number;
  updateTime?: string;
  tags?: TagRow[];
}

interface Envelope {
  code?: string;
  msg?: string;
  data?: object;
}

interface PageData {
  total?: number;
  pages?: number;
  records?: MarketRow[];
}

class Market {
  private async search(kind: string, keywords: string, page: number, sortField: string): Promise<MarketResult> {
    const sort: Record<string, string> = {};
    sort[sortField] = 'desc';
    const query: Record<string, Object> = {
      'keyWords': keywords,
      'pageSize': 20,
      'pageNum': page
    };
    const body: Record<string, Object> = { 'query': query, 'sort': sort };
    const path: string = kind === 'skills' ? '/acx/search/dolphin/skills/full-text'
      : '/acx/search/dolphin/mcp/full-text';
    try {
      const data: object = await httpClient.postJson(path, JSON.stringify(body));
      const pageData = data as PageData;
      const rows: MarketRow[] = pageData.records ?? [];
      const items: MarketItem[] = [];
      for (let i = 0; i < rows.length; i++) {
        const row: MarketRow = rows[i];
        const name: string = row.nameCn ?? (row.name ?? (row.nameEn ?? ''));
        if (name.length === 0) {
          continue;
        }
        const owner: string = row.createUser ?? '';
        const slug: string = row.nameEn ?? name;
        const tags: TagRow[] = row.tags ?? [];
        const item: MarketItem = {
          id: row.id ?? '',
          name: name,
          desc: row.desc ?? (row.description ?? ''),
          iconUrl: row.imageUrl ?? (row.avatarUrl ?? ''),
          owner: owner,
          author: row.authenticatedName ?? owner,
          browseCount: row.browseCount ?? 0,
          downloadCount: row.downloadCount ?? 0,
          updateTime: row.updateTime ?? '',
          category: tags.length > 0 ? (tags[0].nameCn ?? '') : '',
          detailUrl: `https://www.scnet.cn/ui/aihub/${kind === 'skills' ? 'skills' : 'mcp'}/` +
            `${encodeURIComponent(owner)}/${encodeURIComponent(slug)}?id=${encodeURIComponent(row.id ?? '')}`
        };
        items.push(item);
      }
      const out: MarketResult = {
        total: pageData.total ?? 0,
        pages: pageData.pages ?? 0,
        items: items
      };
      hilog.info(0x0000, TAG, 'market %{public}s: total=%{public}d items=%{public}d',
        kind, out.total, items.length);
      return out;
    } catch (e) {
      hilog.warn(0x0000, TAG, 'market search failed: %{public}s', kind);
      const empty: MarketResult = { total: 0, pages: 0, items: [] };
      return empty;
    }
  }

  connectors(keywords: string, page: number, sortField: string): Promise<MarketResult> {
    return this.search('mcp', keywords, page, sortField);
  }

  skills(keywords: string, page: number, sortField: string): Promise<MarketResult> {
    return this.search('skills', keywords, page, sortField);
  }
}

export const market: Market = new Market();
