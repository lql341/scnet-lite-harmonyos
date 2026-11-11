package cn.scnet.agent.svc;

import org.json.JSONArray;
import org.json.JSONObject;

import cn.scnet.agent.core.Http;
import cn.scnet.agent.core.J;
import cn.scnet.agent.core.Store;

/**
 * 平台账号 / 会话接口（对齐 ArkTS 的 service/Auth.ets）。
 *
 * 登录有两条路：客户端 `.action` 端点（吃 form-urlencoded）与 SSO 表单，依次试。
 * 平台把 SSO token 同时放在响应体（data.token / accessToken）和 Set-Cookie 里。
 */
public class Auth {

    public static class UserInfo {
        public String id = "";
        public String userName = "";
        public String fullName = "";
        public String mobile = "";
        public String email = "";
        public String acctRole = "";
    }

    public static class ChatConfig {
        public String[] recommend = new String[0];
        public String defaultIdentify = "";
    }

    public static class ClusterInfo {
        public int clusterId;
        public String clusterName = "";
        public String accountId = "";
        public String groupId = "";
        public String createUser = "";
        public String status = "";
    }

    public static class Identity {
        public String accountId = "";
        public String groupId = "";
        public String createUser = "";
        public String clusterName = "";
    }

    public static class Conversation {
        public String id = "";
        public String title = "";
        public String createTime = "";
        public String taskStatus = "";
    }

    public static class AgentService {
        public String identify = "";
        public String name = "";
        public int modelId;
        public String description = "";
    }

    public static class HistoryMessage {
        public String role = "";
        public String text = "";
    }

    /** expired = 登录过期；manual = 主动退出；unauthenticated = 首次使用。 */
    public String loginReason = "unauthenticated";
    public String lastLoginRoute = "";

    private static final Auth INSTANCE = new Auth();

    public static Auth get() {
        return INSTANCE;
    }

    public void noteSessionExpired() {
        Http.token = "";
        Http.cookie = "";
        Store.get().clearCloudAuth();
        loginReason = "expired";
    }

    public void noteManualLogout() {
        Store.get().setHadSession(false);
        loginReason = "manual";
    }

    /** 启动恢复登录态。 */
    public boolean restore() {
        Http.token = Store.get().getCloudToken();
        Http.cookie = Store.get().getCloudCookie();
        if (Http.token.length() > 0) {
            Store.get().setHadSession(true);
            loginReason = "";
            return true;
        }
        loginReason = Store.get().hadSession() ? "expired" : "unauthenticated";
        return false;
    }

    public boolean isLoggedIn() {
        return Http.token.length() > 0;
    }

    /** 账号密码登录：先客户端 .action，再回落 /sso/login。 */
    public void loginByPassword(String userName, String password) throws Http.ApiError {
        StringBuilder attempts = new StringBuilder();
        try {
            String form = "username=" + Http.enc(userName) + "&password=" + Http.enc(password);
            Http.Response raw = Http.postForm("/ac/api/auth/loginDesktopClient.action", form);
            consume(raw, "登录失败");
            lastLoginRoute = "loginDesktopClient";
            markLoggedIn(userName.trim());
            return;
        } catch (Http.ApiError e) {
            attempts.append("loginDesktopClient: ").append(e.code).append(' ').append(e.getMessage());
            if ("1014".equals(e.code)) {
                boolean need = needCaptcha();
                throw new Http.ApiError("1014", need
                        ? "需要图形验证码（请先在网页端登录一次）或账号密码错误"
                        : "账号或密码错误");
            }
        }
        try {
            String form = "userName=" + Http.enc(userName) + "&password=" + Http.enc(password)
                    + "&rememberMe=true";
            Http.Response raw = Http.postForm("/sso/login", form);
            consume(raw, "登录失败");
            lastLoginRoute = "sso/login";
            markLoggedIn(userName.trim());
            return;
        } catch (Http.ApiError e) {
            attempts.append(" | sso/login: ").append(e.code).append(' ').append(e.getMessage());
        }
        throw new Http.ApiError("", attempts.toString());
    }

    /** 发短信验证码（1016 频控 / 1022 手机号不存在）。 */
    public void sendSmsCode(String phone) throws Http.ApiError {
        Http.Response raw = Http.postForm("/ac/api/auth/sendDesktopClientPhoneCode.action",
                "phoneNum=" + Http.enc(phone));
        expectOk(raw, "验证码发送失败");
    }

    /** 短信登录（字段 phoneNum + messageCode）。 */
    public void loginBySmsCode(String phone, String code) throws Http.ApiError {
        Http.Response raw = Http.postForm("/ac/api/auth/loginDesktopClientByPhoneCode.action",
                "phoneNum=" + Http.enc(phone) + "&messageCode=" + Http.enc(code));
        consume(raw, "登录失败");
        markLoggedIn("");
    }

