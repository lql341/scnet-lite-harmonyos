# scnet-lite-harmonyos

非官方。用 **ArkTS 从零重写**的 SCNet（国家超算互联网）移动端前端，跑在 HarmonyOS 上，
直接对接 SCNet 模型网关（`https://api.scnet.cn/api/gw/v1`，OpenAI 兼容 + SSE 流式）。

> 这是**重新实现**，不是官方 Android 客户端的移植：官方 APK 是 Flutter 应用
> （`libflutter.so` + AOT `libapp.so`，Dart 3.13.0），源码不可得，AOT 快照也不可能换引擎重跑。
> 因此本仓库不含厂商的任何二进制或产物，只复用公开的 HTTP 接口契约。

## 文档索引

| 文档 | 内容 |
| --- | --- |
| [`docs/NEXT.md`](docs/NEXT.md) | **接手先看这个**：当前卡点、下一步、换机器要带什么 |
| [`docs/FEATURES.md`](docs/FEATURES.md) | **功能清单**：能做什么、哪些真机验过、有哪些限制 |
| [`docs/VERIFY.md`](docs/VERIFY.md) | **真机回归清单**：设备接上后照着走一遍 |
| [`docs/APK-ASSESSMENT.md`](docs/APK-ASSESSMENT.md) | **打 Android APK 的难度评估**（含已跑通的 WebView 壳实测 + §8 工作量复核） |
| [`docs/RELEASE.md`](docs/RELEASE.md) | 发版流程：一条命令出未签名/已签名 HAP + APK + SHA256SUMS |
| [`docs/PARITY-ANDROID.md`](docs/PARITY-ANDROID.md) | **HAP ↔ Android 功能对齐表**（逐条、带验证状态） |
| [`docs/ANDROID-DEV.md`](docs/ANDROID-DEV.md) | Android 原生版：构建、模拟器、无账号验 UI、已知坑 |
| [`docs/TODO.md`](docs/TODO.md) | 待办全表（分 A~I 段，带阻塞项与已完成项） |
| [`docs/SIGNING.md`](docs/SIGNING.md) | 签名材料清单、换机迁移、重新签发、失败对照 |
| [`docs/PLAN.md`](docs/PLAN.md) | 对标手机 APK 的分阶段开发计划（P0~P6，约 11 天） |
| [`docs/PARITY.md`](docs/PARITY.md) | 功能对齐 checklist（从 APK 提取，带证据） |
| [`docs/PROTOCOL.md`](docs/PROTOCOL.md) | 账户与网关协议（鉴权双头、集群身份、模型服务授权、取 key、SSE） |
| [`HANDOFF.md`](HANDOFF.md) | 立项背景、环境、已踩的坑、逆向结论 |

## 现状（2026-11-09 12:25）

对话走**网关模型链路**，与官方客户端、隔壁 `scnet-cli` 同一套：

```
账号登录 → cluster-user-detail（集群 accountId）
→ llm/account/config/status →（必要时）authorize
→ llm/api-key/createActivityApiKey（key + baseUrl + 默认模型）
→ {baseUrl}/models → {baseUrl}/chat/completions（SSE）
```

| 能力 | 状态 |
| --- | --- |
| 登录（账号密码 + 短信） | ✅ 真机通过 |
| 集群身份 / 模型服务授权状态 | ✅ 真机 + 本机实测 |
| 自动取 key（activity → 兜底 query） | ✅ 真机（43 字符 `sk-`，33 个模型） |
| 模型列表 / 选择（底部面板，可滚动） | ✅ 真机 |
| 流式对话出字 | ✅ **真机验证**（`SCNet-Max`，OpenAI 兼容 SSE） |
| 智能体服务通道（`aiagent-router`） | ✅ 真机 |
| 附件上传（OSS 直传，智能体可读） | ✅ 真机端到端 |
| 领域场景（同步桌面端 7 类 32 项） | ✅ 真机 |
| 插件市场（连接器 13617 / 技能 17792） | ✅ 真机 |
| 文字识别 OCR（12 种类型） | ✅ 真机自检 |
| 作业面（集群/队列/配额/作业） | ✅ 真机真实数据 |
| 作业提交（校验 + sbatch 预览） | 🟡 代码完成，默认 dry-run，待真机验 |
| 文件/日志浏览 | 🟡 代码完成，契约已 curl 验，待真机验 |
| 主题（6 套，含 SCNet 红）+ 三档字号 + 中英 | ✅ 真机 |
| 会话列表 / 历史浏览（只读） | ✅ 真机通过（30 条） |
| 停止生成（保留已出部分，不崩） | ✅ 真机验证 |
| UI（移动端布局 + 抽屉 + 底部输入） | ✅ 已装机验证 |

