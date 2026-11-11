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

import java.util.List;
import java.util.Stack;

import cn.scnet.agent.core.Crash;
import cn.scnet.agent.core.Store;
import cn.scnet.agent.svc.Hpc;
import cn.scnet.agent.core.Task;
import cn.scnet.agent.svc.Hpc;
import cn.scnet.agent.ui.Ui;
import cn.scnet.agent.ui.Widgets;

/** 集群文件浏览（对齐 ArkTS 的 pages/Files.ets，走 efile openapi）。 */
public class FilesActivity extends Activity {

    private Hpc.Context ctx;
    private LinearLayout content;
    private TextView pathView;
    private final Stack<String> back = new Stack<>();
    private String path = "";
    private String errorMsg = "";

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        Store.init(this);
        Crash.install(this);
        applyAppearance();
        buildUi();
        open("");
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
                if (!back.isEmpty()) {
                    String parent = back.pop();
                    open(parent);
                } else {
                    finish();
                }
            }
        }), new LinearLayout.LayoutParams(Ui.dpInt(this, 34), Ui.dpInt(this, 34)));
        LinearLayout titles = new LinearLayout(this);
        titles.setOrientation(LinearLayout.VERTICAL);
        titles.setPadding(Ui.dpInt(this, 10), 0, 0, 0);
        TextView title = Ui.label(this, Ui.t("集群文件", "Cluster files"), 15.5f, Ui.text);
        title.setTypeface(Typeface.DEFAULT_BOLD);
        titles.addView(title);
        pathView = Ui.label(this, "", 10.5f, Ui.textFaint);
        titles.addView(pathView);
        bar.addView(titles);
        root.addView(bar);

        ScrollView scroll = new ScrollView(this);
        content = new LinearLayout(this);
        content.setOrientation(LinearLayout.VERTICAL);
        content.setPadding(0, 0, 0, Ui.dpInt(this, 24));
        scroll.addView(content);
        root.addView(scroll, new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f));
        setContentView(root);
    }

    private void open(final String target) {
        content.removeAllViews();
        if (!Hpc.get().hasCredentials()) {
            LinearLayout card = Widgets.card(this);
            card.addView(Ui.label(this, Ui.t("未配置 AK/SK", "AK/SK not configured"), 14f,
                    Ui.text));
            TextView hint = Ui.label(this,
                    Ui.t("到「设置 → 算力服务」填 AccessKey / SecretKey（32 位十六进制）。",
                            "Go to Settings → Compute service to add AccessKey / SecretKey."),
                    12f, Ui.textFaint);
            hint.setPadding(0, Ui.dpInt(this, 6), 0, Ui.dpInt(this, 10));
            card.addView(hint);
            card.addView(Widgets.ghostButton(this, Ui.t("去设置", "Open settings"),
                    new Widgets.Action() {
                        @Override
                        public void run() {
                            startActivity(new Intent(FilesActivity.this, ProfileActivity.class));
                        }
                    }));
            addCard(card);
            card.addView(Widgets.ghostButton(this, Ui.t("重试", "Retry"), new Widgets.Action() {
                @Override
                public void run() {
                    open("");
                }
            }));
            pathView.setText("");
            return;
        }
        content.addView(Ui.label(this, Ui.t("加载中…", "Loading…"), 13f, Ui.textFaint));
        Task.run(new Task.Work<List<Hpc.Entry>>() {
            @Override
            public List<Hpc.Entry> run() throws Exception {
                if (ctx == null) {
                    ctx = Hpc.get().context(String.valueOf(Store.get().getClusterId()), false);
                }
                if (target.length() == 0) {
                    path = ctx.homePath.length() > 0 ? ctx.homePath : "/";
                } else {
                    path = target;
                }
                return Hpc.get().listDir(ctx, path);
            }
        }, new Task.Call<List<Hpc.Entry>>() {
            @Override
            public void ok(List<Hpc.Entry> value) {
                pathView.setText(path);
                render(value);
            }

            @Override
            public void fail(String message) {
                content.removeAllViews();
                LinearLayout card = Widgets.card(FilesActivity.this);
                card.setBackground(Ui.round(Ui.dangerSoft, 12, FilesActivity.this));
                card.addView(Ui.label(FilesActivity.this, message, 12.5f, Ui.danger));
                addCard(card);
            }
        });
    }

    private void render(List<Hpc.Entry> entries) {
        content.removeAllViews();
        if (entries.isEmpty()) {
            LinearLayout card = Widgets.card(this);
            card.addView(Ui.label(this, Ui.t("空目录", "Empty directory"), 12f, Ui.textFaint));
            addCard(card);
            return;
        }
        LinearLayout card = Widgets.card(this);
        card.setPadding(0, 0, 0, 0);
        for (final Hpc.Entry entry : entries) {
            LinearLayout line = new LinearLayout(this);
            line.setOrientation(LinearLayout.HORIZONTAL);
            line.setGravity(Gravity.CENTER_VERTICAL);
            line.setPadding(Ui.dpInt(this, 14), Ui.dpInt(this, 11), Ui.dpInt(this, 14),
                    Ui.dpInt(this, 11));
            line.addView(Ui.label(this, entry.name.endsWith("/") ? "📁 " : "📄 ", 13f, Ui.textSub));
            line.addView(Ui.label(this, entry.name, 13f, Ui.text), new LinearLayout.LayoutParams(0,
                    ViewGroup.LayoutParams.WRAP_CONTENT, 1f));
            line.addView(Ui.label(this, "›", 15f, Ui.textFaint));
            line.setOnClickListener(new View.OnClickListener() {
                @Override
                public void onClick(View v) {
                    if (entry.path.endsWith("/")) {
                        back.push(path);
                        open(entry.path);
                    } else {
                        readFile(entry.path);
                    }
                }
            });
            card.addView(line);
        }
        addCard(card);
    }

    private void readFile(final String filePath) {
        Task.run(new Task.Work<String>() {
            @Override
            public String run() throws Exception {
                return Hpc.get().readFile(ctx, filePath, false);
            }
        }, new Task.Call<String>() {
            @Override
            public void ok(String value) {
                ScrollView scroll = new ScrollView(FilesActivity.this);
                LinearLayout box = new LinearLayout(FilesActivity.this);
                box.setOrientation(LinearLayout.VERTICAL);
                box.setBackgroundColor(Ui.codeBg);
                box.setPadding(Ui.dpInt(FilesActivity.this, 12), Ui.dpInt(FilesActivity.this, 10),
                        Ui.dpInt(FilesActivity.this, 12), Ui.dpInt(FilesActivity.this, 10));
                TextView tv = Ui.label(FilesActivity.this,
                        value.length() > 0 ? value : Ui.t("（空文件）", "(empty)"),
                        11.5f, Ui.codeText);
                tv.setTypeface(Typeface.MONOSPACE);
                tv.setTextIsSelectable(true);
                box.addView(tv);
                scroll.addView(box);
                new android.app.AlertDialog.Builder(FilesActivity.this)
                        .setTitle(filePath)
                        .setView(scroll)
                        .setPositiveButton(Ui.t("关闭", "Close"), null)
                        .show();
            }

            @Override
            public void fail(String message) {
                Widgets.tip(FilesActivity.this, message);
            }
        });
    }

    private void addCard(View card) {
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        lp.leftMargin = Ui.dpInt(this, 14);
        lp.rightMargin = Ui.dpInt(this, 14);
        lp.topMargin = Ui.dpInt(this, 8);
        content.addView(card, lp);
    }

    @Override
    public void onBackPressed() {
        if (!back.isEmpty()) {
            open(back.pop());
            return;
        }
        super.onBackPressed();
    }
}
