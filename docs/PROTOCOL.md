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
| 分隔 | 标准 SSE：**只有 `data:` 行，没有 `event:` 行**，`data` 为 JSON；
| 结尾 | **没有 `[done]` 哨兵**（早期文档写错了）：流以 `finish` 帧 + 连接关闭结束，见 §8.4 |
| 缓冲 | 客户端按 4 MiB 上限做行缓冲，UTF-8 `StringDecoder`（跨块多字节安全） |

## 2. 发消息

v2（当前）：

```json
POST /acx/chatbot/v2/agent/stream
{
  "modelId": 600,                    // ← 来自 recommend/list 的 aiagent-router，不是 LLM id！
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

## 3. SSE 帧类型词表（**没有 `event:` 行，看 `data.type`**）

⚠️ 早期版本误写成「SSE `event:` 名」，实测（§8.4）流里根本没有 `event:` 行，
全是 `data:` JSON，靠 `type` 字段区分：

| `type` | 处理 |
| --- | --- |
| `null`（首帧） | 只带 `conversationId`，记下来 |
| `start` | 一次运行开始（`messageId`、`agentName`） |
| `title_gen` | `title` → 回写会话标题 |
| `todolist` | 服务端待办步骤（`resource.steps`），可选渲染 |
| `tool-input-start/delta/available` | 工具调用（**`inputTextDelta` 不是正文**） |
| `tool-output-available` | 工具结果 |
| `tool-exec-progress` | `progressText` / `progressPercent` → 状态行 |
| `heartbeat` | 忽略（保活） |
| `text-start` / `text-delta` / `text-end` | **正文**，`delta` 才是要拼接的 |
| `finish` | 本次运行结束（`finishReason: stop`），应视为流终态 |
| `history` | 服务端权威消息列表（`messages[]`），可做自校验 |
| `error` | `errorText` → 错误文案，终止 |
| `job-terminal-notice` | `{jobId, clusterId}` → `job-monitor` 组件置终态 |

基本规则：只有 `text-delta` 的 `delta` 是给用户看的字；其余 `*-delta` 一律忽略。

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

## 8. 已实测通的关键点（2026-11-08 23:4x，直连）

### 8.1 `modelId` 从哪来 —— ⚠️ 早期结论已纠正，见 §8.3

~~来自 `GET /acx/chatbot/config/list` 的 `modelList[].id`~~ —— **不对**。
`config/list.modelList[]` 是**网关 LLM 目录**（v1 `/api/llm/v1` 用）；v2 stream 要的是
`/acx/chatbot/recommend/list?enable=true` 里的 `services[identify='aiagent-router'].modelId`（= `"600"`，字符串）。
下面这段 `config/list` 记录只作为 LLM 目录参考保留：

```jsonc
data.modelList = [
  { "id": 17,  "name": "Qwen3-30B-A3B-Instruct-2507", "thinkingEnable": false, "mcpEnable": true, "onlineEnable": true },
  { "id": 410, "name": "MiniMax-M2.5",    ... },
  { "id": 120, "name": "Qwen3-235B-A22B", ... },
  { "id": 520, "name": "DeepSeek-V4-Flash","thinkingEnable": true, ... }
]
data.defaultCluster = 11250
data.defaultIdentify = "aiagent-router"
data.speechInputSecretKey = { appId, apiKey, apiSecret }     // 语音走这套
data.fileUploadEnable / relatedQuestionEnable / loginEnable / apiDocumentUrl / vibeCodingScenes[5] / scientificCategory[9]
```

匿名请求这个接口只回 `recommendQuestion + recommendAD`，**带鉴权才有 `modelList`**。

### 8.2 v2 stream 的 SSE 帧 = 扁平大对象（不是 `choices[].delta` 那套）

无 `event:` 行，只有 `data:` 行，每帧字段固定 43 个：

```jsonc
{"type": null, "time": null, "messageId": null, "id": null, "toolCallId": null,
 "toolName": null, "delta": null, "inputTextDelta": null, "input": null, "output": null,
 "finishReason": null, "errorCode": null, "errorText": null, "data": null,
 "conversationId": "2119454680135581698", "clusterId": null, "jobId": null, "taskId": null,
 "parentTaskId": null, "toolCallDescription": null, "agentName": null, "resource": null,
 "filename": null, "mimeType": null, "url": null, "path": null, "enable": null,
 "status": null, "title": null, "messages": null, "statistics": null,
 "progressText": null, "progressPercent": null, "questions": null, "retryId": null,
 "retryCount": 0, "maxRetries": 0, "executionContext": null, "description": null,
 "suggestedQuestions": null, "name": null, "pathList": null}
