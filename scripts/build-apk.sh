#!/usr/bin/env bash
# 构建 Android APK（WebView 壳形态）——不依赖 Gradle。
#
# 背景见 docs/APK-ASSESSMENT.md：ArkTS/HAP 无法直接转 APK（面是方舟运行时 + ArkUI），
# 最短可行路径是「WebView 壳 + 平台自带的移动适配 Web 前端」。
#
# 这个脚本证明该路径可落地：只用 Android SDK 的 build-tools 手工打包
# （aapt2 编译资源 → javac → d8 出 dex → zip 合并 → zipalign → apksigner），
# 不需要 Gradle / AGP，CI 里跑得很快。
#
# 用法：
#   scripts/build-apk.sh                 # 输出 dist/android/scnet-agent-webview-*.apk
#   ANDROID_HOME=/path/to/sdk scripts/build-apk.sh
#
# 依赖：Android SDK（platforms;android-34 + build-tools;35.0.0）、JDK 17+。
#       已按 module 规范纳管：`. ~/opt/module-init.sh && module load android-sdk jdk`
# 没装 SDK 时脚本会给出安装命令并退出。
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SRC=$ROOT/android
OUT=${OUT:-$ROOT/dist/android}
PKG=cn.scnet.agent
VER_NAME=${VER_NAME:-0.6.0}
VER_CODE=${VER_CODE:-20}
# DEBUG=1 出可调试包（仅本机联调用：aapt2 --debug-mode → android:debuggable=true）
DEBUG=${DEBUG:-0}
ENTRY=${ENTRY:-https://www.scnet.cn/ui/chatbot/index.html}

die() { printf '[err] %s\n' "$1" >&2; exit 1; }
note() { printf '[..] %s\n' "$1"; }

[[ -d $SRC ]] || die "缺少 $SRC（Android 壳源码目录）"

# ---- 找 SDK ----
SDK=${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}
if [[ -z $SDK || ! -d $SDK/platforms/android-34 ]]; then
  for cand in "$HOME"/opt/apps/android-sdk/* "$HOME/android-sdk" "$HOME/Android/Sdk" \
              /tmp/asdk/sdk /opt/android-sdk /opt/android-sdk/*; do
    [[ -d $cand/platforms/android-34 ]] && SDK=$cand && break
  done
fi
if [[ -z ${SDK:-} || ! -d $SDK/platforms/android-34 ]]; then
  cat >&2 <<'EOF'
[err] 没找到 Android SDK（需要 platforms;android-34 与 build-tools;34.0.0）

  mkdir -p ~/android-sdk/cmdline-tools && cd ~/android-sdk/cmdline-tools
  curl -LO https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip
  unzip -q commandlinetools-linux-*.zip && mv cmdline-tools latest
  export ANDROID_HOME=~/android-sdk
  yes | ./latest/bin/sdkmanager --sdk_root=$ANDROID_HOME --licenses >/dev/null
  ./latest/bin/sdkmanager --sdk_root=$ANDROID_HOME "platforms;android-34" "build-tools;34.0.0"
EOF
  exit 2
fi

# build-tools 取最新一版（34.0.0 的 d8 在部分离线包里会 NPE 到非静态内部类，
# 35.0.0 起正常；只要求 >= 34）
BT=$(ls -d "$SDK"/build-tools/* 2>/dev/null | sort -V | tail -1)
[[ -n $BT ]] || die "缺 build-tools（需要 >= 34.0.0）"
BT_VER=$(basename "$BT")
[[ ${BT_VER%%.*} -ge 34 ]] || die "build-tools $BT_VER 太旧，需要 >= 34.0.0"
PLAT=$SDK/platforms/android-34/android.jar
for tool in aapt2 d8 zipalign apksigner; do
  [[ -x $BT/$tool ]] || die "缺 $BT/$tool"
done
command -v javac >/dev/null || die "需要 JDK（javac）"
command -v keytool >/dev/null || die "需要 JDK（keytool）"

note "SDK  = $SDK"
note "BT   = $BT ($BT_VER)"
note "out  = $OUT"

rm -rf "$OUT" && mkdir -p "$OUT/work/classes" "$OUT/work/dex" "$OUT/work/res"

# ---- 1) 资源 ----
note "1/6 aapt2 compile（资源）"
"$BT/aapt2" compile --dir "$SRC/res" -o "$OUT/work/res"

# ---- 2) 链接（生成未签名 apk + AndroidManifest） ----
note "2/6 aapt2 link（manifest + 资源）"
CLEARTEXT=false
[[ $DEBUG -eq 1 ]] && CLEARTEXT=true   # 联调 mock 用 http
sed -e "s|@VER_NAME@|$VER_NAME|g" -e "s|@VER_CODE@|$VER_CODE|g" \
  -e "s|@CLEARTEXT@|$CLEARTEXT|g" \
  "$SRC/AndroidManifest.xml" > "$OUT/work/AndroidManifest.xml"
AAPT_DEBUG=""
[[ $DEBUG -eq 1 ]] && AAPT_DEBUG="--debug-mode"
"$BT/aapt2" link \
  $AAPT_DEBUG \
  -o "$OUT/work/base.apk" \
  -I "$PLAT" \
  --manifest "$OUT/work/AndroidManifest.xml" \
  --min-sdk-version 24 --target-sdk-version 34 \
  --version-code "$VER_CODE" --version-name "$VER_NAME" \
  "$OUT/work/res"/*.flat --auto-add-overlay

# ---- 3) javac ----
note "3/6 javac"
javac -Xlint:-options --release 8 -classpath "$PLAT" -d "$OUT/work/classes" \
  $(find "$SRC/src" -name '*.java')

# ---- 4) d8 → dex ----
note "4/6 d8（dex）"
"$BT/d8" --lib "$PLAT" --min-api 24 --output "$OUT/work/dex" \
  $(find "$OUT/work/classes" -name '*.class')

# ---- 5) 合并 + align ----
note "5/6 合并 dex + zipalign"
(cd "$OUT/work" && cp base.apk unsigned.apk && zip -q -j unsigned.apk dex/classes.dex)
"$BT/zipalign" -f -p 4 "$OUT/work/unsigned.apk" "$OUT/work/aligned.apk"

# ---- 6) 签名 ----
note "6/6 apksigner（debug keystore）"
# ⚠️ keystore 必须放在稳定路径：放在 $OUT 里会被下次构建删掉，导致每次签名 key 不同、
# 用户无法覆盖升级（INSTALL_FAILED_UPDATE_INCOMPATIBLE）。默认放在 ~/.android 下。
KS=${APK_KEYSTORE:-$HOME/.android/scnet-agent.keystore}
mkdir -p "$(dirname "$KS")"
if [[ ! -f $KS ]]; then
  keytool -genkeypair -keystore "$KS" -storepass android -keypass android \
    -alias androiddebugkey -keyalg RSA -keysize 2048 -validity 10000 \
    -dname "CN=Android Debug,O=Android,C=US" >/dev/null 2>&1
fi
APK=$OUT/scnet-agent-android-$VER_NAME.apk
"$BT/apksigner" sign \
  --ks "$KS" --ks-pass pass:android --key-pass pass:android \
  --ks-key-alias androiddebugkey --min-sdk-version 24 \
  --out "$APK" "$OUT/work/aligned.apk"

"$BT/apksigner" verify --print-certs "$APK" >/dev/null || die "签名校验失败"
unzip -p "$APK" classes.dex >/dev/null 2>&1 || die "APK 里没有 classes.dex"

rm -rf "$OUT/work"
printf '\n[done] %s  (%s bytes)\n' "$APK" "$(stat -c %s "$APK")"
