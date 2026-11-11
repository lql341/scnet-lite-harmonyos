package cn.scnet.agent.ui;

import android.content.Context;
import android.graphics.Color;
import android.graphics.drawable.GradientDrawable;
import android.util.TypedValue;
import android.view.View;
import android.view.ViewGroup;
import android.widget.TextView;

import java.util.ArrayList;
import java.util.List;

/**
 * 视觉令牌 + 中英文 + 尺寸工具（对齐 ArkTS 的 common/Theme.ets + common/I18n.ets）。
 *
 * 颜色是**运行时静态字段**：切主题/深色只要 apply() 之后重建界面，不用重启。
 */
public final class Ui {

    public static final class Palette {
        public final String id;
        public final String name;
        public final int accent;
        public final int accentDeep;
        public final int accentSoft;
        public final int accentGhost;
        public final int bg;
        public final int surface;
        public final int surfaceAlt;
        public final int text;
        public final int textSub;
        public final int textFaint;
        public final int border;
        public final int hairline;

        Palette(String id, String name, String accent, String accentDeep, String accentSoft,
                String accentGhost, String bg, String surface, String surfaceAlt, String text,
                String textSub, String textFaint, String border, String hairline) {
            this.id = id;
            this.name = name;
            this.accent = Color.parseColor(accent);
            this.accentDeep = Color.parseColor(accentDeep);
            this.accentSoft = Color.parseColor(accentSoft);
            this.accentGhost = Color.parseColor(accentGhost);
            this.bg = Color.parseColor(bg);
            this.surface = Color.parseColor(surface);
            this.surfaceAlt = Color.parseColor(surfaceAlt);
            this.text = Color.parseColor(text);
            this.textSub = Color.parseColor(textSub);
            this.textFaint = Color.parseColor(textFaint);
            this.border = Color.parseColor(border);
            this.hairline = Color.parseColor(hairline);
        }
    }

    public static final List<Palette> PALETTES = new ArrayList<>();

    static {
        add("claude", "暖砂", "#C15F3C", "#A44A2C", "#F2E4DC", "#FAF3EF", "#F7F5F2",
                "#FFFFFF", "#F1EDE7", "#1F1E1D", "#5D5A57", "#8F8A84", "#E6DFD7", "#EFE9E2");
        add("scnet", "SCNet 红", "#C4161C", "#9E1116", "#F8E3E3", "#FDF4F4", "#F7F5F3",
                "#FFFFFF", "#F1EDEA", "#1F1B1A", "#5D5553", "#8F8785", "#E7DFDC", "#F0EAE7");
        add("ocean", "深海蓝", "#0B4F8A", "#083A66", "#E7F0F8", "#F3F8FC", "#F4F6F9",
                "#FFFFFF", "#F1F3F7", "#101828", "#475467", "#98A2B3", "#E6E9EF", "#EFF1F5");
        add("graphite", "石墨", "#1F2937", "#111827", "#E8EBEF", "#F5F6F8", "#F4F5F7",
                "#FFFFFF", "#EDEFF2", "#111827", "#4B5563", "#9CA3AF", "#E2E5EA", "#EDEFF2");
        add("pine", "松绿", "#0E7C66", "#0A5D4D", "#E2F2EE", "#F2FAF7", "#F3F7F6",
                "#FFFFFF", "#EAF2EF", "#12211E", "#47605A", "#8FA8A1", "#DEE9E5", "#E9F1EE");
        add("amber", "琥珀", "#B45309", "#8A3F07", "#FAEDE0", "#FEF8F2", "#F8F5F1",
                "#FFFFFF", "#F2EBE2", "#1F1A15", "#5C5348", "#9C9184", "#E8DFD2", "#F1EAE0");
        add("violet", "紫罗兰", "#5B3FA8", "#46308A", "#ECE8F9", "#F6F4FD", "#F5F4F9",
                "#FFFFFF", "#EEECF6", "#1B1726", "#544E68", "#9891AC", "#E3DFEF", "#EEEBF7");
        add("rose", "玫瑰", "#B02A5B", "#8C1F47", "#FAE8EF", "#FDF4F8", "#F8F4F6",
                "#FFFFFF", "#F4E9EE", "#211519", "#5E4A52", "#A08D95", "#EADDE3", "#F4EBEF");
    }

    private static void add(String id, String name, String accent, String accentDeep,
                            String accentSoft, String accentGhost, String bg, String surface,
                            String surfaceAlt, String text, String textSub, String textFaint,
                            String border, String hairline) {
        PALETTES.add(new Palette(id, name, accent, accentDeep, accentSoft, accentGhost, bg,
                surface, surfaceAlt, text, textSub, textFaint, border, hairline));
    }

    public static String paletteId = "claude";
    public static boolean dark = false;

    public static int bg;
    public static int surface;
    public static int surfaceAlt;
    public static int surfaceSunken;
    public static int accent;
    public static int accentDeep;
    public static int accentSoft;
    public static int accentGhost;
    public static int text;
    public static int textSub;
    public static int textFaint;
    public static int border;
    public static int hairline;
    public static int ok = Color.parseColor("#12805C");
    public static int warn = Color.parseColor("#B45309");
    public static int danger = Color.parseColor("#C4161C");
    public static int dangerSoft = Color.parseColor("#F8E3E3");
    public static int codeBg = Color.parseColor("#1E1E1E");
    public static int codeText = Color.parseColor("#E6E6E6");

