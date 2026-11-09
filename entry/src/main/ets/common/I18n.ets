/**
 * 极简中英双语。
 *
 * 不做 key 表：直接 `L.t('中文', 'English')`，少一层间接、少一处对不上。
 * 语言存在 preferences，切换后由页面重建生效（与主题同一套机制）。
 */
export class L {
  /** true = 中文 */
  static zh: boolean = true;

  static t(zh: string, en: string): string {
    return L.zh ? zh : en;
  }

  /** 按语言取对象里的 zh/en 字段（用于既有双语数据，如场景标题）。 */
  static pick(value: Object | undefined | null): string {
    if (value === undefined || value === null) {
      return '';
    }
    const map = value as Record<string, string>;
    const key: string = L.zh ? 'zh' : 'en';
    const hit = map[key];
    if (typeof hit === 'string' && (hit as string).length > 0) {
      return hit as string;
    }
    const zh = map['zh'];
    return typeof zh === 'string' ? zh as string : '';
  }
}
