# TODO — 待办清单（2026-11-09 00:50 更新）

状态标记：`[x]` 已完成 · `[~]` 部分完成 · `[ ]` 未开始 · `[?]` 阻塞（需要外部确认）

---

## A. 阻塞项

- [x] **对话链路与官方客户端/scnet-cli 对齐**（2026-11-09 12:2x）
  账号登录 → `cluster-user-detail` → `account/config/status` →（必要时）`authorize`
  → `api-key/createActivityApiKey` → `{baseUrl}/models` → `{baseUrl}/chat/completions`。
  平台 v2 智能体通道已从代码移除（历史见 `b60d149`）。
- [x] **402 的真相：按模型计费，不是账号级封锁**（2026-11-09 12:25 纠正）
  33 个模型里只有 **`SCNet-Max`**（平台自营）免费；其余 32 个是上游付费模型，
  余额为 0 → `402 Insufficient Balance`。`MiniMax-M2.5` 也一样收费（它只是
  `createActivityApiKey` 回带的"活动推荐模型"字段，别当默认值用）。
  默认模型已固定 `SCNet-Max` —— 隔壁 `scnet-cli` 的 `pickDefaultModel()` 正是这个逻辑，
  所以"它不需要余额"。
- [x] `authorize` 的正确 accountId 是**集群账号**（427416191724683264），用
      `current-user-info.id` 会 `API010006 无权限访问`（踩过）。
- [x] `/api/gw/v1` 与 `/api/llm/v1` 不是一套 key 空间（前者 401 token_not_found_in_db）
- [x] 登录契约（form-urlencoded，错误码 `1014`/`1006`）、`isNeedCpatcha` 门

## A2. 已知缺陷登记

- [x] **短信验证码登录不可用**（2026-11-09 用户实测反馈）
  原因：我用错了端点。`/acx/user/users/verify-code-send|check` 是**登录后绑定手机**用的（未登录 401），
  短信登录要走 DesktopClient 那套，且字段名不同：

  ```
  POST /ac/api/auth/sendDesktopClientPhoneCode.action     form: phoneNum=<手机号>
       → 1016 发送失败（频控/通道） · 1022 手机号不存在
  POST /ac/api/auth/loginDesktopClientByPhoneCode.action  form: phoneNum=<手机号>&messageCode=<验证码>
       → 1006 验证码错误或过期
  ```

  代码已改（`service/Auth.ets`，`describeAuthError` 补了 1006/1016/1022 文案），
  **待真机复验**：用真实手机号收码 → 登录。

## B. 对话功能（P2，代码主体已在，缺"能出字"的验证——卡在 A 段的余额）

- [x] 会话列表 / 打开历史（`conversation/list`、`v2/agent/conversation/{id}/history`）
- [x] 流式渲染骨架（`service/Gateway.ets`，OpenAI 兼容 SSE）
- [x] **修了一个真 bug**：网关错误体（402/401）是**单行 JSON 且无换行**，
      行缓冲永远等不到 `\n`，`dataEnd` 里必须冲刷残留 buffer —— 否则只会显示兜底文案。
      真机已验证 402 文案正确
- [x] 模型选择面板 = 网关 `/models`（33 个，与官方客户端口径一致）
- [x] 网关错误体解析：402/401 是普通 JSON（非 SSE），已翻译成可读文案
- [x] **真机复验出字**（2026-11-09 12:4x，`SCNet-Max`；停止/402 文案/重启保持登录均已验）
- [ ] 空状态首条气泡异常（"我可以帮你做很多事…" 偶尔先出现）——待查 `emptyState()`
- [ ] 模型面板加搜索（33 个要滚 3 屏）
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

> 隔壁仓库 `../scnet-cli` 已经把这套跑通了，照它的实现抄就行
> （`packages/scnet-agent/src/core/sci/openapi.mjs` 469 行 + `flow.mjs` 411 行）：
>
> - 签名：`POST /api/user/v3/tokens`，头 `user` / `accessKey` / `signature` / `timestamp`，
>   `signature = HMAC-SHA256(secretKey, JSON.stringify({accessKey, timestamp, user}))`（hex）
> - 区域：`GET /ac/openapi/v2/center` → 各区域 `hpcUrls` / `efileUrls`；token TTL 4 h
> - 提交：`POST {hpc}/hpc/openapi/v2/apptemplates/BASIC/BASE/job`，`strJobManagerID` = 调度器 id，
>   `mapAppJobInfo` 用 `GAP_*` 字段（`GAP_NPROC` 是**总核数**，`GAP_NGPU/GAP_NDCU` 是**每节点**）
> - 取消：`DELETE /openapi/v2/jobs` + `strJobInfoMap=<scheduler>,<user>:<jobId>:`
> - 流程：`plan → validate → stage → approve → submit → monitor → collect → diagnose → report`


- [ ] `agent/task/list`（需要 `scopeKey` 等参数，未测出）
- [ ] `jobgather/jobs/history/page-list` 作业历史
- [ ] 产物列表 `v2/agent/conversation/{id}/output-files` + CSV/PDF 预览
- [ ] SLURM 脚本生成模板
- [ ] 集群信息（`customer/group/user-cluster-info`）

## E. 账号 / 团队 / 计费（P5）

- [x] **模型服务授权链路**（对齐官方客户端）：`account/config/status` → `account/config/authorize`
      → `api-key/createActivityApiKey` → `/models`；代码在 `service/ApiKeys.ets`
- [?] **网关 402 是账号侧**：本机实测 `modelServiceEnabled: 0`、`unpaidStatus: 1`
      （`scripts/probe-v2.sh account` 可复现）。需要人去控制台清账 / 开通模型服务，代码侧无解。
- [ ] 图形验证码输入 UI（`isNeedCpatcha.action` + `getClientCaptcha.action`，
      登录字段 `username/password/captcha/captchaKey`；当前只在错误文案里提示）


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
- [x] 停止按钮真机验证（截断保留、不崩、状态复位）
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

- [x] ~~v2 stream 的 `modelId` 从哪来~~ → `recommend/list` → `aiagent-router` → `600`（字符串）
- [x] ~~流结束哨兵~~ → 没有 `[done]`，靠 `finish` 帧 + 连接关闭
- [x] ~~stream 是否必须带 Cookie~~ → 必须，缺了 500
- [ ] `v2/agent/stop` 请求体（已知 `{conversationId, modelId}`，未验证）
- [ ] `v2/agent/resume` / `check-stream` 的入参与返回
- [ ] `agent/task/list` 必填参数
- [ ] 附件 `upload/url` 的入参（文件名/大小/类型）与 OSS 直传流程
- [ ] 会话标题如何生成（`title_gen` 事件 or 客户端截断）
