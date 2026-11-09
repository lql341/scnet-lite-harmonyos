# NEXT — 下一步要做的事（可直接照做）

> 更新时间：2026-11-09 12:10。**卡点已解除**：`系统繁忙` 是 `modelId` 取错了目录
> （v2 要走 `recommend/list` 的 `aiagent-router` → `600`，不是 `config/list.modelList` 的 LLM id）。
> 协议细节以 `docs/PROTOCOL.md` §8.3/§8.4 为准。

---

## 0. 当下第一步：把设备接回来，装上验证出字

```bash
. ~/opt/module-init.sh && module load harmonyos jdk
hvigorw assembleHap --mode module -p product=default -p buildMode=debug --no-daemon
hdc tconn 192.168.1.63:36333      # 无线调试；IP/端口变了就在手机上重新看
hdc list targets                  # 必须不是 [Empty]
./scripts/sign.sh --install       # 需要 signing/ 软链到 ~/Downloads/scnet-hmos（当前不在本机）
```

当前机器状态（2026-11-09 12:05）：工具链 ✅、构建 ✅（3 s）、**设备 ❌（`hdc list targets` = `[Empty]`）**、签名材料 ❌（`signing/` 与 `~/Downloads/scnet-hmos` 都不存在）。
无设备时可以纯后端调试，见 §2。

## 1. 现状一句话

登录/会话列表/历史/智能体服务目录都通；`v2/agent/stream` 已在本机用真实凭据跑通（`modelId=600`），
代码按真实帧词表改完并构建通过；**只剩真机装机复验**。

## 2. 本机脱机调试 v2（不需要手机，强烈推荐）

协议实验全是纯 HTTP，没必要上机循环。仓库自带探针：

```bash
./scripts/probe-v2.sh services                     # 列服务表，标出 aiagent-router 的 modelId
./scripts/probe-v2.sh stream "用一句话说明 SLURM"   # 只要正文，工具帧/标题走 stderr
./scripts/probe-v2.sh stream "继续" --cid <id>     # 多轮
./scripts/probe-v2.sh raw GET '/acx/chatbot/config/list'
./scripts/probe-v2.sh raw POST '/acx/chatbot/v2/agent/stop' '{"conversationId":"…","modelId":600}'
```

凭据自动从桌面客户端配置 `~/.config/scnet-client/config.json` 的 `accessToken`（235 字符 JWT）取，
再换一份 `jsessionid`（参数名就是 `desktopToken`）。也可 `SC_TOKEN`/`SC_COOKIE` 覆盖；
`SC_MODEL_ID=600` 可跳过服务表。

手工等价命令（探针坏了时对照用）：

```bash
curl -s -X POST https://www.scnet.cn/ac/api/auth/loginDesktopClientByToken.action \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  -d "desktopToken=$AT" -D - -o /dev/null | grep -i set-cookie

curl -s 'https://www.scnet.cn/acx/chatbot/recommend/list?enable=true' \
  -H "Token: $AT" -H "Cookie: $CK" | jq -r '.data[]? | select(.identify=="aiagent-router") | .modelId'
# → 600
```

调试纪律：**先在本机 curl 复现 → 改协议 → 再上机**，不要用装机循环试协议。

## 3. 换电脑后第一天（5 分钟）

```bash
git clone git@github.com:lql341/scnet-lite-harmonyos.git
cd scnet-lite-harmonyos
# 1) 拷签名材料（手机不变 → .p7b 不用重签）
scp -r oldhost:~/Downloads/scnet-hmos ~/Downloads/
chmod 600 ~/Downloads/scnet-hmos/signing.env ~/Downloads/scnet-hmos/*.p12
ln -sfn ~/Downloads/scnet-hmos signing
# 2) 一条命令自检（工具链/设备/签名配对/文档）
./scripts/dev-check.sh
# 3) 构建 + 装机
DEVECO_SDK_HOME=~/opt/apps/harmonyos/26.0.0.865/command-line-tools/sdk \
  ~/opt/apps/harmonyos/26.0.0.865/command-line-tools/hvigor/bin/hvigorw \
  assembleHap --mode module -p product=default -p buildMode=debug --no-daemon
./scripts/sign.sh --install
```

