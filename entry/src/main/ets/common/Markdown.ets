/**
 * 轻量 Markdown 渲染（不引入三方库、不用 Web 组件）。
 *
 * 为什么需要它：网关模型回的都是 Markdown（`# 标题`、`**加粗**`、`- 列表`、``` 代码块 ```），
 * 之前直接塞进 Text，屏幕上全是裸标记 —— 这是"看起来不精致"的最大来源。
 *
 * 设计：
 * - 块级（标题/段落/列表/引用/代码块/分隔线）各自用原生组件渲染，行高与间距可控；
 * - 行内（**粗** / *斜* / `码`）拆成 Span 段，交给 Text 统一排版（可正常换行）；
 * - 解析必须容忍"流式半截"输入：未闭合的 ``` ** 也按最接近的语义渲染。
 */

export enum MdKind {
  H1,
  H2,
  H3,
  P,
  Bullet,
  Ordered,
  Code,
  Quote,
  Hr,
  Table
}

export interface MdBlock {
  kind: MdKind;
  text: string;
  level: number;
  order: number;
  lang: string;
  code: string;
  /** 表格：首行是表头，其余是数据行；每行按 `|` 切好 */
  rows: string[][];
}

export interface MdTable {
  header: string[];
  rows: string[][];
}

/** `|a|b|` → ['a','b']；允许首尾不写竖线。 */
export function splitRow(line: string): string[] {
  let body: string = line.trim();
  if (body.startsWith('|')) {
    body = body.substring(1);
  }
  if (body.endsWith('|')) {
    body = body.substring(0, body.length - 1);
  }
  const out: string[] = [];
  const parts: string[] = body.split('|');
  for (let i = 0; i < parts.length; i++) {
    out.push(parts[i].trim());
  }
  return out;
}

/** 判断是不是分隔行（`|---|:--:|`）。 */
function isSeparator(line: string): boolean {
  const body: string = line.trim();
  if (body.indexOf('-') < 0) {
    return false;
  }
  const cells: string[] = splitRow(body);
  for (let i = 0; i < cells.length; i++) {
    if (!/^:?-{2,}:?$/.test(cells[i].replace(/\s/g, ''))) {
      return false;
    }
  }
  return cells.length > 0;
}

export interface MdSeg {
  text: string;
  bold: boolean;
  italic: boolean;
  code: boolean;
}

function isFence(line: string): boolean {
  const t: string = line.trim();
  return t.startsWith('```');
}

function fenceLang(line: string): string {
  return line.trim().substring(3).trim();
}

/**
 * 解析成块。刻意保持单遍、无递归、无正则回溯，长文本（几千字流式）也稳。
 */
export function parseMarkdown(source: string): MdBlock[] {
  const blocks: MdBlock[] = [];
  if (source.length === 0) {
    return blocks;
  }
  const lines: string[] = source.split('\n');
  let i: number = 0;
  let paragraph: string = '';

  const flushParagraph = (): void => {
    const text: string = paragraph.trim();
    if (text.length > 0) {
      const block: MdBlock = { kind: MdKind.P, text: text, level: 0, order: 0, lang: '', code: '', rows: [] };
      blocks.push(block);
    }
    paragraph = '';
  };

  while (i < lines.length) {
    const raw: string = lines[i];
    const line: string = raw.replace(/\r$/, '');
    const trimmed: string = line.trim();

    // ``` 代码块：未闭合时也照常渲染（流式中间态）
    if (isFence(line)) {
      flushParagraph();
      const lang: string = fenceLang(line);
      const body: string[] = [];
      i++;
      while (i < lines.length && !isFence(lines[i])) {
        body.push(lines[i]);
        i++;
      }
      i++; // 跳过闭合 ```（越界也无所谓）
      const code: MdBlock = {
        kind: MdKind.Code, text: '', level: 0, order: 0,
        lang: lang, code: body.join('\n'), rows: []
      };
      blocks.push(code);
      continue;
    }

    if (trimmed.length === 0) {
      flushParagraph();
      i++;
      continue;
    }

    // 表格：`|a|b|` + `|---|---|`
    if (trimmed.startsWith('|') && trimmed.indexOf('|', 1) > 0) {
      const nextLine: string = i + 1 < lines.length ? lines[i + 1] : '';
      if (isSeparator(nextLine)) {
        flushParagraph();
        const header: string[] = splitRow(trimmed);
        const rows: string[][] = [];
        let j: number = i + 2;
        while (j < lines.length) {
          const candidate: string = lines[j].trim();
          if (candidate.length === 0 || candidate.indexOf('|') < 0) {
            break;
          }
          rows.push(splitRow(candidate));
          j++;
        }
        const table: MdBlock = {
          kind: MdKind.Table, text: '', level: 0, order: 0, lang: '', code: '', rows: []
        };
        const all: string[][] = [header];
        for (let k = 0; k < rows.length; k++) {
          all.push(rows[k]);
        }
        table.rows = all;
        blocks.push(table);
        i = j;
        continue;
      }
    }

    // 分隔线
    if (trimmed === '---' || trimmed === '***' || trimmed === '___') {
      flushParagraph();
      const hr: MdBlock = { kind: MdKind.Hr, text: '', level: 0, order: 0, lang: '', code: '', rows: [] };
      blocks.push(hr);
      i++;
      continue;
    }

    // 标题
    if (trimmed.startsWith('#')) {
      let level: number = 0;
      while (level < trimmed.length && trimmed.charAt(level) === '#') {
        level++;
      }
      if (level >= 1 && level <= 6) {
        const rest: string = trimmed.substring(level).trim();
        if (rest.length > 0) {
          flushParagraph();
          const kind: MdKind = level === 1 ? MdKind.H1 : (level === 2 ? MdKind.H2 : MdKind.H3);
          const head: MdBlock = { kind: kind, text: rest, level: level, order: 0, lang: '', code: '', rows: [] };
          blocks.push(head);
          i++;
          continue;
        }
      }
    }

    // 引用
    if (trimmed.startsWith('>')) {
      flushParagraph();
      let text: string = trimmed;
      while (text.startsWith('>')) {
        text = text.substring(1).trim();
      }
      const quote: MdBlock = { kind: MdKind.Quote, text: text, level: 0, order: 0, lang: '', code: '', rows: [] };
      blocks.push(quote);
      i++;
      continue;
    }

    // 无序列表（- * +），按缩进算层级
    const bulletChar: string = trimmed.charAt(0);
    if ((bulletChar === '-' || bulletChar === '*' || bulletChar === '+') &&
      trimmed.length > 1 && (trimmed.charAt(1) === ' ' || trimmed.charAt(1) === '\t')) {
      flushParagraph();
      const indent: number = line.length - line.trimStart().length;
      const item: MdBlock = {
        kind: MdKind.Bullet,
        text: trimmed.substring(1).trim(),
        level: Math.min(2, Math.floor(indent / 2)),
        order: 0, lang: '', code: '', rows: []
      };
      blocks.push(item);
      i++;
      continue;
    }

    // 有序列表：1. / 1) / 1、
    let digits: number = 0;
    while (digits < trimmed.length && trimmed.charAt(digits) >= '0' && trimmed.charAt(digits) <= '9') {
      digits++;
    }
    if (digits > 0 && digits < 4 && trimmed.length > digits + 1) {
      const mark: string = trimmed.charAt(digits);
      if ((mark === '.' || mark === ')' || mark === '、') && trimmed.charAt(digits + 1) === ' ') {
        flushParagraph();
        const indent: number = line.length - line.trimStart().length;
        const item: MdBlock = {
          kind: MdKind.Ordered,
          text: trimmed.substring(digits + 1).trim(),
          level: Math.min(2, Math.floor(indent / 2)),
          order: Number(trimmed.substring(0, digits)),
          lang: '', code: '', rows: []
        };
        blocks.push(item);
        i++;
        continue;
      }
    }

    paragraph = paragraph.length === 0 ? trimmed : `${paragraph} ${trimmed}`;
    i++;
  }
  flushParagraph();
  return blocks;
}

