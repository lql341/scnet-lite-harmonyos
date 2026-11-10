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

    private static final String BASE = Http.CLOUD;
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
                    Http.send("POST", BASE + STOP_PATH, head, body.toString().getBytes("UTF-8"));
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

            c = (HttpURLConnection) new URL(BASE + STREAM_PATH).openConnection();
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
                    }
                });
            }
            return;
        }
        if (!"text-delta".equals(type)) {
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
