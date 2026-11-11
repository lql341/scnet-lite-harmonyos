# SCNet Agent 0.7.1 (HarmonyOS + 原生 Android)

> UI 对齐**全部收尾**：OCR 结果卡、插件市场（三段分组）、AI 社区、内嵌 Web 页也按 HAP 对齐。
> 至此 11 个页面 + 4 个附属页全部以 HAP 为基准；HAP 与 APK 版本同步。

## 本版 Android 改动

| 页面 | 对齐点 |
| --- | --- |
| OCR 结果卡 | 头部「识别结果 N 行」+ `复制`（点后变「已复制」1.5s）+ `发送到对话`；正文独立卡、可选中复制 |
| 插件市场 | 顶栏 `插件` + 副标题；列表改 HAP 三段分组：**精选（suggestType=1）/ 推荐（2）/ 社区**，卡片含精选徽标、作者·浏览·下载·分类 |
| AI 社区 | 顶栏 `AI 社区` + 副标题 + 右上 `刷新`；卡片含 36px 头像、`外链/三方托管/平台构建` 徽标、描述 3 行、右下 `打开 ›` |
| 内嵌 Web 页 | 顶栏 `‹ 标题 / host` + 右侧 `⟳` 刷新 + 顶部 2px 加载进度条（HAP 同款） |

## HAP

ArkTS 侧无功能改动，版本号与 APK 同步为 0.7.1（51 条测试全绿）。

## 产物

| 文件 | 大小 |
| --- | --- |
| `scnet-agent-android-0.7.1.apk` | 205 691 B |
| `scnet-agent-0.7.1-release-signed.hap` | 834 KB |
| `scnet-agent-0.7.1-release-unsigned.hap` | 786 KB |
| `scnet-agent-0.7.1-debug-signed/unsigned.hap` | 1.8 MB |

## 测试

- HAP：Markdown 30 / SSE 10 / 裁剪 13 / HMAC 8 = **51 条全绿**
- Android：同向量 **46 条全绿**
