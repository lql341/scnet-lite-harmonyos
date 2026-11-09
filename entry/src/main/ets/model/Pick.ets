/**
 * 选择器的统一条目：智能体服务（平台）与 LLM（网关）放在同一张表里，用 kind 区分。
 * 这样模型面板只需要渲染一种数据结构，分组只影响视觉。
 */

/** 平台服务（`/acx/chatbot/recommend/list?enable=true` 的一项）。 */
export interface AgentService {
  identify?: string;
  aiAssistantName?: string;
  modelId?: string;
  description?: string;
}

export const KIND_AGENT: string = 'agent';
export const KIND_LLM: string = 'llm';

export interface PickItem {
  kind: string;
  /** agent: identify；llm: 网关模型 id */
  key: string;
  label: string;
  sub: string;
  /** agent 的平台 modelId（llm 为 0） */
  modelId: number;
  free: boolean;
}

/** 平台自营、不扣余额的 LLM（详见 docs/PROTOCOL.md §5）。 */
export const FREE_LLM: string = 'SCNet-Max';

/**
 * v2 stream **只接受 `aiagent-router`** 的 modelId。
 *
 * 实测（2026-11-09，全部 200 但立刻回 error 帧）：
 *   600 aiagent-router      → ✅ 正常流式
 *   103 aiagent-industry    → ❌ 系统繁忙，请稍后再试
 *   104 aiagent-general     → ❌ 同上
 *   107 researchaisearch    → ❌ 同上
 *   109 interpretation      → ❌ 同上
 *   300/105/106（有白名单要求的）→ ❌ 同上
 * 桌面端 main 包里也是这么写的：
 *   `if ("v2"===protocol && ("aiagent-router"!==service || a.modelId!==modelId)) throw 此服务暂不可用`
 *
 * 所以「领域智能体」不是独立通道，而是 router 在服务端把任务路由给子智能体
 * （响应里能看到 toolName: resolve_subtask_agents、agentName: AI助理 的 subagent 帧）。
 * 用户只需要选「智能体服务」，然后在对话里说清楚要做什么。
 */
export const ROUTER_IDENTIFY: string = 'aiagent-router';

/** 服务表 → 选择项：只保留可用的 aiagent-router（其余是假选项，点了只会报错）。 */
export function agentItems(services: AgentService[]): PickItem[] {
  const out: PickItem[] = [];
  for (let i = 0; i < services.length; i++) {
    const service: AgentService = services[i];
    const identify: string = service.identify ?? '';
    const modelId: number = parseInt(service.modelId ?? '', 10);
    if (identify !== ROUTER_IDENTIFY || !Number.isFinite(modelId) || modelId <= 0) {
      continue;
    }
    const item: PickItem = {
      kind: KIND_AGENT,
      key: identify,
      label: service.aiAssistantName ?? '智能体服务',
      sub: '平台运行时 · 领域任务由服务端路由',
      modelId: modelId,
      free: true
    };
    out.push(item);
  }
  return out;
}

/** 把网关模型 id 列表转成选择项。 */
export function llmItems(models: string[], pretty: (name: string) => string): PickItem[] {
  const out: PickItem[] = [];
  for (let i = 0; i < models.length; i++) {
    const id: string = models[i];
    const item: PickItem = {
      kind: KIND_LLM,
      key: id,
      label: pretty(id),
      sub: id,
      modelId: 0,
      free: id === FREE_LLM
    };
    out.push(item);
  }
  return out;
}
