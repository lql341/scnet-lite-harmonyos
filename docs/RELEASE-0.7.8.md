# SCNet Agent 0.7.8 (HarmonyOS + 原生 Android)

> 两个可用性修正：**抽屉不再分块滚动**、**设置页去掉 AK/SK 入口**。

## 1. 抽屉：整块滚动（HAP 修正）

之前 HAP 抽屉里两个列表各自滚动，体验割裂：

| 位置 | 之前 | 现在 |
| --- | --- | --- |
| 本机会话 | `List` + `constraintSize(maxHeight: 190)` → 内部滚动 | 跟随抽屉整体滚动 |
| 平台历史 | `List` + `layoutWeight(1)` → 占满剩余并在内部滚动 | 跟随抽屉整体滚动 |
| 抽屉容器 | `Column`（超出就被裁） | `Scroll` 包一层 `Column` |

Android 侧本来就是「一个 ScrollView 包所有内容」，两端行为一致。

## 2. 设置页去掉「算力密钥（AK/SK）」

AK/SK 是作业功能的配置项，属于开发者/进阶用户才会碰的东西，不该占据设置页首屏。

| 位置 | 处理 |
| --- | --- |
| 设置页 | 移除「算力密钥（AK/SK）」行 |
| 作业页右上 | 保留「算力密钥」入口（用时才点，不打扰） |
| 作业页未配置时 | 保留引导卡「去设置 → 算力服务」+ 重试 |

设置页现在是：头像卡 → 3 行信息 → 自定义模型 → 外观三段 → 检查更新 → 关于 → 退出登录。

## 产物

| 文件 | 大小 |
| --- | --- |
| `scnet-agent-android-0.7.8.apk` | 205 691 B |
| `scnet-agent-0.7.8-release-signed.hap` | 834 KB |
| `scnet-agent-0.7.8-release-unsigned.hap` | 786 KB |

## 测试

- HAP：51 条全绿 · Android：46 条全绿
