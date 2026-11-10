package cn.scnet.agent.core;

import android.os.Handler;
import android.os.Looper;

import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * 极简异步工具：网络/文件在后台线程跑，结果回主线程。
 * ArkTS 版用的是 async/await，这里换成回调，调用点保持一样的顺序。
 */
public final class Task {

    public interface Call<T> {
        void ok(T value);

        void fail(String message);
    }

    public interface Work<T> {
        T run() throws Exception;
    }

    private static final ExecutorService POOL = Executors.newFixedThreadPool(4);
    private static final Handler MAIN = new Handler(Looper.getMainLooper());

    private Task() {
    }

    public static <T> void run(Work<T> work, Call<T> call) {
        POOL.execute(new Runnable() {
            @Override
            public void run() {
                try {
                    final T value = work.run();
                    MAIN.post(new Runnable() {
                        @Override
                        public void run() {
                            if (call != null) {
                                call.ok(value);
                            }
                        }
                    });
                } catch (final Exception e) {
                    final String message = e.getMessage() == null ? e.toString() : e.getMessage();
                    MAIN.post(new Runnable() {
                        @Override
                        public void run() {
                            if (call != null) {
                                call.fail(message);
                            }
                        }
                    });
                }
            }
        });
    }

    /** 后台执行、不回主线程（会话落盘这类）。 */
    public static void bg(Runnable runnable) {
        POOL.execute(runnable);
    }

    public static void onMain(Runnable runnable) {
        if (Looper.myLooper() == Looper.getMainLooper()) {
            runnable.run();
        } else {
            MAIN.post(runnable);
        }
    }
}
