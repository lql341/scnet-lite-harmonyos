package cn.scnet.agent.svc;

import org.json.JSONArray;
import org.json.JSONObject;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import cn.scnet.agent.core.Http;
import cn.scnet.agent.core.J;

/**
 * 首页场景分类（对齐 ArkTS 的 service/Scenes.ets，算法与桌面端一致）：
 * config.list 的 `vibeCodingScenes` × router 的 `question[]`（enable=true、route 空或 aiAssistant），
 * 再按标签映射成「材料科学 / 生物信息 / 工业仿真 / 办公创作 / 平台助手」，
 * 最后用关键词从推荐问题里拆出「文献阅读 / 学术写作」两个静态 tab。
 */
public class Scenes {

    public static class Tab {
        public String id = "";
        public String title = "";
        public List<String> questions = new ArrayList<>();
    }

    public static class Ad {
        public String logo = "";
        public String name = "";
        public String url = "";
    }

    public static class Board {
        public List<Ad> ads = new ArrayList<>();
        public List<Tab> tabs = new ArrayList<>();
        public Map<String, List<String>> byService = new HashMap<>();
    }

    private static final Scenes INSTANCE = new Scenes();

    private Board board = new Board();

    public static Scenes get() {
        return INSTANCE;
    }

    public Board current() {
        return board;
    }

    public Board load() {
        Board out = new Board();
        try {
            JSONObject config = Http.get("/acx/chatbot/config/list");
            JSONArray recommend = Http.getArray("/acx/chatbot/recommend/list?enable=true&position=all");

            JSONArray rawAds = J.ja(config, "recommendAD");
            for (int i = 0; i < rawAds.length(); i++) {
                JSONObject row = J.at(rawAds, i);
                Ad ad = new Ad();
                ad.logo = J.str(row, "logo");
                ad.name = J.str(row, "name");
                ad.url = J.str(row, "url");
                if (ad.name.length() > 0 && ad.url.length() > 0) {
                    out.ads.add(ad);
                }
            }

            List<String[]> scenes = new ArrayList<>();
            JSONArray rawScenes = J.ja(config, "vibeCodingScenes");
            for (int i = 0; i < rawScenes.length(); i++) {
                JSONObject row = J.at(rawScenes, i);
                String value = J.str(row, "value");
                String label = J.str(row, "label");
                if (value.length() > 0 && label.length() > 0 && !"featured".equals(value)) {
                    scenes.add(new String[]{value, label});
                }
            }

            JSONArray routerQuestions = new JSONArray();
            for (int i = 0; i < recommend.length(); i++) {
                JSONObject row = J.at(recommend, i);
                String identify = J.str(row, "identify");
                JSONArray questions = J.ja(row, "question");
                List<String> names = new ArrayList<>();
                for (int k = 0; k < questions.length(); k++) {
                    JSONObject q = J.at(questions, k);
                    String name = J.safe(J.str(q, "name"));
                    if (J.b(q, "enable") && name.length() > 0) {
                        names.add(name);
                    }
                }
                if (identify.length() > 0 && !names.isEmpty()) {
                    out.byService.put(identify, names);
                }
                if ("aiagent-router".equals(identify)) {
                    routerQuestions = questions;
                }
            }

            // router 问题过滤
            List<JSONObject> usable = new ArrayList<>();
            for (int i = 0; i < routerQuestions.length(); i++) {
                JSONObject q = J.at(routerQuestions, i);
                String route = J.str(q, "route");
                String name = J.safe(J.str(q, "name"));
                if (J.b(q, "enable") && (route.length() == 0 || "aiAssistant".equals(route))
                        && name.length() > 0) {
                    usable.add(q);
                }
            }

            List<String> featured = new ArrayList<>();
            for (JSONObject q : usable) {
                featured.add(J.str(q, "name"));
            }
            if (!featured.isEmpty()) {
                Tab tab = new Tab();
                tab.id = "featured";
                tab.title = "推荐";
                tab.questions = featured;
                out.tabs.add(tab);
            }

            for (String[] scene : scenes) {
                List<String> picked = new ArrayList<>();
                for (JSONObject q : usable) {
                    String qScene = J.str(q, "scene");
                    if (qScene.length() == 0 || qScene.equals(scene[0])) {
                        picked.add(J.str(q, "name"));
                    }
                }
                if (!picked.isEmpty()) {
                    Tab tab = new Tab();
                    tab.id = scene[0];
                    tab.title = scene[1];
                    tab.questions = picked;
                    out.tabs.add(tab);
                }
            }

            Map<String, String> labels = new HashMap<>();
            labels.put("industry", "材料科学");
            labels.put("bioinformatics", "生物信息");
            labels.put("simulation", "工业仿真");
            labels.put("office", "办公创作");
            labels.put("general", "平台助手");
            for (Tab tab : out.tabs) {
                String mapped = labels.get(tab.id);
                if (mapped != null) {
                    tab.title = mapped;
                }
            }

            List<String> reading = new ArrayList<>();
            List<String> writing = new ArrayList<>();
            for (JSONObject q : usable) {
                String name = J.str(q, "name");
                if (name.matches(".*(文献|论文|检索|综述|arXiv|Pubmed).*")) {
                    reading.add(name);
                } else if (name.matches(".*(写作|润色|报告|摘要|投稿|论证).*")) {
                    writing.add(name);
                }
            }
            if (!reading.isEmpty()) {
                Tab tab = new Tab();
                tab.id = "literature";
                tab.title = "文献阅读";
                tab.questions = reading;
                out.tabs.add(tab);
            }
            if (!writing.isEmpty()) {
                Tab tab = new Tab();
                tab.id = "writing";
                tab.title = "学术写作";
                tab.questions = writing;
                out.tabs.add(tab);
            }
        } catch (Exception ignored) {
        }
        board = out;
        return out;
    }
}
