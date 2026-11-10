package cn.scnet.agent.core;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.net.URLEncoder;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * 平台 HTTP 客户端（对齐 ArkTS 的 service/Http.ets）。
 *
 * 平台鉴权是**双头**：`Token` + `Cookie`，缺一个就 401。所以这里不能只存 token，
 * 还要在每次响应里抓 `Set-Cookie`（登录接口把 SSO token 藏在 cookie 里）。
 *
 * 401 统一回调（UI 层注册后跳登录页），与 ArkTS 版一致。
 */
public class Http {

    /** 平台主域：业务接口都在 /acx 下；网关是 api.scnet.cn/api/llm/v1（另一套）。 */
    public static final String CLOUD = "https://www.scnet.cn";
    public static final String API = "https://api.scnet.cn";

    /** source 头标识客户端；version 是平台协议版本。 */
    public static String token = "";
    public static String cookie = "";
    public static String version = "1.0.0";
    public static String source = "Android";

    /** 平台错误码 + 文案。 */
    public static class ApiError extends Exception {
        public final String code;

        public ApiError(String code, String message) {
            super(message);
            this.code = code == null ? "" : code;
        }
    }

    public interface UnauthorizedHandler {
        void onUnauthorized();
    }

    private static UnauthorizedHandler unauthorized = null;

    public static void setUnauthorizedHandler(UnauthorizedHandler handler) {
        unauthorized = handler;
    }

    public static class Response {
        public int status;
        public String body = "";
        public Map<String, List<String>> headers = new LinkedHashMap<>();
    }

    /** 实际使用的平台基地址：设置了 debugApiBase 就用它（联调用，正式包默认空）。 */
    public static String base() {
        try {
            String override = Store.get().getDebugBase();
            if (override != null && override.trim().length() > 0) {
                return J.trimSlash(override.trim());
            }
        } catch (Exception ignored) {
        }
        return CLOUD;
    }

    public static Map<String, String> baseHeaders(boolean json) {
        Map<String, String> head = new LinkedHashMap<>();
        head.put("Content-Type", json ? "application/json" : "application/x-www-form-urlencoded");
        head.put("Accept", "application/json");
        head.put("source", source);
        head.put("version", version);
        if (token.length() > 0) {
            head.put("Token", token);
        }
        if (cookie.length() > 0) {
            head.put("Cookie", cookie);
        }
        return head;
    }

    /** 发请求，返回原始响应（含状态码与头）。 */
    public static Response send(String method, String url, Map<String, String> headers, byte[] body)
            throws ApiError {
        Response resp = new Response();
        HttpURLConnection conn = null;
        try {
            conn = (HttpURLConnection) new URL(url).openConnection();
            conn.setRequestMethod(method);
            conn.setConnectTimeout(15000);
            conn.setReadTimeout(60000);
            conn.setInstanceFollowRedirects(false);
            if (headers != null) {
                for (Map.Entry<String, String> e : headers.entrySet()) {
                    if (e.getValue() != null && e.getValue().length() > 0) {
                        conn.setRequestProperty(e.getKey(), e.getValue());
                    }
                }
            }
            if (body != null && body.length > 0
                    && !"GET".equals(method) && !"DELETE".equals(method)) {
                conn.setDoOutput(true);
                InputStream in = new java.io.ByteArrayInputStream(body);
                OutputStream out = conn.getOutputStream();
                Sse.copy(in, out);
                out.close();
            } else if (body != null && body.length > 0) {
                conn.setDoOutput(true);
                OutputStream out = conn.getOutputStream();
                out.write(body);
                out.close();
            } else if ("POST".equals(method) || "PUT".equals(method) || "DELETE".equals(method)) {
                // 无 body 的 POST（如 HPC tokens）也要显式发 Content-Length: 0，否则有的网关回 411
                conn.setDoOutput(true);
                conn.setFixedLengthStreamingMode(0);
                conn.getOutputStream().close();
            }

            resp.status = conn.getResponseCode();
            captureCookies(conn);

            InputStream in = resp.status >= 400 ? conn.getErrorStream() : conn.getInputStream();
            resp.body = in == null ? "" : readAll(in);

            Map<String, List<String>> fields = conn.getHeaderFields();
            if (fields != null) {
                resp.headers.putAll(fields);
            }
            return resp;
        } catch (IOException e) {
            throw new ApiError("network", "网络错误：" + e.getMessage());
        } finally {
            if (conn != null) {
                conn.disconnect();
            }
        }
    }

