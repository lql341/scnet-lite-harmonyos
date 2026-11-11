package cn.scnet.agent;

import android.app.Activity;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Context;
import android.content.Intent;
import android.graphics.Typeface;
import android.net.Uri;
import android.os.Bundle;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.HorizontalScrollView;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

import java.io.InputStream;
import java.util.ArrayList;
import java.util.List;

import cn.scnet.agent.core.Crash;
import cn.scnet.agent.core.Store;
import cn.scnet.agent.core.Task;
import cn.scnet.agent.svc.Ocr;
import cn.scnet.agent.svc.Upload;
import cn.scnet.agent.ui.Sheet;
import cn.scnet.agent.ui.Ui;
import cn.scnet.agent.ui.Widgets;

/**
 * 文字识别 / 文档解析 / 格式转换（对齐 ArkTS 的 pages/OcrPage.ets）。
 * 走 api.scnet.cn/api/llm/v1，Bearer 用网关 key（登录时已自动取到）。
 */
public class OcrActivity extends Activity {

    private LinearLayout content;
    private TextView resultView;
    private TextView statusView;
    private TextView typeView;
    private int mode; // 0 OCR · 1 文档解析 · 2 格式转换
    private String ocrType = "GENERAL";
    private String convertTarget = Ocr.PDF_TO_WORD;
    private byte[] fileBytes;
    private String fileName = "";
    private String mime = "";
    private String resultText = "";
    private boolean busy;

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
        TextView title = Ui.label(this, Ui.t("文字识别", "OCR"), 17f, Ui.text);
        title.setTypeface(Typeface.DEFAULT_BOLD);
        titles.addView(title);
        titles.addView(Ui.label(this, Ui.t("支持图片与 PDF（证照/票据/手写）",
                "Images and PDF: cards, invoices, handwriting"), 10f, Ui.textFaint));
        bar.addView(titles, new LinearLayout.LayoutParams(0,
                ViewGroup.LayoutParams.WRAP_CONTENT, 1f));

