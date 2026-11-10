package cn.scnet.agent.svc;

import android.content.Context;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.InputStream;
import java.util.ArrayList;
import java.util.List;

import cn.scnet.agent.core.J;

/**
 * 领域智能体 / 场景模板（对齐 ArkTS 的 service/Scenarios.ets）。
 *
 * 目录来自桌面端的 home-scenarios，打包进 res/raw/scenarios.json，离线可用。
 * 每个场景带 prompt（预置指令），点一下就能发。
 */
public class Scenarios {

    public static class Item {
        public String id = "";
        public String title = "";
        public String summary = "";
        public String prompt = "";
        public String tier = "";
        public String skillName = "";
        public int inputCount;

        public String toPrompt() {
            return prompt.length() > 0 ? prompt : title;
        }
    }

    public static class Category {
        public String id = "";
        public String title = "";
        public String icon = "";
        public List<Item> items = new ArrayList<>();
    }

    private static final Scenarios INSTANCE = new Scenarios();

    private final List<Category> categories = new ArrayList<>();
    private boolean loaded;

    public static Scenarios get() {
        return INSTANCE;
    }

    public void load(Context context) {
        if (loaded) {
            return;
        }
        loaded = true;
        try {
            InputStream in = context.getResources().openRawResource(
                    context.getResources().getIdentifier("scenarios", "raw", context.getPackageName()));
            byte[] buf = Upload.readAll(in);
            in.close();
            JSONObject file = new JSONObject(new String(buf, "UTF-8"));
            JSONArray rows = J.ja(file, "categories");
            for (int i = 0; i < rows.length(); i++) {
                JSONObject row = J.at(rows, i);
                Category c = new Category();
                c.id = J.str(row, "id");
                c.title = J.str(row, "title");
                c.icon = J.str(row, "icon");
                JSONArray items = J.ja(row, "items");
                for (int k = 0; k < items.length(); k++) {
                    JSONObject o = J.at(items, k);
                    Item item = new Item();
                    item.id = J.str(o, "id");
                    item.title = J.str(o, "title");
                    item.summary = J.str(o, "summary");
                    item.prompt = J.str(o, "prompt");
                    item.tier = J.str(o, "tier");
                    item.skillName = J.str(o, "skillName");
                    item.inputCount = J.i(o, "inputCount");
                    if (item.title.length() > 0) {
                        c.items.add(item);
                    }
                }
                if (c.items.size() > 0) {
                    categories.add(c);
                }
            }
        } catch (Exception ignored) {
        }
    }

    public List<Category> list() {
        return categories;
    }

    /** 换一批：按 offset 轮转。 */
    public List<Item> rotate(String categoryId, int count, int offset) {
        List<Item> all = new ArrayList<>();
        for (Category c : categories) {
            if (c.id.equals(categoryId)) {
                all = c.items;
                break;
            }
        }
        List<Item> out = new ArrayList<>();
        if (all.isEmpty()) {
            return out;
        }
        for (int i = 0; i < count && i < all.size(); i++) {
            out.add(all.get((offset + i) % all.size()));
        }
        return out;
    }
}
