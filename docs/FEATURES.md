# FEATURES — 功能清单

> 本文件是「这个 App 到底能做什么」的权威清单。每条都标注**是否真机验证**。
> 最后更新：2026-11-10（全量回归后）。代码规模约 **10 900 行 ArkTS**（31 个文件）。

图例：✅ 真机验证过 · 🟡 已实现但只做过主机侧/部分验证 · ⛔ 平台不支持或按需求去掉

---

## 1. 账号与登录

| 功能 | 状态 | 说明 |
| --- | --- | --- |
| 账号密码登录 | ✅ | `/ac/api/auth/loginDesktopClient.action`，form-urlencoded，字段 `username/password` |
| 短信验证码登录 | ✅ | `sendDesktopClientPhoneCode` → `loginDesktopClientByPhoneCode`（`phoneNum/messageCode`） |
| 图形验证码门 | 🟡 | `isNeedCpatcha` 会先探；真要求验证码时只给提示（无输入 UI） |
| 登录态持久化 | ✅ | preferences 存 `Token` + `Cookie`；冷启动恢复（`restore: token=235 cookie=99`） |
| 登录过期友好提示 | ✅ | 判 `hadSession`：过期时登录页出黄卡「登录已过期」并带出上次账号 |
| 会话中途 401 | ✅ | 统一清凭据 → 回登录页（1.5s 去重） |
| 退出登录 | ✅ | `logoutDesktopClient.action` → 回登录页 |
| 集群身份 | ✅ | `cluster-user-detail` → 集群 accountId / groupId（13 个集群可切） |
| 用户/集群账号展示 | ✅ | 设置页显示账号、集群账号、当前集群、当前通道、调度器 |

## 2. 对话

