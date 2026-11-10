package cn.scnet.agent;

import android.app.Activity;
import android.graphics.Typeface;
import android.os.Bundle;
import android.view.Gravity;
import android.view.KeyEvent;
import android.view.View;
import android.view.ViewGroup;
import android.webkit.CookieManager;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.LinearLayout;
import android.widget.TextView;

import cn.scnet.agent.core.Http;
import cn.scnet.agent.core.Store;
import cn.scnet.agent.ui.Ui;
import cn.scnet.agent.ui.Widgets;

/** 内嵌 Web（市场详情 / AI 社区智能体），带平台登录 cookie。 */
public class WebActivity extends Activity {

    private WebView web;
    private String url = "";

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        Store.init(this);
        applyAppearance();
        url = getIntent() == null ? "" : getIntent().getStringExtra("url");
        String title = getIntent() == null ? "" : getIntent().getStringExtra("title");

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(Ui.bg);

        LinearLayout bar = new LinearLayout(this);
        bar.setOrientation(LinearLayout.HORIZONTAL);
        bar.setGravity(Gravity.CENTER_VERTICAL);
        bar.setPadding(Ui.dpInt(this, 12), Ui.dpInt(this, 10), Ui.dpInt(this, 14),
                Ui.dpInt(this, 6));
        bar.addView(Widgets.glyphButton(this, "‹", new Widgets.Action() {
            @Override
            public void run() {
                finish();
            }
        }), new LinearLayout.LayoutParams(Ui.dpInt(this, 34), Ui.dpInt(this, 34)));
        TextView titleView = Ui.label(this, title == null || title.length() == 0
                ? "SCNet" : title, 15f, Ui.text);
        titleView.setTypeface(Typeface.DEFAULT_BOLD);
        titleView.setPadding(Ui.dpInt(this, 10), 0, 0, 0);
        titleView.setMaxLines(1);
        bar.addView(titleView, new LinearLayout.LayoutParams(0,
                ViewGroup.LayoutParams.WRAP_CONTENT, 1f));
        root.addView(bar);

        web = new WebView(this);
        WebSettings settings = web.getSettings();
        settings.setJavaScriptEnabled(true);
        settings.setDomStorageEnabled(true);
        settings.setLoadWithOverviewMode(true);
        settings.setUseWideViewPort(true);
        settings.setBuiltInZoomControls(false);
        settings.setMixedContentMode(WebSettings.MIXED_CONTENT_NEVER_ALLOW);
        settings.setUserAgentString(settings.getUserAgentString() + " SCNetAgent-Native/0.2.0");

        CookieManager cookies = CookieManager.getInstance();
        cookies.setAcceptCookie(true);
        cookies.setAcceptThirdPartyCookies(web, true);
        // 把平台登录 cookie 注入过去（详情页需要登录态）
        if (Http.cookie != null && Http.cookie.length() > 0) {
            for (String kv : Http.cookie.split(";")) {
                String item = kv.trim();
                if (item.length() > 0) {
                    cookies.setCookie("https://www.scnet.cn", item + "; path=/");
                }
            }
        }

        web.setWebViewClient(new WebViewClient());
        root.addView(web, new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f));
        setContentView(root);

        if (url != null && url.length() > 0) {
            web.loadUrl(url);
        }
    }

    private void applyAppearance() {
        String mode = Store.get().getColorMode();
        int night = getResources().getConfiguration().uiMode
                & android.content.res.Configuration.UI_MODE_NIGHT_MASK;
        boolean dark = "dark".equals(mode) || ("system".equals(mode)
                && night == android.content.res.Configuration.UI_MODE_NIGHT_YES);
        Ui.apply(Store.get().getTheme(), dark);
        int level = Store.get().getFontLevel();
        Ui.fontScale = level == 0 ? 0.9f : (level == 2 ? 1.15f : 1f);
        Ui.zh = !"en".equals(Store.get().getLang());
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
    protected void onPause() {
        super.onPause();
        if (web != null) {
            web.onPause();
            CookieManager.getInstance().flush();
        }
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
