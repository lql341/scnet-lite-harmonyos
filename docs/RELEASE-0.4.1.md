# SCNet Agent 0.4.1 (HarmonyOS + 原生 Android)

> 这一版把 Android 原生版补到**与 HarmonyOS 版功能一致**（对照表见
> [`docs/PARITY-ANDROID.md`](https://github.com/lql341/scnet-lite-harmonyos/blob/main/docs/PARITY-ANDROID.md)），
> 并给 Android 加上了**崩溃自诊断**（容器里没有 adb 也能把堆栈取出来）。

## Android（`scnet-agent-android-0.4.1.apk`，177 KB）

### 本次补齐的功能（对齐 HAP）

- **首页场景 tab**：服务端 `vibeCodingScenes` × router 推荐问题 → chips（推荐/材料科学/…/文献阅读/学术写作），
  外加「领域场景 ›」打开 7 类 32 项本地目录
- **换一批**：场景问题轮转 3 条
- **会话删除**：本地会话长按 → 重命名 / 删除
- **平台会话重命名**：平台历史长按 → `conversation/rename`
- **长会话窗口化**：默认渲染最近 40 条 + 顶部「加载更早」（对齐 HAP 的 LazyForEach 体验）
- **插件市场**：精选分组（suggestType=1）+ 分页「加载更多」
- **OCR 自检**：内置样图一键跑通用识别（验证 multipart 链路）
- **自定义模型服务**：7 个预设（DeepSeek / Moonshot / 通义 / 智谱 / OpenAI / SiliconFlow / Ollama）
- **设置页「身份」卡**：平台账号 / 集群账号 / 当前集群 / 调度器
- **检查更新 / 作者 / 仓库**三行；头像新增 2 档字母 + 「让智能体生成」入口
- **调试区**：API 基地址（指向自建 mock）、上次崩溃、一键复制诊断

### 崩溃自诊断（这一版的重点）

在 Android 兼容容器（卓易通这类）里没有 adb，闪退等于零信息。现在：

1. 全局捕获未处理异常 → 写 `filesDir/crash.log` + `/Download/scnet-crash.txt`
2. 页面逻辑出错不再闪退，而是把堆栈**直接铺在屏幕上**，带「复制错误信息」按钮
3. 下次启动弹窗显示上次崩溃；设置 → 调试 → 「复制诊断信息」给出
   版本 / 设备 / API 基地址 / 凭据是否就绪 / 上次崩溃

### 验证状态

| 项 | 结果 |
| --- | --- |
| 核心逻辑单测 | ✅ 43/43（Markdown / SSE / 裁剪 / HMAC） |
| 模拟器（Android 11）+ mock 平台 | ✅ 登录态注入、空状态场景 tab、抽屉、会话持久化、Markdown 全要素、深色模式、设置页身份卡、流式出字（SSE 24 字/片）、作业页引导、覆盖安装 |
| 真机 + 真实账号 | ❌ 未做（需要账号；HAP 侧已验证过同一套接口） |

## HarmonyOS（versionCode 6 / versionName 0.4.1）

ArkTS 代码未变，版本号跟随发布：

| 文件 | 大小 |
| --- | --- |
| `scnet-agent-0.4.1-release-signed.hap` | 830 KB |
| `scnet-agent-0.4.1-release-unsigned.hap` | 781 KB |
| `scnet-agent-0.4.1-debug-signed.hap` | 1.8 MB |
| `scnet-agent-0.4.1-debug-unsigned.hap` | 1.76 MB |

## 安装

```bash
# Android（minSdk 24 / target 34）
adb install -r scnet-agent-android-0.4.1.apk

# HarmonyOS（profile 的 device-ids 只含作者设备）
hdc install scnet-agent-0.4.1-release-signed.hap
```

小米/Redmi 上 `adb install` 报 `INSTALL_FAILED_USER_RESTRICTED` 时：开发者选项里打开
「USB 安装 / 通过 USB 安装应用」（需要登录小米账号并插卡），或直接把 APK 传进手机点开装。

## 校验

```bash
sha256sum -c SHA256SUMS.txt
```
