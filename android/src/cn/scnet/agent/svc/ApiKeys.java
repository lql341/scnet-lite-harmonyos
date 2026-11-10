package cn.scnet.agent.svc;

import org.json.JSONArray;
import org.json.JSONObject;

import java.util.ArrayList;
import java.util.List;

import cn.scnet.agent.core.Http;
import cn.scnet.agent.core.J;
import cn.scnet.agent.core.Store;

/**
 * 网关（LLM）凭据获取（对齐 ArkTS 的 service/ApiKeys.ets）。
 *
 * 链路：cluster 身份 → account/config/status →（必要时）authorize
 *      → createActivityApiKey（一把到手）→ 兜底 api-key/query。
 *
 * 实测要点：
 * - accountId 必须是**集群账号**，用户 id 会 API010006；
 * - 授权成功但余额 0 → chat 仍 402（只有 SCNet-Max 免费）；
 * - 平台下发的 baseUrl 是 /api/llm/v1；
 * - /api-key/query 只支持 POST。
 */
public class ApiKeys {

    public static final String LLM_BASE = "https://api.scnet.cn/api/llm/v1";

    private static final String[] KEY_FIELDS =
            {"apiKey", "key", "secretKey", "apiKeyValue", "credential"};

    public static class Access {
        public String key = "";
        public String baseUrl = "";
        public String model = "";
        /** activity / existing / created / cached / none */
        public String source = "none";
    }

    public static class Status {
        public int modelServiceEnabled = -1;
        public int unpaidStatus = -1;
        public String scope = "";
    }

    private static final ApiKeys INSTANCE = new ApiKeys();

    public static ApiKeys get() {
        return INSTANCE;
    }

    /** 需要人介入时的文案（空 = 没问题）。 */
    public String lastBlocked = "";

    public Status accountStatus(String accountId) {
        if (accountId.length() == 0) {
            return null;
        }
        try {
            JSONObject data = Http.get("/acx/llm/account/config/status?accountId=" + accountId);
            Status s = new Status();
            s.modelServiceEnabled = J.i(data, "modelServiceEnabled");
            s.unpaidStatus = J.i(data, "unpaidStatus");
            s.scope = J.str(data, "accessibleModelScope");
            return s;
        } catch (Exception e) {
            return null;
        }
    }

    /** 开通平台模型服务（官方客户端登录后自动做）。 */
    public boolean authorize(String accountId) {
        if (accountId.length() == 0) {
            return false;
        }
        try {
            Http.postForm("/acx/llm/account/config/authorize?accountId=" + accountId, "");
            Status after = accountStatus(accountId);
            return after != null && after.modelServiceEnabled == 1;
        } catch (Exception e) {
            return false;
        }
    }

    private Access activityKey() {
        Access empty = new Access();
        try {
            Http.Response raw = Http.postRaw("/acx/llm/api-key/createActivityApiKey", "{}");
            String text = raw.body == null ? "" : raw.body;
            if (text.length() == 0) {
                return empty;
            }
            Object data = J.unwrapData(text);
            if (!(data instanceof JSONObject)) {
                return empty;
            }
            JSONObject obj = (JSONObject) data;
            String key = pickKey(obj);
            if (key.length() == 0) {
                return empty;
            }
            Access access = new Access();
            access.key = key;
            access.baseUrl = J.trimSlash(J.str(obj, "baseUrl"));
            access.model = J.str(obj, "model");
            access.source = "activity";
            return access;
        } catch (Exception e) {
            return empty;
        }
    }

    private Access queryExisting() {
        Access empty = new Access();
        empty.baseUrl = LLM_BASE;
        try {
            Http.Response raw = Http.postRaw("/acx/llm/api-key/query", "{}");
            String text = raw.body == null ? "" : raw.body;
            if (text.length() == 0) {
                return empty;
            }
            Object payload = J.unwrapData(text);
            JSONArray rows = payload instanceof JSONArray ? (JSONArray) payload : new JSONArray();
            for (int i = 0; i < rows.length(); i++) {
                String key = pickKey(J.at(rows, i));
                if (key.length() > 0) {
                    Access found = new Access();
                    found.key = key;
                    found.baseUrl = LLM_BASE;
                    found.source = "existing";
                    return found;
                }
            }
            return empty;
        } catch (Exception e) {
            return empty;
        }
    }

    /** 全链路：缓存 → status/authorize → activity key → query。 */
    public Access ensureAccess(Auth.Identity identity) {
        lastBlocked = "";
        String cached = Store.get().getAutoKey();
        if (cached.length() >= 20) {
            Access hit = new Access();
            hit.key = cached;
            hit.baseUrl = Store.get().getBaseUrl();
            hit.model = Store.get().getModel();
            hit.source = "cached";
            return hit;
        }
        if (identity.accountId.length() == 0) {
            lastBlocked = "拿不到集群身份（cluster-user-detail），无法授权/取 key";
            return new Access();
        }
        Status status = accountStatus(identity.accountId);
        if (status != null) {
            if (status.modelServiceEnabled != 1) {
                if (status.unpaidStatus == 1) {
                    lastBlocked = "账号有未结清账单，模型服务被暂停（网关会返回 402）";
                } else if (!authorize(identity.accountId)) {
                    lastBlocked = "模型服务未开通（authorize 未生效）";
                }
            } else if (status.unpaidStatus == 1) {
                lastBlocked = "账号有未结清账单，模型服务可能被限（网关可能返回 402）";
            }
        }
        Access access = activityKey();
        if (access.key.length() == 0) {
            access = queryExisting();
        }
        if (access.key.length() == 0) {
            if (lastBlocked.length() == 0) {
                lastBlocked = "拿不到网关 key（授权未开通或接口变更）";
            }
            return access;
        }
        if (access.baseUrl.length() == 0) {
            access.baseUrl = LLM_BASE;
        }
        Store.get().setAutoKey(access.key);
        Store.get().setBaseUrl(access.baseUrl);
        return access;
    }

    /** 网关模型 id 列表（33 个，只有 SCNet-Max 免费）。 */
    public List<String> listModels(String baseUrl, String key) {
        List<String> out = new ArrayList<>();
        String body = "";
        try {
            Http.Response resp = rawGet(J.trimSlash(baseUrl.length() > 0 ? baseUrl : LLM_BASE)
                    + "/models", key);
            JSONObject parsed = J.obj(resp.body);
            JSONArray list = J.ja(parsed, "data");
            for (int i = 0; i < list.length(); i++) {
                String id = J.str(J.at(list, i), "id");
                if (id.length() > 0) {
                    out.add(id);
                }
            }
        } catch (Exception ignored) {
        }
        return out;
    }

    /** 任意 GET（网关地址不在 www.scnet.cn 下，不能走 Http.get）。 */
    public static Http.Response rawGet(String url, String key) throws Http.ApiError {
        java.util.Map<String, String> head = new java.util.LinkedHashMap<>();
        head.put("Accept", "application/json");
        head.put("Content-Type", "application/json");
        head.put("Authorization", "Bearer " + key);
        return Http.send("GET", url, head, null);
    }

    private static String pickKey(JSONObject data) {
        for (String field : KEY_FIELDS) {
            Object value = data.opt(field);
            if (!(value instanceof String)) {
                continue;
            }
            String text = (String) value;
            // 打码的 key（含 *）跳过
            if (text.length() >= 20 && text.indexOf('*') < 0) {
                return text;
            }
        }
        return "";
    }
}
