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
[[ -f "$ROOT/signing/signing.env" ]] && source "$ROOT/signing/signing.env"

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

pubkey_of_cert() { openssl x509 -in "$1" -noout -pubkey | openssl sha256; }
pubkey_of_csr()  { openssl req  -in "$1" -noout -pubkey | openssl sha256; }

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
if [[ -n "${SIGN_CERT:-}" && -f "${SIGN_CERT:-}" ]]; then
  echo "cert file key: $(pubkey_of_cert "$SIGN_CERT")"
fi

echo
if [[ -n "$KS_PUB" ]] && [[ -f "$TMP/dev.cer" ]]; then
  if [[ "$KS_PUB" == "$(pubkey_of_cert "$TMP/dev.cer")" ]]; then
    echo "PASS: profile certificate was issued for this keystore"
  else
    echo "FAIL: profile certificate does NOT match the keystore key."
    echo "      The cert must be re-issued from a CSR of THIS keystore."
    exit 1
  fi
fi