/**
 * 行内解析：**粗体** / *斜体* / `行内代码`。
 * 未闭合的标记在流式过程中会出现，此时保留字面量而不是吞掉。
 */
/** `[文字](url)` → `文字`；用于段落里任何一段（含粗体内部）。 */
function stripLinks(text: string): string {
  if (text.indexOf('](') < 0) {
    return text;
  }
  let out: string = '';
  let i: number = 0;
  while (i < text.length) {
    const ch: string = text.charAt(i);
    if (ch === '[') {
      const mid: number = text.indexOf('](', i + 1);
      const close: number = mid > 0 ? text.indexOf(')', mid + 2) : -1;
      if (mid > 0 && close > mid) {
        out += text.substring(i + 1, mid);
        i = close + 1;
        continue;
      }
    }
    out += ch;
    i++;
  }
  return out;
}

export function parseInline(text: string): MdSeg[] {
  const segs: MdSeg[] = [];
  let pending: string = '';
  let i: number = 0;

  const push = (value: string, bold: boolean, italic: boolean, code: boolean): void => {
    const cleaned: string = code ? value : stripLinks(value);
    if (cleaned.length === 0) {
      return;
    }
    const seg: MdSeg = { text: cleaned, bold: bold, italic: italic, code: code };
    segs.push(seg);
  };
  const flush = (): void => {
    push(pending, false, false, false);
    pending = '';
  };

  while (i < text.length) {
    const ch: string = text.charAt(i);

    // 行内代码
    if (ch === '`') {
      const end: number = text.indexOf('`', i + 1);
      if (end > i + 1) {
        flush();
        push(text.substring(i + 1, end), false, false, true);
        i = end + 1;
        continue;
      }
    }

    // 粗体
    if (ch === '*' && i + 1 < text.length && text.charAt(i + 1) === '*') {
      const end: number = text.indexOf('**', i + 2);
      const inner: string = end > i + 2 ? text.substring(i + 2, end) : '';
      const tight: boolean = inner.length > 0 && inner.charAt(0) !== ' ' && inner.charAt(inner.length - 1) !== ' ';
      if (end > i + 2 && tight) {
        flush();
        push(text.substring(i + 2, end), true, false, false);
        i = end + 2;
        continue;
      }
    }

    // 斜体
    if (ch === '*') {
      const end: number = text.indexOf('*', i + 1);
      const inner: string = end > i + 1 ? text.substring(i + 1, end) : '';
      const tight: boolean = inner.length > 0 && inner.charAt(0) !== ' ' && inner.charAt(inner.length - 1) !== ' ';
      if (end > i + 1 && tight) {
        flush();
        push(text.substring(i + 1, end), false, true, false);
        i = end + 1;
        continue;
      }
    }

    // 链接 [文本](url)：只留文本，链接地址不显示
    if (ch === '[') {
      const mid: number = text.indexOf('](', i + 1);
      const close: number = mid > 0 ? text.indexOf(')', mid + 2) : -1;
      if (mid > 0 && close > mid) {
        flush();
        push(text.substring(i + 1, mid), false, false, false);
        i = close + 1;
        continue;
      }
    }

    pending += ch;
    i++;
  }
  flush();
  return segs;
}
