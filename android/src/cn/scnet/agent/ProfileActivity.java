package cn.scnet.agent;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.Intent;
import android.graphics.Typeface;
import android.net.Uri;
import android.os.Bundle;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.EditText;
import android.widget.FrameLayout;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.util.ArrayList;
import java.util.List;

import cn.scnet.agent.core.Crash;
import cn.scnet.agent.core.Store;
import cn.scnet.agent.core.Task;
import cn.scnet.agent.svc.Auth;
import cn.scnet.agent.svc.Hpc;
import cn.scnet.agent.svc.Upload;
import cn.scnet.agent.ui.Sheet;
import cn.scnet.agent.ui.Ui;
import cn.scnet.agent.ui.Widgets;

/**
 * 设置页（对齐 ArkTS 的 pages/Profile.ets）：外观 / 通道 / 算力 / 关于。
 */
public class ProfileActivity extends Activity {

    private static final String[] PRESET_AVATARS = {"🐼", "🦊", "🐳", "🦉", "🐙", "🌵",
            "🌇", "🌊", "🏔", "🌌", "A", "S"};

    private LinearLayout root;
    private TextView versionView;
    private TextView accountValue;
    private TextView clusterValue;
    private TextView schedulerValue;
    private TextView channelValue;
    private TextView routeValue;
    private TextView userValue;

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        Store.init(this);
        Crash.install(this);
        applyAppearance();
        buildUi();
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

    private void rebuild() {
        applyAppearance();
        buildUi();
    }

    private void buildUi() {
        ScrollView scroll = new ScrollView(this);
        scroll.setBackgroundColor(Ui.bg);
        root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(0, 0, 0, Ui.dpInt(this, 28));
        scroll.addView(root);

        // 顶栏：‹ + 设置（HAP 只有标题，没有副标题）
        LinearLayout bar = new LinearLayout(this);
        bar.setOrientation(LinearLayout.HORIZONTAL);
        bar.setGravity(Gravity.CENTER_VERTICAL);
        bar.setPadding(Ui.dpInt(this, 8), Ui.dpInt(this, 8), Ui.dpInt(this, 14),
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
        TextView title = Ui.label(this, Ui.t("设置", "Settings"), 17f, Ui.text);
        title.setTypeface(Typeface.DEFAULT_BOLD);
        title.setPadding(Ui.dpInt(this, 8), 0, 0, 0);
        bar.addView(title, new LinearLayout.LayoutParams(0,
                ViewGroup.LayoutParams.WRAP_CONTENT, 1f));
        root.addView(bar);

        // 头像卡（HAP：72 头像 + 姓名 20px + 「已登录 · 超算互联网」）
        LinearLayout avatarCard = new LinearLayout(this);
        avatarCard.setOrientation(LinearLayout.VERTICAL);
        avatarCard.setGravity(Gravity.CENTER_HORIZONTAL);
        avatarCard.setPadding(0, Ui.dpInt(this, 12), 0, Ui.dpInt(this, 6));
        avatarCard.addView(Widgets.avatar(this, Store.get().getPlatformUserName(),
                Store.get().getAvatar(), 72, new Widgets.Action() {
                    @Override
                    public void run() {
                        pickAvatar();
                    }
                }));
        String name = Store.get().getPlatformUserName();
        TextView nameView = Ui.label(this, name.length() > 0 ? name
                : Ui.t("未命名用户", "Unnamed"), 20f, Ui.text);
        nameView.setGravity(Gravity.CENTER);
        nameView.setWidth(ViewGroup.LayoutParams.MATCH_PARENT);
        nameView.setPadding(0, Ui.dpInt(this, 10), 0, 0);
        avatarCard.addView(nameView, new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));
        TextView signedIn = Ui.label(this, Ui.t("已登录 · 超算互联网", "Signed in · SCNet"),
                10.5f, Ui.textFaint);
        signedIn.setGravity(Gravity.CENTER);
        avatarCard.addView(signedIn, new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));
        LinearLayout.LayoutParams avatarLp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        root.addView(avatarCard, avatarLp);

        // 信息卡（HAP 5 行：账号 / 集群账号 / 集群 / 当前通道 / 集群调度器）
        LinearLayout infoCard = Widgets.card(this);
        infoCard.setPadding(Ui.dpInt(this, 14), 0, Ui.dpInt(this, 14), 0);
        accountValue = Ui.label(this, "—", 12f, Ui.text);
        clusterValue = Ui.label(this, "—", 12f, Ui.text);
        schedulerValue = Ui.label(this, "—", 12f, Ui.text);
        userValue = Ui.label(this, "—", 12f, Ui.text);
        infoCard.addView(infoRow(Ui.t("账号", "Account"), userValue, null));
        infoCard.addView(divider());
        infoCard.addView(infoRow(Ui.t("集群账号", "Cluster acct"), clusterValue, null));
        infoCard.addView(divider());
        channelValue = Ui.label(this, "—", 12f, Ui.text);
        infoCard.addView(infoRow(Ui.t("集群", "Cluster"), channelValue, new Widgets.Action() {
            @Override
            public void run() {
                pickCluster();
            }
        }));
        infoCard.addView(divider());
        routeValue = Ui.label(this, "—", 12f, Ui.text);
        infoCard.addView(infoRow(Ui.t("当前通道", "Channel"), routeValue, null));
        infoCard.addView(divider());
        infoCard.addView(infoRow(Ui.t("集群调度器", "Scheduler"), schedulerValue, null));
        addCard(infoCard);
        loadIdentity();

