# SCNet Agent 0.7.0 (HarmonyOS + 原生 Android)

> **UI 对齐收尾版**：把剩下的内页（模型面板 / 场景面板 / 登录页）也对齐 HAP，
> 至此 11 个页面的 UI 全部以 HAP 为基准。HAP 与 APK 版本同步。

## 本版 Android 改动

| 页面 | 对齐点 |
| --- | --- |
| 模型面板 | 分组标题带副标题（`智能体服务 · 平台运行时，领域任务由服务端路由` / `模型 · 网关 OpenAI 兼容`）、免费徽标、搜索、选中态 |
| 场景面板 | 独立弹层：标题 + `选一个领域任务，直接带着指令开始` + ✕；卡片式条目（标题 / 摘要 2 行 / 附件徽标 / ›） |
| 登录页 | 68px 圆角图标 + `SCNet 智能体` + `国家超算互联网 · 科研计算助手`；分段 Tab（账号密码 / 短信验证）；**带 label 的浅底输入框**；`登录` / `登录 / 注册`；协议勾选；白卡容器 |

顺带修复：
- 登录页字段容器改用 map 保存（避免 `setTag(null)` 导致 `addView(null)` 崩溃）
- 崩溃捕获弹窗确认可用（上一版残留弹窗就是它拦下来的）

## HAP

ArkTS 侧本版无功能改动（0.6.3 已完成 oss 图片 / 删除线 / 任务列表 / 链接），
版本号与 APK 同步为 0.7.0。

## 产物

| 文件 | 大小 |
| --- | --- |
| `scnet-agent-android-0.7.0.apk` | 205 691 B |
| `scnet-agent-0.7.0-release-signed.hap` | 834 KB |
| `scnet-agent-0.7.0-release-unsigned.hap` | 786 KB |
| `scnet-agent-0.7.0-debug-signed/unsigned.hap` | 1.8 MB |

## 测试

- HAP：Markdown 30 / SSE 10 / 裁剪 13 / HMAC 8 = **51 条全绿**
- Android：Markdown / SSE / 裁剪 / HMAC = **46 条全绿**
