package cn.scnet.agent.core;

import java.util.ArrayList;
import java.util.List;

/** 对话纯逻辑（对齐 ArkTS 的 common/Chat.ets，有单测向量的部分值钱）。 */
public final class ChatText {

    /** 单次请求携带的历史上限（字符数，粗估 token≈chars/3）。 */
    public static final int HISTORY_LIMIT = 24000;
    /** 无论如何至少保留最近这么多条。 */
    public static final int HISTORY_MIN_KEEP = 6;

    public static final class Turn {
        public final String role;
        public final String content;

        public Turn(String role, String content) {
            this.role = role;
            this.content = content;
        }
    }

    public static final class Trimmed {
        public final List<Turn> turns;
        public final int dropped;

        Trimmed(List<Turn> turns, int dropped) {
            this.turns = turns;
            this.dropped = dropped;
        }
    }

    private ChatText() {
    }

    /** 上下文裁剪：从最新往前累计，超上限即停，但至少保留最近 minKeep 条。 */
    public static Trimmed trimHistory(List<Turn> turns, int limit, int minKeep) {
        List<Turn> out = new ArrayList<>();
        int chars = 0;
        for (int i = turns.size() - 1; i >= 0; i--) {
            Turn turn = turns.get(i);
            int cost = turn.content == null ? 0 : turn.content.length();
            boolean enough = out.size() >= minKeep && chars + cost > limit;
            if (enough) {
                java.util.Collections.reverse(out);
                return new Trimmed(out, i + 1);
            }
            out.add(turn);
            chars += cost;
        }
        java.util.Collections.reverse(out);
        return new Trimmed(out, 0);
    }

    public static Trimmed trimHistory(List<Turn> turns) {
        return trimHistory(turns, HISTORY_LIMIT, HISTORY_MIN_KEEP);
    }

    /** 粗估 token（中文 1 字 1 token、英文 4 字符 1 token 的保守混合）。 */
    public static int estimateTokens(List<Turn> turns) {
        int n = 0;
        for (Turn turn : turns) {
            String text = turn.content == null ? "" : turn.content;
            int wide = 0;
            for (int i = 0; i < text.length(); i++) {
                if (text.charAt(i) > 0x2e80) {
                    wide++;
                }
            }
            n += wide + (int) Math.ceil((text.length() - wide) / 4.0);
        }
        return n;
    }

    /** 首条用户消息 → 会话标题（去换行、截断 24 字）。 */
    public static String titleFrom(List<String> roles, List<String> contents) {
        for (int i = 0; i < roles.size(); i++) {
            if ("user".equals(roles.get(i))) {
                String text = contents.get(i) == null ? "" : contents.get(i);
                text = text.replaceAll("\\s+", " ").trim();
                if (text.length() > 0) {
                    return text.length() > 24 ? text.substring(0, 24) + "…" : text;
                }
            }
        }
        return "新对话";
    }

    public static String prettyModel(String id) {
        if (id == null || id.length() == 0) {
            return "模型";
        }
        String name = id;
        if (name.startsWith("SCNet-")) {
            return name;
        }
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < name.length(); i++) {
            char ch = name.charAt(i);
            if (ch == '-' || ch == '_') {
                sb.append(' ');
            } else {
                sb.append(ch);
            }
        }
        return sb.toString();
    }
}
