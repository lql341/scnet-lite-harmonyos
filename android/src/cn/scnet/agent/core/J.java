package cn.scnet.agent.core;

import org.json.JSONArray;
import org.json.JSONObject;

/**
 * JSON 便捷读取（org.json 是 Android 框架自带，不用引三方库）。
 * 平台响应字段经常缺失或类型漂移，这里统一做"取不到就给默认值"。
 */
public final class J {

    private J() {
    }

    public static JSONObject obj(String text) {
        try {
            return new JSONObject(text);
        } catch (Exception e) {
            return new JSONObject();
        }
    }

    public static JSONArray arr(String text) {
        try {
            return new JSONArray(text);
        } catch (Exception e) {
            return new JSONArray();
        }
    }

    public static String str(JSONObject o, String key) {
        if (o == null) {
            return "";
        }
        Object v = o.opt(key);
        if (v == null || v == JSONObject.NULL) {
            return "";
        }
        return String.valueOf(v);
    }

    public static String str(JSONObject o, String key, String fallback) {
        String v = str(o, key);
        return v.length() == 0 ? fallback : v;
    }

    public static int i(JSONObject o, String key) {
        if (o == null) {
            return 0;
        }
        Object v = o.opt(key);
        if (v instanceof Number) {
            return ((Number) v).intValue();
        }
        try {
            return Integer.parseInt(String.valueOf(v));
        } catch (Exception e) {
            return 0;
        }
    }

    public static long l(JSONObject o, String key) {
        if (o == null) {
            return 0L;
        }
        Object v = o.opt(key);
        if (v instanceof Number) {
            return ((Number) v).longValue();
        }
        try {
            return Long.parseLong(String.valueOf(v));
        } catch (Exception e) {
            return 0L;
        }
    }

    public static boolean b(JSONObject o, String key) {
        if (o == null) {
            return false;
        }
        Object v = o.opt(key);
        if (v instanceof Boolean) {
            return (Boolean) v;
        }
        return "true".equals(String.valueOf(v));
    }

    public static JSONObject jo(JSONObject o, String key) {
        if (o == null) {
            return new JSONObject();
        }
        Object v = o.opt(key);
        return v instanceof JSONObject ? (JSONObject) v : new JSONObject();
    }

    public static JSONArray ja(JSONObject o, String key) {
        if (o == null) {
            return new JSONArray();
        }
        Object v = o.opt(key);
        return v instanceof JSONArray ? (JSONArray) v : new JSONArray();
    }

    public static JSONObject at(JSONArray a, int index) {
        Object v = a == null ? null : a.opt(index);
        return v instanceof JSONObject ? (JSONObject) v : new JSONObject();
    }

    /** 平台 `data` 有时是再包了一层字符串的 JSON，统一拆开。 */
    public static Object unwrapData(String text) {
        try {
            JSONObject root = new JSONObject(text);
            Object data = root.opt("data");
            if (data instanceof String) {
                String s = ((String) data).trim();
                if (s.startsWith("{") || s.startsWith("[")) {
                    try {
                        return s.startsWith("{") ? new JSONObject(s) : new JSONArray(s);
                    } catch (Exception ignored) {
                        return data;
                    }
                }
            }
            return data == null ? root : data;
        } catch (Exception e) {
            return new JSONObject();
        }
    }

    public static String trimSlash(String url) {
        String out = url == null ? "" : url.trim();
        while (out.endsWith("/")) {
            out = out.substring(0, out.length() - 1);
        }
        return out;
    }

    public static String safe(String value) {
        return value == null ? "" : value.trim();
    }
}