```

首帧就带回 `conversationId`（会话是在**流开始后**才创建的），这与「`uncertain` 状态」的设计吻合：
没拿到 conversationId 就断了 = 不知道服务端有没有创建任务。

### 8.3 ✅ 已解除（2026-11-09 12:00）：`系统繁忙` 的根因是 `modelId` 取错了目录

> ⚠️ 本节与 §8.4 描述的是 **v2 智能体通道**。本仓库已改为网关模型链路（见 §10），
> 这两节作为实测记录保留（v2 是免费通道，将来若要再启用可直接照抄）。

之前 8.3 的结论（「服务端不可用」）**是错的**。真实原因是 `modelId` 用错了来源：

| 目录 | 用途 | id 形态 | 拿去打 v2 stream |
| --- | --- | --- | --- |
| `GET /acx/chatbot/config/list` → `modelList[]` | 网关 `/api/llm/v1` 的 LLM 目录 | `17 / 120 / 410 / 520` | ❌ 秒回 `{"type":"error","errorText":"系统繁忙，请稍后再试"}` |
| `GET /acx/chatbot/recommend/list?enable=true` → 服务项 | **v2 智能体服务** | `aiagent-router` → `modelId: "600"` | ✅ 正常出字 |

v2 的 `modelId` 是**服务 id**（`aiagent-router` = 智能体路由器），不是 LLM id；
Qwen/DeepSeek 的选择在**服务端由 subagent 路由完成**（`toolName: resolve_subtask_agents`），
客户端根本选不了。桌面端 main 包里的判据写死得很清楚：

```js
if ("v2"===e.protocol && ("aiagent-router"!==e.service || a.modelId!==e.modelId))
  throw Error("此服务暂不可用，请稍后重试。")   // a = recommend/list.services.find(identify===e.service)
```

另一条经验：**`Cookie` 头（`jsessionid` + `Token=<uuid>`）对 stream 是必需的**。
只带 `Token` 打 stream → `500`，空 body，但会下发 `Set-Cookie: SKIP_SESSION_UPDATE=…`（说明已进到应用层）。
补上 cookie 立刻 200。cookie 可以这样现取：

```bash
POST /ac/api/auth/loginDesktopClientByToken.action   form: desktopToken=<accessToken>
  → 200 Set-Cookie: jsessionid=…; Token=<uuid>
