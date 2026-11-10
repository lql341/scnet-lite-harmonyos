/**
 * 对话相关的纯逻辑（可被 Node 单测直接跑，不 import 任何 kit）。
 */

export interface ChatTurn {
  role: string;
  content: string;
}

/** 单次请求携带的历史上限（字符数，粗估 token≈chars/3）。 */
export const HISTORY_LIMIT: number = 24000;
/** 无论如何至少保留最近这么多条。 */
export const HISTORY_MIN_KEEP: number = 6;

export interface TrimResult {
  /** 实际发送的历史（按原顺序） */
  turns: ChatTurn[];
  /** 被裁掉的条数（>0 时 UI 应提示用户） */
  dropped: number;
}

/**
 * 上下文裁剪：从最新往前累计字符数，超过上限就停，但至少保留最近 MIN 条。
 * 不改变最近语义（最近的消息永远保留），只丢最老的部分。
 */
export function trimHistory(turns: ChatTurn[], limit: number = HISTORY_LIMIT,
  minKeep: number = HISTORY_MIN_KEEP): TrimResult {
  const out: ChatTurn[] = [];
  let chars: number = 0;
  for (let i = turns.length - 1; i >= 0; i--) {
    const turn: ChatTurn = turns[i];
    const cost: number = turn.content.length;
    const enough: boolean = out.length >= minKeep && chars + cost > limit;
    if (enough) {
      out.reverse();
      const result: TrimResult = { turns: out, dropped: i + 1 };
      return result;
    }
    out.push(turn);
    chars += cost;
  }
  out.reverse();
  const all: TrimResult = { turns: out, dropped: 0 };
  return all;
}

/** 粗估 token（中文按 1 字 1 token、英文按 4 字符 1 token 的保守混合）。 */
export function estimateTokens(turns: ChatTurn[]): number {
  let n: number = 0;
  for (let i = 0; i < turns.length; i++) {
    const text: string = turns[i].content;
    let wide: number = 0;
    for (let j = 0; j < text.length; j++) {
      if (text.charCodeAt(j) > 0x2e80) {
        wide++;
      }
    }
    n += wide + Math.ceil((text.length - wide) / 4);
  }
  return n;
}
