package cn.scnet.agent.core;

import java.io.InputStream;
import java.io.OutputStream;
import java.nio.ByteBuffer;
import java.nio.CharBuffer;
import java.nio.charset.Charset;
import java.nio.charset.CharsetDecoder;
import java.nio.charset.CodingErrorAction;
import java.util.ArrayList;
import java.util.List;

/**
 * SSE 行缓冲（对齐 ArkTS 的 common/Sse.ets，两个坑照抄）：
 *
 * 1. **跨块多字节**：块边界可能把 UTF-8 汉字切两半 → 必须用流式解码
 *    （`decoder.decode(in, out, false)`），未凑齐的字节留到下一块。**不能**对每块单独解码。
 * 2. **无换行的残尾**：网关 402/401 的报错体是单行 JSON 且没有换行，只按 \n 切永远等不到，
 *    流结束必须 flush() 再处理一次。
 */
public class Sse {

    private static final Charset UTF8 = Charset.forName("UTF-8");

    private final CharsetDecoder decoder;
    private final StringBuilder buffer = new StringBuilder();
    /** 上一块末尾没凑齐一个字符的字节（最多 3 个）。 */
    private byte[] pending = new byte[0];

    public Sse() {
        decoder = UTF8.newDecoder()
                .onMalformedInput(CodingErrorAction.REPLACE)
                .onUnmappableCharacter(CodingErrorAction.REPLACE);
    }

    /** 喂一块字节，返回本次凑齐的完整行。 */
    public List<String> pushBytes(byte[] chunk, int length) {
        byte[] merged = new byte[pending.length + length];
        System.arraycopy(pending, 0, merged, 0, pending.length);
        System.arraycopy(chunk, 0, merged, pending.length, length);
        ByteBuffer in = ByteBuffer.wrap(merged);
        CharBuffer out = CharBuffer.allocate(merged.length * 2 + 16);
        try {
            decoder.decode(in, out, false);
        } catch (Exception e) {
            // 解码异常：退化成"能解多少解多少"，不中断流
            buffer.append(new String(merged, 0, merged.length, UTF8));
            pending = new byte[0];
            return drain();
        }
        out.flip();
        buffer.append(out);
        // 没被消费的字节 = 半个 UTF-8 字符，留给下一块
        int rest = in.remaining();
        if (rest > 0) {
            pending = new byte[rest];
            in.get(pending);
        } else {
            pending = new byte[0];
        }
        return drain();
    }

    public List<String> pushText(String text) {
        buffer.append(text);
        return drain();
    }

    /** 流结束：把没凑齐的字节与没有结尾换行的残留一起吐出。 */
    public List<String> flush() {
        if (pending.length > 0) {
            CharBuffer out = CharBuffer.allocate(pending.length * 2 + 16);
            try {
                decoder.decode(ByteBuffer.wrap(pending), out, true);
                decoder.flush(out);
            } catch (Exception ignored) {
            }
            out.flip();
            buffer.append(out);
            pending = new byte[0];
        }
        List<String> out = new ArrayList<>();
        String rest = buffer.toString().trim();
        buffer.setLength(0);
        if (rest.length() > 0) {
            out.add(rest);
        }
        return out;
    }

    private List<String> drain() {
        List<String> out = new ArrayList<>();
        int index = buffer.indexOf("\n");
        while (index >= 0) {
            String line = buffer.substring(0, index);
            buffer.delete(0, index + 1);
            if (line.endsWith("\r")) {
                line = line.substring(0, line.length() - 1);
            }
            line = line.trim();
            if (line.length() > 0) {
                out.add(line);
            }
            index = buffer.indexOf("\n");
        }
        return out;
    }

    /** `data: {...}` → payload；不是 data 行返回空串。 */
    public static String payload(String line) {
        if (line == null || !line.startsWith("data:")) {
            return "";
        }
        return line.substring(5).trim();
    }

    public static void copy(InputStream in, OutputStream out) throws java.io.IOException {
        byte[] buf = new byte[8192];
        int n;
        while ((n = in.read(buf)) > 0) {
            out.write(buf, 0, n);
        }
    }
}
