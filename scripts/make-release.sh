#!/usr/bin/env bash
# 打一套可发布的物料：HarmonyOS HAP（未签名 + 已签名，debug/release 两种 buildMode）
# 以及（可选）Android WebView 壳 APK。产物落在 dist/release/v<version>/，附 SHA256SUMS.txt。
#
# 用法：
#   scripts/make-release.sh                 # 构建 HAP（debug + release）+ APK（若有 SDK）
#   MODES=release scripts/make-release.sh   # 只打 release buildMode
#   SKIP_APK=1 scripts/make-release.sh      # 只打 HAP
#   scripts/make-release.sh --upload        # 构建后 gh release create/upload
#
# 依赖：JDK（java/javac）、HarmonyOS Command Line Tools、签名材料（signing/signing.env）、
#      Android SDK（可选，见 scripts/build-apk.sh）。
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
CLT=${CLT:-$HOME/opt/apps/harmonyos/26.0.0.865/command-line-tools}
HV=${HV:-$CLT/hvigor/bin/hvigorw}
LIB="$CLT/sdk/default/openharmony/toolchains/lib"
export DEVECO_SDK_HOME=${DEVECO_SDK_HOME:-$CLT/sdk}

MODES=${MODES:-debug release}
SKIP_APK=${SKIP_APK:-0}
UPLOAD=0
[[ "${1:-}" == "--upload" ]] && UPLOAD=1

die() { printf '[err] %s\n' "$1" >&2; exit 1; }
note() { printf '\n[..] %s\n' "$1"; }

command -v java >/dev/null || die "需要 JDK（java）；本机可用 ~/opt/apps/jdk/21.0.13+9/bin"
command -v python3 >/dev/null || die "需要 python3（解析版本号）"

VER=$(python3 - "$ROOT/AppScope/app.json5" <<'PY'
import json,re,sys
src=open(sys.argv[1]).read()
src=re.sub(r'//[^\n]*','',src)
j=json.loads(src)['app']
print(j['versionName'])
PY
)
CODE=$(python3 - "$ROOT/AppScope/app.json5" <<'PY'
import json,re,sys
src=open(sys.argv[1]).read()
src=re.sub(r'//[^\n]*','',src)
print(json.loads(src)['app']['versionCode'])
PY
)

OUT="$ROOT/dist/release/v$VER"
rm -rf "$OUT" && mkdir -p "$OUT"

note "版本 $VER (versionCode $CODE) → $OUT"

# ---- 1) HAP：逐个 buildMode 构建 + 签名 ----
HAPDIR="$ROOT/entry/build/default/outputs/default"
for mode in $MODES; do
  note "HAP buildMode=$mode"
  "$HV" clean --no-daemon >/dev/null 2>&1 || true
  "$HV" assembleHap --mode module -p product=default -p "buildMode=$mode" --no-daemon \
    | grep -E "BUILD (SUCCESSFUL|FAILED)|ERROR" || true
  [[ -f "$HAPDIR/entry-default-unsigned.hap" ]] || die "没有生成 unsigned hap（$mode）"

  cp "$HAPDIR/entry-default-unsigned.hap" "$OUT/scnet-agent-$VER-$mode-unsigned.hap"
  "$ROOT/scripts/sign.sh" >/dev/null || die "签名失败（$mode）"
  cp "$HAPDIR/entry-default-signed.hap" "$OUT/scnet-agent-$VER-$mode-signed.hap"

  # 验签（Digest + 证书链 + profile）
  java -jar "$LIB/hap-sign-tool.jar" verify-app \
    -inFile "$OUT/scnet-agent-$VER-$mode-signed.hap" \
    -outCertChain /tmp/scnet-rel-cert.cer -outProfile /tmp/scnet-rel.p7b \
    2>&1 | grep -q "verify-app success" || die "验签失败（$mode）"
  rm -f /tmp/scnet-rel-cert.cer /tmp/scnet-rel.p7b
  printf '     ok  %s\n' "$(basename "$OUT"/scnet-agent-$VER-$mode-signed.hap)"
done

# ---- 2) Android APK（可选）----
if [[ $SKIP_APK -eq 0 ]]; then
  if [[ -n ${ANDROID_HOME:-}${ANDROID_SDK_ROOT:-} ]] \
     || [[ -d $HOME/Android/Sdk/platforms/android-34 ]] \
     || [[ -d /tmp/asdk/sdk/platforms/android-34 ]]; then
    note "Android 原生 APK"
    OUT="$ROOT/dist/android" \
      ANDROID_HOME=${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$( [[ -d /tmp/asdk/sdk ]] && echo /tmp/asdk/sdk || echo "$HOME/Android/Sdk" )}} \
      "$ROOT/scripts/build-apk.sh" | tail -4
    cp "$ROOT"/dist/android/scnet-agent-android-*.apk "$OUT"/ 2>/dev/null || true
  else
    note "跳过 APK：没有 Android SDK（ANDROID_HOME 未设）"
  fi
fi

# ---- 3) 校验和 ----
note "SHA256SUMS"
( cd "$OUT" && sha256sum ./*.hap > SHA256SUMS.txt
  if compgen -G "./*.apk" >/dev/null; then sha256sum ./*.apk >> SHA256SUMS.txt; fi )
cat "$OUT/SHA256SUMS.txt"

# ---- 4) 可选上传 ----
if [[ $UPLOAD -eq 1 ]]; then
  TAG="v$VER"
  ASSETS=("$OUT"/*.hap "$OUT"/SHA256SUMS.txt)
  compgen -G "$OUT/*.apk" >/dev/null && ASSETS+=("$OUT"/*.apk)
  note "上传到 GitHub Releases $TAG（${#ASSETS[@]} 个文件）"
  if gh release view "$TAG" >/dev/null 2>&1; then
    gh release upload "$TAG" "${ASSETS[@]}" --clobber
  else
    gh release create "$TAG" "${ASSETS[@]}" \
      --title "SCNet Agent $VER (HarmonyOS)" \
      --notes-file "$ROOT/docs/RELEASE-$VER.md"
  fi
fi

printf '\n[done] %s\n' "$OUT"
