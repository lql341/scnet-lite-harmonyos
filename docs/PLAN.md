# PLAN — 面向手机 APK 功能对标的开发计划

对标对象：**手机 APK（Flutter `SCNet-1.1.1`）**的功能面（见 `docs/PARITY.md`）。
桌面客户端只作为"同一套协议的第二实现"用来抄接口细节（见 `docs/PROTOCOL.md`），不作为对标目标。

两者关系（已实测）：同一个后端 `www.scnet.cn/acx/*`、同一鉴权（`Token` + `Cookie` + `source` + `version`）。
差异只在壳能力：手机端有 语音/OCR/相机/深链/分享，桌面端有 openclaw/本地文件/下载器。

估算按"一个 agent 连续干"的口径，单位：天（含自测；不含你方评审等待）。

---

## P0 工程底座（0.5 天）

| 项 | 内容 |
| --- | --- |
| 结构 | `pages/` 路由化：`Login` / `Chat` / `Jobs` / `Me`；`Tabs` 容器 |
| 网络层 | `service/Http.ets`：统一注入 4 头（Token/Cookie/source=HarmonyOS/version）、`code!=="0"` 抛错、401 → 清凭据回登录 |
| 凭据存储 | `@ohos.security.huks` 或加密 preferences；不落明文 |
| 主题 | 深/浅色 + 品牌色，官方图标 + 启动页 |
| 验收 | 冷启动进 Splash → 无凭据进登录页；`hdc hilog` 无异常 |

## P1 登录与账号（2 天）

接口（已从桌面端代码确认）：
```
POST /ac/api/auth/loginDesktopClient.action          账号密码
GET  /sso/captcha.action                             图形验证码
POST /ac/api/auth/sendDesktopClientPhoneCode.action  发短信
POST /ac/api/auth/loginDesktopClientByPhoneCode.action 短信登录
POST /ac/api/auth/loginDesktopClientByToken.action   令牌登录（下次静默）
GET  /acx/user/users/current-user-info?includeToken=true&refresh=true  取用户 + 刷新 token
POST /acx/user/users/logout
```

| 功能 | 备注 |
| --- | --- |
| 首屏《用户协议》《隐私政策》同意 | 不同意 → 只读到协议为止（对齐 APK 文案） |
| 账号密码登录 + 图形验证码 | 密码规则提示：6~30 位、至少 3 类字符 |
| 手机验证码登录 / 注册 | 用户名 5~16 位，不能数字/下划线开头 |
| 登录态持久化 + 静默续期 | `accessToken` 过期自动 refresh，失败才回登录页 |
| 退出登录 | 文案「退出登录不会丢失任何数据」 |
| 验收 | 断网/错密码/验证码错/账号停用 四种错误都有可读中文；杀进程重进仍登录 |

## P2 对话核心（3 天）

| 功能 | 接口 / 要点 |
| --- | --- |
| 会话列表、新建、重命名 | `GET /acx/chatbot/conversation/list?page&size`、`POST /acx/chatbot/conversation/rename` |
| 历史加载 | `GET /acx/chatbot/v2/agent/conversation/{id}/history?page&size` |
| 流式对话 | `POST /acx/chatbot/v2/agent/stream`，SSE，`data: [done]` 结束 |
| 请求体 | `{modelId:<long>, conversationId?, origin:"user", inputs:[{type:"text",text}]}` |
| **模型下拉** | 需要「模型名 → 数字 modelId」映射（当前唯一硬缺口，见 §待解决） |
| 停止 | `POST /acx/chatbot/v2/agent/stop {conversationId, modelId}`；失败要回滚 `stopRequested` |
| 断线语义 | `interrupted` → 重连 + 拉历史；`uncertain` → 查任务列表，**禁止重发** |
| 事件处理 | `title_gen` 改标题、`conversation-status` 改状态、`data/metadata` 出提示语、`heartbeat` 忽略、`*-end` 忽略 |
| 渲染 | Markdown + 代码块高亮 + KaTeX 公式（APK 用 flutter_math_fork），流式增量不高频重排 |
| 验收 | 同一问题切模型得到不同答案；拔网线中断后能接上；停止不崩 |

