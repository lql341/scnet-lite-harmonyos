/**
 * 平台侧 DTO。ArkTS 不允许"无类型的对象字面量"，所以每个响应体都显式声明接口。
 * 证据来源：APK 内字符串 + docs/PROTOCOL.md；未验证字段一律 optional。
 */

/** 平台统一信封：{ code: "0", msg: "success", data: … }，code 是字符串。 */
export interface ApiEnvelope {
  code?: string;
  msg?: string;
  data?: object;
}

export interface UserInfo {
  id?: string;
  userName?: string;
  fullName?: string;
  mobilephoneNum?: string;
  email?: string;
  userLabel?: string;
  isLeader?: boolean;
  acctRole?: string;
}

/** /acx/chatbot/config/list 的模型项：id 是数字，正好是 v2 stream 的 modelId。 */
export interface ModelItem {
  id?: number;
  name?: string;
  logo?: string;
  description?: string;
  thinkingEnable?: boolean;
  onlineEnable?: boolean;
  mcpEnable?: boolean;
}

/**
 * /acx/chatbot/recommend/list?enable=true 的服务项。
 * ⚠️ v2 stream 的 `modelId` 取自这里（`identify === 'aiagent-router'` → `modelId: "600"`），
 * **不是** `config/list.modelList[].id`。用 modelList 的 id（17/120/410/520）会立刻返回
 * 一帧 `{"type":"error","errorText":"系统繁忙，请稍后再试"}`。
 * 注意 `modelId` 是字符串。证据：2026-11-09 直连实测 + 桌面端 main 包 `th()`/`eA()`。
 */
export interface AgentService {
  identify?: string;
  aiAssistantName?: string;
  modelId?: string;
  description?: string;
}

export interface ChatConfig {
  recommendQuestion?: string[];
  modelList?: ModelItem[];
  defaultCluster?: number;
  defaultIdentify?: string;
  fileUploadEnable?: boolean;
  speechInputEnable?: boolean;
  loginEnable?: boolean;
}

export interface Conversation {
  id?: string;
  title?: string;
  createTime?: string;
  taskStatus?: string;
  conversationType?: string;
  protocolType?: string;
}

export interface ConversationPage {
  records?: Conversation[];
  end?: number;
}

/** 历史消息（v2 agent conversation history）。 */
export interface HistoryMessage {
  role?: string;
  type?: string;
  text?: string;
  reasoning?: string;
  time?: string;
  messageId?: string;
  inputs?: HistoryInput[];
}

export interface HistoryInput {
  type?: string;
  text?: string;
}

export interface HistoryPage {
  conversationId?: string;
  taskStatus?: string;
  messages?: HistoryMessage[];
}

/** v2 流式帧（43 字段的扁平结构，只声明会用到的）。 */
export interface StreamFrame {
  type?: string;
  delta?: string;
  inputTextDelta?: string;
  finishReason?: string;
  errorCode?: string;
  errorText?: string;
  conversationId?: string;
  clusterId?: string;
  jobId?: string;
  taskId?: string;
  parentTaskId?: string;
  agentName?: string;
  status?: string;
  title?: string;
  progressText?: string;
  progressPercent?: number;
  description?: string;
  toolCallId?: string;
  toolName?: string;
  path?: string;
  url?: string;
  mimeType?: string;
  name?: string;
}
