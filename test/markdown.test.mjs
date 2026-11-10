// Markdown 解析单测。
//
// 直接用 Node 跑 ArkTS 源文件：先把 .ets 复制成 .ts，再用
// `--experimental-transform-types` 把类型剥掉后 import（Markdown.ets 是纯逻辑、无 UI 装饰器）。
//
//   ./scripts/test.sh          # 或 node --experimental-transform-types test/markdown.test.mjs
import { readFileSync, mkdirSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const cache = resolve(root, 'test/.cache');
mkdirSync(cache, { recursive: true });

/** 把 .ets 源复制成可被 Node 加载的 .ts。 */
function loadEts(relPath) {
  const src = readFileSync(resolve(root, relPath), 'utf8');
  const out = resolve(cache, relPath.split('/').pop().replace(/\.ets$/, '.ts'));
  writeFileSync(out, src);
  return out;
}

const md = await import(loadEts('entry/src/main/ets/common/Markdown.ets'));

// MdKind 顺序见 Markdown.ets
const KIND = {
  0: 'H1', 1: 'H2', 2: 'H3', 3: 'P', 4: 'Bullet',
  5: 'Ordered', 6: 'Code', 7: 'Quote', 8: 'Hr', 9: 'Table'
};

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

function kinds(source) {
  return md.parseMarkdown(source).map((b) => KIND[b.kind]);
}

// ---------------------------------------------------------------- 块级
eq(kinds('# 一级\n## 二级\n### 三级'), ['H1', 'H2', 'H3'], '标题分级');

eq(kinds('- a\n- b\n- c'), ['Bullet', 'Bullet', 'Bullet'], '无序列表');
eq(kinds('1. one\n2. two'), ['Ordered', 'Ordered'], '有序列表');

eq(kinds('```js\ncode\n```'), ['Code'], '代码块');
eq(kinds('```js\n未闭合代码'), ['Code'], '未闭合代码块（流式半截）');
eq(md.parseMarkdown('```python\nprint(1)\n```')[0].lang, 'python', '代码块语言');
eq(md.parseMarkdown('```python\nprint(1)\n```')[0].code, 'print(1)', '代码块内容');

eq(kinds('> 引用一行'), ['Quote'], '引用');
eq(kinds('---'), ['Hr'], '分隔线');

// 段落合并：连续行并成一段
eq(md.parseMarkdown('第一行\n第二行').length, 1, '连续行合并为一段');
eq(md.parseMarkdown('第一行\n第二行')[0].text, '第一行 第二行', '段落内容以空格合并');
eq(kinds('甲\n\n乙'), ['P', 'P'], '空行分段');

// ---------------------------------------------------------------- 表格
const table = md.parseMarkdown('| 列1 | 列2 |\n|---|---|\n| x | y |\n| 1 | 2 |')[0];
eq(KIND[table.kind], 'Table', '表格识别');
eq(table.rows, [['列1', '列2'], ['x', 'y'], ['1', '2']], '表格行列');
eq(md.splitRow('| a | b |'), ['a', 'b'], 'splitRow 去首尾竖线');
eq(md.splitRow('a | b'), ['a', 'b'], 'splitRow 允许无首尾竖线');
eq(md.parseMarkdown('| a | b |\n| --- | --- |')[0].rows, [['a', 'b']], '只有表头也能识别');
eq(kinds('| a | b |\n| - |'), ['P'], '分隔行不合法（单个 -）时按段落处理（相邻行合并）');
// 表格后的行不应被吞
const withTail = md.parseMarkdown('| a | b |\n|---|---|\n| 1 | 2 |\n\n后面一段');
eq(withTail.map((b) => KIND[b.kind]), ['Table', 'P'], '表格后接段落');

// ---------------------------------------------------------------- 行内
const inline = (t) => md.parseInline(t).map((s) => [s.text, s.bold, s.italic, s.code]);

eq(inline('**粗**'), [['粗', true, false, false]], '行内粗体');
eq(inline('*斜*'), [['斜', false, true, false]], '行内斜体');
eq(inline('`码`'), [['码', false, false, true]], '行内代码');
eq(inline('前**粗**后'), [['前', false, false, false], ['粗', true, false, false], ['后', false, false, false]], '粗体前后文本');
eq(inline('**[链接](https://x.com)**'), [['链接', true, false, false]], '链接只留文本');
eq(inline('未闭合 **粗'), [['未闭合 **粗', false, false, false]], '未闭合标记保留字面量');
eq(inline('2 * 3 * 4'), [['2 * 3 * 4', false, false, false]], '星号包裹单字符按斜体处理不影响文本');
eq(inline(''), [], '空串');

// ---------------------------------------------------------------- 边界
eq(md.parseMarkdown('').length, 0, '空输入');
eq(md.parseMarkdown('\n\n\n').length, 0, '全是空行');
eq(md.parseMarkdown('   \n  \t \n').length, 0, '全是空白');

console.log(`\nMarkdown: ${pass} passed, ${fail} failed`);
process.exit(fail === 0 ? 0 : 1);
