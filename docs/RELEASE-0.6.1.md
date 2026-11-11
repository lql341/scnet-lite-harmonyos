# SCNet Agent 0.6.1 (HarmonyOS + 原生 Android)

> 这一版做两件事：**HAP 的富文本修好**（此前图片显示成 `img`），
> **Android 的 UI 按 HAP 收敛**（表格、引用、标题、输入区三 chip）。

## HarmonyOS（HAP）富文本

| 项 | 之前 | 现在 |
| --- | --- | --- |
| `[img](oss:///…)` 平台图片 | ❌ 显示成 `img` 文本 | ✅ `oss:///` → `https://oss.ksai.scnet.cn:58003/scnet-public-resources/…` 渲染 |
| `![alt](https://…)` / 裸图片链接 | ❌ | ✅ |
| `~~删除线~~` | ❌ 原样 | ✅ 删除线 |
| `- [ ]` / `- [x]` | ❌ `[ ]` 原样 | ✅ ☐ / ☑ |
| `[文字](url)` | ❌ 只留文字 | ✅ accent 下划线（可辨识） |
| 段落内夹的图片 | ❌ | ✅（段落里也能切出图片块） |

单测：Markdown 30 / SSE 10 / 上下文裁剪 13 / HMAC 8，共 **51 条全绿**。

## Android（UI 按 HAP 收敛）

| 元素 | Android 之前 | 现在（= HAP） |
| --- | --- | --- |
| 表格 | 真表格 + 横向滚动 | **卡片式**：表头一行浅底，每行「首列标题 + 键:值」 |
| 引用 | 左侧 accent 实色条 | 左侧 `accentSoft` 浅条 |
| H1 | 无装饰 | 左侧 accent 色条 |
| 列表 | `•` 字符 | 5px 圆点（无序）/ `1.` 序号（有序），textFaint |
| 输入区 | `＋ [输入] ↑` | `＋ / 场景 ▾ / 当前通道 ▾ / ↑`，空输入时发送键半透明；底部「内容由 AI 生成，请自行核对」 |

顺带保留 Android 已有的富文本能力（删除线、任务列表、可点链接、H6 分级字号）。

## 产物

| 文件 | 大小 |
| --- | --- |
| `scnet-agent-android-0.6.1.apk` | 193 403 B |
| `scnet-agent-0.6.1-release-signed.hap` | 830 KB |
| `scnet-agent-0.6.1-release-unsigned.hap` | 781 KB |
| `scnet-agent-0.6.1-debug-signed/unsigned.hap` | 1.8 MB |

## 校验

```bash
sha256sum -c SHA256SUMS.txt
```
