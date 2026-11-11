package cn.scnet.agent;

import android.app.Activity;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Context;
import android.content.Intent;
import android.graphics.Typeface;
import android.net.Uri;
import android.os.Bundle;
import android.text.Editable;
import android.text.TextWatcher;
import android.view.Gravity;
import android.view.KeyEvent;
import android.view.View;
import android.view.ViewGroup;
import android.view.inputmethod.EditorInfo;
import android.widget.EditText;
import android.widget.FrameLayout;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;

import java.io.InputStream;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;

import cn.scnet.agent.core.ChatText;
import cn.scnet.agent.core.Md;
import cn.scnet.agent.core.Http;
import cn.scnet.agent.core.Crash;
import cn.scnet.agent.core.Store;
import cn.scnet.agent.core.Task;
import cn.scnet.agent.svc.AgentChat;
import cn.scnet.agent.svc.ApiKeys;
import cn.scnet.agent.svc.Auth;
import cn.scnet.agent.svc.Gateway;
import cn.scnet.agent.svc.Scenarios;
import cn.scnet.agent.svc.Scenes;
import cn.scnet.agent.svc.Sessions;
import cn.scnet.agent.svc.Upload;
import cn.scnet.agent.ui.MdView;
import cn.scnet.agent.ui.Sheet;
import cn.scnet.agent.ui.Ui;
import cn.scnet.agent.ui.Widgets;

/**
 * 对话页（对齐 ArkTS 的 pages/Index.ets）。
 *
 * 结构：顶栏 → 通知/错误卡 → 消息流（Markdown）→ 附件条 → 输入区。
 * 抽屉：账号 / 新对话 / 本地会话 / 平台历史 / 作业 / OCR / 文件 / 市场 / 社区 / 设置 / 退出。
 */
public class MainActivity extends Activity {

    private static final String[] FALLBACK_SUGGEST = {
            "用三句话说明 SLURM 是做什么的",
            "帮我写一个提交 VASP 任务的 sbatch 脚本",
            "HPC 作业排队很久，有哪些常见原因？",
            "解释一下 MPI 和 OpenMP 的区别"
    };

    private static class Msg {
        String role;
        String content;
        String via;

        Msg(String role, String content, String via) {
            this.role = role;
            this.content = content;
            this.via = via == null ? "" : via;
        }
    }

    private final List<Msg> messages = new ArrayList<>();
    private final List<Upload.UploadedFile> attachments = new ArrayList<>();
    private final List<Auth.Conversation> conversations = new ArrayList<>();
    private final List<String> gatewayModels = new ArrayList<>();
    private final List<Auth.AgentService> agentServices = new ArrayList<>();
    private final List<Scenes.Tab> sceneTabs = new ArrayList<>();
    private final Scenarios scenarios = Scenarios.get();
    private String sceneTabId = "featured";
    private int sceneOffset;
    private List<String> suggest = Arrays.asList(FALLBACK_SUGGEST);

    private String userName = "";
    private String avatarSpec = "";
    private String apiKey = "";
    private String baseUrl = Store.DEFAULT_BASE_URL;
    private String gatewayModel = Store.DEFAULT_MODEL;
    private String gatewayNotice = "";
    private String channel = "agent";
    private String agentKey = "aiagent-router";
    private int agentModelId;
    private String agentName = "";
    private String streaming = "";
    private String progressText = "";
    private String errorMsg = "";
    private String notice = "";
    private boolean busy;
    private boolean uploading;
    private String currentSessionId = "";
    private String currentCloudId = "";
    /** 智能体会话 id（多轮要带上，否则服务端每次都当新对话） */
    private String agentConversationId = "";
    private String sessionTitle = "";
    private int trimmedCount;
    private long lastRenderAt;
    private String lastAssistantText = "";
    private boolean pendingAutosend;
    /** 本轮服务端下发的资源（图片/文件），结束时拼进回答正文 */
    private final java.util.List<String> turnResources = new ArrayList<>();
    /** 流式渲染时上一次的块结构（用于判断能否只更新最后一块） */
    private List<Md.Block> streamingBlocks = new ArrayList<>();

    private final Gateway gateway = new Gateway();
    private final AgentChat agentChat = new AgentChat();

