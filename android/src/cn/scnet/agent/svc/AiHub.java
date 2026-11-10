package cn.scnet.agent.svc;

import org.json.JSONArray;
import org.json.JSONObject;

import java.util.ArrayList;
import java.util.List;

import cn.scnet.agent.core.Http;
import cn.scnet.agent.core.J;

/**
 * AIHub（AI 社区）智能体（对齐 ArkTS 的 service/AiHub.ets）。
 *
 * 这些是独立应用（link 外链 / host 三方托管 / build 平台构建），
 * 没有原生对话接口，正确形态是内嵌 Web 打开它的页面。
 */
public class AiHub {

    public static class Agent {
        public String agentId = "";
        public String name = "";
        public String desc = "";
        public String avatarUrl = "";
        public String logoUrl = "";
        public String sourceType = "";
        public String createUser = "";
        public String nameEn = "";
    }

    private static final AiHub INSTANCE = new AiHub();

    public static AiHub get() {
        return INSTANCE;
    }

    public static String webUrl(Agent agent) {
        return "https://www.scnet.cn/ui/aihub/agent/"
                + Http.enc(agent.createUser) + "/" + Http.enc(agent.nameEn);
    }

    public static String sourceLabel(String sourceType) {
        if ("link".equals(sourceType)) {
            return "外链";
        }
        if ("host".equals(sourceType)) {
            return "三方托管";
        }
        if ("build".equals(sourceType)) {
            return "平台构建";
        }
        return sourceType;
    }

    public List<Agent> selectedAgents() {
        List<Agent> out = new ArrayList<>();
        try {
            JSONObject data = Http.postJson("/acx/aihub/selected/agent/list", "{}");
            JSONArray list = data.optJSONArray("records");
            if (list == null) {
                // 有的版本直接返回数组，退回原始解析
                Http.Response raw = Http.postRaw("/acx/aihub/selected/agent/list", "{}");
                Object parsed = J.unwrapData(raw.body == null ? "{}" : raw.body);
                list = parsed instanceof JSONArray ? (JSONArray) parsed : new JSONArray();
            }
            for (int i = 0; i < list.length(); i++) {
                JSONObject row = J.at(list, i);
                Agent a = new Agent();
                a.agentId = J.str(row, "agentId");
                a.name = J.str(row, "nameCn");
                if (a.name.length() == 0) {
                    a.name = J.str(row, "nameEn");
                }
                a.desc = J.str(row, "desc");
                a.avatarUrl = J.str(row, "avatarUrl");
                a.logoUrl = J.str(row, "logoUrl");
                a.sourceType = J.str(row, "sourceType");
                a.createUser = J.str(row, "createUser");
                a.nameEn = J.str(row, "nameEn");
                if (a.name.length() > 0) {
                    out.add(a);
                }
            }
        } catch (Exception ignored) {
        }
        return out;
    }
}
