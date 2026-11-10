package cn.scnet.agent.svc;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.ByteArrayOutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.util.ArrayList;
import java.util.List;

import cn.scnet.agent.core.Http;
import cn.scnet.agent.core.J;

/**
 * OCR + 文档解析 / 格式转换（对齐 ArkTS 的 service/Ocr.ets + DocAi.ets）。
 *
 * 踩坑（照抄别改）：
 * - OCR 的 `ocrType` 必须是**表单字段**且是**大写枚举**（general 会报 not support）；
 * - 文档解析是 `ocr_type=DOC_PARING`（平台少一个 S，别"修正"）；
 * - 都是 multipart，走 api.scnet.cn/api/llm/v1，Bearer 用网关 key。
 */
public class Ocr {

    public static class Type {
        public final String code;
        public final String label;

        Type(String code, String label) {
            this.code = code;
            this.label = label;
        }
    }

    /** 平台支持的 12 种识别类型（实测全部可用）。 */
    public static final Type[] TYPES = {
            new Type("GENERAL", "通用识别"),
            new Type("PRINTED_TEXT", "印刷文字"),
            new Type("HANDWRITING", "手写体"),
            new Type("ID_CARD", "身份证"),
            new Type("BANK_CARD", "银行卡"),
            new Type("DRIVER_LICENSE", "驾驶证"),
            new Type("VEHICLE_LICENSE", "行驶证"),
            new Type("VEHICLE_VIN", "车架号"),
            new Type("BUSINESS_LICENSE", "营业执照"),
            new Type("INVOICE", "发票"),
            new Type("TAXI_RECEIPT", "出租车票"),
            new Type("SOCIAL_SECURITY", "社保卡")
    };

    public static class Result {
        public List<String> lines = new ArrayList<>();
        public String traceId = "";
        public String raw = "";
    }

    public static class Task {
        public String taskId = "";
        public String status = "";
        public List<String> results = new ArrayList<>();
        public String error = "";
        public String submitTime = "";
        public String endTime = "";
    }

    public static final String DOC_PARSE = "DOC_PARING";
    public static final String PDF_TO_WORD = "PDF_TO_WORD";
    public static final String WORD_TO_PDF = "WORD_TO_PDF";
    public static final String PDF_TO_EXCEL = "PDF_TO_EXCEL";
    public static final String PDF_TO_PPT = "PDF_TO_PPT";

    private static final String BASE = "https://api.scnet.cn/api/llm/v1";
    private static final Ocr INSTANCE = new Ocr();

    public static Ocr get() {
        return INSTANCE;
    }

    /** multipart 单文件 + 一个文本字段。 */
    private static byte[] multipart(String boundary, String fileName, String mime, byte[] bytes,
                                    String fieldName, String fieldValue) {
        try {
            ByteArrayOutputStream out = new ByteArrayOutputStream();
            String head = "--" + boundary + "\r\n"
                    + "Content-Disposition: form-data; name=\"" + fieldName + "\"\r\n\r\n"
                    + fieldValue + "\r\n"
                    + "--" + boundary + "\r\n"
                    + "Content-Disposition: form-data; name=\"file\"; filename=\"" + fileName + "\"\r\n"
                    + "Content-Type: " + mime + "\r\n\r\n";
            out.write(head.getBytes("UTF-8"));
            out.write(bytes);
            out.write(("\r\n--" + boundary + "--\r\n").getBytes("UTF-8"));
            return out.toByteArray();
        } catch (Exception e) {
            return new byte[0];
        }
    }

