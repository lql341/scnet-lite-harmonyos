package cn.scnet.agent.core;

import java.nio.charset.Charset;
import java.util.ArrayList;
import java.util.List;

/**
 * 原生核心逻辑自检（不需要设备/Android 运行时，直接 JVM 跑）。
 *
 * 与仓库根 test/*.test.mjs 用同一批向量，确保 Kotlin/Java 移植没有走样：
 *   SSE 分帧（跨块多字节 / 无换行残尾）、上下文裁剪、HMAC、Markdown。
 *
 * 运行：scripts/test-android.sh
 */
public final class CoreTest {

    private static int pass;
    private static int fail;

    public static void main(String[] args) throws Exception {
        sse();
        history();
        hmac();
        markdown();
        System.out.println("\n" + (fail == 0 ? "全部通过" : "有失败"));
        System.out.println("pass=" + pass + " fail=" + fail);
        if (fail > 0) {
            System.exit(1);
        }
    }

    private static void eq(Object actual, Object expected, String label) {
        String a = String.valueOf(actual);
        String e = String.valueOf(expected);
        if (a.equals(e)) {
            pass++;
        } else {
            fail++;
            System.err.println("  x " + label + "\n    expected " + e + "\n    actual   " + a);
        }
    }

    private static void sse() {
        System.out.println("== SSE");
        Sse a = new Sse();
        eq(a.pushText("data: {\"a\":1}\ndata: {\"b\":2}\n").toString(),
                "[data: {\"a\":1}, data: {\"b\":2}]", "一次两块");
        eq(a.pushText("").toString(), "[]", "空块");

        Sse b = new Sse();
        eq(b.pushText("data: {\"a\"").toString(), "[]", "半行不产出");
        eq(b.pushText(":1}\n").toString(), "[data: {\"a\":1}]", "补齐后产出");

        Sse c = new Sse();
        eq(c.pushText("data: x\r\ndata: y\r\n").toString(), "[data: x, data: y]", "CRLF");

        Sse d = new Sse();
        d.pushText("{\"error\":{\"message\":\"Insufficient Balance\",\"code\":\"402\"}}");
        eq(d.flush().toString(),
                "[{\"error\":{\"message\":\"Insufficient Balance\",\"code\":\"402\"}}]",
                "无换行残尾要靠 flush");

        // 跨块多字节：把 "你好" 的 UTF-8 切成两半
        Sse e = new Sse();
        byte[] bytes = "data: 你好\n".getBytes(Charset.forName("UTF-8"));
        int cut = 8; // 落在"你"的多字节中间
        List<String> lines = new ArrayList<>();
        lines.addAll(e.pushBytes(bytes, cut));
        lines.addAll(e.pushBytes(slice(bytes, cut), bytes.length - cut));
        eq(lines.toString(), "[data: 你好]", "跨块多字节不乱码");

        eq(Sse.payload("data: {\"x\":1}"), "{\"x\":1}", "payload 取值");
        eq(Sse.payload("event: x"), "", "非 data 行");
    }

    private static byte[] slice(byte[] bytes, int from) {
        byte[] out = new byte[bytes.length - from];
        System.arraycopy(bytes, from, out, 0, out.length);
        return out;
    }

    private static void history() {
        System.out.println("== 上下文裁剪");
        List<ChatText.Turn> turns = new ArrayList<>();
        turns.add(new ChatText.Turn("user", "aaaaaaaaaa"));
        turns.add(new ChatText.Turn("assistant", "bbbbbbbbbb"));
        turns.add(new ChatText.Turn("user", "cccccccccc"));
        turns.add(new ChatText.Turn("assistant", "dddddddddd"));

        ChatText.Trimmed all = ChatText.trimHistory(turns, 1000, 2);
        eq(all.dropped, 0, "未超限不裁");
        eq(all.turns.size(), 4, "未超限全保留");

        // 与 test/history.test.mjs 同一组向量：10 条 × 100 字符，limit=350，minKeep=2
        List<ChatText.Turn> big = new ArrayList<>();
        for (int i = 0; i < 10; i++) {
            StringBuilder sb = new StringBuilder();
            for (int k = 0; k < 100; k++) {
                sb.append('x');
            }
            big.add(new ChatText.Turn(i % 2 == 0 ? "user" : "assistant", sb.toString()));
        }
        ChatText.Trimmed cut = ChatText.trimHistory(big, 350, 2);
        eq(cut.dropped, 7, "超限时丢弃最老的 7 条");
        eq(cut.turns.size(), 3, "保留最近 3 条");
        eq(cut.turns.get(cut.turns.size() - 1).content.length(), 100, "最后一条仍是原最后一条");

        // minKeep 保护：单条超长也不报丢弃
        List<ChatText.Turn> huge = new ArrayList<>();
        StringBuilder ys = new StringBuilder();
        for (int k = 0; k < 500; k++) {
            ys.append('y');
        }
        huge.add(new ChatText.Turn("user", ys.toString()));
        eq(ChatText.trimHistory(huge, 100, 2).turns.size(), 1, "minKeep 保护生效");
        eq(ChatText.trimHistory(huge, 100, 2).dropped, 0, "minKeep 内不报丢弃");

        List<ChatText.Turn> ordered = new ArrayList<>();
        ordered.add(new ChatText.Turn("user", "1"));
        ordered.add(new ChatText.Turn("assistant", "2"));
        ordered.add(new ChatText.Turn("user", "3"));
        ChatText.Trimmed keep = ChatText.trimHistory(ordered, 1000, 1);
        eq(keep.turns.get(0).content + keep.turns.get(1).content + keep.turns.get(2).content,
                "123", "保持原顺序");

        List<ChatText.Turn> mixed = new ArrayList<>();
        mixed.add(new ChatText.Turn("user", "中文字符测试"));
        eq(ChatText.estimateTokens(mixed), 6, "token 粗估（中文 1 字 1 token）");

        List<String> roles = new ArrayList<>();
        List<String> contents = new ArrayList<>();
        roles.add("assistant");
        roles.add("user");
        contents.add("hi");
        contents.add("  你好\n世界  ");
        eq(ChatText.titleFrom(roles, contents), "你好 世界", "标题取首条用户消息并压缩空白");
    }

