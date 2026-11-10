# 评估：把本项目打成 Android APK 的难度

> 结论先说：**不是打包问题，是「两个平台 UI 框架不同」的问题。**
> 直接打 APK 做不到；有三条路，成本从高到低差异很大。数据基于当前代码实测（12 468 行 ArkTS / 31 文件）。

---

## 1. 为什么不能直接打 APK

`.hap` 是 HarmonyOS 的应用包，`hvigor`/`app_packing_tool` 只能产出 HAP/APP，**没有 Android 目标**。
ArkTS 是 TypeScript 的超集，但运行时是方舟（ArkCompiler）；Android 上跑的是 ART + Kotlin/Java 或 JS 引擎。
两边的 UI 也完全不同：

| 层 | 本项目用法 | Android 对应 | 能否复用 |
| --- | --- | --- | --- |
| UI 框架 | ArkUI **声明式**（`@Component` / `@Builder` / `@State` / `LazyForEach` / `bindContextMenu`） | Jetpack Compose（Kotlin）或 Flutter/Dart | ❌ 逐行重写 |
| 网络 | `@kit.NetworkKit` 的 `http`（含 `requestInStream`） | OkHttp / HttpURLConnection | ❌ 换 API，逻辑可抄 |
| 文件 | `@kit.CoreFileKit` `fileIo` | `java.io` / SAF | ❌ 换 API |
| 相册/文件选择 | `photoAccessHelper` / `DocumentViewPicker` | `ActivityResultContracts` | ❌ 换 API |
| 加密 | `@kit.CryptoArchitectureKit`（Md/Mac） | `javax.crypto.Mac` | ⚠️ 算法可复用，代码重写 |
| 内嵌浏览器 | `@kit.ArkWeb` 的 `Web` 组件 | `WebView` | ❌ 换 API |
| 偏好存储 | `@kit.ArkData` `preferences` | `SharedPreferences` / DataStore | ❌ 换 API |
| 剪贴板 | `@kit.BasicServicesKit` `pasteboard` | `ClipboardManager` | ❌ 换 API |

**能直接复用的是「协议知识」**，不是代码。这一点很关键，见第 3 节。

---

## 2. 现有代码的可移植性实测

```
纯逻辑（无 ArkUI，只有少量 kit 调用）       4 858 行
声明式 UI（@Component/@Builder/@Entry）    7 697 行
```

纯逻辑里真正**不依赖任何 kit** 的只有 4 个文件（739 行），这几份可以直接搬到任何语言/平台：

| 文件 | 行数 | 内容 | 移植价值 |
| --- | --- | --- | --- |
| `common/Markdown.ets` | 362 | Markdown 块级/行内解析（含表格、流式半截容错） | ⭐⭐⭐ 有 30 条单测，可逐行翻译 |
| `common/Hmac.ets` | 85 | RFC 2104 HMAC-SHA256 + 签名 message 构造 | ⭐⭐⭐ 有 RFC 4231 向量单测 |
| `common/Sse.ets` | 72 | SSE 行缓冲（跨块多字节 + 无换行冲刷） | ⭐⭐⭐ 有 10 条单测 |
| `common/Chat.ets` | 62 | 上下文裁剪 + token 估算 | ⭐⭐⭐ 有 13 条单测 |

其余 service 层（`Hpc.ets` 613 行、`Auth.ets` 472 行、`Http.ets` 181 行…）
是「协议 + kit 调用」混在一起：**协议部分能照抄，kit 调用必须换**。
`Hpc.ets` 最典型 —— HMAC 那 85 行可复用，剩下 500 行是 OpenAPI 编排 + `http` 调用。

---

## 3. 三条路线与成本

### 路线 A：Flutter 重写（推荐，若一定要 APK）

官方 App 本身就是 Flutter，社区方案成熟。

