package cn.scnet.agent.ui;

import android.app.Dialog;
import android.content.Context;
import android.graphics.Typeface;
import android.graphics.drawable.ColorDrawable;
import android.text.Editable;
import android.text.TextWatcher;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.view.Window;
import android.view.WindowManager;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

import java.util.ArrayList;
import java.util.List;

/**
 * 底部面板（替代 ArkTS 的 view/ModelSheet.ets 等）。带搜索、分组、选中态。
 */
public final class Sheet {

    public static class Item {
        public final String group;
        public final String key;
        public final String label;
        public final String sub;
        public final boolean free;
        public final boolean selected;

        public Item(String group, String key, String label, String sub, boolean free,
                    boolean selected) {
            this.group = group == null ? "" : group;
            this.key = key;
            this.label = label == null ? "" : label;
            this.sub = sub == null ? "" : sub;
            this.free = free;
            this.selected = selected;
        }
    }

    public interface OnPick {
        void onPick(Item item);
    }

    private Sheet() {
    }

    public static Dialog show(Context context, String title, List<Item> items, OnPick onPick) {
        return show(context, title, items, onPick, true, null);
    }

    public static Dialog show(Context context, String title, List<Item> items, final OnPick onPick,
                              boolean searchable, final String actionLabel) {
        final Dialog dialog = new Dialog(context);
        dialog.requestWindowFeature(Window.FEATURE_NO_TITLE);

        LinearLayout root = new LinearLayout(context);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackground(Ui.round(Ui.surface, 18, context));
        root.setPadding(0, Ui.dpInt(context, 10), 0, Ui.dpInt(context, 12));

        View handle = new View(context);
        handle.setBackground(Ui.round(Ui.border, 3, context));
        LinearLayout.LayoutParams handleLp = new LinearLayout.LayoutParams(Ui.dpInt(context, 38),
                Ui.dpInt(context, 4));
        handleLp.gravity = Gravity.CENTER_HORIZONTAL;
        handleLp.bottomMargin = Ui.dpInt(context, 10);
        root.addView(handle, handleLp);

        TextView titleView = Ui.label(context, title, 15f, Ui.text);
        titleView.setTypeface(Typeface.DEFAULT_BOLD);
        titleView.setPadding(Ui.dpInt(context, 18), 0, Ui.dpInt(context, 18),
                Ui.dpInt(context, 8));
        root.addView(titleView);

        if (actionLabel != null) {
            TextView action = Ui.label(context, actionLabel, 12.5f, Ui.accent);
            action.setPadding(Ui.dpInt(context, 18), 0, Ui.dpInt(context, 18),
                    Ui.dpInt(context, 8));
            action.setOnClickListener(new View.OnClickListener() {
                @Override
                public void onClick(View v) {
                    Item item = new Item("", "", actionLabel, "", false, false);
                    dialog.dismiss();
                    onPick.onPick(item);
                }
            });
            root.addView(action);
        }

        final EditText search = new EditText(context);
        search.setHint(Ui.t("搜索…", "Search…"));
        search.setTextSize(Ui.sp(13.5f));
        search.setSingleLine(true);
        search.setBackground(Ui.round(Ui.surfaceAlt, 10, context));
        search.setPadding(Ui.dpInt(context, 12), Ui.dpInt(context, 6), Ui.dpInt(context, 12),
                Ui.dpInt(context, 6));
        LinearLayout.LayoutParams searchLp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        searchLp.leftMargin = Ui.dpInt(context, 16);
        searchLp.rightMargin = Ui.dpInt(context, 16);
        searchLp.bottomMargin = Ui.dpInt(context, 8);
        if (searchable) {
            root.addView(search, searchLp);
        }

        LinearLayout list = new LinearLayout(context);
        list.setOrientation(LinearLayout.VERTICAL);
        list.setPadding(0, 0, 0, 0);
        ScrollView scroll = new ScrollView(context);
        scroll.addView(list);
        // Dialog 的高度是 wrap_content，用 weight 会算出 0；这里给一个固定上限（屏幕 55%）
        int maxList = Math.max(Ui.dpInt(context, 160),
                (int) (context.getResources().getDisplayMetrics().heightPixels * 0.55f));
        root.addView(scroll, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT,
                maxList));

