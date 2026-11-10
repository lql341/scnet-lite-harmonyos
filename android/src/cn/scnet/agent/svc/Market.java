package cn.scnet.agent.svc;

import org.json.JSONArray;
import org.json.JSONObject;

import java.util.ArrayList;
import java.util.List;

import cn.scnet.agent.core.Http;
import cn.scnet.agent.core.J;

/**
 * AIHub 社区市场：连接器 MCP / 技能 Skills（对齐 ArkTS 的 service/Market.ets）。
 *
 * 实测要点（别再试错）：
 * - `sort` 必须是对象（`{"browseCount":"desc"}`），传数组会 400；
 * - 字段名是驼峰：updateTime / browseCount / downloadCount；snake_case 静默返回 0 条；
 * - 不带 sort 直接 400「字段sort不能为空」。
 */
public class Market {

    public static final String SORT_HOT = "browseCount";
    public static final String SORT_NEW = "updateTime";
    public static final String SORT_DOWNLOAD = "downloadCount";

    public static class Item {
        public String recommend = "";
        public String id = "";
        public String name = "";
        public String desc = "";
        public String iconUrl = "";
        public String owner = "";
        public String author = "";
        public int browseCount;
        public int downloadCount;
        public String updateTime = "";
        public String category = "";
        public String detailUrl = "";
    }

    public static class Result {
        public int total;
        public int pages;
        public List<Item> items = new ArrayList<>();
    }

    private static final Market INSTANCE = new Market();

    public static Market get() {
        return INSTANCE;
    }

    public Result search(String kind, String keywords, int page, String sortField) {
        Result out = new Result();
        try {
            JSONObject sort = new JSONObject();
            sort.put(sortField, "desc");
            JSONObject query = new JSONObject();
            query.put("keyWords", keywords == null ? "" : keywords);
            query.put("pageSize", 64);
            query.put("pageNum", page);
            JSONObject body = new JSONObject();
            body.put("query", query);
            body.put("sort", sort);
            String path = "skills".equals(kind)
                    ? "/acx/search/dolphin/skills/full-text"
                    : "/acx/search/dolphin/mcp/full-text";
            JSONObject data = Http.postJson(path, body.toString());
            out.total = J.i(data, "total");
            out.pages = J.i(data, "pages");
            JSONArray records = J.ja(data, "records");
            for (int i = 0; i < records.length(); i++) {
                JSONObject row = J.at(records, i);
                String name = J.str(row, "nameCn");
                if (name.length() == 0) {
                    name = J.str(row, "name");
                }
                if (name.length() == 0) {
                    name = J.str(row, "nameEn");
                }
                if (name.length() == 0) {
                    continue;
                }
                Item item = new Item();
                item.recommend = J.str(row, "suggestType");
                item.id = J.str(row, "id");
                item.name = name;
                item.desc = J.str(row, "desc");
                if (item.desc.length() == 0) {
                    item.desc = J.str(row, "description");
                }
                item.iconUrl = J.str(row, "imageUrl");
                if (item.iconUrl.length() == 0) {
                    item.iconUrl = J.str(row, "avatarUrl");
                }
                item.owner = J.str(row, "createUser");
                item.author = J.str(row, "authenticatedName", item.owner);
                item.browseCount = J.i(row, "browseCount");
                item.downloadCount = J.i(row, "downloadCount");
                item.updateTime = J.str(row, "updateTime");
                JSONArray tags = J.ja(row, "tags");
                if (tags.length() > 0) {
                    item.category = J.str(J.at(tags, 0), "nameCn");
                }
                String slug = J.str(row, "nameEn", name);
                item.detailUrl = "https://www.scnet.cn/ui/aihub/"
                        + ("skills".equals(kind) ? "skills" : "mcp") + "/"
                        + Http.enc(item.owner) + "/" + Http.enc(slug)
                        + "?id=" + Http.enc(item.id);
                out.items.add(item);
            }
        } catch (Exception ignored) {
        }
        return out;
    }

    public Result connectors(String keywords, int page, String sortField) {
        return search("mcp", keywords, page, sortField);
    }

    public Result skills(String keywords, int page, String sortField) {
        return search("skills", keywords, page, sortField);
    }
}
