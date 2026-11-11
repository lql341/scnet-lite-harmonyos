# PRIVACY / 脱敏约定

> 本仓库已转为**公开**。以下内容**永远不能**出现在仓库里（含提交历史）。

## 禁止提交

| 类别 | 例子 | 处置 |
| --- | --- | --- |
| 签名材料 | `*.p12` / `*.cer` / `*.p7b` / `signing.env` | `.gitignore` 已排除；只在 `~/Downloads/scnet-hmos/` |
| 平台凭据 | `accessToken` / `jsessionid` / 网关 `sk-…` / AK·SK | 只存设备本地（preferences / 日志脱敏） |
| 账号标识 | 用户 ID、集群账号 ID、手机号、真实姓名 | 文档里写占位符：`<用户ID>` / `<集群账号ID>` / `<用户名>` |
| 设备标识 | 设备 UDID、`hdc`/`adb` 序列号 | 写 `<设备UDID>` / `<adb序列号>` |
| 内网信息 | 局域网 IP / 端口、家目录绝对路径 | 写 `<局域网IP:端口>` / `/public/home/<用户名>` |

## 本地开发时

- 探针 `scripts/probe.sh` 从 `~/.config/scnet-client/config.json` 读活体凭据，**不落库**；
- 联调 mock（`scripts/mock-platform.py`）里的 key/账号都是假的（`sk-` + 一串 `m`）；
- 真机日志里的 token 一律 `Http.mask()` 打码（只留前 6 位 + 长度）。

## 发布前检查

```bash
# 1) 有没有敏感串被带进来
git grep -nE "eyJhbGciOi|jsessionid=[A-Za-z0-9]{20,}|sk-[A-Za-z0-9]{30,}" || echo "clean"
# 2) 有没有签名材料
git ls-files | grep -E "\.(p12|cer|p7b)$" || echo "clean"
# 3) 有没有真实账号/设备标识
git grep -nE "11224910962|427416191724683264|01EB73B3|192\.168\." || echo "clean"
```

三条都输出 `clean` 才能发版。
