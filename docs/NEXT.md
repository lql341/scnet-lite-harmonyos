# NEXT — 下一步要做的事（可直接照做）

> 更新时间：2026-11-08 23:55。机器状态、卡点、命令都在这里；跨机器接手看 §7。

---

## 0. 现状一句话

协议已经全部摸清（`docs/PROTOCOL.md`），工程能构建、能签名、能装真机（`cn.scnet.hmos`，PLA-AL10）。
**唯一未打通的是真正的对话内容流**：直连 `v2/agent/stream` 会先回会话 ID 再立刻 `type:"error" 系统繁忙`，
`v1/chat/completion` 回 `CHAT010004 服务繁忙`。原因未定，见 §1。

---

## 1. T0 先解决「服务繁忙」（阻塞 P2）

### 已知事实
- 鉴权没问题：每次请求都能拿到 `conversationId`（已产生 3 个空会话 `2119454…`）。
- 协议没问题：帧结构 43 字段全部对齐客户端实现。
- 不是客户端并发占用：杀掉桌面客户端后重试同样报错。
- 桌面客户端 **自己发不出去**：点了「发送消息」（按钮 enabled）主进程 0 请求 →
  UI 里有「项目：没有项目 / 选择项目」，怀疑缺 `projectId` 之类的字段，或该产品线要求先建项目。

### 两个分支，先做 A 再做 B

**A. 抓桌面客户端真实 body（最快）**

1. 起带调试口的客户端：
   ```bash
   pkill -x scnet-client
   cd /tmp && setsid nohup env SCNET_NO_SANDBOX=1 \
     /opt/scnet-client/launcher.sh --remote-debugging-port=9222 --inspect=9229 \
     >/tmp/sc.log 2>&1 </dev/null &
   ```
2. 装钩子（抓所有出站请求 + body）：
   ```bash
   cd /tmp && node /tmp/main_eval.mjs '(() => {
     if (globalThis.__cap3) return "already";
     globalThis.__cap3 = [];
     const http = require("http"), https = require("https");
     for (const C of [http.ClientRequest, https.ClientRequest]) {
       const p = C.prototype; if (p.__patched) continue; p.__patched = true;
       const _end = p.end;
       p.end = function (c, ...r) {
         try { const ch = []; if (c) ch.push(Buffer.isBuffer(c) ? c : Buffer.from(String(c)));
           globalThis.__cap3.push({ method: this.method, path: this.path,
             headers: { ...this.getHeaders() },
             body: Buffer.concat(ch).toString("utf8").slice(0, 3000) });
           if (globalThis.__cap3.length > 100) globalThis.__cap3.shift(); } catch (e) {}
         return _end.call(this, c, ...r);
       };
     }
     return "patched"; })()'
   ```
   （`/tmp/main_eval.mjs` 不存在就从本文件下方 §6 复制，或直接重写：连 `http://127.0.0.1:9229/json/list` 的 `webSocketDebuggerUrl`，发 `Runtime.evaluate`。）
3. **人工动作**：在客户端里点「选择项目」（新建一个也行），发一条消息。
4. dump：
   ```bash
   node /tmp/main_eval.mjs 'JSON.stringify((globalThis.__cap3||[]).map(x=>({m:x.method,p:x.path,body:x.body})))'
   ```
5. 用 dump 出来的 body 和我们现在的 body 逐字段 diff，补上缺的字段后重试：
   ```bash
   python3 - <<'PY'
   import json, subprocess
   h = json.load(open('/tmp/auth.json'))          # 8 个必需头，见 PROTOCOL §7
   body = json.dumps({"modelId": 520, "origin": "user",
                      "inputs": [{"type": "text", "text": "hi"}]}, ensure_ascii=False)
   args = ["curl","-sS","-N","-m","60","-X","POST",
           "https://www.scnet.cn/acx/chatbot/v2/agent/stream","--data-binary",body]
   for k,v in h.items(): args += ["-H", f"{k}: {v}"]
   args += ["-H","Accept: text/event-stream"]
   print(subprocess.run(args, capture_output=True, text=True).stdout[:800])
   PY
   ```