| 阶段 | 工作 | 估算 |
| --- | --- | --- |
| 协议层 | 照抄 4 个纯逻辑文件（Dart 版）+ 8 个 service 的协议编排 | 2-3 天 |
| UI 层 | 11 个页面用 Dart + 自绘 Markdown 重建 | 5-7 天 |
| 平台能力 | WebView、文件选择、相册、偏好、剪贴板、HMS 推送 | 2 天 |
| 合计 | | **9-12 天**（不含签名/上架） |

优点：一套代码同时出 Android/iOS；协议层几乎零风险（已有单测向量可验）。

### 路线 B：Kotlin + Jetpack Compose

| 阶段 | 估算 |
| --- | --- |
| 协议层（OkHttp + kotlinx.serialization） | 2-3 天 |
| UI（Compose，11 页 + Markdown 渲染器） | 6-8 天 |
| 合计 | **8-11 天** |

和 A 差不多，但只出 Android；如果以后要 iOS 还得再来一遍。**除非团队只做 Android，否则不如 A。**

### 路线 C：ArkWeb 壳 + 现有 Web 端（最快，但功能打折）

平台自己有移动适配的 Web 前端（`/ui/chatbot/index.html`，viewport 已适配移动），
Android 端只需一个 WebView 壳 + 登录态注入。

| 工作 | 估算 |
| --- | --- |
| WebView 壳 + cookie 注入 + 文件选择/下载回调 | **1-2 天** |
| 缺的功能：作业面、OCR、插件市场原生入口 | 都用 Web 端自己的页面 |

代价：**本仓库 12 468 行 ArkTS 全部作废**（除了作为协议参考）；体验受 Web 端限制。
但如果你想先有个能装的 Android 版试试水，这是最短路径。

---

## 4. 我的建议

1. **如果 Android 是主目标**：走路线 A（Flutter）。协议层已有单测向量，照抄成本低；
   把本仓库当「协议规格书 + 行为基准」用（`docs/PROTOCOL.md` + `docs/FEATURES.md` + 4 个纯逻辑文件）。
2. **如果只是想要一个能装的 Android 版看效果**：路线 C，1-2 天。
3. **不建议**：把 ArkTS 硬转 Kotlin（`@Builder` 的 DSL 语义与 Compose 不一一对应，转换器会产出看不懂的代码）。

---

## 5. 不随平台变化的东西（这份才是最值钱的资产）

无论走哪条路线，以下都已经**验证过、可直接复用**：

```
docs/PROTOCOL.md     鉴权双头、登录链路、授权取 key、v2 帧、SSE、OCR/文档解析、HPC 签名与提交
docs/FEATURES.md     功能面清单与限制（哪些平台不支持、为什么）
docs/ROADMAP.md      每个接口的实测结论 + 踩过的坑
scripts/probe.sh     脱机探针（与语言无关，纯 curl/HTTP）
test/*.test.mjs      4 组测试向量（Markdown 30 / SSE 10 / 裁剪 13 / HMAC 8）
```

这些是 12 468 行代码里**唯一与 HarmonyOS 无关**的部分，也是重写时真正的输入。

---

## 6. 一个数据点

官方 APK 42.4 MB（Flutter + Impeller + pdfium + 多个插件）。
本项目的 HAP 只有 **366 KB**（ArkTS 编译产物，无第三方运行时）——
这也是为什么它没法"打包成 APK"：它依赖方舟运行时，而 Android 上没有。

---

## 7. 实测：路线 C 已跑通（2026-11-10）

不是纸上评估了 —— 仓库里现在有一个**能装的真 APK**：

```
android/                         WebView 壳源码（1 个 Activity + manifest + 图标）
scripts/build-apk.sh             不用 Gradle 的打包脚本（aapt2 → javac → d8 → zip → zipalign → apksigner）
dist/android/scnet-agent-webview-0.1.0-webview.apk    45 809 bytes
```

验证结果：

