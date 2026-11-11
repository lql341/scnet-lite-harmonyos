# PROTOCOL — SCNet 账户与模型网关协议（逆向 + 实测）

> 本仓库只走**网关模型链路**（与官方桌面客户端、`../scnet-cli` 同一条）：
> 登录 → 集群身份 → 模型服务授权 → 取 `sk-` key → `/models` → `/chat/completions`。
>
> 平台「v2 智能体」通道（`/acx/chatbot/v2/agent/*`）**已从本仓库移除**，相关内容不再维护；
> 若将来要用，去 git 历史里翻 `b60d149`，那是当时的实测记录。
>
> 证据来源：`/opt/scnet-client/resources/app.asar`（客户端 4.1.0 的 main 包）、
> APK 字符串、以及本机真机/直连实测。标「实测」的都可以用 `scripts/probe.sh` 复现。

---

## 1. 域与鉴权

| 用途 | base |
| --- | --- |
| 平台业务接口 | `https://www.scnet.cn`（`/ac/api/auth/*`、`/acx/*`） |
| 模型网关（OpenAI 兼容） | `https://api.scnet.cn/api/llm/v1`（由取 key 接口下发） |

平台侧请求要**两个头**，缺一个就是 `401 用户未登录!`：

```
Token: <JWT，235 字符>            Accept: application/json
Cookie: jsessionid=…; Token=<uuid>  source: HarmonyOS   version: 1.0.0
```

- `Token` 来自登录响应或 `current-user-info?...&refresh=true`；
- `Cookie` 里的 `jsessionid` 来自登录响应（`Set-Cookie`）。**只带 Token 不带 Cookie 会 401**；
- 桌面客户端用 `source: Electron` / `version: 4.1.0`，我们发 `HarmonyOS` / `1.0.0`，实测无差异。

网关侧是另一套：`Authorization: Bearer <sk-…>`，**不认**平台的 `Token`。

---

## 2. 登录

### 2.1 端点

```
GET  /ac/api/auth/isNeedCpatcha.action         → data:false 表示不需要图形验证码（厂商拼写如此）
GET  /ac/api/auth/getClientCaptcha.action      → {data:"data:image/jpeg;base64,…", captchaKey:"<40 字符>"}
POST /ac/api/auth/loginDesktopClient.action    form: username / password /[captcha / captchaKey]
POST /ac/api/auth/sendDesktopClientPhoneCode.action        form: phoneNum
POST /ac/api/auth/loginDesktopClientByPhoneCode.action     form: phoneNum / messageCode
POST /ac/api/auth/loginDesktopClientByToken.action         form: desktopToken
POST /ac/api/auth/logoutDesktopClient.action               登出
GET  /acx/user/users/current-user-info?includeToken=true&refresh=true
GET  /acx/user/users/cluster-user-detail
```

### 2.2 实测行为

- **只接受 `form-urlencoded`**，字段名全小写：写 `userName` 在某些端会报
  `1003 params not enough: [username] is null`；
- 登录成功 = `Set-Cookie: jsessionid=…` + JSON 正文（可能带 `X-Jwt-Refresh-Token`）；
- 错误码：

| code | 含义 |
| --- | --- |
| `1014` | 账号或密码错误；**平台要求验证码时也是这个码**，要先查 `isNeedCpatcha` |
| `1006` | 验证码错误/过期（换一张重试） |
| `1003` | 参数缺失（编码或字段名错） |
| `1016` | 短信发送失败（频控/通道） |
| `1022` | 手机号未注册 |

- `desktopToken` 换 cookie 这条路很好用（有 `accessToken` 就能免密拿一份新 cookie）：

```bash
curl -s -X POST https://www.scnet.cn/ac/api/auth/loginDesktopClientByToken.action \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  --data-urlencode "desktopToken=$AT" -D - -o /dev/null | grep -i set-cookie
```

---

## 3. 账户与模型服务授权

```
GET  /acx/llm/account/config/status?accountId=…      → modelServiceEnabled / unpaidStatus / accessibleModelScope
POST /acx/llm/account/config/authorize?accountId=…    → 开通平台模型服务（官方客户端登录后自动做）
```

### 3.1 ⚠️ `accountId` 必须用**集群账号**

| accountId | 来源 | `authorize` 结果 |
| --- | --- | --- |
| `<集群账号ID>` | `cluster-user-detail[].accountId` | ✅ `{"code":"0"}`，`modelServiceEnabled` 0 → 1 |
| `<用户ID>` | `current-user-info.id` | ❌ `{"code":"API010006","msg":"无权限访问"}` |

`cluster-user-detail` 按集群返回多行（本账号 13 行，一集群一行），同一账号的
`accountId` / `groupId` / `userId` 在各 active 行里相同，按 status != inactive 取第一行即可。
`userId` 就是用户 id，建 key 时当 `createUser` 用。

### 3.2 status 字段

