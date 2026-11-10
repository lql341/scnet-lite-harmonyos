/**
 * 视觉设计令牌。所有页面只引用这里，避免颜色/圆角/间距散落在各 @Builder 里。
 * 基调：深海蓝主色 + 中性灰阶，白卡片 + 大圆角 + 轻阴影。
 */
export interface Palette {
  id: string;
  name: string;
  accent: string;
  accentDeep: string;
  accentSoft: string;
  accentGhost: string;
  bg: string;
  surface: string;
  surfaceAlt: string;
  text: string;
  textSub: string;
  textFaint: string;
  border: string;
  hairline: string;
}

/** 可选主题（主色 + 背景微调）。顺序就是设置页里的排列顺序。 */
export const PALETTES: Palette[] = [
  {
    id: 'claude', name: '暖砂',
    accent: '#C15F3C', accentDeep: '#A44A2C', accentSoft: '#F2E4DC', accentGhost: '#FAF3EF',
    bg: '#F7F5F2', surface: '#FFFFFF', surfaceAlt: '#F1EDE7',
    text: '#1F1E1D', textSub: '#5D5A57', textFaint: '#8F8A84',
    border: '#E6DFD7', hairline: '#EFE9E2'
  },
  {
    id: 'scnet', name: 'SCNet 红',
    accent: '#C4161C', accentDeep: '#9E1116', accentSoft: '#F8E3E3', accentGhost: '#FDF4F4',
    bg: '#F7F5F3', surface: '#FFFFFF', surfaceAlt: '#F1EDEA',
    text: '#1F1B1A', textSub: '#5D5553', textFaint: '#8F8785',
    border: '#E7DFDC', hairline: '#F0EAE7'
  },
  {
    id: 'ocean', name: '深海蓝',
    accent: '#0B4F8A', accentDeep: '#083A66', accentSoft: '#E7F0F8', accentGhost: '#F3F8FC',
    bg: '#F4F6F9', surface: '#FFFFFF', surfaceAlt: '#F1F3F7',
    text: '#101828', textSub: '#475467', textFaint: '#98A2B3',
    border: '#E6E9EF', hairline: '#EFF1F5'
  },
  {
    id: 'graphite', name: '石墨',
    accent: '#1F2937', accentDeep: '#111827', accentSoft: '#E8EBEF', accentGhost: '#F5F6F8',
    bg: '#F4F5F7', surface: '#FFFFFF', surfaceAlt: '#EDEFF2',
    text: '#111827', textSub: '#4B5563', textFaint: '#9CA3AF',
    border: '#E2E5EA', hairline: '#EDEFF2'
  },
  {
    id: 'pine', name: '松绿',
    accent: '#0E7C66', accentDeep: '#0A5D4D', accentSoft: '#E2F2EE', accentGhost: '#F2FAF7',
    bg: '#F3F7F6', surface: '#FFFFFF', surfaceAlt: '#EAF2EF',
    text: '#12211E', textSub: '#47605A', textFaint: '#8FA8A1',
    border: '#DEE9E5', hairline: '#E9F1EE'
  },
  {
    id: 'amber', name: '琥珀',
    accent: '#B45309', accentDeep: '#8A3F07', accentSoft: '#FAEDE0', accentGhost: '#FEF8F2',
    bg: '#F8F5F1', surface: '#FFFFFF', surfaceAlt: '#F2EBE2',
    text: '#1F1A15', textSub: '#5C5348', textFaint: '#9C9184',
    border: '#E8DFD2', hairline: '#F1EAE0'
  },
  {
    id: 'violet', name: '紫罗兰',
    accent: '#5B3FA8', accentDeep: '#46308A', accentSoft: '#ECE8F9', accentGhost: '#F6F4FD',
    bg: '#F5F4F9', surface: '#FFFFFF', surfaceAlt: '#EEECF6',
    text: '#1B1726', textSub: '#544E68', textFaint: '#9891AC',
    border: '#E3DFEF', hairline: '#EEEBF7'
  },
  {
    id: 'rose', name: '玫瑰',
    accent: '#B02A5B', accentDeep: '#8C1F47', accentSoft: '#FAE8EF', accentGhost: '#FDF4F8',
    bg: '#F8F4F6', surface: '#FFFFFF', surfaceAlt: '#F4E9EE',
    text: '#211519', textSub: '#5E4A52', textFaint: '#A08D95',
    border: '#EADDE3', hairline: '#F4EBEF'
  }
];

