#!/usr/bin/env bash
# 换机器后跑这一条：检查工具链、设备、签名材料、文档是否齐备。
set -uo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
CLT=${CLT:-$HOME/opt/apps/harmonyos/26.0.0.865/command-line-tools}
FAIL=0
ok() { printf '  [ok]   %s\n' "$1"; }
bad() { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL + 1)); }
warn() { printf '  [warn] %s\n' "$1"; }

echo "== 1. 工具链"
if [[ -x $CLT/hvigor/bin/hvigorw ]]; then ok "hvigorw $CLT"; else bad "没找到 hvigorw（预期 $CLT/hvigor/bin/hvigorw）"; fi
if [[ -d $CLT/sdk ]]; then ok "SDK 在 $CLT/sdk（DEVECO_SDK_HOME 要指这里，不是 sdk/default）"; else bad "SDK 目录缺失"; fi
command -v node >/dev/null && ok "node $(node -v)" || bad "缺 node"
command -v java >/dev/null && ok "java $(java -version 2>&1 | head -1 | tr -d '"')" || bad "缺 JDK 21"
[[ -f $CLT/sdk/default/openharmony/toolchains/lib/hap-sign-tool.jar ]] \
  && ok "hap-sign-tool.jar" || bad "缺 hap-sign-tool.jar"

echo "== 2. 设备"
HDC=$CLT/sdk/default/openharmony/toolchains/hdc
if [[ -x $HDC ]]; then
  TARGETS=$($HDC list targets 2>/dev/null | grep -v '^[[:space:]]*$' || true)
  if [[ -n ${TARGETS:-} ]]; then ok "hdc 设备：$(echo "$TARGETS" | tr '\n' ' ')"; else warn "没有连接设备（装机时再连）"; fi
else
  bad "缺 hdc"
fi

echo "== 3. 签名材料（不在仓库里）"
if [[ -e $ROOT/signing ]]; then
  ok "signing 已就位 -> $(readlink -f "$ROOT/signing")"
  if "$ROOT/scripts/check-signing.sh" >/tmp/dc_sign.log 2>&1; then
    ok "keystore / 证书 / profile 三者配对"
  else
    bad "签名材料不配对，明细见 /tmp/dc_sign.log"
  fi
else
  warn "没有 signing/（只构建不装机可忽略；要装机先按 docs/SIGNING.md 迁移）"
fi

echo "== 4. 仓库状态"
if [[ -z $(git -C "$ROOT" status --porcelain) ]]; then ok "工作区干净"; else warn "有未提交改动"; fi
ok "HEAD $(git -C "$ROOT" log --oneline -1)"

echo "== 5. 文档"
for f in docs/NEXT.md docs/TODO.md docs/PROTOCOL.md docs/SIGNING.md docs/PLAN.md docs/PARITY.md; do
  if [[ -f $ROOT/$f ]]; then ok "$f"; else bad "缺 $f"; fi
done

echo
if [[ $FAIL -eq 0 ]]; then
  echo "全部就绪。下一步："
  echo "  DEVECO_SDK_HOME=$CLT/sdk $CLT/hvigor/bin/hvigorw assembleHap --mode module -p product=default -p buildMode=debug --no-daemon"
  echo "  ./scripts/sign.sh --install"
else
  echo "有 $FAIL 项不通过，先修上面标 [FAIL] 的。"
fi
exit $((FAIL > 0))
