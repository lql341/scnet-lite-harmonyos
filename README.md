# scnet-lite-harmonyos

非官方。用 **ArkTS 从零重写**的 SCNet（国家超算互联网）移动端前端，跑在 HarmonyOS 上，
直接对接 SCNet 模型网关（`https://api.scnet.cn/api/gw/v1`，OpenAI 兼容 + SSE 流式）。

> 这是**重新实现**，不是官方 Android 客户端的移植：官方 APK 是 Flutter 应用
> （`libflutter.so` + AOT `libapp.so`，Dart 3.13.0），源码不可得，AOT 快照也不可能换引擎重跑。
> 因此本仓库不含厂商的任何二进制或产物，只复用公开的 HTTP 接口契约。

## 现状（v0.1.0）

| 能力 | 状态 |
| --- | --- |
| 流式对话（SSE 增量渲染，含 `reasoning_content`） | ✅ |
| 模型切换（内置 11 个网关模型） | ✅ |
| API Key / Base URL 设置，本地 preferences 持久化 | ✅ |
| 停止生成 | ✅ |
| 账号密码登录 | ❌ |
| 作业/队列/文件 | ❌ |
| 多会话、PDF 预览 | ❌ |

Bundle name：`cn.scnet.hmos`（v0.1.0，minAPI 26）。
产物：`entry/build/default/outputs/default/entry-default-unsigned.hap`（约 78 KB）。

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
cp signing/signing.env.example signing/signing.env   # 填 keystore/cer/p7b/密码
scripts/sign.sh                 # → entry-default-signed.hap
scripts/sign.sh --install       # 顺便 hdc install -r
```

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
