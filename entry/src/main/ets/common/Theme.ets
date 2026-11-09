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
}

/** 可选主题（主色 + 背景微调）。顺序就是设置页里的排列顺序。 */
export const PALETTES: Palette[] = [
  { id: 'ocean', name: '深海蓝', accent: '#0B4F8A', accentDeep: '#083A66', accentSoft: '#E7F0F8', accentGhost: '#F3F8FC', bg: '#F4F6F9' },
  { id: 'graphite', name: '石墨', accent: '#1F2937', accentDeep: '#111827', accentSoft: '#E8EBEF', accentGhost: '#F5F6F8', bg: '#F4F5F7' },
  { id: 'pine', name: '松绿', accent: '#0E7C66', accentDeep: '#0A5D4D', accentSoft: '#E2F2EE', accentGhost: '#F2FAF7', bg: '#F3F7F6' },
  { id: 'amber', name: '琥珀', accent: '#B45309', accentDeep: '#8A3F07', accentSoft: '#FAEDE0', accentGhost: '#FEF8F2', bg: '#F8F5F1' },
  { id: 'violet', name: '紫罗兰', accent: '#5B3FA8', accentDeep: '#46308A', accentSoft: '#ECE8F9', accentGhost: '#F6F4FD', bg: '#F5F4F9' },
  { id: 'rose', name: '玫瑰', accent: '#B02A5B', accentDeep: '#8C1F47', accentSoft: '#FAE8EF', accentGhost: '#FDF4F8', bg: '#F8F4F6' }
];

export class Theme {
  // 背景与表面
  static bg: string = '#F4F6F9';
  static readonly surface: string = '#FFFFFF';
  static readonly surfaceAlt: string = '#F1F3F7';
  static readonly surfaceSunken: string = '#EAEEF4';

  // 主色（运行时可换，见 applyPalette）
  static accent: string = '#0B4F8A';
  static accentDeep: string = '#083A66';
  static accentSoft: string = '#E7F0F8';
  static accentGhost: string = '#F3F8FC';
  static paletteId: string = 'ocean';

  /**
   * 切换主题。改完要让它生效：调用方 bump AppStorage('themeVersion')，
   * 订阅了该键的页面会重建，build 里读到的就是新颜色。
   */
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
  }

  static findPalette(id: string): Palette {
    for (let i = 0; i < PALETTES.length; i++) {
      if (PALETTES[i].id === id) {
        return PALETTES[i];
      }
    }
    return PALETTES[0];
  }

  // 文本
  static readonly text: string = '#101828';
  static readonly textSub: string = '#475467';
  static readonly textFaint: string = '#98A2B3';
  static readonly textOnAccent: string = '#FFFFFF';

  // 边框/分隔
  static readonly border: string = '#E6E9EF';
  static readonly hairline: string = '#EFF1F5';

  // 状态
  static readonly danger: string = '#B42318';
  static readonly dangerSoft: string = '#FEF3F2';
  static readonly dangerBorder: string = '#FDA29B';
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
  static readonly fTiny: number = 11;
  static readonly fSmall: number = 12;
  static readonly fBody: number = 15;
  static readonly fTitle: number = 16;
  static readonly fH2: number = 17;
  static readonly fH1: number = 20;

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