```

（参数名是 `desktopToken`，不是 `token`/`accessToken`；差一个就回 `1003 params not enough`。）

### 8.4 实测帧词表（2026-11-09，`data:` 行全量统计）

**没有 `data: [done]` 哨兵**，也没有 `event:` 行；流靠 `finish` 帧 + 连接关闭结束。
真实出现的 `type`：

```
null(首帧，只带 conversationId) · start · todolist · title_gen ·
tool-input-start · tool-input-delta · tool-input-available · tool-output-available ·
tool-exec-progress · heartbeat · text-start · text-delta · text-end · finish · history
```

- **正文只认 `text-delta` 的 `delta`**；`tool-input-delta` 走的是 `inputTextDelta`
  （工具入参 JSON 分片，一次对话能有 72 片），当成正文渲染会把 spew 吐进气泡。
- `title_gen.title` = 会话标题；`tool-exec-progress.progressText` = 「正在处理…」；
- `history.messages[]` 是**服务端权威结果**（`role/type/text/reasoning/resource`），
  可作为「流式拼接是否漏字」的自校验基准；
- 同一条流里可能有多个 `agentName`（`SCNet`/`AI助理`），靠 `messageId` + `executionContext.role`
  （`supervisor`/`subagent`）区分。

已验证：20 个 `text-delta` 拼接结果与 `history` 里 `type==='text'` 的 `text` **逐字相等**；
带 `conversationId` 续聊同样正常（第 2 轮）。

## 9. 未解决

- 平台 `Token`/`Cookie` 的签发与刷新时机（`current-user-info?...&refresh=true` 返回的 token 才是新的）。
- 图形验证码：字段已确认（见 §10.2），但输入 UI 未做。

## 10. 账户 / 模型服务授权 / 网关（对齐隔壁 `../scnet-cli`）

> 来源：`scnet-cli` 的 `packages/scnet-agent/src/core/auth.mjs` + 其 `docs/auth.md`（逆向桌面客户端），
> 并在本机用真实账号复验过下面标「实测」的行为。

### 10.1 完整链路

```
GET  /ac/api/auth/isNeedCpatcha.action                      → data:false 表示不需要验证码
GET  /ac/api/auth/getClientCaptcha.action                   → {data:"data:image/jpeg;base64,…", captchaKey}
POST /ac/api/auth/loginDesktopClient.action                 form: username/password/[captcha/captchaKey] → cookie 会话
GET  /acx/user/users/current-user-info?includeToken=true&refresh=true → id(=accountId) / accessToken
GET  /acx/llm/account/config/status?accountId=…              → modelServiceEnabled / unpaidStatus
POST /acx/llm/account/config/authorize?accountId=…           → 开通平台模型服务（客户端登录后自动做）
POST /acx/llm/api-key/createActivityApiKey  {}               → 一把 sk- key + baseUrl + 默认模型
POST /acx/llm/api-key/query  {createUser,accountId,groupId,serviceType,page,size}
GET  /acx/llm/api-key/detail?id=…                            → 明文 key（列表里是打码的）
POST /ac/api/auth/logoutDesktopClient.action                 → 登出
```

### 10.2 实测字段值与坑（本机，2026-11-09 12:1x）

| 项 | 实测值 / 行为 |
| --- | --- |
| 登录字段名 | **`username` / `password` / `captcha` / `captchaKey`（全小写）** |
| 缺验证码时 | `1014 user not exits or password is not correct`（会被误判成密码错） |
| 验证码错 | `1006 code is invalid or error`（换一张重试） |
| `api-key/query` | **只支持 POST**，GET → `{"code":"405","msg":"Request method 'GET' not supported"}` |
| `createActivityApiKey` | 返回 `{apiKey:"sk-…", baseUrl:"https://api.scnet.cn/api/llm/v1", anthropicBaseUrl:"…/anthropic", model:"MiniMax-M2.5"}`，key 43 字符 |
| 网关 base | **`/api/llm/v1`**（不是 `/api/gw/v1`）；`/api/llm/v1/models` 对该 key 返 33 个模型 |
| 身份维度 | `cluster-user-detail` 里的 `accountId`（如 `427416191724683264`）是**集群账号**，与 `userInfo.id`（`11224910962`）不同；建团队 key 用前者 + `groupId` + `userId` |
| key 命名约定 | 客户端建的叫 `scnet-client-member-<createUser>`，`keyStatus: "100"` |

### 10.2.1 实测：`authorize` 必须用**集群** accountId

| accountId | 来源 | `POST llm/account/config/authorize` |
| --- | --- | --- |
| `427416191724683264` | `cluster-user-detail[].accountId` | ✅ `{"code":"0","msg":"success"}`，`modelServiceEnabled` 0→1 |
| `11224910962` | `current-user-info.id` | ❌ `{"code":"API010006","msg":"无权限访问"}` |

`cluster-user-detail` 按集群返回多行（本账号 13 行，一台集群一行），
但 `accountId` / `groupId` / `userId` 三者在所有 active 行里相同，取第一行即可。
`groupId=99450319708108649`，`userId=11224910962`（= 用户 id，`createUser` 用它）。

### 10.2.2 实测：33 个模型里只有 `SCNet-Max` 免费

同一把 key、同一个 base，按模型分：

| model | 结果 |
| --- | --- |
| `SCNet-Max`（平台自营，别名 `gpt-5.6-luna`） | ✅ 200，正常流式出字 |
| `MiniMax-M2.5` | ❌ 402 |
| `GLM-5.3-Flash` / `DeepSeek-V4.1-Flash-1017` / 其余 30 个 | ❌ 402 |

`createActivityApiKey` 回带的 `model: "MiniMax-M2.5"` 只是**活动推荐模型**，
不代表免费 —— 拿它当默认值会直接 402（踩过）。默认必须是 `SCNet-Max`。

### 10.3 `402 Insufficient Balance` 的诊断顺序

**402 与 API key 无关，先看账号状态**：

```bash
scripts/probe-v2.sh account     # modelServiceEnabled / unpaidStatus
scripts/probe-v2.sh gateway     # 拿 activity key → /models → 试一次 chat
```

本机实测（账号 `luql`，2026-11-09 12:2x）：

| 步骤 | 结果 |
| --- | --- |
| `authorize`（集群 accountId） | ✅ `modelServiceEnabled: 0 → 1` |
| `createActivityApiKey` | ✅ `sk-…`（43 字符）、`baseUrl=https://api.scnet.cn/api/llm/v1`、`model=MiniMax-M2.5` |
| `GET {baseUrl}/models` | ✅ 33 个（含 `SCNet-Max`） |
| `POST .../chat/completions` model=`SCNet-Max` | ✅ 200 流式出字 |
| 同上 model=`MiniMax-M2.5` / `GLM-5.3-Flash` / … | ❌ 402 |

