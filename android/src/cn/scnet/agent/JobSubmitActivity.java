package cn.scnet.agent;

import android.app.Activity;
import android.graphics.Typeface;
import android.os.Bundle;
import android.text.InputType;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.CheckBox;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

import java.util.ArrayList;
import java.util.List;

import cn.scnet.agent.core.Crash;
import cn.scnet.agent.core.Store;
import cn.scnet.agent.core.Task;
import cn.scnet.agent.svc.Hpc;
import cn.scnet.agent.ui.Sheet;
import cn.scnet.agent.ui.Ui;
import cn.scnet.agent.ui.Widgets;

/**
 * 提交作业（对齐 ArkTS 的 pages/JobSubmit.ets）：
 * 表单 → 校验 → 等价的 sbatch 预览 → **默认 dry-run**，勾选后才真提交（会真计费）。
 */
public class JobSubmitActivity extends Activity {

    private Hpc.Context ctx;
    private final List<String> queueNames = new ArrayList<>();
    private String queue = "";
    private String errorMsg = "";

    private EditText nameField;
    private TextView queueView;
    private EditText nodesField;
    private EditText cpusField;
    private EditText gpusField;
    private EditText dcusField;
    private EditText memField;
    private EditText wallField;
    private EditText workDirField;
    private EditText commandField;
    private CheckBox allowSubmit;
    private LinearLayout previewBox;
    private TextView statusView;

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        Store.init(this);
        Crash.install(this);
        applyAppearance();
        buildUi();
        loadContext();
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
        TextView title = Ui.label(this, Ui.t("提交作业", "Submit job"), 16f, Ui.text);
        title.setTypeface(Typeface.DEFAULT_BOLD);
        title.setPadding(Ui.dpInt(this, 10), 0, 0, 0);
        bar.addView(title);
        root.addView(bar);

