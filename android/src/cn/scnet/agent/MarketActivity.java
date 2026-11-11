package cn.scnet.agent;

import android.app.Activity;
import android.content.Intent;
import android.graphics.Typeface;
import android.net.Uri;
import android.os.Bundle;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.EditText;
import android.widget.HorizontalScrollView;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

import java.util.ArrayList;
import java.util.List;

import cn.scnet.agent.core.Crash;
import cn.scnet.agent.core.Store;
import cn.scnet.agent.core.Task;
import cn.scnet.agent.svc.Market;
import cn.scnet.agent.ui.Sheet;
import cn.scnet.agent.ui.Ui;
import cn.scnet.agent.ui.Widgets;

/** 插件市场（连接器 MCP / 技能 Skills，对齐 ArkTS 的 pages/MarketPage.ets）。 */
public class MarketActivity extends Activity {

    private LinearLayout list;
    private TextView statusView;
    private EditText search;
    private String kind = "mcp";
    private String sort = Market.SORT_HOT;
    private String keyword = "";
    private boolean onlyFeatured;
    private int page = 1;
    private final java.util.List<Market.Item> loaded = new java.util.ArrayList<>();
    private int total;
    private Market.Result result;
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
        TextView title = Ui.label(this, Ui.t("插件", "Plugins"), 17f, Ui.text);
        title.setTypeface(Typeface.DEFAULT_BOLD);
        titles.addView(title);
        titles.addView(Ui.label(this, Ui.t("连接器与技能，来自 AI 社区",
                "Connectors and skills from AI community"), 10f, Ui.textFaint));
        bar.addView(titles);
        root.addView(bar);