真机验证记录（<HarmonyOS 测试机> / HarmonyOS 7.0.0.111 / API 26，2026-11-09 12:4x）：
出字 ✅（`SCNet-Max`，"收到"）、停止 ✅（截断在中途且不崩）、402 文案 ✅
（切到 `GLM-5.3-Flash` 显示"该模型需要余额…改用 SCNet-Max"）、重启保持登录与模型选择 ✅。

> **模型分两类，别踩坑**：`/models` 返回 33 个 id 里，只有 **`SCNet-Max`** 是平台自营、
> 不扣余额；其余 32 个是上游付费模型，账号余额为 0 时一律
> `402 Insufficient Balance`（包括 activity key 接口回带的 `MiniMax-M2.5` —— 那个字段
> 只是"活动推荐模型"，不代表免费）。所以默认模型固定 `SCNet-Max`
> （`Store.DEFAULT_MODEL`），与隔壁 `scnet-cli` 的 `pickDefaultModel()` 一致。
>
> 调试提示：协议问题不必装机。`scripts/probe.sh` 用桌面客户端里的活体 `accessToken`
> 直接打平台与网关接口，几秒一轮。

## 产物与发布（v0.4.1）

Bundle name：`cn.scnet.hmos`（**v0.4.1**，versionCode 6，minAPI 26）。

产物（`scripts/make-release.sh` 一次全出，落到 `dist/release/v<version>/`）：

| 文件 | 大小 | 说明 |
| --- | --- | --- |
| `scnet-agent-0.4.1-release-signed.hap` | 830 KB | **推荐**，release 构建 + 调试证书签名 |
| `scnet-agent-0.4.1-release-unsigned.hap` | 781 KB | 自签用 |
| `scnet-agent-0.4.1-debug-signed.hap` / `-debug-unsigned.hap` | 1.8 MB | debug 构建（带符号） |
| `scnet-agent-android-0.4.1.apk` | 177 KB | **Android 原生版**（功能对齐 HAP） |
| `SHA256SUMS.txt` | — | `sha256sum -c` 校验 |

