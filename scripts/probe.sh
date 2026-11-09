#!/usr/bin/env bash
# 平台账户 / 网关模型链路探针 —— 不需要手机，用桌面客户端里的活体凭据直接打平台接口。
#
# 链路（与官方客户端、scnet-cli 同一条）：
#   loginDesktopClientByToken → cluster-user-detail → llm/account/config/status
#   →（必要时）llm/account/config/authorize → llm/api-key/createActivityApiKey
#   → {baseUrl}/models → {baseUrl}/chat/completions
#
# 用法：
#   scripts/probe.sh account          # 集群身份 + 模型服务授权状态（402 先看这里）
#   scripts/probe.sh authorize        # 开通平台模型服务（幂等；用集群 accountId）
#   scripts/probe.sh models           # 取 key 并列出网关模型
#   scripts/probe.sh chat [文本] [--model M]    # 流式对话（默认用平台下发的模型）
#   scripts/probe.sh raw <METHOD> <path> [json] # 任意 /acx 接口
#
# 凭据来源（按优先级）：
#   1) 环境变量 SC_TOKEN / SC_COOKIE
#   2) ~/.config/scnet-client/config.json 的 accessToken（自动换 jsessionid cookie）
set -uo pipefail

BASE=${SC_BASE:-https://www.scnet.cn}
SOURCE=${SC_SOURCE:-HarmonyOS}
VERSION=${SC_VERSION:-1.0.0}
MODEL=""
CACHE=${SC_CACHE:-/tmp/scnet-probe-cache}

die() { printf '[err] %s\n' "$1" >&2; exit "${2:-1}"; }
note() { printf '[..] %s\n' "$1" >&2; }

load_token() {
  if [[ -n ${SC_TOKEN:-} ]]; then printf '%s' "$SC_TOKEN"; return 0; fi
  local cfg=$HOME/.config/scnet-client/config.json
  [[ -f $cfg ]] || die "没有 SC_TOKEN，也没有 $cfg" 2
  python3 - "$cfg" <<'PY' || die "从客户端配置里取 accessToken 失败" 2
import json,sys
print(json.load(open(sys.argv[1]))['accessToken'], end='')
PY
}

# accessToken → 一份 jsessionid + Token cookie（参数名就是 desktopToken）
fresh_cookie() {
  local at=$1 jar out
  mkdir -p "$CACHE" && chmod 700 "$CACHE"
  jar=$(mktemp) || die "mktemp 失败"
  chmod 600 "$jar"
  out=$(curl -s -S --max-time 20 -c "$jar" -X POST \
    "$BASE/ac/api/auth/loginDesktopClientByToken.action" \
    -H 'Content-Type: application/x-www-form-urlencoded' \
    -H "source: $SOURCE" -H "version: $VERSION" \
    --data-urlencode "desktopToken=$at")
  grep -q '"code":"0"' <<<"$out" || { printf '%s\n' "$out" | head -c 300 >&2; rm -f "$jar"; die "loginDesktopClientByToken 失败（token 过期？）"; }
  awk 'BEGIN{ORS="; "} /jsessionid|Token/ && $0 !~ /^#/ {printf "%s=%s", $6, $7}' "$jar" | sed 's/; $//'
  rm -f "$jar"
}

ready() { # 把 token/cookie 落到本地缓存，后续 curl 复用
  local at
  at=$(load_token)
  printf '%s' "$at" > "$CACHE/token"; chmod 600 "$CACHE/token"
  if [[ -n ${SC_COOKIE:-} ]]; then
    printf '%s' "$SC_COOKIE" > "$CACHE/cookie"
  else
    fresh_cookie "$at" > "$CACHE/cookie"
  fi
  chmod 600 "$CACHE/cookie"
  [[ -s "$CACHE/cookie" ]] || die "拿不到 Cookie"
}

call() { # call <method> <path> [body]
  local method=$1 path=$2 body=${3:-} args
  args=(-s -S --max-time 300 -X "$method" "$BASE$path"
    -H "Token: $(cat "$CACHE/token")" -H "Cookie: $(cat "$CACHE/cookie")"
    -H "source: $SOURCE" -H "version: $VERSION"
    -H 'Accept: application/json, text/plain, */*')
  [[ -n $body ]] && args+=(-H 'Content-Type: application/json' --data-raw "$body")
  curl "${args[@]}"
}

# 集群身份：authorize / 团队 key 用这里的 accountId（不是 current-user-info 的 id）
identity() {
  call GET '/acx/user/users/cluster-user-detail' | python3 -c '
import json,sys
rows=json.load(sys.stdin).get("data") or []
for r in rows:
    if r.get("status")=="inactive": continue
    if r.get("accountId") and r.get("groupId") and r.get("userId"):
        print(r["accountId"], r["groupId"], r["userId"], r.get("clusterName",""), sep="\t"); break
'
}

account_id() { identity | cut -f1; }

cmd_account() {
  local id
  id=$(account_id)
  [[ -n $id ]] || die "取不到集群 accountId"
  note "集群 accountId=$id"
  call GET "/acx/llm/account/config/status?accountId=$id" | python3 -c '
import json,sys
d=json.load(sys.stdin).get("data") or {}
for k in ("accountId","modelServiceEnabled","unpaidStatus","accessibleModelScope","isVip","modelAllowOverdraft","overallQuota"):
    print("%-22s %s" % (k, d.get(k)))
if d.get("modelServiceEnabled") != 1:
    print("\n-> 模型服务未开通：先跑 scripts/probe.sh authorize")
if d.get("unpaidStatus") == 1:
    print("-> unpaidStatus=1：账号有未结清账单，网关 chat 会 402（与 API key 无关，需去控制台处理）")
'
}

cmd_authorize() {
  local id
  id=$(account_id)
  [[ -n $id ]] || die "取不到集群 accountId"
  note "POST /acx/llm/account/config/authorize?accountId=$id"
  call POST "/acx/llm/account/config/authorize?accountId=$id" ''
  echo
  cmd_account
}

# 取一把 activity key（一条接口给 key + baseUrl + 默认模型）
fetch_key() {
  call POST '/acx/llm/api-key/createActivityApiKey' '{}' | python3 -c '
import json,sys
d=json.load(sys.stdin).get("data") or {}
print("\t".join([d.get("apiKey") or "", d.get("baseUrl") or "", d.get("model") or ""]))
'
}

cmd_models() {
  local key base model
  IFS=$'\t' read -r key base model < <(fetch_key)
  [[ -n $key ]] || die "createActivityApiKey 没给 key"
  base=${base:-https://api.scnet.cn/api/llm/v1}
  note "baseUrl=$base  keyLen=${#key}  平台默认模型=$model"
  curl -s "$base/models" -H "Authorization: Bearer $key" | python3 -c '
import json,sys
rows=json.load(sys.stdin).get("data") or []
print("models: %d" % len(rows))
for r in rows: print(" ", r.get("id"))
'
}

cmd_chat() {
  local text=$1 key base model
  IFS=$'\t' read -r key base model < <(fetch_key)
  [[ -n $key ]] || die "createActivityApiKey 没给 key"
  base=${base:-https://api.scnet.cn/api/llm/v1}
  [[ -n $MODEL ]] && model=$MODEL
  [[ -n $model ]] || die "没有可用模型（用 --model 指定）"
  note "POST $base/chat/completions  model=$model"
  curl -s -N --max-time 300 "$base/chat/completions" \
    -H "Authorization: Bearer $key" -H 'Content-Type: application/json' \
    --data-raw "$(python3 -c '
import json,sys
print(json.dumps({"model":sys.argv[1],"stream":True,
                  "messages":[{"role":"user","content":sys.argv[2]}]}, ensure_ascii=False))
' "$model" "$text")" \
  | python3 -u -c '
import json,sys
for line in sys.stdin:
    line=line.strip()
    if not line: continue
    if not line.startswith("data:"):
        # 网关报错（402/401 等）是普通 JSON，不是 SSE
        try:
            f=json.loads(line)
        except Exception:
            continue
        if "error" in f:
            sys.stderr.write("[error] %s\n" % (json.dumps(f["error"], ensure_ascii=False),))
            break
        continue
    p=line[5:].strip()
    if not p or p=="[DONE]":
        break
    try: f=json.loads(p)
    except Exception: continue
    if "error" in f:
        sys.stderr.write("\n[error] %s\n" % (json.dumps(f["error"], ensure_ascii=False),)); break
    for ch in f.get("choices") or []:
        d=ch.get("delta") or {}
        if d.get("reasoning_content"): sys.stderr.write(d["reasoning_content"])
        if d.get("content"):
            sys.stdout.write(d["content"]); sys.stdout.flush()
sys.stdout.write("\n")
'
}

# ---- 入口 ----
[[ $# -gt 0 ]] || die "用法：probe.sh account|authorize|models|chat|raw [--help]"
case $1 in
  -h|--help|help) sed -n '2,22p' "$0"; exit 0 ;;
esac
mkdir -p "$CACHE" && chmod 700 "$CACHE"
ready

while [[ $# -gt 0 ]]; do
  case $1 in
    account)   shift; cmd_account ;;
    authorize) shift; cmd_authorize ;;
    models)    shift; cmd_models ;;
    chat)
      shift
      text=${1:-hi}; shift || true
      while [[ $# -gt 0 ]]; do
        case $1 in
          --model) MODEL=${2:?}; shift 2 ;;
          *) break ;;
        esac
      done
      cmd_chat "$text"
      ;;
    raw)
      shift
      [[ $# -ge 2 ]] || die "用法：probe.sh raw <GET|POST> <path> [json]"
      call "$1" "$2" "${3:-}"
      echo
      break
      ;;
    *) die "未知子命令：$1" ;;
  esac
done
