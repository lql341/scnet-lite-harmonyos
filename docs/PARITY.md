# PARITY — 对齐官方 APK 的功能清单与施工计划

目标：用 ArkTS 原生实现，功能与官方 APK（Flutter，`SCNet-1.1.1`）一致。本文件是验收基准，
每完成一项把它从 `❌` 改 `✅`。证据来自对 APK（`libapp.so` AOT 快照 + `strings` 提取的中文/接口字符串）
与官方 Web 前端（`www.scnet.cn/ui/chatbot`）的实测，不是猜测。

## 0. 两套后端，别混

| 用途 | 主机 | 鉴权 |
| --- | --- | --- |
| 模型网关（现在在用） | `api.scnet.cn/api/gw/v1` | 网关 key（25 字符），OpenAI 兼容 |
| 平台业务（APK 实际的） | `www.scnet.cn/acx/*`、`/sso/*`、`/ac/api/*` | 平台 accessToken（JWT）/ SSO cookie |

实测（2026-11-08）：用桌面客户端的 `accessToken` 打
`/acx/chatbot/config/list`、`/acx/chatbot/conversation/list` → `200 {"code":"0"}`；
但 `/acx/user/users/current-user`、`/acx/llm/api/console/model` → `401 用户未登录!`。
结论：**chatbot 接口认 Bearer，user/llm 接口认 SSO cookie**，两条鉴权都要实现。

## 1. 接口清单（APK 内 41 个，按模块）

```
SSO      /sso/login  /sso/register[.action]  /sso/sendRegisterMessageCode.action
         /sso/recommendUserName.action   /ac/api/auth/loginDesktopClient.action
         /ac/api/auth/loginSsoRedirect.action
用户     /acx/user/users/{current-user,current-user-info,logout,user-base-info,
         user-telephone-email,cur-user-mobile-email,verify-code,verify-code-send,
         verify-code-check,mobile-is-available-user-v2,user-verifiedF,
         user-unregister,user-unregister-apply}
团队     /acx/user/customer/group/{curuser-group-names,user-cluster-info}
对话     /acx/chatbot/v2/agent/{stream,stop,resume,check-stream}
         /acx/chatbot/v1/chat/reaction   /acx/chatbot/agent/task/list
会话     /acx/chatbot/conversation/{list,rename}
附件     /acx/chatbot/file/{upload,download}/url
配置     /acx/chatbot/config/list（实测公开可读：推荐问题 + 合作伙伴广告位）
模型     /acx/llm/api/console/model      密钥 /acx/llm/api-key/{create,query}
作业     /acx/jobgather/jobs/history/page-list
更新     /download/client/android/version.json
```

统一信封：`{"code":"0","msg":"success","data":…}`（`code` 是**字符串**，非 0 即错误）。

## 2. 功能面 checklist

### 账号
- ❌ 用户协议 + 隐私政策首屏同意（不同意为不可用）
- ❌ 登录（用户名/密码；密码 6~30 位、大写+小写+数字+符号至少 3 类）
- ❌ 短信验证码登录/注册（`verify-code-send` / `verify-code-check`，5~16 位用户名规则）
- ❌ 找回密码、手机/邮箱绑定修改、实名认证状态（`user-verifiedF`）
- ❌ 退出登录（提示"不会丢失任何数据"）
- ❌ 账号注销（10 条须知 + 前置校验：无未结清费用、无未结束作业/图形会话/容器、退出团队）
- ❌ Token 过期统一处理（`登录已过期` → 回登录页）、停用账号提示

### 对话（核心）
- ❌ v2 流式对话 `POST /acx/chatbot/v2/agent/stream`（SSE，支持打断）
- ❌ 打断/续传：`stop` / `resume` / `check-stream`（杀进程后能接回正在生成的消息）
- ❌ 阻塞式交互组件协议（`componentType`：text/button/input/select/table/form/confirm/file/checkbox/date…）
- ❌ 会话列表 / 重命名 / 云端 conversationId 回填（`conversation/list`、`rename`）
- ❌ 附件上传下载（`file/upload/url`、`file/download/url`，OSS 直传预签名）
- ❌ 文献列表渲染、点赞（`reaction`）、"内容由 SCNet AI 生成，仅供参考"角标
- ❌ 生成计算报告（依赖 conversationId）
- ❌ Markdown 渲染 + 代码块 + KaTeX 数学公式（APK 用 `flutter_math_fork`）
- ❌ 语音输入、OCR 识别、相机权限
- ❌ 多模型切换（现有 11 个网关模型可复用）
- ✅ SSE 基础流式渲染 + reasoning_content + 停止生成（现有 MVP）

### 技能 / 工作流
- ❌ 技能面板（APK 内置示例：WorkflowCar Model2 汽车外流场、Quantum ESPRESSO、pro-seq TSS/Pausing Index、hic-seq）
- ❌ "生成 N 核心 SLURM 脚本" 这类参数化提交
- ❌ 任务列表 `agent/task/list`、任务产物加载与预览

### 作业 / 资源 / 计费
- ❌ 作业历史分页（`jobgather/jobs/history/page-list`）、作业状态、产物下载
- ❌ 图形会话、容器实例状态
- ❌ 集群信息（`customer/group/user-cluster-info`，含 11250/11257/11271 等 clusterId → 每集群一个 JWT）
- ❌ 团队/资源授权（`acctRole: Leader,Member`）
- ❌ 计费与发票（实缴/退金额、统一社会信用代码）

### 其它
- ❌ 版本检查与升级提示
- ❌ 深链 / 分享（`/share/:id`、`/mobile/:id`、`/shell/:id` 见 Web 端路由）
- ✅ 图标（官方 1024² 已入包）

## 3. 施工顺序（每步都可上机验收）

1. **壳 + 登录**：Tabs（对话/作业/我的）、SSO 登录、accessToken 持久化（HUKS 或加密 preferences）、401 统一拦截。
2. **对话 v1.5**：会话列表 + 新建/重命名 + 云端 conversationId 回填；v2 stream 接入；stop/resume/check-stream。
3. **对话 v2**：阻塞式交互组件协议、附件上传下载、Markdown+KaTeX、点赞、文献列表。
4. **技能/作业**：task/list、作业历史、产物预览（CSV/PDF）、SLURM 脚本生成。
5. **账号/团队/计费**：资料、绑定、注销、团队授权、发票。
6. **打磨**：LaTeX 性能（LazyForEach）、语音、OCR、升级检查、深链。

## 4. 已知坑
- ArkTS 不允许裸对象字面量：每个请求/响应体都要显式 `interface`（`Api.ets` 已有的写法照抄）。
- `startWindowIcon` 打包时 hvigor 会报 `ScaleImage failed: INVALID_PARAMETERS`（512/288/216 都报，1024 的 app_icon 不报）→ 只影响启动图，先忽略。
- 平台 `code` 是字符串；HTTP 200 但 `code != "0"` 也算失败。
