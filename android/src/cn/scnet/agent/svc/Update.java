package cn.scnet.agent.svc;

import android.app.DownloadManager;
import android.content.Context;
import android.net.Uri;
import android.os.Environment;

import org.json.JSONObject;

import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.Charset;

import cn.scnet.agent.core.Http;
import cn.scnet.agent.core.J;
import cn.scnet.agent.core.Store;

/**
 * 应用内更新。
 *
 * 仓库是 private 时，匿名访问 GitHub 的 releases 页/API 都是 404，所以这里做两路：
 *  1) **自定义更新源**（推荐）：一个公开的 JSON，格式见下，地址在「设置 → 调试 → 更新源」里配。
 *     {"versionName":"0.5.3","versionCode":13,
 *      "url":"https://…/scnet-agent-android-0.5.3.apk","notes":"修了什么"}
 *  2) GitHub Releases API（仓库转公开后自动可用）：
 *     https://api.github.com/repos/lql341/scnet-lite-harmonyos/releases/latest
 *
 * 检查到新版本后，用 DownloadManager 下载到公共下载目录，完成后交给系统安装器。
 */
public class Update {

    public static final String GITHUB_API =
            "https://api.github.com/repos/lql341/scnet-lite-harmonyos/releases/latest";
    public static final String RELEASES_PAGE =
            "https://github.com/lql341/scnet-lite-harmonyos/releases";

    public static class Info {
        public String versionName = "";
        public int versionCode;
        public String url = "";
        public String notes = "";
        /** 来源说明（自定义源 / GitHub） */
        public String source = "";
        /** 失败原因（空 = 成功） */
        public String error = "";
        /** 是否有更新 */
        public boolean newer;
    }

    /** 检查更新（阻塞，调用方在后台线程）。 */
    public static Info check(Context context) {
        Info info = new Info();
        int currentCode = currentVersionCode(context);
        String currentName = currentVersionName(context);

        String custom = Store.get().getUpdateUrl();
        if (custom.length() > 0) {
            info.source = "custom";
            if (parse(fetch(custom), info)) {
                info.newer = info.versionCode > currentCode
                        || (info.versionCode == 0 && newer(info.versionName, currentName));
                return info;
            }
            info.error = "自定义更新源不可用（" + info.error + "）";
            return info;
        }

        info.source = "github";
        String body = fetch(GITHUB_API);
        if (body.startsWith("{")) {
            try {
                JSONObject release = new JSONObject(body);
                info.versionName = J.str(release, "tag_name");
                info.notes = J.str(release, "body");
                org.json.JSONArray assets = J.ja(release, "assets");
                for (int i = 0; i < assets.length(); i++) {
                    JSONObject asset = J.at(assets, i);
                    String name = J.str(asset, "name");
                    if (name.endsWith(".apk")) {
                        info.url = J.str(asset, "browser_download_url");
                        break;
                    }
                }
                if (info.url.length() > 0) {
                    info.newer = newer(info.versionName, currentName);
                    return info;
                }
                info.error = "Release 里没有 APK";
            } catch (Exception e) {
                info.error = "解析失败：" + e.getMessage();
            }
        } else {
            int code = lastStatus;
            info.error = (code == 404 || code == 401 || code == 403)
                    ? "仓库是私有/受限的，匿名无法检查（可把仓库转公开，或在设置里配自定义更新源）"
                    : "请求失败（HTTP " + code + "）";
        }
        return info;
    }

    /** v0.5.3 vs 0.5.2 → true */
    private static boolean newer(String tag, String current) {
        int[] a = version(tag);
        int[] b = version(current);
        for (int i = 0; i < 3; i++) {
            if (a[i] != b[i]) {
                return a[i] > b[i];
            }
        }
        return false;
    }

    private static int[] version(String text) {
        int[] out = new int[3];
        if (text == null) {
            return out;
        }
        String digits = text.replaceAll("[^0-9.]", " ").trim().split(" ")[0];
        String[] parts = digits.split("\\.");
        for (int i = 0; i < 3 && i < parts.length; i++) {
            try {
                out[i] = Integer.parseInt(parts[i]);
            } catch (Exception ignored) {
            }
        }
        return out;
    }

    private static boolean parse(String body, Info info) {
        try {
            JSONObject json = new JSONObject(body);
            info.versionName = J.str(json, "versionName", J.str(json, "tag_name"));
            info.versionCode = J.i(json, "versionCode");
            info.url = J.str(json, "url", J.str(json, "apk"));
            info.notes = J.str(json, "notes", J.str(json, "body"));
            if (info.url.length() == 0) {
                info.error = "JSON 里没有 url/apk 字段";
                return false;
            }
            return true;
        } catch (Exception e) {
            info.error = "不是合法 JSON";
            return false;
        }
    }

    private static int lastStatus;

    private static String fetch(String url) {
        HttpURLConnection conn = null;
        lastStatus = 0;
        try {
            conn = (HttpURLConnection) new URL(url).openConnection();
            conn.setConnectTimeout(12000);
            conn.setReadTimeout(20000);
            conn.setRequestProperty("Accept", "application/vnd.github+json");
            conn.setRequestProperty("User-Agent", "SCNetAgent-Android");
            lastStatus = conn.getResponseCode();
            InputStream in = lastStatus >= 400 ? conn.getErrorStream() : conn.getInputStream();
            if (in == null) {
                return "";
            }
            return Http.readAll(in);
        } catch (Exception e) {
            lastStatus = -1;
            return "";
        } finally {
            if (conn != null) {
                conn.disconnect();
            }
        }
    }

    public static int currentVersionCode(Context context) {
        try {
            return context.getPackageManager().getPackageInfo(context.getPackageName(), 0)
                    .versionCode;
        } catch (Exception e) {
            return 0;
        }
    }

    public static String currentVersionName(Context context) {
        try {
            return context.getPackageManager().getPackageInfo(context.getPackageName(), 0)
                    .versionName;
        } catch (Exception e) {
            return "";
        }
    }

    /** 下载 APK（DownloadManager，进公共下载目录，完成通知可点装）。 */
    public static long download(Context context, Info info) {
        DownloadManager.Request req = new DownloadManager.Request(Uri.parse(info.url));
        String name = info.url.substring(info.url.lastIndexOf('/') + 1);
        if (!name.endsWith(".apk")) {
            name = "scnet-agent-android-" + info.versionName + ".apk";
        }
        req.setTitle("SCNet 智能体 " + info.versionName);
        req.setMimeType("application/vnd.android.package-archive");
        req.setNotificationVisibility(
                DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED);
        req.setDestinationInExternalPublicDir(Environment.DIRECTORY_DOWNLOADS,
                name.replaceAll("[^A-Za-z0-9._-]", "_"));
        DownloadManager dm = (DownloadManager) context.getSystemService(Context.DOWNLOAD_SERVICE);
        if (dm == null) {
            return -1;
        }
        return dm.enqueue(req);
    }
}
