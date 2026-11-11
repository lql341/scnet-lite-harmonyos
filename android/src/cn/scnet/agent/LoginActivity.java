package cn.scnet.agent;

import android.app.Activity;
import android.content.Context;
import android.content.Intent;
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

import cn.scnet.agent.core.Http;
import cn.scnet.agent.core.Crash;
import cn.scnet.agent.core.Store;
import cn.scnet.agent.core.Task;
import cn.scnet.agent.svc.Auth;
import cn.scnet.agent.ui.Ui;
import cn.scnet.agent.ui.Widgets;

/**
 * 登录页（对齐 ArkTS 的 pages/Login.ets）：账号密码 / 短信验证码双 Tab。
 * 登录过期时明显提示，而不是让人莫名回到登录。
 */
public class LoginActivity extends Activity {

    private EditText accountField;
    private EditText passwordField;
    private EditText phoneField;
    private EditText codeField;
    private TextView errorView;
    private TextView passwordTab;
    private TextView smsTab;
    private LinearLayout passwordForm;
    private LinearLayout smsForm;
    private TextView submit;
    private TextView smsSend;
    private boolean smsMode;
    private boolean busy;
    private CheckBox agreeBox;
    private final java.util.Map<EditText, LinearLayout> boxes =
            new java.util.HashMap<>();
    /** 主界面是否已经把本页 pause 掉（用于判断 startActivity 是否真的生效） */
    private boolean leftForMain;

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        Store.init(this);
        Crash.install(this);
        Crash.showIfAny(this);
        Crash.guard(this, new Runnable() {
            @Override
            public void run() {
                applyAppearance();
                buildUi();
            }
        });
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
        ScrollView scroll = new ScrollView(this);
        scroll.setBackgroundColor(Ui.bg);
        scroll.setFillViewport(true);
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(Ui.dpInt(this, 22), Ui.dpInt(this, 32), Ui.dpInt(this, 22),
                Ui.dpInt(this, 16));
        scroll.addView(root);

        // 品牌区（HAP：68px 圆角图标 + SCNet 智能体 + 副标题）
        LinearLayout brand = new LinearLayout(this);
        brand.setOrientation(LinearLayout.VERTICAL);
        brand.setGravity(Gravity.CENTER_HORIZONTAL);
        brand.setPadding(0, Ui.dpInt(this, 16), 0, Ui.dpInt(this, 24));

        android.widget.ImageView icon = new android.widget.ImageView(this);
        try {
            icon.setImageResource(getResources().getIdentifier("ic_launcher", "mipmap",
                    getPackageName()));
            icon.setBackground(Ui.round(Ui.accentSoft, 20, this));
            icon.setScaleType(android.widget.ImageView.ScaleType.CENTER_INSIDE);
            icon.setPadding(Ui.dpInt(this, 12), Ui.dpInt(this, 12), Ui.dpInt(this, 12),
                    Ui.dpInt(this, 12));
        } catch (Throwable ignored) {
        }
        brand.addView(icon, new LinearLayout.LayoutParams(Ui.dpInt(this, 68),
                Ui.dpInt(this, 68)));

        TextView brandName = Ui.label(this, Ui.t("SCNet 智能体", "SCNet Agent"), 24f, Ui.text);
        brandName.setTypeface(Typeface.DEFAULT_BOLD);
        brandName.setPadding(0, Ui.dpInt(this, 10), 0, 0);
        brand.addView(brandName);
        brand.addView(Ui.label(this, Ui.t("国家超算互联网 · 科研计算助手",
                "SCNet · research computing assistant"), 12f, Ui.textSub));
        root.addView(brand);

        // 登录过期提示（HAP：黄卡 + ⓘ）
        if ("expired".equals(Auth.get().loginReason)) {
            LinearLayout warn = new LinearLayout(this);
            warn.setOrientation(LinearLayout.HORIZONTAL);
            warn.setGravity(Gravity.TOP);
            warn.setBackground(Ui.round(android.graphics.Color.parseColor("#FFF8EC"), 12, this));
            warn.setPadding(Ui.dpInt(this, 12), Ui.dpInt(this, 12), Ui.dpInt(this, 12),
                    Ui.dpInt(this, 12));
            TextView mark = Ui.label(this, "ⓘ", 12f, Ui.warn);
            mark.setPadding(0, 0, Ui.dpInt(this, 8), 0);
            warn.addView(mark);
            LinearLayout texts = new LinearLayout(this);
            texts.setOrientation(LinearLayout.VERTICAL);
            texts.addView(Ui.label(this, Ui.t("登录已过期", "Session expired"), 12f, Ui.warn));
            texts.addView(Ui.label(this, Ui.t(
                    "为保护账号，长时间未使用需要重新登录；密码 / 短信验证码都可以",
                    "Please sign in again with password or SMS code"), 10f, Ui.textSub));
            warn.addView(texts, new LinearLayout.LayoutParams(0,
                    ViewGroup.LayoutParams.WRAP_CONTENT, 1f));
            LinearLayout.LayoutParams warnLp = new LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
            warnLp.bottomMargin = Ui.dpInt(this, 12);
            root.addView(warn, warnLp);
        }

