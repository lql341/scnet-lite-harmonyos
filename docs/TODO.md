# TODO — 待办清单

状态：`[x]` 完成 · `[~]` 部分 · `[ ]` 未开始 · `[?]` 阻塞（需要外部条件）

> 对话通道只有一条：**网关模型链路**（登录 → 集群身份 → 授权 → 取 key → `/models` → `/chat/completions`）。
> 平台 v2 智能体通道已彻底移除（含文档），历史见 git `b60d149`。

---

## A. 当前状态

- [x] 登录（账号密码 / 短信验证码），form-urlencoded，`1014`/`1006` 文案分得清
- [x] `isNeedCpatcha` 门槛判断（平台平时返回 false；真要求验证码时给明确提示，UI 未做）
- [x] 集群身份（`cluster-user-detail` → 集群 accountId/groupId/userId）
- [x] 模型服务授权（`account/config/status` → 需要时 `authorize`）—— 必须用**集群** accountId
- [x] 取网关 key（`createActivityApiKey` → 兜底 `api-key/query`）
- [x] 模型列表（33 个）与默认模型 `SCNet-Max`（免费；其余需余额）
- [x] 流式对话（OpenAI 兼容 SSE，含 `reasoning_content` 分离、`[DONE]`、停止）
- [x] 错误路径可读（401/402 是**无换行单行 JSON**，已修 buffer 冲刷）
- [x] 真机验证：出字 / 停止 / 402 文案 / 重启保持登录

## B. UI

- [x] 设计令牌统一到 `common/Theme.ets`（颜色/圆角/间距/字号/阴影）
- [x] Markdown 渲染（标题/列表/引用/代码块/行内粗斜码），替代裸文本
- [x] 代码块复制按钮 + 语言标签
- [x] 空状态用 `config/list.recommendQuestion` 做建议卡
- [x] 思考态（`LoadingProgress` + 进度文案）、流式光标
- [x] 模型面板：搜索框 + 免费标识 + 选中态
- [x] 登录页重做（品牌区 + 分段 Tab + 卡片式表单 + 内联错误）
- [x] 抽屉：账号卡 / 新对话主按钮 / 历史会话 / 设置 / 退出
- [x] 错误卡（可关闭，不打断阅读）
- [ ] 长会话 `LazyForEach`（现在全量渲染；消息 ≥200 条时才值得做）
- [x] 消息操作：长按复制整条（用户/助手气泡都支持）
- [ ] 重新生成（需要有 messageId 关联，智能体通道再考虑）
- [ ] 深色模式（Theme 已集中，改造点单一）
- [x] 表格渲染（`|a|b|` + 分隔行 → 原生表格，窄屏横向滚动）
- [x] 应用图标已换成中性设计（三节点调度意象，无厂商商标）；应用名改为「超级计算智能体」
- [ ] 深色模式（Theme 已集中，改造点单一，但需要真机逐页校色）
- [ ] 空状态"诡异首条气泡"（重启偶发，未复现；怀疑是流式占位与消息列表共用索引）

## C. 会话与上下文

- [x] 平台历史会话列表 + 只读浏览
- [x] 本地多会话（文件存储，非 relationalStore）+ 删除 + 自动标题
- [x] 会话重命名（本地长按改名；平台历史走 `conversation/rename`）
- [x] 上下文裁剪（24000 字符上限、至少保留最近 6 条、被裁时提示用户；
      逻辑在 `common/Chat.trimHistory`，13 条单测）
- [x] 会话重命名（`conversation/rename`）

## D. 富交互 / 附件（需要平台能力，暂缓）

- [ ] 附件上传下载（`file/upload/url`、`file/download/url`）
- [ ] 图片输入（网关多模态模型 + `image_url`）
- [ ] 语音输入（`wss://www.scnet.cn/acx/chatbot/ws/audio/recognize`）
- [ ] OCR（`/api/llm/v1/ocr/recognize`）

## E. 作业面 P4（照 `../scnet-cli` 搬，最高价值的下一步）

> 隔壁已端到端跑通真实作业，契约可照抄：
> `packages/scnet-agent/src/core/sci/openapi.mjs`（469 行）+ `flow.mjs`（411 行）

- [ ] 签名：`POST /api/user/v3/tokens`，头 `user`/`accessKey`/`signature`/`timestamp`，
      `signature = HMAC-SHA256(secretKey, JSON.stringify({accessKey,timestamp,user}))`（hex）
- [ ] 区域：`GET /ac/openapi/v2/center` → 各区域 `hpcUrls` / `efileUrls`；token TTL 4h
- [ ] 提交：`POST {hpc}/hpc/openapi/v2/apptemplates/BASIC/BASE/job`，
      `mapAppJobInfo` 用 `GAP_*`（`GAP_NPROC` 是**总核数**，`GAP_NGPU/GAP_NDCU` 是**每节点**）
- [ ] 取消：`DELETE /openapi/v2/jobs` + `strJobInfoMap=<scheduler>,<user>:<jobId>:`
- [ ] 队列/配额：`sci status` / `sci queues` 对应接口
- [ ] 页面：底部 Tab「作业」，列表 + 详情 + 日志
- [ ] 提交前二次确认（显示集群/队列/资源/计费）

## F. 账号 / 团队 / 计费

- [x] 模型服务授权链路 + 402 归因（按模型计费，非账号封锁）
- [?] 付费模型需要余额：`unpaidStatus: 1`，需人去控制台处理；默认 `SCNet-Max` 不阻塞
- [ ] 图形验证码输入 UI（`getClientCaptcha` → 图片 + `captchaKey`）
- [ ] 用户资料 / 手机绑定 / 团队资源
- [ ] 发票（实缴/退金额、统一社会信用代码）

## G. 工程

- [x] `scripts/probe.sh`（account/authorize/models/chat/raw）脱机复现全链路
- [x] `scripts/dev-check.sh`（工具链/设备/签名/文档）
- [x] 单元测试：Markdown 解析（30）、SSE 分帧/冲刷（10）、上下文裁剪（13）、
      HMAC RFC 4231 向量（8）—— `./scripts/test.sh`，跑的就是线上同一份源码
- [x] 日志分级（逐条 SSE/签名/会话保存等高频 info 降 debug；签名明文日志已移除）
- [ ] 清理平台侧早期探测产生的空会话（服务端无删除接口）

## H. 待补协议细节

- [ ] `api-key/create` 的完整入参（团队维度）与配额字段
- [ ] `createActivityApiKey` 的调用频控（每调一次是否新建 key）
- [ ] 余额/账单查询接口（用于在 App 里直接提示"还差多少钱"）
