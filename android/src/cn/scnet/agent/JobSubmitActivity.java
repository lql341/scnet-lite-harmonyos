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
    private final List<Hpc.Queue> queues = new ArrayList<>();
    private Hpc.Quota quota;
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
    private TextView sbatchView;
    private LinearLayout dangerCard;
    private TextView submitButton;
    private TextView statusView;
    private TextView subtitle;
    private LinearLayout queueChips;
    private TextView queueInfo;

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
        TextView title = Ui.label(this, Ui.t("提交作业", "Submit job"), 17f, Ui.text);
        title.setTypeface(Typeface.DEFAULT_BOLD);
        titles.addView(title);
        subtitle = Ui.label(this, "", 10.5f, Ui.textFaint);
        titles.addView(subtitle);
        bar.addView(titles, new LinearLayout.LayoutParams(0,
                ViewGroup.LayoutParams.WRAP_CONTENT, 1f));
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

        TextView queueLabel = Ui.label(this, Ui.t("队列", "Queue"), 10.5f, Ui.textFaint);
        queueLabel.setPadding(Ui.dpInt(this, 16), Ui.dpInt(this, 6), Ui.dpInt(this, 16), 0);
        form.addView(queueLabel);
        queueChips = new LinearLayout(this);
        queueChips.setOrientation(LinearLayout.HORIZONTAL);
        queueChips.setPadding(Ui.dpInt(this, 16), Ui.dpInt(this, 6), Ui.dpInt(this, 16), 0);
        form.addView(queueChips);
        queueInfo = Ui.label(this, "", 11f, Ui.textFaint);
        queueInfo.setPadding(Ui.dpInt(this, 16), Ui.dpInt(this, 8), Ui.dpInt(this, 16),
                Ui.dpInt(this, 4));
        form.addView(queueInfo);
        queueView = Ui.label(this, "", 1f, Ui.text);
        queueView.setVisibility(View.GONE);

        // 资源步进器（HAP：节点数 / 每节点核数 / DCU / GPU）
        nodesField = stepper(form, Ui.t("节点数", "Nodes"), "1", 1, 1, 64);
        cpusField = stepper(form, Ui.t("每节点核数", "Cores / node"), "1", 1, 1, 64);
        dcusField = stepper(form, "DCU", "0", 1, 0, 8);
        gpusField = stepper(form, "GPU", "0", 1, 0, 8);

        nameField = field(form, Ui.t("作业名", "Job name"), "scnet-lite-job");
        wallField = field(form, Ui.t("运行时长 HH:MM:SS", "Walltime HH:MM:SS"), "00:10:00");
        memField = field(form, Ui.t("内存", "Memory"), "4G");
        workDirField = field(form, Ui.t("工作目录（绝对路径）", "Work dir (absolute)"), "/public/home");
        commandField = field(form, Ui.t("命令", "Command"), "hostname && date");

        // 等价 sbatch（常驻，HAP 样式：深色卡片 + 等宽）
        TextView sbatchLabel = Ui.label(this, Ui.t("等价 sbatch", "Equivalent sbatch"), 10f,
                Ui.textFaint);
        sbatchLabel.setPadding(Ui.dpInt(this, 16), Ui.dpInt(this, 10), Ui.dpInt(this, 16), 0);
        form.addView(sbatchLabel);
        LinearLayout sbatchCard = new LinearLayout(this);
        sbatchCard.setOrientation(LinearLayout.VERTICAL);
        sbatchCard.setBackground(Ui.round(android.graphics.Color.parseColor("#111A26"), 12, this));
        sbatchCard.setPadding(Ui.dpInt(this, 12), Ui.dpInt(this, 10), Ui.dpInt(this, 12),
                Ui.dpInt(this, 12));
        sbatchView = Ui.label(this, "", 11f, android.graphics.Color.parseColor("#E6EDF3"));
        sbatchView.setTypeface(Typeface.MONOSPACE);
        sbatchView.setTextIsSelectable(true);
        sbatchCard.addView(sbatchView);
        LinearLayout.LayoutParams sbatchLp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        sbatchLp.leftMargin = Ui.dpInt(this, 14);
        sbatchLp.rightMargin = Ui.dpInt(this, 14);
        sbatchLp.topMargin = Ui.dpInt(this, 6);
        form.addView(sbatchCard, sbatchLp);

        // 危险开关（HAP：整卡 + 标题/副标题 + Switch，开启时红边）
        dangerCard = new LinearLayout(this);
        dangerCard.setOrientation(LinearLayout.HORIZONTAL);
        dangerCard.setGravity(Gravity.CENTER_VERTICAL);
        dangerCard.setPadding(Ui.dpInt(this, 14), Ui.dpInt(this, 12), Ui.dpInt(this, 14),
                Ui.dpInt(this, 12));
        LinearLayout dangerTexts = new LinearLayout(this);
        dangerTexts.setOrientation(LinearLayout.VERTICAL);
        dangerTexts.addView(Ui.label(this, Ui.t("允许真正提交", "Allow real submission"), 12f,
                Ui.danger));
        dangerTexts.addView(Ui.label(this, Ui.t(
                "提交会占用配额并计费；默认只做校验与脚本预览",
                "Submitting consumes quota and is billed; default is dry run"), 10f, Ui.textFaint));
        dangerCard.addView(dangerTexts, new LinearLayout.LayoutParams(0,
                ViewGroup.LayoutParams.WRAP_CONTENT, 1f));
        allowSubmit = new CheckBox(this);
        allowSubmit.setText("");
        allowSubmit.setOnCheckedChangeListener(new android.widget.CompoundButton
                .OnCheckedChangeListener() {
            @Override
            public void onCheckedChanged(android.widget.CompoundButton buttonView,
                                         boolean isChecked) {
                updateDangerStyle();
            }
        });
        dangerCard.addView(allowSubmit);
        LinearLayout.LayoutParams dangerLp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        dangerLp.leftMargin = Ui.dpInt(this, 14);
        dangerLp.rightMargin = Ui.dpInt(this, 14);
        dangerLp.topMargin = Ui.dpInt(this, 12);
        form.addView(dangerCard, dangerLp);

        // 单一提交按钮（HAP：未开真提交时是主色「校验并生成提交体」，开了变红「提交（真实）」）
        submitButton = new TextView(this);
        submitButton.setGravity(Gravity.CENTER);
        submitButton.setTextSize(Ui.sp(12.5f));
        submitButton.setTextColor(0xFFFFFFFF);
        submitButton.setTypeface(Typeface.DEFAULT_BOLD);
        submitButton.setPadding(0, Ui.dpInt(this, 12), 0, Ui.dpInt(this, 12));
        submitButton.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                doSubmit();
            }
        });
        LinearLayout.LayoutParams submitLp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        submitLp.leftMargin = Ui.dpInt(this, 14);
        submitLp.rightMargin = Ui.dpInt(this, 14);
        submitLp.topMargin = Ui.dpInt(this, 14);
        form.addView(submitButton, submitLp);

        TextView footer = Ui.label(this, Ui.t(
                "当前未接入日志/产物查看；提交后可在作业列表看到状态",
                "Logs/artifacts are not wired yet; the job list shows status"),
                10f, Ui.textFaint);
        footer.setGravity(Gravity.CENTER);
        footer.setPadding(0, Ui.dpInt(this, 8), 0, Ui.dpInt(this, 18));
        form.addView(footer);

        updateDangerStyle();

        previewBox = new LinearLayout(this);
        previewBox.setOrientation(LinearLayout.VERTICAL);

        setContentView(root);
        renderSbatchText();
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
        et.setBackground(Ui.round(Ui.surfaceAlt, 10, this));
        et.setPadding(Ui.dpInt(this, 10), Ui.dpInt(this, 8), Ui.dpInt(this, 10),
                Ui.dpInt(this, 8));
        et.setInputType(hint.contains("核") || hint.contains("节点") || hint.contains("GPU")
                || hint.contains("DCU") || hint.contains("Cores") || hint.contains("Nodes")
                ? InputType.TYPE_CLASS_NUMBER : InputType.TYPE_CLASS_TEXT);
        et.addTextChangedListener(new android.text.TextWatcher() {
            @Override
            public void beforeTextChanged(CharSequence s2, int st, int c, int a) {
            }

            @Override
            public void onTextChanged(CharSequence s2, int st, int b, int c) {
                renderSbatchText();
            }

            @Override
            public void afterTextChanged(android.text.Editable s2) {
            }
        });
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
                List<Hpc.Queue> list = Hpc.get().queues(ctx);
                queues.clear();
                queues.addAll(list);
                queueNames.clear();
                for (Hpc.Queue q : list) {
                    queueNames.add(q.name);
                }
                quota = Hpc.get().quota(ctx);
                return null;
            }
        }, new Task.Call<Void>() {
            @Override
            public void ok(Void value) {
                subtitle.setText(ctx.clusterName + " · " + ctx.userName);
                renderSbatchText();
                statusView.setVisibility(View.GONE);
                if (!queueNames.isEmpty() && queue.length() == 0) {
                    queue = queueNames.get(0);
                }
                renderQueueChips();
                renderSbatchText();
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

    /** 队列 chip（HAP：横向 chips + 下方「空闲 N 核 · 配额 M 核」）。 */
    private void renderQueueChips() {
        if (queueChips == null) {
            return;
        }
        queueChips.removeAllViews();
        for (final String name : queueNames) {
            boolean active = name.equals(queue);
            TextView chip = Widgets.chip(this, name, active ? 0xFFFFFFFF : Ui.textSub,
                    active ? Ui.accent : Ui.surface);
            chip.setPadding(Ui.dpInt(this, 14), Ui.dpInt(this, 7), Ui.dpInt(this, 14),
                    Ui.dpInt(this, 7));
            if (!active) {
                chip.setBackground(Ui.roundStroke(Ui.surface, Ui.border, 999, this));
            }
            LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT);
            lp.rightMargin = Ui.dpInt(this, 8);
            chip.setOnClickListener(new View.OnClickListener() {
                @Override
                public void onClick(View v) {
                    queue = name;
                    renderQueueChips();
                }
            });
            queueChips.addView(chip, lp);
        }
        if (queueInfo != null) {
            Hpc.Queue current = null;
            for (Hpc.Queue q : queues) {
                if (q.name.equals(queue)) {
                    current = q;
                    break;
                }
            }
            String info = "";
            if (current != null) {
                info = Ui.t("空闲 " + current.freeCpus + " 核", "free " + current.freeCpus)
                        + (quota == null ? "" : Ui.t(" · 配额 " + quota.accountMaxCpu + " 核",
                        " · quota " + quota.accountMaxCpu));
            }
            queueInfo.setText(info);
        }
    }

    /** HAP 的数字步进器：− 值 +，整行右侧。 */
    private EditText stepper(LinearLayout parent, String label, String value, int step,
                             int min, int max) {
        LinearLayout row = new LinearLayout(this);
        row.setOrientation(LinearLayout.HORIZONTAL);
        row.setGravity(Gravity.CENTER_VERTICAL);
        row.setPadding(Ui.dpInt(this, 16), Ui.dpInt(this, 8), Ui.dpInt(this, 16),
                Ui.dpInt(this, 8));

        TextView name = Ui.label(this, label, 14f, Ui.text);
        row.addView(name, new LinearLayout.LayoutParams(0,
                ViewGroup.LayoutParams.WRAP_CONTENT, 1f));

        LinearLayout box = new LinearLayout(this);
        box.setOrientation(LinearLayout.HORIZONTAL);
        box.setGravity(Gravity.CENTER_VERTICAL);
        box.setBackground(Ui.round(Ui.surfaceAlt, 10, this));
        box.setTag("stepperBox");

        final EditText input = new EditText(this);
        input.setText(value);
        input.setTextSize(Ui.sp(14f));
        input.setGravity(Gravity.CENTER);
        input.setBackgroundColor(0);
        input.setInputType(android.text.InputType.TYPE_CLASS_NUMBER);
        input.setSingleLine(true);
        input.setWidth(Ui.dpInt(this, 48));

        final int finalMin = min;
        final int finalMax = max;
        final int finalStep = step;
        TextView minus = Ui.label(this, "−", 18f, Ui.textSub);
        minus.setGravity(Gravity.CENTER);
        minus.setWidth(Ui.dpInt(this, 34));
        minus.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                int current = parseInt(input.getText().toString(), finalMin);
                input.setText(String.valueOf(Math.max(finalMin, current - finalStep)));
            }
        });
        TextView plus = Ui.label(this, "+", 18f, Ui.textSub);
        plus.setGravity(Gravity.CENTER);
        plus.setWidth(Ui.dpInt(this, 34));
        plus.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                int current = parseInt(input.getText().toString(), finalMin);
                input.setText(String.valueOf(Math.min(finalMax, current + finalStep)));
            }
        });
        input.addTextChangedListener(new android.text.TextWatcher() {
            @Override
            public void beforeTextChanged(CharSequence s2, int st, int c, int a) {
            }

            @Override
            public void onTextChanged(CharSequence s2, int st, int b, int c) {
                renderSbatchText();
            }

            @Override
            public void afterTextChanged(android.text.Editable s2) {
            }
        });
        box.addView(minus);
        box.addView(input);
        box.addView(plus);
        row.addView(box);

        parent.addView(row);
        // 每个步进器之间加细分隔线（HAP 卡片内分隔）
        View divider = new View(this);
        divider.setBackgroundColor(Ui.hairline);
        LinearLayout.LayoutParams dlp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, Ui.dpInt(this, 1));
        dlp.leftMargin = Ui.dpInt(this, 16);
        dlp.rightMargin = Ui.dpInt(this, 16);
        parent.addView(divider, dlp);
        return input;
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

    /** 开关状态决定：卡片描边色 + 提交按钮文案/配色（HAP 行为）。 */
    private void updateDangerStyle() {
        boolean real = allowSubmit != null && allowSubmit.isChecked();
        if (dangerCard != null) {
            dangerCard.setBackground(Ui.roundStroke(Ui.surface,
                    real ? Ui.danger : Ui.hairline, 12, this));
        }
        if (submitButton != null) {
            submitButton.setText(real ? Ui.t("提交（真实）", "Submit (real)")
                    : Ui.t("校验并生成提交体", "Validate & build"));
            submitButton.setBackground(Ui.round(real ? Ui.danger : Ui.accent, 12, this));
        }
        renderSbatchText();
    }

    /** sbatch 预览常驻（HAP：随字段变化实时刷新）。 */
    private void renderSbatchText() {
        if (sbatchView == null) {
            return;
        }
        Hpc.Plan plan = plan();
        sbatchView.setText(Hpc.renderSbatch(plan, stdout(plan), stderr(plan)));
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
            renderSbatchText();
            Widgets.tip(this, Ui.t("校验通过，已生成提交体（未提交）",
                    "Validated; submission body ready (not submitted)"));
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
