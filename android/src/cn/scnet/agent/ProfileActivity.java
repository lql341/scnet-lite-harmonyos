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
            "🌇", "🌊", "🏔", "🌌"};

    private LinearLayout root;
    private TextView versionView;

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        Store.init(this);
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

        // 关于
        root.addView(Widgets.section(this, Ui.t("关于", "About")));
        LinearLayout about = Widgets.card(this);
        about.setPadding(0, 0, 0, 0);
        versionView = Ui.label(this, versionText(), 13f, Ui.textSub);
        versionView.setPadding(Ui.dpInt(this, 14), Ui.dpInt(this, 12), Ui.dpInt(this, 14),
                Ui.dpInt(this, 12));
        about.addView(versionView);
        about.addView(divider());
        about.addView(Widgets.row(this, Ui.t("GitHub 仓库", "GitHub repository"),
                "lql341/scnet-lite-harmonyos", "", new Widgets.Action() {
                    @Override
                    public void run() {
                        openUrl("https://github.com/lql341/scnet-lite-harmonyos");
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
        for (String emoji : PRESET_AVATARS) {
            items.add(new Sheet.Item(Ui.t("内置", "Presets"), "preset:" + emoji, emoji, "",
                    false, ("preset:" + emoji).equals(Store.get().getAvatar())));
        }
        Sheet.show(this, Ui.t("更换头像", "Change avatar"), items, new Sheet.OnPick() {
            @Override
            public void onPick(Sheet.Item item) {
                if ("reset".equals(item.key)) {
                    Store.get().setAvatar("");
                    rebuild();
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
        TextView presets = Ui.label(this, Ui.t("常用：DeepSeek / Moonshot / 通义 / 智谱 / OpenAI",
                "Common: DeepSeek / Moonshot / Qwen / Zhipu / OpenAI"), 11f, Ui.textFaint);
        presets.setPadding(0, Ui.dpInt(this, 4), 0, Ui.dpInt(this, 6));
        box.addView(name);
        box.addView(url);
        box.addView(key);
        box.addView(model);
        box.addView(presets);
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

    private void openUrl(String url) {
        try {
            startActivity(new Intent(Intent.ACTION_VIEW, Uri.parse(url)));
        } catch (Exception e) {
            Widgets.tip(this, Ui.t("没有可用的浏览器", "No browser available"));
        }
    }
}
