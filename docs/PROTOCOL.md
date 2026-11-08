# PROTOCOL — 平台对话协议（从 Electron 桌面客户端 4.1.0 反推）

来源：`/opt/scnet-client/resources/app.asar` → `dist-electron/main/index.js`（客户端**主进程**发起网络请求，
渲染进程看不到，所以必须从代码里读）。这份是方案 B 原生化直接可用的规格。

## 1. 传输

| 项 | 值 |
| --- | --- |
| base | `https://www.scnet.cn/acx`（未以 `/acx/` 开头的 URL 会自动加前缀） |
| 鉴权头 | `Token: <token>` **和** `Cookie: <cookie>`（不是 `Authorization: Bearer`；两者都带） |
| 流式请求 | `POST /acx/chatbot/v2/agent/stream` |
| 流头 | `Content-Type: application/json`、`Accept: text/event-stream`、`timeout: 0`、`maxRedirects: 0` |
| 分隔 | 标准 SSE：`event:` / `data:`，`data` 为 JSON，**流结束哨兵是 `data: [done]`** |
| 缓冲 | 客户端按 4 MiB 上限做行缓冲，UTF-8 `StringDecoder`（跨块多字节安全） |

## 2. 发消息

v2（当前）：

```json
POST /acx/chatbot/v2/agent/stream
{
  "modelId": "SCNet-Max",
  "conversationId": "…",            // 新会话时省略
  "origin": "user",                  // 续跑任务时为 "system"
  "inputs": [{ "type": "text", "text": "用户输入" }]   // 附件/交互结果追加进 inputs
}
```

v1（兼容，用于查看老会话，**不能**提交新任务）：

```json
POST /acx/chatbot/v1/chat/completion
{ "content": "…", "autoRun": 0, "thinkingEnable": false,
  "onlineEnable": false, "createTitleByModel": true }
```

停止：

```json
POST /acx/chatbot/v2/agent/stop   { "conversationId": "…", "modelId": "…" }
```
（若会话里有未终态的 `job-monitor` 组件，客户端**再额外发一次** `/v2/agent/stop`）

## 3. SSE 事件词表（`event` 名）

| event | 处理 |
| --- | --- |
| `title_gen` | `data.title` → 回写会话标题 |
| `conversation-status` | `data.status` → 任务状态（`taskStatus`） |
| `data` / `metadata` | `data.data.status` 命中 `prepar\|wait\|init\|starting` → 阶段 = `preparing`；`data.data.description` → 提示语 |
| `heartbeat` | 忽略（保活） |
| `job-terminal-notice` | `{jobId, clusterId}` → 把对应 `job-monitor` 组件置 `enable=false, terminalNotice=true`，或补一条 |
| `*-end`（后缀） | 忽略 |
| `[done]`（data 值） | 整条流结束 |

其余带 `data.id` 的事件 = 一条消息记录，按 `type` 归类（见下）。

## 4. 记录（record）类型

`text`、`image`、`file`、`audio`、`video`、`interactive`、`subagent`、`oauth`、`error`、`end`、
`todolist`、`resource_card`、`job-monitor`、`interaction`、`group`、`page`。

关键结构：

```jsonc
// 交互（阻塞式）：用户必须回应，否则后端不继续
{ "messageId": "…", "interactionId": "…", "source": "tool",
  "payload": { … }, "expected": "<JSON 字符串>", "protocol": "v2",
  "pending": true, "state": "pending|confirmed|processed", "selectedValues": ["…"] }

// 资源卡（工具 show_resource_cards / show_resources_cards 的产物）
{ "type": "resource_card",
  "options": [{ "resource": {…}, "value": "…", "selected": false, "disabled": false }],
  "optionType": "single|link|…", "confirm": {…}, "title": "…", "description": "…",
  "enable": true }

// 作业监控
{ "type": "job-monitor", "jobId": "…", "clusterId": "…", "enable": true, "terminalNotice": false }
```

工具白名单里的名字是原始形式（下划线）：`show_resource_cards` / `show_resources_cards`。
其余记录可由 `resource` / `component` 字段再嵌套一层（v1 用 `component`，v2 用 `resource`）。

## 5. 连接状态机（必须复刻，否则体验不一致）