**B. 用手机 App 交叉验证（判定是不是产品线问题）**

在手机 SCNet App（Android / 别人的安卓机都行）里发一条消息：
- **正常出答案** → 手机走的是另一条链路（大概率 v1 + 不同 `identify`/appid）。把手机抓包或反查它的 body，
  我们照手机那条实现，桌面这条放过。APK 里 v2 端点存在，但可能只在某些场景用。
- **也报忙** → 账号级服务问题，等平台恢复；这期间照常做 P0/P1（不依赖流内容）。

### 踩坑提醒
- 别用 `pkill -f "opt/scnet-client/scnet-client"`，它会匹配到你自己的 shell 命令行把当前 bash 杀掉（踩过两次）。
  用 `pkill -x scnet-client`。
- 桌面客户端渲染进程 `file://` 起源，REA 的 `list_browser_targets` 会过滤掉；直接用 `/tmp/cdp.mjs`（见 §6）。
- 抓不到流请求的原因：旧钩子挂在 `http.request` 上，axios 可能已经持有原函数引用；
  **挂 `ClientRequest.prototype.end`** 才保证不漏。

---

## 2. P0 工程底座（0.5 天）

产出文件：

| 文件 | 内容 |
| --- | --- |
| `service/Http.ets` | 统一客户端：4 头注入（`Token`/`Cookie`/`source: HarmonyOS`/`version`）、`code!=="0"` 抛 `ApiError`、401/`code=401` → 清凭据回调、超时与重试策略 |
| `service/Auth.ets` | 登录态：`accessToken`/`cookie` 存取（`preferences` 起步，后续换 HUKS）、刷新（`current-user-info?includeToken=true&refresh=true`）、登出 |
| `service/Chat.ets` | v2 stream：`requestInStream` + 逐行 SSE 解析（复用 `Gateway.ets` 的 UTF-8 跨块处理思路）、43 字段帧解析、状态机（`sending/streaming/interrupted/uncertain/stopped/error`） |
| `pages/Tabs.ets` | 底部 4 Tab：对话 / 作业 / 文件 / 我的 |
| `model/Types.ets` | 所有 DTO（`ApiResult`、`Conversation`、`Frame`、`Record*`、`Config`、`ModelItem`…），ArkTS 不允许裸字面量，全部显式声明 |

验收：`hvigorw assembleHap` 无 ERROR；`hdc install` 后冷启动进 Splash → 无凭据跳登录页。

---

## 3. P1 登录（2 天）

接口（`docs/PROTOCOL.md §6`，已确认存在）：

```
POST /ac/api/auth/loginDesktopClient.action             账号密码（返回 token/cookie）
GET  /sso/captcha.action                                图形验证码
POST /ac/api/auth/sendDesktopClientPhoneCode.action     发短信
POST /ac/api/auth/loginDesktopClientByPhoneCode.action  短信登录
POST /ac/api/auth/loginDesktopClientByToken.action      令牌登录（静默）
GET  /acx/user/users/current-user-info?includeToken=true&refresh=true
POST /acx/user/users/logout
```

页面：`pages/Login.ets`（账号密码 + 验证码 Tab；短信验证码 Tab）、首屏协议同意（拒绝即不可进）。
验收：错密码/错验证码/停用账号三种错误文案正确；杀进程重进仍登录；token 过期自动刷新一次。

> ⚠️ 登录是 **HTTP 层**，不需要真机验证码，但需要真实账号联调。**需要你提供测试账号**（或允许用你的账号只做登录/登出）。

---

## 4. P2 对话（3 天，依赖 T0）

顺序：
1. `GET /acx/chatbot/config/list` → 取 `modelList[].id`（数字 modelId）、`defaultCluster`、`defaultIdentify`
2. 会话列表/新建/重命名/历史（`conversation/list|rename`、`v2/agent/conversation/{id}/history`）
3. v2 stream + 状态机 + 停止（`v2/agent/stop`）
4. Markdown + 代码块 + KaTeX；`LazyForEach`
5. 模型下拉按 `modelList` 渲染（4 个：17/410/120/520）

