# HANDOFF — scnet-lite-harmonyos

交接文档。给下一个接手的 agent：读这一份就能继续干活，不需要重新做可行性调研。

---

## 1. 这是什么

用 **ArkTS 从零重写**的 SCNet（国家超算互联网）移动端前端，跑 HarmonyOS。
当前是 **MVP：流式对话**。

**不是**官方 Android 客户端的移植。原因（已确认，不要重复调研）：

- 官方 APK（`https://dlcdn.scnet.cn/client/android/1.1.1/SCNet-1.1.1-ae010e5_1793867022.apk`，42.4 MB）
  是 **Flutter** 应用：`lib/arm64-v8a/libflutter.so`（Impeller）+ `libapp.so`（Dart **AOT 快照**，
  `Dart 3.13.0 (stable) on "android_arm64"`），`readelf -d libapp.so` 无 `NEEDED`。
- AOT 快照不能还原成可编译的 Dart 源码，且与引擎构建强绑定；换 HarmonyOS 的 Flutter 引擎跑不通。
- 附带原生依赖：`libpdfium.cr.so`、`libpdfiumandroid.so`、`libdatastore_shared_counter.so`、`libdartjni.so`。
- 插件面（dex 里可见）：`flutter_secure_storage`、`flutter_local_notifications`、`image_picker`、`url_launcher`。

结论：只能重写（本仓库），或 ArkWeb 套 Web 端，或直接侧载（仅 HarmonyOS 4.x AOSP 底座可跑 APK）。
**不要**尝试方案「AOT 复用 + OHOS Flutter 引擎」，投入产出比极差。

---

## 2. 当前状态

- 分支 `main`，最新提交 `da4a0b3`（README/ LICENSE），在此之前 `152b626`（MVP 代码）。
- 构建产物：`entry/build/default/outputs/default/entry-default-unsigned.hap`（约 78 KB，**未签名**）。
- 已实现：SSE 流式对话（含 `reasoning_content`）、11 个网关模型切换、API Key/Base URL 设置
  + preferences 持久化、停止生成。
- 未实现：账号登录、作业/队列/文件、多会话、PDF 预览、消息 Markdown 渲染、流式 token 计数。

代码规模：`ets` 共 555 行 —— `pages/Index.ets` 259、`service/Gateway.ets` 170、
`service/Store.ets` 72、`model/Models.ets` 33、`entryability/EntryAbility.ets` 21。

---

## 3. 环境（本机已装，直接可用）

```
~/opt/apps/harmonyos/26.0.0.865/command-line-tools   # SDK API 26 (26.0.0.105)
  ├─ hvigor/bin/hvigorw            6.26.9
  ├─ ohpm/bin/ohpm                 26.0.0.630
  ├─ sdk/default/openharmony/toolchains/hdc
  └─ sdk/default/openharmony/toolchains/lib/
        hap-sign-tool.jar  OpenHarmony.p12  UnsgnedDebugProfileTemplate.json
node v26.13.0 · jdk 21 · 无设备连接（`hdc list targets` 为空）
```

## 4. 构建 / 签名 / 安装

```bash
CLT=~/opt/apps/harmonyos/26.0.0.865/command-line-tools

# 构建（约 16 s，无签名）
DEVECO_SDK_HOME=$CLT/sdk $CLT/hvigor/bin/hvigorw assembleHap \
  --mode module -p product=default -p buildMode=debug --no-daemon

# 装到设备/模拟器（先确认 hdc 能看到目标）
$CLT/sdk/default/openharmony/toolchains/hdc list targets
$CLT/sdk/default/openharmony/toolchains/hdc install \
  entry/build/default/outputs/default/entry-default-signed.hap
```

签名两条路（当前 `build-profile.json5` 的 `signingConfigs` 为空，hvigor 会跳过签名）：

1. **华为真机**：装 DevEco Studio → 打开本工程 → Project Structure → Signing Configs 勾选自动生成
   （需登录华为账号），会写回 `build-profile.json5`，然后重跑 `assembleHap`。