    private static Http.Response postMultipart(String path, String apiKey, byte[] body,
                                               String boundary) throws Exception {
        HttpURLConnection c = null;
        try {
            c = (HttpURLConnection) new URL(BASE + path).openConnection();
            c.setRequestMethod("POST");
            c.setConnectTimeout(20000);
            c.setReadTimeout(120000);
            c.setDoOutput(true);
            c.setFixedLengthStreamingMode(body.length);
            c.setRequestProperty("Authorization", "Bearer " + apiKey);
            c.setRequestProperty("Accept", "application/json");
            c.setRequestProperty("Content-Type", "multipart/form-data; boundary=" + boundary);
            c.getOutputStream().write(body);
            c.getOutputStream().close();
            Http.Response resp = new Http.Response();
            resp.status = c.getResponseCode();
            java.io.InputStream in = resp.status >= 400 ? c.getErrorStream() : c.getInputStream();
            resp.body = in == null ? "" : Http.readAll(in);
            return resp;
        } finally {
            if (c != null) {
                c.disconnect();
            }
        }
    }

    /** 识别。调用方在后台线程。 */
    public Result recognize(String apiKey, byte[] bytes, String fileName, String mime, String ocrType)
            throws Exception {
        String boundary = "----scnet" + System.currentTimeMillis();
        byte[] body = multipart(boundary, fileName, mime, bytes, "ocrType", ocrType);
        Http.Response resp = postMultipart("/ocr/recognize", apiKey, body, boundary);
        JSONObject env = J.obj(resp.body);
        String code = J.str(env, "code");
        if (code.length() > 0 && !"0".equals(code)) {
            throw new Exception(J.str(env, "msg", "识别失败 (HTTP " + resp.status + ")"));
        }
        Result out = new Result();
        out.raw = resp.body == null ? "" : resp.body;
        JSONArray rows = J.ja(env, "data");
        for (int i = 0; i < rows.length(); i++) {
            JSONObject row = J.at(rows, i);
            if (out.traceId.length() == 0) {
                out.traceId = J.str(row, "traceId");
            }
            JSONArray results = J.ja(row, "result");
            for (int k = 0; k < results.length(); k++) {
                collect(J.jo(J.at(results, k), "elements"), out.lines);
            }
        }
        return out;
    }

    /** elements 是嵌套结构，递归抓所有 text。 */
    private void collect(JSONObject node, List<String> out) {
        java.util.Iterator<String> keys = node.keys();
        while (keys.hasNext()) {
            String key = keys.next();
            Object value = node.opt(key);
            if ("text".equals(key) && value instanceof String) {
                String text = ((String) value).trim();
                if (text.length() > 0) {
                    out.add(text);
                }
                continue;
            }
            if (value instanceof JSONArray) {
                JSONArray arr = (JSONArray) value;
                for (int i = 0; i < arr.length(); i++) {
                    Object item = arr.opt(i);
                    if (item instanceof JSONObject) {
                        collect((JSONObject) item, out);
                    }
                }
            } else if (value instanceof JSONObject) {
                collect((JSONObject) value, out);
            }
        }
    }

    /** 提交文档解析任务。 */
    public Task submitParse(String apiKey, byte[] bytes, String fileName, String mime) throws Exception {
        String boundary = "----scnet" + System.currentTimeMillis();
        byte[] body = multipart(boundary, fileName, mime, bytes, "ocr_type", DOC_PARSE);
        return pickTask(postMultipart("/ocrdoc/submit", apiKey, body, boundary));
    }

    /** 提交格式转换任务。 */
    public Task submitConvert(String apiKey, byte[] bytes, String fileName, String mime, String target)
            throws Exception {
        String boundary = "----scnet" + System.currentTimeMillis();
        byte[] body = multipart(boundary, fileName, mime, bytes, "ocr_type", target);
        return pickTask(postMultipart("/doc/convert/task", apiKey, body, boundary));
    }

    private Task pickTask(Http.Response resp) throws Exception {
        JSONObject env = J.obj(resp.body);
        String code = J.str(env, "code");
        if (code.length() > 0 && !"0".equals(code)) {
            throw new Exception(J.str(env, "msg", "提交失败"));
        }
        JSONObject out = J.jo(J.jo(env, "data"), "output");
        String taskId = J.str(out, "task_id");
        if (taskId.length() == 0) {
            throw new Exception("提交后没有返回任务号");
        }
        return readTask(out, taskId);
    }

