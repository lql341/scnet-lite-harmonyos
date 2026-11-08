/**
 * Static model catalogue of the SCNet model gateway (api.scnet.cn/api/gw/v1).
 * Curated subset of ~/.sclaw/agent/models.json (32 entries) — small enough to
 * ship in the HAP, so the app works before any network call.
 */
export interface ModelInfo {
  id: string;
  label: string;
  note: string;
}

export const MODELS: ModelInfo[] = [
  { id: 'glm-5.3-flash', label: 'GLM-5.3-Flash', note: '快速，日常对话' },
  { id: 'glm-5.3', label: 'GLM-5.3', note: '旗舰' },
  { id: 'deepseek-v4.1-flash', label: 'DeepSeek-V4.1-Flash', note: '快，支持图像' },
  { id: 'deepseek-v4-pro', label: 'DeepSeek-V4-Pro', note: '推理' },
  { id: 'kimi-k3', label: 'Kimi-K3', note: '长上下文' },
  { id: 'kimi-k2.7-code', label: 'Kimi-K2.7-Code', note: '代码' },
  { id: 'qwen3.8-max', label: 'Qwen3.8-Max', note: '旗舰' },
  { id: 'qwen3.8-flash', label: 'Qwen3.8-Flash', note: '快速' },
  { id: 'minimax-m3', label: 'MiniMax-M3', note: '长文本' },
  { id: 'claude-sonnet-5', label: 'Claude Sonnet 5', note: '通用' },
  { id: 'gpt-5.6-terra-lite', label: 'GPT-5.6 Terra Lite', note: '通用' }
];

export function modelLabel(id: string): string {
  for (const m of MODELS) {
    if (m.id === id) {
      return m.label;
    }
  }
  return id;
}