        // 白卡（HAP：表单在 surface 卡里）
        LinearLayout card = new LinearLayout(this);
        card.setOrientation(LinearLayout.VERTICAL);
        card.setBackground(Ui.round(Ui.surface, 20, this));
        card.setPadding(Ui.dpInt(this, 18), Ui.dpInt(this, 16), Ui.dpInt(this, 18),
                Ui.dpInt(this, 18));

        // 分段 Tab（HAP：账号密码 / 短信验证）
        LinearLayout tabs = new LinearLayout(this);
        tabs.setOrientation(LinearLayout.HORIZONTAL);
        tabs.setBackground(Ui.round(Ui.surfaceAlt, 12, this));
        tabs.setPadding(Ui.dpInt(this, 4), Ui.dpInt(this, 4), Ui.dpInt(this, 4),
                Ui.dpInt(this, 4));
        passwordTab = tab(this, Ui.t("账号密码", "Password"), true);
        smsTab = tab(this, Ui.t("短信验证", "SMS"), false);
        tabs.addView(passwordTab, new LinearLayout.LayoutParams(0,
                ViewGroup.LayoutParams.WRAP_CONTENT, 1f));
        tabs.addView(smsTab, new LinearLayout.LayoutParams(0,
                ViewGroup.LayoutParams.WRAP_CONTENT, 1f));
        card.addView(tabs);
        passwordTab.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                switchMode(false);
            }
        });
        smsTab.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                switchMode(true);
            }
        });

        // 密码表单（HAP：账号 / 密码 + 登录）
        passwordForm = new LinearLayout(this);
        passwordForm.setOrientation(LinearLayout.VERTICAL);
        passwordForm.setPadding(0, Ui.dpInt(this, 16), 0, 0);
        accountField = field(Ui.t("账号", "Account"), Ui.t("用户名 / 手机号", "User / phone"),
                android.text.InputType.TYPE_CLASS_TEXT, false);
        passwordField = field(Ui.t("密码", "Password"), Ui.t("登录密码", "Password"),
                android.text.InputType.TYPE_CLASS_TEXT
                        | android.text.InputType.TYPE_TEXT_VARIATION_PASSWORD, false);
        passwordForm.addView(fieldBox(accountField));
        passwordForm.addView(fieldBox(passwordField));
        passwordForm.addView(Widgets.primaryButton(this, Ui.t("登录", "Sign in"), 46,
                new Widgets.Action() {
                    @Override
                    public void run() {
                        doLogin();
                    }
                }));
        card.addView(passwordForm);

        // 短信表单（HAP：手机号 / 验证码+获取 + 登录·注册）
        smsForm = new LinearLayout(this);
        smsForm.setOrientation(LinearLayout.VERTICAL);
        smsForm.setPadding(0, Ui.dpInt(this, 16), 0, 0);
        smsForm.setVisibility(View.GONE);
        phoneField = field(Ui.t("手机号", "Phone"), Ui.t("11 位手机号", "11-digit phone"),
                android.text.InputType.TYPE_CLASS_PHONE, false);
        LinearLayout codeRow = new LinearLayout(this);
        codeRow.setOrientation(LinearLayout.HORIZONTAL);
        codeRow.setGravity(Gravity.CENTER_VERTICAL);
        codeField = field(Ui.t("验证码", "Code"), Ui.t("短信验证码", "SMS code"),
                android.text.InputType.TYPE_CLASS_NUMBER, false);
        codeRow.addView(fieldBox(codeField), new LinearLayout.LayoutParams(0,
                ViewGroup.LayoutParams.WRAP_CONTENT, 1f));
        smsSend = new TextView(this);
        smsSend.setText(Ui.t("获取验证码", "Send code"));
        smsSend.setTextSize(Ui.sp(12f));
        smsSend.setTextColor(Ui.accent);
        smsSend.setGravity(Gravity.CENTER);
        smsSend.setBackground(Ui.round(Ui.accentGhost, 10, this));
        smsSend.setPadding(Ui.dpInt(this, 12), Ui.dpInt(this, 13), Ui.dpInt(this, 12),
                Ui.dpInt(this, 13));
        LinearLayout.LayoutParams sendLp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        sendLp.leftMargin = Ui.dpInt(this, 8);
        sendLp.bottomMargin = Ui.dpInt(this, 10);
        codeRow.addView(smsSend, sendLp);
        smsSend.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                sendSms();
            }
        });
        smsForm.addView(fieldBox(phoneField));
        smsForm.addView(codeRow);
        smsForm.addView(Widgets.primaryButton(this, Ui.t("登录 / 注册", "Sign in / sign up"), 46,
                new Widgets.Action() {
                    @Override
                    public void run() {
                        doLogin();
                    }
                }));
        card.addView(smsForm);

        // 错误条（HAP：! 圆点 + 文案）
        errorView = Ui.label(this, "", 12f, Ui.danger);
        errorView.setPadding(0, Ui.dpInt(this, 10), 0, 0);
        errorView.setVisibility(View.GONE);
        card.addView(errorView);

        // 协议勾选（HAP：圆点 + 「我已阅读并同意…」）
        LinearLayout agree = new LinearLayout(this);
        agree.setOrientation(LinearLayout.HORIZONTAL);
        agree.setGravity(Gravity.CENTER_VERTICAL);
        agree.setPadding(0, Ui.dpInt(this, 14), 0, 0);
        agreeBox = new CheckBox(this);
        agreeBox.setText("");
        agreeBox.setChecked(true);
        agree.addView(agreeBox, new LinearLayout.LayoutParams(Ui.dpInt(this, 34),
                Ui.dpInt(this, 34)));
        agree.addView(Ui.label(this, Ui.t("我已阅读并同意《用户协议》和《隐私政策》",
                "I agree to the Terms and Privacy Policy"), 10.5f, Ui.textSub));

        String lastUser = Store.get().getPlatformUserName();
        if (lastUser.length() > 0) {
            accountField.setText(lastUser);
        }

        LinearLayout.LayoutParams cardLp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        cardLp.topMargin = Ui.dpInt(this, 4);
        root.addView(card, cardLp);
        root.addView(agree);

        TextView note = Ui.label(this,
                Ui.t("非官方客户端 · 凭据只保存在本机，不会上传",
                        "Unofficial client · credentials stay on this device"),
                10.5f, Ui.textFaint);
        note.setGravity(Gravity.CENTER);
        note.setPadding(0, Ui.dpInt(this, 18), 0, 0);
        root.addView(note);

        setContentView(scroll);
    }

    private TextView tab(Context context, String text, boolean active) {
        TextView tv = Ui.label(context, text, 12.5f, active ? Ui.text : Ui.textSub);
        tv.setGravity(Gravity.CENTER);
        tv.setPadding(0, Ui.dpInt(context, 9), 0, Ui.dpInt(context, 9));
        if (active) {
            tv.setBackground(Ui.round(Ui.surface, 9, context));
            tv.setTypeface(Typeface.DEFAULT_BOLD);
        }
        return tv;
    }

    private EditText field(String label, String hint, int inputType, boolean multiline) {
        LinearLayout box = new LinearLayout(this);
        box.setOrientation(LinearLayout.VERTICAL);
        box.setPadding(0, 0, 0, Ui.dpInt(this, 12));
        TextView labelView = Ui.label(this, label, 10.5f, Ui.textFaint);
        labelView.setPadding(Ui.dpInt(this, 2), 0, 0, Ui.dpInt(this, 4));
        box.addView(labelView);
        EditText et = new EditText(this);
        et.setHint(hint);
        et.setTextSize(Ui.sp(14f));
        et.setTextColor(Ui.text);
        et.setHintTextColor(Ui.textFaint);
        et.setInputType(inputType);
        et.setSingleLine(!multiline);
        et.setBackground(Ui.round(Ui.surfaceAlt, 12, this));
        et.setPadding(Ui.dpInt(this, 14), Ui.dpInt(this, 12), Ui.dpInt(this, 14),
                Ui.dpInt(this, 12));
        box.addView(et, new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));
        // 外层容器（label + 输入框）记在 map 里，调用方用 fieldBox(et) 取
        boxes.put(et, box);
        return et;
    }

    /** 带 label 的字段容器（HAP 样式）。 */
    private LinearLayout fieldBox(EditText et) {
        LinearLayout box = boxes.get(et);
        if (box == null) {
            box = new LinearLayout(this);
            box.setOrientation(LinearLayout.VERTICAL);
            box.addView(et, new LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));
            boxes.put(et, box);
        }
        return box;
    }

    private void switchMode(boolean sms) {
        smsMode = sms;
        passwordForm.setVisibility(sms ? View.GONE : View.VISIBLE);
        smsForm.setVisibility(sms ? View.VISIBLE : View.GONE);
        passwordTab.setBackground(sms ? null : Ui.round(Ui.surface, 8, this));
        smsTab.setBackground(sms ? Ui.round(Ui.surface, 8, this) : null);
        passwordTab.setTextColor(sms ? Ui.textSub : Ui.text);
        smsTab.setTextColor(sms ? Ui.text : Ui.textSub);
        errorView.setVisibility(View.GONE);
    }

    @Override
    protected void onPause() {
        super.onPause();
        leftForMain = true;
    }

    private void showError(String message) {
        errorView.setText(message);
        errorView.setVisibility(View.VISIBLE);
    }

    private void setBusy(boolean value) {
        busy = value;
        submit.setText(value ? Ui.t("登录中…", "Signing in…") : Ui.t("登录", "Sign in"));
        submit.setAlpha(value ? 0.7f : 1f);
    }

    private void doLogin() {
        if (busy) {
            return;
        }
        errorView.setVisibility(View.GONE);
        if (smsMode) {
            final String phone = phoneField.getText().toString().trim();
            final String code = codeField.getText().toString().trim();
            if (phone.length() == 0 || code.length() == 0) {
                showError(Ui.t("请填手机号和验证码", "Enter phone and code"));
                return;
            }
            setBusy(true);
            Task.run(new Task.Work<Void>() {
                @Override
                public Void run() throws Exception {
                    Auth.get().loginBySmsCode(phone, code);
                    Store.get().setPlatformUserName(phone);
                    return null;
                }
            }, loginCallback());
            return;
        }
        final String account = accountField.getText().toString().trim();
        final String password = passwordField.getText().toString();
        if (account.length() == 0 || password.length() == 0) {
            showError(Ui.t("请填账号和密码", "Enter account and password"));
            return;
        }
        setBusy(true);
        Task.run(new Task.Work<Void>() {
            @Override
            public Void run() throws Exception {
                Auth.get().loginByPassword(account, password);
                return null;
            }
        }, loginCallback());
    }

    /** 跳主界面：成功才 finish；系统静默吞掉 startActivity 时留在登录页并说明原因。 */
    private void goMain() {
        leftForMain = false;
        try {
            android.util.Log.i("SCNetDbg", "login: startActivity(MainActivity)");
            startActivity(new Intent(LoginActivity.this, MainActivity.class));
        } catch (Throwable error) {
            android.util.Log.e("SCNetDbg", "login: startActivity failed: " + error);
            Crash.fatal(this, error);
            return;
        }
        // 若 1.2s 内本页还没被 pause，说明目标页没起来（有的 ROM 会静默拦截）
        new android.os.Handler(android.os.Looper.getMainLooper()).postDelayed(new Runnable() {
            @Override
            public void run() {
                if (leftForMain || isFinishing()) {
                    finish();
                    return;
                }
                android.util.Log.w("SCNetDbg", "login: MainActivity did not come up");
                setBusy(false);
                showError(Ui.t("登录成功，但主界面启动被系统拦截（请检查「应用锁/后台弹出界面」权限）",
                        "Signed in, but the system blocked opening the main screen"));
            }
        }, 1200);
    }

    private Task.Call<Void> loginCallback() {
        return new Task.Call<Void>() {
            @Override
            public void ok(Void value) {
                setBusy(false);
                android.util.Log.i("SCNetDbg", "login: callback ok, token="
                        + cn.scnet.agent.core.Http.mask(cn.scnet.agent.core.Http.token)
                        + " storeToken=" + cn.scnet.agent.core.Http.mask(
                        cn.scnet.agent.core.Store.get().getCloudToken()));
                goMain();
            }

            @Override
            public void fail(String message) {
                setBusy(false);
                android.util.Log.w("SCNetDbg", "login: callback fail: " + message);
                // 网络错误 / 平台错误码都翻译一下
                if (message.contains("network")) {
                    showError(Ui.t("网络错误，检查网络后重试", "Network error"));
                } else {
                    showError(message);
                }
            }
        };
    }

    private void sendSms() {
        final String phone = phoneField.getText().toString().trim();
        if (phone.length() == 0) {
            showError(Ui.t("请先填手机号", "Enter phone first"));
            return;
        }
        smsSend.setEnabled(false);
        Task.run(new Task.Work<Void>() {
            @Override
            public Void run() throws Exception {
                Auth.get().sendSmsCode(phone);
                return null;
            }
        }, new Task.Call<Void>() {
            @Override
            public void ok(Void value) {
                smsSend.setText(Ui.t("已发送", "Sent"));
                Widgets.tip(LoginActivity.this, Ui.t("验证码已发送", "Code sent"));
            }

            @Override
            public void fail(String message) {
                smsSend.setEnabled(true);
                showError(Auth.describe("", message));
            }
        });
    }
}
