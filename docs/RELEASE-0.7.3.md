# SCNet Agent 0.7.3 (HarmonyOS + 原生 Android)

> 仓库已**转为公开**；本版做了一次**全量脱敏**，并统一了「关于 / 检查更新」两端的地址与文案。

## 脱敏（仓库公开前必做）

| 类别 | 处置 |
| --- | --- |
| 用户 ID / 集群账号 ID | → `<用户ID>` / `<集群账号ID>` |
| 证书主体里的真实姓名、开发者 ID | → `开发者` / `<开发者ID>` |
| 设备 UDID / hdc 序列号 / adb 序列号 | → `<设备UDID>` / `<adb序列号>` |
| 局域网 IP:端口 | → `<局域网IP:端口>` |
| 家目录、集群用户名 | → `/public/home/<用户名>` / `<用户名>` |
| 测试机型号 | → `<HarmonyOS 测试机>` / `<Android 测试机>` |

**确认没有凭据泄露**：

- 历史与当前代码里均**不存在**真实 JWT / `jsessionid` / 网关 `sk-` key / AK·SK
- 签名材料（`*.p12` / `*.cer` / `*.p7b` / `signing.env`）**从未入库**（`.gitignore` 一直排除）
- HMAC 单测里的示例用户名换成中性值 `u` 并同步期望摘要（51 条测试仍全绿）

新增 `docs/PRIVACY.md`：禁止提交清单 + 发版前三条件自检命令。

## 「关于 / 检查更新」统一

仓库公开后 `releases/latest` 匿名可访问，所以：

- **检查更新**可直接比对版本并下载（不再需要自定义更新源）
- **关于**弹层：版本号 + 非官方声明 + 作者 + 项目，新增「**查看 Releases**」「作者主页」按钮
- 去掉所有「私有仓库」字样；HAP 与 APK 使用同一套地址

## 产物

| 文件 | 大小 |
| --- | --- |
| `scnet-agent-android-0.7.3.apk` | 205 691 B |
| `scnet-agent-0.7.3-release-signed.hap` | 834 KB |
| `scnet-agent-0.7.3-release-unsigned.hap` | 786 KB |
| `scnet-agent-0.7.3-debug-signed/unsigned.hap` | 1.8 MB |

## 测试

- HAP：51 条全绿 · Android：46 条全绿