2. **OpenHarmony 设备 / 模拟器**：用 SDK 自带材料自签，顺序
   `generate-keypair → generate-csr → generate-app-cert → sign-profile → sign-app`
   （`java -jar $CLT/.../lib/hap-sign-tool.jar <subcommand> --help` 查参数），
   把 keystore/profile 填进 `signingConfigs`。自签证书在华为真机上会被拒，别混用。

---

## 5. 代码地图

| 文件 | 职责 | 接手要点 |
| --- | --- | --- |
| `entry/src/main/ets/service/Gateway.ets` | OpenAI 兼容 SSE 客户端 | `http.requestInStream` + `on('dataReceive')` 手写行缓冲；`util.TextDecoder.create('utf-8',{ignoreBOM:true}).decodeToString(u8,{stream:true})` 处理跨块多字节；`cancel()` 走 `request.destroy()` |
| `entry/src/main/ets/service/Store.ets` | preferences 持久化 | `preferences.getPreferencesSync(context,{name})` + `getSync/putSync/flush`；单例 `store` |
| `entry/src/main/ets/pages/Index.ets` | 单页 UI（会话气泡 + 设置面板 + 输入区） | `@State messages: RenderMsg[]` 用 `concat` 换引用触发刷新；`Scroller.scrollEdge(Edge.Bottom)` 滚到底；设置面板是条件渲染，不是路由 |
| `entry/src/main/ets/model/Models.ets` | 内置模型目录（11 个） | 来源：桌面客户端 `~/.sclaw/agent/models.json` 的 `visibleModelIds`（32 个），按需加 |
| `entry/src/main/ets/entryability/EntryAbility.ets` | 入口 Ability | `windowStage.loadContent('pages/Index')` |
| `entry/src/main/module.json5` | 权限 | 已声明 `ohos.permission.INTERNET`、`ohos.permission.GET_NETWORK_INFO` |
| `build-profile.json5` | 产品配置 | `compatibleSdkVersion`/`targetSdkVersion` 都是 `"26.0.0"`（见坑 2） |

---

## 6. 已经踩过的坑（照抄结论，别再试错）

1. **`DEVECO_SDK_HOME` 必须指 `<CLT>/sdk`**，指 `sdk/default` 会报
   `00303312 Cannot find the corresponding SDK version`；不设会报 `00303217 Invalid value of 'DEVECO_SDK_HOME'`。
2. **API 26 起 `compatibleSdkVersion` 写 `"26.0.0"`**，带 `(26)` 后缀会报
   `00306042 ... For API version 26 and later, the value ... must be a string (for example, '26.0.0')`；
   写 `"26"` 也一样报错。
3. **ArkTS 不允许“无类型的对象字面量”**：`header: {...} as Record<string,string>`、`JSON.stringify({...} as Record<string,Object>)`
   都会报 `arkts-no-untyped-obj-literals`。做法：显式声明 `interface`（见 `RequestHeaders`、`ChatRequestBody`）再赋值。
4. `http.HttpRequest` **没有** `'error'` 事件（只有 `dataReceive` / `dataEnd` / `headersReceive`）；
   网络错误从 `requestInStream(...).catch()` 拿。
5. `requestInStream` 是 `Promise<number>`，返回的只是一个请求 id；数据必须靠事件回调收集。
6. `@Builder` 方法里的对象字面量会触发 ArkTS 严格检查，尽量用已声明类型。
7. hvigor 首次构建会自己解析 `hvigor-config.json5` 里的 `modelVersion: "6.26.9"`，无需手工 `npm i`；
   构建日志在 `.hvigor/outputs/build-logs/build.log`。

## 7. 已验证的接口契约

```bash
K=<gateway key>            # 25 字符；和网页登录态 accessToken 不是一套
GET  https://api.scnet.cn/api/gw/v1/models            -H "Authorization: Bearer $K"   # 200，51 个模型
POST https://api.scnet.cn/api/gw/v1/chat/completions  -H "Authorization: Bearer $K" \
     -H 'Content-Type: application/json' \
     -d '{"model":"glm-5.3-flash","stream":true,"messages":[{"role":"user","content":"hi"}]}'
# → data: {"choices":[{"delta":{"content":"…","reasoning_content":"…"}}]} … data: [DONE]
```

