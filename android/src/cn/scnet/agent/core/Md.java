package cn.scnet.agent.core;

import java.util.ArrayList;
import java.util.List;

/**
 * 轻量 Markdown 解析（对齐 ArkTS 的 common/Markdown.ets，逻辑逐条照搬）。
 *
 * 设计要点（与 ArkTS 版一致）：
 * - 块级（标题/段落/列表/引用/代码块/分隔线/表格）各自成块，交给 UI 逐块渲染；
 * - 行内（**粗** / *斜* / `码` / [文字](url)）拆成段；
 * - **必须容忍流式半截输入**：未闭合的 ```、** 也要照常显示，不能吞字。
 */
public final class Md {

    public static final int H1 = 0, H2 = 1, H3 = 2, P = 3, BULLET = 4,
            ORDERED = 5, CODE = 6, QUOTE = 7, HR = 8, TABLE = 9;

    public static final class Block {
        public int kind;
        public String text = "";
        public int level;
        public int order;
        public String lang = "";
        public String code = "";
        /** 表格：首行是表头，其余数据行 */
        public List<List<String>> rows = new ArrayList<>();

        Block(int kind) {
            this.kind = kind;
        }
    }

    public static final class Seg {
        public final String text;
        public final boolean bold;
        public final boolean italic;
        public final boolean code;

        Seg(String text, boolean bold, boolean italic, boolean code) {
            this.text = text;
            this.bold = bold;
            this.italic = italic;
            this.code = code;
        }
    }

    private Md() {
    }

    /** `|a|b|` → ["a","b"]；允许首尾不写竖线。 */
    public static List<String> splitRow(String line) {
        String body = line == null ? "" : line.trim();
        if (body.startsWith("|")) {
            body = body.substring(1);
        }
        if (body.endsWith("|")) {
            body = body.substring(0, body.length() - 1);
        }
        List<String> out = new ArrayList<>();
        for (String part : body.split("\\|", -1)) {
            out.add(part.trim());
        }
        return out;
    }

    private static boolean isSeparator(String line) {
        String body = line == null ? "" : line.trim();
        if (body.indexOf('-') < 0) {
            return false;
        }
        List<String> cells = splitRow(body);
        for (String cell : cells) {
            if (!cell.replaceAll("\\s", "").matches("^:?-{2,}:?$")) {
                return false;
            }
        }
        return !cells.isEmpty();
    }

    private static boolean isFence(String line) {
        return line != null && line.trim().startsWith("```");
    }

    /** 解析成块：单遍、无递归、无正则回溯，几千字流式也稳。 */
    public static List<Block> parse(String source) {
        List<Block> blocks = new ArrayList<>();
        if (source == null || source.length() == 0) {
            return blocks;
        }
        String[] lines = source.split("\n", -1);
        int i = 0;
        StringBuilder paragraph = new StringBuilder();

        while (i < lines.length) {
            String raw = lines[i];
            String line = raw.endsWith("\r") ? raw.substring(0, raw.length() - 1) : raw;
            String trimmed = line.trim();

            // ``` 代码块：未闭合也照常渲染（流式中间态）
            if (isFence(line)) {
                flushParagraph(blocks, paragraph);
                String lang = line.trim().substring(3).trim();
                StringBuilder body = new StringBuilder();
                i++;
                while (i < lines.length && !isFence(lines[i])) {
                    if (body.length() > 0) {
                        body.append('\n');
                    }
                    body.append(lines[i]);
                    i++;
                }
                i++; // 跳过闭合 ```
                Block code = new Block(CODE);
                code.lang = lang;
                code.code = body.toString();
                blocks.add(code);
                continue;
            }

            if (trimmed.length() == 0) {
                flushParagraph(blocks, paragraph);
                i++;
                continue;
            }

            // 表格：`|a|b|` + `|---|---|`
            if (trimmed.startsWith("|") && trimmed.indexOf('|', 1) > 0) {
                String next = i + 1 < lines.length ? lines[i + 1] : "";
                if (isSeparator(next)) {
                    flushParagraph(blocks, paragraph);
                    Block table = new Block(TABLE);
                    table.rows.add(splitRow(trimmed));
                    int j = i + 2;
                    while (j < lines.length) {
                        String candidate = lines[j].trim();
                        if (candidate.length() == 0 || candidate.indexOf('|') < 0) {
                            break;
                        }
                        table.rows.add(splitRow(candidate));
                        j++;
                    }
                    blocks.add(table);
                    i = j;
                    continue;
                }
            }

            if (trimmed.equals("---") || trimmed.equals("***") || trimmed.equals("___")) {
                flushParagraph(blocks, paragraph);
                blocks.add(new Block(HR));
                i++;
                continue;
            }

            if (trimmed.startsWith("#")) {
                int level = 0;
                while (level < trimmed.length() && trimmed.charAt(level) == '#') {
                    level++;
                }
                if (level >= 1 && level <= 6) {
                    String rest = trimmed.substring(level).trim();
                    if (rest.length() > 0) {
                        flushParagraph(blocks, paragraph);
                        Block head = new Block(level == 1 ? H1 : (level == 2 ? H2 : H3));
                        head.text = rest;
                        head.level = level;
                        blocks.add(head);
                        i++;
                        continue;
                    }
                }
            }

            if (trimmed.startsWith(">")) {
                flushParagraph(blocks, paragraph);
                String text = trimmed;
                while (text.startsWith(">")) {
                    text = text.substring(1).trim();
                }
                Block quote = new Block(QUOTE);
                quote.text = text;
                blocks.add(quote);
                i++;
                continue;
            }

            char bullet = trimmed.charAt(0);
            if ((bullet == '-' || bullet == '*' || bullet == '+')
                    && trimmed.length() > 1
                    && (trimmed.charAt(1) == ' ' || trimmed.charAt(1) == '\t')) {
                flushParagraph(blocks, paragraph);
                int indent = line.length() - line.replaceAll("^\\s+", "").length();
                Block item = new Block(BULLET);
                item.text = trimmed.substring(1).trim();
                item.level = Math.min(2, indent / 2);
                blocks.add(item);
                i++;
                continue;
            }

            int digits = 0;
            while (digits < trimmed.length()
                    && trimmed.charAt(digits) >= '0' && trimmed.charAt(digits) <= '9') {
                digits++;
            }
            if (digits > 0 && digits < 4 && trimmed.length() > digits + 1) {
                char mark = trimmed.charAt(digits);
                if ((mark == '.' || mark == ')' || mark == '、') && trimmed.charAt(digits + 1) == ' ') {
                    flushParagraph(blocks, paragraph);
                    int indent = line.length() - line.replaceAll("^\\s+", "").length();
                    Block item = new Block(ORDERED);
                    item.text = trimmed.substring(digits + 1).trim();
                    item.level = Math.min(2, indent / 2);
                    try {
                        item.order = Integer.parseInt(trimmed.substring(0, digits));
                    } catch (Exception e) {
                        item.order = 1;
                    }
                    blocks.add(item);
                    i++;
                    continue;
                }
            }

            if (paragraph.length() > 0) {
                paragraph.append(' ');
            }
            paragraph.append(trimmed);
            i++;
        }
        flushParagraph(blocks, paragraph);
        return blocks;
    }