    // 视图引用
    private FrameLayout root;
    private LinearLayout messagesBox;
    private ScrollView messageScroll;
    private LinearLayout banner;
    private LinearLayout attachRow;
    private EditText input;
    private TextView sendButton;
    private TextView statusLabel;
    private TextView titleLabel;
    private LinearLayout emptyState;
    private View drawerScrim;
    private LinearLayout drawerPanel;
    private LinearLayout drawerSessions;
    private boolean drawerOpen;
    private View streamingBubble;
    private LinearLayout streamingBox;
    private TextView streamingMeta;
    private TextView progressLabel;
    private LinearLayout traceBox;
    private final java.util.List<String> trace = new ArrayList<>();
    private long attachBusyAt;
    /** 长会话只渲染最近这么多条，更早的点按钮再加载（对齐 HAP 的 LazyForEach 体验） */
    private static final int WINDOW = 40;
    private int windowStart = 0;
    private long lastUnauthorizedAt;

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        Store.init(this);
        Crash.install(this);
        Crash.showIfAny(this);
        // 整段启动逻辑兜住：出异常就把堆栈铺在屏幕上（容器里没有 adb，只能这样取信息）
        Crash.guard(this, new Runnable() {
            @Override
            public void run() {
                boot();
            }
        });
    }

    private void boot() {
        Crash.stage(this, "boot: start");
        applyAppearance();
        Http.setUnauthorizedHandler(new Http.UnauthorizedHandler() {
            @Override
            public void onUnauthorized() {
                // 可能是网络线程回调过来的，必须切主线程再动 UI
                Task.onMain(new Runnable() {
                    @Override
                    public void run() {
                        long now = System.currentTimeMillis();
                        if (now - lastUnauthorizedAt < 3000) {
                            return; // 去抖：并发请求会连续 401
                        }
                        lastUnauthorizedAt = now;
                        Auth.get().noteSessionExpired();
                        Widgets.tip(MainActivity.this,
                                Ui.t("登录已过期，请重新登录", "Session expired, sign in again"));
                        try {
                            startActivity(new Intent(MainActivity.this, LoginActivity.class)
                                    .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP));
                        } catch (Throwable error) {
                            Crash.fatal(MainActivity.this, error);
                            return;
                        }
                        finish();
                    }
                });
            }
        });
        Sessions.get().init(this);
        scenarios.load(this);

        boolean restored = Auth.get().restore();
        Crash.stage(this, "boot: restore=" + restored + " token="
                + Http.mask(Http.token));
        if (!restored) {
            startActivity(new Intent(this, LoginActivity.class));
            finish();
            return;
        }
        apiKey = Store.get().getApiKey();
        baseUrl = Store.get().getBaseUrl();
        gatewayModel = Store.get().getModel();
        channel = Store.get().getChannel();
        agentKey = Store.get().getAgent();
        avatarSpec = Store.get().getAvatar();
        userName = Store.get().getPlatformUserName();

        buildUi();
        Crash.stage(this, "boot: ui built");
        openLatestSession();
        Crash.stage(this, "boot: session opened (" + messages.size() + " msgs)");
        loadCloud();
        // 调试用：清空当前会话（--ez newchat true），配合 mdfile/mdtest 干净验证渲染
        if (getIntent() != null && getIntent().getBooleanExtra("newchat", false)) {
            messages.clear();
            currentSessionId = "";
            sessionTitle = "";
            windowStart = 0;
            agentConversationId = "";
            agentChat.conversationId = "";
        }
        // 调试用：从 files/md.txt 读 markdown 渲染（--ez mdfile true），避免命令行转义问题
        if (getIntent() != null && getIntent().getBooleanExtra("mdfile", false)) {
            Task.onMain(new Runnable() {
                @Override
                public void run() {
                    try {
                        java.io.File f = new java.io.File(getExternalFilesDir(null), "md.txt");
                        java.io.FileInputStream in = new java.io.FileInputStream(f);
                        byte[] buf = new byte[(int) f.length()];
                        int off = 0;
                        int n;
                        while (off < buf.length && (n = in.read(buf, off, buf.length - off)) > 0) {
                            off += n;
                        }
                        in.close();
                        messages.add(new Msg("assistant", new String(buf, 0, off, "UTF-8"),
                                "md file"));
                        renderMessages();
                        scrollToEnd();
                    } catch (Throwable e) {
                        messages.add(new Msg("assistant", "read md.txt failed: " + e, "md file"));
                        renderMessages();
                    }
                }
            });
        }
        // 调试用：渲染任意 markdown 文本（--es mdtext "…"）
        if (getIntent() != null && getIntent().getStringExtra("mdtext") != null) {
            final String md = getIntent().getStringExtra("mdtext");
            Task.onMain(new Runnable() {
                @Override
                public void run() {
                    messages.add(new Msg("assistant", md, "mdtext"));
                    renderMessages();
                    scrollToEnd();
                }
            });
        }
        if (getIntent() != null && getIntent().getBooleanExtra("mdtest", false)) {
            Task.onMain(new Runnable() {
                @Override
                public void run() {
                    messages.add(new Msg("assistant", Ui.t(
                            "# 图片渲染自检\n\n下面是行内图片：\n\n![logo](https://www.baidu.com/img/flexible/logo/pc/result.png)\n\n"
                                    + "再一张单独成行的：\n\n![png](https://www.baidu.com/img/flexible/logo/pc/result@2.png)\n\n"
                                    + "| 列 | 值 |\n|---|---|\n| A | 1 |\n\n```bash\necho ok\n```\n",
                            "# Image render test\n\n![logo](https://www.baidu.com/img/flexible/logo/pc/result.png)\n"),
                            "mdtest"));
                    renderMessages();
                    scrollToEnd();
                }
            });
        }
        if (getIntent() != null && getIntent().getStringExtra("open") != null) {
            final String page = getIntent().getStringExtra("open");
            Task.onMain(new Runnable() {
                @Override
                public void run() {
                    Crash.stage(MainActivity.this, "deep-link open=" + page);
                    openPage(page);
                }
            });
        }
        if (getIntent() != null && getIntent().getStringExtra("prefill") != null) {
            input.setText(getIntent().getStringExtra("prefill"));
            input.setSelection(input.getText().length());
        }
        // 调试用：直接打开某个平台会话（--es convid <id>），便于验证历史里的图片渲染
        if (getIntent() != null && getIntent().getStringExtra("convid") != null) {
            final String cid = getIntent().getStringExtra("convid");
            Task.onMain(new Runnable() {
                @Override
                public void run() {
                    openCloudConversation(cid);
                }
            });
        }
        // 调试用：把平台历史的原始 JSON 落盘（排查图片/资源字段）
        if (getIntent() != null && getIntent().getBooleanExtra("dumphistory", false)) {
            dumpHistory();
        }
        // 调试用：自动发一条（配合 --es prefill）；延后到云端加载完成，避免"没有可用通道"
        if (getIntent() != null && getIntent().getBooleanExtra("autosend", false)) {
            pendingAutosend = true;
        }
    }

    private void applyAppearance() {
        String mode = Store.get().getColorMode();
        boolean dark = "dark".equals(mode) || ("system".equals(mode) && isSystemDark());
        Ui.apply(Store.get().getTheme(), dark);
        int level = Store.get().getFontLevel();
        Ui.fontScale = level == 0 ? 0.9f : (level == 2 ? 1.15f : 1f);
        Ui.zh = !"en".equals(Store.get().getLang());
    }

    private boolean isSystemDark() {
        int night = getResources().getConfiguration().uiMode
                & android.content.res.Configuration.UI_MODE_NIGHT_MASK;
        return night == android.content.res.Configuration.UI_MODE_NIGHT_YES;
    }

    @Override
    protected void onResume() {
        super.onResume();
        if (root == null) {
            return;
        }
        Crash.stage(this, "onResume");
        Crash.guard(this, new Runnable() {
            @Override
            public void run() {
                onResumed();
            }
        });
    }

    private void onResumed() {
        // 从设置页回来：外观 / 头像可能改了
        String mode = Store.get().getColorMode();
        boolean wantDark = "dark".equals(mode) || ("system".equals(mode) && isSystemDark());
        String wantTheme = Store.get().getTheme();
        int level = Store.get().getFontLevel();
        float wantScale = level == 0 ? 0.9f : (level == 2 ? 1.15f : 1f);
        if (wantDark != Ui.dark || !wantTheme.equals(Ui.paletteId) || wantScale != Ui.fontScale) {
            applyAppearance();
            rebuildUi();
            return;
        }
        avatarSpec = Store.get().getAvatar();
        userName = Store.get().getPlatformUserName();
        if (titleLabel != null) {
            titleLabel.setText(Ui.t("超级计算智能体", "SCNet Supercomputing"));
        }
        refreshDrawer();
    }

    // ---------------------------------------------------------------- 骨架

    private void buildUi() {
        root = new FrameLayout(this);
        root.setBackgroundColor(Ui.bg);

        LinearLayout content = new LinearLayout(this);
        content.setOrientation(LinearLayout.VERTICAL);
        content.setBackgroundColor(Ui.bg);

        LinearLayout bar = Widgets.topBar(this, Ui.t("超级计算智能体", "SCNet Supercomputing"),
                "", "☰", new Widgets.Action() {
                    @Override
                    public void run() {
                        toggleDrawer(true);
                    }
                }, Widgets.avatar(this, userName, avatarSpec, 32, new Widgets.Action() {
                    @Override
                    public void run() {
                        startActivity(new Intent(MainActivity.this, ProfileActivity.class));
                    }
                }));
        titleLabel = (TextView) ((LinearLayout) bar.getChildAt(1)).getChildAt(0);
        statusLabel = (TextView) ((LinearLayout) bar.getChildAt(1)).getChildAt(1);
        content.addView(bar);

        statusLabel.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                showModelSheet();
            }
        });
        titleLabel.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                showModelSheet();
            }
        });

        banner = new LinearLayout(this);
        banner.setOrientation(LinearLayout.VERTICAL);
        banner.setVisibility(View.GONE);
        content.addView(banner);

        messageScroll = new ScrollView(this);
        messageScroll.setFillViewport(true);
        messagesBox = new LinearLayout(this);
        messagesBox.setOrientation(LinearLayout.VERTICAL);
        int pad = Ui.dpInt(this, 14);
        messagesBox.setPadding(pad, pad, pad, pad);
        messageScroll.addView(messagesBox);
        content.addView(messageScroll, new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f));

        attachRow = new LinearLayout(this);
        attachRow.setOrientation(LinearLayout.HORIZONTAL);
        attachRow.setPadding(Ui.dpInt(this, 12), Ui.dpInt(this, 4), Ui.dpInt(this, 12), 0);
        attachRow.setVisibility(View.GONE);
        content.addView(attachRow);

        content.addView(buildInputBar());
        root.addView(content, new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT));

        root.addView(buildDrawer());
        setContentView(root);
        renderEmptyState();
        renderBanner();
        refreshStatus();
    }

    private void rebuildUi() {
        root.removeAllViews();
        boolean wasDrawer = drawerOpen;
        buildUi();
        windowStart = Math.max(0, messages.size() - WINDOW);
        renderMessages();
        if (streamingBubble != null) {
            streamingBubble = null;
        }
        if (wasDrawer) {
            toggleDrawer(true);
        }
        scrollToEnd();
    }

    private View buildInputBar() {
        LinearLayout wrap = new LinearLayout(this);
        wrap.setOrientation(LinearLayout.VERTICAL);
        wrap.setBackgroundColor(Ui.bg);
        wrap.setPadding(Ui.dpInt(this, 12), Ui.dpInt(this, 6), Ui.dpInt(this, 12),
                Ui.dpInt(this, 8));

        LinearLayout box = new LinearLayout(this);
        box.setOrientation(LinearLayout.HORIZONTAL);
        box.setGravity(Gravity.BOTTOM);
        box.setBackground(Ui.roundStroke(Ui.surface, Ui.border, 16, this));
        box.setPadding(Ui.dpInt(this, 6), Ui.dpInt(this, 4), Ui.dpInt(this, 4),
                Ui.dpInt(this, 4));

        TextView plus = Widgets.glyphButton(this, "＋", new Widgets.Action() {
            @Override
            public void run() {
                pickAttachment();
            }
        });
        LinearLayout.LayoutParams plusLp = new LinearLayout.LayoutParams(Ui.dpInt(this, 32),
                Ui.dpInt(this, 32));
        plusLp.bottomMargin = Ui.dpInt(this, 2);
        box.addView(plus, plusLp);

        input = new EditText(this);
        input.setHint(Ui.t("问点什么，或说清要做的科研任务…", "Ask anything, or describe a research task…"));
        input.setTextSize(Ui.sp(14.5f));
        input.setTextColor(Ui.text);
        input.setHintTextColor(Ui.textFaint);
        input.setBackgroundColor(0);
        input.setMaxLines(5);
        input.setMinLines(1);
        input.setPadding(Ui.dpInt(this, 8), Ui.dpInt(this, 8), Ui.dpInt(this, 4),
                Ui.dpInt(this, 8));
        input.setOnEditorActionListener(new TextView.OnEditorActionListener() {
            @Override
            public boolean onEditorAction(TextView v, int actionId, KeyEvent event) {
                if (actionId == EditorInfo.IME_ACTION_SEND) {
                    send();
                    return true;
                }
                return false;
            }
        });
        box.addView(input, new LinearLayout.LayoutParams(0,
                ViewGroup.LayoutParams.WRAP_CONTENT, 1f));

        sendButton = new TextView(this);
        sendButton.setText("↑");
        sendButton.setTextSize(Ui.sp(17f));
        sendButton.setTextColor(0xFFFFFFFF);
        sendButton.setGravity(Gravity.CENTER);
        sendButton.setTypeface(Typeface.DEFAULT_BOLD);
        sendButton.setBackground(Ui.round(Ui.accent, 999, this));
        LinearLayout.LayoutParams sendLp = new LinearLayout.LayoutParams(Ui.dpInt(this, 34),
                Ui.dpInt(this, 34));
        box.addView(sendButton, sendLp);
        sendButton.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                if (busy) {
                    stopStreaming();
                } else {
                    send();
                }
            }
        });
        wrap.addView(box);

        TextView footer = Ui.label(this, Ui.t("AI 生成内容可能不准确，请自行核实", "AI output may be inaccurate; verify before use"),
                10.5f, Ui.textFaint);
        footer.setGravity(Gravity.CENTER);
        footer.setPadding(0, Ui.dpInt(this, 6), 0, 0);
        wrap.addView(footer);
        return wrap;
    }

    // ---------------------------------------------------------------- 抽屉

    private View buildDrawer() {
        FrameLayout layer = new FrameLayout(this);
        layer.setLayoutParams(new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT));
        layer.setVisibility(View.GONE);
        layer.setTag("drawerLayer");

        drawerScrim = new View(this);
        drawerScrim.setBackgroundColor(0x99000000);
        drawerScrim.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                toggleDrawer(false);
            }
        });
        layer.addView(drawerScrim, new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT));

        ScrollView scroll = new ScrollView(this);
        drawerPanel = new LinearLayout(this);
        drawerPanel.setOrientation(LinearLayout.VERTICAL);
        drawerPanel.setBackgroundColor(Ui.bg);
        drawerPanel.setPadding(0, Ui.dpInt(this, 16), 0, Ui.dpInt(this, 16));
        scroll.addView(drawerPanel);

        FrameLayout.LayoutParams panelLp = new FrameLayout.LayoutParams(
                Math.min(Ui.dpInt(this, 320), (int) (getResources().getDisplayMetrics().widthPixels * 0.84f)),
                ViewGroup.LayoutParams.MATCH_PARENT);
        layer.addView(scroll, panelLp);
        return layer;
    }

    private void toggleDrawer(boolean open) {
        android.util.Log.d("SCNetDbg", "toggleDrawer(" + open + ")");
        View layer = root == null ? null : root.findViewWithTag("drawerLayer");
        if (layer == null) {
            return;
        }
        drawerOpen = open;
        layer.setVisibility(open ? View.VISIBLE : View.GONE);
        if (open) {
            refreshDrawer();
        }
    }

    private void refreshDrawer() {
        if (drawerPanel == null) {
            return;
        }
        drawerPanel.removeAllViews();

        // ---- 账号行（点头像/名字进设置，✕ 关闭抽屉）
        LinearLayout account = new LinearLayout(this);
        account.setOrientation(LinearLayout.HORIZONTAL);
        account.setGravity(Gravity.CENTER_VERTICAL);
        account.setPadding(Ui.dpInt(this, 16), Ui.dpInt(this, 4), Ui.dpInt(this, 16),
                Ui.dpInt(this, 12));
        View avatar = Widgets.avatar(this, userName, avatarSpec, 42, new Widgets.Action() {
            @Override
            public void run() {
                startActivity(new Intent(MainActivity.this, ProfileActivity.class));
            }
        });
        account.addView(avatar);
        LinearLayout names = new LinearLayout(this);
        names.setOrientation(LinearLayout.VERTICAL);
        names.setPadding(Ui.dpInt(this, 10), 0, 0, 0);
        names.addView(Ui.label(this, userName.length() > 0 ? userName
                : Ui.t("未命名用户", "Unnamed"), 14f, Ui.text));
        names.addView(Ui.label(this, Ui.t("已登录 · 超算互联网", "Signed in · SCNet"),
                10.5f, Ui.textFaint));
        LinearLayout.LayoutParams namesLp = new LinearLayout.LayoutParams(0,
                ViewGroup.LayoutParams.WRAP_CONTENT, 1f);
        account.addView(names, namesLp);
        TextView close = Ui.label(this, "✕", 13f, Ui.textFaint);
        close.setGravity(Gravity.CENTER);
        close.setBackground(Ui.round(Ui.surfaceAlt, 999, this));
        close.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                toggleDrawer(false);
            }
        });
        account.addView(close, new LinearLayout.LayoutParams(Ui.dpInt(this, 28),
                Ui.dpInt(this, 28)));
        drawerPanel.addView(account);

        // ---- ＋ 新对话
        TextView newChat = Widgets.primaryButton(this, Ui.t("＋  新对话", "＋  New chat"), 44,
                new Widgets.Action() {
                    @Override
                    public void run() {
                        newChat();
                    }
                });
        LinearLayout.LayoutParams newLp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        newLp.leftMargin = Ui.dpInt(this, 16);
        newLp.rightMargin = Ui.dpInt(this, 16);
        drawerPanel.addView(newChat, newLp);

        // ---- 服务入口（顺序与 HAP / PC 客户端一致）
        String[][] services = {
                {"HPC", Ui.t("算力服务", "Compute service"),
                        Ui.t("集群 · 队列 · 作业 · 文件", "Clusters · queues · jobs"), "jobs"},
                {"＋", Ui.t("插件", "Plugins"),
                        Ui.t("精选连接器 / 技能", "Featured connectors & skills"), "market"},
                {"AI", Ui.t("AI 社区", "AI community"),
                        Ui.t("领域智能体 / 应用市场", "Domain agents & apps"), "aihub"},
                {"OCR", Ui.t("文字识别", "OCR"),
                        Ui.t("识别 · 文档解析 · 格式转换", "OCR · parse · convert"), "ocr"}
        };
        LinearLayout serviceBox = new LinearLayout(this);
        serviceBox.setOrientation(LinearLayout.VERTICAL);
        serviceBox.setBackground(Ui.round(Ui.surfaceAlt, 9, this));
        LinearLayout.LayoutParams serviceLp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        serviceLp.leftMargin = Ui.dpInt(this, 16);
        serviceLp.rightMargin = Ui.dpInt(this, 16);
        serviceLp.topMargin = Ui.dpInt(this, 12);
        for (final String[] service : services) {
            serviceBox.addView(Widgets.entryRow(this, service[0], service[1], service[2],
                    new Widgets.Action() {
                        @Override
                        public void run() {
                            toggleDrawer(false);
                            openPage(service[3]);
                        }
                    }));
        }
        drawerPanel.addView(serviceBox, serviceLp);

        // ---- 本机会话
        drawerPanel.addView(Widgets.section(this, Ui.t("本机会话", "Local chats")));
        drawerSessions = new LinearLayout(this);
        drawerSessions.setOrientation(LinearLayout.VERTICAL);
        drawerPanel.addView(drawerSessions);

        // ---- 平台历史（带刷新）
        LinearLayout historyHead = new LinearLayout(this);
        historyHead.setOrientation(LinearLayout.HORIZONTAL);
        historyHead.setGravity(Gravity.CENTER_VERTICAL);
        historyHead.setPadding(Ui.dpInt(this, 16), Ui.dpInt(this, 14), Ui.dpInt(this, 16),
                Ui.dpInt(this, 6));
        historyHead.addView(Ui.label(this, Ui.t("平台历史", "Platform history"), 11.5f,
                Ui.textFaint), new LinearLayout.LayoutParams(0,
                ViewGroup.LayoutParams.WRAP_CONTENT, 1f));
        TextView refresh = Ui.label(this, Ui.t("刷新", "Refresh"), 11.5f, Ui.accent);
        refresh.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                Task.run(new Task.Work<List<Auth.Conversation>>() {
                    @Override
                    public List<Auth.Conversation> run() {
                        return Auth.get().conversationList();
                    }
                }, new Task.Call<List<Auth.Conversation>>() {
                    @Override
                    public void ok(List<Auth.Conversation> value) {
                        conversations.clear();
                        conversations.addAll(value);
                        refreshDrawer();
                    }

                    @Override
                    public void fail(String message) {
                        Widgets.tip(MainActivity.this, message);
                    }
                });
            }
        });
        historyHead.addView(refresh);
        drawerPanel.addView(historyHead);

        LinearLayout history = new LinearLayout(this);
        history.setOrientation(LinearLayout.VERTICAL);
        if (conversations.isEmpty()) {
            TextView empty = Ui.label(this, Ui.t("没有平台历史", "No platform history yet"),
                    12f, Ui.textFaint);
            empty.setPadding(Ui.dpInt(this, 16), Ui.dpInt(this, 6), Ui.dpInt(this, 16), 0);
            history.addView(empty);
        }
        for (final Auth.Conversation c : conversations) {
            final String title = c.title.length() > 0 ? c.title : Ui.t("（无标题）", "(untitled)");
            LinearLayout row = Widgets.row(this, title, c.createTime, "",
                    new Widgets.Action() {
                        @Override
                        public void run() {
                            openCloudConversation(c.id);
                        }
                    });
            row.setOnLongClickListener(new View.OnLongClickListener() {
                @Override
                public boolean onLongClick(View v) {
                    Widgets.prompt(MainActivity.this,
                            Ui.t("重命名平台会话", "Rename platform session"), title, "", false,
                            new Widgets.OnText() {
                                @Override
                                public void onText(String value) {
                                    final String next = value.trim();
                                    if (next.length() == 0) {
                                        return;
                                    }
                                    Task.run(new Task.Work<Boolean>() {
                                        @Override
                                        public Boolean run() {
                                            return Auth.get().renameConversation(c.id, next);
                                        }
                                    }, new Task.Call<Boolean>() {
                                        @Override
                                        public void ok(Boolean done) {
                                            Widgets.tip(MainActivity.this, done
                                                    ? Ui.t("已改名", "Renamed")
                                                    : Ui.t("平台不支持改名或失败",
                                                    "Rename failed"));
                                            if (done) {
                                                c.title = next;
                                                refreshDrawer();
                                            }
                                        }

                                        @Override
                                        public void fail(String message) {
                                            Widgets.tip(MainActivity.this, message);
                                        }
                                    });
                                }
                            });
                    return true;
                }
            });
            history.addView(row);
        }
        drawerPanel.addView(history);

        // ---- 设置 / 退出登录
        drawerPanel.addView(Widgets.row(this, Ui.t("设置", "Settings"), "", "",
                new Widgets.Action() {
                    @Override
                    public void run() {
                        toggleDrawer(false);
                        startActivity(new Intent(MainActivity.this, ProfileActivity.class));
                    }
                }));
        drawerPanel.addView(Widgets.row(this, Ui.t("退出登录", "Sign out"), "", "",
                new Widgets.Action() {
                    @Override
                    public void run() {
                        Widgets.confirm(MainActivity.this, Ui.t("退出登录", "Sign out"),
                                Ui.t("确定要退出吗？", "Sign out now?"),
                                Ui.t("退出", "Sign out"), new Widgets.Action() {
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
                                                startActivity(new Intent(MainActivity.this,
                                                        LoginActivity.class)
                                                        .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP));
                                                finish();
                                            }

                                            @Override
                                            public void fail(String message) {
                                            }
                                        });
                                    }
                                });
                    }
                }));

        refreshLocalSessions();
    }

    private String entryEn(String key) {
        switch (key) {
            case "jobs":
                return "Compute jobs";
            case "ocr":
                return "OCR";
            case "files":
                return "Files";
            case "market":
                return "Plugin market";
            case "aihub":
                return "AI community";
            default:
                return "Settings";
        }
    }

    private void refreshLocalSessions() {
        if (drawerSessions == null) {
            return;
        }
        drawerSessions.removeAllViews();
        List<Sessions.Meta> list = Sessions.get().list();
        if (list.isEmpty()) {
            TextView empty = Ui.label(this, Ui.t("还没有本地会话", "No local sessions yet"),
                    12f, Ui.textFaint);
            empty.setPadding(Ui.dpInt(this, 16), Ui.dpInt(this, 6), Ui.dpInt(this, 16), 0);
            drawerSessions.addView(empty);
            return;
        }
        for (final Sessions.Meta meta : list) {
            String sub = meta.count + Ui.t(" 条消息", " messages");
            LinearLayout row = Widgets.row(this, meta.title, sub, "", new Widgets.Action() {
                @Override
                public void run() {
                    openLocalSession(meta.id);
                }
            });
            row.setOnLongClickListener(new View.OnLongClickListener() {
                @Override
                public boolean onLongClick(View v) {
                    final String[] options = {Ui.t("重命名", "Rename"), Ui.t("删除", "Delete")};
                    Sheet.pick(MainActivity.this, meta.title, options, new Sheet.OnPick() {
                        @Override
                        public void onPick(Sheet.Item picked) {
                            if (Ui.t("重命名", "Rename").equals(picked.key)) {
                                Widgets.prompt(MainActivity.this,
                                        Ui.t("重命名会话", "Rename session"), meta.title, "",
                                        false, new Widgets.OnText() {
                                            @Override
                                            public void onText(String value) {
                                                if (value.trim().length() > 0) {
                                                    Sessions.get().rename(meta.id, value.trim());
                                                    refreshLocalSessions();
                                                    if (meta.id.equals(currentSessionId)) {
                                                        sessionTitle = value.trim();
                                                    }
                                                }
                                            }
                                        });
                            } else {
                                Widgets.confirm(MainActivity.this,
                                        Ui.t("删除会话", "Delete session"),
                                        Ui.t("删除后无法恢复，确定吗？",
                                                "This cannot be undone. Continue?"),
                                        Ui.t("删除", "Delete"), new Widgets.Action() {
                                            @Override
                                            public void run() {
                                                Sessions.get().remove(meta.id);
                                                if (meta.id.equals(currentSessionId)) {
                                                    newChat();
                                                }
                                                refreshLocalSessions();
                                            }
                                        });
                            }
                        }
                    });
                    return true;
                }
            });
            drawerSessions.addView(row);
        }
    }

    private void openPage(String key) {
        switch (key) {
            case "jobs":
                startActivity(new Intent(this, JobsActivity.class));
                break;
            case "ocr":
                startActivity(new Intent(this, OcrActivity.class));
                break;
            case "files":
                startActivity(new Intent(this, FilesActivity.class));
                break;
            case "market":
                startActivity(new Intent(this, MarketActivity.class));
                break;
            case "aihub":
                startActivity(new Intent(this, AiHubActivity.class));
                break;
            default:
                startActivity(new Intent(this, ProfileActivity.class));
                break;
        }
    }

    // ---------------------------------------------------------------- 云侧

    private void loadCloud() {
        Task.run(new Task.Work<Void>() {
            @Override
            public Void run() {
                try {
                    Auth.UserInfo me = Auth.get().refreshUser();
                    userName = me.fullName.length() > 0 ? me.fullName : me.userName;
                    if (me.userName.length() > 0) {
                        Store.get().setPlatformUserName(me.userName);
                    }
                } catch (Exception ignored) {
                }
                try {
                    Auth.ChatConfig cfg = Auth.get().chatConfig();
                    if (cfg.recommend.length > 0) {
                        List<String> list = new ArrayList<>();
                        for (int i = 0; i < cfg.recommend.length && i < 4; i++) {
                            if (cfg.recommend[i].length() > 0) {
                                list.add(cfg.recommend[i]);
                            }
                        }
                        if (!list.isEmpty()) {
                            suggest = list;
                        }
                    }
                } catch (Exception ignored) {
                }
                try {
                    agentServices.clear();
                    agentServices.addAll(Auth.get().agentServices());
                } catch (Exception ignored) {
                }
                try {
                    ApiKeys.Access access = ApiKeys.get().ensureAccess(Auth.get().clusterIdentity());
                    if (access.key.length() > 0) {
                        apiKey = access.key;
                        baseUrl = access.baseUrl;
                        gatewayModels.clear();
                        gatewayModels.addAll(ApiKeys.get().listModels(baseUrl, apiKey));
                        gatewayModel = pickModel(gatewayModels, gatewayModel);
                        Store.get().setModel(gatewayModel);
                    }
                    if (ApiKeys.get().lastBlocked.length() > 0) {
                        gatewayNotice = ApiKeys.get().lastBlocked;
                    }
                } catch (Exception ignored) {
                }
                try {
                    Scenes.Board board = Scenes.get().load();
                    sceneTabs.clear();
                    sceneTabs.addAll(board.tabs);
                } catch (Exception ignored) {
                }
                conversations.clear();
                conversations.addAll(Auth.get().conversationList());
                return null;
            }
        }, new Task.Call<Void>() {
            @Override
            public void ok(Void value) {
                Crash.stage(MainActivity.this, "cloud: loaded");
                try {
                    applySelection();
                    refreshStatus();
                    refreshIdentity();
                    renderEmptyState();
                    refreshDrawer();
                    renderBanner();
                    if (pendingAutosend) {
                        pendingAutosend = false;
                        Crash.stage(MainActivity.this, "autosend after cloud loaded");
                        send();
                    }
                } catch (Throwable error) {
                    errorMsg = Ui.t("界面渲染出错：", "Render error: ") + error;
                    try {
                        renderBanner();
                    } catch (Throwable ignored) {
                    }
                    Crash.fatal(MainActivity.this, error);
                }
            }

            @Override
            public void fail(String message) {
                refreshStatus();
            }
        });
    }

    /** 调试：把最近一个会话的原始 history JSON 与全部 URL 落盘。 */
    private void dumpHistory() {
        Task.run(new Task.Work<String>() {
            @Override
            public String run() {
                List<Auth.Conversation> list = Auth.get().conversationList();
                StringBuilder sb = new StringBuilder();
                sb.append("conversations=").append(list.size()).append('\n');
                int shown = 0;
                for (Auth.Conversation c : list) {
                    if (shown >= 3) {
                        break;
                    }
                    Auth.get().loadHistory(c.id);
                    String raw = Auth.get().lastHistoryRaw;
                    sb.append("---- conv ").append(c.id).append(" len=").append(raw.length())
                            .append(" ----\n");
                    sb.append(raw.length() > 6000 ? raw.substring(0, 6000) + "…" : raw)
                            .append('\n');
                    shown++;
                }
                return sb.toString();
            }
        }, new Task.Call<String>() {
            @Override
            public void ok(String value) {
                cn.scnet.agent.core.StreamLog.event(MainActivity.this, "HISTORY DUMP\n" + value);
            }

            @Override
            public void fail(String message) {
                cn.scnet.agent.core.StreamLog.event(MainActivity.this, "HISTORY DUMP failed: "
                        + message);
            }
        });
    }

    /** 拿到用户信息后刷新顶栏头像（登录时还不知道显示名）。 */
    private void refreshIdentity() {
        String name = Store.get().getPlatformUserName();
        String avatar = Store.get().getAvatar();
        if (name.equals(userName) && avatar.equals(avatarSpec)) {
            return;
        }
        userName = name;
        avatarSpec = avatar;
        if (root == null || root.getChildCount() == 0) {
            return;
        }
        View content = root.getChildAt(0);
        if (!(content instanceof LinearLayout)) {
            return;
        }
        LinearLayout column = (LinearLayout) content;
        View oldBar = column.getChildAt(0);
        LinearLayout newBar = Widgets.topBar(this,
                Ui.t("超级计算智能体", "SCNet Supercomputing"), "", "☰",
                new Widgets.Action() {
                    @Override
                    public void run() {
                        toggleDrawer(true);
                    }
                }, Widgets.avatar(this, userName, avatarSpec, 32, new Widgets.Action() {
                    @Override
                    public void run() {
                        startActivity(new Intent(MainActivity.this, ProfileActivity.class));
                    }
                }));
        column.removeView(oldBar);
        column.addView(newBar, 0);
        titleLabel = (TextView) ((LinearLayout) newBar.getChildAt(1)).getChildAt(0);
        statusLabel = (TextView) ((LinearLayout) newBar.getChildAt(1)).getChildAt(1);
        statusLabel.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                showModelSheet();
            }
        });
        titleLabel.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                showModelSheet();
            }
        });
        refreshStatus();
    }

    private void applySelection() {
        boolean agentExists = false;
        for (Auth.AgentService s : agentServices) {
            if ("aiagent-router".equals(s.identify) && s.modelId > 0) {
                agentExists = true;
                if (agentModelId == 0) {
                    agentModelId = s.modelId;
                    agentName = s.name;
                }
                if (agentKey.equals(s.identify)) {
                    agentModelId = s.modelId;
                    agentName = s.name;
                }
                break;
            }
        }
        if (!agentExists) {
            agentModelId = 0;
            agentName = "";
        }
        if ("agent".equals(channel) && agentModelId == 0 && !gatewayModels.isEmpty()) {
            channel = "llm";
        }
        if ("llm".equals(channel) && gatewayModels.isEmpty() && agentModelId > 0) {
            channel = "agent";
        }
        Store.get().setChannel(channel);
        Store.get().setModel(gatewayModel);
        Store.get().setAgent(agentKey);
    }

    private String pickModel(List<String> list, String preferred) {
        if (preferred != null && preferred.length() > 0 && list.contains(preferred)) {
            return preferred;
        }
        if (list.contains(Store.DEFAULT_MODEL)) {
            return Store.DEFAULT_MODEL;
        }
        return list.isEmpty() ? preferred : list.get(0);
    }

    private String currentLabel() {
        if ("custom".equals(Store.get().getModelProvider())) {
            String name = Store.get().getCustomName();
            return name.length() > 0 ? name : Ui.t("自定义", "Custom");
        }
        if ("agent".equals(channel)) {
            return agentName.length() > 0 ? agentName : Ui.t("智能体服务", "Agent service");
        }
        return ChatText.prettyModel(gatewayModel);
    }

    private void refreshStatus() {
        if (statusLabel == null) {
            return;
        }
        boolean ready = "custom".equals(Store.get().getModelProvider())
                ? Store.get().getCustomBaseUrl().length() > 0 : apiKey.length() > 0;
        statusLabel.setText((ready ? "● " : "○ ") + (ready
                ? Ui.t("网关已就绪", "Gateway ready")
                : Ui.t("未就绪", "Not ready")) + " · " + currentLabel());
        statusLabel.setTextColor(ready ? Ui.ok : Ui.textFaint);
    }

    // ---------------------------------------------------------------- 消息渲染

    private void renderEmptyState() {
        if (messagesBox == null) {
            return;
        }
        if (!messages.isEmpty()) {
            removeEmptyState();
            return;
        }
        removeEmptyState();
        emptyState = new LinearLayout(this);
        emptyState.setOrientation(LinearLayout.VERTICAL);
        emptyState.setPadding(0, Ui.dpInt(this, 12), 0, Ui.dpInt(this, 12));

        TextView head = Ui.label(this, Ui.t("有什么可以帮你？", "How can I help?"), 20f, Ui.text);
        head.setTypeface(Typeface.DEFAULT_BOLD);
        emptyState.addView(head);
        TextView sub = Ui.label(this, Ui.t("选一个场景直接开始，或在下面输入任务。",
                "Pick a scenario to start, or type a task below."), 12.5f, Ui.textFaint);
        sub.setPadding(0, Ui.dpInt(this, 4), 0, Ui.dpInt(this, 10));
        emptyState.addView(sub);

        // 场景 tab（服务端 config 的 vibeCodingScenes × router 推荐问题）+ 领域场景入口
        boolean hasSceneTabs = !sceneTabs.isEmpty();
        if (hasSceneTabs || !scenarios.list().isEmpty()) {
            LinearLayout cats = new LinearLayout(this);
            cats.setOrientation(LinearLayout.HORIZONTAL);
            cats.setPadding(0, 0, 0, Ui.dpInt(this, 8));
            for (final Scenes.Tab tab : sceneTabs) {
                boolean active = tab.id.equals(sceneTabId);
                TextView chip = Widgets.chip(this, tab.title,
                        active ? 0xFFFFFFFF : Ui.textSub, active ? Ui.accent : Ui.surface);
                LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(
                        ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT);
                lp.rightMargin = Ui.dpInt(this, 6);
                chip.setOnClickListener(new View.OnClickListener() {
                    @Override
                    public void onClick(View v) {
                        sceneTabId = tab.id;
                        sceneOffset = 0;
                        renderEmptyState();
                    }
                });
                cats.addView(chip, lp);
            }
            // 领域场景（scenarios.json 的 7 类 32 项）
            if (!scenarios.list().isEmpty()) {
                final Scenarios.Category first = scenarios.list().get(0);
                TextView more = Widgets.chip(this, Ui.t("领域场景 ›", "Scenarios ›"),
                        Ui.accent, Ui.accentSoft);
                more.setOnClickListener(new View.OnClickListener() {
                    @Override
                    public void onClick(View v) {
                        showScenarios(first);
                    }
                });
                cats.addView(more);
            }
            android.widget.HorizontalScrollView hsv = new android.widget.HorizontalScrollView(this);
            hsv.setHorizontalScrollBarEnabled(false);
            hsv.addView(cats);
            emptyState.addView(hsv);
        }

        // 推荐问题 / 场景问题
        List<String> questions = visibleQuestions();
        if (questions.size() > 3) {
            LinearLayout row = new LinearLayout(this);
            row.setOrientation(LinearLayout.HORIZONTAL);
            row.setPadding(0, 0, 0, Ui.dpInt(this, 6));
            TextView hint = Ui.label(this, Ui.t("换一批试试", "Try another batch"), 11.5f,
                    Ui.textFaint);
            row.addView(hint, new LinearLayout.LayoutParams(0,
                    ViewGroup.LayoutParams.WRAP_CONTENT, 1f));
            TextView shuffle = Widgets.ghostButton(this, Ui.t("换一批", "Shuffle"),
                    new Widgets.Action() {
                        @Override
                        public void run() {
                            sceneOffset = (sceneOffset + 3) % Math.max(1,
                                    currentQuestionCount());
                            renderEmptyState();
                        }
                    });
            row.addView(shuffle);
            emptyState.addView(row);
        }
        for (final String question : questions) {
            LinearLayout card = Widgets.card(this);
            TextView tv = Ui.label(this, question, 13.5f, Ui.text);
            tv.setMaxLines(3);
            card.addView(tv);
            LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
            lp.bottomMargin = Ui.dpInt(this, 8);
            card.setOnClickListener(new View.OnClickListener() {
                @Override
                public void onClick(View v) {
                    input.setText(question);
                    send();
                }
            });
            emptyState.addView(card, lp);
        }
        messagesBox.addView(emptyState);
    }

    private int currentQuestionCount() {
        for (Scenes.Tab tab : sceneTabs) {
            if (tab.id.equals(sceneTabId)) {
                return tab.questions.size();
            }
        }
        return suggest.size();
    }

    private List<String> visibleQuestions() {
        for (Scenes.Tab tab : sceneTabs) {
            if (tab.id.equals(sceneTabId) && !tab.questions.isEmpty()) {
                List<String> out = new ArrayList<>();
                for (int i = 0; i < 3 && i < tab.questions.size(); i++) {
                    out.add(tab.questions.get((sceneOffset + i) % tab.questions.size()));
                }
                return out;
            }
        }
        return suggest.size() > 4 ? suggest.subList(0, 4) : suggest;
    }

    private void removeEmptyState() {
        if (emptyState != null) {
            messagesBox.removeView(emptyState);
            emptyState = null;
        }
    }

    private void showScenarios(final Scenarios.Category category) {
        List<Sheet.Item> items = new ArrayList<>();
        for (Scenarios.Item item : category.items) {
            items.add(new Sheet.Item("", item.id, item.title,
                    item.summary + (item.inputCount > 0
                            ? " · " + Ui.t("附件 " + item.inputCount, item.inputCount + " files") : ""),
                    false, false));
        }
        Sheet.show(this, category.title, items, new Sheet.OnPick() {
            @Override
            public void onPick(Sheet.Item picked) {
                for (Scenarios.Item item : category.items) {
                    if (item.id.equals(picked.key)) {
                        input.setText(item.toPrompt());
                        send();
                        return;
                    }
                }
            }
        }, true, null);
    }

    private void addBubble(final Msg msg) {
        removeEmptyState();
        boolean user = "user".equals(msg.role);
        LinearLayout cell = new LinearLayout(this);
        cell.setOrientation(LinearLayout.VERTICAL);
        LinearLayout.LayoutParams cellLp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        cellLp.bottomMargin = Ui.dpInt(this, 12);
        cell.setLayoutParams(cellLp);

        LinearLayout bubble = new LinearLayout(this);
        bubble.setOrientation(LinearLayout.VERTICAL);
        bubble.setPadding(Ui.dpInt(this, 12), Ui.dpInt(this, 10), Ui.dpInt(this, 12),
                Ui.dpInt(this, 10));

        if (user) {
            TextView tv = Ui.label(this, msg.content, 14.5f, Ui.text);
            tv.setLineSpacing(Ui.dp(this, 3), 1f);
            bubble.addView(tv);
            bubble.setBackground(Ui.round(Ui.accentSoft, 14, this));
            LinearLayout.LayoutParams bLp = new LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT);
            bLp.gravity = Gravity.END;
            bLp.leftMargin = Ui.dpInt(this, 40);
            cell.addView(bubble, bLp);
        } else {
            LinearLayout box = new LinearLayout(this);
            box.setOrientation(LinearLayout.VERTICAL);
            MdView.render(this, box, msg.content);
            bubble.addView(box);
            bubble.setBackground(Ui.round(Ui.surface, 14, this));
            LinearLayout.LayoutParams bLp = new LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
            bLp.rightMargin = Ui.dpInt(this, 8);
            cell.addView(bubble, bLp);
            if (msg.via.length() > 0) {
                TextView meta = Ui.label(this, msg.via, 10.5f, Ui.textFaint);
                meta.setPadding(Ui.dpInt(this, 6), Ui.dpInt(this, 4), 0, 0);
                cell.addView(meta);
            }
        }

        final String copyText = msg.content;
        bubble.setOnLongClickListener(new View.OnLongClickListener() {
            @Override
            public boolean onLongClick(View v) {
                ClipboardManager cm = (ClipboardManager) getSystemService(Context.CLIPBOARD_SERVICE);
                cm.setPrimaryClip(ClipData.newPlainText("message", copyText));
                Toast.makeText(MainActivity.this, Ui.t("已复制", "Copied"), Toast.LENGTH_SHORT).show();
                return true;
            }
        });
        messagesBox.addView(cell);
    }

    private void ensureStreamingBubble() {
        if (streamingBubble != null) {
            return;
        }
        removeEmptyState();
        LinearLayout cell = new LinearLayout(this);
        cell.setOrientation(LinearLayout.VERTICAL);
        LinearLayout.LayoutParams cellLp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        cellLp.bottomMargin = Ui.dpInt(this, 12);
        cell.setLayoutParams(cellLp);

        LinearLayout bubble = new LinearLayout(this);
        bubble.setOrientation(LinearLayout.VERTICAL);
        bubble.setPadding(Ui.dpInt(this, 12), Ui.dpInt(this, 10), Ui.dpInt(this, 12),
                Ui.dpInt(this, 10));
        bubble.setBackground(Ui.round(Ui.surface, 14, this));

        streamingBox = new LinearLayout(this);
        streamingBox.setOrientation(LinearLayout.VERTICAL);
        bubble.addView(streamingBox);
        LinearLayout.LayoutParams bLp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        bLp.rightMargin = Ui.dpInt(this, 8);
        cell.addView(bubble, bLp);

        streamingMeta = Ui.label(this, currentLabel(), 10.5f, Ui.textFaint);
        streamingMeta.setPadding(Ui.dpInt(this, 6), Ui.dpInt(this, 4), 0, 0);
        cell.addView(streamingMeta);

        progressLabel = Ui.label(this, "", 11.5f, Ui.textFaint);
        progressLabel.setPadding(Ui.dpInt(this, 6), Ui.dpInt(this, 2), 0, 0);
        progressLabel.setVisibility(View.GONE);
        cell.addView(progressLabel);

        // 服务端 harness 的工具轨迹（todolist / tool-*）
        traceBox = new LinearLayout(this);
        traceBox.setOrientation(LinearLayout.VERTICAL);
        traceBox.setPadding(Ui.dpInt(this, 12), Ui.dpInt(this, 6), Ui.dpInt(this, 12),
                Ui.dpInt(this, 6));
        traceBox.setBackground(Ui.round(Ui.surfaceAlt, 10, this));
        traceBox.setVisibility(View.GONE);
        cell.addView(traceBox);

        messagesBox.addView(cell);
        streamingBubble = cell;
        renderStreaming(true);
    }

    /** 把工具轨迹画到气泡下方（最多保留最近 6 条）。 */
    private void renderTrace() {
        if (traceBox == null) {
            return;
        }
        traceBox.removeAllViews();
        traceBox.setVisibility(trace.isEmpty() ? View.GONE : View.VISIBLE);
        int from = Math.max(0, trace.size() - 6);
        for (int i = from; i < trace.size(); i++) {
            TextView line = Ui.label(this, trace.get(i), 10.5f, Ui.textSub);
            line.setSingleLine(true);
            traceBox.addView(line);
        }
    }

    private void renderStreaming(boolean force) {
        if (streamingBox == null) {
            return;
        }
        long now = System.currentTimeMillis();
        if (!force && now - lastRenderAt < 90) {
            return;
        }
        lastRenderAt = now;
        String text = streaming.length() > 0 ? streaming : progressText;
        if (text.length() == 0) {
            text = Ui.t("正在生成…", "Generating…");
        }
        // 流式性能：块结构没变时只改最后一个文本控件，不整段重建（否则长回答会一顿一顿）
        List<Md.Block> blocks = Md.parse(text);
        if (!force && canPatch(blocks)) {
            TextView last = MdView.lastText;
            if (last != null) {
                last.setText(MdView.inline(this, blocks.get(blocks.size() - 1).text, Ui.text));
                streamingBlocks = blocks;
                if (progressLabel != null) {
                    progressLabel.setVisibility(View.GONE);
                }
                scrollToEnd();
                return;
            }
        }
        MdView.render(this, streamingBox, text);
        streamingBlocks = blocks;
        if (progressLabel != null) {
            boolean show = progressText.length() > 0 && streaming.length() == 0;
            progressLabel.setText(progressText);
            progressLabel.setVisibility(show ? View.VISIBLE : View.GONE);
        }
        scrollToEnd();
    }

    /** 新文本与上次的块结构除最后一块外完全一致 → 可以只更新最后一块。 */
    private boolean canPatch(List<Md.Block> next) {
        List<Md.Block> prev = streamingBlocks;
        if (prev == null || prev.size() == 0 || next.size() != prev.size()) {
            return false;
        }
        int last = next.size() - 1;
        int lastKind = next.get(last).kind;
        if (lastKind != Md.P && lastKind != Md.H1 && lastKind != Md.H2 && lastKind != Md.H3
                && lastKind != Md.BULLET && lastKind != Md.ORDERED) {
            return false;
        }
        for (int i = 0; i < last; i++) {
            Md.Block a = prev.get(i);
            Md.Block b = next.get(i);
            if (a.kind != b.kind || !a.text.equals(b.text) || !a.code.equals(b.code)
                    || a.rows.size() != b.rows.size()) {
                return false;
            }
        }
        return true;
    }

    private void clearStreamingBubble() {
        trace.clear();
        traceBox = null;
        streamingBlocks = new ArrayList<>();
        streamingBubble = null;
        streamingBox = null;
        streamingMeta = null;
        progressLabel = null;
    }

    private void scrollToEnd() {
        if (messageScroll == null) {
            return;
        }
        messageScroll.post(new Runnable() {
            @Override
            public void run() {
                messageScroll.fullScroll(View.FOCUS_DOWN);
            }
        });
    }

    private void renderBanner() {
        if (banner == null) {
            return;
        }
        banner.removeAllViews();
        String text = errorMsg.length() > 0 ? errorMsg
                : (notice.length() > 0 ? notice
                : (gatewayNotice.length() > 0 ? gatewayNotice : ""));
        if (text.length() == 0) {
            banner.setVisibility(View.GONE);
            return;
        }
        boolean isError = errorMsg.length() > 0 || gatewayNotice.length() > 0;
        int bg = isError ? Ui.dangerSoft : Ui.accentGhost;
        int fg = isError ? Ui.danger : Ui.textSub;
        LinearLayout card = new LinearLayout(this);
        card.setOrientation(LinearLayout.HORIZONTAL);
        card.setGravity(Gravity.CENTER_VERTICAL);
        card.setBackground(Ui.round(bg, 10, this));
        card.setPadding(Ui.dpInt(this, 12), Ui.dpInt(this, 9), Ui.dpInt(this, 8),
                Ui.dpInt(this, 9));
        TextView tv = Ui.label(this, text, 12f, fg);
        card.addView(tv, new LinearLayout.LayoutParams(0,
                ViewGroup.LayoutParams.WRAP_CONTENT, 1f));
        TextView close = Ui.label(this, "✕", 12f, fg);
        close.setPadding(Ui.dpInt(this, 8), 0, Ui.dpInt(this, 4), 0);
        close.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                errorMsg = "";
                notice = "";
                gatewayNotice = "";
                renderBanner();
            }
        });
        card.addView(close);
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        lp.leftMargin = Ui.dpInt(this, 12);
        lp.rightMargin = Ui.dpInt(this, 12);
        lp.bottomMargin = Ui.dpInt(this, 6);
        banner.addView(card, lp);
        banner.setVisibility(View.VISIBLE);
    }

    // ---------------------------------------------------------------- 发送

    private void send() {
        final String text = input.getText().toString().trim();
        if (text.length() == 0 || busy) {
            return;
        }
        errorMsg = "";
        notice = "";
        input.setText("");
        streaming = "";
        progressText = "";
        busy = true;
        trimmedCount = 0;
        currentCloudId = "";
        final String via = currentLabel();
        messages.add(new Msg("user", text, ""));
        if (windowStart > 0 && messages.size() - windowStart > WINDOW) {
            windowStart = messages.size() - 1;
            renderMessages();
        } else {
            addBubble(messages.get(messages.size() - 1));
        }
        persistSession();
        scrollToEnd();
        updateSendButton();
        ensureStreamingBubble();

        ChatText.Trimmed trimmed = ChatText.trimHistory(buildTurns(messages));
        trimmedCount = trimmed.dropped;
        if (trimmedCount > 0) {
            notice = Ui.t("上下文较长，已省略最近 " + trimmedCount + " 条之前的历史",
                    "Long context: omitted history before the last " + trimmedCount + " messages");
            renderBanner();
        }

        Gateway.Handlers handlers = new Gateway.Handlers() {
            @Override
            public void onDelta(String content, String reasoning) {
                if (content.length() > 0) {
                    streaming += content;
                    progressText = "";
                }
                renderStreaming(false);
            }

            @Override
            public void onProgress(String value) {
                progressText = value;
                renderStreaming(true);
            }

            @Override
            public void onTool(String phase, String name, String detail) {
                String line;
                if ("progress".equals(phase)) {
                    line = (name != null && name.length() > 0 ? name + " · " : "") + detail;
                } else if (phase.endsWith("start")) {
                    line = "▸ " + (name.length() > 0 ? name : "工具");
                } else if (phase.endsWith("available")) {
                    line = "✓ " + (name.length() > 0 ? name : "工具") + " 完成";
                } else {
                    return;
                }
                line = line.trim();
                if (line.length() == 0 || trace.contains(line)) {
                    return;
                }
                trace.add(line);
                renderTrace();
            }

            @Override
            public void onResource(String name, String url, String mime) {
                if (url == null || url.length() == 0) {
                    return;
                }
                if (mime != null && mime.length() > 0 && !mime.startsWith("image/")) {
                    String md = "\n\n[📎 " + (name.length() > 0 ? name : "附件") + "](" + url + ")";
                    streaming += md;
                    turnResources.add(md);
                    renderStreaming(true);
                    return;
                }
                String alt = name.length() > 0 ? name : "图片";
                String md = "\n\n![" + alt + "](" + url + ")";
                streaming += md;
                turnResources.add(md);
                renderStreaming(true);
            }

            @Override
            public void onTitle(String title) {
                sessionTitle = title;
                persistSession();
            }

            @Override
            public void onDone() {
                finishStream(via);
            }

            @Override
            public void onError(String message) {
                errorMsg = message;
                finishStream(via);
            }
        };

        if ("custom".equals(Store.get().getModelProvider())
                && Store.get().getCustomBaseUrl().length() > 0) {
            String customModel = Store.get().getCustomModel();
            gateway.stream(Store.get().getCustomBaseUrl(), Store.get().getCustomApiKey(),
                    customModel.length() > 0 ? customModel : "gpt-4o-mini", trimmed.turns, handlers);
            return;
        }
        agentChat.ctx = this;
        gateway.ctx = this;
        cn.scnet.agent.core.StreamLog.event(this, "=== send via " + via + " ===");
        turnResources.clear();
        if ("agent".equals(channel) && agentModelId > 0) {
            agentChat.conversationId = agentConversationId;
            agentChat.stream(agentModelId, text, new ArrayList<>(attachments), handlers);
            attachments.clear();
            renderAttachments();
            return;
        }
        if (apiKey.length() > 0) {
            gateway.stream(baseUrl, apiKey, gatewayModel, trimmed.turns, handlers);
            return;
        }
        errorMsg = gatewayNotice.length() > 0 ? gatewayNotice : "没有可用通道，请重新登录";
        busy = false;
        updateSendButton();
        clearStreamingBubble();
        renderBanner();
    }

    private void finishStream(String via) {
        lastAssistantText = streaming;
        if (streaming.length() > 0) {
            messages.add(new Msg("assistant", streaming, via));
            if (streamingBubble != null) {
                messagesBox.removeView(streamingBubble);
            }
            addBubble(messages.get(messages.size() - 1));
        } else if (streamingBubble != null) {
            messagesBox.removeView(streamingBubble);
        }
        agentConversationId = agentChat.conversationId;
        cn.scnet.agent.core.StreamLog.finalText(this, via,
                streaming.length() > 0 ? streaming : lastAssistantText);
        streaming = "";
        progressText = "";
        busy = false;
        clearStreamingBubble();
        updateSendButton();
        persistSession();
        renderBanner();
        scrollToEnd();
        // 刷新平台历史（新会话会出现在列表里）
        Task.run(new Task.Work<List<Auth.Conversation>>() {
            @Override
            public List<Auth.Conversation> run() {
                return Auth.get().conversationList();
            }
        }, new Task.Call<List<Auth.Conversation>>() {
            @Override
            public void ok(List<Auth.Conversation> value) {
                conversations.clear();
                conversations.addAll(value);
                refreshLocalSessions();
            }

            @Override
            public void fail(String message) {
            }
        });
    }

    private void stopStreaming() {
        if (!busy) {
            return;
        }
        gateway.cancel();
        agentChat.stop(agentModelId);
        finishStream(currentLabel());
    }

    private void updateSendButton() {
        if (sendButton == null) {
            return;
        }
        sendButton.setText(busy ? "■" : "↑");
        sendButton.setBackground(Ui.round(busy ? Ui.textSub : Ui.accent, 999, this));
    }

    private List<ChatText.Turn> buildTurns(List<Msg> list) {
        List<ChatText.Turn> turns = new ArrayList<>();
        for (Msg m : list) {
            if (m.content.length() > 0) {
                turns.add(new ChatText.Turn(m.role, m.content));
            }
        }
        return turns;
    }

    // ---------------------------------------------------------------- 会话

    private void openLatestSession() {
        List<Sessions.Meta> list = Sessions.get().list();
        if (!list.isEmpty()) {
            openLocalSession(list.get(0).id);
        }
    }

    private void openLocalSession(String id) {
        Sessions.Data data = Sessions.get().load(id);
        if (data == null) {
            return;
        }
        messages.clear();
        for (Sessions.Message m : data.messages) {
            messages.add(new Msg(m.role, m.content, m.via));
        }
        currentSessionId = id;
        currentCloudId = "";
        sessionTitle = data.title;
        agentChat.conversationId = "";
        streaming = "";
        windowStart = Math.max(0, messages.size() - WINDOW);
        renderMessages();
        toggleDrawer(false);
        scrollToEnd();
    }

    /** 按窗口重画消息区（首条是「加载更早」）。 */
    private void renderMessages() {
        if (messagesBox == null) {
            return;
        }
        messagesBox.removeAllViews();
        clearStreamingBubble();
        if (messages.isEmpty()) {
            renderEmptyState();
            return;
        }
        if (windowStart > 0) {
            TextView earlier = Widgets.ghostButton(this,
                    Ui.t("加载更早（还有 " + windowStart + " 条）",
                            "Load earlier (" + windowStart + " more)"),
                    new Widgets.Action() {
                        @Override
                        public void run() {
                            int from = Math.max(0, windowStart - WINDOW);
                            int keep = messages.size() - windowStart;
                            windowStart = from;
                            renderMessages();
                            if (from == 0) {
                                scrollToEnd();
                            } else {
                                // 保持阅读位置：滚到"加载更早"附近
                                messageScroll.post(new Runnable() {
                                    @Override
                                    public void run() {
                                        messageScroll.scrollTo(0,
                                                0);
                                    }
                                });
                            }
                        }
                    });
            LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
            lp.bottomMargin = Ui.dpInt(this, 10);
            messagesBox.addView(earlier, lp);
        }
        for (int i = windowStart; i < messages.size(); i++) {
            addBubble(messages.get(i));
        }
    }

    private void openCloudConversation(final String id) {
        toggleDrawer(false);
        Task.run(new Task.Work<List<Auth.HistoryMessage>>() {
            @Override
            public List<Auth.HistoryMessage> run() {
                return Auth.get().loadHistory(id);
            }
        }, new Task.Call<List<Auth.HistoryMessage>>() {
            @Override
            public void ok(List<Auth.HistoryMessage> value) {
                messages.clear();
                for (Auth.HistoryMessage m : value) {
                    messages.add(new Msg(m.role, m.text, ""));
                }
                currentCloudId = id;
                currentSessionId = "";
                windowStart = Math.max(0, messages.size() - WINDOW);
                renderMessages();
                scrollToEnd();
            }

            @Override
            public void fail(String message) {
                errorMsg = Ui.t("加载会话历史失败", "Failed to load conversation");
                renderBanner();
            }
        });
    }

    private void persistSession() {
        if (messages.isEmpty()) {
            return;
        }
        if (currentSessionId.length() == 0) {
            currentSessionId = Sessions.get().newId();
        }
        Sessions.Data data = new Sessions.Data();
        data.id = currentSessionId;
        data.title = sessionTitle.length() > 0 ? sessionTitle : Sessions.titleFrom(toSessionMessages());
        data.model = currentLabel();
        data.createdAt = System.currentTimeMillis();
        for (Msg m : messages) {
            data.messages.add(new Sessions.Message(m.role, m.content, m.via));
        }
        Sessions.get().save(data);
        refreshLocalSessions();
    }

    private List<Sessions.Message> toSessionMessages() {
        List<Sessions.Message> out = new ArrayList<>();
        for (Msg m : messages) {
            out.add(new Sessions.Message(m.role, m.content, m.via));
        }
        return out;
    }

    private void newChat() {
        messages.clear();
        windowStart = 0;
        messagesBox.removeAllViews();
        clearStreamingBubble();
        streaming = "";
        errorMsg = "";
        streaming = "";
        progressText = "";
        currentCloudId = "";
        currentSessionId = "";
        sessionTitle = "";
        agentConversationId = "";
        agentChat.conversationId = "";
        agentChat.lastTitle = "";
        attachments.clear();
        renderAttachments();
        toggleDrawer(false);
        renderEmptyState();
        renderBanner();
    }

    // ---------------------------------------------------------------- 附件

    private void pickAttachment() {
        // 一步到位：系统文件选择器（*/* 里包含图片，可多选），不再先弹面板分图片/文件
        Intent intent = new Intent(Intent.ACTION_OPEN_DOCUMENT);
        intent.addCategory(Intent.CATEGORY_OPENABLE);
        intent.setType("*/*");
        intent.putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true);
        try {
            startActivityForResult(Intent.createChooser(intent,
                    Ui.t("选择附件", "Choose attachment")), 2001);
        } catch (Exception e) {
            Widgets.tip(this, Ui.t("没有可用的文件选择器", "No file picker available"));
        }
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (requestCode != 2001 || resultCode != RESULT_OK || data == null) {
            return;
        }
        List<Uri> uris = new ArrayList<>();
        ClipData clip = data.getClipData();
        if (clip != null) {
            for (int i = 0; i < clip.getItemCount(); i++) {
                uris.add(clip.getItemAt(i).getUri());
            }
        } else if (data.getData() != null) {
            uris.add(data.getData());
        }
        if (uris.isEmpty()) {
            return;
        }
        if (uris.size() > 3) {
            Widgets.tip(this, Ui.t("一次最多 3 个附件", "Up to 3 attachments"));
            uris = uris.subList(0, 3);
        }
        uploading = true;
        final List<Uri> picked = uris;
        Task.run(new Task.Work<List<Upload.UploadedFile>>() {
            @Override
            public List<Upload.UploadedFile> run() {
                List<Upload.UploadedFile> out = new ArrayList<>();
                for (Uri uri : picked) {
                    String display = displayName(uri);
                    byte[] bytes;
                    try {
                        InputStream in = getContentResolver().openInputStream(uri);
                        bytes = Upload.readAll(in);
                        in.close();
                    } catch (Exception e) {
                        Upload.get().lastError = Ui.t("读取失败：", "Read failed: ") + display;
                        continue;
                    }
                    Upload.UploadedFile file = Upload.get().upload(bytes, display);
                    if (file != null) {
                        out.add(file);
                    }
                }
                return out;
            }
        }, new Task.Call<List<Upload.UploadedFile>>() {
            @Override
            public void ok(List<Upload.UploadedFile> value) {
                uploading = false;
                attachments.addAll(value);
                renderAttachments();
                if (value.isEmpty() && Upload.get().lastError.length() > 0) {
                    errorMsg = Upload.get().lastError;
                    renderBanner();
                }
            }

            @Override
            public void fail(String message) {
                uploading = false;
                errorMsg = message;
                renderBanner();
            }
        });
    }

    private String displayName(Uri uri) {
        String name = uri.getLastPathSegment();
        if (name == null) {
            return "file";
        }
        int slash = name.lastIndexOf('/');
        return slash >= 0 ? name.substring(slash + 1) : name;
    }

    private void renderAttachments() {
        if (attachRow == null) {
            return;
        }
        attachRow.removeAllViews();
        if (attachments.isEmpty() && !uploading) {
            attachRow.setVisibility(View.GONE);
            return;
        }
        attachRow.setVisibility(View.VISIBLE);
        if (uploading) {
            TextView chip = Widgets.chip(this, Ui.t("上传中…", "Uploading…"), Ui.textSub,
                    Ui.surfaceAlt);
            attachRow.addView(chip);
            return;
        }
        for (final Upload.UploadedFile file : attachments) {
            LinearLayout chip = new LinearLayout(this);
            chip.setOrientation(LinearLayout.HORIZONTAL);
            chip.setGravity(Gravity.CENTER_VERTICAL);
            chip.setBackground(Ui.round(Ui.surface, 999, this));
            chip.setPadding(Ui.dpInt(this, 10), Ui.dpInt(this, 5), Ui.dpInt(this, 6),
                    Ui.dpInt(this, 5));
            String label = "📎 " + file.localName + " · " + file.sizeKb + "KB";
            chip.addView(Ui.label(this, label, 11.5f, Ui.textSub));
            TextView close = Ui.label(this, "✕", 11f, Ui.textFaint);
            close.setPadding(Ui.dpInt(this, 6), 0, Ui.dpInt(this, 2), 0);
            close.setOnClickListener(new View.OnClickListener() {
                @Override
                public void onClick(View v) {
                    attachments.remove(file);
                    renderAttachments();
                }
            });
            chip.addView(close);
            LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT);
            lp.rightMargin = Ui.dpInt(this, 6);
            attachRow.addView(chip, lp);
        }
    }

    // ---------------------------------------------------------------- 模型面板

    private void showModelSheet() {
        List<Sheet.Item> items = new ArrayList<>();
        for (Auth.AgentService service : agentServices) {
            if (!"aiagent-router".equals(service.identify) || service.modelId <= 0) {
                continue;
            }
            items.add(new Sheet.Item(Ui.t("智能体服务", "Agent services"), service.identify,
                    service.name, Ui.t("平台运行时 · 领域任务由服务端路由",
                            "Platform runtime · routed server-side"),
                    true, agentModelId == service.modelId && "agent".equals(channel)));
        }
        for (String model : gatewayModels) {
            items.add(new Sheet.Item(Ui.t("模型", "Models"), model, ChatText.prettyModel(model),
                    model, Store.DEFAULT_MODEL.equals(model), !"agent".equals(channel)
                    && gatewayModel.equals(model)));
        }
        if (items.isEmpty()) {
            Widgets.tip(this, Ui.t("还没有拿到可用模型，请检查登录态", "No models yet — check sign-in"));
            return;
        }
        Sheet.show(this, Ui.t("选择通道", "Choose channel"), items, new Sheet.OnPick() {
            @Override
            public void onPick(Sheet.Item item) {
                if (item.key.length() == 0) {
                    return;
                }
                if ("agent".equals(item.group)) {
                    channel = "agent";
                    agentKey = item.key;
                    agentModelId = findAgentModelId(item.key);
                    agentName = item.label;
                    Store.get().setChannel("agent");
                    Store.get().setAgent(item.key);
                } else {
                    channel = "llm";
                    gatewayModel = item.key;
                    Store.get().setChannel("llm");
                    Store.get().setModel(item.key);
                }
                refreshStatus();
            }
        }, true, null);
    }

    private int findAgentModelId(String identify) {
        for (Auth.AgentService s : agentServices) {
            if (s.identify.equals(identify)) {
                return s.modelId;
            }
        }
        return 0;
    }

    @Override
    public void onBackPressed() {
        if (drawerOpen) {
            toggleDrawer(false);
            return;
        }
        super.onBackPressed();
    }
}
