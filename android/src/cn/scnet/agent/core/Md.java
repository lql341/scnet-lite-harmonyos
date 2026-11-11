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
            ORDERED = 5, CODE = 6, QUOTE = 7, HR = 8, TABLE = 9, IMAGE = 10;

    public static final class Block {
        public int kind;
        public String text = "";
        public int level;
        public int order;
        public String lang = "";
        public String code = "";
        /** 表格：首行是表头，其余数据行 */
        public List<List<String>> rows = new ArrayList<>();
        /** 表格列对齐：0 左 1 中 2 右（按分隔行的冒号位置） */
        public List<Integer> aligns = new ArrayList<>();

        Block(int kind) {
            this.kind = kind;
        }
    }

    public static final class Seg {
        public final String text;
        public final boolean bold;
        public final boolean italic;
        public final boolean code;
        public final boolean strike;
        /** 非空表示这段是链接文字，值为目标 URL。 */
        public final String link;

        Seg(String text, boolean bold, boolean italic, boolean code) {
            this(text, bold, italic, code, false, "");
        }

        Seg(String text, boolean bold, boolean italic, boolean code, boolean strike) {
            this(text, bold, italic, code, strike, "");
        }

        Seg(String text, boolean bold, boolean italic, boolean code, boolean strike, String link) {
            this.text = text;
            this.bold = bold;
            this.italic = italic;
            this.code = code;
            this.strike = strike;
            this.link = link == null ? "" : link;
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

    /** 从 `|---|:--:|` 解析每列对齐：0 左 / 1 中 / 2 右。 */
    private static List<Integer> alignsOf(String line) {
        List<Integer> out = new ArrayList<>();
        for (String cell : splitRow(line)) {
            String c = cell.replaceAll("\\s", "");
            boolean left = c.startsWith(":");
            boolean right = c.endsWith(":");
            out.add(left && right ? 1 : (right ? 2 : 0));
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

    /** 整行就是一个图片：`![alt](url)`（可带标题） */
    /** 图片行：`![alt](url)` 或 `[img](oss:///…)`（平台素材用后者）。 */
    private static String imageUrl(String line) {
        String t = line == null ? "" : line.trim();
        if (t.startsWith("[img](")) {
            int close = t.indexOf(')', 6);
            if (close > 6) {
                String url = t.substring(6, close).trim();
                return isImageLike(url) ? url : "";
            }
            return "";
        }
        if (!t.startsWith("![")) {
            return "";
        }
        int mid = t.indexOf("](");
        if (mid < 0) {
            return "";
        }
        int close = t.indexOf(')', mid + 2);
        if (close < 0) {
            return "";
        }
        String url = t.substring(mid + 2, close).trim();
        if (url.startsWith("<") && url.endsWith(">")) {
            url = url.substring(1, url.length() - 1);
        }
        // 去掉 title：![a](url "title")
        int space = url.indexOf(' ');
        if (space > 0) {
            url = url.substring(0, space);
        }
        return url;
    }

    /** 地址看起来是图片（按扩展名判断，oss:// 也适用）。 */
    public static boolean isImageLike(String url) {
        if (url == null) {
            return false;
        }
        String lower = url.trim().toLowerCase();
        int q = lower.indexOf('?');
        if (q > 0) {
            lower = lower.substring(0, q);
        }
        return lower.endsWith(".png") || lower.endsWith(".jpg") || lower.endsWith(".jpeg")
                || lower.endsWith(".gif") || lower.endsWith(".webp")
                || lower.endsWith(".svg") || lower.endsWith(".bmp");
    }

    /** 整行就是一个图片直链（png/jpg/gif/webp）。 */
    private static boolean isBareImageUrl(String line) {
        if (line.startsWith("oss://")) {
            return isImageLike(line);
        }
        if (!line.startsWith("http://") && !line.startsWith("https://")) {
            return false;
        }
        String lower = line.toLowerCase();
        int q = lower.indexOf('?');
        if (q > 0) {
            lower = lower.substring(0, q);
        }
        return lower.endsWith(".png") || lower.endsWith(".jpg") || lower.endsWith(".jpeg")
                || lower.endsWith(".gif") || lower.endsWith(".webp");
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
                    table.aligns = alignsOf(next);
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

            // 图片（整行）：![](url) 或裸图片链接
            String image = imageUrl(trimmed);
            if (image.length() == 0 && isBareImageUrl(trimmed)) {
                image = trimmed;
            }
            if (image.length() > 0) {
                flushParagraph(blocks, paragraph);
                Block img = new Block(IMAGE);
                img.text = image;
                blocks.add(img);
                i++;
                continue;
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
                        head.level = level;  // 4~6 仍归 H3 块，但 level 决定字号
                        blocks.add(head);
                        i++;
                        continue;
                    }
                }
            }

            if (trimmed.startsWith(">")) {
                flushParagraph(blocks, paragraph);
                StringBuilder quoteText = new StringBuilder();
                int depth = 0;
                while (i < lines.length && lines[i].trim().startsWith(">")) {
                    String line2 = lines[i].trim();
                    int level2 = 0;
                    while (line2.startsWith(">")) {
                        level2++;
                        line2 = line2.substring(1).trim();
                    }
                    depth = Math.max(depth, level2);
                    if (quoteText.length() > 0) {
                        quoteText.append('\n');
                    }
                    quoteText.append(line2);
                    i++;
                }
                Block quote = new Block(QUOTE);
                quote.text = quoteText.toString();
                quote.level = Math.max(0, depth - 1);  // 嵌套引用缩进
                blocks.add(quote);
                continue;
            }

            char bullet = trimmed.charAt(0);
            if ((bullet == '-' || bullet == '*' || bullet == '+')
                    && trimmed.length() > 1
                    && (trimmed.charAt(1) == ' ' || trimmed.charAt(1) == '\t')) {
                flushParagraph(blocks, paragraph);
                int indent = line.length() - line.replaceAll("^\\s+", "").length();
                Block item = new Block(BULLET);
                String body = trimmed.substring(1).trim();
                if (body.startsWith("[ ] ")) {
                    body = "☐ " + body.substring(4);
                } else if (body.startsWith("[x] ") || body.startsWith("[X] ")) {
                    body = "☑ " + body.substring(4);
                }
                item.text = body;
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
        paragraph.setLength(0);
        if (text.length() == 0) {
            return;
        }
        int i = 0;
        while (i < text.length()) {
            int start = text.indexOf("![", i);
            int imgLink = text.indexOf("[img](", i);
            if (imgLink >= 0 && (start < 0 || imgLink < start)) {
                int start2 = imgLink + 1; // 等价于 "![" 位置的替代物
                int mid2 = text.indexOf("](", imgLink);
                int close2 = mid2 < 0 ? -1 : text.indexOf(')', mid2 + 2);
                if (mid2 > 0 && close2 > mid2) {
                    String candidate = text.substring(mid2 + 2, close2).trim();
                    if (isImageLike(candidate)) {
                        if (imgLink > i) {
                            addText(blocks, text.substring(i, imgLink));
                        }
                        Block img = new Block(IMAGE);
                        img.text = candidate;
                        blocks.add(img);
                        i = close2 + 1;
                        continue;
                    }
                }
            }
            int mid = start < 0 ? -1 : text.indexOf("](", start);
            int close = mid < 0 ? -1 : text.indexOf(')', mid + 2);
            if (start < 0 || mid < 0 || close < 0) {
                addText(blocks, text.substring(i));
                return;
            }
            if (start > i) {
                addText(blocks, text.substring(i, start));
            }
            String url = text.substring(mid + 2, close).trim();
            int space = url.indexOf(' ');
            if (space > 0) {
                url = url.substring(0, space);
            }
            if (url.startsWith("<") && url.endsWith(">")) {
                url = url.substring(1, url.length() - 1);
            }
            if (url.length() > 0) {
                Block img = new Block(IMAGE);
                img.text = url;
                blocks.add(img);
            }
            i = close + 1;
        }
    }

    private static void addText(List<Block> blocks, String text) {
        String t = text.trim();
        if (t.length() > 0) {
            Block p = new Block(P);
            p.text = t;
            blocks.add(p);
        }
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

            // 删除线 ~~x~~
            if (ch == '~' && i + 1 < text.length() && text.charAt(i + 1) == '~') {
                int end = text.indexOf("~~", i + 2);
                if (end > i + 2) {
                    String inner = text.substring(i + 2, end);
                    if (inner.trim().length() > 0) {
                        push(segs, pending);
                        push(segs, new Seg(inner, false, false, false, true));
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
                    String label = text.substring(i + 1, mid);
                    String target = text.substring(mid + 2, close).trim();
                    int space = target.indexOf(' ');
                    if (space > 0) {
                        target = target.substring(0, space);
                    }
                    if (label.length() > 0) {
                        segs.add(new Seg(label, false, false, false, false, target));
                    }
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
        segs.add(new Seg(cleaned, seg.bold, seg.italic, seg.code, seg.strike, seg.link));
    }
}
