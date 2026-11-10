package cn.scnet.agent.svc;

import android.content.Context;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.nio.charset.Charset;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.List;

import cn.scnet.agent.core.ChatText;

/**
 * 本地会话持久化（对齐 ArkTS 的 service/Sessions.ets）。
 *
 * 不用 SharedPreferences：字符串值有长度上限，聊天记录很容易超。
 * 落 `filesDir/sessions/`：
 *   index.json      → [{id,title,model,updatedAt,count}]
 *   <id>.json       → {id,title,model,createdAt,updatedAt,messages:[{role,content,via}]}
 *
 * 所有 IO 都吞异常：存储坏掉不能让人打不开 App。
 */
public class Sessions {

    public static class Message {
        public String role = "";
        public String content = "";
        /** 这条回答来自哪条通道（"智能体服务" / "SCNet Max"），用户消息为空 */
        public String via = "";

        public Message() {
        }

        public Message(String role, String content, String via) {
            this.role = role;
            this.content = content;
            this.via = via == null ? "" : via;
        }
    }

    public static class Meta {
        public String id = "";
        public String title = "";
        public String model = "";
        public long updatedAt;
        public int count;
    }

    public static class Data {
        public String id = "";
        public String title = "";
        public String model = "";
        public long createdAt;
        public long updatedAt;
        public List<Message> messages = new ArrayList<>();
    }

    private static final Charset UTF8 = Charset.forName("UTF-8");
    private static final Sessions INSTANCE = new Sessions();

    private File root;

    public static Sessions get() {
        return INSTANCE;
    }

    public void init(Context context) {
        root = new File(context.getFilesDir(), "sessions");
        if (!root.exists()) {
            //noinspection ResultOfMethodCallIgnored
            root.mkdirs();
        }
    }

    private File indexFile() {
        return new File(root, "index.json");
    }

    private File dataFile(String id) {
        return new File(root, id + ".json");
    }

    private String readText(File file) {
        if (file == null || !file.exists()) {
            return "";
        }
        try {
            FileInputStream in = new FileInputStream(file);
            byte[] buf = new byte[(int) file.length()];
            int off = 0;
            int n;
            while (off < buf.length && (n = in.read(buf, off, buf.length - off)) > 0) {
                off += n;
            }
            in.close();
            return new String(buf, 0, off, UTF8);
        } catch (Exception e) {
            return "";
        }
    }

    private void writeText(File file, String text) {
        if (file == null) {
            return;
        }
        FileOutputStream out = null;
        try {
            out = new FileOutputStream(file);
            out.write(text.getBytes(UTF8));
            out.flush();
            out.getFD().sync();
        } catch (Exception ignored) {
        } finally {
            if (out != null) {
                try {
                    out.close();
                } catch (Exception ignored) {
                }
            }
        }
    }

    /** 按 updatedAt 倒序。 */
    public List<Meta> list() {
        List<Meta> out = new ArrayList<>();
        String text = readText(indexFile());
        if (text.length() == 0) {
            return out;
        }
        try {
            JSONArray arr = new JSONArray(text);
            for (int i = 0; i < arr.length(); i++) {
                JSONObject row = arr.optJSONObject(i);
                if (row == null) {
                    continue;
                }
                Meta m = new Meta();
                m.id = row.optString("id");
                m.title = row.optString("title");
                m.model = row.optString("model");
                m.updatedAt = row.optLong("updatedAt");
                m.count = row.optInt("count");
                if (m.id.length() > 0) {
                    out.add(m);
                }
            }
            Collections.sort(out, new Comparator<Meta>() {
                @Override
                public int compare(Meta a, Meta b) {
                    return Long.compare(b.updatedAt, a.updatedAt);
                }
            });
        } catch (Exception ignored) {
        }
        return out;
    }

    public Data load(String id) {
        String text = readText(dataFile(id));
        if (text.length() == 0) {
            return null;
        }
        try {
            JSONObject row = new JSONObject(text);
            Data data = new Data();
            data.id = row.optString("id");
            data.title = row.optString("title");
            data.model = row.optString("model");
            data.createdAt = row.optLong("createdAt");
            data.updatedAt = row.optLong("updatedAt");
            JSONArray messages = row.optJSONArray("messages");
            if (messages != null) {
                for (int i = 0; i < messages.length(); i++) {
                    JSONObject m = messages.optJSONObject(i);
                    if (m == null) {
                        continue;
                    }
                    data.messages.add(new Message(m.optString("role"), m.optString("content"),
                            m.optString("via")));
                }
            }
            return data;
        } catch (Exception e) {
            return null;
        }
    }

    public void save(Data data) {
        long now = System.currentTimeMillis();
        try {
            JSONObject row = new JSONObject();
            row.put("id", data.id);
            row.put("title", data.title);
            row.put("model", data.model);
            row.put("createdAt", data.createdAt);
            row.put("updatedAt", now);
            JSONArray messages = new JSONArray();
            for (Message m : data.messages) {
                JSONObject o = new JSONObject();
                o.put("role", m.role);
                o.put("content", m.content);
                o.put("via", m.via);
                messages.put(o);
            }
            row.put("messages", messages);
            writeText(dataFile(data.id), row.toString());

            List<Meta> all = list();
            Meta meta = null;
            for (Meta m : all) {
                if (m.id.equals(data.id)) {
                    meta = m;
                    break;
                }
            }
            if (meta == null) {
                meta = new Meta();
                all.add(meta);
            }
            meta.id = data.id;
            meta.title = data.title;
            meta.model = data.model;
            meta.updatedAt = now;
            meta.count = data.messages.size();

            JSONArray index = new JSONArray();
            for (Meta m : all) {
                JSONObject o = new JSONObject();
                o.put("id", m.id);
                o.put("title", m.title);
                o.put("model", m.model);
                o.put("updatedAt", m.updatedAt);
                o.put("count", m.count);
                index.put(o);
            }
            writeText(indexFile(), index.toString());
        } catch (Exception ignored) {
        }
    }

    public boolean rename(String id, String title) {
        Data data = load(id);
        if (data == null) {
            return false;
        }
        data.title = title;
        save(data);
        return true;
    }

    public void remove(String id) {
        //noinspection ResultOfMethodCallIgnored
        dataFile(id).delete();
        List<Meta> rest = new ArrayList<>();
        for (Meta m : list()) {
            if (!m.id.equals(id)) {
                rest.add(m);
            }
        }
        JSONArray index = new JSONArray();
        for (Meta m : rest) {
            JSONObject o = new JSONObject();
            try {
                o.put("id", m.id);
                o.put("title", m.title);
                o.put("model", m.model);
                o.put("updatedAt", m.updatedAt);
                o.put("count", m.count);
            } catch (Exception ignored) {
            }
            index.put(o);
        }
        writeText(indexFile(), index.toString());
    }

    /** 首条用户消息 → 标题。 */
    public static String titleFrom(List<Message> messages) {
        List<String> roles = new ArrayList<>();
        List<String> contents = new ArrayList<>();
        for (Message m : messages) {
            roles.add(m.role);
            contents.add(m.content);
        }
        return ChatText.titleFrom(roles, contents);
    }

    public String newId() {
        return "s_" + System.currentTimeMillis() + "_" + (int) (Math.random() * 1000);
    }
}
