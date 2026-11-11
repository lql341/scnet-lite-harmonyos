# SCNet Agent 0.7.6 (HarmonyOS + 原生 Android)

> **移除网关 key 展示**（安全修正）。设置页里的 key 是账号额度凭证，
> 连打码显示（`sk-Mz…Dk=`）也不合适——截图分享会泄露首尾标识。

## 变更

| 位置 | 处理 |
| --- | --- |
| 设置页信息卡 | 删除「网关 key」行（原 6 行 → 5 行：账号 / 集群账号 / 集群 / 当前通道 / 集群调度器） |
| 设置页调试区 | 删除重复的「网关 key」状态行（与信息卡重复） |
| HAP `maskedKey()` | 一并删除，避免以后又把它渲染出来 |

两端同步，截图已确认：设置页不再出现任何 key 片段。

## key 现在存在哪

- 只存在设备本地：`preferences`（`autoGatewayKey`）+ 内存中的 `Http` 层；
- 日志里一律经 `Http.mask()`（只留前 6 位 + 长度），不打印明文；
- 仓库里没有任何 key（见 `docs/PRIVACY.md` 的自检命令）。

## 产物

| 文件 | 大小 |
| --- | --- |
| `scnet-agent-android-0.7.6.apk` | 205 691 B |
| `scnet-agent-0.7.6-release-signed.hap` | 834 KB |
| `scnet-agent-0.7.6-release-unsigned.hap` | 786 KB |

## 测试

- HAP：51 条全绿 · Android：46 条全绿
