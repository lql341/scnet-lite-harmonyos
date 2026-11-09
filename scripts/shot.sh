#!/usr/bin/env bash
# 真机截图 + 拉回本地。用于 UI 迭代（改完 → 装 → 截图 → 看）。
#
#   scripts/shot.sh            → /tmp/scnet-shot.jpeg（并打印路径）
#   scripts/shot.sh out.jpeg   → 指定输出路径
#
# 依赖：module load harmonyos（hdc）。设备需已解锁，否则拍到的是锁屏。
set -uo pipefail
OUT=${1:-/tmp/scnet-shot.jpeg}
. "$HOME/opt/module-init.sh" 2>/dev/null || true
module load harmonyos >/dev/null 2>&1 || true

if ! hdc list targets 2>/dev/null | grep -qv '^\[Empty\]$'; then
  echo "[err] 没有连接的设备（hdc list targets）" >&2
  exit 2
fi

hdc shell snapshot_display -f /data/local/tmp/_shot.jpeg >/dev/null 2>&1 \
  || { echo "[err] snapshot_display 失败" >&2; exit 1; }
hdc file recv /data/local/tmp/_shot.jpeg "$OUT" >/dev/null 2>&1 \
  || { echo "[err] 拉取截图失败" >&2; exit 1; }
echo "$OUT"
