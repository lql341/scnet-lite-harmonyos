package cn.scnet.agent.core;

import android.app.Activity;
import android.content.Context;
import android.os.Handler;
import android.os.Looper;

import java.io.File;
import java.io.FileOutputStream;
import java.io.PrintWriter;
import java.io.StringWriter;
import java.nio.charset.Charset;

/**
 * 全局崩溃捕获。
 *
 * 为什么需要：在 Android 兼容容器（卓易通/出境易这类）里没有 adb，`logcat` 拿不到，
 * 闪退就等于零信息。这里把堆栈落到 filesDir/crash.log，并且下次启动时在界面上直接显示，
 * 用户可以复制发给开发者。
 */
public final class Crash {

    private static final String FILE = "crash.log";
    private static String pending;

    private Crash() {
    }

    public static void install(final Context context) {
        final Context app = context.getApplicationContext();
        final Thread.UncaughtExceptionHandler previous = Thread.getDefaultUncaughtExceptionHandler();
        Thread.setDefaultUncaughtExceptionHandler(new Thread.UncaughtExceptionHandler() {
            @Override
            public void uncaughtException(Thread thread, Throwable error) {
                try {
                    String text = dump(thread, error);
                    write(app, text);
                    // 再往公共下载目录写一份（容器里可能只有这条路能取到文件）
                    writeQuiet(new File("/storage/media/100/local/files/Docs/Download/scnet-crash.txt"), text);
                } catch (Throwable ignored) {
                }
                if (previous != null) {
                    previous.uncaughtException(thread, error);
                }
            }
        });
    }

    private static String dump(Thread thread, Throwable error) {
        StringWriter sw = new StringWriter();
        PrintWriter pw = new PrintWriter(sw);
        pw.println("time   : " + new java.util.Date());
        pw.println("thread : " + thread.getName());
        pw.println("device : " + android.os.Build.MANUFACTURER + " " + android.os.Build.MODEL
                + " / Android " + android.os.Build.VERSION.RELEASE
                + " (API " + android.os.Build.VERSION.SDK_INT + ")");
        pw.println();
        error.printStackTrace(pw);
        pw.flush();
        return sw.toString();
    }

    private static void write(Context context, String text) {
        writeQuiet(new File(context.getFilesDir(), FILE), text);
        pending = text;
    }

    private static void writeQuiet(File file, String text) {
        FileOutputStream out = null;
        try {
            File dir = file.getParentFile();
            if (dir != null && !dir.exists()) {
                //noinspection ResultOfMethodCallIgnored
                dir.mkdirs();
            }
            out = new FileOutputStream(file, false);
            out.write(text.getBytes(Charset.forName("UTF-8")));
            out.flush();
        } catch (Throwable ignored) {
        } finally {
            if (out != null) {
                try {
                    out.close();
                } catch (Throwable ignored) {
                }
            }
        }
    }

    /** 上次崩溃的堆栈（没有就返回空串）。 */
    public static String last(Context context) {
        if (pending != null) {
            return pending;
        }
        try {
            File file = new File(context.getFilesDir(), FILE);
            if (!file.exists()) {
                return "";
            }
            java.io.FileInputStream in = new java.io.FileInputStream(file);
            byte[] buf = new byte[(int) file.length()];
            int off = 0;
            int n;
            while (off < buf.length && (n = in.read(buf, off, buf.length - off)) > 0) {
                off += n;
            }
            in.close();
            pending = new String(buf, 0, off, Charset.forName("UTF-8"));
            return pending;
        } catch (Throwable e) {
            return "";
        }
    }

    public static void clear(Context context) {
        pending = null;
        //noinspection ResultOfMethodCallIgnored
        new File(context.getFilesDir(), FILE).delete();
    }