```
apksigner verify   → Verifies（v2 + v3 scheme 都已签）
aapt2 dump badging → package cn.scnet.agent, sdkVersion 24, target 34,
                     application-label 'SCNet 智能体'
内容               → classes.dex 3.6 KB + 4 档 mipmap 图标 + resources.arsc
```

**怎么做到不用 Gradle 的**（这也是为什么它能进 CI）：

```bash
aapt2 compile --dir android/res -o work/res              # 资源编译
aapt2 link -I $PLAT --manifest … --min-sdk-version 24    # 生成 base.apk
javac --release 11 -classpath $PLAT -d work/classes …    # 编译 Java
d8 --lib $PLAT --min-api 24 --output work/dex …          # 出 classes.dex
zip -j base.apk dex/classes.dex && zipalign -p 4 …       # 合并 + 对齐
apksigner sign --ks debug.keystore …                     # 签名
```

需要装的东西只有 `platforms;android-34` + `build-tools;34.0.0`（脚本里带了安装命令）。
构建耗时 **约 6 秒**，产物 45 KB。

**它是什么、不是什么**：

- 是：一个能加载 `https://www.scnet.cn/ui/chatbot/index.html` 的壳，带 cookie 持久化、
  DOM storage、返回键回退 Web 历史。平台 Web 端本身有移动 viewport，所以能直接用。
- 不是：ArkTS 那 1.2 万行功能的重写。作业面 / OCR / 插件市场 / 本地多会话都不在这个壳里。

**要继续下去的话**（把壳做成"像 App"）：

| 步骤 | 工作 | 估算 |
| --- | --- | --- |
| 1 | 登录态打通：壳内登录后把 cookie 交给原生层，或直接复用 Web 端登录 | 0.5 天 |
| 2 | 文件上传/下载回调（`WebChromeClient.onShowFileChooser` + `DownloadListener`） | 0.5 天 |
| 3 | 原生入口：底部 Tab（对话 / 作业 / 我的），作业/OCR 用原生页对 API | 3-5 天 |
| 4 | 深链、分享、通知 | 1 天 |

第 3 步才是真正的工作量所在 —— 也就是把本仓库已经验证过的接口在 Android 上再实现一遍
（协议可直接照抄 `docs/PROTOCOL.md`）。

---

## 8. 2026-11-10 复核：壳已到「能用」，剩下的是原生功能

上一节的路线 C 已经从 demo 推进到可发布状态。代码在 `android/`（1 个 Activity，约 290 行 Java），
构建脚本 `scripts/build-apk.sh`（不依赖 Gradle）。

### 8.1 已经有的（APK 0.2.0-webview，49 KB）

| 能力 | 实现 | 状态 |
| --- | --- | --- |
| 加载平台 Web 端（移动 viewport） | `WebView` + `ENTRY` | ✅ 可装可跑 |
| 登录态持久化 | `CookieManager.flush()`（onPause / onDestroy） | ✅ |
| 附件上传 | `onShowFileChooser` → `ACTION_GET_CONTENT`（多选 + MIME 过滤） | ✅ |
| 文件下载 | `DownloadListener` → `DownloadManager`（带 cookie） | ✅ |
| 返回键回退 Web 历史 / 转屏保状态 | `onKeyDown` + `saveState/restoreState` | ✅ |
| 顶部进度条 | `onProgressChanged` → 6px `ProgressBar` | ✅ |
| 构建 | aapt2 → javac → d8 → zipalign → apksigner，约 6 s | ✅ |

构建坑（已修）：**build-tools 34.0.0 里的 d8 对非静态内部类/匿名类会 NPE**
（`Cannot invoke "String.length()" because "<parameter1>" is null`），
`scripts/build-apk.sh` 现在自动取最新 build-tools（35.0.0 正常）。

### 8.2 还差什么（按「要不要重写成原生」分两类）

**A. 壳方案本身就够了的部分（不写代码）**

