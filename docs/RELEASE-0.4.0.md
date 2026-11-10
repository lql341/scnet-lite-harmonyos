# SCNet Agent 0.4.0 (HarmonyOS + **原生 Android**)

> 这一版的重点是 **Android 原生版**：不是 WebView 壳，而是把 HarmonyOS 版的业务逻辑与 11 个页面
> 用 Java + 框架控件重写了一遍，功能对齐，APK 只有 **165 KB**。

## Android（`scnet-agent-android-0.4.0.apk`，minSdk 24）

| 能力 | 状态 |
| --- | --- |
| 账号密码 / 短信验证码登录、登录态持久化 | ✅ |
| 集群身份 → 模型服务授权 → 自动取网关 key（33 模型） | ✅ |
| 双通道对话：平台智能体（v2 SSE）+ 网关 LLM（OpenAI 兼容） | ✅ |
| 流式出字、停止（智能体通道会真停服务端任务）、进度文案 | ✅ |
| Markdown：标题/列表/引用/代码块（复制）/表格/行内样式 | ✅ |
| 长按复制、上下文裁剪（24k 字符）、会话自动标题 | ✅ |
| 本地多会话（重命名/删除）+ 平台历史（只读） | ✅ |
| 首页场景（7 类 32 项，`scenarios.json` 内置）+ 推荐问题 | ✅ |
| 附件上传（OSS 预签名直传，50+ 扩展名） | ✅ |
| 自定义模型服务（7 个预设可手填 baseUrl/key/model） | ✅ |
| 插件市场（连接器 13 617 / 技能 17 792，搜索+排序+详情） | ✅ |
| AI 社区（精选智能体，内嵌 Web + cookie 注入） | ✅ |
| OCR 12 种类型 + 文档解析（DOC_PARING）+ 格式转换 | ✅ |
| 作业面：13 集群、队列空闲核、配额、列表、详情、日志、文件浏览、提交、取消 | ✅ |
| 8 套配色 + 深色模式 + 三档字号 + 中英切换 + 头像 | ✅ |
| AK/SK 配置、集群切换、关于页 | ✅ |

**验证到哪一步**（Android 11 / API 30 模拟器，2026-11-11）：

- ✅ 冷启动 / 登录页 / 主界面 / 抽屉 / 本地会话持久化 / Markdown（表格+代码块）/ 深色模式 /
  设置页 / 作业页引导 / 空态与错误卡 / 覆盖安装升级
- ✅ 核心逻辑单测 43/43（Markdown / SSE / 上下文裁剪 / HMAC）
- ❌ **真实账号登录、流式出字、作业提交**需要真机 + 真实账号，未验证

模拟器上抓出的 3 个 bug 已修：签名 keystore 每次变（升级失败）、底部面板高度为 0、
401 回调在后台线程动 UI。

**与 HarmonyOS 版的差异**（都是产品决定，不是缺失）：

- 语音输入：按需求取消
- 应用商城入口：`/ui/mall` 未做移动适配，已移除
- 图形验证码输入 UI：平台平时不要求，只给文案提示
- 检查更新：只做「打开 GitHub Releases」，不做匿名版本比对（仓库是 private）

构建方式（不用 Gradle，8 秒出包）：

```bash
ANDROID_HOME=~/android-sdk scripts/build-apk.sh
# → dist/android/scnet-agent-android-0.4.0.apk
```

## HarmonyOS（versionCode 5 / versionName 0.4.0）

ArkTS 业务代码与 0.3.1 一致，仅版本号跟随发布。产物仍是 debug/release × 未签名/已签名：

| 文件 | 大小 |
| --- | --- |
| `scnet-agent-0.4.0-release-signed.hap` | 830 KB |
| `scnet-agent-0.4.0-release-unsigned.hap` | 781 KB |
| `scnet-agent-0.4.0-debug-signed.hap` | 1.8 MB |
| `scnet-agent-0.4.0-debug-unsigned.hap` | 1.76 MB |

## 安装

```bash
# HarmonyOS（profile 的 device-ids 只含作者设备，别人装不上）
hdc install scnet-agent-0.4.0-release-signed.hap

# Android
adb install scnet-agent-android-0.4.0.apk
```

## 校验

```bash
sha256sum -c SHA256SUMS.txt
```

- 功能清单 [`docs/FEATURES.md`](https://github.com/lql341/scnet-lite-harmonyos/blob/main/docs/FEATURES.md)
- Android 实现映射与剩余工作 [`docs/APK-ASSESSMENT.md` §9](https://github.com/lql341/scnet-lite-harmonyos/blob/main/docs/APK-ASSESSMENT.md)
- 发版流程 [`docs/RELEASE.md`](https://github.com/lql341/scnet-lite-harmonyos/blob/main/docs/RELEASE.md)
