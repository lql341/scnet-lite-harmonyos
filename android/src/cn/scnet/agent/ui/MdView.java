package cn.scnet.agent.ui;

import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Context;
import android.graphics.Typeface;
import android.text.SpannableString;
import android.text.SpannableStringBuilder;
import android.text.Spanned;
import android.text.style.BackgroundColorSpan;
import android.text.style.StyleSpan;
import android.text.style.TypefaceSpan;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.HorizontalScrollView;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;

import java.util.List;

import cn.scnet.agent.core.Md;

/**
 * Markdown 渲染器（替代 ArkTS 的 view/MarkdownView.ets）。
 *
 * 没有 WebView、没有三方库：块级用原生控件堆，行内用 Spannable。
 * 流式半截输入（未闭合的 ``` 与 **）照常显示，不吞字。
 */
public final class MdView {

    /** 最近一次渲染里"最后一个可增量更新的文本控件"（流式时只改它，避免整段重排）。 */
    public static TextView lastText;

    private MdView() {
    }

    public static void render(Context context, LinearLayout target, String markdown) {
        target.removeAllViews();
        List<Md.Block> blocks = Md.parse(markdown);
        for (Md.Block block : blocks) {
            View view = blockView(context, block);
            if (view != null) {
                target.addView(view);
            }
        }
    }

    private static View blockView(Context context, Md.Block block) {
        switch (block.kind) {
            case Md.H1:
            case Md.H2:
            case Md.H3: {
                float size;
                if (block.kind == Md.H1) {
                    size = 19f;
                } else if (block.kind == Md.H2) {
                    size = 17f;
                } else if (block.level >= 6) {
                    size = 13f;
                } else if (block.level == 5) {
                    size = 13.5f;
                } else if (block.level == 4) {
                    size = 14.2f;
                } else {
                    size = 15.5f;
                }
                TextView tv = text(context, block.text, size, Ui.text, true);
                tv.setPadding(0, Ui.dpInt(context, 4), 0, Ui.dpInt(context, 2));
                lastText = tv;
                if (block.kind != Md.H1) {
                    tv.setPadding(0, Ui.dpInt(context, 8), 0, Ui.dpInt(context, 2));
                    return tv;
                }
                // H1：左侧 accent 色条（与 HAP 的 heading 一致）
                LinearLayout row = new LinearLayout(context);
                row.setOrientation(LinearLayout.HORIZONTAL);
                row.setGravity(Gravity.CENTER_VERTICAL);
                View bar = new View(context);
                bar.setBackground(Ui.round(Ui.accent, 2, context));
                LinearLayout.LayoutParams barLp = new LinearLayout.LayoutParams(
                        Ui.dpInt(context, 3), Ui.dpInt(context, 16));
                barLp.rightMargin = Ui.dpInt(context, 8);
                row.addView(bar, barLp);
                row.addView(tv, new LinearLayout.LayoutParams(0,
                        ViewGroup.LayoutParams.WRAP_CONTENT, 1f));
                row.setPadding(0, Ui.dpInt(context, 6), 0, Ui.dpInt(context, 2));
                return row;
            }
            case Md.P: {
                TextView tv = text(context, "", 15f, Ui.text, false);
                tv.setText(inline(context, block.text, Ui.text));
                tv.setLineSpacing(Ui.dp(context, 4), 1f);
                tv.setPadding(0, Ui.dpInt(context, 3), 0, Ui.dpInt(context, 3));
                tv.setMovementMethod(android.text.method.LinkMovementMethod.getInstance());
                tv.setLinkTextColor(Ui.accent);
                lastText = tv;
                return tv;
            }
            case Md.BULLET:
            case Md.ORDERED: {
                LinearLayout row = new LinearLayout(context);
                row.setOrientation(LinearLayout.HORIZONTAL);
                int pad = Ui.dpInt(context, 4 + block.level * 12);
                row.setPadding(pad, Ui.dpInt(context, 2), 0, Ui.dpInt(context, 2));
                if (block.kind == Md.BULLET) {
                    View dot = new View(context);
                    dot.setBackground(Ui.round(Ui.textFaint, 999, context));
                    LinearLayout.LayoutParams dotLp = new LinearLayout.LayoutParams(
                            Ui.dpInt(context, 5), Ui.dpInt(context, 5));
                    dotLp.leftMargin = Ui.dpInt(context, 4);
                    dotLp.rightMargin = Ui.dpInt(context, 9);
                    dotLp.topMargin = Ui.dpInt(context, 9);
                    row.addView(dot, dotLp);
                } else {
                    TextView order = text(context,
                            (block.order > 0 ? block.order : 1) + ".", 15f, Ui.textFaint, false);
                    order.setMinWidth(Ui.dpInt(context, 18));
                    row.addView(order);
                }
                TextView body = text(context, "", 15f, Ui.text, false);
                body.setText(inline(context, block.text, Ui.text));
                body.setLineSpacing(Ui.dp(context, 3), 1f);
                LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(0,
                        ViewGroup.LayoutParams.WRAP_CONTENT, 1f);
                row.addView(body, lp);
                lastText = body;
                return row;
            }
            case Md.QUOTE: {
                LinearLayout quoteWrap = new LinearLayout(context);
                quoteWrap.setOrientation(LinearLayout.HORIZONTAL);
                quoteWrap.setPadding(Ui.dpInt(context, 4 + block.level * 12), Ui.dpInt(context, 3),
                        0, Ui.dpInt(context, 3));
                View bar = new View(context);
                bar.setBackgroundColor(Ui.accentSoft);
                quoteWrap.addView(bar, new LinearLayout.LayoutParams(Ui.dpInt(context, 3),
                        ViewGroup.LayoutParams.MATCH_PARENT));
                TextView body = text(context, "", 14.5f, Ui.textSub, false);
                body.setText(inline(context, block.text, Ui.textSub));
                body.setLineSpacing(Ui.dp(context, 4), 1f);
                body.setPadding(Ui.dpInt(context, 10), Ui.dpInt(context, 2), 0, Ui.dpInt(context, 2));
                quoteWrap.addView(body, new LinearLayout.LayoutParams(0,
                        ViewGroup.LayoutParams.WRAP_CONTENT, 1f));
                LinearLayout wrap = new LinearLayout(context);
                wrap.setPadding(0, Ui.dpInt(context, 3), 0, Ui.dpInt(context, 3));
                wrap.addView(quoteWrap);
                return wrap;
            }
            case Md.CODE:
                return codeBlock(context, block);
            case Md.HR: {
                View line = new View(context);
                line.setBackgroundColor(Ui.hairline);
                LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(
                        ViewGroup.LayoutParams.MATCH_PARENT, Ui.dpInt(context, 1));
                lp.topMargin = Ui.dpInt(context, 8);
                lp.bottomMargin = Ui.dpInt(context, 8);
                line.setLayoutParams(lp);
                return line;
            }
            case Md.TABLE:
                return table(context, block);
            case Md.IMAGE:
                return image(context, block.text);
            default:
                return null;
        }
    }