对话 / 模型切换 / 会话历史 / 文档解析 / OCR / 插件市场 / 作业面 —— 平台 Web 端
（`/ui/chatbot`，内含 `/ui/aihub`、`/ui/mall` 入口）全都有，跟在浏览器里用一样。

**B. 壳方案做不到 / 体验差的部分**

| 缺口 | 原因 | 原生实现工作量 |
| --- | --- | --- |
| 首屏冷启动慢（每次都要拉 Web 资源） | 纯 WebView | 预置离线包 / 首屏骨架：1 天 |
| 推送通知（作业完成） | Web 端没有 | 原生页 + FCM/厂商通道：2 天 |
| 后台长任务（作业提交后回前台看进度） | WebView 后台会被杀 | 原生 JobIntentService 轮询 + 通知：2 天 |
| 系统分享 / 深链（`scnet://`） | 需要原生 intent-filter | 1 天 |
| 文件管理（下载到沙盒、列表、删除） | 现在走系统 DownloadManager | 原生文件页：1.5 天 |
| 应用内更新 | Web 端无 | 检查 GitHub Releases + 下载安装：0.5 天 |

合计 **约 8 天**，全部是「壳之外的原生增强」，与 ArkTS 那 1.2 万行业务无关。

### 8.3 如果要做「原生 Android 版」（和 HAP 功能对齐）

按现有代码实测行数换算（2026-11-10：40 个 `.ets`，12 468 行）：

| 层 | 现状（ArkTS） | Android 目标 | 估算 |
| --- | --- | --- | --- |
| 纯逻辑 | `common/{Markdown,Hmac,Sse,Chat}.ets` 579 行，51 条单测 | Kotlin 逐行翻译（单测向量可复用） | 2 天 |
| 协议服务 | `service/*` 3 934 行（Auth/Http/Gateway/AgentChat/Upload/Hpc/Ocr/Market/DocAi/ApiKeys/Sessions，kit 调用与协议混杂） | OkHttp + kotlinx.serialization，协议照抄 | 5 天 |
| 声明式 UI | `pages/*` 6 459 行 + `view/*` 922 行（11 页） | Jetpack Compose | 9 天 |
| 平台能力 | 文件选择/相册/剪贴板/偏好/ArkWeb 内嵌 | SAF / PhotoPicker / DataStore / WebView | 2 天 |
| 工程 | hvigor + 自签脚本 | Gradle + AGP + 签名 + CI | 1.5 天 |
| **合计** | | | **19.5 天**（单人，含自测；不含上架） |

如果砍到「MVP：登录 + 对话 + 会话 + 设置」（不做作业面/OCR/插件市场/文档解析），
约 **8-10 天**（`pages/Jobs|JobDetail|JobSubmit|Files|OcrPage|MarketPage` 共 2 803 行不做）。

> Flutter 方案（本节 §3 路线 A）仍是同样量级：9-12 天出双端。差在 Compose 只有 Android，
> 但可以直接复用本仓库的 Kotlin 对照（`Hmac.ets` 的 RFC 4231 向量、`Sse.ets` 的 10 条分帧用例）。

### 8.4 结论（给决策用）

1. **现在就能发 Android 版**：`dist/android/scnet-agent-webview-*.apk`，49 KB，debug 签名，
   功能等于平台 Web 端的手机版。**推荐先这样发**，成本已付。
2. 想让 Android 版「像 App」：加 §8.2 的 8 天原生增强（优先级最高是应用内更新 + 下载/分享）。
3. 想做功能对齐的原生版：§8.3 的 19.5 天；MVP 8-10 天。
4. 不建议把 ArkTS 硬转 Kotlin —— `@Builder`/`@State` 与 Compose 语义不一一对应，
   转换产物可维护性差；用 `docs/PROTOCOL.md` + 4 个纯逻辑文件 + 51 条单测当规格书重写更划算。


---

## 9. 原生版已落地（2026-11-11）

