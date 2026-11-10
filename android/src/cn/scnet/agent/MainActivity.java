package cn.scnet.agent;

import android.app.Activity;
import android.app.DownloadManager;
import android.content.Context;
import android.content.Intent;
import android.net.Uri;
import android.os.Bundle;
import android.os.Environment;
import android.view.KeyEvent;
import android.view.View;
import android.view.ViewGroup;
import android.webkit.CookieManager;
import android.webkit.DownloadListener;
import android.webkit.ValueCallback;
import android.webkit.WebChromeClient;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.ProgressBar;
import android.widget.FrameLayout;

/**
 * WebView 壳：加载平台自带移动适配的 Web 前端（/ui/chatbot）。
 *
 * 只做「壳该做的事」，业务全在 Web 端：
 *   1. JS / DOM storage / 三方 cookie —— 登录态要落在 cookie 里
 *   2. **登录态持久化**：onPause 时 CookieManager.flush()，否则杀进程后要重新登录
 *   3. **附件上传**：onShowFileChooser → 系统文件选择器（对应 Web 端的 ＋ / 上传按钮）
 *   4. **文件下载**：DownloadListener → DownloadManager（带 cookie，站点要求登录）
 *   5. 返回键回退 Web 历史；转屏保存状态；顶部 2px 进度条
 */
public class MainActivity extends Activity {

    private static final String ENTRY = "https://www.scnet.cn/ui/chatbot/index.html";
    /** 文件选择请求码（startActivityForResult 用，避免引入 androidx） */
    private static final int REQ_FILE = 1001;