| 功能 | 状态 | 说明 |
| --- | --- | --- |
| **两条通道** | ✅ | ① 平台智能体 `aiagent-router`（v2 SSE）② 网关 LLM（OpenAI 兼容，33 个模型） |
| 通道选择器 | ✅ | 底部面板分组：智能体服务 / 模型，带搜索 |
| 流式出字 | ✅ | 逐字渲染 + 流式光标 + 「生成中」指示 |
| 停止生成 | ✅ | 按钮变 ■；智能体通道会额外发 `v2/agent/stop` 真停服务端任务 |
| 每条消息标注来源通道 | ✅ | meta 行显示「SCNet Max · AI」/「智能体服务 · 智能体」 |
| Markdown 渲染 | ✅ | 标题/列表/引用/代码块/分隔线/表格（真表格：表头+行分隔+斑马纹） |
| 代码块 | ✅ | 深色卡 + 语言标签 + 一键复制 + 按字符换行 |
| 行内样式 | ✅ | `**粗**` `*斜*` `` `码` ``（浅灰底深字） |
| 长按消息复制 | ✅ | 原生上下文菜单（`bindContextMenu`） |
| 流式健壮性 | ✅ | 未闭合 ``` / ** 也照常渲染；跨块多字节不乱码；无换行错误体在 `dataEnd` 冲刷 |
| 错误可读化 | ✅ | 401/402 翻译成中文（「该模型需要余额…改用 SCNet-Max」） |
| 上下文裁剪 | ✅ | 24 000 字符上限，至少保留最近 6 条，被裁时明确提示 |
| AI 风险提示 | ✅ | 空状态常驻「AI 生成内容可能不准确…请自行核实」 |
| 自定义 provider | 🟡 | 7 个预设（DeepSeek/Moonshot/通义/智谱/OpenAI/SiliconFlow/Ollama）+ 手填 baseUrl/model/key |

## 3. 会话管理

| 功能 | 状态 | 说明 |
| --- | --- | --- |
| 本地多会话 | ✅ | 落 `filesDir/sessions/*.json`（不用 preferences：有长度上限） |
| 自动标题 | ✅ | 首条用户消息截断 24 字 |
| 会话重命名 | ✅ | 本地长按改名；平台历史走 `PUT conversation/rename` |
| 删除会话 | ✅ | 抽屉里 ✕ |
| 平台历史（只读） | ✅ | `conversation/list` 30 条 + `v2/agent/conversation/{id}/history` |
| 长会话性能 | ✅ | `LazyForEach`（MsgSource 实现 IDataSource，追加走 `onDataAdd`） |

## 4. 首页场景（领域智能体）

| 功能 | 状态 | 说明 |
| --- | --- | --- |
| 7 类场景目录 | ✅ | 文献阅读/材料科学/工业仿真/生物信息/学术写作/平台助手/办公创作，共 32 项 |
| 数据来源 | ✅ | 桌面客户端 `home-scenarios.read`（`window.host.invoke` 导出为 rawfile） |
| 场景卡 | ✅ | 标题 + 摘要 + 「附件 N」标记；点一下带预置 prompt 直接发 |
| 换一批 | ✅ | 轮转 |

## 5. 附件

| 功能 | 状态 | 说明 |
| --- | --- | --- |
| 上传到平台 OSS | ✅ | `file/upload/url` → 预签名 PUT → v2 `inputs[]` |
| 智能体读取附件 | ✅ | 端到端验证：智能体调 `download_oss_files` 读到 CSV 并答行数 |
| 格式范围 | ✅ | PDF/Office/文本/代码/图片/压缩包（50+ 扩展名 MIME 表） |
| 失败原因直出 | ✅ | 0 字节 / 权限 code / OSS 状态码，不只说"失败" |
| 上限保护 | ✅ | 单文件 40MB、一次最多 3 个 |

## 6. 插件市场

| 功能 | 状态 | 说明 |
| --- | --- | --- |
| 连接器（MCP） | ✅ | 全社区 13 617 条，`POST /acx/search/dolphin/mcp/full-text` |
| 技能（Skills） | ✅ | 17 792 条 |
| 精选分组 | ✅ | `suggestType=1`（必应搜索 / MATLAB / COMSOL / Blender / FreeCAD / Fetch…） |
| 排序 | ✅ | 最热 / 最新 / 最多下载 |
| 搜索 + 分页 | ✅ | |
| 详情页 | ✅ | 内嵌 Web 打开 AIHub 详情（注入登录 cookie） |

## 7. AI 社区

| 功能 | 状态 | 说明 |
| --- | --- | --- |
| 第三方智能体列表 | ✅ | `POST /acx/aihub/selected/agent/list`（6 个：文献洞察/视频生成/短剧/船舶阻力/hic-seq/音乐） |
| 打开智能体 | ✅ | 内嵌 ArkWeb + 注入 cookie，`/ui/aihub/agent/{owner}/{slug}` |

## 8. 文字识别 / 文档

| 功能 | 状态 | 说明 |
| --- | --- | --- |
| 通用文字识别 | ✅ | `POST /api/llm/v1/ocr/recognize`（multipart），12 种类型：通用/印刷/手写/身份证/银行卡/驾照/行驶证/车架号/营业执照/发票/出租车票/社保卡 |
| PDF 识别 | ✅ | 服务端先转 PNG 再识别 |
| **文档解析（DOC_MIND）** | ✅ | `POST /ocrdoc/submit`（`ocr_type=DOC_PARING`）→ 轮询 `/ocrdoc/result` → 取 OSS 结果 json 抽文本。支持 PDF/Word/Excel/PPT/图片 |
| **格式转换（DOC_CONVERSION）** | ✅ | `POST /doc/convert/task`（`PDF_TO_WORD` / `PDF_TO_EXCEL` / `PDF_TO_PPT`），结果为产物文件链接 |
| 结果操作 | ✅ | 复制 / 发送到对话（带回输入框） |
| 自检 | ✅ | 内置小图跑一次，验证 multipart 链路 |

## 9. 算力服务（作业面）

| 功能 | 状态 | 说明 |
| --- | --- | --- |
| 认证 | ✅ | AK/SK → `POST /api/user/v3/tokens`（HMAC-SHA256 手写实现，RFC 4231 向量单测） |
| 集群切换 | ✅ | 13 个区域可切（昆山/甘肃/合肥/哈尔滨/乌镇/西安…） |
| 队列与空闲核 | ✅ | 例：昆山 6 队列（kshdAI 116/992 …）；哈尔滨 3 队列 |
| 配额 | ✅ | accountMaxCpu / DCU / Job 数 |
| 运行中作业 | ✅ | 状态中文化（运行中/排队中/已完成/异常退出/超时/OOM…）+ 着色 |
| 作业详情 | ✅ | 11 项字段（提交/开始/结束时间、节点、核数、workDir、outputPath…） |
| 日志读取 | ✅ | `file/content`，深色等宽卡片 + 可复制 |
| 文件浏览 | ✅ | efile `file/list`，31 个目录逐级进入，文件内容可读 |
| **提交作业（真提交）** | ✅ | 2026-11-10 真机成功：jobId `127537835`，1 节点 1 核 2 分钟 → `statC`，日志含命令输出 |
| 取消作业 | 🟡 | `DELETE /jobs` 契约已验，UI 有二次确认弹层 |

## 10. 外观与设置

| 功能 | 状态 | 说明 |
| --- | --- | --- |
| 6 套配色 | ✅ | 暖砂（默认，Claude 风）/ SCNet 红 / 深海蓝 / 石墨 / 松绿 / 琥珀 / 紫罗兰 / 玫瑰 |
| 深色模式 | ✅ | 外观三档：跟随系统 / 浅色 / 深色（`setColorMode`，连系统件一起变） |
| 字号三档 | ✅ | 小 / 标准 / 大（含 Markdown 正文与行高） |
| 中英切换 | ✅ | 顶栏/空状态/输入区/抽屉/面板/设置页 |
| 头像 | ✅ | 默认首字 / 卡通 6 款（🐼🦊🐳🦉🐙🌵）/ 风景 4 款（日落·海面·雪山·星空）/ 字母 2 款 / 相册图片 / 「让智能体生成」入口 |
| 深色危险色 | ✅ | 错误条 / 退出登录 / 取消按钮在深色下用深红底 + 亮红字（不再是浅粉块） |
| 集群选择 | ✅ | 设置页「集群」行可点，13 个集群 |
| 检查更新 | ✅ | 显示当前版本 0.2.0 + 内嵌打开 GitHub Releases（仓库是 private，无法匿名比对） |
| 关于 | ✅ | 作者 lql341 + GitHub 主页 + 项目链接 + 非官方声明 |

## 11. 工程

| 项 | 状态 |
| --- | --- |
| 构建 `assembleHap` | ✅ 无 ERROR（约 2s 增量 / 8-13s 全量） |
| 签名 `scripts/sign.sh` | ✅ hap-sign-tool localSign |
| 签前自检 `check-signing.sh` | ✅ keystore ↔ .cer ↔ .p7b 公钥比对 |
| 单元测试 `scripts/test.sh` | ✅ 51/51（Markdown 30 / SSE 10 / 上下文裁剪 13 / HMAC 8） |
| 脱机探针 `scripts/probe.sh` | ✅ account/authorize/models/chat/raw（不需要真机） |
| 真机截图 `scripts/shot.sh` | ✅ UI 迭代用 |
| 环境自检 `scripts/dev-check.sh` | ✅ 工具链/设备/签名/文档 |
| 日志分级 | ✅ 高频 info → debug，签名明文已移除 |

---

## 已知限制 / 未做

| 项 | 原因 |
| --- | --- |
| ~~文档解析/格式转换原生调用~~ | ✅ 已接（接口来自平台模型详情页的 `codeExamples`） |
| 「检查更新」自动版本比对 | 仓库 private，`api.github.com` 匿名 404；转公开即可加（约 20 行） |
| ~~作业真提交~~ | ✅ 已验证（默认仍是 dry-run，红色开关才真提交） |
| 图形验证码输入 UI | 平台平时不要求；真要求时目前只给文案提示 |
| 连接器「安装/接入」 | 需要 MCP 运行时（`mcp.*` 传输），手机端只做浏览+跳转社区 |
| 语音输入 | 按需求取消 |
| 应用商城入口 | `/ui/mall` 未做移动适配，已从抽屉移除 |