→ 402 **不是账号级封锁**，是"这个模型要钱"。`unpaidStatus: 1` 只影响付费模型；
`SCNet-Max` 是平台自营、走平台算力，无余额也能用。

⚠️ 两条 base 不是一套 key 空间：同一把 `sk-` 打 `/api/gw/v1` 会
`401 token_not_found_in_db`（LiteLLM 的 key 表里没有它），只有 `/api/llm/v1` 认。

### 10.4 两条对话通道的分工（本仓库只用网关）

| 通道 | 依赖 | 本账号现状 | 本仓库 |
| --- | --- | --- | --- |
| 网关 `{baseUrl}/chat/completions` | `sk-` key（+ 付费模型需余额） | ✅ `SCNet-Max` 可用 | ✅ **唯一实现**（与官方客户端 / scnet-cli 一致） |
| v2 智能体 `POST /acx/chatbot/v2/agent/stream` | 登录 cookie + `modelId=600` | ✅ 免费可用 | ❌ 已移除（代码在 `b60d149`） |

两条通道**不是一套模型目录**：v2 是服务 id（600），网关是 LLM id（`GLM-5.3` / `MiniMax-M2.5` …）。
§8.3/§8.4 保留的是 v2 的实测结论，作为历史知识（免费通道，将来若要再启用可直接照抄）。


---

## 10. 登录与取 key 的完整链路（2026-11-09 真机验证）

### 10.1 登录（`/ac/api/auth/loginDesktopClient.action`）

**只接受 form-urlencoded，字段名小写**（JSON 会报 `1003 params not enough: [username] is null`）：

```
POST https://www.scnet.cn/ac/api/auth/loginDesktopClient.action
Content-Type: application/x-www-form-urlencoded
source: HarmonyOS      version: 1.0.0

username=luql&password=xxxx
```

| 返回 | 含义 |
| --- | --- |
| `{"code":"1003"}` | 参数缺失（编码/字段名错） |
| `{"code":"1014","msg":"user not exits or password is not correct"}` | 账号或密码错 |
| `{"code":"0"}` + `Set-Cookie: jsessionid=…; Token=<uuid>` | 成功 |