    /** 字号基准（三档：0.9 / 1.0 / 1.15）。 */
    public static float fontScale = 1f;

    public static boolean zh = true;

    static {
        apply("claude", false);
    }

    private Ui() {
    }

    public static Palette find(String id) {
        for (Palette p : PALETTES) {
            if (p.id.equals(id)) {
                return p;
            }
        }
        return PALETTES.get(0);
    }

    /** 切换配色 + 深色。深色下刻意不用纯黑（和 ArkTS 版一致）。 */
    public static void apply(String paletteIdValue, boolean darkMode) {
        Palette p = find(paletteIdValue == null ? "claude" : paletteIdValue);
        paletteId = p.id;
        dark = darkMode;
        accent = p.accent;
        accentDeep = p.accentDeep;
        accentGhost = dark ? blend(p.accentGhost, "#000000", 0.82f) : p.accentGhost;
        if (dark) {
            bg = Color.parseColor("#121110");
            surface = Color.parseColor("#1B1A19");
            surfaceAlt = Color.parseColor("#232120");
            surfaceSunken = Color.parseColor("#0D0C0B");
            text = Color.parseColor("#EDEAE6");
            textSub = Color.parseColor("#A9A49E");
            textFaint = Color.parseColor("#7A756F");
            border = Color.parseColor("#2E2B29");
            hairline = Color.parseColor("#26231F");
            accentSoft = blend(p.accent, "#1B1A19", 0.62f);
            danger = Color.parseColor("#F07178");
            dangerSoft = Color.parseColor("#3A1F21");
            warn = Color.parseColor("#E0A45A");
            ok = Color.parseColor("#4CC38A");
            codeBg = Color.parseColor("#111111");
            codeText = Color.parseColor("#E6E6E6");
        } else {
            bg = p.bg;
            surface = p.surface;
            surfaceAlt = p.surfaceAlt;
            surfaceSunken = blend(p.surfaceAlt, "#000000", 0.06f);
            text = p.text;
            textSub = p.textSub;
            textFaint = p.textFaint;
            border = p.border;
            hairline = p.hairline;
            accentSoft = p.accentSoft;
            danger = Color.parseColor("#C4161C");
            dangerSoft = Color.parseColor("#F8E3E3");
            warn = Color.parseColor("#B45309");
            ok = Color.parseColor("#12805C");
            codeBg = Color.parseColor("#1E1E1E");
            codeText = Color.parseColor("#E6E6E6");
        }
    }

    private static int blend(int color, String toward, float ratio) {
        int t = Color.parseColor(toward);
        int r = (int) (Color.red(color) * (1 - ratio) + Color.red(t) * ratio);
        int g = (int) (Color.green(color) * (1 - ratio) + Color.green(t) * ratio);
        int b = (int) (Color.blue(color) * (1 - ratio) + Color.blue(t) * ratio);
        return Color.rgb(r, g, b);
    }

    /** 中英双语：和 ArkTS 同一个写法，少一层 key 间接。 */
    public static String t(String zhText, String enText) {
        return zh ? zhText : enText;
    }

    public static float dp(Context context, float value) {
        return TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, value,
                context.getResources().getDisplayMetrics());
    }

    public static int dpInt(Context context, float value) {
        return Math.round(dp(context, value));
    }

    public static float sp(float base) {
        return base * fontScale;
    }

    public static GradientDrawable round(int fill, float radiusDp, Context context) {
        GradientDrawable d = new GradientDrawable();
        d.setColor(fill);
        d.setCornerRadius(dp(context, radiusDp));
        return d;
    }

    public static GradientDrawable roundStroke(int fill, int stroke, float radiusDp, Context context) {
        GradientDrawable d = round(fill, radiusDp, context);
        d.setStroke(dpInt(context, 1), stroke);
        return d;
    }

    public static TextView label(Context context, String value, float sizeSp, int color) {
        TextView tv = new TextView(context);
        tv.setText(value);
        tv.setTextSize(sp(sizeSp));
        tv.setTextColor(color);
        return tv;
    }

    public static View spacer(Context context, int heightDp) {
        View v = new View(context);
        v.setLayoutParams(new ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT,
                dpInt(context, heightDp)));
        return v;
    }

    /** 提亮（用于选中态色块，保证 emoji 可见）。 */
    public static int lighten(int color) {
        int r = Math.min(255, (int) (Color.red(color) * 0.55f + 255 * 0.45f));
        int g = Math.min(255, (int) (Color.green(color) * 0.55f + 255 * 0.45f));
        int b = Math.min(255, (int) (Color.blue(color) * 0.55f + 255 * 0.45f));
        return Color.rgb(r, g, b);
    }

    public static int alpha(int color, float ratio) {
        return Color.argb((int) (ratio * 255), Color.red(color), Color.green(color), Color.blue(color));
    }
}
