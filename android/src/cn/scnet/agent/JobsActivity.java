package cn.scnet.agent;

import android.app.Activity;
import android.content.Intent;
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

/**
 * 作业页（对齐 ArkTS 的 pages/Jobs.ets）：
 * 集群切换 → 队列空闲核数 → 配额 → 作业列表（详情 / 取消 / 提交）。
 */
public class JobsActivity extends Activity {

    private static class Row {
        String id = "";
        String name = "";
        String status = "";
        String queue = "";
        String nodes = "";
        String cpus = "";
    }

    private LinearLayout root;
    private LinearLayout content;
    private Hpc.Context ctx;
    private List<Hpc.Region> regions = new ArrayList<>();
    private List<Hpc.Queue> queues = new ArrayList<>();
    private List<Row> jobs = new ArrayList<>();
    private Hpc.Quota quota;
    private String clusterId = "";
    private String errorMsg = "";
    private String highlightId = "";
    private boolean jobsUnavailable;
    private TextView clusterLabel;

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        Store.init(this);
        Crash.install(this);
        applyAppearance();
        clusterId = String.valueOf(Store.get().getClusterId());
        if (getIntent() != null) {
            highlightId = getIntent().getStringExtra("highlight");
        }
        buildUi();
        load();
    }

    private void applyAppearance() {
        String mode = Store.get().getColorMode();
        int night = getResources().getConfiguration().uiMode
                & android.content.res.Configuration.UI_MODE_NIGHT_MASK;
        boolean dark = "dark".equals(mode)
                || ("system".equals(mode)
                && night == android.content.res.Configuration.UI_MODE_NIGHT_YES);
        Ui.apply(Store.get().getTheme(), dark);
        int level = Store.get().getFontLevel();
        Ui.fontScale = level == 0 ? 0.9f : (level == 2 ? 1.15f : 1f);
        Ui.zh = !"en".equals(Store.get().getLang());
    }

    private void buildUi() {
        root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(Ui.bg);

        LinearLayout bar = new LinearLayout(this);
        bar.setOrientation(LinearLayout.HORIZONTAL);
        bar.setGravity(Gravity.CENTER_VERTICAL);
        bar.setPadding(Ui.dpInt(this, 10), Ui.dpInt(this, 8), Ui.dpInt(this, 10),
                Ui.dpInt(this, 4));
        bar.addView(Widgets.glyphButton(this, "‹", new Widgets.Action() {
            @Override
            public void run() {
                finish();
            }
        }), new LinearLayout.LayoutParams(Ui.dpInt(this, 34), Ui.dpInt(this, 34)));

        LinearLayout titles = new LinearLayout(this);
        titles.setOrientation(LinearLayout.VERTICAL);
        titles.setPadding(Ui.dpInt(this, 8), 0, 0, 0);
        TextView title = Ui.label(this, Ui.t("作业", "Jobs"), 17f, Ui.text);
        title.setTypeface(Typeface.DEFAULT_BOLD);
        titles.addView(title);
        clusterLabel = Ui.label(this, "", 10.5f, Ui.textFaint);
        titles.addView(clusterLabel);
        bar.addView(titles, new LinearLayout.LayoutParams(0,
                ViewGroup.LayoutParams.WRAP_CONTENT, 1f));

        TextView refresh = Ui.label(this, "↻", 16f, Ui.textSub);
        refresh.setPadding(Ui.dpInt(this, 6), 0, Ui.dpInt(this, 6), 0);
        refresh.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                load();
            }
        });
        bar.addView(refresh);

        TextView filesBtn = Ui.label(this, Ui.t("文件", "Files"), 13f, Ui.accent);
        filesBtn.setPadding(Ui.dpInt(this, 8), Ui.dpInt(this, 6), Ui.dpInt(this, 8),
                Ui.dpInt(this, 6));
        filesBtn.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                startActivity(new Intent(JobsActivity.this, FilesActivity.class));
            }
        });
        bar.addView(filesBtn);

        TextView submit = new TextView(this);
        submit.setText(Ui.t("提交", "Submit"));
        submit.setTextSize(Ui.sp(13f));
        submit.setTextColor(0xFFFFFFFF);
        submit.setTypeface(Typeface.DEFAULT_BOLD);
        submit.setGravity(Gravity.CENTER);
        submit.setBackground(Ui.round(Ui.accent, 999, this));
        submit.setPadding(Ui.dpInt(this, 12), Ui.dpInt(this, 6), Ui.dpInt(this, 12),
                Ui.dpInt(this, 6));
        submit.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                startActivity(new Intent(JobsActivity.this, JobSubmitActivity.class));
            }
        });
        LinearLayout.LayoutParams submitLp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        submitLp.leftMargin = Ui.dpInt(this, 6);
        bar.addView(submit, submitLp);

        TextView keys = Ui.label(this, Ui.t("算力密钥", "AK/SK"), 13f, Ui.accent);
        keys.setPadding(Ui.dpInt(this, 8), Ui.dpInt(this, 6), Ui.dpInt(this, 4),
                Ui.dpInt(this, 6));
        keys.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                startActivity(new Intent(JobsActivity.this, ProfileActivity.class));
            }
        });
        LinearLayout.LayoutParams keysLp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        keysLp.leftMargin = Ui.dpInt(this, 4);
        bar.addView(keys, keysLp);
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
        if (!Hpc.get().hasCredentials()) {
            renderNeedCreds();
            return;
        }
        content.addView(Ui.label(this, Ui.t("加载中…", "Loading…"), 13f, Ui.textFaint));
        Task.run(new Task.Work<Void>() {
            @Override
            public Void run() throws Exception {
                regions = Hpc.get().regions(false);
                List<Hpc.Region> usable = new ArrayList<>();
                for (Hpc.Region r : regions) {
                    if (!"0".equals(r.clusterId)) {
                        usable.add(r);
                    }
                }
                regions = usable;
                if (regions.isEmpty()) {
                    errorMsg = Ui.t("没有可用集群", "No regions available");
                    return null;
                }
                boolean found = false;
                for (Hpc.Region r : regions) {
                    if (r.clusterId.equals(clusterId)) {
                        found = true;
                    }
                }
                if (!found) {
                    clusterId = regions.get(0).clusterId;
                }
                ctx = Hpc.get().context(clusterId, false);
                queues = Hpc.get().queues(ctx);
                quota = Hpc.get().quota(ctx);
                jobsUnavailable = false;
                try {
                    jobs = mapJobs(Hpc.get().jobs(ctx, 20));
                } catch (Exception e) {
                    jobsUnavailable = true;
                    jobs = new ArrayList<>();
                }
                return null;
            }
        }, new Task.Call<Void>() {
            @Override
            public void ok(Void value) {
                render();
            }

            @Override
            public void fail(String message) {
                errorMsg = message;
                render();
            }
        });
    }

    private List<Row> mapJobs(List<JSONObject> raw) {
        List<Row> out = new ArrayList<>();
        for (JSONObject row : raw) {
            String id = J.str(row, "jobId");
            if (id.length() == 0) {
                id = J.str(row, "id");
            }
            if (id.length() == 0) {
                continue;
            }
            Row r = new Row();
            r.id = id;
            r.name = J.str(row, "jobName", J.str(row, "name"));
            r.status = J.str(row, "jobStatus");
            if (r.status.length() == 0) {
                r.status = J.str(row, "status");
            }
            r.queue = J.str(row, "queueName", J.str(row, "queue"));
            r.nodes = J.str(row, "nodes", J.str(row, "nodeNum"));
            r.cpus = J.str(row, "cpus", J.str(row, "cpuNum"));
            out.add(r);
        }
        return out;
    }

    private void render() {
        content.removeAllViews();
        if (errorMsg.length() > 0) {
            LinearLayout card = Widgets.card(this);
            card.setBackground(Ui.round(Ui.dangerSoft, 12, this));
            card.addView(Ui.label(this, errorMsg, 12.5f, Ui.danger));
            addWithMargins(card);
        }
        if (ctx == null) {
            return;
        }
        clusterLabel.setText(ctx.clusterName);

        // 集群 chips（HAP：浅底圆角，点一下切集群）
        LinearLayout chips = new LinearLayout(this);
        chips.setOrientation(LinearLayout.HORIZONTAL);
        chips.setPadding(Ui.dpInt(this, 14), Ui.dpInt(this, 4), Ui.dpInt(this, 14), 0);
        for (final Hpc.Region region : regions) {
            if (region.clusterId.equals(clusterId)) {
                continue;
            }
            TextView chip = Widgets.chip(this, region.clusterName, Ui.text, Ui.surface);
            chip.setBackground(Ui.roundStroke(Ui.surface, Ui.border, 999, this));
            chip.setPadding(Ui.dpInt(this, 14), Ui.dpInt(this, 8), Ui.dpInt(this, 14),
                    Ui.dpInt(this, 8));
            LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT);
            lp.rightMargin = Ui.dpInt(this, 8);
            chip.setOnClickListener(new View.OnClickListener() {
                @Override
                public void onClick(View v) {
                    clusterId = region.clusterId;
                    Store.get().setClusterId(Integer.parseInt(region.clusterId));
                    load();
                }
            });
            chips.addView(chip, lp);
        }
        HorizontalScrollView hsv = new HorizontalScrollView(this);
        hsv.setHorizontalScrollBarEnabled(false);
        hsv.addView(chips);
        content.addView(hsv);

        // 两张统计卡：空闲核 / 配额（HAP 布局）
        LinearLayout stats = new LinearLayout(this);
        stats.setOrientation(LinearLayout.HORIZONTAL);
        int freeTotal = 0;
        for (Hpc.Queue queue : queues) {
            try {
                freeTotal += Integer.parseInt(queue.freeCpus);
            } catch (Exception ignored) {
            }
        }
        stats.addView(statCard(Ui.t("空闲核", "Free cores"), String.valueOf(freeTotal),
                Ui.t("共 " + queues.size() + " 个队列", queues.size() + " queues")),
                weighted(context9(), 1f));
        String quotaValue = quota == null ? "-" : String.valueOf(quota.accountMaxCpu);
        String quotaSub = quota == null ? Ui.t("未获取", "n/a")
                : Ui.t("DCU " + quota.accountMaxDcu + " · Job " + quota.accountMaxJob,
                "DCU " + quota.accountMaxDcu + " · Job " + quota.accountMaxJob);
        stats.addView(statCard(Ui.t("配额", "Quota"), quotaValue, quotaSub),
                weighted(context9(), 1f, 8));
        addWithMargins(stats);

        // 队列
        content.addView(Widgets.section(this, Ui.t("队列", "Queues")));
        LinearLayout queueCard = Widgets.card(this);
        queueCard.setPadding(0, 0, 0, 0);
        if (queues.isEmpty()) {
            TextView empty = Ui.label(this, Ui.t("没有队列信息", "No queues"), 12f, Ui.textFaint);
            empty.setPadding(Ui.dpInt(this, 14), Ui.dpInt(this, 12), 0, Ui.dpInt(this, 12));
            queueCard.addView(empty);
        }
        for (int i = 0; i < queues.size(); i++) {
            Hpc.Queue queue = queues.get(i);
            LinearLayout line = new LinearLayout(this);
            line.setOrientation(LinearLayout.HORIZONTAL);
            line.setGravity(Gravity.CENTER_VERTICAL);
            line.setPadding(Ui.dpInt(this, 14), Ui.dpInt(this, 10), Ui.dpInt(this, 14),
                    Ui.dpInt(this, 10));

            LinearLayout left = new LinearLayout(this);
            left.setOrientation(LinearLayout.VERTICAL);
            left.addView(Ui.label(this, queue.name, 13.5f, Ui.text));
            String sub = queue.nodes.length() > 0
                    ? Ui.t(queue.nodes + " 节点 · 单节点最多 " + queue.maxPpn + " 核",
                    queue.nodes + " nodes · max " + queue.maxPpn + " cores/node")
                    : "";
            if (sub.length() > 0) {
                left.addView(Ui.label(this, sub, 10.5f, Ui.textFaint));
            }
            line.addView(left, new LinearLayout.LayoutParams(0,
                    ViewGroup.LayoutParams.WRAP_CONTENT, 1f));

            LinearLayout right = new LinearLayout(this);
            right.setOrientation(LinearLayout.VERTICAL);
            right.setGravity(Gravity.END);
            TextView free = Ui.label(this, queue.freeCpus, 17f, Ui.ok);
            free.setTypeface(Typeface.DEFAULT_BOLD);
            right.addView(free);
            right.addView(Ui.label(this, "/ " + queue.totalCpus, 10.5f, Ui.textFaint));
            line.addView(right);
            queueCard.addView(line);
            if (i < queues.size() - 1) {
                View divider = new View(this);
                divider.setBackgroundColor(Ui.hairline);
                LinearLayout.LayoutParams dlp = new LinearLayout.LayoutParams(
                        ViewGroup.LayoutParams.MATCH_PARENT, Ui.dpInt(this, 1));
                dlp.leftMargin = Ui.dpInt(this, 14);
                queueCard.addView(divider, dlp);
            }
        }
        addWithMargins(queueCard);

        // 运行中作业
        content.addView(Widgets.section(this, Ui.t("运行中作业", "Running jobs")));
        if (jobsUnavailable) {
            LinearLayout card = Widgets.card(this);
            card.addView(Ui.label(this, Ui.t("作业列表暂时取不到（平台偶发 internal_error），点刷新重试。",
                    "Job list unavailable (platform internal_error). Refresh to retry."),
                    12f, Ui.warn));
            addWithMargins(card);
        } else if (jobs.isEmpty()) {
            LinearLayout card = Widgets.card(this);
            TextView empty = Ui.label(this, Ui.t("当前没有运行中的作业", "No running jobs"),
                    13f, Ui.textSub);
            empty.setGravity(Gravity.CENTER);
            empty.setPadding(0, Ui.dpInt(this, 18), 0, Ui.dpInt(this, 18));
            card.addView(empty);
            addWithMargins(card);
        }
        for (final Row job : jobs) {
            LinearLayout card = Widgets.card(this);
            if (job.id.equals(highlightId)) {
                card.setBackground(Ui.roundStroke(Ui.accentGhost, Ui.accent, 12, this));
            }
            LinearLayout line = new LinearLayout(this);
            line.setOrientation(LinearLayout.HORIZONTAL);
            line.setGravity(Gravity.CENTER_VERTICAL);
            TextView name = Ui.label(this, job.name.length() > 0 ? job.name
                    : ("#" + job.id), 13.5f, Ui.text);
            name.setTypeface(Typeface.DEFAULT_BOLD);
            line.addView(name, new LinearLayout.LayoutParams(0,
                    ViewGroup.LayoutParams.WRAP_CONTENT, 1f));
            line.addView(Widgets.chip(this, statusText(job.status), statusColor(job.status),
                    Ui.alpha(statusColor(job.status), 0.14f)));
            card.addView(line);
            card.addView(Ui.label(this, "#" + job.id + " · " + job.queue
                    + (job.nodes.length() > 0 ? " · " + job.nodes + Ui.t(" 节点", " nodes") : "")
                    + (job.cpus.length() > 0 ? " · " + job.cpus + Ui.t(" 核", " cores") : ""),
                    11f, Ui.textFaint));
            card.setOnClickListener(new View.OnClickListener() {
                @Override
                public void onClick(View v) {
                    startActivity(new Intent(JobsActivity.this, JobDetailActivity.class)
                            .putExtra("jobId", job.id));
                }
            });
            card.setOnLongClickListener(new View.OnLongClickListener() {
                @Override
                public boolean onLongClick(View v) {
                    Widgets.confirm(JobsActivity.this, Ui.t("取消作业", "Cancel job"),
                            Ui.t("确定取消 #", "Cancel #") + job.id + "？",
                            Ui.t("取消作业", "Cancel job"), new Widgets.Action() {
                                @Override
                                public void run() {
                                    cancelJob(job.id);
                                }
                            });
                    return true;
                }
            });
            addWithMargins(card);
        }

        TextView hint = Ui.label(this, Ui.t(
                "提交作业：点右上「提交」进入表单（默认只做校验与脚本预览）",
                "Submit: tap Submit at top right (dry-run by default)"), 11f, Ui.textFaint);
        hint.setPadding(Ui.dpInt(this, 16), Ui.dpInt(this, 16), Ui.dpInt(this, 16), 0);
        content.addView(hint);
    }

    private float context9() {
        return 1f;
    }

    private LinearLayout.LayoutParams weighted(float unused, float weight) {
        return weighted(unused, weight, 0);
    }

    private LinearLayout.LayoutParams weighted(float unused, float weight, int leftMarginDp) {
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(0,
                ViewGroup.LayoutParams.WRAP_CONTENT, weight);
        if (leftMarginDp > 0) {
            lp.leftMargin = Ui.dpInt(this, leftMarginDp);
        }
        return lp;
    }

    /** HAP 的大数字统计卡。 */
    private LinearLayout statCard(String label, String value, String sub) {
        LinearLayout card = Widgets.card(this);
        TextView big = Ui.label(this, value, 26f, Ui.text);
        big.setTypeface(Typeface.DEFAULT_BOLD);
        card.addView(big);
        card.addView(Ui.label(this, label, 12f, Ui.textSub));
        card.addView(Ui.label(this, sub, 10.5f, Ui.textFaint));
        return card;
    }

    private void cancelJob(final String jobId) {
        Task.run(new Task.Work<Void>() {
            @Override
            public Void run() throws Exception {
                Hpc.get().cancel(ctx, jobId);
                return null;
            }
        }, new Task.Call<Void>() {
            @Override
            public void ok(Void value) {
                Widgets.tip(JobsActivity.this, Ui.t("已取消", "Cancelled"));
                load();
            }

            @Override
            public void fail(String message) {
                Widgets.tip(JobsActivity.this, message);
            }
        });
    }

    private void renderNeedCreds() {
        LinearLayout card = Widgets.card(this);
        card.addView(Ui.label(this, Ui.t("还没有配置 AK/SK", "AK/SK not configured"), 14f, Ui.text));
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
                        startActivity(new Intent(JobsActivity.this, ProfileActivity.class));
                    }
                }));
        addWithMargins(card);

        card.addView(Widgets.ghostButton(this, Ui.t("我去设置完了，重试", "Retry"),
                new Widgets.Action() {
                    @Override
                    public void run() {
                        load();
                    }
                }));
    }

    @Override
    protected void onResume() {
        super.onResume();
        if (Hpc.get().hasCredentials() && content != null
                && (ctx == null || content.getChildCount() <= 1)) {
            load();
        }
    }

    private void addWithMargins(View view) {
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        lp.leftMargin = Ui.dpInt(this, 14);
        lp.rightMargin = Ui.dpInt(this, 14);
        lp.topMargin = Ui.dpInt(this, 6);
        content.addView(view, lp);
    }

    private String statusText(String code) {
        if ("statR".equals(code)) {
            return Ui.t("运行中", "Running");
        }
        if ("statPD".equals(code) || "statP".equals(code) || "statQ".equals(code)) {
            return Ui.t("排队中", "Pending");
        }
        if ("statC".equals(code)) {
            return Ui.t("已完成", "Completed");
        }
        if ("statE".equals(code)) {
            return Ui.t("异常退出", "Failed");
        }
        if ("statCA".equals(code)) {
            return Ui.t("已取消", "Cancelled");
        }
        if ("statTO".equals(code)) {
            return Ui.t("超时", "Timeout");
        }
        if ("statOOM".equals(code)) {
            return Ui.t("内存超限", "OOM");
        }
        if ("statNF".equals(code)) {
            return Ui.t("节点失效", "Node failure");
        }
        return code;
    }

    private int statusColor(String code) {
        if ("statR".equals(code)) {
            return Ui.ok;
        }
        if ("statE".equals(code) || "statTO".equals(code) || "statOOM".equals(code)
                || "statNF".equals(code)) {
            return Ui.danger;
        }
        if ("statPD".equals(code) || "statP".equals(code) || "statQ".equals(code)) {
            return Ui.warn;
        }
        return Ui.textFaint;
    }
}