    public UserInfo refreshUser() throws Http.ApiError {
        JSONObject data = Http.get("/acx/user/users/current-user-info?includeToken=true&refresh=true");
        UserInfo me = new UserInfo();
        me.id = J.str(data, "id");
        me.userName = J.str(data, "userName");
        me.fullName = J.str(data, "fullName");
        me.mobile = J.str(data, "mobilephoneNum");
        me.email = J.str(data, "email");
        me.acctRole = J.str(data, "acctRole");
        // ⚠️ 不要用这里的 token 覆盖登录 token：`includeToken=true` 回的字段与
        // 登录拿到的 accessToken 不是一回事（HAP 版也不覆盖）。覆盖过一次就会
        // 变成"登录成功 → 后续请求全 401 → 被踢回登录页"，看起来像闪退。
        return me;
    }

    public ChatConfig chatConfig() throws Http.ApiError {
        JSONObject data = Http.get("/acx/chatbot/config/list");
        ChatConfig cfg = new ChatConfig();
        JSONArray qs = J.ja(data, "recommendQuestion");
        java.util.List<String> list = new java.util.ArrayList<>();
        for (int i = 0; i < qs.length(); i++) {
            String q = J.safe(qs.optString(i));
            if (q.length() > 0) {
                list.add(q);
            }
        }
        cfg.recommend = list.toArray(new String[0]);
        cfg.defaultIdentify = J.str(data, "defaultIdentify");
        return cfg;
    }

    /** 13 个集群（按账号 × 集群返回多行，去重；inactive 排后面）。 */
    public java.util.List<ClusterInfo> clusters() {
        java.util.List<ClusterInfo> out = new java.util.ArrayList<>();
        try {
            JSONArray rows = Http.getArray("/acx/user/users/cluster-user-detail");
            java.util.Set<Integer> seen = new java.util.HashSet<>();
            java.util.List<ClusterInfo> inactive = new java.util.ArrayList<>();
            for (int i = 0; i < rows.length(); i++) {
                JSONObject row = J.at(rows, i);
                int id = J.i(row, "clusterId");
                if (id <= 0 || seen.contains(id)) {
                    continue;
                }
                seen.add(id);
                ClusterInfo c = new ClusterInfo();
                c.clusterId = id;
                c.clusterName = J.str(row, "clusterName", "集群 " + id);
                c.accountId = J.str(row, "accountId");
                c.groupId = J.str(row, "groupId");
                c.createUser = J.str(row, "userId");
                c.status = J.str(row, "status");
                if ("inactive".equals(c.status)) {
                    inactive.add(c);
                } else {
                    out.add(c);
                }
            }
            out.addAll(inactive);
        } catch (Exception ignored) {
        }
        return out;
    }

    /**
     * 集群身份。⚠️ authorize / 团队 key 必须用这里的 **集群 accountId**，
     * 用 current-user-info.id 会 API010006 无权限访问。
     */
    public Identity clusterIdentity() {
        Identity identity = new Identity();
        try {
            JSONArray rows = Http.getArray("/acx/user/users/cluster-user-detail");
            for (int i = 0; i < rows.length(); i++) {
                JSONObject row = J.at(rows, i);
                String accountId = J.str(row, "accountId");
                String groupId = J.str(row, "groupId");
                String userId = J.str(row, "userId");
                String status = J.str(row, "status");
                if (accountId.length() > 0 && groupId.length() > 0 && userId.length() > 0
                        && !"inactive".equals(status)) {
                    identity.accountId = accountId;
                    identity.groupId = groupId;
                    identity.createUser = userId;
                    identity.clusterName = J.str(row, "clusterName");
                    return identity;
                }
            }
        } catch (Exception ignored) {
        }
        return identity;
    }

    /** 平台智能体服务表（只保留 aiagent-router，见 model/Pick.ets 的实测结论）。 */
    public java.util.List<AgentService> agentServices() {
        java.util.List<AgentService> out = new java.util.ArrayList<>();
        try {
            JSONArray rows = Http.getArray("/acx/chatbot/recommend/list?enable=true");
            for (int i = 0; i < rows.length(); i++) {
                JSONObject row = J.at(rows, i);
                AgentService s = new AgentService();
                s.identify = J.str(row, "identify");
                s.name = J.str(row, "aiAssistantName", "智能体服务");
                s.description = J.str(row, "description");
                try {
                    s.modelId = Integer.parseInt(J.str(row, "modelId"));
                } catch (Exception e) {
                    s.modelId = 0;
                }
                out.add(s);
            }
        } catch (Exception ignored) {
        }
        return out;
    }

    public java.util.List<Conversation> conversationList() {
        java.util.List<Conversation> out = new java.util.ArrayList<>();
        try {
            JSONObject page = Http.get("/acx/chatbot/conversation/list?page=1&size=30");
            JSONArray records = J.ja(page, "records");
            for (int i = 0; i < records.length(); i++) {
                JSONObject row = J.at(records, i);
                Conversation c = new Conversation();
                c.id = J.str(row, "id");
                c.title = J.str(row, "title");
                c.createTime = J.str(row, "createTime");
                c.taskStatus = J.str(row, "taskStatus");
                if (c.id.length() > 0) {
                    out.add(c);
                }
            }
        } catch (Exception ignored) {
        }
        return out;
    }

