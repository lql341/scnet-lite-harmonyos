package cn.scnet.agent.ui;

import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.os.Handler;
import android.os.Looper;
import android.util.LruCache;
import android.widget.ImageView;

import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * 极简图片加载：URL → Bitmap（内存 LRU + 后台线程 + ImageView 绑定）。
 *
 * 为什么不引三方库：整个 App 没有 Gradle/AndroidX，多一个依赖就多一套构建约束；
 * 聊天里的图片只用于展示模型返回的图 / Markdown 里的图片，够用即可。
 */
public final class ImageLoader {

    private static final ExecutorService POOL = Executors.newFixedThreadPool(3);
    private static final Handler MAIN = new Handler(Looper.getMainLooper());
    /** 约 12MB 的内存缓存。 */
    private static final LruCache<String, Bitmap> CACHE =
            new LruCache<String, Bitmap>((int) (Runtime.getRuntime().maxMemory() / 1024 / 12)) {
                @Override
                protected int sizeOf(String key, Bitmap value) {
                    return value.getByteCount() / 1024;
                }
            };

    private ImageLoader() {
    }

    /** oss 公共资源前缀（官方客户端同款映射，见 app.asar 的 oss:/// 处理）。 */
    public static final String OSS_PREFIX =
            "https://oss.ksai.scnet.cn:58003/scnet-public-resources";

    /**
     * 平台素材的地址归一：
     *   oss:///hpc/x/1.png → https://oss.ksai.scnet.cn:58003/scnet-public-resources/hpc/x/1.png
     *   /acx/...           → https://www.scnet.cn/acx/...
     *   //host/x           → https:​//host/x
     *   &amp;              → &
     */
    public static String normalize(String url) {
        if (url == null) {
            return "";
        }
        String out = url.trim().replace("&amp;", "&");
        if (out.startsWith("oss:///")) {
            String path = out.substring(6);
            if (path.contains("\\") || path.matches(".*[\\u0000-\\u0020].*")) {
                return "";
            }
            return OSS_PREFIX + (path.startsWith("/") ? path : "/" + path);
        }
        if (out.startsWith("oss://")) {
            String path = out.substring(6);
            int slash = path.indexOf('/');
            return slash > 0 ? "https://" + path.substring(0, slash)
                    + "/" + path.substring(slash + 1) : "";
        }
        if (out.startsWith("//")) {
            return "https:" + out;
        }
        if (out.startsWith("/")) {
            return "https://www.scnet.cn" + out;
        }
        return out;
    }

    public static void load(final String raw, final ImageView target, final int maxWidthPx) {
        final String url = normalize(raw);
        if (url.length() == 0 || target == null) {
            return;
        }
        if (!isSafeUrl(url)) {
            android.util.Log.w("SCNetDbg", "ImageLoader: unsafe url refused " + url);
            return;
        }
        if (url.startsWith("data:")) {
            Bitmap inline = decodeDataUri(url);
            if (inline != null) {
                target.setImageBitmap(inline);
            }
            return;
        }
        Bitmap hit = CACHE.get(url);
        if (hit != null) {
            target.setImageBitmap(hit);
            return;
        }
        target.setTag(url);
        POOL.execute(new Runnable() {
            @Override
            public void run() {
                Bitmap bitmap = fetch(url, maxWidthPx);
                if (bitmap == null) {
                    return;
                }
                CACHE.put(url, bitmap);
                MAIN.post(new Runnable() {
                    @Override
                    public void run() {
                        // 防止视图已被复用
                        if (url.equals(target.getTag())) {
                            target.setImageBitmap(bitmap);
                        }
                    }
                });
            }
        });
    }

    /**
     * 只允许 http(s) 与 data:image；拒绝 localhost / 内网 IP / 无点主机名
     * （与官方客户端 markdown 图片的地址校验一致，避免把内网地址渲染出来）。
     */
    public static boolean isSafeUrl(String url) {
        if (url == null || url.length() == 0) {
            return false;
        }
        if (url.startsWith("data:")) {
            return url.toLowerCase().startsWith("data:image/");
        }
        if (!url.startsWith("http://") && !url.startsWith("https://")) {
            return false;
        }
        try {
            String host = new java.net.URL(url).getHost();
            if (host == null) {
                return false;
            }
            String h = host.toLowerCase();
            if (h.equals("localhost") || h.endsWith(".localhost") || h.endsWith(".local")
                    || !h.contains(".") || h.startsWith("[")) {
                return false;
            }
            return !h.matches("^(?:127|10|0)\\.|^169\\.254\\.|^192\\.168\\."
                    + "|^172\\.(?:1[6-9]|2\\d|3[01])\\.");
        } catch (Throwable e) {
            return false;
        }
    }

    /** data:image/png;base64,xxxx */
    private static Bitmap decodeDataUri(String uri) {
        try {
            int comma = uri.indexOf(',');
            if (comma < 0) {
                return null;
            }
            byte[] bytes = android.util.Base64.decode(uri.substring(comma + 1),
                    android.util.Base64.DEFAULT);
            return BitmapFactory.decodeByteArray(bytes, 0, bytes.length);
        } catch (Throwable e) {
            return null;
        }
    }

    private static Bitmap fetch(String url, int maxWidthPx) {
        HttpURLConnection conn = null;
        try {
            conn = (HttpURLConnection) new URL(url).openConnection();
            conn.setConnectTimeout(12000);
            conn.setReadTimeout(30000);
            conn.setInstanceFollowRedirects(true);
            conn.setRequestProperty("Accept", "image/*");
            conn.setRequestProperty("User-Agent", "SCNetAgent-Android");
            // 平台 OSS / 站内图片要登录态，不带就 403（图裂开）
            String host = new URL(url).getHost();
            if (host != null && host.endsWith("scnet.cn")) {
                if (cn.scnet.agent.core.Http.token.length() > 0) {
                    conn.setRequestProperty("Token", cn.scnet.agent.core.Http.token);
                }
                if (cn.scnet.agent.core.Http.cookie.length() > 0) {
                    conn.setRequestProperty("Cookie", cn.scnet.agent.core.Http.cookie);
                }
            }
            int code = conn.getResponseCode();
            if (code < 200 || code >= 300) {
                return null;
            }
            InputStream in = conn.getInputStream();
            byte[] bytes = cn.scnet.agent.svc.Upload.readAll(in);
            in.close();
            BitmapFactory.Options options = new BitmapFactory.Options();
            options.inJustDecodeBounds = true;
            BitmapFactory.decodeByteArray(bytes, 0, bytes.length, options);
            int width = options.outWidth <= 0 ? maxWidthPx : options.outWidth;
            int sample = 1;
            while (width / sample > maxWidthPx * 2) {
                sample *= 2;
            }
            options.inJustDecodeBounds = false;
            options.inSampleSize = sample;
            return BitmapFactory.decodeByteArray(bytes, 0, bytes.length, options);
        } catch (Exception e) {
            return null;
        } finally {
            if (conn != null) {
                conn.disconnect();
            }
        }
    }
}