> 结论更新：**路线 B（Java + 框架控件，不用 Gradle）已经实现功能对齐的原生 APK**，
> 不再是「只有 WebView 壳」。产物 `dist/android/scnet-agent-android-<ver>.apk`（约 165 KB）。

为什么不走 Compose/Flutter：本机只能保证 Android SDK 自带工具链（aapt2/javac/d8/apksigner）可用，
Gradle + AndroidX 依赖解析会把构建绑死在网络上；直接用框架控件 + 自绘 Markdown 反而更可控，
且产物只有 165 KB（dex 239 KB），无任何三方运行时。

### 9.1 代码映射（ArkTS → Java）

| ArkTS | Java | 说明 |
| --- | --- | --- |
| `common/Markdown.ets` | `core/Md.java` | 块级/行内解析，逐条照搬（含流式半截容错） |
| `common/Sse.ets` | `core/Sse.java` | 流式 UTF-8 解码 + 无换行残尾 flush |
| `common/Chat.ets` | `core/ChatText.java` | 24k 上下文裁剪 / token 粗估 / 自动标题 |
| `common/Hmac.ets` | `core/Hmac.java` | 改用 javax.crypto（标准实现） |
| `common/Theme.ets` + `I18n.ets` | `ui/Ui.java` | 8 套配色 + 深色 + 三档字号 + 中英 |
| `service/Http.ets` | `core/Http.java` | Token+Cookie 双头、Set-Cookie 抓取、401 回调 |
| `service/Auth.ets` | `svc/Auth.java` | 密码/短信登录、集群身份、会话与历史 |
| `service/ApiKeys.ets` | `svc/ApiKeys.java` | status → authorize → activity key → query |
| `service/Gateway.ets` | `svc/Gateway.java` | OpenAI 兼容 SSE + 402/401 文案 |
| `service/AgentChat.ets` | `svc/AgentChat.java` | v2 帧分派、stop、多轮 conversationId |
| `service/Sessions.ets` | `svc/Sessions.java` | `filesDir/sessions/*.json` + index |
| `service/Upload.ets` | `svc/Upload.java` | OSS 预签名直传（50+ 扩展名 MIME 表） |
| `service/Ocr.ets` + `DocAi.ets` | `svc/Ocr.java` | OCR 12 类 + DOC_PARING + 格式转换 |
| `service/Hpc.ets` | `svc/Hpc.java` | AK/SK 签名、13 集群、队列/配额/作业/日志/提交/取消 |
| `service/Market.ets` / `AiHub.ets` / `Scenes.ets` | `svc/Market.java` / `AiHub.java` / `Scenes.java` | 市场搜索、社区智能体、首页场景 tab |
| `service/Scenarios.ets` | `svc/Scenarios.java` | 同一份 `scenarios.json` 打进 `res/raw` |
| `view/MarkdownView.ets` | `ui/MdView.java` | 原生控件渲染（代码块复制、表格横向滚动） |
| `pages/*.ets`（11 页） | `MainActivity` `LoginActivity` `ProfileActivity` `JobsActivity` `JobDetailActivity` `JobSubmitActivity` `FilesActivity` `OcrActivity` `MarketActivity` `AiHubActivity` `WebActivity` | 一页一 Activity |

### 9.2 已验证 / 未验证

| 项 | 状态 |
| --- | --- |
| 构建（无须 Gradle，约 8 s） | ✅ `scripts/build-apk.sh` |
| 签名 / 结构 | ✅ `apksigner verify`、`aapt2 dump badging`（minSdk 24 / target 34，release 包不可调试） |
| 核心逻辑单测 | ✅ `scripts/test-android.sh` **43/43**（Markdown / SSE / 裁剪 / HMAC） |
| **装机运行（Android 11 / API 30 模拟器）** | ✅ 见下 |
| 真实账号登录 / 出字 / 作业提交 | ❌ 需要真机 + 真实账号 |

