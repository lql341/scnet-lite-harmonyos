package cn.scnet.agent.svc;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.util.List;

import cn.scnet.agent.core.Http;
import cn.scnet.agent.core.J;
import cn.scnet.agent.core.Sse;
import cn.scnet.agent.core.Task;

/**
 * 平台智能体通道 v2（对齐 ArkTS 的 service/AgentChat.ets）。
 *
 * 帧按 `type` 分派，只有 `text-delta` 的 `delta` 是正文；
 * `tool-input-delta` 走 `inputTextDelta`（工具入参分片，当正文渲染会把 JSON 吐进气泡）。
 * 没有 `data: [done]` 哨兵，`finish` 帧或连接关闭即结束。
 */
public class AgentChat {

    private static String base() {
        return Http.base();
    }
    private static final String STREAM_PATH = "/acx/chatbot/v2/agent/stream";
    private static final String STOP_PATH = "/acx/chatbot/v2/agent/stop";

    /** 当前会话 id（首帧带回；新对话要清空）。 */
    public String conversationId = "";
    public String lastTitle = "";

    private volatile HttpURLConnection conn = null;
    private volatile boolean cancelled = false;

    public void cancel() {
        cancelled = true;
        HttpURLConnection c = conn;
        conn = null;
        if (c != null) {
            try {
                c.disconnect();
            } catch (Exception ignored) {
            }
        }
    }

    /** 停服务端任务：只断开本地连接不会让服务端停（会继续烧算力）。 */
    public void stop(final int modelId) {
        final String conversation = conversationId;
        if (conversation.length() == 0) {
            return;
        }
        Task.bg(new Runnable() {
            @Override
            public void run() {
                try {
                    JSONObject body = new JSONObject();
                    body.put("conversationId", conversation);
                    body.put("modelId", modelId);
                    java.util.Map<String, String> head = agentHeaders();
                    head.put("Content-Type", "application/json");
                    Http.send("POST", base() + STOP_PATH, head, body.toString().getBytes("UTF-8"));
                } catch (Exception ignored) {
                }
            }
        });
    }

    private java.util.Map<String, String> agentHeaders() {
        java.util.Map<String, String> head = new java.util.LinkedHashMap<>();
        head.put("Accept", "text/event-stream");
        head.put("source", Http.source);
        head.put("version", Http.version);
        if (Http.token.length() > 0) {
            head.put("Token", Http.token);
        }
        if (Http.cookie.length() > 0) {
            head.put("Cookie", Http.cookie);
        }
        return head;
    }

    public void stream(final int modelId, final String text, final List<Upload.UploadedFile> files,
                       final Gateway.Handlers handlers) {
        cancel();
        cancelled = false;
        if (Http.token.length() == 0) {
            handlers.onError("未登录，无法使用智能体服务");
            return;
        }
        Task.bg(new Runnable() {
            @Override
            public void run() {
                doStream(modelId, text, files, handlers);
            }
        });
    }

