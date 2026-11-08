# TODO — 待办清单（2026-11-09 00:50 更新）

状态标记：`[x]` 已完成 · `[~]` 部分完成 · `[ ]` 未开始 · `[?]` 阻塞（需要外部确认）

---

## A. 阻塞项（先解决这些，其它才有意义）

- [?] **确认手机 APK 用的是哪个账号**
  官方 App 在手机上能出字，但同一个账号从鸿蒙客户端请求：
  - `POST /acx/chatbot/v2/agent/stream` → 200 → 第二帧 `{"type":"error","errorText":"系统繁忙，请稍后再试"}`
  - `POST /api/llm/v1/chat/completions`（自动建的 key）→ `402 Insufficient Balance`
  9 种 header/body 组合（`source=Android|HarmonyOS|Electron`、`clusterId=11250`、`identify=aiagent-router`）全部一样。
  → **需要一个能正常对话的账号**，或者确认手机端登录的是不是 `luql`。

- [?] **如果账号没问题，就抓手机端真实请求**
  手机装 mitmproxy 证书 → 代理到本机 → App 里发一条 → 导出 HAR。
  拿到后比对，就能确定差异在字段还是账号侧权益。

- [x] 平台 `v2` 帧结构、SSE 事件、连接状态机（见 `docs/PROTOCOL.md`）
- [x] 登录契约（form-urlencoded `username`/`password`，错误码 `1014`）
- [x] 自动取网关 key 的完整链路（query → 需要团队 → create → Bearer 调用）

---

## B. 对话功能（P2，代码主体已在，缺"能出字"的验证）

- [x] 会话列表 / 打开历史（`conversation/list`、`v2/agent/conversation/{id}/history`）
- [x] 流式渲染骨架（`service/Chat.ets`，43 字段帧 + `[done]` 哨兵）
- [x] 停止生成（`chat.cancel()` + `v2/agent/stop` 接口未接）
- [ ] **`v2/agent/stop` 接入**（现在只是断开本地请求，服务端任务不会停）
- [ ] 断线续传：`interrupted` → 重连 + 拉历史；`uncertain` → `check-stream` / 任务列表，禁止重发
- [ ] 会话重命名（`conversation/rename`）
- [ ] 新建对话时把 `chat.conversationId` 清空（已做）并同步 UI
- [ ] Markdown 渲染（标题/列表/表格/代码块）
- [ ] KaTeX 公式
- [ ] 长会话 `LazyForEach`
- [ ] 消息里的 `reasoning` 折叠展示

## C. 富交互（P3）

- [ ] `interaction` 阻塞式组件（按钮/输入/选择/确认/表格）
- [ ] `resource_card` 资源卡
- [ ] `job-monitor` 作业监控卡 + `job-terminal-notice` 收尾
- [ ] `todolist`
- [ ] 附件上传下载（`file/upload/url`、`file/download/url`）
- [ ] 点赞（`v1/chat/reaction`）、相关提问（`v1/chat/related/question`）
- [ ] 文献列表、"内容由 SCNet AI 生成"角标（已有静态文案）

## D. 作业 / 文件 / 技能（P4）

- [ ] `agent/task/list`（需要 `scopeKey` 等参数，未测出）
- [ ] `jobgather/jobs/history/page-list` 作业历史
- [ ] 产物列表 `v2/agent/conversation/{id}/output-files` + CSV/PDF 预览
- [ ] SLURM 脚本生成模板
- [ ] 集群信息（`customer/group/user-cluster-info`）

## E. 账号 / 团队 / 计费（P5）

- [ ] 用户资料（`user-base-info`）
- [ ] 手机/邮箱绑定（`user-telephone-email`、`verify-code*`）
- [ ] 团队与资源授权
- [ ] 发票（实缴/退金额、统一社会信用代码）
- [ ] 账号注销（10 条须知 + 前置校验）
- [ ] 版本检查（`platform/config/client/check-version`）

## F. 手机专属（P6）

- [ ] 语音输入（`wss://www.scnet.cn/acx/chatbot/ws/audio/recognize`）
- [ ] OCR（`https://api.scnet.cn/api/llm/v1/ocr/recognize`，需要 `ensureOcrApiKey`）
- [ ] 相机/相册
- [ ] 深链/分享（`/share/:id`、`/mobile/:id`）

## G. UI / 体验

- [x] 输入框遮挡文字（内容区 `layoutWeight(1)` + 输入区贴底）
- [x] 抽屉会话行可点、选中态
- [x] 空状态垂直居中
- [x] 登录页卡片化 + 品牌区
- [x] 模型面板（底部弹出，列真实 33 个网关模型）
- [ ] 深色模式
- [ ] 消息时间分组
- [ ] 加载骨架屏（首屏拉数据时）

## H. 工程

- [x] `service/Http.ets` 统一 4 头 / 错误码 / 401 回调
- [x] `service/Auth.ets` 登录 + 刷新 + 历史
- [x] `service/ApiKeys.ets` 自动取 key（含团队归属）
- [x] `scripts/sign.sh` / `scripts/check-signing.sh`
- [ ] 单元测试（帧解析、SSE 分帧）
- [ ] 日志分级（现在 hilog 全量，发布前收口）
- [ ] 清理探测残留：服务端有 ~13 个 `hi` 空会话（我探测时造的，APK 无删除接口）

## I. 待补的协议细节

- [ ] `v2/agent/stop` 请求体（已知 `{conversationId, modelId}`，未验证）
- [ ] `v2/agent/resume` / `check-stream` 的入参与返回
- [ ] `agent/task/list` 必填参数
- [ ] 附件 `upload/url` 的入参（文件名/大小/类型）与 OSS 直传流程
- [ ] 会话标题如何生成（`title_gen` 事件 or 客户端截断）