    /** 平台历史会话（只读）。 */
    public java.util.List<HistoryMessage> loadHistory(String conversationId) {
        java.util.List<HistoryMessage> out = new java.util.ArrayList<>();
        try {
            JSONObject page = Http.get("/acx/chatbot/v2/agent/conversation/"
                    + conversationId + "/history?page=1&size=50");
            JSONArray messages = J.ja(page, "messages");
            for (int i = 0; i < messages.length(); i++) {
                JSONObject m = J.at(messages, i);
                String text = J.safe(J.str(m, "text"));
                if (text.length() == 0) {
                    JSONArray inputs = J.ja(m, "inputs");
                    for (int k = 0; k < inputs.length(); k++) {
                        String t = J.safe(J.str(J.at(inputs, k), "text"));
                        if (t.length() > 0) {
                            text = t;
                            break;
                        }
                    }
                }
                if (text.length() == 0) {
                    continue;
                }
                HistoryMessage hm = new HistoryMessage();
                hm.role = "user".equals(J.str(m, "role")) ? "user" : "assistant";
                hm.text = text;
                out.add(hm);
            }
        } catch (Exception ignored) {
        }
        return out;
    }

    public boolean renameConversation(String conversationId, String title) {
        try {
            JSONObject body = new JSONObject();
            body.put("conversationId", conversationId);
            body.put("title", title);
            Http.postJson("/acx/chatbot/conversation/rename", body.toString());
            return true;
        } catch (Exception e) {
            return false;
        }
    }

    public void logout() {
        try {
            Http.postForm("/ac/api/auth/logoutDesktopClient.action", "");
        } catch (Exception e) {
            try {
                Http.get("/acx/user/users/logout");
            } catch (Exception ignored) {
            }
        }
        Http.token = "";
        Http.cookie = "";
        Store.get().clearCloudAuth();
        Store.get().setAutoKey("");
        noteManualLogout();
    }

    /** 平台是否要求图形验证码（厂商拼写就是 isNeedCpatcha）。 */
    public boolean needCaptcha() {
        try {
            JSONObject env = Http.envelope(Http.send("GET",
                    Http.CLOUD + "/ac/api/auth/isNeedCpatcha.action", Http.baseHeaders(true), null));
            return "true".equals(String.valueOf(env.opt("data")));
        } catch (Exception e) {
            return false;
        }
    }

    private void markLoggedIn(String userName) {
        if (userName.length() > 0) {
            Store.get().setPlatformUserName(userName);
        }
        Store.get().setHadSession(true);
        loginReason = "";
    }

    /** 登录响应：可能是 JSON，也可能是 SSO 的 HTML 页面。 */
    private void consume(Http.Response raw, String fallback) throws Http.ApiError {
        String text = raw.body == null ? "" : raw.body.trim();
        if (text.startsWith("{")) {
            JSONObject env;
            try {
                env = new JSONObject(text);
            } catch (Exception e) {
                throw new Http.ApiError("", "登录响应不是合法 JSON");
            }
            String code = J.str(env, "code");
            if (code.length() > 0 && !"0".equals(code) && !"200".equals(code)) {
                throw new Http.ApiError(code, J.str(env, "msg", fallback));
            }
            JSONObject data = J.jo(env, "data");
            String token = J.str(data, "token");
            if (token.length() == 0) {
                token = J.str(data, "accessToken");
            }
            if (token.length() > 0) {
                Http.token = token;
                Store.get().setCloudToken(token);
            }
        }
        // 平台把 SSO token 也放在 cookie 里（Token=…）
        if (Http.token.length() == 0 && Http.cookie.length() > 0) {
            int idx = Http.cookie.indexOf("Token=");
            if (idx >= 0) {
                String rest = Http.cookie.substring(idx + 6);
                int end = rest.indexOf(';');
                String token = end >= 0 ? rest.substring(0, end) : rest;
                if (token.length() > 0) {
                    Http.token = token;
                    Store.get().setCloudToken(token);
                }
            }
        }
        if (Http.token.length() == 0) {
            String tail = text.length() > 120 ? text.substring(0, 120) : text;
            throw new Http.ApiError("", "登录成功但没拿到 token（响应：" + tail + "）");
        }
    }

    private void expectOk(Http.Response raw, String fallback) throws Http.ApiError {
        JSONObject env = J.obj(raw.body == null ? "" : raw.body);
        String code = J.str(env, "code");
        if (code.length() > 0 && !"0".equals(code) && !"200".equals(code)) {
            throw new Http.ApiError(code, J.str(env, "msg", fallback));
        }
    }

    /** 平台错误码 → 中文文案。 */
    public static String describe(String code, String msg) {
        if ("1003".equals(code)) {
            return "登录参数缺失（服务端契约变了，请反馈给开发者）";
        }
        if ("1014".equals(code)) {
            return "账号或密码错误";
        }
        if ("1006".equals(code)) {
            return "验证码错误或已过期";
        }
        if ("1016".equals(code)) {
            return "验证码发送失败（可能是频率限制，稍后再试）";
        }
        if ("1022".equals(code)) {
            return "该手机号未注册";
        }
        return msg != null && msg.length() > 0 ? msg : "登录失败 (" + code + ")";
    }
}
