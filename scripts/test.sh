#!/usr/bin/env bash
# 单元测试（Node 直接跑 ArkTS 纯逻辑模块）。
#
#   ./scripts/test.sh
#
# 原理：Markdown.ets 这类纯逻辑文件没有 UI 装饰器，复制成 .ts 后用 Node 的
# `--experimental-transform-types` 剥掉类型即可 import —— 保证测试跑的就是**线上同一份代码**，
# 不是复制出来的一份实现。
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

NODE=${NODE:-node}
if ! "$NODE" --experimental-transform-types -e 'process.exit(0)' 2>/dev/null; then
  echo "[err] 当前 node 不支持 --experimental-transform-types（需要 Node >= 22.6）" >&2
  exit 2
fi

FAIL=0
for t in test/*.test.mjs; do
  [[ -f $t ]] || continue
  printf '== %s\n' "$(basename "$t")"
  if ! "$NODE" --experimental-transform-types --no-warnings "$t"; then
    FAIL=$((FAIL + 1))
  fi
done

if [[ $FAIL -eq 0 ]]; then
  echo "全部通过"
else
  echo "有 $FAIL 个测试文件失败"
fi
exit $((FAIL > 0))