        final Context ctx = context;
        final List<Item> all = items == null ? new ArrayList<Item>() : items;
        final Runnable[] bind = new Runnable[1];
        bind[0] = new Runnable() {
            @Override
            public void run() {
                String query = searchable ? search.getText().toString().trim().toLowerCase() : "";
                list.removeAllViews();
                String lastGroup = "";
                for (final Item item : all) {
                    if (query.length() > 0
                            && !item.label.toLowerCase().contains(query)
                            && !item.sub.toLowerCase().contains(query)) {
                        continue;
                    }
                    if (item.group.length() > 0 && !item.group.equals(lastGroup)) {
                        lastGroup = item.group;
                        TextView head = Ui.label(ctx, item.group, 11f, Ui.textFaint);
                        head.setPadding(Ui.dpInt(ctx, 18), Ui.dpInt(ctx, 10),
                                Ui.dpInt(ctx, 18), Ui.dpInt(ctx, 4));
                        list.addView(head);
                    }
                    LinearLayout row = new LinearLayout(ctx);
                    row.setOrientation(LinearLayout.VERTICAL);
                    row.setPadding(Ui.dpInt(ctx, 18), Ui.dpInt(ctx, 10), Ui.dpInt(ctx, 18),
                            Ui.dpInt(ctx, 10));
                    if (item.selected) {
                        row.setBackground(Ui.round(Ui.accentGhost, 10, ctx));
                    }
                    LinearLayout line = new LinearLayout(ctx);
                    line.setOrientation(LinearLayout.HORIZONTAL);
                    line.setGravity(Gravity.CENTER_VERTICAL);
                    TextView label = Ui.label(ctx, item.label, 14f,
                            item.selected ? Ui.accent : Ui.text);
                    label.setTypeface(item.selected ? Typeface.DEFAULT_BOLD : Typeface.DEFAULT);
                    line.addView(label, new LinearLayout.LayoutParams(0,
                            ViewGroup.LayoutParams.WRAP_CONTENT, 1f));
                    if (item.free) {
                        line.addView(Widgets.chip(ctx, Ui.t("免费", "Free"), Ui.ok,
                                Ui.alpha(Ui.ok, 0.14f)));
                    }
                    if (item.selected) {
                        TextView check = Ui.label(ctx, "✓", 14f, Ui.accent);
                        check.setPadding(Ui.dpInt(ctx, 8), 0, 0, 0);
                        line.addView(check);
                    }
                    row.addView(line);
                    if (item.sub.length() > 0) {
                        TextView sub = Ui.label(ctx, item.sub, 11f, Ui.textFaint);
                        sub.setMaxLines(2);
                        row.addView(sub);
                    }
                    row.setOnClickListener(new View.OnClickListener() {
                        @Override
                        public void onClick(View v) {
                            dialog.dismiss();
                            onPick.onPick(item);
                        }
                    });
                    list.addView(row);
                }
                if (list.getChildCount() == 0) {
                    TextView empty = Ui.label(ctx, Ui.t("没有匹配的项", "No match"), 13f, Ui.textFaint);
                    empty.setPadding(Ui.dpInt(ctx, 18), Ui.dpInt(ctx, 16), Ui.dpInt(ctx, 18),
                            Ui.dpInt(ctx, 16));
                    list.addView(empty);
                }
            }
        };
        bind[0].run();
        if (searchable) {
            search.addTextChangedListener(new TextWatcher() {
                @Override
                public void beforeTextChanged(CharSequence s, int st, int c, int a) {
                }

                @Override
                public void onTextChanged(CharSequence s, int st, int b, int c) {
                    bind[0].run();
                }

                @Override
                public void afterTextChanged(Editable s) {
                }
            });
        }

        dialog.setContentView(root);
        Window window = dialog.getWindow();
        if (window != null) {
            window.setBackgroundDrawable(new ColorDrawable(0));
            window.setLayout(WindowManager.LayoutParams.MATCH_PARENT,
                    WindowManager.LayoutParams.WRAP_CONTENT);
            window.setGravity(Gravity.BOTTOM);
            WindowManager.LayoutParams lp = window.getAttributes();
            lp.width = WindowManager.LayoutParams.MATCH_PARENT;
            window.setAttributes(lp);
        }
        dialog.show();
        return dialog;
    }

    /** 简单确认/选择面板（无搜索）。 */
    public static void pick(Context context, String title, String[] options, OnPick onPick) {
        List<Item> items = new ArrayList<>();
        for (String option : options) {
            items.add(new Item("", option, option, "", false, false));
        }
        show(context, title, items, onPick, false, null);
    }
}