模拟器上跑过的（2026-11-11，`system-images;android-30;default;x86_64`，1080×2340）：

| 场景 | 结果 |
| --- | --- |
| 冷启动 → 未登录跳登录页 | ✅ 817 ms 显示，无崩溃 |
| 登录页渲染（品牌区/分段 Tab/表单/免责） | ✅ |
| 主界面空状态（场景分类 chips + 推荐问题） | ✅ 场景目录来自内置 `scenarios.json` |
| 抽屉（账号卡/新对话/本地会话/平台历史/6 个入口/退出） | ✅ |
| 发消息 → 网络失败 → 顶部错误卡 + 消息气泡 | ✅ 文案可读（DNS 解析失败直出） |
| 本地会话落盘 + 重启后仍在抽屉里 | ✅ `files/sessions/*.json` |
| Markdown 渲染（标题/粗斜/行内码/链接/列表/引用/表格/代码块+复制/分隔线） | ✅ 截图比对通过 |
| 设置页 + 深色模式切换（重新着色整个界面） | ✅ |
| 作业页未配置 AK/SK 的引导卡 | ✅ |
| AI 社区 / 市场 空态 | ✅ 不崩、给"0 个"提示 |
| 覆盖安装升级（同一 keystore） | ✅ `adb install -r` |

模拟器上抓出来并修掉的 3 个真问题：

1. **签名 keystore 每次构建都变**（放在会被 `rm -rf` 的构建目录里）→ 用户升级报
   `INSTALL_FAILED_UPDATE_INCOMPATIBLE`。已改到 `~/.android/scnet-agent.keystore`。
2. **底部面板高度算错**：Dialog 是 `wrap_content`，ScrollView 用 `weight=1` 会算出 0 高；
   现在按内容量测 + 上限屏幕 55%。
3. **401 回调在后台线程动 UI** → 已切主线程。

### 9.3 剩下的活（真机回归 + 打磨，约 3-5 天）

1. **真机跑一遍**（最高优先级）：登录 → 出字 → 停止 → 附件 → 作业 → OCR → 主题切换。
2. 长会话列表性能：目前用 `ScrollView + LinearLayout` 增量追加，几百条消息会吃内存，
   建议换 `ListView`/自建复用（1 天）。
3. 通知与后台：作业完成提醒（2 天，见 §8.2）。
4. 应用内更新（0.5 天）。
5. 图片输入（网关多模态 `image_url`，0.5 天）。
6. 上架准备：正式 keystore、隐私政策、目标商店（1-2 天，不含审核）。

> 与 §8.3 的 19.5 天估算对比：实际完成（协议层 + 11 页 UI + 平台能力）用了约 1 个工作日的密集实现，
> 原因是所有接口契约、字段名、错误码、渲染规则都已在 HarmonyOS 版里验证过，
> 移植过程中只发现 2 个真实 bug（SSE 跨块解码、提示列表 off-by-one），都由自检脚本抓出来。


---

## 10. 对齐完成（0.4.1）

Android 版已按 [`PARITY-ANDROID.md`](PARITY-ANDROID.md) 逐条对齐 HAP，包括：

- 首页场景 tabs + 换一批、领域场景目录
- 会话删除 / 平台会话重命名 / 长会话窗口化（40 条 + 加载更早）
- 市场精选分组 + 分页、OCR 自检、自定义 provider 7 预设
- 设置页身份卡（平台账号/集群账号/集群/调度器）、检查更新、关于、头像字母与「让智能体生成」
- **崩溃自诊断**：容器内无 adb 时也能取到堆栈（界面展示 + 剪贴板 + `/Download/scnet-crash.txt`）
- `scripts/mock-platform.py`：1:1 复刻平台响应（含 SSE），模拟器上可完整走通登录后路径

仍未验证的只有「真实账号 + 真机」这一段（HAP 侧已用同一套接口验过）。
