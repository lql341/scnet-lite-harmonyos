/**
 * AIHub（AI 社区）智能体市场。
 *
 * 这是平台真正的「领域智能体」入口，与 chatbot 里的 aiagent-* 服务不是一回事：
 * - chatbot 的 aiagent-* 是平台内置服务，v2 只接受 aiagent-router（见 docs/ROADMAP.md P1）
 * - AIHub 的智能体是**独立应用**，`sourceType` 分三种：
 *     link  外链应用
 *     host  三方托管（iframe）
 *     build 平台内构建
 *   它们没有可供原生调用的对话接口，正确形态是内嵌 Web 打开其页面。
 *
 * 接口：POST /acx/aihub/selected/agent/list（GET → 405）
 */
import { httpClient } from './Http';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG: string = 'SCNetLite';

export interface AiAgent {
  agentId?: string;
  nameCn?: string;
  nameEn?: string;
  desc?: string;
  avatarUrl?: string;
  coverImageUrl?: string;
  logoUrl?: string;
  sourceType?: string;
  createUser?: string;
  recIndex?: number;
}

/** 智能体页面的 web 路由（实测 200）。 */
export function agentWebUrl(agent: AiAgent): string {
  const user: string = agent.createUser ?? '';
  const name: string = agent.nameEn ?? '';
  return `https://www.scnet.cn/ui/aihub/agent/${encodeURIComponent(user)}/${encodeURIComponent(name)}`;
}

/** sourceType → 展示标签。 */
export function sourceLabel(sourceType: string): string {
  if (sourceType === 'link') {
    return '外链';
  }
  if (sourceType === 'host') {
    return '三方托管';
  }
  if (sourceType === 'build') {
    return '平台构建';
  }
  return sourceType;
}

class AiHub {
  async selectedAgents(): Promise<AiAgent[]> {
    try {
      const data = await httpClient.postJson('/acx/aihub/selected/agent/list', '{}');
      const list: AiAgent[] = data as AiAgent[];
      hilog.info(0x0000, TAG, 'aihub agents: %{public}d', Array.isArray(list) ? list.length : 0);
      return Array.isArray(list) ? list : [];
    } catch (e) {
      hilog.warn(0x0000, TAG, 'aihub agent list failed');
      return [];
    }
  }
}

export const aiHub: AiHub = new AiHub();