        // 自定义模型（HAP：单行 → 面板）
        LinearLayout customRow = Widgets.card(this);
        customRow.setPadding(0, 0, 0, 0);
        customRow.addView(Widgets.row(this, Ui.t("自定义模型", "Custom model"),
                customLabel(), "", new Widgets.Action() {
                    @Override
                    public void run() {
                        editCustomProvider();
                    }
                }));
        addCard(customRow);

        // 外观：深色模式分段（HAP：跟随 / 浅色 / 深色 三个 chip）
        LinearLayout lookCard = Widgets.card(this);
        lookCard.setPadding(0, 0, 0, 0);
        LinearLayout modeRow = new LinearLayout(this);
        modeRow.setOrientation(LinearLayout.HORIZONTAL);
        modeRow.setGravity(Gravity.CENTER_VERTICAL);
        modeRow.setPadding(Ui.dpInt(this, 14), Ui.dpInt(this, 12), Ui.dpInt(this, 12),
                Ui.dpInt(this, 12));
        modeRow.addView(Ui.label(this, Ui.t("外观", "Appearance"), 13f, Ui.text),
                new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f));
        modeRow.addView(segment(new String[]{Ui.t("跟随", "Auto"), Ui.t("浅色", "Light"),
                Ui.t("深色", "Dark")}, colorModeIndex(), new Widgets.OnInt() {
            @Override
            public void onInt(int index) {
                Store.get().setColorMode(new String[]{"system", "light", "dark"}[index]);
                recreate();
            }
        }));
        lookCard.addView(modeRow);
        lookCard.addView(divider());
        lookCard.addView(Widgets.row(this, Ui.t("主题色", "Theme"),
                Ui.find(Store.get().getTheme()).name, "", new Widgets.Action() {
                    @Override
                    public void run() {
                        pickPalette();
                    }
                }));
        lookCard.addView(divider());
        LinearLayout fontRow = new LinearLayout(this);
        fontRow.setOrientation(LinearLayout.HORIZONTAL);
        fontRow.setGravity(Gravity.CENTER_VERTICAL);
        fontRow.setPadding(Ui.dpInt(this, 14), Ui.dpInt(this, 12), Ui.dpInt(this, 12),
                Ui.dpInt(this, 12));
        fontRow.addView(Ui.label(this, Ui.t("字体大小", "Text size"), 13f, Ui.text),
                new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f));
        fontRow.addView(segment(new String[]{Ui.t("小", "S"), Ui.t("标准", "M"), Ui.t("大", "L")},
                Store.get().getFontLevel(), new Widgets.OnInt() {
                    @Override
                    public void onInt(int index) {
                        Store.get().setFontLevel(index);
                        recreate();
                    }
                }));
        lookCard.addView(fontRow);
        lookCard.addView(divider());
        LinearLayout langRow = new LinearLayout(this);
        langRow.setOrientation(LinearLayout.HORIZONTAL);
        langRow.setGravity(Gravity.CENTER_VERTICAL);
        langRow.setPadding(Ui.dpInt(this, 14), Ui.dpInt(this, 12), Ui.dpInt(this, 12),
                Ui.dpInt(this, 12));
        langRow.addView(Ui.label(this, Ui.t("语言", "Language"), 13f, Ui.text),
                new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f));
        langRow.addView(segment(new String[]{"中文", "English"},
                "zh".equals(Store.get().getLang()) ? 0 : 1, new Widgets.OnInt() {
                    @Override
                    public void onInt(int index) {
                        Store.get().setLang(index == 0 ? "zh" : "en");
                        recreate();
                    }
                }));
        lookCard.addView(langRow);
        addCard(lookCard);

        // 检查更新（HAP：单行，右侧当前版本）
        LinearLayout updateCard = Widgets.card(this);
        updateCard.setPadding(0, 0, 0, 0);
        updateCard.addView(Widgets.row(this, Ui.t("检查更新", "Check for updates"),
                newVersionName(), "", new Widgets.Action() {
                    @Override
                    public void run() {
                        checkUpdate();
                    }
                }));
        addCard(updateCard);

        // 关于（HAP：单行 → 弹层）
        LinearLayout aboutCard = Widgets.card(this);
        aboutCard.setPadding(0, 0, 0, 0);
        aboutCard.addView(Widgets.row(this, Ui.t("关于", "About"),
                "SCNet " + newVersionName(), "", new Widgets.Action() {
                    @Override
                    public void run() {
                        showAbout();
                    }
                }));
        addCard(aboutCard);

        // 算力密钥（HAP 在作业页入口，这里保留一行方便找）
        LinearLayout keyCard = Widgets.card(this);
        keyCard.setPadding(0, 0, 0, 0);
        keyCard.addView(Widgets.row(this, Ui.t("算力密钥（AK/SK）", "Compute AK/SK"),
                Store.get().getHpcAk().length() > 0
                        ? Ui.t("已配置", "Configured") : Ui.t("未配置", "Not configured"),
                "", new Widgets.Action() {
                    @Override
                    public void run() {
                        editAkSk();
                    }
                }));
        addCard(keyCard);

        // 调试（Android 特有：镜像/更新源/崩溃）
        root.addView(Widgets.section(this, Ui.t("调试", "Debug")));
        LinearLayout debugCard = Widgets.card(this);
        debugCard.setPadding(0, 0, 0, 0);
        final String debugBase = Store.get().getDebugBase();
        debugCard.addView(Widgets.row(this, Ui.t("API 基地址（mock）", "API base (mock)"),
                debugBase.length() > 0 ? debugBase : Ui.t("官方", "Official"), "",
                new Widgets.Action() {
                    @Override
                    public void run() {
                        Widgets.prompt(ProfileActivity.this,
                                Ui.t("API 基地址（留空=官方）", "API base (empty = official)"),
                                Store.get().getDebugBase(), "http://127.0.0.1:8080", false,
                                new Widgets.OnText() {
                                    @Override
                                    public void onText(String value) {
                                        Store.get().setDebugBase(value.trim());
                                        Widgets.tip(ProfileActivity.this, Ui.t(
                                                "已保存，重启 App 生效", "Saved, restart the app"));
                                    }
                                });
                    }
                }));
        debugCard.addView(divider());
        final String updateUrl = Store.get().getUpdateUrl();
        debugCard.addView(Widgets.row(this, Ui.t("更新源（JSON）", "Update source"),
                updateUrl.length() > 0 ? updateUrl : Ui.t("GitHub Releases", "GitHub"), "",
                new Widgets.Action() {
                    @Override
                    public void run() {
                        Widgets.prompt(ProfileActivity.this,
                                Ui.t("更新源 URL（留空=GitHub）", "Update URL"), updateUrl,
                                "https://example.com/update.json", false, new Widgets.OnText() {
                                    @Override
                                    public void onText(String value) {
                                        Store.get().setUpdateUrl(value.trim());
                                        rebuild();
                                    }
                                });
                    }
                }));
        debugCard.addView(divider());
        debugCard.addView(Widgets.row(this, Ui.t("上次崩溃", "Last crash"), "",
                Store.get().getDebugBase().length() >= 0
                        ? (cn.scnet.agent.core.Crash.last(this).length() > 0
                        ? Ui.t("有", "Yes") : Ui.t("无", "None")) : "—",
                new Widgets.Action() {
                    @Override
                    public void run() {
                        cn.scnet.agent.core.Crash.showIfAny(ProfileActivity.this);
                    }
                }));
        debugCard.addView(divider());
        debugCard.addView(Widgets.row(this, Ui.t("复制诊断信息", "Copy diagnostics"), "", "",
                new Widgets.Action() {
                    @Override
                    public void run() {
                        String text = cn.scnet.agent.core.Crash.diagnostics(ProfileActivity.this);
                        android.content.ClipboardManager cm =
                                (android.content.ClipboardManager)
                                        getSystemService(android.content.Context.CLIPBOARD_SERVICE);
                        cm.setPrimaryClip(android.content.ClipData.newPlainText("diag", text));
                        Widgets.tip(ProfileActivity.this, Ui.t("已复制", "Copied"));
                    }
                }));
        addCard(debugCard);

        // 退出登录（HAP：浅红底按钮）
        TextView logout = new TextView(this);
        logout.setText(Ui.t("退出登录", "Sign out"));
        logout.setTextSize(Ui.sp(14f));
        logout.setTextColor(Ui.danger);
        logout.setGravity(Gravity.CENTER);
        logout.setBackground(Ui.round(Ui.dangerSoft, 12, this));
        logout.setPadding(0, Ui.dpInt(this, 12), 0, Ui.dpInt(this, 12));
        logout.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                Widgets.confirm(ProfileActivity.this, Ui.t("退出登录", "Sign out"),
                        Ui.t("确定要退出吗？", "Sign out now?"), Ui.t("退出", "Sign out"),
                        new Widgets.Action() {
                            @Override
                            public void run() {
                                Task.run(new Task.Work<Void>() {
                                    @Override
                                    public Void run() {
                                        Auth.get().logout();
                                        return null;
                                    }
                                }, new Task.Call<Void>() {
                                    @Override
                                    public void ok(Void value) {
                                        startActivity(new Intent(ProfileActivity.this,
                                                LoginActivity.class)
                                                .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TASK
                                                        | Intent.FLAG_ACTIVITY_NEW_TASK));
                                        finish();
                                    }

                                    @Override
                                    public void fail(String message) {
                                    }
                                });
                            }
                        });
            }
        });
        LinearLayout.LayoutParams logoutLp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        logoutLp.leftMargin = Ui.dpInt(this, 14);
        logoutLp.rightMargin = Ui.dpInt(this, 14);
        logoutLp.topMargin = Ui.dpInt(this, 18);
        root.addView(logout, logoutLp);

        setContentView(scroll);
    }

    /** 信息行的可变值控件（HAP：label 固定 84 宽 + 值）。 */
    private LinearLayout infoRow(String label, TextView value, final Widgets.Action onTap) {
        LinearLayout line = new LinearLayout(this);
        line.setOrientation(LinearLayout.HORIZONTAL);
        line.setGravity(Gravity.CENTER_VERTICAL);
        line.setPadding(0, Ui.dpInt(this, 11), 0, Ui.dpInt(this, 11));
        TextView labelView = Ui.label(this, label, 12f, Ui.textFaint);
        labelView.setWidth(Ui.dpInt(this, 84));
        line.addView(labelView);
        value.setSingleLine(true);
        value.setEllipsize(android.text.TextUtils.TruncateAt.END);
        line.addView(value, new LinearLayout.LayoutParams(0,
                ViewGroup.LayoutParams.WRAP_CONTENT, 1f));
        if (onTap != null) {
            line.setOnClickListener(new View.OnClickListener() {
                @Override
                public void onClick(View v) {
                    onTap.run();
                }
            });
        }
        return line;
    }

    /** 分段控件（HAP：选中的 chip 用主色实心）。 */
    private LinearLayout segment(String[] labels, int selected, final Widgets.OnInt onPick) {
        LinearLayout row = new LinearLayout(this);
        row.setOrientation(LinearLayout.HORIZONTAL);
        for (int i = 0; i < labels.length; i++) {
            final int index = i;
            TextView chip = new TextView(this);
            chip.setText(labels[i]);
            chip.setTextSize(Ui.sp(11.5f));
            chip.setGravity(Gravity.CENTER);
            boolean active = i == selected;
            chip.setTextColor(active ? 0xFFFFFFFF : Ui.textSub);
            chip.setBackground(Ui.round(active ? Ui.accent : Ui.surfaceAlt, 8, this));
            chip.setPadding(Ui.dpInt(this, 10), Ui.dpInt(this, 6), Ui.dpInt(this, 10),
                    Ui.dpInt(this, 6));
            LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT);
            lp.leftMargin = Ui.dpInt(this, 6);
            chip.setOnClickListener(new View.OnClickListener() {
                @Override
                public void onClick(View v) {
                    onPick.onInt(index);
                }
            });
            row.addView(chip, lp);
        }
        return row;
    }

    private int colorModeIndex() {
        String mode = Store.get().getColorMode();
        if ("light".equals(mode)) {
            return 1;
        }
        if ("dark".equals(mode)) {
            return 2;
        }
        return 0;
    }

    private void showAbout() {
        new android.app.AlertDialog.Builder(this)
                .setTitle("SCNet " + newVersionName())
                .setMessage(Ui.t("SCNet 智能体\n非官方客户端，仅调用公开接口\n\n作者：lql341\n"
                                + "项目：scnet-lite-harmonyos（私有仓库）\n\n"
                                + "非官方项目，与曙光智算 / 国家超算互联网无隶属关系。",
                        "SCNet Agent\nUnofficial client, public APIs only\n\nAuthor: lql341\n"
                                + "Project: scnet-lite-harmonyos (private)\n\n"
                                + "Not affiliated with Sugon or SCNet."))
                .setPositiveButton(Ui.t("关闭", "Close"), null)
                .show();
    }

    /** 一行：左侧标题（可点击不做事）+ 右侧可变的 TextView。 */
    private LinearLayout labeledRow(String title, TextView value) {
        LinearLayout line = new LinearLayout(this);
        line.setOrientation(LinearLayout.HORIZONTAL);
        line.setGravity(Gravity.CENTER_VERTICAL);
        line.setPadding(Ui.dpInt(this, 14), Ui.dpInt(this, 12), Ui.dpInt(this, 14),
                Ui.dpInt(this, 12));
        line.addView(Ui.label(this, title, 14f, Ui.text), new LinearLayout.LayoutParams(0,
                ViewGroup.LayoutParams.WRAP_CONTENT, 1f));
        line.addView(value);
        return line;
    }

    /** 异步补上集群账号 / 集群 / 调度器（和 HAP 设置页一致）。 */
    private void loadIdentity() {
        Task.run(new Task.Work<String[]>() {
            @Override
            public String[] run() {
                String[] out = new String[]{"-", "-", "-", "-", "0"};
                try {
                    Auth.Identity identity = Auth.get().clusterIdentity();
                    out[0] = identity.accountId.length() > 0 ? identity.accountId : "-";
                    out[1] = identity.clusterName.length() > 0 ? identity.clusterName : "-";
                } catch (Throwable ignored) {
                }
                try {
                    Auth.UserInfo me = Auth.get().refreshUser();
                    if (me.userName.length() > 0) {
                        Store.get().setPlatformUserName(me.userName);
                    }
                    out[3] = me.id.length() > 0 ? me.id : me.userName;
                } catch (Throwable ignored) {
                }
                try {
                    out[4] = String.valueOf(Auth.get().clusters().size());
                } catch (Throwable ignored) {
                }
                try {
                    if (cn.scnet.agent.svc.Hpc.get().hasCredentials()) {
                        cn.scnet.agent.svc.Hpc.Context ctx = cn.scnet.agent.svc.Hpc.get()
                                .context(String.valueOf(Store.get().getClusterId()), false);
                        out[1] = ctx.clusterName;
                        out[2] = ctx.schedulerId.length() > 0 ? ctx.schedulerId : "-";
                    }
                } catch (Throwable ignored) {
                }
                return out;
            }
        }, new Task.Call<String[]>() {
            @Override
            public void ok(String[] value) {
                if (accountValue != null) {
                    accountValue.setText(value[0]);
                }
                if (clusterValue != null) {
                    clusterValue.setText(value[1]);
                }
                if (channelValue != null) {
                    String count = value[4];
                    channelValue.setText(value[1] + (("-".equals(value[1]) || "0".equals(count))
                            ? "" : Ui.t("（" + count + " 个可选）", " (" + count + ")")));
                }
                if (routeValue != null) {
                    routeValue.setText("agent".equals(Store.get().getChannel())
                            ? Ui.t("智能体服务", "Agent router")
                            : Ui.t("模型网关", "Model gateway"));
                }
                if (userValue != null) {
                    userValue.setText(value[3]);
                }
                if (schedulerValue != null) {
                    schedulerValue.setText(value[2]);
                }
            }

            @Override
            public void fail(String message) {
            }
        });
    }

    private String newVersionName() {
        try {
            return getPackageManager().getPackageInfo(getPackageName(), 0).versionName;
        } catch (Throwable e) {
            return "?";
        }
    }

    private void addCard(View card) {
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        lp.leftMargin = Ui.dpInt(this, 14);
        lp.rightMargin = Ui.dpInt(this, 14);
        root.addView(card, lp);
    }

    private View divider() {
        View v = new View(this);
        v.setBackgroundColor(Ui.hairline);
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, Ui.dpInt(this, 1));
        lp.leftMargin = Ui.dpInt(this, 14);
        v.setLayoutParams(lp);
        return v;
    }

    private String colorModeLabel() {
        String mode = Store.get().getColorMode();
        if ("dark".equals(mode)) {
            return Ui.t("深色", "Dark");
        }
        if ("light".equals(mode)) {
            return Ui.t("浅色", "Light");
        }
        return Ui.t("跟随系统", "System");
    }

    private String fontLevelLabel() {
        int level = Store.get().getFontLevel();
        return level == 0 ? Ui.t("小", "Small") : (level == 2 ? Ui.t("大", "Large")
                : Ui.t("标准", "Normal"));
    }

    private String clusterLabel() {
        int id = Store.get().getClusterId();
        return id == 0 ? Ui.t("自动（第一个）", "Auto (first)") : String.valueOf(id);
    }

    private String customLabel() {
        if (!"custom".equals(Store.get().getModelProvider())) {
            return Ui.t("平台网关", "Platform gateway");
        }
        String name = Store.get().getCustomName();
        return name.length() > 0 ? name : Ui.t("已启用", "Enabled");
    }

    private String versionText() {
        try {
            android.content.pm.PackageInfo info = getPackageManager()
                    .getPackageInfo(getPackageName(), 0);
            return Ui.t("版本 ", "Version ") + info.versionName
                    + " (" + info.versionCode + ") · Android 原生版";
        } catch (Exception e) {
            return Ui.t("版本未知", "Version unknown");
        }
    }

    /** 配色：HAP 的圆形色板网格（4 列，选中打勾）。 */
    private void pickPalette() {
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackground(Ui.round(Ui.surface, 18, this));
        root.setPadding(Ui.dpInt(this, 14), Ui.dpInt(this, 14), Ui.dpInt(this, 14),
                Ui.dpInt(this, 18));

        TextView title = Ui.label(this, Ui.t("主题色", "Palette"), 16f, Ui.text);
        title.setTypeface(android.graphics.Typeface.DEFAULT_BOLD);
        root.addView(title);
        root.addView(Ui.label(this, Ui.t("选中即刻生效，会记住", "Applies instantly"),
                11f, Ui.textFaint));

        final android.app.Dialog dialog = new android.app.Dialog(this);
        dialog.requestWindowFeature(android.view.Window.FEATURE_NO_TITLE);

        LinearLayout grid = new LinearLayout(this);
        grid.setOrientation(LinearLayout.VERTICAL);
        grid.setPadding(0, Ui.dpInt(this, 10), 0, 0);
        LinearLayout row = null;
        for (int i = 0; i < Ui.PALETTES.size(); i++) {
            final Ui.Palette palette = Ui.PALETTES.get(i);
            if (i % 4 == 0) {
                row = new LinearLayout(this);
                row.setOrientation(LinearLayout.HORIZONTAL);
                grid.addView(row);
            }
            LinearLayout cell = new LinearLayout(this);
            cell.setOrientation(LinearLayout.VERTICAL);
            cell.setGravity(Gravity.CENTER_HORIZONTAL);
            cell.setPadding(0, Ui.dpInt(this, 8), 0, Ui.dpInt(this, 8));

            TextView swatch = new TextView(this);
            boolean active = palette.id.equals(Store.get().getTheme());
            swatch.setText(active ? "✓" : "");
            swatch.setTextColor(0xFFFFFFFF);
            swatch.setTextSize(Ui.sp(15f));
            swatch.setGravity(Gravity.CENTER);
            swatch.setBackground(Ui.round(palette.accent, 999, this));
            cell.addView(swatch, new LinearLayout.LayoutParams(Ui.dpInt(this, 44),
                    Ui.dpInt(this, 44)));
            TextView name = Ui.label(this, palette.name, 10.5f,
                    active ? Ui.accent : Ui.textSub);
            name.setPadding(0, Ui.dpInt(this, 6), 0, 0);
            cell.addView(name);
            cell.setOnClickListener(new View.OnClickListener() {
                @Override
                public void onClick(View v) {
                    Store.get().setTheme(palette.id);
                    dialog.dismiss();
                    rebuild();
                }
            });
            row.addView(cell, new LinearLayout.LayoutParams(0,
                    ViewGroup.LayoutParams.WRAP_CONTENT, 1f));
        }
        root.addView(grid);

        TextView close = Widgets.ghostButton(this, Ui.t("关闭", "Close"), new Widgets.Action() {
            @Override
            public void run() {
                dialog.dismiss();
            }
        });
        LinearLayout.LayoutParams closeLp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        closeLp.topMargin = Ui.dpInt(this, 10);
        root.addView(close, closeLp);

        dialog.setContentView(root);
        android.view.Window window = dialog.getWindow();
        if (window != null) {
            window.setBackgroundDrawable(new android.graphics.drawable.ColorDrawable(0));
            window.setLayout(android.view.WindowManager.LayoutParams.MATCH_PARENT,
                    android.view.WindowManager.LayoutParams.WRAP_CONTENT);
            window.setGravity(Gravity.BOTTOM);
        }
        dialog.show();
    }

    private void pickColorMode() {
        String[] options = {Ui.t("跟随系统", "System"), Ui.t("浅色", "Light"), Ui.t("深色", "Dark")};
        String[] values = {"system", "light", "dark"};
        Sheet.pick(this, Ui.t("深色模式", "Dark mode"), options, new Sheet.OnPick() {
            @Override
            public void onPick(Sheet.Item item) {
                for (int i = 0; i < options.length; i++) {
                    if (options[i].equals(item.key)) {
                        Store.get().setColorMode(values[i]);
                        getWindow().getDecorView().post(new Runnable() {
                            @Override
                            public void run() {
                                recreate();
                            }
                        });
                    }
                }
            }
        });
    }

    private void pickFontLevel() {
        String[] options = {Ui.t("小", "Small"), Ui.t("标准", "Normal"), Ui.t("大", "Large")};
        Sheet.pick(this, Ui.t("字号", "Font size"), options, new Sheet.OnPick() {
            @Override
            public void onPick(Sheet.Item item) {
                for (int i = 0; i < options.length; i++) {
                    if (options[i].equals(item.key)) {
                        Store.get().setFontLevel(i);
                        rebuild();
                    }
                }
            }
        });
    }

    private void pickCluster() {
        Task.run(new Task.Work<List<Auth.ClusterInfo>>() {
            @Override
            public List<Auth.ClusterInfo> run() {
                return Auth.get().clusters();
            }
        }, new Task.Call<List<Auth.ClusterInfo>>() {
            @Override
            public void ok(List<Auth.ClusterInfo> value) {
                List<Sheet.Item> items = new ArrayList<>();
                for (Auth.ClusterInfo c : value) {
                    items.add(new Sheet.Item("", String.valueOf(c.clusterId), c.clusterName,
                            c.status, false, Store.get().getClusterId() == c.clusterId));
                }
                if (items.isEmpty()) {
                    Widgets.tip(ProfileActivity.this,
                            Ui.t("没有拿到集群列表", "No clusters"));
                    return;
                }
                Sheet.show(ProfileActivity.this, Ui.t("选择集群", "Choose cluster"), items,
                        new Sheet.OnPick() {
                            @Override
                            public void onPick(Sheet.Item item) {
                                Store.get().setClusterId(Integer.parseInt(item.key));
                                rebuild();
                            }
                        }, true, null);
            }

            @Override
            public void fail(String message) {
                Widgets.tip(ProfileActivity.this, message);
            }
        });
    }

    /** 头像：HAP 的分组网格（卡通 / 风景 / 字母 + 相册 + 让智能体生成）。 */
    private void pickAvatar() {
        final android.app.Dialog dialog = new android.app.Dialog(this);
        dialog.requestWindowFeature(android.view.Window.FEATURE_NO_TITLE);

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackground(Ui.round(Ui.surface, 18, this));
        root.setPadding(Ui.dpInt(this, 16), Ui.dpInt(this, 12), Ui.dpInt(this, 16),
                Ui.dpInt(this, 16));

        TextView title = Ui.label(this, Ui.t("更换头像", "Change avatar"), 16f, Ui.text);
        title.setTypeface(android.graphics.Typeface.DEFAULT_BOLD);
        root.addView(title);
        root.addView(Ui.label(this, Ui.t("选一个内置头像，或从相册选，或让智能体帮你画一个",
                "Pick a preset, choose a photo, or ask the agent"), 10.5f, Ui.textFaint));

        android.widget.ScrollView scroll = new android.widget.ScrollView(this);
        LinearLayout.LayoutParams scrollLp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f);
        scrollLp.topMargin = Ui.dpInt(this, 8);
        root.addView(scroll, scrollLp);

        LinearLayout box = new LinearLayout(this);
        box.setOrientation(LinearLayout.VERTICAL);
        scroll.addView(box);

        String[][] groups = {
                {Ui.t("卡通", "Cartoon"), "🐼", "🦊", "🐳", "🦉", "🐙", "🌵"},
                {Ui.t("风景", "Scenery"), "🌇", "🌊", "🏔", "🌌"},
                {Ui.t("字母", "Letters"), "A", "S"}
        };
        for (final String[] group : groups) {
            TextView head = Ui.label(this, group[0], 10.5f, Ui.textFaint);
            head.setPadding(0, Ui.dpInt(this, 10), 0, Ui.dpInt(this, 6));
            box.addView(head);
            LinearLayout row = new LinearLayout(this);
            row.setOrientation(LinearLayout.HORIZONTAL);
            for (int i = 1; i < group.length; i++) {
                final String glyph = group[i];
                boolean active = ("preset:" + glyph).equals(Store.get().getAvatar());
                TextView cell = new TextView(this);
                cell.setText(glyph);
                cell.setTextSize(Ui.sp(glyph.length() == 1 && glyph.charAt(0) < 0x2000
                        ? 17f : 22f));
                cell.setGravity(Gravity.CENTER);
                cell.setBackground(Ui.round(active ? Ui.lighten(Ui.accent) : Ui.surfaceAlt,
                        999, this));
                LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(
                        Ui.dpInt(this, 46), Ui.dpInt(this, 46));
                lp.rightMargin = Ui.dpInt(this, 10);
                cell.setOnClickListener(new View.OnClickListener() {
                    @Override
                    public void onClick(View v) {
                        Store.get().setAvatar("preset:" + glyph);
                        dialog.dismiss();
                        rebuild();
                    }
                });
                row.addView(cell, lp);
            }
            box.addView(row);
        }

        TextView more = Ui.label(this, Ui.t("其他", "More"), 10.5f, Ui.textFaint);
        more.setPadding(0, Ui.dpInt(this, 14), 0, Ui.dpInt(this, 6));
        box.addView(more);
        box.addView(Widgets.row(this, Ui.t("默认首字", "Initial"), "", "",
                new Widgets.Action() {
                    @Override
                    public void run() {
                        Store.get().setAvatar("");
                        dialog.dismiss();
                        rebuild();
                    }
                }));
        box.addView(Widgets.row(this, Ui.t("从相册选", "From gallery"), "", "",
                new Widgets.Action() {
                    @Override
                    public void run() {
                        dialog.dismiss();
                        Intent intent = new Intent(Intent.ACTION_GET_CONTENT);
                        intent.setType("image/*");
                        try {
                            startActivityForResult(intent, 3001);
                        } catch (Exception e) {
                            Widgets.tip(ProfileActivity.this,
                                    Ui.t("没有相册应用", "No gallery app"));
                        }
                    }
                }));
        box.addView(Widgets.row(this, Ui.t("让智能体生成头像 →", "Ask the agent →"), "", "",
                new Widgets.Action() {
                    @Override
                    public void run() {
                        dialog.dismiss();
                        startActivity(new Intent(ProfileActivity.this, MainActivity.class)
                                .putExtra("prefill", Ui.t(
                                        "帮我设计一个头像：科幻风、超算主题、简洁，给出可用的图片提示词",
                                        "Design an avatar: sci-fi, supercomputing, minimal"))
                                .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP));
                        finish();
                    }
                }));

        root.addView(Widgets.ghostButton(this, Ui.t("关闭", "Close"), new Widgets.Action() {
            @Override
            public void run() {
                dialog.dismiss();
            }
        }));

        dialog.setContentView(root);
        android.view.Window window = dialog.getWindow();
        if (window != null) {
            window.setBackgroundDrawable(new android.graphics.drawable.ColorDrawable(0));
            window.setLayout(android.view.WindowManager.LayoutParams.MATCH_PARENT,
                    (int) (getResources().getDisplayMetrics().heightPixels * 0.72f));
            window.setGravity(Gravity.BOTTOM);
        }
        dialog.show();
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (requestCode != 3001 || resultCode != RESULT_OK || data == null
                || data.getData() == null) {
            return;
        }
        try {
            InputStream in = getContentResolver().openInputStream(data.getData());
            File target = new File(getFilesDir(), "avatar.png");
            FileOutputStream out = new FileOutputStream(target);
            byte[] bytes = Upload.readAll(in);
            in.close();
            out.write(bytes);
            out.close();
            Store.get().setAvatar("file:" + target.getAbsolutePath());
            rebuild();
        } catch (Exception e) {
            Widgets.tip(this, Ui.t("保存头像失败", "Failed to save avatar"));
        }
    }

    private void editCustomProvider() {
        LinearLayout box = new LinearLayout(this);
        box.setOrientation(LinearLayout.VERTICAL);
        box.setPadding(Ui.dpInt(this, 16), Ui.dpInt(this, 8), Ui.dpInt(this, 16), 0);
        final EditText name = input(Ui.t("名称（如 DeepSeek）", "Name"), Store.get().getCustomName());
        final EditText url = input("Base URL", Store.get().getCustomBaseUrl());
        final EditText key = input("API Key", Store.get().getCustomApiKey());
        final EditText model = input(Ui.t("模型 id", "Model id"), Store.get().getCustomModel());
        final String[][] presets = {
                {"DeepSeek", "https://api.deepseek.com/v1", "deepseek-chat"},
                {"Moonshot", "https://api.moonshot.cn/v1", "moonshot-v1-8k"},
                {Ui.t("通义千问", "Qwen"), "https://dashscope.aliyuncs.com/compatible-mode/v1",
                        "qwen-plus"},
                {Ui.t("智谱 GLM", "Zhipu GLM"), "https://open.bigmodel.cn/api/paas/v4",
                        "glm-4-plus"},
                {"OpenAI", "https://api.openai.com/v1", "gpt-4o-mini"},
                {"SiliconFlow", "https://api.siliconflow.cn/v1", "Qwen/Qwen2.5-7B-Instruct"},
                {"Ollama", "http://127.0.0.1:11434/v1", "llama3.1"}
        };
        LinearLayout presetRow = new LinearLayout(this);
        presetRow.setOrientation(LinearLayout.HORIZONTAL);
        presetRow.setPadding(0, Ui.dpInt(this, 2), 0, Ui.dpInt(this, 8));
        for (final String[] preset : presets) {
            TextView chip = Widgets.chip(this, preset[0], Ui.accent, Ui.accentSoft);
            LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT);
            lp.rightMargin = Ui.dpInt(this, 6);
            chip.setOnClickListener(new View.OnClickListener() {
                @Override
                public void onClick(View v) {
                    name.setText(preset[0]);
                    url.setText(preset[1]);
                    model.setText(preset[2]);
                }
            });
            presetRow.addView(chip, lp);
        }
        android.widget.HorizontalScrollView presetScroll =
                new android.widget.HorizontalScrollView(this);
        presetScroll.setHorizontalScrollBarEnabled(false);
        presetScroll.addView(presetRow);
        box.addView(presetScroll);
        box.addView(name);
        box.addView(url);
        box.addView(key);
        box.addView(model);
        TextView clear = Widgets.ghostButton(this, Ui.t("恢复平台网关", "Back to platform gateway"),
                null);
        box.addView(clear);

        final AlertDialog dialog = new AlertDialog.Builder(this)
                .setTitle(Ui.t("自定义模型服务", "Custom model service"))
                .setView(box)
                .setNegativeButton(Ui.t("取消", "Cancel"), null)
                .setPositiveButton(Ui.t("保存", "Save"), null)
                .create();
        dialog.show();
        clear.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                Store.get().clearCustomProvider();
                dialog.dismiss();
                rebuild();
            }
        });
        dialog.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                if (url.getText().toString().trim().length() == 0) {
                    Widgets.tip(ProfileActivity.this, Ui.t("Base URL 必填", "Base URL required"));
                    return;
                }
                Store.get().setCustomProvider(name.getText().toString().trim(),
                        url.getText().toString().trim(),
                        key.getText().toString().trim(),
                        model.getText().toString().trim());
                dialog.dismiss();
                rebuild();
            }
        });
    }

    private void editAkSk() {
        LinearLayout box = new LinearLayout(this);
        box.setOrientation(LinearLayout.VERTICAL);
        box.setPadding(Ui.dpInt(this, 16), Ui.dpInt(this, 8), Ui.dpInt(this, 16), 0);
        final EditText ak = input("AccessKey", Store.get().getHpcAk());
        final EditText sk = input("SecretKey", Store.get().getHpcSk());
        final EditText user = input(Ui.t("平台用户名", "Platform user name"), Store.get().getHpcUser());
        TextView hint = Ui.label(this, Ui.t("也可一次粘贴「AccessKey:SecretKey」到第一个框里。",
                "You can also paste \"AccessKey:SecretKey\" into the first field."), 11f, Ui.textFaint);
        box.addView(ak);
        box.addView(sk);
        box.addView(user);
        box.addView(hint);

        new AlertDialog.Builder(this)
                .setTitle(Ui.t("算力服务 AK/SK", "Compute AK/SK"))
                .setView(box)
                .setNegativeButton(Ui.t("取消", "Cancel"), null)
                .setPositiveButton(Ui.t("保存", "Save"), new android.content.DialogInterface.OnClickListener() {
                    @Override
                    public void onClick(android.content.DialogInterface d, int which) {
                        String akText = ak.getText().toString().trim();
                        String skText = sk.getText().toString().trim();
                        if (akText.contains(":")) {
                            String[] parts = akText.split(":", 2);
                            akText = parts[0].trim();
                            skText = parts[1].trim();
                        }
                        String error = Hpc.get().validateCreds(akText, skText);
                        if (error.length() > 0) {
                            Widgets.tip(ProfileActivity.this, error);
                            return;
                        }
                        Store.get().setHpcAk(akText);
                        Store.get().setHpcSk(skText);
                        Store.get().setHpcUser(user.getText().toString().trim());
                        rebuild();
                    }
                })
                .show();
    }

    private EditText input(String hint, String value) {
        EditText et = new EditText(this);
        et.setHint(hint);
        et.setText(value);
        et.setTextSize(Ui.sp(13.5f));
        et.setSingleLine(true);
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        lp.bottomMargin = Ui.dpInt(this, 6);
        et.setLayoutParams(lp);
        return et;
    }

    /** 检查更新：自定义 JSON 源优先，其次 GitHub Releases API；结果用对话框给出。 */
    private void checkUpdate() {
        Widgets.tip(this, Ui.t("正在检查更新…", "Checking for updates…"));
        Task.run(new Task.Work<cn.scnet.agent.svc.Update.Info>() {
            @Override
            public cn.scnet.agent.svc.Update.Info run() {
                return cn.scnet.agent.svc.Update.check(ProfileActivity.this);
            }
        }, new Task.Call<cn.scnet.agent.svc.Update.Info>() {
            @Override
            public void ok(final cn.scnet.agent.svc.Update.Info info) {
                if (info.error.length() > 0) {
                    new android.app.AlertDialog.Builder(ProfileActivity.this)
                            .setTitle(Ui.t("检查更新失败", "Update check failed"))
                            .setMessage(info.error + "\n\n" + Ui.t(
                                    "提示：仓库是私有的，匿名访问 GitHub 会 404。\n"
                                            + "可以在「调试 → 更新源」填一个公开的 JSON 地址，格式：\n"
                                            + "{\"versionName\":\"0.5.3\",\"versionCode\":13,\"url\":\"https://…/x.apk\"}",
                                    "The repo is private, so anonymous GitHub requests 404.\n"
                                            + "Set a public JSON URL in Debug → update source."))
                            .setPositiveButton(Ui.t("去配更新源", "Set source"),
                                    new android.content.DialogInterface.OnClickListener() {
                                        @Override
                                        public void onClick(android.content.DialogInterface d,
                                                            int which) {
                                            Store.get().setUpdateUrl("");
                                            Widgets.tip(ProfileActivity.this,
                                                    Ui.t("请在调试区填写更新源",
                                                            "Fill the update source in Debug"));
                                        }
                                    })
                            .setNegativeButton(Ui.t("关闭", "Close"), null)
                            .show();
                    return;
                }
                if (!info.newer) {
                    new android.app.AlertDialog.Builder(ProfileActivity.this)
                            .setTitle(Ui.t("已是最新版本", "Up to date"))
                            .setMessage(Ui.t("当前版本 ", "Current ") + newVersionName())
                            .setPositiveButton(Ui.t("好", "OK"), null)
                            .show();
                    return;
                }
                new android.app.AlertDialog.Builder(ProfileActivity.this)
                        .setTitle(Ui.t("发现新版本 ", "New version ") + info.versionName)
                        .setMessage(info.notes.length() > 0 ? info.notes
                                : Ui.t("（无更新说明）", "(no release notes)"))
                        .setPositiveButton(Ui.t("下载并安装", "Download & install"),
                                new android.content.DialogInterface.OnClickListener() {
                                    @Override
                                    public void onClick(android.content.DialogInterface d,
                                                        int which) {
                                        long id = cn.scnet.agent.svc.Update.download(
                                                ProfileActivity.this, info);
                                        Widgets.tip(ProfileActivity.this, id > 0
                                                ? Ui.t("开始下载，完成后点通知安装",
                                                "Downloading — tap the notification to install")
                                                : Ui.t("无法启动下载", "Cannot start download"));
                                    }
                                })
                        .setNegativeButton(Ui.t("取消", "Cancel"), null)
                        .show();
            }

            @Override
            public void fail(String message) {
                Widgets.tip(ProfileActivity.this, message);
            }
        });
    }

    private void openUrl(String url) {
        try {
            startActivity(new Intent(Intent.ACTION_VIEW, Uri.parse(url)));
        } catch (Exception e) {
            Widgets.tip(this, Ui.t("没有可用的浏览器", "No browser available"));
        }
    }
}
