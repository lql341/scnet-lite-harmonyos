# RELEASE — 怎么打一套可发布的物料

一条命令，全部产物落到 `dist/release/v<version>/`（git-ignored，走 GitHub Releases）：

```bash
. ~/opt/module-init.sh && module load harmonyos jdk
export ANDROID_HOME=/tmp/asdk/sdk        # 可选：打了 Android APK 才需要
scripts/make-release.sh                  # HAP（debug+release）+ APK + SHA256SUMS
scripts/make-release.sh --upload         # 顺带 gh release create/upload
```

脚本做的事：

1. 从 `AppScope/app.json5` 读 `versionName` / `versionCode`（**先改这里**，只改一处）；
2. 对 `MODES`（默认 `debug release`）逐个 `hvigorw clean` + `assembleHap`，
   留一份未签名 HAP，再 `scripts/sign.sh` 出已签名 HAP；
3. 用 `hap-sign-tool verify-app` 验签（Digest + 证书链 + profile）；
4. 有 Android SDK 时跑 `scripts/build-apk.sh` 出 APK（`SKIP_APK=1` 可跳过）；
5. 生成 `SHA256SUMS.txt`。

产物命名：

```
scnet-agent-<ver>-<buildMode>-unsigned.hap
scnet-agent-<ver>-<buildMode>-signed.hap
scnet-agent-webview-<apkVer>-webview.apk
SHA256SUMS.txt
```

## 发版前检查

- [ ] `AppScope/app.json5` 版本号已加一（`versionCode` 是整数，必须递增）
- [ ] `scripts/check-signing.sh` PASS（keystore ↔ .cer ↔ .p7b 是一把钥匙）
- [ ] `scripts/test.sh` 51/51
- [ ] 真机回归：`docs/VERIFY.md` 至少跑「登录 / 出字 / 停止 / 作业页」
- [ ] 写发版说明 `docs/RELEASE-<ver>.md`（`--upload` 会拿它当 `--notes-file`）
- [ ] 仓库里没有签名材料（`git status` 不应出现 `*.p12/*.cer/*.p7b`）

## 手动等价命令（脚本坏了的时候）

```bash
CLT=~/opt/apps/harmonyos/26.0.0.865/command-line-tools
HV=$CLT/hvigor/bin/hvigorw
export DEVECO_SDK_HOME=$CLT/sdk

$HV clean --no-daemon
$HV assembleHap --mode module -p product=default -p buildMode=release --no-daemon
scripts/sign.sh                      # → entry/build/default/outputs/default/entry-default-signed.hap

java -jar $CLT/sdk/default/openharmony/toolchains/lib/hap-sign-tool.jar verify-app \
  -inFile entry/build/default/outputs/default/entry-default-signed.hap \
  -outCertChain /tmp/c.cer -outProfile /tmp/p.p7b
```

## 已知限制

- **签名是调试证书**：profile 的 `device-ids` 只含作者设备 UDID，别人装不上（`9568322`）。
  对外分发要先走 AGC 正式证书 / 发布 profile，或让用户自签。
- `buildMode=release` 也走 debug profile 签名 —— 华为侧目前不校验 buildMode，
  但真机安装仍受 `device-ids` 限制。
- 本机无设备时只能做「构建 + 验签 + 结构检查」，装机回归必须接 `hdc`。