模型 ID 示例：`glm-5.3-flash`、`glm-5.3`、`deepseek-v4.1-flash`、`deepseek-v4-pro`、`kimi-k3`、
`kimi-k2.7-code`、`qwen3.8-max`、`qwen3.8-flash`、`minimax-m3`、`claude-sonnet-5`、`gpt-5.6-terra-lite`。

---

## 8. 待办（按建议顺序）

### P0 登录（替代手填 key）
现状：用户手动粘贴网关 key。目标：账号/短信登录。
- 线索：桌面客户端把网页登录态放在 `~/.config/scnet-client/config.json` 的 `accessToken`
  （打 `api/llm/v1` 返回 401，说明网关 key 是另一套）；
- 平台侧登录接口未知，**下一步先测绘**：在桌面客户端主进程的 host 操作表里找 `auth.*`
  （`auth.login`、`auth.get-picture-captcha`、`auth.get-refresh-state`、`auth.persist-remembered-login` 等 13 个）。
  取表方法：`strings`/字节搜索 `/opt/scnet-client/resources/app.asar`，或找
  `"auth.login":{optional:` 附近能看到 payload schema（`additionalProperties/kind/properties` 的 JSON 描述）。
- 拿到接口后在 ArkTS 里用 `@kit.NetworkKit` 的 `http` 实现，token 存 `@ohos.security.huks` 或
  `preferences` + 加密；不要明文写死在代码里。

### P1 作业/队列/文件（真正体现“超算”）
- 用 SCNet OpenAPI（AK/SK）+ Slurm 语义，参考现成 skill：`~/Downloads/agent/skills/scnet-hpc/references/openapi.md`。
- 建议新增 `service/Hpc.ets`：签名（AK/SK）、`jobs.list/submit/cancel`、`queues`、`account`；
  页面用 `Tabs` 放在首页旁边，与聊天页并列。
- 提交类操作必须有二次确认，并显示目标区域/队列/资源。

### P2 多会话 + 持久化
- `sessions` 存 `relationalStore`（`@kit.ArkData`），列表页 + 侧滑删除 + 标题自动摘要。
- 现在 `Index.ets` 只有一条内存会话，改造点集中在 `messages` 状态与 `Store`。

### P3 文件 / PDF / Markdown
- Markdown：用 `RichText`/自定义解析（不要引入 web 组件）。
- PDF：`@ohos.file.picker` + 系统预览，或接 `pdfview` 类三方库；不要试图复用 APK 里的 pdfium。

### P4 细节
- 消息渲染性能（长会话用 `LazyForEach`）、`reasoning` 折叠、token/上下文档位显示（网关暂不回 usage，可估算）。

---

## 9. 验证清单

1. `hvigorw assembleHap` 无 ERROR（WARN 允许）。
2. 模拟器/真机：冷启动 3 s 内出界面；无 key 时自动弹设置面板。
3. 设置里保存 key → 杀进程重进 → key 仍在（preferences 生效）。
4. 发一条消息：字符逐个出现（流式），"停止"能中断且不崩。
5. 切模型后同一个问题能得到不同模型回答（`/models` 交叉验证）。
6. 断网发消息：报错可读、可重试，不卡在 loading。

## 10. 需要人确认的问题

- 目标设备是 HarmonyOS **4.x** 还是 **NEXT/6.x**？（决定“侧载 APK”是否是零成本选项）
- 平台是否有可登录的 **Web 端**入口？（决定 ArkWeb 套壳是否比原生重写更划算）
- 是否要发布到应用市场？涉及实名/签名证书/隐私声明与合规，会改变实现要求。

## 11. 禁止事项

- 不要从 APK 反编译/复用 Dart AOT 快照；不要试图复刻 pdfium 等 Android 原生库。
- 不要把厂商二进制（APK/asm/资源）提交进仓库；不要使用厂商图标与商标做应用图标（当前是纯色占位 PNG）。
- 不要在仓库或文档里声称是官方客户端。