    /** 登录态：平台把 token 也可能放在 Set-Cookie 里（`Token=…`）。 */
    private static void captureCookies(HttpURLConnection conn) {
        List<String> sets = new ArrayList<>();
        for (Map.Entry<String, List<String>> e : conn.getHeaderFields().entrySet()) {
            String key = e.getKey();
            if (key != null && key.equalsIgnoreCase("Set-Cookie")) {
                sets.addAll(e.getValue());
            }
        }
        if (sets.isEmpty()) {
            return;
        }
        List<String> picked = new ArrayList<>();
        String[] names = {"jsessionid", "Token", "SKIP_SESSION_UPDATE"};
        for (String raw : sets) {
            for (String name : names) {
                int idx = raw.indexOf(name + "=");
                if (idx < 0) {
                    continue;
                }
                int end = idx;
                while (end < raw.length()) {
                    char ch = raw.charAt(end);
                    if (ch == ';' || ch == '\n' || ch == '"') {
                        break;
                    }
                    end++;
                }
                String kv = raw.substring(idx, end).trim();
                if (kv.length() > 0 && !picked.contains(kv)) {
                    picked.add(kv);
                }
            }
        }
        if (!picked.isEmpty()) {
            StringBuilder sb = new StringBuilder();
            for (String kv : picked) {
                if (sb.length() > 0) {
                    sb.append("; ");
                }
                sb.append(kv);
            }
            cookie = sb.toString();
            Store.get().setCloudCookie(cookie);
        }
    }

    public static String readAll(InputStream in) throws IOException {
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        Sse.copy(in, out);
        return new String(out.toByteArray(), "UTF-8");
    }

    /** 解析信封；`code` 非 0/200/空 视为失败。401 会清凭据并回调。 */
    public static org.json.JSONObject envelope(Response resp) throws ApiError {
        String raw = resp.body == null ? "" : resp.body.trim();
        if (raw.length() == 0) {
            throw new ApiError(String.valueOf(resp.status), "空响应 (HTTP " + resp.status + ")");
        }
        org.json.JSONObject env;
        try {
            env = new org.json.JSONObject(raw);
        } catch (Exception e) {
            throw new ApiError(String.valueOf(resp.status),
                    "响应不是 JSON (HTTP " + resp.status + ")");
        }
        String code = J.str(env, "code");
        if ("401".equals(code) || resp.status == 401) {
            token = "";
            cookie = "";
            Store.get().clearCloudAuth();
            if (unauthorized != null) {
                unauthorized.onUnauthorized();
            }
            throw new ApiError("401", "登录已过期，请重新登录");
        }
        if (resp.status != 200) {
            throw new ApiError(code.length() > 0 ? code : String.valueOf(resp.status),
                    J.str(env, "msg", "HTTP " + resp.status));
        }
        if (code.length() > 0 && !"0".equals(code) && !"200".equals(code)) {
            throw new ApiError(code, J.str(env, "msg", "请求失败"));
        }
        return env;
    }

    public static org.json.JSONObject get(String path) throws ApiError {
        Response resp = send("GET", base() + path, baseHeaders(true), null);
        org.json.JSONObject env = envelope(resp);
        return J.jo(env, "data");
    }

    /** 有些接口 data 是数组，单独给一个。 */
    public static org.json.JSONArray getArray(String path) throws ApiError {
        Response resp = send("GET", base() + path, baseHeaders(true), null);
        org.json.JSONObject env = envelope(resp);
        return J.ja(env, "data");
    }

    public static org.json.JSONObject postJson(String path, String json) throws ApiError {
        Response resp = send("POST", base() + path, baseHeaders(true),
                json.getBytes(java.nio.charset.Charset.forName("UTF-8")));
        org.json.JSONObject env = envelope(resp);
        return J.jo(env, "data");
    }

    /** 表单 POST（SSO 那套是 x-www-form-urlencoded，不是 JSON）。 */
    public static Response postForm(String path, String form) throws ApiError {
        Map<String, String> head = baseHeaders(false);
        head.put("Accept", "application/json, text/plain, */*");
        return send("POST", base() + path, head,
                form.getBytes(java.nio.charset.Charset.forName("UTF-8")));
    }

    /** 登录类接口要拿 Set-Cookie，所以返回原始响应。 */
    public static Response postRaw(String path, String json) throws ApiError {
        return send("POST", base() + path, baseHeaders(true),
                json.getBytes(java.nio.charset.Charset.forName("UTF-8")));
    }

    public static String enc(String value) {
        try {
            return URLEncoder.encode(value == null ? "" : value, "UTF-8");
        } catch (Exception e) {
            return "";
        }
    }
}
