# SCNet Agent 0.3.1 (HarmonyOS + Android)

> 非官方、从零重写的 SCNet 移动端。**0.3.1 不是功能版本**：ArkTS 业务代码与 0.3.0 一致，
> 主要是补齐发布物料（release 构建 + 校验和）和新增 Android WebView 壳。

## 本次变化

### HarmonyOS（versionCode 4 / versionName 0.3.1）

- 同一个版本同时提供 **debug / release** 两种构建模式 × **未签名 / 已签名** 两种产物：

  | 文件 | 大小 | 说明 |
  | --- | --- | --- |
  | `scnet-agent-0.3.1-release-signed.hap` | 830 KB | **推荐**，release 构建 + 调试证书签名 |
  | `scnet-agent-0.3.1-release-unsigned.hap` | 781 KB | 自签用（release 构建） |
  | `scnet-agent-0.3.1-debug-signed.hap` | 1.8 MB | debug 构建 + 调试证书签名（带符号/日志） |
  | `scnet-agent-0.3.1-debug-unsigned.hap` | 1.8 MB | 自签用（debug 构建） |

- 新增 `scripts/make-release.sh`：一条命令重建整套物料（构建 → 签名 → 验签 → 出 SHA256SUMS）。
- release 构建关闭了混淆（`entry/build-profile.json5` 里 `obfuscation.enable=false`），
  与 debug 构建行为一致，只是去掉调试符号。

### Android（`scnet-agent-webview-0.2.0-webview.apk`，49 KB）

WebView 壳，加载平台自带移动适配的 Web 端（`/ui/chatbot`）。这一版补上：

- 登录态持久化：`onPause`/`onDestroy` 时 flush cookie，杀进程不用重登
- **附件上传**：`onShowFileChooser` → 系统文件选择器（图片/PDF/Office/文本/压缩包，可多选）
- **文件下载**：`DownloadListener` → `DownloadManager`，自动带 cookie
- 顶部进度条、转屏保状态、返回键回退 Web 历史
- 打包改为自动选最新 build-tools（34.0.0 的 d8 对非静态内部类会 NPE，35.0.0 正常）

⚠️ 壳里的功能等于平台 Web 端的手机版：对话/会话/文档解析/OCR/插件市场/作业面都在 Web 端里，
**但作业面、OCR 等没有原生入口**；完整差异与本机原生重写的工作量见
[`docs/APK-ASSESSMENT.md`](https://github.com/lql341/scnet-lite-harmonyos/blob/main/docs/APK-ASSESSMENT.md) §8。

## 安装

HarmonyOS（需要 profile 里的 UDID，见下方「已知限制」）：

```bash
hdc install scnet-agent-0.3.1-release-signed.hap
```

Android（`minSdk 24`，无需额外权限）：

```bash
adb install scnet-agent-webview-0.2.0-webview.apk
```

## 已知限制

- HAP 是 **debug 证书签名**：profile 的 `device-ids` 只有作者设备的 UDID，
  **别的设备装不上**（报 `9568322`）。要自己装请按 README「构建 / 签名」自签一份。
- Android APK 是 **Android debug keystore 签名**，仅用于自装；上架需换正式 keystore。
- 两个包都已在本机做签名/结构校验（`hap-sign-tool verify-app`、`apksigner verify`、`aapt2 dump badging`），
  **但 0.3.1 尚未在真机上回归**（本机当前无 `hdc` 设备）。

## 校验

```bash
sha256sum -c SHA256SUMS.txt
```

- 功能清单：[`docs/FEATURES.md`](https://github.com/lql341/scnet-lite-harmonyos/blob/main/docs/FEATURES.md)
- 协议与踩过的坑：[`docs/PROTOCOL.md`](https://github.com/lql341/scnet-lite-harmonyos/blob/main/docs/PROTOCOL.md)
- 发布流程：[`docs/RELEASE.md`](https://github.com/lql341/scnet-lite-harmonyos/blob/main/docs/RELEASE.md)
