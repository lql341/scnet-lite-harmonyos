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

        LinearLayout bar = new LinearLayout(this);
        bar.setOrientation(LinearLayout.HORIZONTAL);
        bar.setGravity(Gravity.CENTER_VERTICAL);
        bar.setPadding(Ui.dpInt(this, 12), Ui.dpInt(this, 10), Ui.dpInt(this, 14),
                Ui.dpInt(this, 6));
        TextView back = Widgets.glyphButton(this, "‹", new Widgets.Action() {
            @Override
            public void run() {
                finish();
            }
        });
        bar.addView(back, new LinearLayout.LayoutParams(Ui.dpInt(this, 34), Ui.dpInt(this, 34)));
        TextView title = Ui.label(this, Ui.t("设置", "Settings"), 16f, Ui.text);
        title.setTypeface(Typeface.DEFAULT_BOLD);
        title.setPadding(Ui.dpInt(this, 10), 0, 0, 0);
        bar.addView(title);
        root.addView(bar);

        // 账号卡
        LinearLayout account = Widgets.card(this);
        account.setOrientation(LinearLayout.HORIZONTAL);
        account.setGravity(Gravity.CENTER_VERTICAL);
        account.setPadding(Ui.dpInt(this, 16), Ui.dpInt(this, 16), Ui.dpInt(this, 16),
                Ui.dpInt(this, 16));
        account.addView(Widgets.avatar(this, Store.get().getPlatformUserName(),
                Store.get().getAvatar(), 52, new Widgets.Action() {
                    @Override
                    public void run() {
                        pickAvatar();
                    }
                }));
        LinearLayout names = new LinearLayout(this);
        names.setOrientation(LinearLayout.VERTICAL);
        names.setPadding(Ui.dpInt(this, 12), 0, 0, 0);
        String name = Store.get().getPlatformUserName();
        names.addView(Ui.label(this, name.length() > 0 ? name : Ui.t("已登录", "Signed in"),
                16f, Ui.text));
        names.addView(Ui.label(this, Ui.t("点左上角头像可换头像",
                "Tap the avatar to change it"), 11f, Ui.textFaint));
        account.addView(names);
        LinearLayout.LayoutParams accountLp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        accountLp.leftMargin = Ui.dpInt(this, 14);
        accountLp.rightMargin = Ui.dpInt(this, 14);
        accountLp.topMargin = Ui.dpInt(this, 4);
        root.addView(account, accountLp);

        // 外观
        root.addView(Widgets.section(this, Ui.t("外观", "Appearance")));
        LinearLayout look = Widgets.card(this);
        look.setPadding(0, 0, 0, 0);
        look.addView(Widgets.row(this, Ui.t("配色", "Palette"), Ui.find(Store.get().getTheme()).name,
                "", new Widgets.Action() {
                    @Override
                    public void run() {
                        pickPalette();
                    }
                }));
        look.addView(divider());
        look.addView(Widgets.row(this, Ui.t("深色模式", "Dark mode"),
                colorModeLabel(), "", new Widgets.Action() {
                    @Override
                    public void run() {
                        pickColorMode();
                    }
                }));
        look.addView(divider());
        look.addView(Widgets.row(this, Ui.t("字号", "Font size"), fontLevelLabel(), "",
                new Widgets.Action() {
                    @Override
                    public void run() {
                        pickFontLevel();
                    }
                }));
        look.addView(divider());
        look.addView(Widgets.row(this, Ui.t("语言", "Language"),
                "zh".equals(Store.get().getLang()) ? "中文" : "English", "",
                new Widgets.Action() {
                    @Override
                    public void run() {
                        Store.get().setLang("zh".equals(Store.get().getLang()) ? "en" : "zh");
                        rebuild();
                    }
                }));
        addCard(look);

        // 身份（对齐 HAP 设置页的账号/集群信息）
        root.addView(Widgets.section(this, Ui.t("身份", "Identity")));
        LinearLayout identityCard = Widgets.card(this);
        identityCard.setPadding(0, 0, 0, 0);
        String user = Store.get().getPlatformUserName();
        identityCard.addView(Widgets.row(this, Ui.t("平台账号", "Platform account"),
                user.length() > 0 ? user : Ui.t("未登录", "Not signed in"), "", null));
        identityCard.addView(divider());
        accountValue = Ui.label(this, "…", 12.5f, Ui.textSub);
        identityCard.addView(labeledRow(Ui.t("集群账号", "Cluster account"), accountValue));
        identityCard.addView(divider());
        clusterValue = Ui.label(this, "…", 12.5f, Ui.textSub);
        identityCard.addView(labeledRow(Ui.t("当前集群", "Cluster"), clusterValue));
        identityCard.addView(divider());
        schedulerValue = Ui.label(this, "…", 12.5f, Ui.textSub);
        identityCard.addView(labeledRow(Ui.t("调度器", "Scheduler"), schedulerValue));
        addCard(identityCard);
        loadIdentity();

        // 通道
        root.addView(Widgets.section(this, Ui.t("通道", "Channel")));
        LinearLayout channelCard = Widgets.card(this);
        channelCard.setPadding(0, 0, 0, 0);
        channelCard.addView(Widgets.row(this, Ui.t("集群", "Cluster"), clusterLabel(), "",
                new Widgets.Action() {
                    @Override
                    public void run() {
                        pickCluster();
                    }
                }));
        channelCard.addView(divider());
        channelCard.addView(Widgets.row(this, Ui.t("当前通道", "Current channel"),
                "agent".equals(Store.get().getChannel())
                        ? Ui.t("智能体服务", "Agent service")
                        : (Ui.t("模型网关 · ", "Model gateway · ") + Store.get().getModel()),
                "", null));
        channelCard.addView(divider());
        channelCard.addView(Widgets.row(this, Ui.t("自定义模型服务", "Custom model service"),
                customLabel(), "", new Widgets.Action() {
                    @Override
                    public void run() {
                        editCustomProvider();
                    }
                }));
        addCard(channelCard);

        // 算力服务
        root.addView(Widgets.section(this, Ui.t("算力服务", "Compute service")));
        LinearLayout hpcCard = Widgets.card(this);
        hpcCard.setPadding(0, 0, 0, 0);
        hpcCard.addView(Widgets.row(this, Ui.t("AccessKey / SecretKey", "AK / SK"),
                Store.get().getHpcAk().length() > 0
                        ? Ui.t("已配置", "Configured") : Ui.t("未配置", "Not configured"),
                "", new Widgets.Action() {
                    @Override
                    public void run() {
                        editAkSk();
                    }
                }));
        addCard(hpcCard);

        // 调试（联调用：把平台域名指向自建 mock）
        root.addView(Widgets.section(this, Ui.t("调试", "Debug")));
        LinearLayout debugCard = Widgets.card(this);
        debugCard.setPadding(0, 0, 0, 0);
        String debugBase = Store.get().getDebugBase();
        debugCard.addView(Widgets.row(this, Ui.t("API 基地址（mock）", "API base (mock)"),
                debugBase.length() > 0 ? debugBase : Ui.t("官方（www.scnet.cn）", "Official"),
                "", new Widgets.Action() {
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
        debugCard.addView(Widgets.row(this, Ui.t("上次崩溃堆栈", "Last crash"), "",
                cn.scnet.agent.core.Crash.last(this).length() > 0
                        ? Ui.t("有", "Yes") : Ui.t("无", "None"),
                new Widgets.Action() {
                    @Override
                    public void run() {
                        cn.scnet.agent.core.Crash.showIfAny(ProfileActivity.this);
                    }
                }));
        debugCard.addView(divider());
        final String updateUrl = Store.get().getUpdateUrl();
        debugCard.addView(Widgets.row(this, Ui.t("更新源（JSON）", "Update source (JSON)"),
                updateUrl.length() > 0 ? updateUrl : Ui.t("GitHub Releases（私有仓库会 404）",
                        "GitHub Releases (404 when private)"), "",
                new Widgets.Action() {
                    @Override
                    public void run() {
                        Widgets.prompt(ProfileActivity.this,
                                Ui.t("更新源 URL（留空=GitHub）", "Update URL (empty = GitHub)"),
                                Store.get().getUpdateUrl(),
                                "https://example.com/scnet-agent-update.json", false,
                                new Widgets.OnText() {
                                    @Override
                                    public void onText(String value) {
                                        Store.get().setUpdateUrl(value.trim());
                                        rebuild();
                                    }
                                });
                    }
                }));
        debugCard.addView(divider());
        debugCard.addView(Widgets.row(this, Ui.t("复制诊断信息", "Copy diagnostics"),
                Ui.t("版本/网络/配置 + 上次崩溃", "Version/network/config + last crash"), "",
                new Widgets.Action() {
                    @Override
                    public void run() {
                        String text = cn.scnet.agent.core.Crash.diagnostics(ProfileActivity.this);
                        android.content.ClipboardManager cm =
                                (android.content.ClipboardManager)
                                        getSystemService(android.content.Context.CLIPBOARD_SERVICE);
                        cm.setPrimaryClip(android.content.ClipData.newPlainText("diag", text));
                        Widgets.tip(ProfileActivity.this, Ui.t("已复制，发给开发者即可",
                                "Copied — send it to the developer"));
                    }
                }));
        addCard(debugCard);

        // 关于
        root.addView(Widgets.section(this, Ui.t("关于", "About")));
        LinearLayout about = Widgets.card(this);
        about.setPadding(0, 0, 0, 0);
        versionView = Ui.label(this, versionText(), 13f, Ui.textSub);
        versionView.setPadding(Ui.dpInt(this, 14), Ui.dpInt(this, 12), Ui.dpInt(this, 14),
                Ui.dpInt(this, 12));
        about.addView(versionView);
        about.addView(divider());
        about.addView(Widgets.row(this, Ui.t("检查更新", "Check for updates"),
                Ui.t("当前版本 ", "Current ") + newVersionName(), "",
                new Widgets.Action() {
                    @Override
                    public void run() {
                        checkUpdate();
                    }
                }));
        about.addView(divider());
        about.addView(Widgets.row(this, Ui.t("作者", "Author"), "lql341", "",
                new Widgets.Action() {
                    @Override
                    public void run() {
                        openUrl("https://github.com/lql341");
                    }
                }));

        about.addView(divider());
        TextView disclaimer = Ui.label(this,
                Ui.t("非官方项目，与曙光智算 / 国家超算互联网无隶属关系。不含厂商代码与二进制，只复用公开接口契约。",
                        "Unofficial project, not affiliated with Sugon or SCNet. No vendor code or binaries."),
                11.5f, Ui.textFaint);
        disclaimer.setPadding(Ui.dpInt(this, 14), Ui.dpInt(this, 12), Ui.dpInt(this, 14),
                Ui.dpInt(this, 12));
        about.addView(disclaimer);
        addCard(about);

        TextView logout = Widgets.ghostButton(this, Ui.t("退出登录", "Sign out"), new Widgets.Action() {
            @Override
            public void run() {
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
        logout.setTextColor(Ui.danger);
        logout.setBackground(Ui.roundStroke(Ui.dangerSoft, Ui.dangerSoft, 12, this));
        LinearLayout.LayoutParams logoutLp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        logoutLp.leftMargin = Ui.dpInt(this, 14);
        logoutLp.rightMargin = Ui.dpInt(this, 14);
        logoutLp.topMargin = Ui.dpInt(this, 18);
        root.addView(logout, logoutLp);

        setContentView(scroll);
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
                String[] out = new String[]{"-", "-", "-"};
                try {
                    Auth.Identity identity = Auth.get().clusterIdentity();
                    out[0] = identity.accountId.length() > 0 ? identity.accountId : "-";
                    out[1] = identity.clusterName.length() > 0 ? identity.clusterName : "-";
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

    private void pickPalette() {
        List<Sheet.Item> items = new ArrayList<>();
        for (Ui.Palette palette : Ui.PALETTES) {
            items.add(new Sheet.Item("", palette.id, palette.name, "",
                    false, palette.id.equals(Store.get().getTheme())));
        }
        Sheet.show(this, Ui.t("配色", "Palette"), items, new Sheet.OnPick() {
            @Override
            public void onPick(Sheet.Item item) {
                Store.get().setTheme(item.key);
                rebuild();
            }
        }, false, null);
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

    private void pickAvatar() {
        List<Sheet.Item> items = new ArrayList<>();
        items.add(new Sheet.Item("", "reset", Ui.t("默认首字", "Initial"), "", false, false));
        items.add(new Sheet.Item("", "photo", Ui.t("从相册选择", "Choose photo"), "", false, false));
        items.add(new Sheet.Item("", "ai", Ui.t("让智能体生成", "Ask the agent"), "", false, false));
        for (String emoji : PRESET_AVATARS) {
            boolean letter = emoji.length() == 1 && emoji.charAt(0) < 0x2000;
            items.add(new Sheet.Item(Ui.t(letter ? "字母" : "内置", letter ? "Letters" : "Presets"),
                    "preset:" + emoji, emoji, "", false,
                    ("preset:" + emoji).equals(Store.get().getAvatar())));
        }
        Sheet.show(this, Ui.t("更换头像", "Change avatar"), items, new Sheet.OnPick() {
            @Override
            public void onPick(Sheet.Item item) {
                if ("reset".equals(item.key)) {
                    Store.get().setAvatar("");
                    rebuild();
                } else if ("ai".equals(item.key)) {
                    // 对齐 HAP：把生成头像的提示词带回对话页
                    startActivity(new Intent(ProfileActivity.this, MainActivity.class)
                            .putExtra("prefill", Ui.t(
                                    "帮我设计一个头像：科幻风、超算主题、简洁，给出可用的图片提示词",
                                    "Design an avatar for me: sci-fi, supercomputing, minimal — "
                                            + "give me a usable image prompt"))
                            .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP));
                    finish();
                } else if ("photo".equals(item.key)) {
                    Intent intent = new Intent(Intent.ACTION_GET_CONTENT);
                    intent.setType("image/*");
                    try {
                        startActivityForResult(intent, 3001);
                    } catch (Exception e) {
                        Widgets.tip(ProfileActivity.this, Ui.t("没有相册应用", "No gallery app"));
                    }
                } else if (item.key.startsWith("preset:")) {
                    Store.get().setAvatar(item.key);
                    rebuild();
                }
            }
        }, false, null);
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
