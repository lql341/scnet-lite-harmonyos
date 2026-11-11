package cn.scnet.agent.ui;

import android.app.AlertDialog;
import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Typeface;
import android.text.InputType;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.EditText;
import android.widget.FrameLayout;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.TextView;

import java.io.File;

/**
 * 通用小部件（替代 ArkTS 里散落的 @Builder）：顶栏、头像、卡片、图标按钮、输入弹窗。
 */
public final class Widgets {

    private Widgets() {
    }

    public interface Action {
        void run();
    }

    /** 顶栏：菜单 + 标题/状态 + 头像。 */
    public static LinearLayout topBar(Context context, String title, String status,
                                      String menuGlyph, Action onMenu, final View right) {
        LinearLayout bar = new LinearLayout(context);
        bar.setOrientation(LinearLayout.HORIZONTAL);
        bar.setGravity(Gravity.CENTER_VERTICAL);
        bar.setPadding(Ui.dpInt(context, 14), Ui.dpInt(context, 8), Ui.dpInt(context, 14),
                Ui.dpInt(context, 8));
        bar.setBackgroundColor(Ui.bg);

        if (menuGlyph != null && onMenu != null) {
            TextView menu = glyphButton(context, menuGlyph, onMenu);
            LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(
                    Ui.dpInt(context, 34), Ui.dpInt(context, 34));
            lp.rightMargin = Ui.dpInt(context, 10);
            bar.addView(menu, lp);
        }

        LinearLayout titles = new LinearLayout(context);
        titles.setOrientation(LinearLayout.VERTICAL);
        TextView titleView = Ui.label(context, title, 15.5f, Ui.text);
        titleView.setTypeface(Typeface.DEFAULT_BOLD);
        titles.addView(titleView);
        if (status != null) {
            TextView statusView = Ui.label(context, status, 10.5f, Ui.textFaint);
            titles.addView(statusView);
        }
        bar.addView(titles, new LinearLayout.LayoutParams(0,
                ViewGroup.LayoutParams.WRAP_CONTENT, 1f));

        if (right != null) {
            bar.addView(right);
        }
        return bar;
    }

