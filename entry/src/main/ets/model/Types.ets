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
  userId?: string;
  accountId?: string;
  userName?: string;
  fullName?: string;
  mobilephoneNum?: string;
  email?: string;
  userLabel?: string;
  isLeader?: boolean;
  acctRole?: string;
}

export interface ChatConfig {
  recommendQuestion?: string[];
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