    private void doStream(int modelId, String text, List<Upload.UploadedFile> files,
                          final Gateway.Handlers handlers) {
        final boolean[] finished = {false};
        final boolean[] gotText = {false};
        Sse sse = new Sse();
        HttpURLConnection c = null;
        try {
            JSONObject body = new JSONObject();
            body.put("modelId", modelId);
            body.put("origin", "user");
            JSONArray inputs = new JSONArray();
            JSONObject textInput = new JSONObject();
            textInput.put("type", "text");
            textInput.put("text", text);
            inputs.put(textInput);
            if (files != null) {
                for (Upload.UploadedFile f : files) {
                    JSONObject resource = new JSONObject();
                    resource.put("name", f.name);
                    resource.put("mimeType", f.mimeType);
                    resource.put("size", f.sizeKb);
                    JSONObject input = new JSONObject();
                    input.put("type", f.mimeType.startsWith("image/") ? "image" : "file");
                    input.put("resource", resource);
                    inputs.put(input);
                }
            }
            body.put("inputs", inputs);
            if (conversationId.length() > 0) {
                body.put("conversationId", conversationId);
            }

            c = (HttpURLConnection) new URL(base() + STREAM_PATH).openConnection();
            conn = c;
            c.setRequestMethod("POST");
            c.setConnectTimeout(20000);
            c.setReadTimeout(300000);
            c.setDoOutput(true);
            java.util.Map<String, String> head = agentHeaders();
            for (java.util.Map.Entry<String, String> e : head.entrySet()) {
                c.setRequestProperty(e.getKey(), e.getValue());
            }
            c.setRequestProperty("Content-Type", "application/json");
            c.setRequestProperty("Accept", "text/event-stream");
            c.getOutputStream().write(body.toString().getBytes("UTF-8"));
            c.getOutputStream().close();

            int status = c.getResponseCode();
            InputStream in = status >= 400 ? c.getErrorStream() : c.getInputStream();
            if (in == null) {
                finish(handlers, finished, "智能体无响应 (HTTP " + status + ")");
                return;
            }
            byte[] buf = new byte[8192];
            int n;
            while (!cancelled && (n = in.read(buf)) > 0) {
                for (String line : sse.pushBytes(buf, n)) {
                    handleLine(line, handlers, finished, gotText);
                }
            }
            in.close();
            for (String line : sse.flush()) {
                handleLine(line, handlers, finished, gotText);
            }
            if (cancelled) {
                finish(handlers, finished, null);
                return;
            }
            if (!gotText[0]) {
                finish(handlers, finished, conversationId.length() > 0
                        ? "智能体没有返回内容，请重试" : "智能体没有响应，请稍后重试");
                return;
            }
            finish(handlers, finished, null);
        } catch (Exception e) {
            if (!cancelled) {
                finish(handlers, finished, "智能体请求失败："
                        + (e.getMessage() == null ? e.toString() : e.getMessage()));
            } else {
                finish(handlers, finished, null);
            }
        } finally {
            if (c != null) {
                try {
                    c.disconnect();
                } catch (Exception ignored) {
                }
            }
            conn = null;
        }
    }

    /** 由 UI 层注入的 Context，用于把原始帧落盘（可空）。 */
    public android.content.Context ctx;

    private void handleLine(String raw, final Gateway.Handlers handlers, final boolean[] finished,
                            final boolean[] gotText) {
        String line = raw == null ? "" : raw.trim();
        if (line.length() == 0 || !line.startsWith("data:")) {
            return;
        }
        String payload = line.substring(5).trim();
        if ("[done]".equalsIgnoreCase(payload)) {
            finish(handlers, finished, null);
            return;
        }
        JSONObject frame;
        try {
            frame = new JSONObject(payload);
        } catch (Exception e) {
            return;
        }
        String type = J.str(frame, "type");
        String conversation = J.str(frame, "conversationId");
        if (conversation.length() > 0) {
            conversationId = conversation;
        }
        if ("error".equals(type)) {
            finish(handlers, finished, J.str(frame, "errorText", "智能体返回错误"));
            return;
        }
        if ("finish".equals(type)) {
            finish(handlers, finished, null);
            return;
        }
        if ("title_gen".equals(type)) {
            final String title = J.str(frame, "title");
            if (title.length() > 0) {
                lastTitle = title;
                Task.onMain(new Runnable() {
                    @Override
                    public void run() {
                        handlers.onTitle(title);
                    }
                });
            }
            return;
        }
        if ("tool-exec-progress".equals(type) || "todolist".equals(type)) {
            final String progress = J.str(frame, "progressText");
            if (progress.length() > 0) {
                Task.onMain(new Runnable() {
                    @Override
                    public void run() {
                        handlers.onProgress(progress);
                        handlers.onTool("progress", J.str(frame, "toolName"), progress);
                    }
                });
            }
            if ("todolist".equals(type)) {
                android.util.Log.d("SCNetDbg", "todolist frame: " + payload);
            }
            return;
        }
        if (ctx != null) {
            cn.scnet.agent.core.StreamLog.event(ctx, "frame " + type + " "
                    + (payload.length() > 200 ? payload.substring(0, 200) : payload));
        }
        if (type.startsWith("tool")) {
            final String toolName = J.str(frame, "toolName");
            final String detail = J.str(frame, "errorText", J.str(frame, "progressText",
                    J.str(frame, "inputTextDelta", "")));
            android.util.Log.i("SCNetDbg", "tool frame " + type + " name=" + toolName
                    + " detail=" + (detail.length() > 80 ? detail.substring(0, 80) : detail));
            Task.onMain(new Runnable() {
                @Override
                public void run() {
                    handlers.onTool(type, toolName, detail);
                }
            });
            return;
        }
        if (!"text-delta".equals(type)) {
            // 资源卡片（图片/文件）：宽容地从帧里找 url/name/mime
            if (type.contains("resource") || type.contains("card") || type.contains("image")
                    || type.contains("file")) {
                final String[] hit = findResource(frame);
                if (hit != null) {
                    Task.onMain(new Runnable() {
                        @Override
                        public void run() {
                            handlers.onResource(hit[0], hit[1], hit[2]);
                        }
                    });
                }
            }
            return;
        }
        final String delta = J.str(frame, "delta");
        if (delta.length() > 0) {
            gotText[0] = true;
            Task.onMain(new Runnable() {
                @Override
                public void run() {
                    handlers.onDelta(delta, "");
                }
            });
        }
    }

