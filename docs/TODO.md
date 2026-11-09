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

## B. UI（当前重点）

- [x] 设计令牌统一到 `common/Theme.ets`（颜色/圆角/间距/字号/阴影）
- [x] Markdown 渲染（标题/列表/引用/代码块/行内粗斜码），替代裸文本
- [x] 代码块复制按钮 + 语言标签
- [x] 空状态用 `config/list.recommendQuestion` 做建议卡
- [x] 思考态（`LoadingProgress` + 进度文案）、流式光标
- [x] 模型面板：搜索框 + 免费标识 + 选中态
- [x] 登录页重做（品牌区 + 分段 Tab + 卡片式表单 + 内联错误）
- [x] 抽屉：账号卡 / 新对话主按钮 / 历史会话 / 设置 / 退出
- [x] 错误卡（可关闭，不打断阅读）
- [ ] 长会话 `LazyForEach`（现在全量渲染）
- [ ] 消息操作：长按复制整条 / 重新生成
- [ ] 深色模式（Theme 已集中，改造点单一）
- [ ] 表格渲染（Markdown 表格目前退化为段落）
- [ ] 应用图标仍是官方 APK 的 logo（仅调试用），发布前必须换成自有图标
- [ ] 空状态那次"诡异首条气泡"的根因（重启偶发一次，未复现）

## C. 会话与上下文

- [x] 平台历史会话列表 + 只读浏览
- [ ] 本地多会话（`relationalStore`）+ 侧滑删除 + 标题摘要
- [ ] 上下文裁剪（长对话按 token 估算截断，现在全量发送）
- [ ] 会话重命名（`conversation/rename`）

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
- [ ] 单元测试：Markdown 解析、SSE 分帧、buffer 冲刷（用真实抓包做 fixture）
- [ ] 日志分级（现在 hilog 全量，发布前收口）
- [ ] 清理平台侧早期探测产生的空会话（服务端无删除接口）

## H. 待补协议细节

- [ ] `api-key/create` 的完整入参（团队维度）与配额字段
- [ ] `createActivityApiKey` 的调用频控（每调一次是否新建 key）
- [ ] 余额/账单查询接口（用于在 App 里直接提示"还差多少钱"）