        ScrollView scroll = new ScrollView(this);
        LinearLayout form = new LinearLayout(this);
        form.setOrientation(LinearLayout.VERTICAL);
        form.setPadding(0, 0, 0, Ui.dpInt(this, 30));
        scroll.addView(form);
        root.addView(scroll, new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f));

        statusView = Ui.label(this, Ui.t("读取集群上下文…", "Loading cluster context…"), 11.5f,
                Ui.textFaint);
        statusView.setPadding(Ui.dpInt(this, 16), Ui.dpInt(this, 4), Ui.dpInt(this, 16),
                Ui.dpInt(this, 8));
        form.addView(statusView);

        nameField = field(form, Ui.t("作业名", "Job name"), "scnet-job");
        queueView = fieldView(form, Ui.t("队列", "Queue"), Ui.t("点这里选择", "Tap to choose"),
                new Widgets.Action() {
                    @Override
                    public void run() {
                        pickQueue();
                    }
                });
        nodesField = field(form, Ui.t("节点数", "Nodes"), "1");
        cpusField = field(form, Ui.t("每节点核数", "Cores per node"), "1");
        gpusField = field(form, "GPU / 节点", "0");
        dcusField = field(form, "DCU / 节点", "0");
        memField = field(form, Ui.t("内存（如 8G，可空）", "Memory (e.g. 8G)"), "");
        wallField = field(form, Ui.t("运行时长 HH:MM:SS", "Walltime HH:MM:SS"), "00:30:00");
        workDirField = field(form, Ui.t("工作目录（绝对路径）", "Work dir (absolute)"), "/home");
        commandField = field(form, Ui.t("命令", "Command"), "hostname && date");

        LinearLayout note = Widgets.card(this);
        note.setBackground(Ui.round(Ui.accentGhost, 12, this));
        note.addView(Ui.label(this,
                Ui.t("默认只做 dry-run（校验 + 预览 sbatch），不会真提交；勾选下面的开关才会真提交，会占用配额并计费。",
                        "Default is dry run (validate + preview sbatch). Tick the switch below to really submit — that consumes quota and is billed."),
                11.5f, Ui.textSub));
        addCard(form, note);

        allowSubmit = new CheckBox(this);
        allowSubmit.setText(Ui.t("我确认真提交（计费）", "Really submit (billed)"));
        allowSubmit.setTextSize(Ui.sp(13f));
        allowSubmit.setTextColor(Ui.danger);
        allowSubmit.setPadding(Ui.dpInt(this, 14), Ui.dpInt(this, 6), 0, 0);
        form.addView(allowSubmit);

        LinearLayout actions = new LinearLayout(this);
        actions.setOrientation(LinearLayout.HORIZONTAL);
        actions.setPadding(Ui.dpInt(this, 14), Ui.dpInt(this, 8), Ui.dpInt(this, 14), 0);
        TextView preview = Widgets.ghostButton(this, Ui.t("预览 sbatch", "Preview"), new Widgets.Action() {
            @Override
            public void run() {
                renderPreview();
            }
        });
        actions.addView(preview, new LinearLayout.LayoutParams(0,
                ViewGroup.LayoutParams.WRAP_CONTENT, 1f));
        TextView submit = Widgets.primaryButton(this, Ui.t("提交", "Submit"), 44, new Widgets.Action() {
            @Override
            public void run() {
                doSubmit();
            }
        });
        LinearLayout.LayoutParams submitLp = new LinearLayout.LayoutParams(0,
                ViewGroup.LayoutParams.WRAP_CONTENT, 1f);
        submitLp.leftMargin = Ui.dpInt(this, 8);
        actions.addView(submit, submitLp);
        form.addView(actions);

        previewBox = new LinearLayout(this);
        previewBox.setOrientation(LinearLayout.VERTICAL);
        form.addView(previewBox);

        setContentView(root);
    }

    private EditText field(LinearLayout parent, String hint, String value) {
        LinearLayout box = new LinearLayout(this);
        box.setOrientation(LinearLayout.VERTICAL);
        box.setPadding(Ui.dpInt(this, 14), Ui.dpInt(this, 6), Ui.dpInt(this, 14), 0);
        box.addView(Ui.label(this, hint, 11f, Ui.textFaint));
        EditText et = new EditText(this);
        et.setText(value);
        et.setTextSize(Ui.sp(13.5f));
        et.setSingleLine(true);
        et.setBackground(Ui.roundStroke(Ui.surface, Ui.border, 10, this));
        et.setPadding(Ui.dpInt(this, 10), Ui.dpInt(this, 8), Ui.dpInt(this, 10),
                Ui.dpInt(this, 8));
        et.setInputType(hint.contains("核") || hint.contains("节点") || hint.contains("GPU")
                || hint.contains("DCU") || hint.contains("Cores") || hint.contains("Nodes")
                ? InputType.TYPE_CLASS_NUMBER : InputType.TYPE_CLASS_TEXT);
        box.addView(et);
        parent.addView(box);
        return et;
    }

    private TextView fieldView(LinearLayout parent, String hint, String value,
                               final Widgets.Action onTap) {
        LinearLayout box = new LinearLayout(this);
        box.setOrientation(LinearLayout.VERTICAL);
        box.setPadding(Ui.dpInt(this, 14), Ui.dpInt(this, 6), Ui.dpInt(this, 14), 0);
        box.addView(Ui.label(this, hint, 11f, Ui.textFaint));
        TextView tv = Ui.label(this, value, 13.5f, Ui.text);
        tv.setBackground(Ui.roundStroke(Ui.surface, Ui.border, 10, this));
        tv.setPadding(Ui.dpInt(this, 10), Ui.dpInt(this, 10), Ui.dpInt(this, 10),
                Ui.dpInt(this, 10));
        tv.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                onTap.run();
            }
        });
        box.addView(tv);
        parent.addView(box);
        return tv;
    }

    private void loadContext() {
        Task.run(new Task.Work<Void>() {
            @Override
            public Void run() throws Exception {
                ctx = Hpc.get().context(String.valueOf(Store.get().getClusterId()), false);
                List<Hpc.Queue> queues = Hpc.get().queues(ctx);
                queueNames.clear();
                for (Hpc.Queue q : queues) {
                    queueNames.add(q.name);
                }
                return null;
            }
        }, new Task.Call<Void>() {
            @Override
            public void ok(Void value) {
                statusView.setText(ctx.clusterName + " · " + ctx.userName
                        + (ctx.schedulerId.length() > 0 ? " · 调度器 " + ctx.schedulerId : ""));
                if (!queueNames.isEmpty()) {
                    queue = queueNames.get(0);
                    queueView.setText(queue);
                }
                if (ctx.homePath.length() > 0) {
                    workDirField.setText(ctx.homePath);
                }
            }

            @Override
            public void fail(String message) {
                statusView.setText(Ui.t("读取集群失败：", "Cluster failed: ") + message);
                errorMsg = message;
            }
        });
    }

    private void pickQueue() {
        if (queueNames.isEmpty()) {
            Widgets.tip(this, Ui.t("还没有队列信息", "No queues yet"));
            return;
        }
        Sheet.pick(this, Ui.t("选择队列", "Choose queue"),
                queueNames.toArray(new String[0]), new Sheet.OnPick() {
                    @Override
                    public void onPick(Sheet.Item item) {
                        queue = item.key;
                        queueView.setText(queue);
                    }
                });
    }

    private Hpc.Plan plan() {
        Hpc.Plan plan = new Hpc.Plan();
        plan.name = nameField.getText().toString().trim();
        plan.queue = queue;
        plan.nodes = parseInt(nodesField.getText().toString(), 1);
        plan.cpus = parseInt(cpusField.getText().toString(), 1);
        plan.gpus = parseInt(gpusField.getText().toString(), 0);
        plan.dcus = parseInt(dcusField.getText().toString(), 0);
        plan.memory = memField.getText().toString().trim();
        plan.walltime = wallField.getText().toString().trim();
        plan.workDir = workDirField.getText().toString().trim();
        plan.command = commandField.getText().toString();
        plan.exclusive = false;
        plan.allowSubmit = allowSubmit.isChecked();
        return plan;
    }

    private int parseInt(String text, int fallback) {
        try {
            return Integer.parseInt(text.trim());
        } catch (Exception e) {
            return fallback;
        }
    }

    private String stdout(Hpc.Plan plan) {
        String dir = plan.workDir.endsWith("/") ? plan.workDir.substring(0, plan.workDir.length() - 1)
                : plan.workDir;
        return dir + "/std.out.%j";
    }

    private String stderr(Hpc.Plan plan) {
        String dir = plan.workDir.endsWith("/") ? plan.workDir.substring(0, plan.workDir.length() - 1)
                : plan.workDir;
        return dir + "/std.err.%j";
    }

    private void renderPreview() {
        Hpc.Plan plan = plan();
        String error = Hpc.validate(plan, queueNames);
        previewBox.removeAllViews();
        if (error.length() > 0) {
            LinearLayout card = Widgets.card(this);
            card.setBackground(Ui.round(Ui.dangerSoft, 12, this));
            card.addView(Ui.label(this, error, 12.5f, Ui.danger));
            addCard(previewBox, card);
            return;
        }
        LinearLayout card = Widgets.card(this);
        card.setBackground(Ui.round(Ui.codeBg, 12, this));
        TextView code = Ui.label(this, Hpc.renderSbatch(plan, stdout(plan), stderr(plan)),
                11.5f, Ui.codeText);
        code.setTypeface(Typeface.MONOSPACE);
        code.setTextIsSelectable(true);
        card.addView(code);
        addCard(previewBox, card);
    }

    private void doSubmit() {
        final Hpc.Plan plan = plan();
        String error = Hpc.validate(plan, queueNames);
        if (error.length() > 0) {
            Widgets.tip(this, error);
            return;
        }
        if (ctx == null) {
            Widgets.tip(this, Ui.t("集群上下文还没准备好", "Cluster context not ready"));
            return;
        }
        if (!allowSubmit.isChecked()) {
            // dry-run：只预览，不提交
            renderPreview();
            Widgets.tip(this, Ui.t("dry-run：已生成 sbatch 预览，未提交",
                    "Dry run: sbatch preview only"));
            return;
        }
        Widgets.confirm(this, Ui.t("确认提交作业", "Confirm submit"),
                Ui.t("将真的提交到 " + plan.queue + "，占用 " + (plan.cpus * plan.nodes)
                        + " 核，按平台计费。确定吗？",
                        "This will really submit to " + plan.queue + " using "
                                + (plan.cpus * plan.nodes) + " cores and be billed."),
                Ui.t("提交", "Submit"), new Widgets.Action() {
                    @Override
                    public void run() {
                        submit(plan);
                    }
                });
    }

    private void submit(final Hpc.Plan plan) {
        statusView.setText(Ui.t("正在提交…", "Submitting…"));
        Task.run(new Task.Work<String>() {
            @Override
            public String run() throws Exception {
                return Hpc.get().submit(ctx, plan, stdout(plan), stderr(plan));
            }
        }, new Task.Call<String>() {
            @Override
            public void ok(String jobId) {
                statusView.setText(Ui.t("提交成功：#", "Submitted: #") + jobId);
                Widgets.tip(JobSubmitActivity.this, Ui.t("已提交 #", "Submitted #") + jobId);
                startActivity(new android.content.Intent(JobSubmitActivity.this,
                        JobDetailActivity.class).putExtra("jobId", jobId));
                finish();
            }

            @Override
            public void fail(String message) {
                statusView.setText(Ui.t("提交失败：", "Submit failed: ") + message);
                Widgets.tip(JobSubmitActivity.this, message);
            }
        });
    }

    private void addCard(LinearLayout parent, View card) {
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        lp.leftMargin = Ui.dpInt(this, 14);
        lp.rightMargin = Ui.dpInt(this, 14);
        lp.topMargin = Ui.dpInt(this, 8);
        parent.addView(card, lp);
    }
}