    /** 在任意嵌套 JSON 里找第一个像图片/文件资源的 (name, url, mime)。 */
    private static String[] findResource(org.json.JSONObject frame) {
        final String[] found = new String[1];
        walk(frame, found, 0);
        if (found[0] == null) {
            return null;
        }
        return found[0].split("\u0001", -1);
    }

    private static void walk(Object node, String[] found, int depth) {
        if (found[0] != null || node == null || depth > 6) {
            return;
        }
        if (node instanceof org.json.JSONArray) {
            org.json.JSONArray arr = (org.json.JSONArray) node;
            for (int i = 0; i < arr.length(); i++) {
                walk(arr.opt(i), found, depth + 1);
            }
            return;
        }
        if (!(node instanceof org.json.JSONObject)) {
            return;
        }
        org.json.JSONObject obj = (org.json.JSONObject) node;
        String url = "";
        String name = "";
        String mime = "";
        java.util.Iterator<String> keys = obj.keys();
        while (keys.hasNext()) {
            String key = keys.next();
            Object value = obj.opt(key);
            if (!(value instanceof String)) {
                continue;
            }
            String text = (String) value;
            String lower = key.toLowerCase();
            if (url.length() == 0 && (lower.contains("url") || lower.equals("src")
                    || lower.equals("path") || lower.equals("href"))
                    && (text.startsWith("http") || text.startsWith("/")
                    || text.startsWith("data:"))) {
                url = text;
            } else if (name.length() == 0 && (lower.contains("name") || lower.contains("title"))
                    && text.length() > 0 && !text.contains("/")) {
                name = text;
            } else if (mime.length() == 0 && lower.contains("mime") && text.length() > 0) {
                mime = text;
            }
        }
        if (url.length() > 0 && (mime.startsWith("image/") || looksLikeImage(url))) {
            found[0] = name + "\u0001" + url + "\u0001" + (mime.length() > 0 ? mime
                    : cn.scnet.agent.ui.ImageLoader.normalize(url).contains(".")
                    ? "image/*" : "");
            return;
        }
        keys = obj.keys();
        while (keys.hasNext()) {
            Object value = obj.opt(keys.next());
            if (value instanceof org.json.JSONObject || value instanceof org.json.JSONArray) {
                walk(value, found, depth + 1);
            }
        }
    }

    private static boolean looksLikeImage(String url) {
        String lower = url.toLowerCase();
        int q = lower.indexOf('?');
        if (q > 0) {
            lower = lower.substring(0, q);
        }
        return lower.endsWith(".png") || lower.endsWith(".jpg") || lower.endsWith(".jpeg")
                || lower.endsWith(".gif") || lower.endsWith(".webp") || lower.endsWith(".svg")
                || lower.contains("/image") || lower.contains("image/");
    }

    private void finish(final Gateway.Handlers handlers, final boolean[] finished, final String error) {
        synchronized (finished) {
            if (finished[0]) {
                return;
            }
            finished[0] = true;
        }
        Task.onMain(new Runnable() {
            @Override
            public void run() {
                if (error != null && error.length() > 0) {
                    handlers.onError(error);
                } else {
                    handlers.onDone();
                }
            }
        });
    }
}