        TextView selfTestTop = new TextView(this);
        selfTestTop.setText(Ui.t("自检", "Test"));
        selfTestTop.setTextSize(Ui.sp(11.5f));
        selfTestTop.setTextColor(Ui.accent);
        selfTestTop.setBackground(Ui.round(Ui.accentGhost, 999, this));
        selfTestTop.setPadding(Ui.dpInt(this, 10), Ui.dpInt(this, 5), Ui.dpInt(this, 10),
                Ui.dpInt(this, 5));
        selfTestTop.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                runSelfTest();
            }
        });
        bar.addView(selfTestTop);
        root.addView(bar);

        ScrollView scroll = new ScrollView(this);
        content = new LinearLayout(this);
        content.setOrientation(LinearLayout.VERTICAL);
        content.setPadding(0, 0, 0, Ui.dpInt(this, 24));
        scroll.addView(content);
        root.addView(scroll, new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f));

        LinearLayout modes = new LinearLayout(this);
        modes.setOrientation(LinearLayout.HORIZONTAL);
        modes.setPadding(Ui.dpInt(this, 14), Ui.dpInt(this, 4), Ui.dpInt(this, 14), 0);
        String[] labels = {Ui.t("通用文字识别", "OCR"), Ui.t("文档解析", "Parse"),
                Ui.t("格式转换", "Convert")};
        for (int i = 0; i < labels.length; i++) {
            final int index = i;
            TextView chip = Widgets.chip(this, labels[i],
                    i == mode ? 0xFFFFFFFF : Ui.textSub, i == mode ? Ui.accent : Ui.surface);
            LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT);
            lp.rightMargin = Ui.dpInt(this, 6);
            chip.setOnClickListener(new View.OnClickListener() {
                @Override
                public void onClick(View v) {
                    mode = index;
                    rebuildContent();
                }
            });
            modes.addView(chip, lp);
        }
        HorizontalScrollView hsv = new HorizontalScrollView(this);
        hsv.setHorizontalScrollBarEnabled(false);
        hsv.addView(modes);
        content.addView(hsv);

        LinearLayout card = Widgets.card(this);
        LinearLayout.LayoutParams cardLp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        cardLp.leftMargin = Ui.dpInt(this, 14);
        cardLp.rightMargin = Ui.dpInt(this, 14);
        cardLp.topMargin = Ui.dpInt(this, 10);

        statusView = Ui.label(this, "", 11.5f, Ui.textFaint);
        card.addView(statusView);
        typeView = Ui.label(this, "", 13f, Ui.accent);
        typeView.setPadding(0, Ui.dpInt(this, 6), 0, Ui.dpInt(this, 6));
        typeView.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                pickType();
            }
        });
        card.addView(typeView);

        LinearLayout actions = new LinearLayout(this);
        actions.setOrientation(LinearLayout.HORIZONTAL);
        actions.addView(Widgets.ghostButton(this, Ui.t("选择文件", "Choose file"),
                new Widgets.Action() {
                    @Override
                    public void run() {
                        pickFile();
                    }
                }), new LinearLayout.LayoutParams(0,
                ViewGroup.LayoutParams.WRAP_CONTENT, 1f));
        TextView run = Widgets.primaryButton(this, Ui.t("开始", "Run"), 42, new Widgets.Action() {
            @Override
            public void run() {
                run();
            }
        });
        LinearLayout.LayoutParams runLp = new LinearLayout.LayoutParams(0,
                ViewGroup.LayoutParams.WRAP_CONTENT, 1f);
        runLp.leftMargin = Ui.dpInt(this, 8);
        actions.addView(run, runLp);
        card.addView(actions);
        content.addView(card, cardLp);

        resultView = Ui.label(this, "", 13f, Ui.text);
        resultView.setTextIsSelectable(true);
        resultView.setLineSpacing(Ui.dp(this, 3), 1f);
        LinearLayout resultCard = Widgets.card(this);
        resultCard.addView(resultView);
        CardHolder holder = new CardHolder(resultCard, cardLp);
        content.addView(resultCard, cardLp);
        resultCard.setTag(holder);
        resultCard.setVisibility(View.GONE);
        resultCardId = resultCard;

        setContentView(root);
        rebuildContent();
    }

    private static class CardHolder {
        final View card;
        final LinearLayout.LayoutParams lp;

        CardHolder(View card, LinearLayout.LayoutParams lp) {
            this.card = card;
            this.lp = lp;
        }
    }

    private View resultCardId;

    private void rebuildContent() {
        rebuildContent(false);
    }

    private void rebuildContent(boolean keepScroll) {
        // 只更新模式相关文案，避免整页重建
        String typeLabel;
        if (mode == 0) {
            typeLabel = Ui.t("识别类型：", "Type: ") + labelOfOcrType(ocrType);
        } else if (mode == 1) {
            typeLabel = Ui.t("文档解析（DOC_MIND）· 支持 PDF/Word/Excel/PPT/图片",
                    "Document parse (DOC_MIND) · PDF/Word/Excel/PPT/images");
        } else {
            typeLabel = Ui.t("转换方向：", "Direction: ") + convertLabel(convertTarget);
        }
        typeView.setText(typeLabel);
        if (statusView.getText().length() == 0) {
            statusView.setText(Ui.t("已登录即可用，识别走平台模型（消耗网关额度）",
                    "Uses the platform model gateway (consumes quota)"));
        }
        if (!keepScroll) {
            refreshResult();
        }
    }

    private String labelOfOcrType(String code) {
        for (Ocr.Type type : Ocr.TYPES) {
            if (type.code.equals(code)) {
                return type.label;
            }
        }
        return code;
    }

    private String convertLabel(String code) {
        switch (code) {
            case Ocr.PDF_TO_WORD:
                return Ui.t("PDF → Word", "PDF → Word");
            case Ocr.PDF_TO_EXCEL:
                return "PDF → Excel";
            case Ocr.PDF_TO_PPT:
                return "PDF → PPT";
            case Ocr.WORD_TO_PDF:
                return "Word → PDF";
            default:
                return code;
        }
    }

    private void pickType() {
        List<Sheet.Item> items = new ArrayList<>();
        if (mode == 0) {
            for (Ocr.Type type : Ocr.TYPES) {
                items.add(new Sheet.Item("", type.code, type.label, "", false,
                        type.code.equals(ocrType)));
            }
        } else if (mode == 2) {
            String[][] targets = {
                    {Ocr.PDF_TO_WORD, "PDF → Word"},
                    {Ocr.PDF_TO_EXCEL, "PDF → Excel"},
                    {Ocr.PDF_TO_PPT, "PDF → PPT"},
                    {Ocr.WORD_TO_PDF, "Word → PDF"}
            };
            for (String[] target : targets) {
                items.add(new Sheet.Item("", target[0], target[1], "", false,
                        target[0].equals(convertTarget)));
            }
        } else {
            Widgets.tip(this, Ui.t("文档解析不需要选类型", "No type needed for parsing"));
            return;
        }
        Sheet.show(this, Ui.t("选择类型", "Choose type"), items, new Sheet.OnPick() {
            @Override
            public void onPick(Sheet.Item item) {
                if (mode == 0) {
                    ocrType = item.key;
                } else {
                    convertTarget = item.key;
                }
                rebuildContent(true);
            }
        }, false, null);
    }

    private void pickFile() {
        Intent intent = new Intent(Intent.ACTION_OPEN_DOCUMENT);
        intent.addCategory(Intent.CATEGORY_OPENABLE);
        intent.setType("*/*");
        try {
            startActivityForResult(Intent.createChooser(intent,
                    Ui.t("选择文件", "Choose file")), 4001);
        } catch (Exception e) {
            Widgets.tip(this, Ui.t("没有文件选择器", "No file picker"));
        }
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (requestCode != 4001 || resultCode != RESULT_OK || data == null
                || data.getData() == null) {
            return;
        }
        final Uri uri = data.getData();
        try {
            InputStream in = getContentResolver().openInputStream(uri);
            fileBytes = Upload.readAll(in);
            in.close();
        } catch (Exception e) {
            Widgets.tip(this, Ui.t("读取文件失败", "Failed to read file"));
            return;
        }
        fileName = displayName(uri);
        mime = Upload.mimeOf(fileName);
        if (mode == 0 && !Upload.isOcrSupported(fileName)) {
            statusView.setText(Ui.t("OCR 只支持图片和 PDF（当前：", "OCR supports images and PDF only: ")
                    + fileName + "）");
        } else {
            statusView.setText(fileName + " · " + (fileBytes.length / 1024) + "KB");
        }
    }

    private String displayName(Uri uri) {
        String name = uri.getLastPathSegment();
        if (name == null) {
            return "file";
        }
        int slash = name.lastIndexOf('/');
        return slash >= 0 ? name.substring(slash + 1) : name;
    }

    /** 自检：用内置小图跑一次通用识别，验证 multipart 链路（对齐 HAP 的自检）。 */
    private void runSelfTest() {
        if (busy) {
            return;
        }
        final String key = Store.get().getApiKey().length() > 0
                ? Store.get().getApiKey() : Store.get().getAutoKey();
        if (key.length() == 0) {
            Widgets.tip(this, Ui.t("还没有网关 key，请重新登录", "No gateway key — sign in again"));
            return;
        }
        busy = true;
        resultText = "";
        refreshResult();
        statusView.setText(Ui.t("自检中：内置样图 → 通用识别…",
                "Self-test: bundled image → general OCR…"));
        Task.run(new Task.Work<String>() {
            @Override
            public String run() throws Exception {
                InputStream in = getResources().openRawResource(
                        getResources().getIdentifier("ocr_selftest", "raw", getPackageName()));
                byte[] bytes = Upload.readAll(in);
                in.close();
                mode = 0;
                ocrType = "GENERAL";
                Ocr.Result r = Ocr.get().recognize(key, bytes, "ocr-selftest.png", "image/png",
                        "GENERAL");
                StringBuilder sb = new StringBuilder();
                for (String line : r.lines) {
                    sb.append(line).append('\n');
                }
                return sb.toString().trim();
            }
        }, new Task.Call<String>() {
            @Override
            public void ok(String value) {
                busy = false;
                resultText = value.length() > 0 ? value
                        : Ui.t("自检通过：请求成功但没有识别到文字（样图可能太简单）",
                        "Self-test OK: request succeeded, no text detected");
                statusView.setText(Ui.t("自检完成", "Self-test done"));
                refreshResult();
            }

            @Override
            public void fail(String message) {
                busy = false;
                statusText = Ui.t("自检失败：", "Self-test failed: ") + message;
                statusView.setText(statusText);
            }
        });
    }

    private String statusText = "";

    private void run() {
        if (busy) {
            return;
        }
        if (fileBytes == null) {
            Widgets.tip(this, Ui.t("先选一个文件", "Choose a file first"));
            return;
        }
        String key = Store.get().getApiKey();
        if (key.length() == 0) {
            key = Store.get().getAutoKey();
        }
        if (key.length() == 0) {
            Widgets.tip(this, Ui.t("还没有网关 key，请重新登录", "No gateway key — sign in again"));
            return;
        }
        busy = true;
        resultText = "";
        refreshResult();
        statusView.setText(Ui.t("处理中…", "Working…"));
        final String apiKey = key;
        final int currentMode = mode;
        Task.run(new Task.Work<String>() {
            @Override
            public String run() throws Exception {
                if (currentMode == 0) {
                    Ocr.Result r = Ocr.get().recognize(apiKey, fileBytes, fileName, mime, ocrType);
                    StringBuilder sb = new StringBuilder();
                    for (String line : r.lines) {
                        sb.append(line).append('\n');
                    }
                    return sb.toString().trim();
                }
                Ocr.Task task = currentMode == 1
                        ? Ocr.get().submitParse(apiKey, fileBytes, fileName, mime)
                        : Ocr.get().submitConvert(apiKey, fileBytes, fileName, mime, convertTarget);
                String taskId = task.taskId;
                String status = task.status;
                for (int i = 0; i < 60; i++) {
                    if ("succeeded".equals(status) || "failed".equals(status)) {
                        break;
                    }
                    Thread.sleep(2000);
                    Ocr.Task latest = Ocr.get().query(apiKey, taskId);
                    task = latest;
                    status = latest.status;
                }
                if ("failed".equals(task.status)) {
                    throw new Exception(task.error.length() > 0 ? task.error : "任务失败");
                }
                if (task.results.isEmpty()) {
                    throw new Exception("任务完成但没有结果 URL");
                }
                String url = task.results.get(0);
                if (currentMode == 1) {
                    String json = Ocr.get().fetchResult(url);
                    return Ocr.get().extractText(json);
                }
                return Ui.t("产物已生成（有效期 3 天）：\n\n", "Result file (valid 3 days):\n\n") + url;
            }
        }, new Task.Call<String>() {
            @Override
            public void ok(String value) {
                busy = false;
                resultText = value;
                statusView.setText(Ui.t("完成", "Done"));
                refreshResult();
            }

            @Override
            public void fail(String message) {
                busy = false;
                statusView.setText(Ui.t("失败：", "Failed: ") + message);
            }
        });
    }

    private void refreshResult() {
        if (resultCardId == null) {
            return;
        }
        if (resultText.length() == 0) {
            resultCardId.setVisibility(View.GONE);
            return;
        }
        resultCardId.setVisibility(View.VISIBLE);
        resultView.setText(resultText);
        LinearLayout card = (LinearLayout) resultCardId;
        if (card.getChildCount() > 1) {
            return;
        }
        LinearLayout actions = new LinearLayout(this);
        actions.setOrientation(LinearLayout.HORIZONTAL);
        actions.setPadding(0, Ui.dpInt(this, 10), 0, 0);
        actions.addView(Widgets.ghostButton(this, Ui.t("复制", "Copy"), new Widgets.Action() {
            @Override
            public void run() {
                ClipboardManager cm = (ClipboardManager) getSystemService(Context.CLIPBOARD_SERVICE);
                cm.setPrimaryClip(ClipData.newPlainText("ocr", resultText));
                Widgets.tip(OcrActivity.this, Ui.t("已复制", "Copied"));
            }
        }), new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f));
        TextView send = Widgets.primaryButton(this, Ui.t("发送到对话", "Send to chat"), 40,
                new Widgets.Action() {
                    @Override
                    public void run() {
                        startActivity(new Intent(OcrActivity.this, MainActivity.class)
                                .putExtra("prefill", resultText)
                                .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP));
                    }
                });
        LinearLayout.LayoutParams sendLp = new LinearLayout.LayoutParams(0,
                ViewGroup.LayoutParams.WRAP_CONTENT, 1f);
        sendLp.leftMargin = Ui.dpInt(this, 8);
        actions.addView(send, sendLp);
        card.addView(actions);
    }
}
