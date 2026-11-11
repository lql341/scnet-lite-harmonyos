# SCNet Agent 0.6.0 (HarmonyOS + 原生 Android)

> Android 版这一轮做的是**富文本与平台素材的彻底对齐**：把"模型返回的图片显示不出来"
> 这个卡了很久的问题定位到根因并修掉，同时逐个修掉 Markdown 的边界问题。

## 关键修复：平台图片显示不出来

根因有两层，缺一不可：

```
模型返回： [img](oss:///hpc/beginner-guide/upload-example/1.png)
            ↑ 不是标准图片语法     ↑ 私有协议，浏览器不认识
```

1. 没有 `!` 前缀 → 被当普通链接，只保留文字，屏幕上就是一串 `img`
2. `oss://` 是平台私有协议 → 必须映射成 https

映射规则取自官方桌面客户端（`app.asar` 原函数）：

```js
oss:///path → https://oss.ksai.scnet.cn:58003/scnet-public-resources/path
```

Android 0.6.0 已实现该映射（含 `//`、`/`、`&amp;`、`data:` base64 归一），
并移植了官方同款**私网地址拦截**（拒绝 localhost / 10. / 192.168. / 172.16-31. / 无点主机名）。

> ⚠️ HarmonyOS（HAP）版**尚未修**，仍会把图片显示成 `img` 文本；待同步。

## Markdown 富文本（Android 实测）

| 语法 | 结果 |
| --- | --- |
| `#`~`######` | ✅ 字号分级 |
| `**粗**` `*斜*` `` `码` `` `~~删除~~` | ✅ |
| `- ` / `1. ` / 缩进子项 | ✅ 三级缩进、有序嵌套 |
| `- [ ]` / `- [x]` | ✅ ☐ / ☑ |
| `>` / `> >` | ✅ 合并 + 嵌套缩进 |
| 表格 + `:---:` | ✅ 列宽按内容测量（`1024/2048` 不再折断）、左/中/右对齐 |
| 代码块 | ✅ 语言标签 + 复制；未闭合也渲染（流式） |
| `![alt](https://…)` / 裸图片链接 | ✅ |
| `[img](oss:///…)` | ✅（本次修复） |
| `[文字](url)` / 裸 URL | ✅ 可点击（代码块内不转链接） |
| `$x^2$` 行内公式 | ⛔ 原样显示（无 KaTeX，与 HAP 相同） |
| HTML 标签 | ⛔ 原样显示（不解析，避免注入） |

## 其他 Android 改动

- 流式渲染不再整段重建：块结构没变时只更新最后一个文本控件（长回答不再一顿一顿）
- 服务端 harness 的工具轨迹可视化（`todolist` / `tool-*` → 气泡下方最多 6 行）
- 首轮资源卡片宽容解析（任意帧里的图片/文件 URL 会自动渲染成图片或可点链接）
- 调试钩子：`--es open <page>`、`--ez mdtest`、`--ez mdfile`、`--es convid`、
  `--ez dumphistory`、`--es prefill --ez autosend`；`stream.log` 落盘原始帧

## 产物

| 文件 | 大小 |
| --- | --- |
| `scnet-agent-android-0.6.0.apk` | 193 403 B |
| `scnet-agent-0.6.0-release-signed.hap` | 830 KB |
| `scnet-agent-0.6.0-release-unsigned.hap` | 781 KB |
| `scnet-agent-0.6.0-debug-signed/unsigned.hap` | 1.8 MB |

## 校验

```bash
sha256sum -c SHA256SUMS.txt
```
