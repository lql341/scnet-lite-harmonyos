package cn.scnet.agent.svc;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.util.HashMap;
import java.util.Map;

import cn.scnet.agent.core.Http;
import cn.scnet.agent.core.J;

/**
 * 附件上传 —— 平台 OSS 直传（对齐 ArkTS 的 service/Upload.ets）。
 *
 * 1) POST /acx/chatbot/file/upload/url  → [{fileName, uploadUrl}]（预签名，5 分钟有效）
 * 2) PUT uploadUrl  （**不能带平台 Token/Cookie**，否则 OSS 会拒）
 * 3) 发消息时把 **平台返回的 fileName** 放进 v2 inputs 的 resource.name
 */
public class Upload {

    public static class UploadedFile {
        /** 平台返回的 fileName（不是本地文件名） */
        public String name = "";
        public String mimeType = "";
        public int sizeKb;
        public String localName = "";
    }

    private static final Map<String, String> MIME = new HashMap<>();

    static {
        String[] text = {".txt", ".log", ".out", ".md", ".markdown", ".csv", ".tsv", ".json",
                ".xml", ".yaml", ".yml", ".toml", ".html", ".htm", ".tex", ".bib", ".srt",
                ".py", ".js", ".ts", ".sh", ".c", ".h", ".cpp", ".hpp", ".rs", ".go", ".java",
                ".r", ".m", ".f90", ".f", ".inp"};
        for (String ext : text) {
            MIME.put(ext, "text/plain");
        }
        MIME.put(".md", "text/markdown");
        MIME.put(".markdown", "text/markdown");
        MIME.put(".csv", "text/csv");
        MIME.put(".tsv", "text/tab-separated-values");
        MIME.put(".json", "application/json");
        MIME.put(".xml", "application/xml");
        MIME.put(".html", "text/html");
        MIME.put(".htm", "text/html");
        MIME.put(".pdf", "application/pdf");
        MIME.put(".doc", "application/msword");
        MIME.put(".docx", "application/vnd.openxmlformats-officedocument.wordprocessingml.document");
        MIME.put(".xls", "application/vnd.ms-excel");
        MIME.put(".xlsx", "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet");
        MIME.put(".ppt", "application/vnd.ms-powerpoint");
        MIME.put(".pptx", "application/vnd.openxmlformats-officedocument.presentationml.presentation");
        MIME.put(".rtf", "application/rtf");
        MIME.put(".epub", "application/epub+zip");
        MIME.put(".png", "image/png");
        MIME.put(".jpg", "image/jpeg");
        MIME.put(".jpeg", "image/jpeg");
        MIME.put(".gif", "image/gif");
        MIME.put(".webp", "image/webp");
        MIME.put(".bmp", "image/bmp");
        MIME.put(".svg", "image/svg+xml");
        MIME.put(".heic", "image/heic");
        MIME.put(".tif", "image/tiff");
        MIME.put(".tiff", "image/tiff");
        MIME.put(".mp3", "audio/mpeg");
        MIME.put(".wav", "audio/wav");
        MIME.put(".m4a", "audio/mp4");
        MIME.put(".mp4", "video/mp4");
        MIME.put(".mov", "video/quicktime");
        MIME.put(".zip", "application/zip");
        MIME.put(".tar", "application/x-tar");
        MIME.put(".gz", "application/gzip");
    }

    private static final Upload INSTANCE = new Upload();

    public static Upload get() {
        return INSTANCE;
    }

    /** 最近一次失败原因（UI 直接展示，避免"上传失败"四个字说不清）。 */
    public String lastError = "";

    public static String mimeOf(String name) {
        int dot = name == null ? -1 : name.lastIndexOf('.');
        String ext = dot >= 0 ? name.substring(dot).toLowerCase() : "";
        String hit = MIME.get(ext);
        return hit == null ? "application/octet-stream" : hit;
    }

    /** OCR 端点实测只接受图片 + PDF。 */
    public static boolean isOcrSupported(String name) {
        String mime = mimeOf(name);
        return mime.startsWith("image/") || "application/pdf".equals(mime);
    }

    /** 上传本地字节（调用方已在后台线程）。 */
    public UploadedFile upload(byte[] data, String displayName) {
        lastError = "";
        if (data == null || data.length == 0) {
            lastError = "文件为空（0 字节）：" + displayName;
            return null;
        }
        if (data.length > 40 * 1024 * 1024) {
            lastError = "文件超过 40MB：" + Math.round(data.length / 1048576f) + "MB";
            return null;
        }
        String mime = mimeOf(displayName);
        try {
            String[] ticket = ticket(displayName);
            if (ticket == null) {
                return null;
            }
            if (!put(ticket[1], data, mime)) {
                return null;
            }
            UploadedFile f = new UploadedFile();
            f.name = ticket[0];
            f.mimeType = mime;
            f.sizeKb = data.length / 1024;
            f.localName = displayName;
            return f;
        } catch (Exception e) {
            if (lastError.length() == 0) {
                lastError = "上传到平台失败：" + (e.getMessage() == null ? e.toString() : e.getMessage());
            }
            return null;
        }
    }

    /** 申请上传地址 → [fileName, uploadUrl]。 */
    private String[] ticket(String name) throws Exception {
        JSONObject req = new JSONObject();
        req.put("fileId", System.currentTimeMillis() + "-" + (int) (Math.random() * 100000));
        req.put("fileName", name);
        req.put("totalSize", "0");
        JSONArray body = new JSONArray();
        body.put(req);
        Http.Response resp = Http.send("POST", Http.CLOUD + "/acx/chatbot/file/upload/url",
                Http.baseHeaders(true), body.toString().getBytes("UTF-8"));
        JSONObject env = Http.envelope(resp);
        JSONArray data = J.ja(env, "data");
        if (data.length() == 0) {
            lastError = "申请上传地址失败：" + J.str(env, "msg", "空响应");
            return null;
        }
        JSONObject first = J.at(data, 0);
        String fileName = J.str(first, "fileName");
        String uploadUrl = J.str(first, "uploadUrl");
        if (fileName.length() == 0 || uploadUrl.length() == 0) {
            lastError = "申请上传地址失败：返回缺字段";
            return null;
        }
        return new String[]{fileName, uploadUrl};
    }

    /** PUT 到预签名地址：只带 OSS 需要的头，不能带平台鉴权头。 */
    private boolean put(String url, byte[] data, String mime) {
        HttpURLConnection c = null;
        try {
            c = (HttpURLConnection) new URL(url).openConnection();
            c.setRequestMethod("PUT");
            c.setDoOutput(true);
            c.setConnectTimeout(20000);
            c.setReadTimeout(120000);
            c.setFixedLengthStreamingMode(data.length);
            c.setRequestProperty("Content-Type", mime);
            c.setRequestProperty("x-amz-meta-total-size", "0");
            c.getOutputStream().write(data);
            c.getOutputStream().close();
            int code = c.getResponseCode();
            if (code != 200) {
                lastError = "OSS 上传返回 HTTP " + code;
                return false;
            }
            return true;
        } catch (Exception e) {
            lastError = "OSS 上传失败：" + (e.getMessage() == null ? e.toString() : e.getMessage());
            return false;
        } finally {
            if (c != null) {
                try {
                    c.disconnect();
                } catch (Exception ignored) {
                }
            }
        }
    }

    /** 读流（下载/读取结果文件用）。 */
    public static byte[] readAll(InputStream in) throws Exception {
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        byte[] buf = new byte[8192];
        int n;
        while ((n = in.read(buf)) > 0) {
            out.write(buf, 0, n);
        }
        return out.toByteArray();
    }
}
