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

### P3 作业面（HPC OpenAPI）— 🟡 代码完成，待正确凭据下验数据

已实现（`service/Hpc.ets` + `pages/Jobs.ets`，抽屉「作业」入口）：

```
POST api.scnet.cn/api/user/v3/tokens
     headers: user / accessKey / timestamp / signature
     signature = hex(HMAC-SHA256(secretKey, '{"accessKey":…,"timestamp":…,"user":…}'))
     → data[{clusterId, clusterName, token}]
GET  www.scnet.cn/ac/openapi/v2/center          → hpcUrls / efileUrls / clusterUserInfo
GET  {hpc}/hpc/openapi/v2/cluster               → 调度器（SLURM id = strJobManagerID） 实测
GET  …/queuenames/users/{user}?strJobManagerID= → 队列 + 空闲核数                      实测
GET  …/userquotas/userlimit?strJobManagerID=    → 配额上限                             实测
GET  …/jobs?strClusterIDList=&start=&limit=     → 运行中作业（平台偶发 10001 internal_error）
```

⚠️ **踩坑：cryptoFramework 的 `createMac('SHA256')` 不可用**
同一 key/message，它算出的摘要与标准 HMAC-SHA256 不一致（用 Python `hmac` 对比），
平台因此报「AK/SK签名校验失败」。改为用 `createMd('SHA256')` 按 RFC 2104 自己拼
ipad/opad，并在启动时用已知向量自检：`sha('abc')` 与
`HMAC('key','The quick brown fox jumps over the lazy dog')`，真机日志
`crypto selfcheck sha=true hmac=true`。

AK/SK 录入：一次粘贴 `AccessKey:SecretKey`（自动按 `:`/`,`/空白/64 位连写拆分），
并校验 32 位十六进制，避免重复输入导致签名失败。

进度：
- [x] 正确 AK/SK 下的实际数据拉取（真机：14 集群 / 6 队列 / 4 作业）
- [x] 提交表单 + 校验 + 等价 sbatch 预览 + 二次确认（`pages/JobSubmit.ets`）
      **默认 dry-run**：只把请求体打到 hilog；页面上的红色开关打开后才会真实提交
- [x] 提交体构造 `hpc.buildSubmitBody()`：`{strJobManagerID, mapAppJobInfo{GAP_*}}`，
      `GAP_NPROC = cpus × nodes`（总核），`GAP_NGPU/NDCU` 是每节点
- [x] 文件/日志浏览 `pages/Files.ets` + `service/Hpc.ets:listDir/readFile`
- [ ] 提交取消 `DELETE /openapi/v2/jobs`（`strJobInfoMap=<scheduler>,<user>:<jobId>:`）
- [ ] 作业详情（`/openapi/v2/jobs/{id}`）与产物下载（efile `file/download`）

文件浏览契约（本机 curl 实测）：
```
GET  {efile}/efile/openapi/v2/file/list?path=<dir>
     → data.children[{path,id,label}]
     ⚠️ 根目录 `/` 返回 911030 无权限，必须从 clusterUserInfo.homePath 起浏览
     ⚠️ 返回里**没有** isDirectory 标记，只能「先按目录试，失败再当文件读」
POST {hpc}/hpc/openapi/v2/file/content   (form)
     hostName= & dirPath=<file> & triggerNum=1 & rollDirection=UP|DOWN
     → data.data = 文本内容，data.allLineTotal = 总行数

原始计划（保留背景）：
- `POST /api/user/v3/tokens`：`signature = HMAC-SHA256(secretKey, JSON.stringify({accessKey,timestamp,user}))`
- `GET /ac/openapi/v2/center` → 各区域 `hpcUrls` / `efileUrls`（token TTL 4h）
- `POST {hpc}/hpc/openapi/v2/apptemplates/BASIC/BASE/job`（`GAP_NPROC` 是总核数）
- `DELETE /openapi/v2/jobs`（`strJobInfoMap=<scheduler>,<user>:<jobId>:`）
- UI：底部 Tab「作业」= 列表 / 详情 / 日志；提交前二次确认显示队列与资源
- 验收：提交一个 `sleep 5` 作业 → 看状态流转 → 收日志

### P4 插件市场 — ✅ 已接（2026-11-09）

接口（桌面端 4.1.1 的 `dist-electron/main` 里挖到，本机实测通）：

```
POST /acx/search/dolphin/mcp/full-text      ← 连接器（MCP）
POST /acx/search/dolphin/skills/full-text   ← 技能
  {"query": {"keyWords":"", "pageSize":20, "pageNum":1},
   "sort":  {"browseCount":"desc"}}