    /** 圆形图标按钮（浅底 + 细边）。 */
    public static TextView glyphButton(Context context, String glyph, final Action action) {
        final TextView tv = new TextView(context);
        tv.setText(glyph);
        tv.setTextSize(Ui.sp(15f));
        tv.setTextColor(Ui.textSub);
        tv.setGravity(Gravity.CENTER);
        tv.setBackground(Ui.roundStroke(Ui.surface, Ui.border, 999, context));
        tv.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                if (action != null) {
                    action.run();
                }
            }
        });
        return tv;
    }

    /** 主按钮（实心 accent）。 */
    public static TextView primaryButton(Context context, String text, float heightDp,
                                         final Action action) {
        TextView tv = new TextView(context);
        tv.setText(text);
        tv.setTextSize(Ui.sp(14f));
        tv.setTextColor(0xFFFFFFFF);
        tv.setGravity(Gravity.CENTER);
        tv.setTypeface(Typeface.DEFAULT_BOLD);
        tv.setBackground(Ui.round(Ui.accent, 10, context));
        tv.setMinHeight(Ui.dpInt(context, heightDp));
        tv.setPadding(Ui.dpInt(context, 14), Ui.dpInt(context, 10), Ui.dpInt(context, 14),
                Ui.dpInt(context, 10));
        tv.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                if (action != null) {
                    action.run();
                }
            }
        });
        return tv;
    }

    /** 次级按钮（描边）。 */
    public static TextView ghostButton(Context context, String text, final Action action) {
        TextView tv = new TextView(context);
        tv.setText(text);
        tv.setTextSize(Ui.sp(13f));
        tv.setTextColor(Ui.textSub);
        tv.setGravity(Gravity.CENTER);
        tv.setBackground(Ui.roundStroke(Ui.surface, Ui.border, 9, context));
        tv.setPadding(Ui.dpInt(context, 12), Ui.dpInt(context, 8), Ui.dpInt(context, 12),
                Ui.dpInt(context, 8));
        tv.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                if (action != null) {
                    action.run();
                }
            }
        });
        return tv;
    }

    public static TextView chip(Context context, String text, int textColor, int fill) {
        TextView tv = new TextView(context);
        tv.setText(text);
        tv.setTextSize(Ui.sp(12f));
        tv.setTextColor(textColor);
        tv.setPadding(Ui.dpInt(context, 10), Ui.dpInt(context, 5), Ui.dpInt(context, 10),
                Ui.dpInt(context, 5));
        tv.setBackground(Ui.round(fill, 999, context));
        return tv;
    }

    /** 白卡片容器。 */
    public static LinearLayout card(Context context) {
        LinearLayout box = new LinearLayout(context);
        box.setOrientation(LinearLayout.VERTICAL);
        box.setBackground(Ui.roundStroke(Ui.surface, Ui.border, 14, context));
        box.setPadding(Ui.dpInt(context, 14), Ui.dpInt(context, 12), Ui.dpInt(context, 14),
                Ui.dpInt(context, 12));
        return box;
    }

    /** 设置页一行：标题 + 副标题 + 右侧值。 */
    public static LinearLayout row(Context context, String title, String sub, String value,
                                   final Action onTap) {
        return row(context, title, sub, value, onTap, true);
    }

    /** chevron=false 时右侧不画 ›（会话行自己带 ✕）。 */
    public static LinearLayout row(Context context, String title, String sub, String value,
                                   final Action onTap, boolean chevron) {
        LinearLayout line = new LinearLayout(context);
        line.setOrientation(LinearLayout.HORIZONTAL);
        line.setGravity(Gravity.CENTER_VERTICAL);
        line.setPadding(Ui.dpInt(context, 14), Ui.dpInt(context, 12), Ui.dpInt(context, 14),
                Ui.dpInt(context, 12));
        LinearLayout left = new LinearLayout(context);
        left.setOrientation(LinearLayout.VERTICAL);
        left.addView(Ui.label(context, title, 14f, Ui.text));
        if (sub != null && sub.length() > 0) {
            left.addView(Ui.label(context, sub, 11f, Ui.textFaint));
        }
        line.addView(left, new LinearLayout.LayoutParams(0,
                ViewGroup.LayoutParams.WRAP_CONTENT, 1f));
        if (value != null && value.length() > 0) {
            TextView valueView = Ui.label(context, value, 12.5f, Ui.textSub);
            valueView.setTag("rowValue");
            line.addView(valueView);
        }
        if (chevron) {
            line.addView(Ui.label(context, "›", 16f, Ui.textFaint));
        }
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

    /** 头像：首字 / 内置 emoji / 相册图片。 */
    public static View avatar(Context context, String name, String spec, int sizeDp,
                              final Action onTap) {
        int size = Ui.dpInt(context, sizeDp);
        FrameLayout box = new FrameLayout(context);
        box.setLayoutParams(new ViewGroup.LayoutParams(size, size));
        if (spec != null && spec.startsWith("preset:")) {
            String emoji = spec.substring(7);
            TextView tv = new TextView(context);
            tv.setText(emoji);
            tv.setTextSize(Ui.sp(sizeDp * 0.46f));
            tv.setGravity(Gravity.CENTER);
            tv.setBackground(Ui.round(Ui.accentSoft, 999, context));
            box.addView(tv, new FrameLayout.LayoutParams(size, size));
        } else {
            Bitmap bitmap = loadAvatarFile(spec);
            if (bitmap != null) {
                ImageView iv = new ImageView(context);
                iv.setImageBitmap(bitmap);
                iv.setScaleType(ImageView.ScaleType.CENTER_CROP);
                iv.setBackground(Ui.round(Ui.accentSoft, 999, context));
                box.addView(iv, new FrameLayout.LayoutParams(size, size));
            } else {
                TextView tv = new TextView(context);
                String initial = firstChar(name);
                tv.setText(initial);
                tv.setTextSize(Ui.sp(sizeDp * 0.36f));
                tv.setTextColor(Ui.accent);
                tv.setTypeface(Typeface.DEFAULT_BOLD);
                tv.setGravity(Gravity.CENTER);
                tv.setBackground(Ui.round(Ui.accentSoft, 999, context));
                box.addView(tv, new FrameLayout.LayoutParams(size, size));
            }
        }
        if (onTap != null) {
            box.setOnClickListener(new View.OnClickListener() {
                @Override
                public void onClick(View v) {
                    onTap.run();
                }
            });
        }
        return box;
    }

    private static Bitmap loadAvatarFile(String spec) {
        if (spec == null || !spec.startsWith("file:")) {
            return null;
        }
        try {
            String path = spec.substring(5);
            return BitmapFactory.decodeFile(new File(path).getAbsolutePath());
        } catch (Exception e) {
            return null;
        }
    }

    public static String firstChar(String name) {
        String text = name == null ? "" : name.trim();
        if (text.length() == 0) {
            return "超";
        }
        // 中文取第一个字，英文取首字母大写
        char ch = text.charAt(0);
        if (ch >= 0x4e00 && ch <= 0x9fff) {
            return String.valueOf(ch);
        }
        return String.valueOf(Character.toUpperCase(ch));
    }

    /** 单行输入弹窗（重命名等）。 */
    /** 分段/索引选择回调。 */
    public interface OnInt {
        void onInt(int index);
    }

    public interface OnText {
        void onText(String value);
    }

    public static void prompt(Context context, String title, String initial, String hint,
                              boolean multiline, final OnText onText) {
        EditText input = new EditText(context);
        input.setText(initial == null ? "" : initial);
        input.setHint(hint == null ? "" : hint);
        input.setTextSize(Ui.sp(14f));
        input.setTextColor(Ui.text);
        input.setPadding(Ui.dpInt(context, 16), Ui.dpInt(context, 10), Ui.dpInt(context, 16),
                Ui.dpInt(context, 10));
        if (multiline) {
            input.setMinLines(3);
            input.setGravity(Gravity.TOP | Gravity.START);
            input.setInputType(InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_FLAG_MULTI_LINE);
        }
        FrameLayout wrap = new FrameLayout(context);
        wrap.setPadding(Ui.dpInt(context, 8), Ui.dpInt(context, 4), Ui.dpInt(context, 8), 0);
        wrap.addView(input);
        new AlertDialog.Builder(context)
                .setTitle(title)
                .setView(wrap)
                .setNegativeButton(Ui.t("取消", "Cancel"), null)
                .setPositiveButton(Ui.t("确定", "OK"), new android.content.DialogInterface.OnClickListener() {
                    @Override
                    public void onClick(android.content.DialogInterface d, int which) {
                        onText.onText(input.getText().toString());
                    }
                })
                .show();
    }

    public static void confirm(Context context, String title, String message, String positive,
                               final Action action) {
        new AlertDialog.Builder(context)
                .setTitle(title)
                .setMessage(message)
                .setNegativeButton(Ui.t("取消", "Cancel"), null)
                .setPositiveButton(positive, new android.content.DialogInterface.OnClickListener() {
                    @Override
                    public void onClick(android.content.DialogInterface d, int which) {
                        action.run();
                    }
                })
                .show();
    }

    public static void tip(Context context, String text) {
        android.widget.Toast.makeText(context, text, android.widget.Toast.LENGTH_SHORT).show();
    }

    /** 服务入口行：左侧方形徽标 + 标题/副标题 + ›（对齐 HAP 抽屉的服务入口）。 */
    public static LinearLayout entryRow(Context context, String badge, String title, String sub,
                                        final Action onTap) {
        LinearLayout row = new LinearLayout(context);
        row.setOrientation(LinearLayout.HORIZONTAL);
        row.setGravity(Gravity.CENTER_VERTICAL);
        row.setPadding(Ui.dpInt(context, 10), Ui.dpInt(context, 9), Ui.dpInt(context, 10),
                Ui.dpInt(context, 9));

        TextView mark = new TextView(context);
        mark.setText(badge);
        mark.setTextSize(Ui.sp(9f));
        mark.setTypeface(Typeface.DEFAULT_BOLD);
        mark.setTextColor(Ui.accent);
        mark.setGravity(Gravity.CENTER);
        mark.setBackground(Ui.round(Ui.accentGhost, 7, context));
        row.addView(mark, new LinearLayout.LayoutParams(Ui.dpInt(context, 24),
                Ui.dpInt(context, 24)));

        LinearLayout texts = new LinearLayout(context);
        texts.setOrientation(LinearLayout.VERTICAL);
        LinearLayout.LayoutParams textLp = new LinearLayout.LayoutParams(0,
                ViewGroup.LayoutParams.WRAP_CONTENT, 1f);
        textLp.leftMargin = Ui.dpInt(context, 8);
        TextView titleView = Ui.label(context, title, 13.5f, Ui.text);
        texts.addView(titleView);
        if (sub != null && sub.length() > 0) {
            texts.addView(Ui.label(context, sub, 10f, Ui.textFaint));
        }
        row.addView(texts, textLp);
        row.addView(Ui.label(context, "›", 14f, Ui.textFaint));

        if (onTap != null) {
            row.setOnClickListener(new View.OnClickListener() {
                @Override
                public void onClick(View v) {
                    onTap.run();
                }
            });
        }
        return row;
    }

    /** 分组标题。 */
    public static TextView section(Context context, String text) {
        TextView tv = Ui.label(context, text, 11.5f, Ui.textFaint);
        tv.setPadding(Ui.dpInt(context, 16), Ui.dpInt(context, 14), Ui.dpInt(context, 16),
                Ui.dpInt(context, 6));
        return tv;
    }
}
