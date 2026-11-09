# ROADMAP — 把桌面端能力逐个搬过来

> 目标：手机端不只是"能聊天"，而是覆盖桌面客户端的 **平台助手 / 领域智能体 / 插件市场 / 作业面**。
> 本文件只写**已经验证过的接口事实**和**依赖关系**，不做无依据的排期。

## 0. 一个必须先说清的事实（决定后面怎么排）

| 能力 | 桌面端怎么实现的 | 我们能用哪条通道 |
| --- | --- | --- |
| 普通对话（选 LLM） | 网关 `{baseUrl}/chat/completions` | ✅ 已实现 |
| **平台助手 / 领域智能体** | `POST /acx/chatbot/v2/agent/stream`，`modelId` 取 `/acx/chatbot/recommend/list?enable=true` 里 `services[].modelId` | ⚠️ **只有 v2 通道**，网关没有这些 agent |
| 附件 / 图片输入 | 同上（v2 的 `inputs[]` 支持 file/image），或网关多模态 `image_url` | 两条都行 |
| 会话历史（平台侧） | `/acx/chatbot/conversation/list` + `v2/agent/conversation/{id}/history` | ✅ 已能只读浏览 |
| 作业面 | HPC OpenAPI（AK/SK） | ✅ 与 agent 无关，照 `../scnet-cli` 搬 |
| 插件市场 | `/acx/aihub/skills/*`、`/acx/aihub/mcp/user/server/*`（AIHub） | ❓ 只探到路径存在，list 接口的 method 还没对 |
| 语音 / OCR | `wss://.../ws/audio/recognize`、`/api/llm/v1/ocr/recognize` | ✅ 网关侧 |

**结论**：要"平台助手 + 领域智能体"，就必须把 v2 通道请回来。
之前删掉它是因为"从没在设备上验证通过"，而不是它不可用 —— 我们在本机用
`modelId=600` 拿到过完整流式回复。这次按**第二通道**的方式重新引入，与网关并存：
- 网关通道：选 LLM（默认 `SCNet-Max`，免费）
- 智能体通道：选服务（`aiagent-router` / `aiagent-science` / `aiagent-industry` / …）
UI 上就是模型选择器里的两个分组，不是两套页面。

## 1. 阶段划分（每阶段都能上机验收）

### P0 本地多会话 + 持久化（进行中）
- 会话落本地文件（`filesDir/sessions/*.json`），App 杀掉重进还在
- 抽屉：本地会话（可删） + 平台历史（只读）
- 验收：发两轮 → 杀进程 → 重进 → 会话还在、能续聊

### P1 智能体通道（v2 回归）— ✅ 已完成（2026-11-09）

**实测结论（先看这个，别再做假功能）**：v2 stream 只接受 `aiagent-router`（600）。
其余 9 个服务全部 200 但立刻回 `系统繁忙，请稍后再试`：

```
600 aiagent-router      ✅ 正常流式（15 个 text-delta）
103 aiagent-industry    ❌ 系统繁忙
104 aiagent-general     ❌
107 researchaisearch    ❌
109 interpretation      ❌
300/105/106（有白名单） ❌
```

桌面端 main 包里的断言也是这个：
`if ("v2"===protocol && ("aiagent-router"!==service || modelId!==service.modelId)) throw 此服务暂不可用`。

→ **领域智能体不是独立通道**，而是 router 在服务端把任务路由给子智能体
（响应里可见 `toolName: resolve_subtask_agents`、`agentName: AI助理` 的 subagent 帧）。
所以选择器里只有「智能体服务」一项，用户用自然语言说需求即可。

**进一步的否定验证（2026-11-09，避免以后再试错）**：

| 变体 | 结果 |
| --- | --- |
| `{modelId:300}` | ❌ 系统繁忙 |
| `{modelId:300, clusterId:11250}` | ❌ 系统繁忙 |
| `{modelId:300, identify:"aiagent-science"}` | ❌ 系统繁忙 |
| `{modelId:300, service:"aiagent-science"}` | ❌ 系统繁忙 |
| `POST /acx/chatbot/v1/chat/completion {content,autoRun,…}` | ⚠️ 200 且**无 error 帧**（帧结构是 v1 的 `msgFromType/msgContent`，未解析） |