已发布：[`v0.4.1` Releases](https://github.com/lql341/scnet-lite-harmonyos/releases/tag/v0.4.1)
（HAP 为 debug 证书签名，profile 的 `device-ids` 只含作者设备，别人装不上 —— 自己构建+签名）。

### Android（原生版，功能对齐）

`android/` 是**原生 Android 实现**（Java + 框架控件，不用 Gradle / AndroidX / Compose），
把 HarmonyOS 版的业务逻辑与 11 个页面重写了一遍：登录、双通道流式对话、Markdown、本地会话、
场景、附件上传、插件市场、AI 社区、OCR/文档解析、作业面（列表/详情/日志/文件/提交/取消）、
8 套配色 + 深色 + 中英。

| 项 | 值 |
| --- | --- |
| 产物 | `dist/android/scnet-agent-android-0.4.1.apk` |
| 体积 | 177 KB（dex 约 250 KB，无三方运行时） |
| minSdk / target | 24 / 34 |
| 构建 | `ANDROID_HOME=~/android-sdk scripts/build-apk.sh`（aapt2 → javac → d8 → zipalign → apksigner，约 8 s） |
| 自检 | `scripts/test-android.sh` 43/43（Markdown / SSE / 上下文裁剪 / HMAC） |

实现映射（ArkTS → Java）与剩余工作见 [`docs/APK-ASSESSMENT.md` §9](docs/APK-ASSESSMENT.md)。

## 旧版说明（v0.1.0 MVP，已被上面取代）

| 能力 | 状态 |
| --- | --- |
| 流式对话（SSE 增量渲染，含 `reasoning_content`） | ✅ |
| 模型切换（内置 11 个网关模型） | ✅ |
| API Key / Base URL 设置，本地 preferences 持久化 | ✅ |
| 停止生成 | ✅ |
| 账号密码登录 | ❌ |
| 作业/队列/文件 | ❌ |
| 多会话、PDF 预览 | ❌ |

## 构建

需要 HarmonyOS Command Line Tools（本仓库在 `26.0.0.865` / SDK API 26 / hvigor 6.26.9 上验证）：

```bash
CLT="$HOME/opt/apps/harmonyos/26.0.0.865/command-line-tools"
DEVECO_SDK_HOME="$CLT/sdk" "$CLT/hvigor/bin/hvigorw" assembleHap \
  --mode module -p product=default -p buildMode=debug --no-daemon
```

两个已知坑：

- `DEVECO_SDK_HOME` 指向 `<CLT>/sdk`，不是 `sdk/default`；
- API 26 起 `compatibleSdkVersion` 写 `"26.0.0"`，不再带 `(26)` 后缀。

## 签名

`build-profile.json5` 里 `signingConfigs` 为空，hvigor 会跳过签名。两条路：

1. **华为真机**：DevEco Studio → Project Structure → Signing Configs 自动生成（需登录华为账号），
   或从 AGC 下载证书 + profile（profile 里的 bundleName 必须是 `cn.scnet.hmos`）。
   把材料放到 `signing/`，然后 `scripts/sign.sh`。
2. **OpenHarmony 设备 / 模拟器**：用 SDK 自带的
   `sdk/default/openharmony/toolchains/lib/{hap-sign-tool.jar,OpenHarmony.p12,UnsgnedDebugProfileTemplate.json}`
   走 `generate-keypair → generate-csr → generate-app-cert → sign-profile → sign-app`，
   再把 keystore/profile 填回 `signingConfigs`。

```bash
scripts/check-signing.sh        # 先验 keystore / .cer / .p7b 是否同一把钥匙
scripts/sign.sh                 # → entry-default-signed.hap
scripts/sign.sh --install       # 顺便 hdc install -r
```

签名材料放在 `~/Downloads/scnet-hmos/`（仓库里 `signing` 是指向它的软链，git-ignored）。

安装：`hdc install -r entry/build/default/outputs/default/entry-default-signed.hap`。

## 接口契约（实测）

```bash
GET  https://api.scnet.cn/api/gw/v1/models              -H "Authorization: Bearer <key>"
POST https://api.scnet.cn/api/gw/v1/chat/completions    -H "Authorization: Bearer <key>" \
     -d '{"model":"glm-5.3-flash","stream":true,"messages":[{"role":"user","content":"hi"}]}'
```

- 响应是逐行 `data: {...}`，增量在 `choices[0].delta.{content,reasoning_content}`；
- 网关 key 与网页登录态 `accessToken` 不是同一套（后者打 `api/llm/v1` 返回 401）。

Key 目前需手动粘贴，只存本机 preferences，不代登录、不上传。

## 路线

1. 原生登录（验证码/短信链路）替代手填 key。
2. 作业面：OpenAPI（AK/SK）→ `jobs.list/submit/cancel`。
3. 多会话持久化 + 会话列表。
4. 文件与 PDF：`@ohos.file` + 系统预览。

## 交接

接手继续开发请先读 [`HANDOFF.md`](HANDOFF.md)：项目边界、构建/签名命令、已踩的坑、接口契约、
待办拆解（登录 / 作业面 / 多会话 / PDF）与验证清单都在里面。

## 免责

非官方项目，与曙光智算 / 国家超算互联网无隶属关系。不含厂商代码与二进制。
