// SSE 分帧单测。
//
// 被测对象是 `entry/src/main/ets/common/Sse.ets` 里的纯逻辑（Gateway / AgentChat 共用），
// 覆盖两个真实踩过的坑：
//   1. 跨块多字节字符（中文按 1 字节切开）不能出现乱码
//   2. 网关错误体是**单行无换行 JSON**，流结束时必须冲刷残留 buffer
import { readFileSync, mkdirSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const cache = resolve(root, 'test/.cache');
mkdirSync(cache, { recursive: true });
const src = readFileSync(resolve(root, 'entry/src/main/ets/common/Sse.ets'), 'utf8');
const out = resolve(cache, 'Sse.ts');
writeFileSync(out, src);
const sse = await import(out);

/** 测试用的解码器：用 Node 的 TextDecoder，stream 模式与 ArkTS 行为一致。 */
const nodeDecoder = new TextDecoder('utf-8');
const decode = (bytes) => nodeDecoder.decode(bytes, { stream: true });

let pass = 0;
let fail = 0;
function eq(actual, expected, label) {
  const a = JSON.stringify(actual);
  const e = JSON.stringify(expected);
  if (a === e) {
    pass++;
  } else {
    fail++;
    console.error(`  ✗ ${label}\n    expected ${e}\n    actual   ${a}`);
  }
}

// --- 基本分帧
const a = new sse.SseBuffer(decode);
eq(a.pushText('data: {"a":1}\ndata: {"b":2}\n'), ['data: {"a":1}', 'data: {"b":2}'], '一次两块');
eq(a.pushText(''), [], '空块');

const b = new sse.SseBuffer(decode);
eq(b.pushText('data: {"a"'), [], '半行不产出');
eq(b.pushText(':1}\n'), ['data: {"a":1}'], '补齐后产出');

const c = new sse.SseBuffer(decode);
eq(c.pushText('data: x\r\ndata: y\r\n'), ['data: x', 'data: y'], 'CRLF 行尾');

// --- 流结束冲刷（无换行的单行 JSON 错误体）
const d = new sse.SseBuffer(decode);
d.pushText('{"error":{"message":"Insufficient Balance","code":"402"}}');
eq(d.flush(), ['{"error":{"message":"Insufficient Balance","code":"402"}}'], 'flush 冲刷残留');
eq(d.flush(), [], 'flush 幂等');

// --- 空行与纯 `data:` 前缀
const e2 = new sse.SseBuffer(decode);
eq(e2.pushText('\n\ndata: v\n\n'), ['data: v'], '忽略空行');

// --- 多字节跨块：UTF-8 的中文被切开
const f = new sse.SseBuffer(decode);
const text = 'data: 你好\n';
const bytes = Buffer.from(text, 'utf8');
const cut = 8; // 切在"你"字中间
const first = f.pushBytes(bytes.subarray(0, cut));
const second = f.pushBytes(bytes.subarray(cut));
eq([...first, ...second], ['data: 你好'], '多字节跨块不乱码');

// --- 一行内多次 push 的累积
const g = new sse.SseBuffer(decode);
const chunks = ['da', 'ta: ', '{"k"', ':1}', '\n'];
let lines = [];
for (const ch of chunks) lines = lines.concat(g.pushText(ch));
eq(lines, ['data: {"k":1}'], '逐字符拼行');

console.log(`\nSseBuffer: ${pass} passed, ${fail} failed`);
process.exit(fail === 0 ? 0 : 1);