也就是说：**不是"缺字段"**，是这些服务在 v2 上根本不可用。
桌面端 `eA()` 里普通发送的 body 就只是 `{modelId, origin, inputs}`（`...l` 是附件 helper、
`...s` 只在交互表单时出现），它自己都只发 router。

**要真正接上领域智能体，还缺一次"谁在调它"的证据**：

1. 手机 APK 抓包（Dart AOT 不可读，REA 也不支持）—— mitmproxy + 系统证书；
2. 或 Web 端 `https://www.scnet.cn/ui/chatbot/index.html` 打开"智能体"入口抓 Network（最省事）。

拿到那一次请求的 body 与 path，就知道是 `v2 + 某个未发现的字段`、还是另一套端点。
在此之前，聊天里选「智能体服务」并说清需求，router 会在服务端路由到对应子智能体
（响应里可见 `agentName: AI助理`、`toolName: resolve_subtask_agents`）。

已实现：
- `service/AgentChat.ets`：v2 流 + 帧按 `type` 分派 + `stop` 真停服务端任务 + `title_gen` 回写会话标题
- `model/Pick.ets`：智能体/模型统一成 `PickItem`，只保留可用的 router
- `view/ModelSheet.ets`：两组（智能体服务 / 模型）+ 搜索
- `pages/Index.ets`：`channel` 路由、每条消息记它自己走的通道（`via`）、停止时按通道分别处理

原计划（保留作为背景）：
- `GET /acx/chatbot/recommend/list?enable=true` → 服务表（identify / 名字 / modelId）
- `POST /acx/chatbot/v2/agent/stream`，帧按 `type` 分派：
  `text-delta` 才是正文；`tool-input-delta` 是 `inputTextDelta`（不要当正文）；
  `finish` 终态；`title_gen` 回写标题；`tool-exec-progress` 走进度条
- `POST /acx/chatbot/v2/agent/stop` 真正停服务端任务
- 模型选择器分两组：**LLM（网关）** / **智能体（平台服务）**
- 验收：在同一条 UI 里切到 `超级科学计算智能体`，能出字、能停、标题回填

### P1.5 领域智能体（场景模板）— ✅ 已完成（2026-11-09）

用户说的「领域智能体」= 桌面端首页那排 **科学计算 / 科研助手 / 办公与创作 / 开发** 下面的场景卡，
数据源是**本地目录** `~/.config/scnet-client/home-scenarios/catalog.json`
（schemaVersion 2，由 `home-scenarios.read/refresh` 维护，不是接口）。

每个场景带：`prompt`（预置中文指令）、`workflowIntent{executionMode, requiredCapabilities, skillName}`、
`requires.skills`、`inputs`（附件）、`artifacts`、`tier`。

实现：
- `entry/src/main/resources/rawfile/scenarios.json`（23 KB，从桌面目录裁剪：4 类 30 个场景）
- `service/Scenarios.ets`：读 rawfile、分类/取前 N/换一批/查找
- `view/ScenarioSheet.ets`：分类 Tab + 场景卡 + 「附件 N」标记
- `pages/Index.ets`：输入区加「场景」入口；空状态直接展示当前分类前 3 个 + 换一批
- 点场景 = 把预置 prompt 填进输入框并发送（与桌面端行为一致）

**已知限制**：30 个场景里 26 个带 `inputs`（如 `standard-doe.csv`）。
P2 附件上传完成后，这类场景在有附件时可直接发送；没附件时提示「点 ＋ 选择文件」。

### P2 附件上传 — ✅ 已完成（2026-11-09）

契约（本机 curl + 真机双向验证）：