## P3 富交互（2.5 天）

| 功能 | 要点 |
| --- | --- |
| 阻塞式交互 | `interaction` 记录：`{messageId, interactionId, payload, expected, state: pending/confirmed/processed}`，用户不回应后端不继续 |
| 组件渲染 | `interactive` 组件协议：按钮 / 输入 / 选择 / 确认 / 表格 / 文件 / 复选 / 日期（`componentType` 词表） |
| 资源卡 | 工具 `show_resource_cards` 产出 `resource_card`：`options[].resource/value/selected`、`optionType`(single/link)、`confirm` |
| 作业监控卡 | `job-monitor`：`jobId/clusterId/enable/terminalNotice`；`job-terminal-notice` 事件收尾 |
| 待办清单 | `todolist` 记录，含 `taskId/parentTaskId` |
| 附件 | `POST /acx/chatbot/file/upload/url` 拿预签名 → 直传 → 把引用塞进 `inputs`；`file/download/url` 下载 |
| 其它 | 点赞 `v1/chat/reaction`、相关提问 `v1/chat/related/question`、文献列表渲染、「内容由 SCNet AI 生成，仅供参考」角标 |
| 验收 | 一个需要用户确认的工具调用能走完「弹出→确认→继续输出」；上传 5 MB 文件能出现在消息里 |

## P4 技能 / 作业 / 产物（2 天）

| 功能 | 接口 |
| --- | --- |
| 任务列表 | `GET /acx/chatbot/agent/task/list`、`/agent/task/stop` |
| 作业历史 | `GET /acx/jobgather/jobs/history/page-list` |
| 集群信息 | `GET /acx/user/customer/group/user-cluster-info`、`curuser-group-names` |
| 产物 | `GET /acx/chatbot/v2/agent/conversation/{id}/output-files`；CSV 表格预览、PDF 走系统预览 |
| SLURM 脚本 | 按「N 核心 + 队列 + 区域」生成脚本（对齐 APK 的 WorkflowCar Model2 场景） |
| 验收 | 提交类操作二次确认并显示目标集群/队列/核数 |

## P5 账号 / 团队 / 计费（1.5 天）

资料（`user-base-info`）、手机/邮箱绑定（`user-telephone-email`、`verify-code*`）、团队与授权、
发票（实缴/退金额、统一社会信用代码）、账号注销（10 条须知 + 前置校验，`user-unregister-apply`）、
版本检查（`/acx/platform/config/client/check-version`）。

## P6 打磨与手机专属（1 天）

语音输入（`wss://www.scnet.cn/acx/chatbot/ws/audio/recognize`）、OCR、相机、长会话 `LazyForEach`、
深链/分享（`/share/:id`、`/mobile/:id`）、错误文案与 APK 逐条对齐。

---

## 里程碑

| 里程碑 | 内容 | 累计 |
| --- | --- | --- |
| **M1** | 能登录 + 能流式对话（P0+P1+P2 主干） | 4 天 |
| **M2** | 富交互 + 附件（P3） | 6.5 天 |
| **M3** | 作业/产物 + 账号体系（P4+P5） | 10 天 |
| **M4** | 打磨 + 手机专属能力（P6） | 11 天 |

每个里程碑都能单独装机验收，不用等全部做完。

## 待解决 / 需要你定的

1. **模型名 → 数字 modelId 映射**（P2 阻塞项）。两条路：
   - 你手动发一条消息，我 hook 主进程拿真实 body（1 分钟）
   - 或者你告诉我 `/acx/llm/api/console/model` 之外还有哪个接口给数字 id
2. **测试账号**：登录/注销/发票这些要真账号才验收。你给一个测试号，还是用你自己账号我给你开只读动作？
3. **范围确认**：P5（发票/注销）和 P6（语音/OCR/相机）是否要进第一版？砍掉能提前 2.5 天。
4. **是否允许真实提交作业**（P4 验收会产生真实计费）。
5. **商标/图标**：现在用的是 APK 提取的官方图标与 SCNet 名称，仅供调试；上架要换成你们自有的。