        LinearLayout filters = new LinearLayout(this);
        filters.setOrientation(LinearLayout.HORIZONTAL);
        filters.setPadding(Ui.dpInt(this, 14), Ui.dpInt(this, 2), Ui.dpInt(this, 14), 0);
        String[] kinds = {Ui.t("连接器", "Connectors"), Ui.t("技能", "Skills")};
        for (int i = 0; i < kinds.length; i++) {
            final String value = i == 0 ? "mcp" : "skills";
            TextView chip = Widgets.chip(this, kinds[i], kind.equals(value) ? 0xFFFFFFFF : Ui.textSub,
                    kind.equals(value) ? Ui.accent : Ui.surface);
            LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT);
            lp.rightMargin = Ui.dpInt(this, 6);
            chip.setOnClickListener(new View.OnClickListener() {
                @Override
                public void onClick(View v) {
                    kind = value;
                    buildUi();
                    load();
                }
            });
            filters.addView(chip, lp);
        }
        TextView featuredChip = Widgets.chip(this, Ui.t("精选", "Featured"),
                onlyFeatured ? 0xFFFFFFFF : Ui.textSub,
                onlyFeatured ? Ui.accent : Ui.surface);
        LinearLayout.LayoutParams featuredLp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        featuredLp.rightMargin = Ui.dpInt(this, 6);
        featuredChip.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                onlyFeatured = !onlyFeatured;
                buildUi();
                load();
            }
        });
        filters.addView(featuredChip, featuredLp);

        TextView sortChip = Widgets.chip(this,
                sort.equals(Market.SORT_HOT) ? Ui.t("最热", "Hot")
                        : (sort.equals(Market.SORT_NEW) ? Ui.t("最新", "New")
                        : Ui.t("最多下载", "Downloads")),
                Ui.textSub, Ui.surface);
        sortChip.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                String[] options = {Ui.t("最热", "Hot"), Ui.t("最新", "New"),
                        Ui.t("最多下载", "Downloads")};
                Sheet.pick(MarketActivity.this, Ui.t("排序", "Sort"), options,
                        new Sheet.OnPick() {
                            @Override
                            public void onPick(Sheet.Item item) {
                                if (item.key.startsWith(Ui.t("最新", "New").substring(0, 1))) {
                                    sort = Market.SORT_NEW;
                                } else if (item.key.contains(Ui.t("下载", "Download"))) {
                                    sort = Market.SORT_DOWNLOAD;
                                } else {
                                    sort = Market.SORT_HOT;
                                }
                                buildUi();
                                load();
                            }
                        });
            }
        });
        filters.addView(sortChip);
        HorizontalScrollView filterScroll = new HorizontalScrollView(this);
        filterScroll.setHorizontalScrollBarEnabled(false);
        filterScroll.addView(filters);
        root.addView(filterScroll);

        search = new EditText(this);
        search.setHint(Ui.t("搜索插件…", "Search plugins…"));
        search.setTextSize(Ui.sp(13f));
        search.setSingleLine(true);
        search.setText(keyword);
        search.setBackground(Ui.roundStroke(Ui.surface, Ui.border, 10, this));
        search.setPadding(Ui.dpInt(this, 12), Ui.dpInt(this, 7), Ui.dpInt(this, 12),
                Ui.dpInt(this, 7));
        LinearLayout.LayoutParams searchLp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        searchLp.leftMargin = Ui.dpInt(this, 14);
        searchLp.rightMargin = Ui.dpInt(this, 14);
        searchLp.topMargin = Ui.dpInt(this, 8);
        root.addView(search, searchLp);
        search.setOnEditorActionListener(new TextView.OnEditorActionListener() {
            @Override
            public boolean onEditorAction(TextView v, int actionId, android.view.KeyEvent event) {
                keyword = search.getText().toString().trim();
                load();
                return true;
            }
        });

        statusView = Ui.label(this, "", 11.5f, Ui.textFaint);
        statusView.setPadding(Ui.dpInt(this, 16), Ui.dpInt(this, 6), Ui.dpInt(this, 16), 0);
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
        loaded.clear();
        page = 1;
        fetch(1, false);
    }

    private void fetch(final int pageToLoad, final boolean append) {
        if (loading) {
            return;
        }
        loading = true;
        statusView.setText(Ui.t("加载中…", "Loading…"));
        final String currentKind = kind;
        final String currentSort = sort;
        final String currentKeyword = keyword;
        Task.run(new Task.Work<Market.Result>() {
            @Override
            public Market.Result run() {
                return "skills".equals(currentKind)
                        ? Market.get().skills(currentKeyword, pageToLoad, currentSort)
                        : Market.get().connectors(currentKeyword, pageToLoad, currentSort);
            }
        }, new Task.Call<Market.Result>() {
            @Override
            public void ok(Market.Result value) {
                loading = false;
                result = value;
                total = value.total;
                page = pageToLoad;
                if (append) {
                    loaded.addAll(value.items);
                } else {
                    loaded.clear();
                    loaded.addAll(value.items);
                }
                render();
            }

            @Override
            public void fail(String message) {
                loading = false;
                statusView.setText(Ui.t("加载失败：", "Failed: ") + message);
            }
        });
    }

    private void render() {
        list.removeAllViews();
        if (result == null) {
            return;
        }
        statusView.setText(Ui.t("共 " + total + " 条", total + " items")
                + (onlyFeatured ? Ui.t(" · 只看精选", " · featured only") : "")
                + Ui.t(" · 已加载 " + loaded.size(), " · loaded " + loaded.size()));
        if (loaded.isEmpty()) {
            LinearLayout card = Widgets.card(this);
            card.addView(Ui.label(this, Ui.t("没有结果", "No results"), 12f, Ui.textFaint));
            addCard(card);
            return;
        }
        // HAP：精选（suggestType=1）/ 推荐（2）/ 社区 三段分组
        if (!onlyFeatured) {
            java.util.List<Market.Item> featured = new java.util.ArrayList<>();
            java.util.List<Market.Item> recommended = new java.util.ArrayList<>();
            java.util.List<Market.Item> community = new java.util.ArrayList<>();
            for (Market.Item item : loaded) {
                if ("1".equals(item.recommend)) {
                    featured.add(item);
                } else if ("2".equals(item.recommend)) {
                    recommended.add(item);
                } else {
                    community.add(item);
                }
            }
            if (!featured.isEmpty()) {
                list.addView(sectionLabel(Ui.t("精选", "Featured")));
                for (Market.Item item : featured) {
                    addItem(item);
                }
            }
            if (!recommended.isEmpty()) {
                list.addView(sectionLabel(Ui.t("推荐", "Recommended")));
                for (Market.Item item : recommended) {
                    addItem(item);
                }
            }
            if (!community.isEmpty()) {
                if (!featured.isEmpty() || !recommended.isEmpty()) {
                    list.addView(sectionLabel(Ui.t("社区", "Community")));
                }
                for (Market.Item item : community) {
                    addItem(item);
                }
            }
            if (loaded.size() < total) {
                TextView more = Widgets.ghostButton(this, Ui.t("加载更多", "Load more"),
                        new Widgets.Action() {
                            @Override
                            public void run() {
                                fetch(page + 1, true);
                            }
                        });
                addCard(more);
            }
            return;
        }

        int shown = 0;
        for (final Market.Item item : loaded) {
            if (onlyFeatured && !"1".equals(item.recommend)) {
                continue;
            }
            shown++;
            LinearLayout card = Widgets.card(this);
            LinearLayout head = new LinearLayout(this);
            head.setOrientation(LinearLayout.HORIZONTAL);
            head.setGravity(Gravity.CENTER_VERTICAL);
            TextView name = Ui.label(this, item.name, 14f, Ui.text);
            name.setTypeface(Typeface.DEFAULT_BOLD);
            head.addView(name, new LinearLayout.LayoutParams(0,
                    ViewGroup.LayoutParams.WRAP_CONTENT, 1f));
            if ("1".equals(item.recommend)) {
                head.addView(Widgets.chip(this, Ui.t("精选", "Featured"), Ui.accent,
                        Ui.accentSoft));
            }
            card.addView(head);
            if (item.desc.length() > 0) {
                TextView desc = Ui.label(this, item.desc, 12f, Ui.textSub);
                desc.setMaxLines(3);
                desc.setPadding(0, Ui.dpInt(this, 4), 0, 0);
                card.addView(desc);
            }
            String meta = item.author.length() > 0 ? item.author : item.owner;
            meta += " · 浏览 " + item.browseCount + " · 下载 " + item.downloadCount;
            if (item.category.length() > 0) {
                meta += " · " + item.category;
            }
            card.addView(Ui.label(this, meta, 10.5f, Ui.textFaint));
            card.setOnClickListener(new View.OnClickListener() {
                @Override
                public void onClick(View v) {
                    startActivity(new Intent(MarketActivity.this, WebActivity.class)
                            .putExtra("url", item.detailUrl)
                            .putExtra("title", item.name));
                }
            });
            addCard(card);
        }
        if (shown == 0) {
            LinearLayout empty = Widgets.card(this);
            empty.addView(Ui.label(this, Ui.t("没有结果", "No results"), 12f, Ui.textFaint));
            addCard(empty);
            return;
        }
        if (loaded.size() < total) {
            TextView more = Widgets.ghostButton(this, Ui.t("加载更多", "Load more"),
                    new Widgets.Action() {
                        @Override
                        public void run() {
                            fetch(page + 1, true);
                        }
                    });
            addCard(more);
        }
    }

    private TextView sectionLabel(String text) {
        TextView tv = Ui.label(this, text, 10.5f, Ui.textFaint);
        tv.setPadding(Ui.dpInt(this, 2), Ui.dpInt(this, 10), 0, Ui.dpInt(this, 2));
        return tv;
    }

    /** HAP 的插件卡片：名称 + 精选徽标 / 描述 / 作者·浏览·下载·分类。 */
    private void addItem(final Market.Item item) {
        LinearLayout card = Widgets.card(this);
        LinearLayout head = new LinearLayout(this);
        head.setOrientation(LinearLayout.HORIZONTAL);
        head.setGravity(Gravity.CENTER_VERTICAL);
        TextView name = Ui.label(this, item.name, 14f, Ui.text);
        name.setTypeface(android.graphics.Typeface.DEFAULT_BOLD);
        head.addView(name, new LinearLayout.LayoutParams(0,
                ViewGroup.LayoutParams.WRAP_CONTENT, 1f));
        if ("1".equals(item.recommend)) {
            head.addView(Widgets.chip(this, Ui.t("精选", "Featured"), Ui.accent, Ui.accentSoft));
        }
        card.addView(head);
        if (item.desc.length() > 0) {
            TextView desc = Ui.label(this, item.desc, 12f, Ui.textSub);
            desc.setMaxLines(3);
            desc.setEllipsize(android.text.TextUtils.TruncateAt.END);
            desc.setPadding(0, Ui.dpInt(this, 4), 0, 0);
            card.addView(desc);
        }
        String meta = item.author.length() > 0 ? item.author : item.owner;
        meta += Ui.t(" · 浏览 " + item.browseCount + " · 下载 " + item.downloadCount,
                " · " + item.browseCount + " views · " + item.downloadCount + " downloads");
        if (item.category.length() > 0) {
            meta += " · " + item.category;
        }
        card.addView(Ui.label(this, meta, 10.5f, Ui.textFaint));
        card.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                startActivity(new Intent(MarketActivity.this, WebActivity.class)
                        .putExtra("url", item.detailUrl)
                        .putExtra("title", item.name));
            }
        });
        addCard(card);
    }

    private void addCard(View card) {
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        lp.leftMargin = Ui.dpInt(this, 14);
        lp.rightMargin = Ui.dpInt(this, 14);
        lp.topMargin = Ui.dpInt(this, 8);
        list.addView(card, lp);
    }
}
