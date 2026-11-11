#!/usr/bin/env bash
# 原生 Android 核心逻辑自检（纯 JVM，不需要设备）。
#
# 覆盖从 ArkTS 移植到 Java 的四块纯逻辑：Markdown / SSE / 上下文裁剪 / HMAC，
# 向量与仓库根 test/*.test.mjs 保持一致。
#
# 用法：. ~/opt/module-init.sh && module load jdk && scripts/test-android.sh
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=${OUT:-$ROOT/dist/android/test-classes}
JAVAC=${JAVAC:-javac}
JAVA=${JAVA:-java}

if ! command -v "$JAVAC" >/dev/null; then
  echo "[err] 需要 JDK（javac）；本机可用 ~/opt/apps/jdk/21.0.13+9/bin" >&2
  exit 2
fi

rm -rf "$OUT" && mkdir -p "$OUT"

# 只编纯逻辑 + 自检，不碰 android.* 依赖
"$JAVAC" -nowarn -Xlint:-options --release 8 -d "$OUT" \
  "$ROOT/android/src/cn/scnet/agent/core/Md.java" \
  "$ROOT/android/src/cn/scnet/agent/core/ChatText.java" \
  "$ROOT/android/src/cn/scnet/agent/core/Hmac.java" \
  "$ROOT/android/src/cn/scnet/agent/core/Sse.java" \
  "$ROOT/android/test/cn/scnet/agent/core/CoreTest.java"

"$JAVA" -cp "$OUT" cn.scnet.agent.core.CoreTest