```
1) POST /acx/chatbot/file/upload/url   body: [{fileId, fileName, totalSize:"0"}]
   → [{fileName, fileId, uploadUrl}]     # OSS 预签名，5 分钟有效，host: oss.ksai.scnet.cn:58003
2) PUT uploadUrl
   Content-Type: <mime>  Content-Length: <bytes>  x-amz-meta-total-size: 0
   → 200（注意：**不能**带平台 Token/Cookie 头，OSS 会拒）
3) 发消息时 inputs 追加：
   { "type": "file" | "image",           # image/ 前缀走 image
     "resource": { "name": <返回的 fileName>, "mimeType": "...", "size": <KB> } }
```

实测：智能体侧调用 `download_oss_files` 工具读取，问「附件有多少行数据」答 `33`
（与主机 curl 同一份文件、同一个答案）。

实现：
- `service/Upload.ets`：ticket → OSS PUT → `UploadedFile{name,mimeType,sizeKb}`
  （`mimeOf()` 与桌面端同一张扩展名表；`readSync` 读 picker 的 uri）
- `service/AgentChat.ets`：`stream(modelId, text, files, handlers)`，按 mime 分 file/image
- `pages/Index.ets`：＋ 接 `DocumentViewPicker`（最多 3 个）、附件 chip 可删、
  中性提示与红色错误分离；**长按 ＋** 跑一次上传自检（诊断用）

### P2.1 图片与附件（后续）
- 网关：多模态模型 `messages[].content = [{type:'text'},{type:'image_url'}]`
- 智能体：`POST /acx/chatbot/file/upload/url` 拿 OSS 直传 → `inputs[]` 追加 file
- UI：+ 号接 `photoAccessHelper` / `filePicker`，缩略图在气泡里预览
- 验收：发一张图，模型能描述内容

### P3 作业面（HPC OpenAPI，照 `../scnet-cli`）
- `POST /api/user/v3/tokens`：`signature = HMAC-SHA256(secretKey, JSON.stringify({accessKey,timestamp,user}))`
- `GET /ac/openapi/v2/center` → 各区域 `hpcUrls` / `efileUrls`（token TTL 4h）
- `POST {hpc}/hpc/openapi/v2/apptemplates/BASIC/BASE/job`（`GAP_NPROC` 是总核数）
- `DELETE /openapi/v2/jobs`（`strJobInfoMap=<scheduler>,<user>:<jobId>:`）
- UI：底部 Tab「作业」= 列表 / 详情 / 日志；提交前二次确认显示队列与资源
- 验收：提交一个 `sleep 5` 作业 → 看状态流转 → 收日志

### P4 插件市场（AIHub）
- 已确认存在的路径：`/acx/aihub/skills/…`、`/acx/aihub/mcp/user/server/reconnect`
- `POST /acx/aihub/skills/list` 与 `GET` 都返回 405 → 需要继续逆向（下一步：在 asar 里定位调用点，
  或给桌面端主进程挂 CDP 看真实请求）
- 依赖：先有 P1/P2，否则装上插件也无法执行
- UI：市场列表 / 详情 / 安装到本地 = 写 `filesDir/skills/<slug>/SKILL.md` + `.scnet-marketplace.json`

### P5 语音与 OCR
- 语音：`wss://www.scnet.cn/acx/chatbot/ws/audio/recognize`（`config/list` 的 `speechInputSecretKey`）
- OCR：`POST /api/llm/v1/ocr/recognize`（需 `ensureOcrApiKey`）

## 2. 不做的

- 桌面端的 `desktopagent/*`（Citrix / RDP / DCV / VNC 图形桌面）—— 手机上没有意义
- 本地 shell / git / browser 自动化 —— 属于桌面 agent 形态
- MCP 的 stdio 传输（手机没有子进程）

## 3. 当前代码结构（搬东西时往哪放）

```
service/Http.ets        平台 4 头 + 信封 + 401
service/Auth.ets        登录 / 集群身份 / 历史
service/ApiKeys.ets     模型服务授权 + 取网关 key
service/Gateway.ets     网关 SSE（OpenAI 兼容）
service/Sessions.ets    本地会话持久化            ← P0
common/Theme.ets        设计令牌
common/Markdown.ets     Markdown 解析
view/MarkdownView.ets   渲染
view/ModelSheet.ets     模型/服务选择
pages/Index.ets         对话页
pages/Login.ets         登录页
```