export class Theme {
  // 背景与表面
  static bg: string = '#F7F5F2';
  static surface: string = '#FFFFFF';
  static surfaceAlt: string = '#F1EDE7';
  static surfaceSunken: string = '#EAE4DC';

  // 主色（运行时可换，见 applyPalette）
  static accent: string = '#C15F3C';
  static accentDeep: string = '#A44A2C';
  static accentSoft: string = '#F2E4DC';
  static accentGhost: string = '#FAF3EF';
  static paletteId: string = 'claude';

  /**
   * 切换主题。改完要让它生效：调用方 bump AppStorage('themeVersion')，
   * 订阅了该键的页面会重建，build 里读到的就是新颜色。
   */
  /** 浅色基色（深色模式要在它的基础上反推，不能直接覆盖） */
  private static lightAccent: string = '#C15F3C';
  private static lightAccentDeep: string = '#A44A2C';
  private static lightAccentSoft: string = '#F2E4DC';
  private static lightAccentGhost: string = '#FAF3EF';

  /** 'light' | 'dark'（已解析过，不是 system） */
  static dark: boolean = false;

  /**
   * 深色模式底色。刻意不用纯黑：暖砂主题在 #15130F 上更协调，
   * 文字用 '#F2EFEA' 而不是纯白，长时间看更舒服。
   */
  static applyDark(on: boolean): void {
    Theme.dark = on;
    if (on) {
      Theme.bg = '#15130F';
      Theme.surface = '#1F1C18';
      Theme.surfaceAlt = '#2A2620';
      Theme.surfaceSunken = '#332E27';
      Theme.text = '#F2EFEA';
      Theme.textSub = '#BDB6AC';
      Theme.textFaint = '#8C857B';
      Theme.border = '#3A342C';
      Theme.hairline = '#2C2823';
      // 主色在深色下要提亮一档，否则对比度不足
      Theme.accent = Theme.lighten(Theme.lightAccent);
      Theme.accentDeep = Theme.lightAccent;
      Theme.accentSoft = '#3A2A22';
      Theme.accentGhost = '#241C17';
      // 危险色：深色底上用更亮的红 + 深红底，避免大片浅粉
      Theme.danger = '#FF7A70';
      Theme.dangerSoft = '#3A1D1A';
      Theme.dangerBorder = '#7A3B36';
    } else {
      Theme.restoreLight();
    }
  }

  /** 恢复浅色（用记录下来的基色）。 */
  static restoreLight(): void {
    Theme.dark = false;
    Theme.danger = '#B42318';
    Theme.dangerSoft = '#FEF3F2';
    Theme.dangerBorder = '#FDA29B';
    Theme.applyPalette(Theme.paletteId);
  }

  /** 把 #RRGGBB 提亮（深色模式主色用）。 */
  private static lighten(hex: string): string {
    if (hex.length !== 7) {
      return hex;
    }
    const r: number = parseInt(hex.substring(1, 3), 16);
    const g: number = parseInt(hex.substring(3, 5), 16);
    const b: number = parseInt(hex.substring(5, 7), 16);
    const mix = (v: number): number => Math.min(255, Math.round(v + (255 - v) * 0.28));
    const toHex = (v: number): string => {
      const h: string = v.toString(16);
      return h.length === 1 ? `0${h}` : h;
    };
    return `#${toHex(mix(r))}${toHex(mix(g))}${toHex(mix(b))}`;
  }

  static applyPalette(id: string): void {
    let chosen: Palette | null = null;
    for (let i = 0; i < PALETTES.length; i++) {
      if (PALETTES[i].id === id) {
        chosen = PALETTES[i];
        break;
      }
    }
    if (chosen === null) {
      chosen = PALETTES[0];
    }
    Theme.paletteId = chosen.id;
    Theme.accent = chosen.accent;
    Theme.accentDeep = chosen.accentDeep;
    Theme.accentSoft = chosen.accentSoft;
    Theme.accentGhost = chosen.accentGhost;
    Theme.bg = chosen.bg;
    Theme.surface = chosen.surface;
    Theme.surfaceAlt = chosen.surfaceAlt;
    Theme.surfaceSunken = chosen.border;
    Theme.text = chosen.text;
    Theme.textSub = chosen.textSub;
    Theme.textFaint = chosen.textFaint;
    Theme.border = chosen.border;
    Theme.hairline = chosen.hairline;
    Theme.lightAccent = chosen.accent;
    Theme.lightAccentDeep = chosen.accentDeep;
    Theme.lightAccentSoft = chosen.accentSoft;
    Theme.lightAccentGhost = chosen.accentGhost;
    // 换配色时如果正处在深色模式，要重新套一次深色底色
    if (Theme.dark) {
      Theme.applyDark(true);
    }
  }