    private static void flushParagraph(List<Block> blocks, StringBuilder paragraph) {
        String text = paragraph.toString().trim();
        if (text.length() > 0) {
            Block p = new Block(P);
            p.text = text;
            blocks.add(p);
        }
        paragraph.setLength(0);
    }

    /** `[文字](url)` → `文字`。 */
    private static String stripLinks(String text) {
        if (text.indexOf("](") < 0) {
            return text;
        }
        StringBuilder out = new StringBuilder();
        int i = 0;
        while (i < text.length()) {
            char ch = text.charAt(i);
            if (ch == '[') {
                int mid = text.indexOf("](", i + 1);
                int close = mid > 0 ? text.indexOf(')', mid + 2) : -1;
                if (mid > 0 && close > mid) {
                    out.append(text, i + 1, mid);
                    i = close + 1;
                    continue;
                }
            }
            out.append(ch);
            i++;
        }
        return out.toString();
    }

    /** 行内解析：**粗体** / *斜体* / `行内代码` / [文字](url)。 */
    public static List<Seg> inline(String text) {
        List<Seg> segs = new ArrayList<>();
        if (text == null) {
            return segs;
        }
        StringBuilder pending = new StringBuilder();
        int i = 0;

        while (i < text.length()) {
            char ch = text.charAt(i);

            if (ch == '`') {
                int end = text.indexOf('`', i + 1);
                if (end > i + 1) {
                    push(segs, pending);
                    push(segs, new Seg(text.substring(i + 1, end), false, false, true));
                    i = end + 1;
                    continue;
                }
            }

            if (ch == '*' && i + 1 < text.length() && text.charAt(i + 1) == '*') {
                int end = text.indexOf("**", i + 2);
                if (end > i + 2) {
                    String inner = text.substring(i + 2, end);
                    boolean tight = inner.length() > 0
                            && inner.charAt(0) != ' '
                            && inner.charAt(inner.length() - 1) != ' ';
                    if (tight) {
                        push(segs, pending);
                        push(segs, new Seg(inner, true, false, false));
                        i = end + 2;
                        continue;
                    }
                }
            }

            if (ch == '*') {
                int end = text.indexOf('*', i + 1);
                if (end > i + 1) {
                    String inner = text.substring(i + 1, end);
                    boolean tight = inner.length() > 0
                            && inner.charAt(0) != ' '
                            && inner.charAt(inner.length() - 1) != ' ';
                    if (tight) {
                        push(segs, pending);
                        push(segs, new Seg(inner, false, true, false));
                        i = end + 1;
                        continue;
                    }
                }
            }

            if (ch == '[') {
                int mid = text.indexOf("](", i + 1);
                int close = mid > 0 ? text.indexOf(')', mid + 2) : -1;
                if (mid > 0 && close > mid) {
                    push(segs, pending);
                    push(segs, new Seg(text.substring(i + 1, mid), false, false, false));
                    i = close + 1;
                    continue;
                }
            }

            pending.append(ch);
            i++;
        }
        push(segs, pending);
        return segs;
    }

    private static void push(List<Seg> segs, StringBuilder pending) {
        if (pending.length() > 0) {
            push(segs, new Seg(pending.toString(), false, false, false));
            pending.setLength(0);
        }
    }

    private static void push(List<Seg> segs, Seg seg) {
        String cleaned = seg.code ? seg.text : stripLinks(seg.text);
        if (cleaned.length() == 0) {
            return;
        }
        segs.add(new Seg(cleaned, seg.bold, seg.italic, seg.code));
    }
}
