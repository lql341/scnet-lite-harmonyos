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
                TextView tv = text(context, block.text, block.kind == Md.H1 ? 19 : (block.kind == Md.H2 ? 17 : 15.5f),
                        Ui.text, true);
                tv.setPadding(0, Ui.dpInt(context, 10), 0, Ui.dpInt(context, 4));
                return tv;
            }
            case Md.P: {
                TextView tv = text(context, "", 15f, Ui.text, false);
                tv.setText(inline(context, block.text, Ui.text));
                tv.setLineSpacing(Ui.dp(context, 4), 1f);
                tv.setPadding(0, Ui.dpInt(context, 3), 0, Ui.dpInt(context, 3));
                return tv;
            }
            case Md.BULLET:
            case Md.ORDERED: {
                LinearLayout row = new LinearLayout(context);
                row.setOrientation(LinearLayout.HORIZONTAL);
                int pad = Ui.dpInt(context, 4 + block.level * 12);
                row.setPadding(pad, Ui.dpInt(context, 2), 0, Ui.dpInt(context, 2));
                TextView bullet = text(context,
                        block.kind == Md.BULLET ? "•" : (block.order > 0 ? block.order + "." : "•"),
                        15f, Ui.textSub, false);
                bullet.setMinWidth(Ui.dpInt(context, 16));
                row.addView(bullet);
                TextView body = text(context, "", 15f, Ui.text, false);
                body.setText(inline(context, block.text, Ui.text));
                body.setLineSpacing(Ui.dp(context, 3), 1f);
                LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(0,
                        ViewGroup.LayoutParams.WRAP_CONTENT, 1f);
                row.addView(body, lp);
                return row;
            }
            case Md.QUOTE: {
                LinearLayout row = new LinearLayout(context);
                row.setOrientation(LinearLayout.HORIZONTAL);
                View bar = new View(context);
                bar.setBackgroundColor(Ui.accent);
                LinearLayout.LayoutParams barLp = new LinearLayout.LayoutParams(Ui.dpInt(context, 3),
                        ViewGroup.LayoutParams.MATCH_PARENT);
                row.addView(bar, barLp);
                TextView body = text(context, "", 14.5f, Ui.textSub, false);
                body.setText(inline(context, block.text, Ui.textSub));
                body.setLineSpacing(Ui.dp(context, 4), 1f);
                body.setPadding(Ui.dpInt(context, 10), Ui.dpInt(context, 2), 0, Ui.dpInt(context, 2));
                row.addView(body, new LinearLayout.LayoutParams(0,
                        ViewGroup.LayoutParams.WRAP_CONTENT, 1f));
                LinearLayout wrap = new LinearLayout(context);
                wrap.setPadding(0, Ui.dpInt(context, 6), 0, Ui.dpInt(context, 6));
                wrap.addView(row);
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

    /** 表格：表头浅底 + 行分隔，窄屏横向滚动。 */
    private static View table(Context context, Md.Block block) {
        HorizontalScrollView hsv = new HorizontalScrollView(context);
        hsv.setHorizontalScrollBarEnabled(false);
        LinearLayout grid = new LinearLayout(context);
        grid.setOrientation(LinearLayout.VERTICAL);
        int columns = 0;
        for (List<String> row : block.rows) {
            columns = Math.max(columns, row.size());
        }
        int cellWidth = Math.min(Ui.dpInt(context, 150),
                Math.max(Ui.dpInt(context, 74), (int) (Ui.dpInt(context, 300) * 0.9f / Math.max(1, columns))));
        for (int r = 0; r < block.rows.size(); r++) {
            List<String> row = block.rows.get(r);
            LinearLayout line = new LinearLayout(context);
            line.setOrientation(LinearLayout.HORIZONTAL);
            line.setBackgroundColor(r == 0 ? Ui.surfaceAlt
                    : (r % 2 == 0 ? Ui.alpha(Ui.surfaceAlt, 0.45f) : 0));
            for (int c = 0; c < columns; c++) {
                String value = c < row.size() ? row.get(c) : "";
                TextView cell = text(context, "", 13f, Ui.text, r == 0);
                cell.setText(inline(context, value, Ui.text));
                cell.setPadding(Ui.dpInt(context, 8), Ui.dpInt(context, 6), Ui.dpInt(context, 8),
                        Ui.dpInt(context, 6));
                line.addView(cell, new LinearLayout.LayoutParams(cellWidth,
                        ViewGroup.LayoutParams.WRAP_CONTENT));
            }
            grid.addView(line);
            View lineView = new View(context);
            lineView.setBackgroundColor(Ui.hairline);
            grid.addView(lineView, new LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT, Ui.dpInt(context, 1)));
        }
        hsv.addView(grid);
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        lp.topMargin = Ui.dpInt(context, 6);
        lp.bottomMargin = Ui.dpInt(context, 6);
        hsv.setLayoutParams(lp);
        hsv.setBackground(Ui.roundStroke(Ui.surface, Ui.border, 10, context));
        return hsv;
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
            if (seg.code) {
                sb.setSpan(new TypefaceSpan("monospace"), start, end, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE);
                sb.setSpan(new BackgroundColorSpan(Ui.alpha(Ui.accent, 0.14f)), start, end,
                        Spanned.SPAN_EXCLUSIVE_EXCLUSIVE);
            }
        }
        if (sb.length() == 0) {
            return "";
        }
        return sb;
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
