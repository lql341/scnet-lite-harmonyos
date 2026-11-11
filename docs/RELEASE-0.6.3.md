# SCNet Agent 0.6.3 (HarmonyOS + 原生 Android)

> **HAP 富文本修好**（此前模型返回的平台图片显示成 `img` 文本），
> **Android 的 UI 按 HAP 逐项对齐**（真机双端截图比对）。
> 以 **HAP 为准**。

## HarmonyOS（HAP）

| 项 | 之前 | 现在 |
| --- | --- | --- |
| `[img](oss:///…)` 平台图片 | ❌ 显示成 `img` | ✅ 映射 `https://oss.ksai.scnet.cn:58003/scnet-public-resources/…` 渲染 |
| `![alt](https://…)` / 裸图片链接 | ❌ | ✅ |
| `~~删除线~~` | ❌ 原样 | ✅ |
| `- [ ]` / `- [x]` | ❌ `[ ]` 原样 | ✅ ☐ / ☑ |
| `[文字](url)` | ❌ 只留文字 | ✅ accent 下划线 |

## Android（UI 对齐 HAP）

顶栏状态去掉模型名、输入框改「发消息…」、输入区三 chip（＋/场景/当前通道）、
底注改「内容由 AI 生成，请自行核对」、消息来源标注移到气泡上方、
H1 左侧色条、表格改**卡片式**、引用条改 `accentSoft`、列表改 5px 圆点、
抽屉头顶部布局、新对话靠左、**服务入口改 4 张独立卡片**、
本机会话带数量 + `N 条 · 模型` + ✕、平台历史带数量 + `状态 · MM-DD` + 绿点、
退出登录改浅红底按钮、去掉抽屉里多余的「设置」行（点头像进设置）。

> 比对中顺带修掉一个崩溃：会话行去掉 `›` 后按索引取控件触发 `ClassCastException`
> （被应用内崩溃兜底接住并显示堆栈），改为按 tag 查找。

## 产物

| 文件 | 大小 |
| --- | --- |
| `scnet-agent-android-0.6.3.apk` | 193 403 B |
| `scnet-agent-0.6.3-release-signed.hap` | 833 KB |
| `scnet-agent-0.6.3-release-unsigned.hap` | 785 KB |
| `scnet-agent-0.6.3-debug-signed/unsigned.hap` | 1.8 MB |

## 校验

```bash
sha256sum -c SHA256SUMS.txt
```
