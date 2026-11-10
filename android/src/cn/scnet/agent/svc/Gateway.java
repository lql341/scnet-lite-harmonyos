package cn.scnet.agent.svc;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.util.List;

import cn.scnet.agent.core.ChatText;
import cn.scnet.agent.core.J;
import cn.scnet.agent.core.Sse;
import cn.scnet.agent.core.Task;

/**
 * 网关 LLM 通道（OpenAI 兼容 SSE，对齐 ArkTS 的 service/Gateway.ets）。
 *
 * 两个必须保留的细节：
 * - 网关的 402/401 错误体是**单行 JSON 且没有换行** → 流结束要 flush 残留再解析；
 * - 只有 SCNet-Max 免费，其余模型余额为 0 时一律 402。
 */
public class Gateway {

    /** 流式回调（都在主线程）。 */
    public static abstract class Handlers {
        public void onDelta(String content, String reasoning) {
        }

        public void onProgress(String text) {
        }

        public void onTitle(String title) {
        }

        public abstract void onDone();

        public abstract void onError(String message);
    }

    private volatile HttpURLConnection conn = null;
    private volatile boolean cancelled = false;

    public void cancel() {
        cancelled = true;
        HttpURLConnection current = conn;
        conn = null;
        if (current != null) {
            try {
                current.disconnect();
            } catch (Exception ignored) {
            }
        }
    }

    public boolean hasContent() {
        return false;
    }

    /** 把网关错误翻译成人话。 */
    public static String describeError(String raw) {
        String code = "";
        String message = "";
        String type = "";
        try {
            JSONObject body = new JSONObject(raw);
            JSONObject err = J.jo(body, "error");
            if (err.length() > 0) {
                message = J.str(err, "message");
                code = J.str(err, "code");
                type = J.str(err, "type");
            } else {
                message = J.str(body, "message");
                code = J.str(body, "code");
            }
        } catch (Exception e) {
            message = raw == null ? "" : raw;
        }
        if ("402".equals(code) || message.contains("Insufficient Balance")) {
            return "该模型需要余额（402 Insufficient Balance）。改用 SCNet-Max 可免费使用，或到控制台充值";
        }
        if ("401".equals(code) || message.contains("Authentication")
                || message.contains("token_not_found")) {
            return "网关 key 无效 (401)：请重新登录以重新获取 key";
        }
        if (message.length() > 0) {
            return "网关报错 (" + (code.length() > 0 ? code : type) + ")：" + message;
        }
        return "网关报错：" + (raw == null ? "未知" : raw);
    }

    public void stream(final String baseUrl, final String apiKey, final String model,
                       final List<ChatText.Turn> messages, final Handlers handlers) {
        cancel();
        cancelled = false;
        Task.bg(new Runnable() {
            @Override
            public void run() {
                doStream(baseUrl, apiKey, model, messages, handlers);
            }
        });
    }

    private void doStream(String baseUrl, String apiKey, String model,
                          List<ChatText.Turn> messages, final Handlers handlers) {
        final boolean[] finished = {false};
        final String[] serverError = {""};
        final boolean[] gotDelta = {false};

        Sse sse = new Sse();
        HttpURLConnection c = null;
        try {
            JSONObject payload = new JSONObject();
            payload.put("model", model);
            payload.put("stream", true);
            JSONArray arr = new JSONArray();
            for (ChatText.Turn turn : messages) {
                JSONObject m = new JSONObject();
                m.put("role", turn.role);
                m.put("content", turn.content);
                arr.put(m);
            }
            payload.put("messages", arr);

            String url = J.trimSlash(baseUrl.length() > 0 ? baseUrl
                    : "https://api.scnet.cn/api/llm/v1") + "/chat/completions";
            c = (HttpURLConnection) new URL(url).openConnection();
            conn = c;
            c.setRequestMethod("POST");
            c.setConnectTimeout(20000);
            c.setReadTimeout(300000);
            c.setDoOutput(true);
            c.setRequestProperty("Content-Type", "application/json");
            c.setRequestProperty("Accept", "text/event-stream");
            c.setRequestProperty("Authorization", "Bearer " + apiKey);
            byte[] body = payload.toString().getBytes("UTF-8");
            c.getOutputStream().write(body);
            c.getOutputStream().close();

            int status = c.getResponseCode();
            InputStream in = status >= 400 ? c.getErrorStream() : c.getInputStream();
            if (in == null) {
                finish(handlers, finished, "网关无响应 (HTTP " + status + ")");
                return;
            }
            byte[] buf = new byte[8192];
            int n;
            while (!cancelled && (n = in.read(buf)) > 0) {
                for (String line : sse.pushBytes(buf, n)) {
                    handleLine(line, handlers, finished, serverError, gotDelta);
                }
            }
            in.close();
            // 残留：单行 JSON 错误体没有换行，只会在缓冲区里
            for (String line : sse.flush()) {
                handleLine(line, handlers, finished, serverError, gotDelta);
            }
            if (cancelled) {
                finish(handlers, finished, null);
                return;
            }
            if (serverError[0].length() > 0) {
                finish(handlers, finished, serverError[0]);
                return;
            }
            if (!gotDelta[0]) {
                finish(handlers, finished, "网关没有返回内容，也没给错误体：换个模型或检查 Base URL");
                return;
            }
            finish(handlers, finished, null);
        } catch (Exception e) {
            if (!cancelled) {
                finish(handlers, finished, "请求失败：" + (e.getMessage() == null ? e.toString() : e.getMessage()));
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

    private void handleLine(String rawLine, final Handlers handlers, final boolean[] finished,
                            final String[] serverError, final boolean[] gotDelta) {
        String line = rawLine == null ? "" : rawLine.trim();
        if (line.length() == 0) {
            return;
        }
        if (!line.startsWith("data:")) {
            if (line.startsWith("{") && line.contains("\"error\"")) {
                serverError[0] = describeError(line);
            }
            return;
        }
        String payload = line.substring(5).trim();
        if ("[DONE]".equals(payload)) {
            finish(handlers, finished, null);
            return;
        }
        try {
            JSONObject chunk = new JSONObject(payload);
            JSONArray choices = J.ja(chunk, "choices");
            if (choices.length() == 0) {
                return;
            }
            JSONObject delta = J.jo(J.at(choices, 0), "delta");
            final String content = J.str(delta, "content");
            final String reasoning = J.str(delta, "reasoning_content");
            if (content.length() > 0 || reasoning.length() > 0) {
                gotDelta[0] = true;
                Task.onMain(new Runnable() {
                    @Override
                    public void run() {
                        handlers.onDelta(content, reasoning);
                    }
                });
            }
        } catch (Exception ignored) {
            // 不完整的分片，跳过
        }
    }

    private void finish(final Handlers handlers, final boolean[] finished, final String error) {
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
