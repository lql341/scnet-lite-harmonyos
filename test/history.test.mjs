// 上下文裁剪 / token 估算单测。
import { readFileSync, mkdirSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const cache = resolve(root, 'test/.cache');
mkdirSync(cache, { recursive: true });
const out = resolve(cache, 'Chat.ts');
writeFileSync(out, readFileSync(resolve(root, 'entry/src/main/ets/common/Chat.ets'), 'utf8'));
const chat = await import(out);

let pass = 0;
let fail = 0;
function eq(actual, expected, label) {
  const a = JSON.stringify(actual);
  const e = JSON.stringify(expected);
  if (a === e) { pass++; } else { fail++; console.error(`  ✗ ${label}\n    expected ${e}\n    actual   ${a}`); }
}

const t = (role, content) => ({ role, content });

// 未超限：原样返回、不丢
const small = [t('user', 'a'), t('assistant', 'b')];
eq(chat.trimHistory(small, 100, 1), { turns: small, dropped: 0 }, '未超限不裁剪');

// 超限：丢最老，保留最近
const big = [];
for (let i = 0; i < 10; i++) big.push(t(i % 2 === 0 ? 'user' : 'assistant', 'x'.repeat(100)));
const r = chat.trimHistory(big, 350, 2);
eq(r.dropped, 7, '超限时丢弃最老的 7 条');
eq(r.turns.length, 3, '保留 3 条');
eq(r.turns[r.turns.length - 1].content.length, 100, '最后一条仍是原最后一条');

// minKeep 保护：即使一条就超限，也要保留最近 minKeep 条
const huge = [t('user', 'y'.repeat(1000)), t('assistant', 'z'.repeat(1000))];
eq(chat.trimHistory(huge, 100, 2).turns.length, 2, 'minKeep 保护生效');
eq(chat.trimHistory(huge, 100, 2).dropped, 0, 'minKeep 内不报丢弃');

// 空输入
eq(chat.trimHistory([], 100, 1), { turns: [], dropped: 0 }, '空历史');

// 顺序不被打乱
const ordered = [t('user', '1'), t('assistant', '2'), t('user', '3')];
eq(chat.trimHistory(ordered, 1000, 1).turns.map((x) => x.content), ['1', '2', '3'], '保持原顺序');

// token 估算：中文按字、英文按 4 字符
eq(chat.estimateTokens([t('user', '你好')]), 2, '中文 1 字 1 token');
eq(chat.estimateTokens([t('user', 'abcdefgh')]), 2, '英文 4 字符 1 token');
eq(chat.estimateTokens([]), 0, '空估算为 0');

// 常量合理
eq(chat.HISTORY_LIMIT >= 8000, true, '历史上限不至于过小');
eq(chat.HISTORY_MIN_KEEP >= 2, true, 'minKeep 至少 2');

console.log(`\nChat/trim: ${pass} passed, ${fail} failed`);
process.exit(fail === 0 ? 0 : 1);
