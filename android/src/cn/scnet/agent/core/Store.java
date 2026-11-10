package cn.scnet.agent.core;

import android.content.Context;
import android.content.SharedPreferences;

/**
 * 本地偏好（对齐 ArkTS 的 service/Store.ets）。用 SharedPreferences，
 * 所有键名与 ArkTS 版一致，方便对照排查。
 */
public class Store {

    public static final String DEFAULT_MODEL = "SCNet-Max";
    public static final String DEFAULT_BASE_URL = "https://api.scnet.cn/api/llm/v1";

    private static Store instance;

    private final SharedPreferences prefs;

    private Store(Context context) {
        prefs = context.getApplicationContext()
                .getSharedPreferences("scnet_lite", Context.MODE_PRIVATE);
    }

    public static synchronized void init(Context context) {
        if (instance == null) {
            instance = new Store(context);
        }
    }

    public static Store get() {
        if (instance == null) {
            throw new IllegalStateException("Store.init(context) 先调用");
        }
        return instance;
    }

    private String read(String key, String fallback) {
        try {
            String v = prefs.getString(key, fallback);
            return v == null ? fallback : v;
        } catch (Exception e) {
            return fallback;
        }
    }

    private int readInt(String key, int fallback) {
        try {
            return prefs.getInt(key, fallback);
        } catch (Exception e) {
            return fallback;
        }
    }

    private void write(String key, String value) {
        try {
            prefs.edit().putString(key, value == null ? "" : value).apply();
        } catch (Exception ignored) {
        }
    }

    private void writeInt(String key, int value) {
        try {
            prefs.edit().putInt(key, value).apply();
        } catch (Exception ignored) {
        }
    }

    // ---- 网关 ----
    public String getApiKey() {
        return read("apiKey", "");
    }

    public void setApiKey(String v) {
        write("apiKey", v);
    }

    public String getBaseUrl() {
        return read("baseUrl", DEFAULT_BASE_URL);
    }

    public void setBaseUrl(String v) {
        write("baseUrl", v);
    }

    public String getModel() {
        return read("model", DEFAULT_MODEL);
    }

    public void setModel(String v) {
        write("model", v);
    }

    /** 自动取到的网关 key（登录后免手填）。 */
    public String getAutoKey() {
        return read("autoGatewayKey", "");
    }

    public void setAutoKey(String v) {
        write("autoGatewayKey", v);
    }

    // ---- 外观 ----
    public String getTheme() {
        return read("themePalette", "claude");
    }

    public void setTheme(String v) {
        write("themePalette", v);
    }

    /** system | light | dark */
    public String getColorMode() {
        return read("colorMode", "system");
    }

    public void setColorMode(String v) {
        write("colorMode", v);
    }

    /** 0 小 · 1 标准 · 2 大 */
    public int getFontLevel() {
        return readInt("fontLevel", 1);
    }

    public void setFontLevel(int v) {
        writeInt("fontLevel", v);
    }

    /** zh | en */
    public String getLang() {
        return read("lang", "zh");
    }

    public void setLang(String v) {
        write("lang", v);
    }

    /** '' = 首字；'preset:<id>'；'file:<path>' */
    public String getAvatar() {
        return read("avatar", "");
    }

    public void setAvatar(String v) {
        write("avatar", v);
    }

    // ---- 账号 ----
    public String getPlatformUserName() {
        return read("platformUserName", "");
    }

    public void setPlatformUserName(String v) {
        write("platformUserName", v);
    }

    public boolean hadSession() {
        return "1".equals(read("hadSession", ""));
    }

    public void setHadSession(boolean v) {
        write("hadSession", v ? "1" : "");
    }

    public String getCloudToken() {
        return read("cloudToken", "");
    }

    public void setCloudToken(String v) {
        write("cloudToken", v);
    }

    public String getCloudCookie() {
        return read("cloudCookie", "");
    }

    public void setCloudCookie(String v) {
        write("cloudCookie", v);
    }

    public void clearCloudAuth() {
        write("cloudToken", "");
        write("cloudCookie", "");
    }

    // ---- 通道 / 集群 ----
    public String getChannel() {
        return read("channel", "agent");
    }

    public void setChannel(String v) {
        write("channel", v);
    }

    public String getAgent() {
        return read("agentIdentify", "aiagent-router");
    }

    public void setAgent(String v) {
        write("agentIdentify", v);
    }

    public int getClusterId() {
        return readInt("clusterId", 0);
    }

    public void setClusterId(int v) {
        writeInt("clusterId", v);
    }

    // ---- 自定义 provider ----
    public String getModelProvider() {
        return read("modelProvider", "platform");
    }

    public void setModelProvider(String v) {
        write("modelProvider", v);
    }

    public String getCustomName() {
        return read("customProviderName", "");
    }

    public String getCustomBaseUrl() {
        return read("customProviderUrl", "");
    }

    public String getCustomApiKey() {
        return read("customProviderKey", "");
    }

    public String getCustomModel() {
        return read("customProviderModel", "");
    }

    public void setCustomProvider(String name, String baseUrl, String apiKey, String model) {
        write("customProviderName", name);
        write("customProviderUrl", baseUrl);
        write("customProviderKey", apiKey);
        write("customProviderModel", model);
        write("modelProvider", "custom");
    }

    public void clearCustomProvider() {
        write("customProviderName", "");
        write("customProviderUrl", "");
        write("customProviderKey", "");
        write("customProviderModel", "");
        write("modelProvider", "platform");
    }

    /** 调试用：把平台域名换成自建 mock（空 = 用 https://www.scnet.cn）。 */
    public String getDebugBase() {
        return read("debugApiBase", "");
    }

    public void setDebugBase(String v) {
        write("debugApiBase", v);
    }

    // ---- HPC（AK/SK） ----
    public String getHpcAk() {
        return read("hpcAk", "");
    }

    public void setHpcAk(String v) {
        write("hpcAk", v);
    }

    public String getHpcSk() {
        return read("hpcSk", "");
    }

    public void setHpcSk(String v) {
        write("hpcSk", v);
    }

    public String getHpcUser() {
        return read("hpcUser", "");
    }

    public void setHpcUser(String v) {
        write("hpcUser", v);
    }
}