    private static void hmac() {
        System.out.println("== HMAC-SHA256");
        eq(Hmac.hmacHex("key", "The quick brown fox jumps over the lazy dog"),
                "f7bc83f430538424b13298e6aa6fb143ef4d59a14946175997479dbc2d1a3cd8",
                "RFC 4231 用例");
        eq(Hmac.hex(Hmac.sha256("abc".getBytes(Charset.forName("UTF-8")))),
                "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
                "SHA-256 向量");
        eq(Hmac.hpcSignMessage("ak", "123", "u"),
                "{\"accessKey\":\"ak\",\"timestamp\":\"123\",\"user\":\"u\"}",
                "签名 message 字段顺序");
        eq(Hmac.selfCheck(), "true", "自检");
    }

    private static void markdown() {
        System.out.println("== Markdown");
        List<Md.Block> blocks = Md.parse("# 标题\n\n正文 **加粗** 和 `代码`\n\n- 一\n- 二\n\n```java\nint a=1;\n```");
        eq(blocks.get(0).kind, Md.H1, "标题块");
        eq(blocks.get(0).text, "标题", "标题内容");
        eq(blocks.get(1).kind, Md.P, "段落块");
        eq(blocks.get(2).kind, Md.BULLET, "无序列表");
        eq(blocks.get(3).kind, Md.BULLET, "无序列表 2");
        eq(blocks.get(4).kind, Md.CODE, "代码块");
        eq(blocks.get(4).lang, "java", "代码语言");
        eq(blocks.get(4).code, "int a=1;", "代码内容");

        // 未闭合的 ``` 也要渲染（流式中间态）
        List<Md.Block> streaming = Md.parse("```python\nprint(1)");
        eq(streaming.get(0).kind, Md.CODE, "未闭合代码块");
        eq(streaming.get(0).code, "print(1)", "未闭合代码内容");

        // 表格
        List<Md.Block> table = Md.parse("|a|b|\n|---|---|\n|1|2|\n|3|4|");
        eq(table.get(0).kind, Md.TABLE, "表格块");
        eq(table.get(0).rows.size(), 3, "表格行数（含表头）");
        eq(table.get(0).rows.get(0).toString(), "[a, b]", "表头");
        eq(table.get(0).rows.get(2).toString(), "[3, 4]", "数据行");

        // 行内
        List<Md.Seg> segs = Md.inline("前 **粗** *斜* `码` 后 [链接](https://x.y)");
        StringBuilder dump = new StringBuilder();
        for (Md.Seg seg : segs) {
            dump.append(seg.text)
                    .append(seg.bold ? "|B" : "")
                    .append(seg.italic ? "|I" : "")
                    .append(seg.code ? "|C" : "")
                    .append(";");
        }
        eq(dump.toString(), "前 ;粗|B; ;斜|I; ;码|C; 后 ;链接;", "行内样式拆段");

        // 未闭合粗体：保留字面量，不吞字
        List<Md.Seg> open = Md.inline("**没闭合");
        eq(open.get(0).text, "**没闭合", "未闭合粗体保留字面量");

        // 引用 / 分隔线 / 有序列表
        List<Md.Block> misc = Md.parse("> 引用\n\n---\n\n1. 第一\n2. 第二");
        eq(misc.get(0).kind, Md.QUOTE, "引用");
        eq(misc.get(1).kind, Md.HR, "分隔线");
        eq(misc.get(2).kind, Md.ORDERED, "有序列表");
        eq(misc.get(2).order, 1, "有序列表序号");
    }
}