→ data{ total, pages, records[{id,nameCn,nameEn,desc,imageUrl,avatarUrl,
                              createUser,authenticatedName,browseCount,
                              downloadCount,updateTime,tags[]}]}
```

实测规模：**连接器 13617 个 / 技能 17792 个**。

**踩坑**：
- `sort` 必须是**对象（Map）**。传数组 `[{"field":…,"order":…}]` 直接 400：
  `Cannot deserialize value of type LinkedHashMap`。
- 字段名**驼峰**：`updateTime` / `browseCount` / `downloadCount`；写 `update_time` 会**静默返回 0 条**
  （不是报错，最容易误判成"没有数据"）。
- 不带 `sort` → 400「字段sort不能为空」。
- `criterion` 过滤（tag / suggestType）传了不生效，暂用关键词搜索替代。
- `/acx/aihub/skills/list` 存在但对 GET/POST 都回 405，不是列表接口，别在那儿耗时间。

实现：`service/Market.ets` + `pages/MarketPage.ets`
（连接器/技能 Tab、最热/最新/最多下载排序、搜索、分页加载，点卡片用内嵌 Web 打开 AIHub 详情），
抽屉「插件」入口。

### 首页 7 个分类的真正来源 — ✅ 已定位并同步（2026-11-09）

**不是**服务端 config，而是桌面客户端的**本地场景目录**：
渲染进程通过 host op `home-scenarios.read`（主进程 `iW()`）读取
`userData/home-scenarios/catalog.json` + `assets/`，2026-11-08 版为 7 类 32 项：

```
literature 文献阅读(3) · materials 材料科学(3) · simulation 工业仿真(3) ·
bioinformatics 生物信息(3) · writing 学术写作(3) · platform-assistant 平台助手(4) ·
office 办公创作(13)
```

定位方法（可复用）：Electron 客户端带 `--remote-debugging-port=9222` 启动 →
CDP 连 renderer → `window.host.invoke('home-scenarios.read')` 直接返回目录 JSON。
（`window.host.invoke` 不接受第二参数，传 `{}` 会报 `payload is not allowed`。）

已同步：`rawfile/scenarios.json` 换成这 7 类 32 项（21 KB），首页按其展示；
服务端 `vibeCodingScenes` 那套降级为兜底。

### 首页分类（旧方案，保留作兜底）

桌面端 4.1.1 `dist-electron/main` 的 `tp()` 是这么算 tab 的：

```
并发取 /config/list + /v1/agent/permission/check + /recommend/list?enable=true
scenes = config.vibeCodingScenes  （滤掉 value === "featured"）
qs     = recommend[identify === "aiagent-router"].question
         .filter(q => q.enable === true && (!q.route || q.route === "aiAssistant"))
tabs   = [{id:"featured", questions: 全部 qs}] +
         scenes.map(s => ({id: s.value, title: s.label,
                           questions: qs.filter(q => q.scene == null || q.scene === s.value)}))
         .filter(t => t.questions.length > 0)     ← 没有问题的分类直接不显示