`dev-check.sh` 会把不该靠记忆的东西都验一遍：hvigorw/SDK/JDK/node、`hdc` 设备、
`signing/` 软链与三者公钥是否配对、工作区是否干净、6 份文档是否齐。
只构建不装机时可以跳过签名那步（会标 `[warn]`）。

## 4. 历史记录：当时卡在哪（已解决，留档）

之前以为是「账号侧权益 / 服务端不可用」，实际是 `modelId` 用错了目录。
错判过程与纠正见 `docs/PROTOCOL.md` §8.3；不要再为「系统繁忙」去抓手机端的 mitmproxy HAR，
本机 curl 几秒就能复现并定位。

不阻塞的部分（可以直接往下做）：`v2/agent/stop` 接入、断线续传（`interrupted`/`uncertain`）、
Markdown + KaTeX 渲染、会话重命名、附件上传下载。见 `docs/TODO.md` B/C 段。

## 5. P0 工程底座（0.5 天）— **已完成**

已落地（提交 `feat(P0/P1)`）：

| 文件 | 作用 |
| --- | --- |
| `model/Types.ets` | `ApiEnvelope / UserInfo / ModelItem / ChatConfig / Conversation / StreamFrame` |
| `service/Http.ets` | 4 头注入（`Token`/`Cookie`/`source: HarmonyOS`/`version`）、`code!=="0"` 抛 `ApiError`、401 清凭据并回调 |
| `service/Auth.ets` | 密码登录、短信登录、`current-user-info` 刷新、`chatConfig`、`conversationList`、`logout`、Set-Cookie 捕获 |
| `service/Store.ets` | 新增 `cloudCookie` / `clearCloudAuth` |
| `pages/Login.ets` | 密码/短信双 Tab + 协议勾选 + 错误文案 |
| `entryability/EntryAbility.ets` | 启动按登录态选 `pages/Login` 或 `pages/Index` |

原始设计说明（仍适用）：


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

## 6. P1 登录（2 天）

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

## 7. P2 对话（3 天，依赖 T0）

顺序：
1. `GET /acx/chatbot/config/list` → 取 `modelList[].id`（数字 modelId）、`defaultCluster`、`defaultIdentify`
2. 会话列表/新建/重命名/历史（`conversation/list|rename`、`v2/agent/conversation/{id}/history`）
3. v2 stream + 状态机 + 停止（`v2/agent/stop`）
4. Markdown + 代码块 + KaTeX；`LazyForEach`
5. 模型下拉按 `modelList` 渲染（4 个：17/410/120/520）

验收：见 `docs/PLAN.md` P2 的 4 条。

---

## 8. P3~P6

见 `docs/PLAN.md`。P3（富交互：`interaction`/`resource_card`/`job-monitor`）、P4（作业/产物/SLURM）、
P5（账号/团队/计费）、P6（语音/OCR/相机/打磨）。

---

## 9. 本机工具脚本（不在仓库里，重写很快）

- `/tmp/cdp.mjs`：最小 CDP 驱动（Node ≥22 有全局 `WebSocket`）——仅在调试 Web 端/Electron 时才用得到，"复刻 APK"本身不需要
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

## 10. 换一台机器怎么无缝接手

### 必须带的（不在仓库里，详见 [`SIGNING.md`](SIGNING.md)）
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

## 11. 未决问题（需要人）
1. **手机端联调**：需要在真机上跑一次对话，确认 `/acx/chatbot/*` 链路可用（若不繁忙则直接接）。
2. **测试账号**：登录/注销/发票联调。
3. **范围**：P5/P6 是否进第一版（砍掉省 2.5 天）。
4. **是否允许真实提交作业**（P4 验收会真计费）。
5. **商标/图标**：当前图标与名称来自官方 APK，仅调试用。
