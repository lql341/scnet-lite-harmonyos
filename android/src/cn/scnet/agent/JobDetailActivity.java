package cn.scnet.agent;

import android.app.Activity;
import android.graphics.Typeface;
import android.os.Bundle;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.HorizontalScrollView;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

import org.json.JSONObject;

import java.util.ArrayList;
import java.util.List;

import cn.scnet.agent.core.J;
import cn.scnet.agent.core.Crash;
import cn.scnet.agent.core.Store;
import cn.scnet.agent.core.Task;
import cn.scnet.agent.svc.Hpc;
import cn.scnet.agent.ui.Ui;
import cn.scnet.agent.ui.Widgets;

/** 作业详情 + 日志（对齐 ArkTS 的 pages/JobDetail.ets）。 */
public class JobDetailActivity extends Activity {

    private static class Field {
        final String label;
        final String key;

        Field(String label, String key) {
            this.label = label;
            this.key = key;
        }
    }

    private LinearLayout content;
    private Hpc.Context ctx;
    private String jobId = "";
    private String logPath = "";
    private String logText = "";
    private String errorMsg = "";
    private boolean logLoading;
    private boolean submitting;

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        Store.init(this);
        Crash.install(this);
        applyAppearance();
        jobId = getIntent() == null ? "" : getIntent().getStringExtra("jobId");
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
        TextView title = Ui.label(this, Ui.t("作业详情 #", "Job #") + jobId, 15.5f, Ui.text);
        title.setTypeface(Typeface.DEFAULT_BOLD);
        title.setPadding(Ui.dpInt(this, 10), 0, 0, 0);
        bar.addView(title, new LinearLayout.LayoutParams(0,
                ViewGroup.LayoutParams.WRAP_CONTENT, 1f));
        bar.addView(Widgets.ghostButton(this, Ui.t("取消作业", "Cancel"), new Widgets.Action() {
            @Override
            public void run() {
                Widgets.confirm(JobDetailActivity.this, Ui.t("取消作业", "Cancel job"),
                        Ui.t("确定取消这个作业吗？", "Cancel this job?"),
                        Ui.t("取消作业", "Cancel job"), new Widgets.Action() {
                            @Override
                            public void run() {
                                doCancel();
                            }
                        });
            }
        }));
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

    private void load() {
        content.removeAllViews();
        content.addView(Widgets.section(this, "…"));
        Task.run(new Task.Work<JSONObject>() {
            @Override
            public JSONObject run() throws Exception {
                ctx = Hpc.get().context(String.valueOf(Store.get().getClusterId()),
                        false);
                return Hpc.get().jobDetail(ctx, jobId);
            }
        }, new Task.Call<JSONObject>() {
            @Override
            public void ok(JSONObject value) {
                if (value == null) {
                    errorMsg = Ui.t("读不到作业详情（可能已结束，去列表里找）",
                            "No detail (job may have finished)");
                    render();
                    return;
                }
                renderDetail(value);
            }

            @Override
            public void fail(String message) {
                errorMsg = message;
                render();
            }
        });
    }

    private void render() {
        content.removeAllViews();
        if (errorMsg.length() > 0) {
            LinearLayout card = Widgets.card(this);
            card.setBackground(Ui.round(Ui.dangerSoft, 12, this));
            card.addView(Ui.label(this, errorMsg, 12.5f, Ui.danger));
            addCard(card);
        }
        if (logText.length() > 0 || logLoading || logPath.length() > 0) {
            renderLog();
        }
    }