```

本账号实测：`vibeCodingScenes` = 材料计算/生物信息/仿真优化/办公提效/平台助手；
router 的 94 条问题里 `scene` 分布 general 83 / industry 4 / bioinformatics 4 / simulation 3；
**office 没有专属问题 → 「办公提效」按规则被过滤掉**，最终 5 个 tab。

> 桌面端截图里的 7 个 tab（含文献阅读/学术写作）说明那份 config 与我们账号不同，
> 我们的实现是数据驱动的，不硬编码 tab 名。

实现：`service/Scenes.ets`（完全照上面的算法）+ `pages/Index.ets` 空状态
（分类 chips + 3 条推荐问题 + 换一批；本地场景目录作为兜底）。

### 待办：连接器安装/接入

- 连接器**安装**（把 MCP 接入当前会话）需要 MCP 客户端 + 传输，桌面端走 host op
  `mcp.*` / `aihub/mcp/user/server/reconnect`；手机端要做的是「浏览+跳转社区」，
  真正执行 MCP 需要额外运行时（后续评估）。
- 桌面端 4.1.1 首页出现 7 个分类（文献阅读/材料科学/工业仿真/生物信息/学术写作/
  平台助手/办公创作）与「本地 | 云端」切换；我们打包的 `home-scenarios` 仍是 4 类
  （`~/.config/scnet-client/home-scenarios/catalog.json`，schemaVersion 2，2026-11-04）。
  云端分类的服务端接口尚未找到（`/acx/chatbot/scenario/list` 等多条路径均 404），
  下一步在 Web 端 `/ui/chatbot` 抓一次 Network 即可定位。

### 平台作业接口（新发现，暂不可用）

桌面端 4.1.1 新增 `/acx/jobsched/*`（走登录态，不需要 AK/SK）：
`job/history/list`、`job/history/detail`、`job/history/queue/list`、
`user/quotas/activejob/num?strJobManagerId=`、`job/file/afterN`、
`apptemplates/BASIC/VNC/job`。**本机实测全部 503 Service Unavailable**
（服务未上线/不可用），所以作业面继续用 HPC OpenAPI。

### 原 P4 计划（保留背景）
- 已确认存在的路径：`/acx/aihub/skills/…`、`/acx/aihub/mcp/user/server/reconnect`
- `POST /acx/aihub/skills/list` 与 `GET` 都返回 405 → 需要继续逆向（下一步：在 asar 里定位调用点，
  或给桌面端主进程挂 CDP 看真实请求）
- 依赖：先有 P1/P2，否则装上插件也无法执行
- UI：市场列表 / 详情 / 安装到本地 = 写 `filesDir/skills/<slug>/SKILL.md` + `.scnet-marketplace.json`

### P5 OCR — ✅ 已完成（2026-11-09）｜语音输入按需求取消

契约（与本机实测一致，**不是 JSON 接口**）：

```
POST https://api.scnet.cn/api/llm/v1/ocr/recognize
     Authorization: Bearer <sk-…>
     Content-Type: multipart/form-data
     fields: file=<图片字节>, ocrType=<大写枚举>
  → { code:"0", data:[{ traceId, originalFilename, cosPath,
                       result:[{ status, coordinate[], confidence, elements{…} }] }] }
```

**踩坑（花了最多时间的一处）**：
- `ocrType` 必须是**表单字段**。放 JSON body 会被完全忽略，报
  `Field 'ocrType' cannot be null` —— 很容易误判成"参数名不对"，我在这上面试了
  十来种 body 写法（camelCase / snake_case / 嵌套 / 带图 URL）全是同一个错。
- 查询参数 `ocr_type` 不参与校验（传什么都"通过"，但不生效）。
- 值是**大写枚举**，小写会报 `ocr_type ：{x} is not support`。

实测可用枚举（12 个）：
`GENERAL` `PRINTED_TEXT` `HANDWRITING` `ID_CARD` `BANK_CARD` `DRIVER_LICENSE`
`VEHICLE_LICENSE` `VEHICLE_VIN` `BUSINESS_LICENSE` `INVOICE` `TAXI_RECEIPT` `SOCIAL_SECURITY`

平台模型目录里 `OCR` 项带 `teamFreeQuota: 200 / teamFreeRemaining: 198`（试用额度），
`inputPrice 0.01`，属于按次计费的试用模型。

实现：
- `service/Ocr.ets`：手写 multipart 拼装（不引三方库）+ 递归展开 `elements` 取文字
- `pages/OcrPage.ets`：相册选图 / 12 种识别类型 / 结果行数 + 复制 + 发送到对话 /
  内置小图「自检」（`rawfile/ocr-selftest.png`），真机日志
  `ocr selftest ok trace=… lines=0`
- 抽屉「文字识别」入口

### P5 语音输入（已按需求取消）
- ~~语音~~：用户确认不需要（CLI 形态也不需要），跳过。
- OCR：见上，已完成。

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
