#!/usr/bin/env bash
# 平台 v2 对话脱机探针 —— 不需要手机，用桌面客户端里的活体凭据直接打平台接口。
#
# 为什么有它：`系统繁忙，请稍后再试` 这种问题的根因在请求参数（modelId 目录选错），
# 装机循环验证协议太慢。协议实验一律先在这里 curl 通，再上机。
#
# 用法：
#   scripts/probe-v2.sh services                 # 列服务表，标出 aiagent-router 的 modelId
#   scripts/probe-v2.sh stream "用一句话说明 SLURM"
#   scripts/probe-v2.sh stream "继续" --cid <conversationId>
#   scripts/probe-v2.sh raw  <method> <path> [json]   # 任意 /acx 接口
#
# 凭据来源（按优先级）：
#   1) 环境变量 SC_TOKEN / SC_COOKIE
#   2) ~/.config/scnet-client/config.json 的 accessToken（自动换 jsessionid cookie）
#
# 退出码：0 正常；2 拿不到凭据；1 其它。
set -uo pipefail

BASE=${SC_BASE:-https://www.scnet.cn}
SOURCE=${SC_SOURCE:-HarmonyOS}
VERSION=${SC_VERSION:-1.0.0}
CID=""

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

# 用 accessToken 换一份 jsessionid + Token cookie（参数名就是 desktopToken）
fresh_cookie() {
  local at=$1 out jar
  jar=$(mktemp) || die "mktemp 失败"
  chmod 600 "$jar"
  out=$(curl -s -S --max-time 20 -c "$jar" -X POST \
    "$BASE/ac/api/auth/loginDesktopClientByToken.action" \
    -H 'Content-Type: application/x-www-form-urlencoded' \
    -H "source: $SOURCE" -H "version: $VERSION" \
    --data-urlencode "desktopToken=$at")
  if ! grep -q '"code":"0"' <<<"$out"; then
    printf '%s\n' "$out" | head -c 300 >&2
    rm -f "$jar"
    die "loginDesktopClientByToken 失败（token 过期？）"
  fi
  # 只取 jsessionid 与 Token 两个 cookie，拼成 Cookie 头
  awk 'BEGIN{ORS="; "} /jsessionid|Token/ && $0 !~ /^#/ {printf "%s=%s", $6, $7}' "$jar" | sed 's/; $//'
  rm -f "$jar"
}

request() { # request <method> <path> [body]
  local method=$1 path=$2 body=${3:-}
  local at ck
  at=$(load_token)
  ck=${SC_COOKIE:-$(fresh_cookie "$at")}
  [[ -n $ck ]] || die "拿不到 Cookie（v2 stream 缺 cookie 会 500）"
  local args=(-s -S --max-time 300 -X "$method" "$BASE$path"
    -H "Token: $at" -H "Cookie: $ck"
    -H "source: $SOURCE" -H "version: $VERSION"
    -H 'Accept: application/json, text/plain, */*')
  [[ -n $body ]] && args+=(-H 'Content-Type: application/json' --data-raw "$body")
  curl "${args[@]}"
}

# v2 的 modelId：从服务表里取 aiagent-router，**不要**用 config/list.modelList
router_model_id() {
  request GET '/acx/chatbot/recommend/list?enable=true' \
    | python3 -c '
import json,sys
try: d=json.load(sys.stdin)
except Exception: sys.exit(3)
rows=d.get("data") or d
for r in rows:
    if r.get("identify")=="aiagent-router":
        print(r.get("modelId")); break
else:
    sys.exit(4)
'
}

cmd_services() {
  request GET '/acx/chatbot/recommend/list?enable=true' | python3 -c '
import json,sys
d=json.load(sys.stdin)
rows=d.get("data") or d
for r in rows:
    i=r.get("identify",""); m=r.get("modelId"); n=r.get("aiAssistantName","")
    mark="   <-- v2 stream 用这个" if i=="aiagent-router" else ""
    print("%-34s modelId=%-6s %s%s" % (i, m, n, mark))
'
}

cmd_stream() {
  local text=$1
  local mid=${SC_MODEL_ID:-}
  if [[ -z $mid ]]; then mid=$(router_model_id) || true; fi
  [[ -n $mid ]] || die "取不到 aiagent-router 的 modelId（可用 SC_MODEL_ID=600 兜底）"
  note "POST /acx/chatbot/v2/agent/stream  modelId=$mid${CID:+ conversationId=$CID}"

  local at ck payload
  at=$(load_token)
  ck=${SC_COOKIE:-$(fresh_cookie "$at")}
  payload=$(python3 - "$mid" "$text" "$CID" <<'PY'
import json,sys
mid,text,cid=sys.argv[1],sys.argv[2],sys.argv[3]
b={"modelId":int(mid),"origin":"user","inputs":[{"type":"text","text":text}]}
if cid: b["conversationId"]=cid
print(json.dumps(b,ensure_ascii=False))
PY
)
  # 只显示正文增量 / 标题 / 报错 / 结束，工具帧压成一行
  curl -s -N --max-time 300 -X POST "$BASE/acx/chatbot/v2/agent/stream" \
    -H "Token: $at" -H "Cookie: $ck" \
    -H "source: $SOURCE" -H "version: $VERSION" \
    -H 'Content-Type: application/json' -H 'Accept: text/event-stream' \
    --data-raw "$payload" \
  | python3 -u -c '
import json,sys
for line in sys.stdin:
    line=line.strip()
    if not line.startswith("data:"): continue
    p=line[5:].strip()
    if not p: continue
    if p in ("[done]","[DONE]"):
        sys.stderr.write("\n[done]\n"); break
    try: f=json.loads(p)
    except Exception: continue
    t=f.get("type") or ""
    if t=="error":
        sys.stderr.write("\n[error] %s\n" % (f.get("errorText"),)); break
    if t=="finish":
        sys.stderr.write("\n[finish] %s\n" % (f.get("finishReason"),)); continue
    if t=="title_gen":
        sys.stderr.write("[title] %s\n" % (f.get("title"),)); continue
    if t in ("tool-input-start","tool-input-available","tool-output-available","tool-exec-progress"):
        desc=f.get("toolCallDescription") or f.get("progressText") or ""
        if desc: sys.stderr.write("[tool] %s\n" % desc)
        continue
    if t and t!="text-delta":
        continue
    d=f.get("delta")
    if d:
        sys.stdout.write(d); sys.stdout.flush()
sys.stdout.write("\n")
'
}

while [[ $# -gt 0 ]]; do
  case $1 in
    services) shift; cmd_services ;;
    stream)
      shift
      text=${1:-hi}; shift || true
      while [[ $# -gt 0 ]]; do
        case $1 in
          --cid) CID=${2:?}; shift 2 ;;
          *) break ;;
        esac
      done
      cmd_stream "$text"
      ;;
    raw)
      shift
      [[ $# -ge 2 ]] || die "usage: probe-v2.sh raw <GET|POST> <path> [json]"
      request "$1" "$2" "${3:-}"
      ;;
    -h|--help|help) sed -n '2,20p' "$0" ;;
    *) die "未知子命令：$1（服务/流：services | stream | raw）" ;;
  esac
done