登录成功后要同时保存 **cookie（jsessionid + Token=uuid）** 和 **Token 头（235 字符 JWT，
来自后续 `current-user-info?includeToken=true&refresh=true`）**，两者缺一个平台接口就 401。

### 10.2 取网关 key（三步，全是 POST）

```
POST /acx/llm/api-key/query     body: {}
  → data 是"再编码一次的 JSON 字符串"：{"total":4,"pages":1,"records":["{\"id\":…}"]}
  → records 每一项也是字符串，要 parse 两次
  → records[].apiKey 是打码的（sk-N****MTM=），不能直接用
  → 但能拿到 records[].accountId(18位) 和 records[].teamName

POST /acx/llm/api-key/create    body: {"apiKeyName":"…","accountId":"…","teamName":"…"}
  缺 team → {"code":"API010010","msg":"创建ApiKey必须选择归属团队"}
  成功   → {"code":"0","data":{"id":"…","apiKey":"sk-…（43 字符，只此一次）"}}

GET  https://api.scnet.cn/api/llm/v1/models   Authorization: Bearer <apiKey>
  → 200，33 个模型（用户可见的那份：Qwen3.5-122B-A10B / MiMo-V2.5-Pro / SCNet-Max / GLM-5.2-Base …）
```

### 10.3 三套模型目录，别混

| 来源 | 数量 | 用途 | 用户可见 |
| --- | --- | --- | --- |
| `/api/llm/v1/models` | 33 | 手机端实际展示/使用 | ✅ |
| `/acx/chatbot/config/list` → `modelList[]` | 4（id 17/410/120/520） | v2 agent 的 `modelId` | ❌（用户看不到，别放进 UI） |
| `/acx/llm/api/console/model` | 40 | 控制台计费目录 | 控制台可见 |

### 10.4 两条对话通道的真实状态（同一账号、真机）

| 通道 | 结果 |
| --- | --- |
| `www.scnet.cn/acx/chatbot/v2/agent/stream` | 200，首帧给 `conversationId`，第二帧 `系统繁忙，请稍后再试`（9 种 header/body 组合均如此） |
| `api.scnet.cn/api/llm/v1/chat/completions` + 自动 key | `402 Insufficient Balance` |
| `api.scnet.cn/api/gw/v1/chat/completions` + 同一 key | `401 Invalid proxy server token` |

结论：协议/鉴权/模型目录都已对齐，剩下是**账号侧权益或后端可用性**问题，需要用手机端 APK 的请求做最后比对（见 `docs/TODO.md` A 段）。

### 10.5 已踩的 ArkTS 坑（补）

- **平台字段常是 `null` 而不是 `undefined`**：`item.taskStatus.length` 会抛
  `Cannot read property length of null`，整个 `@Component` 的 update 失败并**直接退出进程**
  （真机表现：点抽屉就闪退）。所有可能为空的字段统一走 `safe()` 收口。
- `JSON.stringify(new Map())` 得到 `{}`，用 Map 拼日志会误导自己。
- `Record<string, string>` 字面量会触发 `arkts-no-untyped-obj-literals`，请求头一律显式声明接口。

### 10.6 短信验证码登录（实测契约）

```
POST /ac/api/auth/sendDesktopClientPhoneCode.action
Content-Type: application/x-www-form-urlencoded
phoneNum=139xxxxxxxx

  200 {"code":"1016","msg":"sending message code failed"}        发送失败（频控/通道）
  200 {"code":"1022","msg":"phone number does not exist"}        号码未注册
  200 {"code":"0"} + Set-Cookie                                  发送成功

POST /ac/api/auth/loginDesktopClientByPhoneCode.action
phoneNum=139xxxxxxxx&messageCode=123456

  200 {"code":"1006","msg":"code is invalid or error"}           验证码错/过期
  200 {"code":"0"} + Set-Cookie                                  登录成功
```

⚠️ **`/acx/user/users/verify-code-send` / `verify-code-check` 不是登录用的**（未登录直接 401
`用户未登录!`），它们属于"已登录用户绑定/换绑手机"。这一条踩过，别再混。