验收：见 `docs/PLAN.md` P2 的 4 条。

---

## 5. P3~P6

见 `docs/PLAN.md`。P3（富交互：`interaction`/`resource_card`/`job-monitor`）、P4（作业/产物/SLURM）、
P5（账号/团队/计费）、P6（语音/OCR/相机/打磨）。

---

## 6. 本机工具脚本（不在仓库里，重写很快）

- `/tmp/cdp.mjs`：最小 CDP 驱动（Node ≥22 有全局 `WebSocket`）
  ```js
  export async function pageTarget(){ const l=await (await fetch("http://127.0.0.1:9222/json/list")).json();
    return l.find(x=>x.type==="page"); }
  export async function connect(url){ /* new WebSocket(url); send(method,params) => Promise; on(fn) */ }
  ```
- `/tmp/main_eval.mjs`：同上，但连 `http://127.0.0.1:9229/json/list`（Electron **主进程** V8 Inspector），
  发 `Runtime.evaluate`（`awaitPromise:true, returnByValue:true`）。
- `/tmp/api.sh METHOD PATH [BODY]`：用 `/tmp/auth.json` 里的 8 个头打 `https://www.scnet.cn`。
- `/tmp/auth.json`：**活体凭据，600 权限，绝不进仓库**。失效就重新抓（§1 A 的钩子）。

---

## 7. 换一台机器怎么无缝接手

### 必须带的（不在仓库里）
| 东西 | 位置（本机） | 说明 |
| --- | --- | --- |
| 签名私钥 | `~/Downloads/scnet-hmos/scnet.hmos.debug.p12` | **丢了就要重新申请证书**（已踩过一次） |
| 应用证书 | `…/scnet.hmos.debug.cer` | AGC 下载的证书链（3 级） |
| 调试 profile | `…/scnet.hmos.debug.p7b` | 绑 `cn.scnet.hmos` + UDID `01EB73B3…DC37FB` |
| 签名变量 | `…/signing.env` | 别名/密码/路径，`chmod 600` |
| 网关 key（可选） | 真机 preferences 里 | 也可重新从网页复制 |

仓库里 `signing` 是指向 `~/Downloads/scnet-hmos` 的软链（git-ignored）。换机器后：
```bash
mkdir -p ~/Downloads/scnet-hmos && cp -a <U盘>/scnet-hmos/* ~/Downloads/scnet-hmos/
ln -s ~/Downloads/scnet-hmos <repo>/signing
./scripts/check-signing.sh     # 必须 PASS，否则证书和私钥不是一对
```
没有这些材料就重新走一遍：`generate-keypair → generate-csr` → AGC 上传 CSR 拿 `.cer` → 建 debug profile（勾 UDID）→ 下 `.p7b`。

### 环境
```bash
CLT=~/opt/apps/harmonyos/26.0.0.865/command-line-tools     # SDK API 26 / hvigor 6.26.9
export DEVECO_SDK_HOME=$CLT/sdk                            # 注意是 sdk，不是 sdk/default
$CLT/hvigor/bin/hvigorw assembleHap --mode module -p product=default -p buildMode=debug --no-daemon
./scripts/sign.sh --install
```
Node ≥22（用全局 `WebSocket`）、JDK 21、`gh` 已登录 `lql341`。

### 已连接的调试设备
`192.168.1.63:36333`（HUAWEI PLA-AL10，HarmonyOS 7.0.0.111，API 26）。
新机器要装就得保证 UDID 在 profile 的 `device-ids` 里，否则装不上（报 9568322）。

---

## 8. 未决问题（需要人）
1. **T0 的 body diff**：需要有人在桌面客户端「选项目 → 发一条消息」，或给出手机端交叉验证结果。
2. **测试账号**：登录/注销/发票联调。
3. **范围**：P5/P6 是否进第一版（砍掉省 2.5 天）。
4. **是否允许真实提交作业**（P4 验收会真计费）。
5. **商标/图标**：当前图标与名称来自官方 APK，仅调试用。
