# SCNet Agent 0.7.2 (HarmonyOS + 原生 Android)

> **Android 真机（Xiaomi <Android 测试机> / Android 13）全链路验收通过**。
> 本版修掉真机上发现的唯一数据错位，其余页面观感与 HAP 一致。

## 真机验收结果（2026-11-11，小米 <Android 测试机>）

| 项 | 结果 |
| --- | --- |
| 安装 / 启动 | ✅ `adb install` 成功，登录态自动恢复 |
| 启动链路 | ✅ `current-user-info` → `config/list` → `cluster-user-detail` 全部 200，`cloud: loaded` |
| **真实流式出字** | ✅ 问「只回两个字：收到」→ 收到 `start` → `text-delta 收到` → `text-end` → `history`，界面显示「收到」 |
| 主界面 | ✅ 顶栏「● 网关已就绪」、消息来源在气泡上方、输入区 `＋ / 场景 ▾ / 智能体服务 ▾ / ↑` |
| 作业页 | ✅ 顶栏「‹ 作业 / ⟳ 文件 提交 算力密钥」（AK/SK 未配置时给引导） |
| 设置页 | ✅ 头像卡居中、五行信息（账号 <用户ID> / 集群账号 <集群账号ID> / 集群 华东一区昆山（13 个可选））、外观三组分段、检查更新 0.7.2 |
| 插件市场 | ✅ 真实数据 **13 617 条**、精选分组、卡片信息完整 |
| AI 社区 | ✅ 6 个智能体、来源徽标（外链 / 三方托管 / 平台构建）、「打开 ›」 |
| 文字识别 | ✅ 顶栏「‹ 文字识别 / 支持图片与 PDF」+ 右上「自检」、三模式 chips |

## 本版修复

- **设置页「集群账号」显示成了集群名**：`loadIdentity()` 的下标错位（`out[0]`=集群账号 被写进了「集群」行）。
  已拆成独立控件，真机复验显示 `<集群账号ID>`。

## 产物

| 文件 | 大小 |
| --- | --- |
| `scnet-agent-android-0.7.2.apk` | 205 691 B |
| `scnet-agent-0.7.2-release-signed.hap` | 834 KB |
| `scnet-agent-0.7.2-release-unsigned.hap` | 786 KB |
| `scnet-agent-0.7.2-debug-signed/unsigned.hap` | 1.8 MB |

## 测试

- HAP：51 条全绿 · Android：46 条全绿
