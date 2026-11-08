#!/usr/bin/env bash
# Verify that keystore / certificate / provisioning profile actually belong
# together before signing. Catches the classic "cert issued for a key we no
# longer have" mistake.
#
# Usage: scripts/check-signing.sh
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
CLT=${CLT:-$HOME/opt/apps/harmonyos/26.0.0.865/command-line-tools}
LIB="$CLT/sdk/default/openharmony/toolchains/lib"
if [[ ! -f "$ROOT/signing/signing.env" ]]; then
  cat >&2 <<EOF
没有找到签名材料：$ROOT/signing/signing.env

签名材料不在仓库里（git-ignored）。换机器时把旧机器的 ~/Downloads/scnet-hmos/ 拷过来：
  scp -r oldhost:~/Downloads/scnet-hmos ~/Downloads/
  chmod 600 ~/Downloads/scnet-hmos/signing.env ~/Downloads/scnet-hmos/*.p12
  ln -sfn ~/Downloads/scnet-hmos $ROOT/signing

清单与重新签发流程见 docs/SIGNING.md
EOF
  exit 2
fi
source "$ROOT/signing/signing.env"

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

pubkey_of_cert() { openssl x509 -in "$1" -noout -pubkey | openssl sha256; }
pubkey_of_csr()  { openssl req  -in "$1" -noout -pubkey | openssl sha256; }

# .cer files from AGC are chains (root -> intermediate -> leaf, any order).
# The app cert is the one that is NOT a CA; compare every cert and report a hit.
cert_file_summary() {
  local f=$1 n=0 hit=0
  openssl crl2pkcs7 -nocrl -certfile "$f" 2>/dev/null \
    | openssl pkcs7 -print_certs -out "$TMP/chain.pem" 2>/dev/null || return 1
  awk -v dir="$TMP" '/BEGIN CERTIFICATE/{n++} n>0{print > (dir "/c" n ".pem")}' "$TMP/chain.pem"
  for c in "$TMP"/c*.pem; do
    [[ -f $c ]] || continue
    n=$((n+1))
    local pub subj
    pub=$(pubkey_of_cert "$c")
    subj=$(openssl x509 -in "$c" -noout -subject | sed 's/^subject=//')
    echo "  cert$n: ${pub#SHA2-256(stdin)= }  $subj"
    [[ -n "${KS_PUB:-}" && "$pub" == "$KS_PUB" ]] && hit=1
  done
  return $((1-hit))
}

# 1. key in keystore -> throwaway CSR (only its public key is used)
KS_PUB=""
if [[ -n "${SIGN_KEYSTORE:-}" && -f "${SIGN_KEYSTORE:-}" ]]; then
  java -jar "$LIB/hap-sign-tool.jar" generate-csr \
    -keyAlias "$SIGN_KEY_ALIAS" -keyPwd "$SIGN_KEY_PWD" \
    -subject "C=CN,O=check,OU=check,CN=check" -signAlg SHA256withECDSA \
    -keystoreFile "$SIGN_KEYSTORE" -keystorePwd "$SIGN_STORE_PWD" \
    -outFile "$TMP/k.p12.csr" >/dev/null 2>&1 || true
  [[ -f "$TMP/k.p12.csr" ]] && KS_PUB=$(pubkey_of_csr "$TMP/k.p12.csr")
fi
echo "keystore key : ${KS_PUB:-<unreadable: wrong password? keyAlias?>}"

# 2. profile -> embedded development certificate + metadata
if [[ -n "${SIGN_PROFILE:-}" && -f "${SIGN_PROFILE:-}" ]]; then
  openssl asn1parse -inform DER -in "$SIGN_PROFILE" -i > "$TMP/p7b.txt"
  python3 - "$TMP/p7b.txt" "$TMP" <<'PY'
import json,re,sys
txt=open(sys.argv[1]).read(); tmp=sys.argv[2]
m=re.search(r'\{"[^\n]*\}',txt)
j=json.loads(m.group(0))
bi=j.get("bundle-info",{})
print("profile      : type=%s bundle=%s dev-id=%s" % (j.get("type"),bi.get("bundle-name"),bi.get("developer-id")))
d=j.get("debug-info",{}).get("device-ids",[])
print("profile devs : %s" % (", ".join(d) if d else "<none>"))
open(tmp+"/dev.cer","w").write(bi.get("development-certificate",""))
PY
  echo "profile key  : $(pubkey_of_cert "$TMP/dev.cer")"
fi

# 3. separate .cer file, if any
CERT_HIT=0
if [[ -n "${SIGN_CERT:-}" && -f "${SIGN_CERT:-}" ]]; then
  echo "cert file    : ${SIGN_CERT##*/}"
  cert_file_summary "$SIGN_CERT" && CERT_HIT=1
fi

echo
if [[ -n "$KS_PUB" ]] && [[ -f "$TMP/dev.cer" ]]; then
  if [[ "$KS_PUB" != "$(pubkey_of_cert "$TMP/dev.cer")" ]]; then
    echo "FAIL: profile certificate does NOT match the keystore key."
    echo "      The cert must be re-issued from a CSR of THIS keystore."
    exit 1
  fi
  if [[ -n "${SIGN_CERT:-}" && -f "${SIGN_CERT:-}" && $CERT_HIT -eq 0 ]]; then
    echo "FAIL: CERT file contains no certificate for this keystore key."
    exit 1
  fi
  echo "PASS: keystore / certificate / profile belong together"
fi