```
sending → streaming → (finished | stopped | error)
                    ↘ interrupted   （连接断了但会话存在 → "连接已中断，请重新连接"）
                    ↘ uncertain     （还没拿到 conversationId 就断了 → "请先查看任务列表，避免重复提交"）
```

- 断流后**不要**自动重发：`interrupted` 走「重连 + 拉历史」(`/v2/agent/conversation/{id}/history`)，
  `uncertain` 走「查任务列表」(`/chatbot/agent/task/list`)。
- 停止时先置 `stopRequested`，再 POST stop；stop 请求失败要回滚 `stopRequested`。
- 会话模型变了（历史里的 `modelId` ≠ 当前）→ 拒绝继续，提示「当前会话模型已变化，请刷新历史后继续」。

## 6. 其它已确认端点

```
GET  /acx/chatbot/config/list                       推荐问题 + 广告位（公开）
GET  /acx/chatbot/conversation/list
POST /acx/chatbot/conversation/rename
GET  /acx/chatbot/v2/agent/conversation/{id}/history?page&size
GET  /acx/chatbot/v2/agent/conversation/{id}/output-files
POST /acx/chatbot/file/upload/url | /download/url
POST /acx/chatbot/v1/chat/reaction                  点赞
GET  /acx/chatbot/v1/chat/related/question
POST /acx/chatbot/v1/agent/permission/check
WS   wss://www.scnet.cn/acx/chatbot/ws/audio/recognize   语音输入
GET  /acx/user/users/current-user-info?includeToken=true&refresh=true
POST /ac/api/auth/loginDesktopClient[ByToken].action     桌面登录
GET  /acx/platform/config/client/check-version?os&version 版本检查
```

## 7. 实测（2026-11-08，用桌面客户端在跑的活体凭据）

抓取方式：给主进程加 `--inspect=9229`，在 main 进程里 hook `http/https.request`，
然后从渲染进程点 UI 触发请求，把真实头部导出到临时文件。**8 个必需头**：

```
Token: <JWT 235 字符>            Accept: application/json
Cookie: jsessionid=…; SKIP_SESSION_UPDATE=…; Token=<uuid>
source: Electron                 version: 4.1.0
Content-Type: application/json   User-Agent: axios/1.20.0
```

> 只带 `Token` 不带 `jsessionid` → 401「用户未登录!」。之前用 `Authorization: Bearer` 之所以对
> `/acx/chatbot/config/list` 能过，是那几个 chatbot 接口宽松，用户态接口一律要 Cookie。

已验证可用（HTTP 200）：

| 接口 | 结果 |
| --- | --- |
| `GET /acx/chatbot/conversation/list?page=1&size=30` | `records[{id,title,createTime,taskStatus,conversationType,protocolType}]` |
| `GET /acx/llm/api/console/model` | 40 个模型，字段 `modelName/displayName/maxToken/modelType{LLM,VIDEO,OCR,AUDIO,Embedding,DOC_*}/inputPrice/outputPrice/cachedPrice/modalities{input,output}/logoUrl/brand/tags` |
| `GET /acx/chatbot/config/list` | 推荐问题 + 广告位（公开） |
| `POST /acx/chatbot/v2/agent/stream` | **body 的 `modelId` 是 long（数字），不是模型名** |

stream 的错误响应直接吐出了服务端 DTO 全名，说明请求体反序列化到：

```
com.sugon.acx.chatbot.app.entity.dto.coder.VibeCodingChatDto
 error: Cannot deserialize value of type `long` from String "GLM-5.3-Flash"
```

所以还差一步：**模型名 → 数字 modelId 的映射表**。`console/model` 里没有数字 id，
候选来源：模型选择器实际调的接口（下一步继续 hook 主进程抓发送动作），或 `/acx/chatbot/agent/*` 家族。

## 8. 未解决

- 平台 `Token`/`Cookie` 的签发与刷新时机（`current-user-info?...&refresh=true` 返回的 token 才是新的）。
  桌面客户端配置里的旧 token 实测已失效（401），所以**必须自己走登录**，不能复用本地残留。
- `/sso/login` 的表单字段与验证码类型（下一步要么抓登录包，要么用 REA 的 CDP 驱动登录页）。