    /** 兜底界面：把崩溃堆栈直接铺在屏幕上（容器里没有 adb 也能复制）。 */
    public static void fatal(Activity activity, Throwable error) {
        String text = "";
        try {
            text = dump(Thread.currentThread(), error);
            write(activity, text);
        } catch (Throwable ignored) {
        }
        android.widget.ScrollView scroll = new android.widget.ScrollView(activity);
        android.widget.LinearLayout box = new android.widget.LinearLayout(activity);
        box.setOrientation(android.widget.LinearLayout.VERTICAL);
        box.setPadding(40, 60, 40, 40);

        android.widget.TextView title = new android.widget.TextView(activity);
        title.setText("页面出错了\n把下面的内容复制发给开发者即可定位");
        title.setTextSize(15f);
        title.setTextColor(0xFFC4161C);
        box.addView(title);

        final String crashText = text;
        android.widget.TextView copy = new android.widget.TextView(activity);
        copy.setText("［复制错误信息］");
        copy.setTextSize(14f);
        copy.setPadding(0, 24, 0, 24);
        copy.setTextColor(0xFF0B4F8A);
        copy.setOnClickListener(new android.view.View.OnClickListener() {
            @Override
            public void onClick(android.view.View v) {
                android.content.ClipboardManager cm = (android.content.ClipboardManager)
                        activity.getSystemService(Context.CLIPBOARD_SERVICE);
                cm.setPrimaryClip(android.content.ClipData.newPlainText("crash", crashText));
                android.widget.Toast.makeText(activity, "已复制", android.widget.Toast.LENGTH_SHORT).show();
            }
        });
        box.addView(copy);

        android.widget.TextView body = new android.widget.TextView(activity);
        body.setText(text);
        body.setTextSize(9f);
        body.setTypeface(android.graphics.Typeface.MONOSPACE);
        body.setTextIsSelectable(true);
        box.addView(body);
        scroll.addView(box);
        try {
            activity.setContentView(scroll);
        } catch (Throwable ignored) {
        }
    }

    /** 跑一段界面代码，出错就把堆栈铺到屏幕上，而不是闪退。 */
    public static void guard(Activity activity, Runnable body) {
        try {
            body.run();
        } catch (final Throwable error) {
            fatal(activity, error);
        }
    }

    /** 启动时如果有上次崩溃，直接在界面上弹出来（可复制）。 */
    /** 诊断摘要（版本 / 环境 / 最近崩溃 / 关键配置是否就绪），设置页可一键复制。 */
    public static String diagnostics(Context context) {
        StringBuilder sb = new StringBuilder();
        sb.append("time   : ").append(new java.util.Date()).append('\n');
        sb.append("device : ").append(android.os.Build.MANUFACTURER).append(' ')
                .append(android.os.Build.MODEL).append(" / Android ")
                .append(android.os.Build.VERSION.RELEASE).append(" (API ")
                .append(android.os.Build.VERSION.SDK_INT).append(")\n");
        try {
            android.content.pm.PackageInfo info = context.getPackageManager()
                    .getPackageInfo(context.getPackageName(), 0);
            sb.append("app    : ").append(info.versionName).append(" (")
                    .append(info.versionCode).append(")\n");
        } catch (Throwable ignored) {
        }
        try {
            sb.append("base   : ").append(Http.base()).append('\n');
            sb.append("token  : ").append(Http.token.length() > 0 ? "有" : "无")
                    .append("  cookie: ").append(Http.cookie.length() > 0 ? "有" : "无").append('\n');
            sb.append("autoKey: ").append(Store.get().getAutoKey().length()).append(" 字符\n");
            sb.append("model  : ").append(Store.get().getModel())
                    .append("  channel: ").append(Store.get().getChannel()).append('\n');
        } catch (Throwable ignored) {
        }
        String last = last(context);
        if (last.length() > 0) {
            sb.append("\n=== 上次崩溃 ===\n").append(last);
        }
        return sb.toString();
    }

    public static void showIfAny(final Activity activity) {
        final String text = last(activity);
        if (text.length() == 0) {
            return;
        }
        new Handler(Looper.getMainLooper()).post(new Runnable() {
            @Override
            public void run() {
                android.app.AlertDialog.Builder builder = new android.app.AlertDialog.Builder(activity);
                builder.setTitle("上次崩溃了（点复制发给开发者）");
                android.widget.TextView view = new android.widget.TextView(activity);
                view.setText(text);
                view.setTextSize(9f);
                view.setTypeface(android.graphics.Typeface.MONOSPACE);
                view.setTextIsSelectable(true);
                view.setPadding(30, 20, 30, 20);
                android.widget.ScrollView scroll = new android.widget.ScrollView(activity);
                scroll.addView(view);
                builder.setView(scroll);
                builder.setNegativeButton("关闭", null);
                builder.setPositiveButton("复制", new android.content.DialogInterface.OnClickListener() {
                    @Override
                    public void onClick(android.content.DialogInterface dialog, int which) {
                        android.content.ClipboardManager cm = (android.content.ClipboardManager)
                                activity.getSystemService(Context.CLIPBOARD_SERVICE);
                        cm.setPrimaryClip(android.content.ClipData.newPlainText("crash", text));
                    }
                });
                builder.show();
            }
        });
    }
}