    private WebView web;
    private ProgressBar bar;
    private ValueCallback<Uri[]> fileCallback;

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);

        FrameLayout root = new FrameLayout(this);
        web = new WebView(this);

        bar = new ProgressBar(this, null, android.R.attr.progressBarStyleHorizontal);
        bar.setMax(100);
        bar.setVisibility(View.GONE);
        FrameLayout.LayoutParams barLp =
                new FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 6);
        barLp.topMargin = 0;

        root.addView(web, new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT));
        root.addView(bar, barLp);
        setContentView(root);

        WebSettings s = web.getSettings();
        s.setJavaScriptEnabled(true);
        s.setDomStorageEnabled(true);
        s.setDatabaseEnabled(true);
        s.setLoadWithOverviewMode(true);
        s.setUseWideViewPort(true);
        s.setBuiltInZoomControls(false);
        s.setSupportMultipleWindows(false);
        s.setMediaPlaybackRequiresUserGesture(false);
        s.setMixedContentMode(WebSettings.MIXED_CONTENT_NEVER_ALLOW);
        s.setUserAgentString(s.getUserAgentString() + " SCNetAgent/0.2.0");

        CookieManager cm = CookieManager.getInstance();
        cm.setAcceptCookie(true);
        cm.setAcceptThirdPartyCookies(web, true);

        web.setWebViewClient(new Client());
        web.setWebChromeClient(new Chrome());
        web.setDownloadListener(new Downloader());

        if (state != null) {
            web.restoreState(state);
        } else {
            web.loadUrl(ENTRY);
        }
    }

    /**
     * 具名内部类只是风格：build-tools 34.0.0 那份 d8 对非静态内部类/匿名类会 NPE，
     * 35.0.0 起正常（scripts/build-apk.sh 现在取最新一版 build-tools）。
     */
    private static final class Client extends WebViewClient {
        @Override
        public boolean shouldOverrideUrlLoading(WebView view, String url) {
            // 站内/站外都留在 WebView：不接管 Intent，避免跳出应用
            view.loadUrl(url);
            return true;
        }
    }

    private final class Chrome extends WebChromeClient {
        @Override
        public void onProgressChanged(WebView view, int progress) {
            if (bar == null) {
                return;
            }
            bar.setProgress(progress);
            bar.setVisibility(progress >= 100 ? View.GONE : View.VISIBLE);
        }

        /** Web 端 <input type=file> 被点击时触发 —— 附件上传要靠它。 */
        @Override
        public boolean onShowFileChooser(WebView view, ValueCallback<Uri[]> callback,
                                        FileChooserParams params) {
            if (fileCallback != null) {
                fileCallback.onReceiveValue(null);
            }
            fileCallback = callback;
            Intent intent = new Intent(Intent.ACTION_GET_CONTENT);
            intent.addCategory(Intent.CATEGORY_OPENABLE);
            // 与 Web 端能识别的类型对齐（图片/PDF/Office/文本/压缩包）
            intent.setType("*/*");
            intent.putExtra(Intent.EXTRA_MIME_TYPES, new String[] {
                    "image/*", "application/pdf", "text/*",
                    "application/msword",
                    "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
                    "application/vnd.ms-excel",
                    "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
                    "application/vnd.ms-powerpoint",
                    "application/vnd.openxmlformats-officedocument.presentationml.presentation",
                    "application/zip"
            });
            intent.putExtra(Intent.EXTRA_ALLOW_MULTIPLE, params != null && params.getMode() == FileChooserParams.MODE_OPEN_MULTIPLE);
            try {
                startActivityForResult(Intent.createChooser(intent, "选择文件"), REQ_FILE);
                return true;
            } catch (Exception e) {
                fileCallback = null;
                return false;
            }
        }
    }

    /** 下载走系统 DownloadManager，并把 cookie 带过去（站点要求登录）。 */
    private final class Downloader implements DownloadListener {
        @Override
        public void onDownloadStart(String url, String userAgent, String contentDisposition,
                                    String mimeType, long contentLength) {
            try {
                String cookie = CookieManager.getInstance().getCookie(url);
                DownloadManager.Request req = new DownloadManager.Request(Uri.parse(url));
                req.setMimeType(mimeType);
                req.addRequestHeader("User-Agent", userAgent);
                if (cookie != null && !cookie.isEmpty()) {
                    req.addRequestHeader("Cookie", cookie);
                }
                req.setNotificationVisibility(
                        DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED);
                req.setDestinationInExternalPublicDir(
                        Environment.DIRECTORY_DOWNLOADS, fileNameOf(url, contentDisposition));
                DownloadManager dm = (DownloadManager) getSystemService(Context.DOWNLOAD_SERVICE);
                if (dm != null) {
                    dm.enqueue(req);
                } else {
                    startActivity(new Intent(Intent.ACTION_VIEW, Uri.parse(url)));
                }
            } catch (Exception e) {
                try {
                    startActivity(new Intent(Intent.ACTION_VIEW, Uri.parse(url)));
                } catch (Exception ignored) {
                    // 交给 Web 自己处理
                }
            }
        }
    }

    private static String fileNameOf(String url, String contentDisposition) {
        String name = "download";
        if (contentDisposition != null) {
            int i = contentDisposition.indexOf("filename=");
            if (i >= 0) {
                name = contentDisposition.substring(i + 9).replace("\"", "").trim();
            }
        }
        if ("download".equals(name) && url != null) {
            int slash = url.lastIndexOf('/');
            if (slash >= 0 && slash < url.length() - 1) {
                name = url.substring(slash + 1);
                int q = name.indexOf('?');
                if (q > 0) {
                    name = name.substring(0, q);
                }
            }
        }
        return name.isEmpty() ? "download" : name;
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        if (requestCode == REQ_FILE) {
            Uri[] results = null;
            if (resultCode == RESULT_OK && data != null) {
                if (data.getClipData() != null) {
                    int count = data.getClipData().getItemCount();
                    results = new Uri[count];
                    for (int i = 0; i < count; i++) {
                        results[i] = data.getClipData().getItemAt(i).getUri();
                    }
                } else if (data.getData() != null) {
                    results = new Uri[] { data.getData() };
                }
            }
            if (fileCallback != null) {
                fileCallback.onReceiveValue(results);
                fileCallback = null;
            }
            return;
        }
        super.onActivityResult(requestCode, resultCode, data);
    }

    @Override
    protected void onSaveInstanceState(Bundle out) {
        super.onSaveInstanceState(out);
        if (web != null) {
            web.saveState(out);
        }
    }

    @Override
    protected void onPause() {
        super.onPause();
        if (web != null) {
            web.onPause();
            // 关键：把 cookie 落盘，否则杀进程后要重新登录
            CookieManager.getInstance().flush();
        }
    }

    @Override
    protected void onResume() {
        super.onResume();
        if (web != null) {
            web.onResume();
        }
    }

    @Override
    public boolean onKeyDown(int keyCode, KeyEvent event) {
        if (keyCode == KeyEvent.KEYCODE_BACK && web != null && web.canGoBack()) {
            web.goBack();
            return true;
        }
        return super.onKeyDown(keyCode, event);
    }

    @Override
    protected void onDestroy() {
        if (web != null) {
            CookieManager.getInstance().flush();
            web.destroy();
            web = null;
        }
        super.onDestroy();
    }
}
