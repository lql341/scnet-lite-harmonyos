# SIGNING — 签名材料清单与换机迁移

签名材料**不在仓库里**（`.gitignore` 排除 `*.p12/*.cer/*.p7b` 和 `signing`），
仓库里 `signing` 是指向 `~/Downloads/scnet-hmos/` 的软链。

---

## 1. 必须带走的东西（4 个文件 + 1 个密码表）

| 文件 | 大小 | sha256 前 16 位 | 丢了会怎样 |
| --- | --- | --- | --- |
| `scnet.hmos.debug.p12` | 1032 B | `1bdf9cdefd17dc01` | **私钥，丢了必须重新申请证书**（踩过一次） |
| `scnet.hmos.debug.cer` | 2914 B | `a8239b263d310cf9` | 可从 AGC 重新下载 |
| `scnet.hmos.debug.p7b` | 4161 B | `8ff03107c8d6b706` | 可重新签发（需勾 UDID） |
| `signing.env` | 536 B | `b149df6d1fa043c1` | 密码丢了 = 私钥废掉（**这条最容易丢**） |
| `signing.env.example` | 620 B | — | 模板，无所谓 |

密钥别名：`scnet-hmos-debug`（密码在 `signing.env` 的 `SIGN_KEY_PWD` / `SIGN_STORE_PWD`）。

## 2. 这些材料绑定的是什么

```
bundleName : cn.scnet.hmos
证书主体   : C=CN, O=开发者, OU=<开发者ID>, CN=开发者(…)\,Development
证书链     : Huawei CBG Root CA G2 → Huawei CBG Developer Relations CA G2 → 上面这张
profile    : type=debug, bundle-name=cn.scnet.hmos
device-ids : <设备UDID>   ← <HarmonyOS 测试机>
有效期     : 2026-11-08 → 2027-11-08
```

**改 bundleName 必须重签**；**换设备必须把新 UDID 加进 profile 并重新下载 `.p7b`**。

> 当前场景是**换电脑、手机不变**（<HarmonyOS 测试机> 继续用）→ UDID 不变，**`.p7b` 不用重签**，
> 只要把 4 个文件拷过去 + `check-signing.sh` PASS 即可装同一台手机。

## 2.5 已经打好的迁移包（本机）

```
~/Downloads/scnet-hmos-transfer/
├── scnet-hmos-signing.tar.gz      6666 B  sha256 见 MANIFEST（明文，方便 U 盘）
├── scnet-hmos-signing.tar.gz.enc  6688 B  AES-256（PBKDF2 200k），口令在 .passphrase
├── .passphrase                    600     24 位随机口令
└── MANIFEST.txt                   文件明细 + sha256 + 恢复步骤
```

解密解包：

```bash
openssl enc -d -aes-256-cbc -pbkdf2 -iter 200000 \
  -in scnet-hmos-signing.tar.gz.enc -out bag.tgz -pass pass:"$(cat .passphrase)"
mkdir -p ~/Downloads/scnet-hmos && tar -xzf bag.tgz -C ~/Downloads/scnet-hmos
chmod 600 ~/Downloads/scnet-hmos/signing.env ~/Downloads/scnet-hmos/*.p12
```

`signing.env` 里的路径用 `${SIGNING_DIR:-$HOME/Downloads/scnet-hmos}` 推导，**换机器不用改文件**；
放别处就 `export SIGNING_DIR=/path/to/dir`。

## 3. 换机迁移（3 条命令）

```bash
# 1. 拷过去（U 盘 / scp / 加密压缩包都行）
scp -r ~/Downloads/scnet-hmos you@newhost:~/Downloads/

# 2. 权限 + 软链（仓库里的 signing/ 指向它）
chmod 600 ~/Downloads/scnet-hmos/signing.env ~/Downloads/scnet-hmos/scnet.hmos.debug.p12
ln -sfn ~/Downloads/scnet-hmos <repo>/signing

# 3. 校验三者是否配对（不配对就别浪费时间签名）
cd <repo> && ./scripts/check-signing.sh      # 必须 PASS
```

`check-signing.sh` 会做四件事：从 keystore 现生成一份临时 CSR 取公钥、
解析 p7b 里内嵌的 `development-certificate`、拆 `.cer` 证书链、
打印 `profile` 的 bundle / type / device-ids，最后比对三者公钥是否一致。

## 4. 全新签发（材料彻底丢了才走）

```bash
CLT=~/opt/apps/harmonyos/26.0.0.865/command-line-tools
LIB=$CLT/sdk/default/openharmony/toolchains/lib

# 1) 建 key
java -jar $LIB/hap-sign-tool.jar generate-keypair \
  -keyAlias scnet-hmos-debug -keyAlg ECC -keySize NIST-P-256 \
  -keystoreFile ~/Downloads/scnet-hmos/scnet.hmos.debug.p12 \
  -keystorePwd <PW> -keyPwd <PW>

# 2) 出 CSR
java -jar $LIB/hap-sign-tool.jar generate-csr -keyAlias scnet-hmos-debug -keyPwd <PW> \
  -subject "C=CN,O=SCNet,OU=SCNet Lite,CN=scnet.hmos debug" -signAlg SHA256withECDSA \
  -keystoreFile ~/Downloads/scnet-hmos/scnet.hmos.debug.p12 -keystorePwd <PW> \
  -outFile ~/Downloads/scnet-hmos/scnet.hmos.debug.csr

# 3) AGC：证书管理 → 新增调试证书 → 上传 CSR → 下载 .cer
# 4) AGC：Profile → 新增调试 profile → bundle=cn.scnet.hmos + 勾 UDID → 下载 .p7b
# 5) 填 signing.env，跑 check-signing.sh，再 sign.sh
```

> AGC 调试证书有名额限制，旧证书先删再建。

## 5. 不需要带的东西

- 网关 API Key：登录后自动创建（`/acx/llm/api-key/create`），不入库也不入库文件
- 平台 token / cookie：登录态，存在设备 preferences 里
- `hidx`/构建缓存：`.hvigor/`、`entry/build/` 都是产物，重新构建即可

## 6. 常见失败对照

| 报错 | 原因 |
| --- | --- |
| `11013004 Profile cert must a cert chain` | `.cer` 只有叶子证书，用了"从 p7b 抽出来的单张"；要 AGC 下载的完整链 |
| `check-signing.sh` FAIL | keystore 与 p7b 不是一对（换过 key 但没重签证书） |
| 安装报 `9568322` / 权限校验失败 | profile 的 `device-ids` 不含当前设备 UDID |
| `hdc install` 报签名校验失败 | 用了 OpenHarmony 自签材料（华为真机只认 AGC 证书） |
