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
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(Ui.dpInt(this, 24), Ui.dpInt(this, 46), Ui.dpInt(this, 24),
                Ui.dpInt(this, 24));

        TextView brand = Ui.label(this, "SCNet", 30f, Ui.accent);
        brand.setTypeface(Typeface.DEFAULT_BOLD);
        root.addView(brand);
        TextView title = Ui.label(this, Ui.t("超级计算智能体", "SCNet Supercomputing"), 19f, Ui.text);
        title.setTypeface(Typeface.DEFAULT_BOLD);
        title.setPadding(0, Ui.dpInt(this, 6), 0, 0);
        root.addView(title);
        TextView subtitle = Ui.label(this,
                Ui.t("登录国家超算互联网账号，直接用平台模型与算力",
                        "Sign in with your SCNet account to use platform models and compute"),
                12.5f, Ui.textFaint);
        subtitle.setPadding(0, Ui.dpInt(this, 6), 0, Ui.dpInt(this, 22));
        root.addView(subtitle);

        // 登录过期提示
        if ("expired".equals(Auth.get().loginReason)) {
            TextView warn = Ui.label(this, Ui.t("登录已过期 · 长时间未使用需要重新登录",
                    "Session expired — please sign in again"), 12f, Ui.warn);
            warn.setBackground(Ui.round(Ui.warn == Ui.warn ? Ui.accentGhost : Ui.accentGhost, 10, this));
            warn.setPadding(Ui.dpInt(this, 12), Ui.dpInt(this, 9), Ui.dpInt(this, 12),
                    Ui.dpInt(this, 9));
            LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
            lp.bottomMargin = Ui.dpInt(this, 14);
            root.addView(warn, lp);
        }

        // Tab
        LinearLayout tabs = new LinearLayout(this);
        tabs.setOrientation(LinearLayout.HORIZONTAL);
        tabs.setBackground(Ui.round(Ui.surfaceAlt, 10, this));
        tabs.setPadding(Ui.dpInt(this, 4), Ui.dpInt(this, 4), Ui.dpInt(this, 4),
                Ui.dpInt(this, 4));
        passwordTab = tab(this, Ui.t("账号密码", "Password"), true);
        smsTab = tab(this, Ui.t("短信验证码", "SMS code"), false);
        tabs.addView(passwordTab, new LinearLayout.LayoutParams(0,
                ViewGroup.LayoutParams.WRAP_CONTENT, 1f));
        tabs.addView(smsTab, new LinearLayout.LayoutParams(0,
                ViewGroup.LayoutParams.WRAP_CONTENT, 1f));
        root.addView(tabs);
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

        // 密码表单
        passwordForm = new LinearLayout(this);
        passwordForm.setOrientation(LinearLayout.VERTICAL);
        passwordForm.setPadding(0, Ui.dpInt(this, 16), 0, 0);
        accountField = field(Ui.t("平台账号", "Account"), InputType.TYPE_CLASS_TEXT, false);
        passwordField = field(Ui.t("密码", "Password"),
                InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_VARIATION_PASSWORD, false);
        passwordForm.addView(accountField);
        passwordForm.addView(passwordField);
        root.addView(passwordForm);

        // 短信表单
        smsForm = new LinearLayout(this);
        smsForm.setOrientation(LinearLayout.VERTICAL);
        smsForm.setPadding(0, Ui.dpInt(this, 16), 0, 0);
        smsForm.setVisibility(View.GONE);
        phoneField = field(Ui.t("手机号", "Phone"), InputType.TYPE_CLASS_PHONE, false);
        LinearLayout row = new LinearLayout(this);
        row.setOrientation(LinearLayout.HORIZONTAL);
        row.setGravity(Gravity.CENTER_VERTICAL);
        codeField = field(Ui.t("验证码", "Code"), InputType.TYPE_CLASS_NUMBER, false);
        row.addView(codeField, new LinearLayout.LayoutParams(0,
                ViewGroup.LayoutParams.WRAP_CONTENT, 1f));
        smsSend = Widgets.ghostButton(this, Ui.t("发送验证码", "Send code"), new Widgets.Action() {
            @Override
            public void run() {
                sendSms();
            }
        });
        LinearLayout.LayoutParams sendLp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        sendLp.leftMargin = Ui.dpInt(this, 8);
        row.addView(smsSend, sendLp);
        smsForm.addView(phoneField);
        smsForm.addView(row);
        root.addView(smsForm);

        String lastUser = Store.get().getPlatformUserName();
        if (lastUser.length() > 0) {
            accountField.setText(lastUser);
        }

        errorView = Ui.label(this, "", 12f, Ui.danger);
        errorView.setPadding(0, Ui.dpInt(this, 10), 0, 0);
        errorView.setVisibility(View.GONE);
        root.addView(errorView);

        submit = Widgets.primaryButton(this, Ui.t("登录", "Sign in"), 46, new Widgets.Action() {
            @Override
            public void run() {
                doLogin();
            }
        });
        LinearLayout.LayoutParams submitLp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        submitLp.topMargin = Ui.dpInt(this, 16);
        root.addView(submit, submitLp);

        TextView note = Ui.label(this,
                Ui.t("非官方客户端 · 凭据只保存在本机，不会上传",
                        "Unofficial client · credentials stay on this device"),
                11f, Ui.textFaint);
        note.setGravity(Gravity.CENTER);
        note.setPadding(0, Ui.dpInt(this, 18), 0, 0);
        root.addView(note);

        scroll.addView(root);
        setContentView(scroll);
    }

    private TextView tab(Context context, String text, boolean active) {
        TextView tv = Ui.label(context, text, 13f, active ? Ui.text : Ui.textSub);
        tv.setGravity(Gravity.CENTER);
        tv.setPadding(0, Ui.dpInt(context, 9), 0, Ui.dpInt(context, 9));
        if (active) {
            tv.setBackground(Ui.round(Ui.surface, 8, context));
            tv.setTypeface(Typeface.DEFAULT_BOLD);
        }
        return tv;
    }

    private EditText field(String hint, int inputType, boolean multiline) {
        EditText et = new EditText(this);
        et.setHint(hint);
        et.setTextSize(Ui.sp(14f));
        et.setTextColor(Ui.text);
        et.setHintTextColor(Ui.textFaint);
        et.setInputType(inputType);
        et.setSingleLine(!multiline);
        et.setBackground(Ui.roundStroke(Ui.surface, Ui.border, 10, this));
        et.setPadding(Ui.dpInt(this, 12), Ui.dpInt(this, 10), Ui.dpInt(this, 12),
                Ui.dpInt(this, 10));
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        lp.bottomMargin = Ui.dpInt(this, 10);
        et.setLayoutParams(lp);
        return et;
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

    private Task.Call<Void> loginCallback() {
        return new Task.Call<Void>() {
            @Override
            public void ok(Void value) {
                setBusy(false);
                try {
                    // 不带 NEW_TASK：容器类环境里跨任务启动最容易出问题
                    startActivity(new Intent(LoginActivity.this, MainActivity.class));
                    finish();
                } catch (Throwable error) {
                    Crash.fatal(LoginActivity.this, error);
                }
            }

            @Override
            public void fail(String message) {
                setBusy(false);
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