    /** 查询任务状态 / 结果。 */
    public Task query(String apiKey, String taskId) throws Exception {
        HttpURLConnection c = null;
        try {
            c = (HttpURLConnection) new URL(BASE + "/ocrdoc/result").openConnection();
            c.setRequestMethod("POST");
            c.setConnectTimeout(15000);
            c.setReadTimeout(30000);
            c.setDoOutput(true);
            c.setRequestProperty("Authorization", "Bearer " + apiKey);
            c.setRequestProperty("Content-Type", "application/json");
            c.setRequestProperty("Accept", "application/json");
            byte[] body = ("{\"task_ids\":[\"" + taskId + "\"]}").getBytes("UTF-8");
            c.getOutputStream().write(body);
            c.getOutputStream().close();
            int status = c.getResponseCode();
            java.io.InputStream in = status >= 400 ? c.getErrorStream() : c.getInputStream();
            JSONObject env = J.obj(in == null ? "" : Http.readAll(in));
            String code = J.str(env, "code");
            if (code.length() > 0 && !"0".equals(code)) {
                throw new Exception(J.str(env, "msg", "查询失败"));
            }
            JSONArray rows = J.ja(env, "data");
            if (rows.length() == 0) {
                throw new Exception("查询结果为空");
            }
            return readTask(J.jo(J.at(rows, 0), "output"), taskId);
        } finally {
            if (c != null) {
                c.disconnect();
            }
        }
    }

    private Task readTask(JSONObject out, String fallbackId) {
        Task task = new Task();
        task.taskId = J.str(out, "task_id", fallbackId);
        task.status = J.str(out, "task_status");
        task.error = J.str(out, "error_message");
        task.submitTime = J.str(out, "submit_time");
        task.endTime = J.str(out, "end_time");
        JSONArray results = J.ja(out, "results");
        for (int i = 0; i < results.length(); i++) {
            String url = J.safe(results.optString(i));
            if (url.length() > 0) {
                task.results.add(url);
            }
        }
        return task;
    }

    /** 拉结果文件（解析结果是 json，转换结果是产物）。 */
    public String fetchResult(String url) {
        HttpURLConnection c = null;
        try {
            c = (HttpURLConnection) new URL(url).openConnection();
            c.setRequestMethod("GET");
            c.setConnectTimeout(15000);
            c.setReadTimeout(60000);
            int status = c.getResponseCode();
            if (status >= 400) {
                return "";
            }
            return Http.readAll(c.getInputStream());
        } catch (Exception e) {
            return "";
        } finally {
            if (c != null) {
                c.disconnect();
            }
        }
    }

    /** 宽容遍历结果 json，抓所有 text/content/html/markdown 字段。 */
    public String extractText(String json) {
        Object parsed;
        try {
            parsed = json.trim().startsWith("[") ? new JSONArray(json) : new JSONObject(json);
        } catch (Exception e) {
            return json;
        }
        List<String> parts = new ArrayList<>();
        walk(parsed, parts);
        StringBuilder sb = new StringBuilder();
        for (String p : parts) {
            if (sb.length() > 0) {
                sb.append('\n');
            }
            sb.append(p);
        }
        return sb.toString();
    }

    private void walk(Object node, List<String> parts) {
        if (node == null) {
            return;
        }
        if (node instanceof JSONArray) {
            JSONArray arr = (JSONArray) node;
            for (int i = 0; i < arr.length(); i++) {
                walk(arr.opt(i), parts);
            }
            return;
        }
        if (!(node instanceof JSONObject)) {
            return;
        }
        JSONObject obj = (JSONObject) node;
        java.util.Iterator<String> keys = obj.keys();
        while (keys.hasNext()) {
            String key = keys.next();
            Object value = obj.opt(key);
            if (("text".equals(key) || "content".equals(key) || "html".equals(key)
                    || "markdown".equals(key)) && value instanceof String) {
                String text = ((String) value).trim();
                if (text.length() > 0) {
                    parts.add(text);
                }
            } else if (value instanceof JSONObject || value instanceof JSONArray) {
                walk(value, parts);
            }
        }
    }
}
