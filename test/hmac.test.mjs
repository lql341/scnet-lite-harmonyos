// HMAC-SHA256（RFC 2104）单测：用 Node crypto 做参考实现，逐字节对比。
import { readFileSync, mkdirSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createHash, createHmac } from 'node:crypto';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const cache = resolve(root, 'test/.cache');
mkdirSync(cache, { recursive: true });
const out = resolve(cache, 'Hmac.ts');
writeFileSync(out, readFileSync(resolve(root, 'entry/src/main/ets/common/Hmac.ets'), 'utf8'));
const hmac = await import(out);

const sha256 = (bytes) => new Uint8Array(createHash('sha256').update(Buffer.from(bytes)).digest());
const ref = (key, msg) => createHmac('sha256', Buffer.from(key)).update(Buffer.from(msg)).digest('hex');

let pass = 0;
let fail = 0;
function eq(actual, expected, label) {
  if (actual === expected) { pass++; } else { fail++; console.error(`  ✗ ${label}\n    expected ${expected}\n    actual   ${actual}`); }
}

// RFC 4231 测试向量（1、2、6、7）
const vectors = [
  { key: Buffer.alloc(20, 0x0b), data: 'Hi There', expect: 'b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7' },
  { key: Buffer.from('Jefe'), data: 'what do ya want for nothing?', expect: '5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843' },
  { key: Buffer.alloc(131, 0xaa), data: 'Test Using Larger Than Block-Size Key - Hash Key First', expect: '60e431591ee0b67f0d8a26aacbf5b77f8e0bc6213728c5140546040f0ee37f54' },
  { key: Buffer.alloc(131, 0xaa), data: 'This is a test using a larger than block-size key and a larger than block-size data. The key needs to be hashed before being used by the HMAC algorithm.', expect: '9b09ffa71b942fcb27635fbcd5b0e944bfdc63644f0713938a7f51535c3a35e2' }
];
for (const v of vectors) {
  const got = hmac.toHex(hmac.hmacSha256(new Uint8Array(v.key), hmac.utf8(v.data), sha256));
  eq(got, v.expect, `RFC 4231 向量（keyLen=${v.key.length}）`);
}
// 与 Node crypto 随机对照
for (const [k, m] of [['key', 'The quick brown fox jumps over the lazy dog'], ['015b119973a34d748f4d8b54b685a1a7', '{"accessKey":"a","timestamp":"1","user":"u"}']]) {
  const got = hmac.toHex(hmac.hmacSha256(hmac.utf8(k), hmac.utf8(m), sha256));
  eq(got, ref(k, m), `与 node:crypto 对照（${k.slice(0, 6)}…）`);
}
// 中文 / emoji 的 UTF-8 编码
const cn = '{"user":"卢麒麟","n":"🎉"}';
eq(Buffer.from(hmac.utf8(cn)).toString('hex'), Buffer.from(cn, 'utf8').toString('hex'), 'utf8 编码与 Node 一致');
// 签名 message 字段顺序固定
eq(hmac.hpcSignMessage('AK', '123', 'u'), '{"accessKey":"AK","timestamp":"123","user":"u"}', '签名 message 字段顺序');

console.log(`\nHMAC: ${pass} passed, ${fail} failed`);
process.exit(fail === 0 ? 0 : 1);
