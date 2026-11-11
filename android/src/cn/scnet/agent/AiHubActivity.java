package cn.scnet.agent;

import android.app.Activity;
import android.content.Intent;
import android.graphics.Typeface;
import android.os.Bundle;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

import java.util.ArrayList;
import java.util.List;

import cn.scnet.agent.core.Crash;
import cn.scnet.agent.core.Store;
import cn.scnet.agent.core.Task;
import cn.scnet.agent.svc.AiHub;
import cn.scnet.agent.ui.Ui;
import cn.scnet.agent.ui.Widgets;

/** AI 社区（AIHub 第三方智能体，对齐 ArkTS 的 pages/AiHubPage.ets，内嵌 Web 打开）。 */
public class AiHubActivity extends Activity {

    private LinearLayout list;
    private TextView statusView;
    private boolean loading;

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        Store.init(this);
        Crash.install(this);
        applyAppearance();
        buildUi();
        load();
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

    private void buildUi() {
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
        LinearLayout titles = new LinearLayout(this);
        titles.setOrientation(LinearLayout.VERTICAL);
        titles.setPadding(Ui.dpInt(this, 8), 0, 0, 0);
        TextView title = Ui.label(this, Ui.t("AI 社区", "AI community"), 17f, Ui.text);
        title.setTypeface(Typeface.DEFAULT_BOLD);
        titles.addView(title);
        titles.addView(Ui.label(this, Ui.t("第三方智能体，内嵌打开",
                "Third-party agents, opened inline"), 10f, Ui.textFaint));
        bar.addView(titles, new LinearLayout.LayoutParams(0,
                ViewGroup.LayoutParams.WRAP_CONTENT, 1f));
        TextView refresh = Ui.label(this, Ui.t("刷新", "Refresh"), 11.5f, Ui.accent);
        refresh.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                loading = false;
                load();
            }
        });
        bar.addView(refresh);
        root.addView(bar);

        statusView = Ui.label(this, "", 11.5f, Ui.textFaint);
        statusView.setPadding(Ui.dpInt(this, 16), Ui.dpInt(this, 4), Ui.dpInt(this, 16),
                Ui.dpInt(this, 4));
        root.addView(statusView);

        ScrollView scroll = new ScrollView(this);
        list = new LinearLayout(this);
        list.setOrientation(LinearLayout.VERTICAL);
        list.setPadding(0, 0, 0, Ui.dpInt(this, 24));
        scroll.addView(list);
        root.addView(scroll, new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f));
        setContentView(root);
    }

    private void load() {
        if (loading) {
            return;
        }
        loading = true;
        statusView.setText(Ui.t("加载中…", "Loading…"));
        Task.run(new Task.Work<List<AiHub.Agent>>() {
            @Override
            public List<AiHub.Agent> run() {
                return AiHub.get().selectedAgents();
            }
        }, new Task.Call<List<AiHub.Agent>>() {
            @Override
            public void ok(List<AiHub.Agent> value) {
                loading = false;
                render(value);
            }

            @Override
            public void fail(String message) {
                loading = false;
                statusView.setText(Ui.t("加载失败：", "Failed: ") + message);
            }
        });
    }

    private void render(List<AiHub.Agent> agents) {
        list.removeAllViews();
        statusView.setText(Ui.t("精选 " + agents.size() + " 个智能体",
                agents.size() + " featured agents"));
        for (final AiHub.Agent agent : agents) {
            LinearLayout card = Widgets.card(this);
            card.setPadding(Ui.dpInt(this, 12), Ui.dpInt(this, 12), Ui.dpInt(this, 12),
                    Ui.dpInt(this, 12));
            LinearLayout head = new LinearLayout(this);
            head.setOrientation(LinearLayout.HORIZONTAL);
            head.setGravity(Gravity.CENTER_VERTICAL);
            head.addView(Widgets.avatar(this, agent.name, "", 36, null));
            TextView name = Ui.label(this, agent.name, 13.5f, Ui.text);
            name.setTypeface(Typeface.DEFAULT_BOLD);
            name.setPadding(Ui.dpInt(this, 10), 0, Ui.dpInt(this, 8), 0);
            head.addView(name, new LinearLayout.LayoutParams(0,
                    ViewGroup.LayoutParams.WRAP_CONTENT, 1f));
            head.addView(Widgets.chip(this, AiHub.sourceLabel(agent.sourceType),
                    Ui.accent, Ui.accentGhost));
            card.addView(head);
            if (agent.desc.length() > 0) {
                TextView desc = Ui.label(this, agent.desc, 11.5f, Ui.textSub);
                desc.setMaxLines(3);
                desc.setEllipsize(android.text.TextUtils.TruncateAt.END);
                desc.setLineSpacing(Ui.dp(this, 2), 1f);
                desc.setPadding(0, Ui.dpInt(this, 8), 0, 0);
                card.addView(desc);
            }
            TextView open = Ui.label(this, Ui.t("打开 ›", "Open ›"), 10f, Ui.textFaint);
            open.setPadding(0, Ui.dpInt(this, 8), 0, 0);
            card.addView(open);
            card.setOnClickListener(new View.OnClickListener() {
                @Override
                public void onClick(View v) {
                    startActivity(new Intent(AiHubActivity.this, WebActivity.class)
                            .putExtra("url", AiHub.webUrl(agent))
                            .putExtra("title", agent.name));
                }
            });
            LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
            lp.leftMargin = Ui.dpInt(this, 14);
            lp.rightMargin = Ui.dpInt(this, 14);
            lp.topMargin = Ui.dpInt(this, 8);
            list.addView(card, lp);
        }
    }
}