  static bumpRev(): void {
    const cur: number = AppStorage.get<number>('themeRev') ?? 0;
    AppStorage.setOrCreate('themeRev', cur + 1);
  }

  static findPalette(id: string): Palette {
    for (let i = 0; i < PALETTES.length; i++) {
      if (PALETTES[i].id === id) {
        return PALETTES[i];
      }
    }
    return PALETTES[0];
  }

  // 文本（随主题变）
  static text: string = '#1F1E1D';
  static textSub: string = '#5D5A57';
  static textFaint: string = '#8F8A84';
  static readonly textOnAccent: string = '#FFFFFF';

  // 边框/分隔（随主题变）
  static border: string = '#E6DFD7';
  static hairline: string = '#EFE9E2';

  /** 标题字体：Claude 那种衬线感。设备没有 serif 时会自动回落到系统字体。 */
  static readonly fontDisplay: string = 'serif';
  static readonly fontBody: string = 'HarmonyOS Sans';

  /** 正文字号档位：0 小 / 1 标准 / 2 大（0.9 / 1.0 / 1.15） */
  static fontLevel: number = 1;
  /** Markdown 正文与行高（跟着档位走） */
  static mdBody: number = 15.5;
  static mdLine: number = 26;

  static applyFontLevel(level: number): void {
    const lv: number = level < 0 ? 0 : (level > 2 ? 2 : level);
    const k: number = lv === 0 ? 0.9 : (lv === 2 ? 1.15 : 1.0);
    Theme.fontLevel = lv;
    Theme.fTiny = Math.round(11 * k);
    Theme.fSmall = Math.round(12 * k);
    Theme.fBody = Math.round(15 * k);
    Theme.fTitle = Math.round(16 * k);
    Theme.fH2 = Math.round(17 * k);
    Theme.fH1 = Math.round(20 * k);
    Theme.mdBody = Math.round(15.5 * k * 10) / 10;
    Theme.mdLine = Math.round(26 * k);
  }

  // 状态
  static danger: string = '#B42318';
  static dangerSoft: string = '#FEF3F2';
  static dangerBorder: string = '#FDA29B';
  static readonly ok: string = '#12B76A';
  static readonly warn: string = '#B54708';

  // 代码块（深色卡片）
  static readonly codeBg: string = '#111A26';
  static readonly codeText: string = '#E6EDF3';
  static readonly codeLabel: string = '#8FA3B8';

  // 圆角
  static readonly rSm: number = 8;
  static readonly rMd: number = 12;
  static readonly rLg: number = 16;
  static readonly rXl: number = 20;
  static readonly rPill: number = 999;

  // 间距
  static readonly s1: number = 4;
  static readonly s2: number = 8;
  static readonly s3: number = 12;
  static readonly s4: number = 16;
  static readonly s5: number = 20;
  static readonly s6: number = 24;

  // 字号
  static fTiny: number = 11;
  static fSmall: number = 12;
  static fBody: number = 15;
  static fTitle: number = 16;
  static fH2: number = 17;
  static fH1: number = 20;

  // 阴影
  static readonly shadowSoft: ShadowOptions = {
    radius: 16, color: '#0B1F3314', offsetX: 0, offsetY: 4
  };
  static readonly shadowSheet: ShadowOptions = {
    radius: 28, color: '#0B1F3324', offsetX: 0, offsetY: -6
  };
}

/**
 * 网关模型 id → 展示名。`DeepSeek-V4.1-Flash-1017` → `DeepSeek V4.1 Flash`，
 * `SCNet-Max` → `SCNet Max`。
 */
export function prettyModel(name: string): string {
  let out: string = name;
  const dash: number = out.lastIndexOf('-');
  if (dash > 0) {
    const tail: string = out.substring(dash + 1);
    if (tail.length >= 4 && Number.isNaN(Number(tail)) === false) {
      out = out.substring(0, dash);
    }
  }
  return out.replace(/-/g, ' ');
}

/** 平台字段经常是 null，ArkTS 里直接 .length 会抛，统一收口。 */
export function safe(value: Object | undefined | null): string {
  if (value === undefined || value === null) {
    return '';
  }
  if (typeof value === 'string') {
    return value as string;
  }
  return `${value}`;
}