    private void renderDetail(JSONObject detail) {
        content.removeAllViews();
        List<Field> fields = new ArrayList<>();
        fields.add(new Field(Ui.t("作业名", "Name"), "jobName"));
        fields.add(new Field(Ui.t("状态", "Status"), "jobStatus"));
        fields.add(new Field(Ui.t("队列", "Queue"), "queue"));
        fields.add(new Field(Ui.t("用户", "User"), "user"));
        fields.add(new Field(Ui.t("提交时间", "Submitted"), "jobSubmitTime"));
        fields.add(new Field(Ui.t("开始时间", "Started"), "jobStartTime"));
        fields.add(new Field(Ui.t("结束时间", "Ended"), "jobEndTime"));
        fields.add(new Field(Ui.t("退出码", "Exit code"), "exitCode"));
        fields.add(new Field(Ui.t("节点", "Nodes"), "nodeUsed"));
        fields.add(new Field(Ui.t("核数", "Cores"), "procNumUsed"));
        fields.add(new Field(Ui.t("GPU", "GPU"), "gpuNumUsed"));
        fields.add(new Field(Ui.t("DCU", "DCU"), "dcuNumUsed"));
        fields.add(new Field(Ui.t("工作目录", "Work dir"), "workDir"));
        fields.add(new Field(Ui.t("输出文件", "Output"), "outputPath"));

        LinearLayout card = Widgets.card(this);
        card.setPadding(0, 0, 0, 0);
        for (Field field : fields) {
            String value = J.str(detail, field.key);
            if (value.length() == 0 || "null".equals(value)) {
                continue;
            }
            LinearLayout line = new LinearLayout(this);
            line.setOrientation(LinearLayout.VERTICAL);
            line.setPadding(Ui.dpInt(this, 14), Ui.dpInt(this, 8), Ui.dpInt(this, 14),
                    Ui.dpInt(this, 8));
            line.addView(Ui.label(this, field.label, 11f, Ui.textFaint));
            line.addView(Ui.label(this, value, 13f, Ui.text));
            card.addView(line);
        }
        addCard(card);

        logPath = J.str(detail, "outputPath");
        if (logPath.length() == 0) {
            logPath = J.str(detail, "errorPath");
        }
        if (logPath.length() > 0) {
            renderLog();
            loadLog();
        }
    }

    private void renderLog() {
        // 移除旧日志卡（放在最后）
        if (content.getChildCount() > 0) {
            View last = content.getChildAt(content.getChildCount() - 1);
            if (last.getTag() != null && "log".equals(last.getTag())) {
                content.removeView(last);
            }
        }
        LinearLayout wrap = new LinearLayout(this);
        wrap.setTag("log");
        wrap.setOrientation(LinearLayout.VERTICAL);
        wrap.addView(Widgets.section(this, Ui.t("日志 · ", "Log · ") + logPath));

        HorizontalScrollView hsv = new HorizontalScrollView(this);
        LinearLayout box = new LinearLayout(this);
        box.setOrientation(LinearLayout.VERTICAL);
        box.setBackground(Ui.round(Ui.codeBg, 12, this));
        box.setPadding(Ui.dpInt(this, 12), Ui.dpInt(this, 10), Ui.dpInt(this, 12),
                Ui.dpInt(this, 10));
        TextView log = Ui.label(this, logLoading ? Ui.t("读取中…", "Loading…")
                : (logText.length() > 0 ? logText : Ui.t("（日志为空）", "(empty log)")),
                11.5f, Ui.codeText);
        log.setTypeface(Typeface.MONOSPACE);
        log.setTextIsSelectable(true);
        box.addView(log);
        hsv.addView(box);
        wrap.addView(hsv);
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        lp.leftMargin = Ui.dpInt(this, 14);
        lp.rightMargin = Ui.dpInt(this, 14);
        content.addView(wrap, lp);
    }

    private void loadLog() {
        if (ctx == null || logPath.length() == 0) {
            return;
        }
        logLoading = true;
        renderLog();
        final String path = logPath;
        Task.run(new Task.Work<String>() {
            @Override
            public String run() throws Exception {
                return Hpc.get().readFile(ctx, path, true);
            }
        }, new Task.Call<String>() {
            @Override
            public void ok(String value) {
                logLoading = false;
                logText = value == null ? "" : value;
                renderLog();
            }

            @Override
            public void fail(String message) {
                logLoading = false;
                logText = Ui.t("读取日志失败：", "Failed to read log: ") + message;
                renderLog();
            }
        });
    }

    private void doCancel() {
        if (ctx == null || submitting) {
            return;
        }
        submitting = true;
        Task.run(new Task.Work<Void>() {
            @Override
            public Void run() throws Exception {
                Hpc.get().cancel(ctx, jobId);
                return null;
            }
        }, new Task.Call<Void>() {
            @Override
            public void ok(Void value) {
                submitting = false;
                Widgets.tip(JobDetailActivity.this, Ui.t("已发送取消请求", "Cancel requested"));
                load();
            }

            @Override
            public void fail(String message) {
                submitting = false;
                Widgets.tip(JobDetailActivity.this, message);
            }
        });
    }

    private void addCard(View card) {
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        lp.leftMargin = Ui.dpInt(this, 14);
        lp.rightMargin = Ui.dpInt(this, 14);
        content.addView(card, lp);
    }
}
