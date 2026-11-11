package cn.scnet.agent.core;

import android.content.Context;

import java.io.File;
import java.io.FileOutputStream;
import java.nio.charset.Charset;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Locale;

/**
 * 把一次流式会话的"原始证据"落盘，方便没有 adb 输入权限时排查：
 *   files/stream.log（外部私有目录，adb pull 可取）
 * 内容：每个非 text 帧的类型与关键字段、最终正文（截断 8KB）、正文里出现的全部 URL。
 */
public final class StreamLog {

    private static final String FILE = "stream.log";
    private static final StringBuilder PENDING = new StringBuilder();
    private static final SimpleDateFormat FMT =
            new SimpleDateFormat("MM-dd HH:mm:ss", Locale.US);

    private StreamLog() {
    }

    public static synchronized void event(Context context, String text) {
        PENDING.append(FMT.format(new Date())).append("  ").append(text).append('\n');
        if (PENDING.length() > 200 * 1024) {
            PENDING.delete(0, PENDING.length() - 150 * 1024);
        }
        flush(context);
    }

    /** 一次流结束时调用：记录正文与 URL 摘要。 */
    public static synchronized void finalText(Context context, String channel, String text) {
        if (text == null) {
            text = "";
        }
        StringBuilder sb = new StringBuilder();
        sb.append("---- final (").append(channel).append(", ").append(text.length())
                .append(" chars) ----\n");
        sb.append(text.length() > 8192 ? text.substring(0, 8192) + "…" : text).append('\n');
        java.util.regex.Matcher m = java.util.regex.Pattern
                .compile("https?://[^\\s)\\]}>\"']+").matcher(text);
        StringBuilder urls = new StringBuilder();
        while (m.find()) {
            String url = m.group();
            if (urls.indexOf(url) >= 0) {
                continue;
            }
            urls.append("  URL: ").append(url).append('\n');
        }
        if (urls.length() > 0) {
            sb.append("---- urls ----\n").append(urls);
        }
        PENDING.append(sb);
        flush(context);
    }

    private static void flush(Context context) {
        try {
            File ext = context.getExternalFilesDir(null);
            File target = new File(ext != null ? ext : context.getFilesDir(), FILE);
            FileOutputStream out = new FileOutputStream(target, false);
            out.write(PENDING.toString().getBytes(Charset.forName("UTF-8")));
            out.flush();
            out.close();
        } catch (Throwable ignored) {
        }
    }

    public static synchronized void clear() {
        PENDING.setLength(0);
    }
}