```jsonc
{ "accountId": "<集群账号ID>",
  "modelServiceEnabled": 1,        // 必须为 1，否则网关一律拒
  "unpaidStatus": 1,               // 1 = 有未结清账单（只影响付费模型）
  "accessibleModelScope": "CUSTOM",
  "modelAllowOverdraft": 0,
  "isVip": false,
  "overallQuota": null, "overallRpm": null }
```

---

## 4. 取网关 key

优先走一条接口（官方客户端 4.1.0 的做法）：

```
POST /acx/llm/api-key/createActivityApiKey   {"": 无 body} / {}
→ {"apiKey":"sk-…"(43 字符), "baseUrl":"https://api.scnet.cn/api/llm/v1",
   "anthropicBaseUrl":"https://api.scnet.cn/api/llm/anthropic", "model":"MiniMax-M2.5"}
```

兜底（团队维度）：

```
POST /acx/llm/api-key/query   {createUser, accountId, groupId, serviceType:"model", page, size}
GET  /acx/llm/api-key/detail?id=…     → 明文 key（列表里是打码的，含 *）
POST /acx/llm/api-key/create  {createUser, apiKeyName, serviceTypes:["model"],
                               accessibleModelScope:"ALL", groupId, accountId}
```

实测坑：

- `/api-key/query` **只支持 POST**，GET → `{"code":"405","msg":"Request method 'GET' not supported"}`；
- 回带的 `"model": "MiniMax-M2.5"` 是**活动推荐模型**，不是免费模型，拿它当默认会直接 402；
- key 是 `sk-` 开头 43 字符，base64 里能看到 `<userId>-<timestamp>`；
- 同一把 key 只认 `/api/llm/v1`；打 `/api/gw/v1` 会 `401 token_not_found_in_db`（LiteLLM 里没有它）。

---

## 5. 模型与计费

`GET {baseUrl}/models`（带 `Authorization: Bearer`）返回 33 个 id。

**只有 `SCNet-Max` 是平台自营、不扣余额**，其余 32 个是上游付费模型：

| model | 结果（余额 0 的账号） |
| --- | --- |
| `SCNet-Max`（别名 `gpt-5.6-luna`） | ✅ 200，正常流式 |
| `MiniMax-M2.5` / `GLM-5.3-Flash` / `DeepSeek-V4.1-Flash-1017` / 其余 | ❌ `402 Insufficient Balance` |

所以默认模型固定 `SCNet-Max`（`Store.DEFAULT_MODEL`），与 `scnet-cli` 的 `pickDefaultModel()` 一致。
402 的文案要引导用户换模型，而不是让用户以为登录坏了。

---

## 6. 对话（OpenAI 兼容 SSE）

```
POST {baseUrl}/chat/completions
Authorization: Bearer <sk-…>
Content-Type: application/json

{"model":"SCNet-Max","stream":true,"messages":[{"role":"user","content":"hi"}]}
```

- 正常流：`data: {"choices":[{"delta":{"content":"…","reasoning_content":"…"}}]}` … `data: [DONE]`；
- `reasoning_content` 是思考过程（`thinkingEnable` 模型才有），不要混进正文；
- **错误响应不是 SSE**：是普通 JSON，`content-type: application/json`，且**单行、末尾无换行**：

```json
{"error":{"message":"Insufficient Balance (request_id: …)","type":"invalid_request_error","code":"402"}}
```

> 踩过：按 `\n` 切行的 SSE 解析器永远等不到这个换行，错误体一直留在缓冲区里，
> 界面只能给兜底文案。必须在流结束时把残留 buffer 再冲一遍
> （见 `service/Gateway.ets` 的 `handleLine()` / `dataEnd`）。

| HTTP | code | 处理 |
| --- | --- | --- |
| 401 | `token_not_found_in_db` / `Authentication Error` | key 失效或用错 base → 重新取 key |
| 402 | `Insufficient Balance` | 该模型要钱 → 换 `SCNet-Max` 或充值 |
| 429 | rate limit | 退避重试 |

---

## 7. 其它已确认端点

```
GET  /acx/chatbot/config/list                        推荐问题（空状态用）+ 广告位
GET  /acx/chatbot/conversation/list?page=1&size=30   → records[{id,title,createTime,taskStatus,…}]
GET  /acx/chatbot/v2/agent/conversation/{id}/history?page&size=50
GET  /acx/user/users/current-user-info?includeToken=true&refresh=true
GET  /acx/llm/api/console/model                      平台模型目录（含别名、价格、trial 标记）
```

会话历史目前只用来**浏览**：本仓库的发消息走网关，不会续写平台会话。

---

## 8. 复现工具

```bash
scripts/probe.sh account      # 集群身份 + 授权状态 + 欠费标记
scripts/probe.sh authorize    # 开通模型服务（幂等）
scripts/probe.sh models       # 取 key → 列模型（标出免费项）
scripts/probe.sh chat "hi"    # 流式对话（默认 SCNet-Max）
scripts/probe.sh raw POST '/acx/llm/api-key/createActivityApiKey' '{}'
```

凭据来源：`~/.config/scnet-client/config.json` 的 `accessToken`（也可 `SC_TOKEN` / `SC_COOKIE` 覆盖）。
