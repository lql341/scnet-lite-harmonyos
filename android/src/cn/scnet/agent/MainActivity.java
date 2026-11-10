package cn.scnet.agent;

import android.app.Activity;
import android.content.SharedPreferences;
import android.os.Bundle;
import android.webkit.CookieManager;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.webkit.WebChromeClient;
import android.view.KeyEvent;

/**
 * 最小 WebView 壳：加载平台自带移动适配的 Web 前端（/ui/chatbot）。
 *
 * 为什么是这个形态：平台已有移动 viewport 的 Web 端，Android 上重写整套 UI
 * 不划算（见 docs/APK-ASSESSMENT.md 路线 C）。这里只做四件事：
 *   1. 开 DOM storage / JS / 第三方 cookie（登录态要落 cookie）
 *   2. 允许混合内容里的需要项，禁明文 HTTP
 *   3. 返回键回退 Web 历史而不是退出
 *   4. 复用系统 WebView 的 cookie 持久化，登录一次之后不用重复登录
 */
public class MainActivity extends Activity {

    private static final String ENTRY = "https://www.scnet.cn/ui/chatbot/index.html";

    private WebView web;

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);

        web = new WebView(this);
        setContentView(web);

        WebSettings s = web.getSettings();
        s.setJavaScriptEnabled(true);
        s.setDomStorageEnabled(true);
        s.setDatabaseEnabled(true);
        s.setLoadWithOverviewMode(true);
        s.setUseWideViewPort(true);
        s.setBuiltInZoomControls(false);
        s.setMediaPlaybackRequiresUserGesture(false);
        s.setMixedContentMode(WebSettings.MIXED_CONTENT_NEVER_ALLOW);
        // 移动端 UA 里带 SCNetAgent，方便平台侧区分（可选）
        s.setUserAgentString(s.getUserAgentString() + " SCNetAgent/0.1.0");

        CookieManager cm = CookieManager.getInstance();
        cm.setAcceptCookie(true);
        cm.setAcceptThirdPartyCookies(web, true);

        web.setWebViewClient(new Client());

        web.setWebChromeClient(new WebChromeClient());

        if (state != null) {
            web.restoreState(state);
        } else {
            web.loadUrl(ENTRY);
        }
    }

    @Override
    protected void onSaveInstanceState(Bundle out) {
        super.onSaveInstanceState(out);
        web.saveState(out);
    }

    @Override
    public boolean onKeyDown(int keyCode, KeyEvent event) {
        if (keyCode == KeyEvent.KEYCODE_BACK && web != null && web.canGoBack()) {
            web.goBack();
            return true;
        }
        return super.onKeyDown(keyCode, event);
    }

    /** 具名内部类：d8 对匿名类偶发 NPE，用具名类规避。 */
    private static final class Client extends WebViewClient {
        @Override
        public boolean shouldOverrideUrlLoading(WebView view, String url) {
            // 站内链接留在 WebView，外链也留在 WebView（先不接管 Intent，保持最小实现）
            view.loadUrl(url);
            return true;
        }
    }

    @Override
    protected void onDestroy() {
        if (web != null) {
            web.destroy();
            web = null;
        }
        super.onDestroy();
    }
}
