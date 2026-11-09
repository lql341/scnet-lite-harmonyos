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

### P1 智能体通道（v2 回归，带真实帧词表）
- `GET /acx/chatbot/recommend/list?enable=true` → 服务表（identify / 名字 / modelId）
- `POST /acx/chatbot/v2/agent/stream`，帧按 `type` 分派：
  `text-delta` 才是正文；`tool-input-delta` 是 `inputTextDelta`（不要当正文）；
  `finish` 终态；`title_gen` 回写标题；`tool-exec-progress` 走进度条
- `POST /acx/chatbot/v2/agent/stop` 真正停服务端任务
- 模型选择器分两组：**LLM（网关）** / **智能体（平台服务）**
- 验收：在同一条 UI 里切到 `超级科学计算智能体`，能出字、能停、标题回填

### P2 附件与图片
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