    /** 代码块：深色圆角 + 语言标签 + 复制按钮 + 等宽正文。 */
    private static View codeBlock(final Context context, Md.Block block) {
        LinearLayout outer = new LinearLayout(context);
        outer.setOrientation(LinearLayout.VERTICAL);
        outer.setBackground(Ui.round(Ui.codeBg, 10, context));
        LinearLayout.LayoutParams outerLp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        outerLp.topMargin = Ui.dpInt(context, 6);
        outerLp.bottomMargin = Ui.dpInt(context, 6);
        outer.setLayoutParams(outerLp);

        LinearLayout head = new LinearLayout(context);
        head.setOrientation(LinearLayout.HORIZONTAL);
        head.setGravity(Gravity.CENTER_VERTICAL);
        head.setPadding(Ui.dpInt(context, 12), Ui.dpInt(context, 7), Ui.dpInt(context, 8),
                Ui.dpInt(context, 4));
        TextView lang = text(context, block.lang.length() > 0 ? block.lang : "code", 11f,
                Ui.alpha(Ui.codeText, 0.55f), false);
        head.addView(lang, new LinearLayout.LayoutParams(0,
                ViewGroup.LayoutParams.WRAP_CONTENT, 1f));
        final TextView copy = text(context, "复制", 11f, Ui.alpha(Ui.codeText, 0.75f), false);
        copy.setPadding(Ui.dpInt(context, 8), Ui.dpInt(context, 2), Ui.dpInt(context, 8),
                Ui.dpInt(context, 2));
        copy.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                ClipboardManager cm = (ClipboardManager) context.getSystemService(
                        Context.CLIPBOARD_SERVICE);
                cm.setPrimaryClip(ClipData.newPlainText("code", block.code));
                Toast.makeText(context, Ui.t("已复制", "Copied"), Toast.LENGTH_SHORT).show();
            }
        });
        head.addView(copy);
        outer.addView(head);

        TextView body = new TextView(context);
        body.setText(block.code);
        body.setTextSize(Ui.sp(12.5f));
        body.setTextColor(Ui.codeText);
        body.setTypeface(Typeface.MONOSPACE);
        body.setLineSpacing(Ui.dp(context, 2), 1f);
        body.setPadding(Ui.dpInt(context, 12), Ui.dpInt(context, 2), Ui.dpInt(context, 12),
                Ui.dpInt(context, 12));
        // 长行不横向滚动（气泡内横向滚动很难用），按字符折行
        body.setHorizontallyScrolling(false);
        outer.addView(body);
        return outer;
    }

    /** 图片块：先占位，异步加载；点击用浏览器看大图。 */
    private static View image(final Context context, final String rawUrl) {
        final String url = ImageLoader.normalize(rawUrl);
        LinearLayout wrap = new LinearLayout(context);
        wrap.setOrientation(LinearLayout.VERTICAL);
        wrap.setPadding(0, Ui.dpInt(context, 6), 0, Ui.dpInt(context, 6));

        final ImageView view = new ImageView(context);
        view.setAdjustViewBounds(true);
        view.setScaleType(ImageView.ScaleType.FIT_START);
        view.setMinimumHeight(Ui.dpInt(context, 80));
        view.setBackground(Ui.round(Ui.surfaceAlt, 10, context));
        int maxWidth = Math.min(context.getResources().getDisplayMetrics().widthPixels
                - Ui.dpInt(context, 64), Ui.dpInt(context, 320));
        wrap.addView(view, new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT));
        view.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                try {
                    context.startActivity(new android.content.Intent(
                            android.content.Intent.ACTION_VIEW, android.net.Uri.parse(url)));
                } catch (Throwable ignored) {
                }
            }
        });
        ImageLoader.load(url, view, maxWidth);
        TextView hint = Ui.label(context, url, 10f, Ui.textFaint);
        hint.setMaxLines(1);
        wrap.addView(hint);
        return wrap;
    }

    /**
     * 表格：**按 HAP 的卡片式**渲染（手机上横向滚动表格会被消息列表抢手势）。
     *   表头一行浅底；每行「首列标题 + 其余列 键:值」。
     */
    private static View table(Context context, Md.Block block) {
        LinearLayout card = new LinearLayout(context);
        card.setOrientation(LinearLayout.VERTICAL);
        card.setBackground(Ui.roundStroke(Ui.surface, Ui.border, 12, context));
        LinearLayout.LayoutParams cardLp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        cardLp.topMargin = Ui.dpInt(context, 6);
        cardLp.bottomMargin = Ui.dpInt(context, 6);
        card.setLayoutParams(cardLp);
        card.setClipToOutline(true);

        if (block.rows.isEmpty()) {
            return card;
        }
        List<String> header = block.rows.get(0);

        // 表头
        LinearLayout head = new LinearLayout(context);
        head.setOrientation(LinearLayout.HORIZONTAL);
        head.setBackgroundColor(Ui.surfaceAlt);
        head.setPadding(Ui.dpInt(context, 12), Ui.dpInt(context, 8), Ui.dpInt(context, 12),
                Ui.dpInt(context, 8));
        for (int c = 0; c < header.size(); c++) {
            TextView cell = text(context, "", 10.5f, Ui.textSub, false);
            cell.setText(inline(context, header.get(c), Ui.textSub));
            cell.setMaxLines(1);
            cell.setEllipsize(android.text.TextUtils.TruncateAt.END);
            head.addView(cell, new LinearLayout.LayoutParams(0,
                    ViewGroup.LayoutParams.WRAP_CONTENT, c == 0 ? 3f : 4f));
        }
        card.addView(head);
        card.addView(divider(context));

        // 数据行
        for (int r = 1; r < block.rows.size(); r++) {
            List<String> row = block.rows.get(r);
            LinearLayout wrap = new LinearLayout(context);
            wrap.setOrientation(LinearLayout.VERTICAL);
            wrap.setPadding(Ui.dpInt(context, 12), Ui.dpInt(context, 10), Ui.dpInt(context, 12),
                    Ui.dpInt(context, 10));
            if (r % 2 == 0) {
                wrap.setBackgroundColor(Ui.alpha(Ui.surfaceAlt, 0.45f));
            }

            TextHolder first = new TextHolder();
            TextView title = text(context, "", 14f, Ui.text, false);
            title.setText(inline(context, row.isEmpty() ? "" : row.get(0), Ui.text));
            wrap.addView(title);

            if (row.size() > 1) {
                LinearLayout kvRow = new LinearLayout(context);
                kvRow.setOrientation(LinearLayout.HORIZONTAL);
                kvRow.setPadding(0, Ui.dpInt(context, 4), 0, 0);
                for (int c = 1; c < row.size(); c++) {
                    LinearLayout cellBox = new LinearLayout(context);
                    cellBox.setOrientation(LinearLayout.VERTICAL);
                    String name = c < header.size() ? header.get(c) : "";
                    if (name.length() > 0) {
                        TextView key = text(context, name, 9.5f, Ui.textFaint, false);
                        key.setMaxLines(1);
                        key.setEllipsize(android.text.TextUtils.TruncateAt.END);
                        cellBox.addView(key);
                    }
                    TextView value = text(context, "", 12.5f, Ui.textSub, false);
                    value.setText(inline(context, row.get(c), Ui.textSub));
                    cellBox.addView(value);
                    LinearLayout.LayoutParams cellLp = new LinearLayout.LayoutParams(0,
                            ViewGroup.LayoutParams.WRAP_CONTENT, 1f);
                    if (c > 1) {
                        cellLp.leftMargin = Ui.dpInt(context, 6);
                    }
                    kvRow.addView(cellBox, cellLp);
                }
                wrap.addView(kvRow);
            }
            card.addView(wrap);
            if (r < block.rows.size() - 1) {
                card.addView(divider(context));
            }
        }
        return card;
    }

    private static final class TextHolder {
    }

    private static View divider(Context context) {
        View line = new View(context);
        line.setBackgroundColor(Ui.hairline);
        line.setLayoutParams(new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, Ui.dpInt(context, 1)));
        return line;
    }

    /** 行内样式 → Spannable。 */
    public static CharSequence inline(Context context, String text, int baseColor) {
        SpannableStringBuilder sb = new SpannableStringBuilder();
        List<Md.Seg> segs = Md.inline(text);
        for (Md.Seg seg : segs) {
            int start = sb.length();
            sb.append(seg.text);
            int end = sb.length();
            if (end <= start) {
                continue;
            }
            if (seg.bold) {
                sb.setSpan(new StyleSpan(Typeface.BOLD), start, end, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE);
            }
            if (seg.italic) {
                sb.setSpan(new StyleSpan(Typeface.ITALIC), start, end, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE);
            }
            if (seg.link.length() > 0) {
                sb.setSpan(new android.text.style.URLSpan(seg.link), start, end,
                        Spanned.SPAN_EXCLUSIVE_EXCLUSIVE);
                sb.setSpan(new android.text.style.ForegroundColorSpan(Ui.accent), start, end,
                        Spanned.SPAN_EXCLUSIVE_EXCLUSIVE);
            }
            if (seg.strike) {
                sb.setSpan(new android.text.style.StrikethroughSpan(), start, end,
                        Spanned.SPAN_EXCLUSIVE_EXCLUSIVE);
            }
            if (seg.code) {
                sb.setSpan(new TypefaceSpan("monospace"), start, end, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE);
                sb.setSpan(new BackgroundColorSpan(Ui.alpha(Ui.accent, 0.14f)), start, end,
                        Spanned.SPAN_EXCLUSIVE_EXCLUSIVE);
            }
        }
        if (sb.length() == 0) {
            return "";
        }
        applyLinks(sb);
        return sb;
    }

    /**
     * 把 spannable 里的 http(s) 链接做成可点击（含模型直接吐的裸 URL）。
     * 代码片段不处理（避免把示例里的 URL 变成链接）。
     */
    private static void applyLinks(SpannableStringBuilder sb) {
        String text = sb.toString();
        java.util.regex.Matcher m = java.util.regex.Pattern
                .compile("https?://[^\\s)\\]}>\u4e00-\u9fff，。；、]+").matcher(text);
        while (m.find()) {
            int start = m.start();
            int end = m.end();
            boolean inCode = false;
            TypefaceSpan[] codeSpans = sb.getSpans(start, end, TypefaceSpan.class);
            if (codeSpans != null && codeSpans.length > 0) {
                inCode = true;
            }
            if (inCode) {
                continue;
            }
            final String url = text.substring(start, end);
            sb.setSpan(new android.text.style.URLSpan(url), start, end,
                    Spanned.SPAN_EXCLUSIVE_EXCLUSIVE);
            sb.setSpan(new android.text.style.ForegroundColorSpan(Ui.accent), start, end,
                    Spanned.SPAN_EXCLUSIVE_EXCLUSIVE);
        }
    }

    private static TextView text(Context context, String value, float sizeSp, int color, boolean bold) {
        TextView tv = new TextView(context);
        tv.setText(value);
        tv.setTextSize(Ui.sp(sizeSp));
        tv.setTextColor(color);
        if (bold) {
            tv.setTypeface(Typeface.DEFAULT_BOLD);
        }
        return tv;
    }
}
