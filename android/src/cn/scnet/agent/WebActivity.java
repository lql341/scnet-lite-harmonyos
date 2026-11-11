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
import cn.scnet.agent.core.Crash;
import cn.scnet.agent.core.Store;
import cn.scnet.agent.ui.Ui;
import cn.scnet.agent.ui.Widgets;

/** 内嵌 Web（市场详情 / AI 社区智能体），带平台登录 cookie。 */
public class WebActivity extends Activity {

    private WebView web;
    private String url = "";
    private android.widget.ProgressBar progress;

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        Store.init(this);
        Crash.install(this);
        applyAppearance();
        url = getIntent() == null ? "" : getIntent().getStringExtra("url");
        String title = getIntent() == null ? "" : getIntent().getStringExtra("title");

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(Ui.bg);

        LinearLayout bar = new LinearLayout(this);
        bar.setOrientation(LinearLayout.HORIZONTAL);
        bar.setGravity(Gravity.CENTER_VERTICAL);
        bar.setPadding(Ui.dpInt(this, 8), Ui.dpInt(this, 8), Ui.dpInt(this, 12),
                Ui.dpInt(this, 4));
        TextView back = Ui.label(this, "‹", 20f, Ui.textSub);
        back.setGravity(Gravity.CENTER);
        back.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                finish();
            }
        });
        bar.addView(back, new LinearLayout.LayoutParams(Ui.dpInt(this, 32),
                Ui.dpInt(this, 32)));

        LinearLayout titles = new LinearLayout(this);
        titles.setOrientation(LinearLayout.VERTICAL);
        titles.setPadding(Ui.dpInt(this, 6), 0, 0, 0);
        TextView titleView = Ui.label(this, title == null || title.length() == 0
                ? Ui.t("AI 社区", "AI community") : title, 15f, Ui.text);
        titleView.setTypeface(Typeface.DEFAULT_BOLD);
        titleView.setMaxLines(1);
        titles.addView(titleView);
        TextView hostView = Ui.label(this, hostOf(url), 10f, Ui.textFaint);
        hostView.setMaxLines(1);
        titles.addView(hostView);
        bar.addView(titles, new LinearLayout.LayoutParams(0,
                ViewGroup.LayoutParams.WRAP_CONTENT, 1f));

        final TextView reload = Ui.label(this, "⟳", 15f, Ui.textSub);
        reload.setPadding(Ui.dpInt(this, 8), 0, Ui.dpInt(this, 4), 0);
        reload.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                if (web != null) {
                    web.reload();
                }
            }
        });
        bar.addView(reload);
        root.addView(bar);

        progress = new android.widget.ProgressBar(this, null,
                android.R.attr.progressBarStyleHorizontal);
        progress.setMax(100);
        progress.setVisibility(View.GONE);
        root.addView(progress, new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, Ui.dpInt(this, 2)));

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
        web.setWebChromeClient(new android.webkit.WebChromeClient() {
            @Override
            public void onProgressChanged(WebView view, int newProgress) {
                if (progress == null) {
                    return;
                }
                progress.setProgress(newProgress);
                progress.setVisibility(newProgress > 0 && newProgress < 100
                        ? View.VISIBLE : View.GONE);
            }
        });
        root.addView(web, new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f));
        setContentView(root);

        if (url != null && url.length() > 0) {
            web.loadUrl(url);
        }
    }

    /** 从 URL 取 host 作副标题（HAP 同款）。 */
    private static String hostOf(String link) {
        try {
            String host = new java.net.URL(link).getHost();
            return host == null ? "" : host;
        } catch (Throwable e) {
            return "";
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
