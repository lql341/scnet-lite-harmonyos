/**
 * HMAC-SHA256（纯逻辑，不 import 任何 kit → 可被 Node 单测）。
 *
 * 为什么手写：ArkTS `cryptoFramework.createMac('SHA256')` 实测产出的摘要
 * **与标准 HMAC-SHA256 不一致**（同一 key/message 与 Python hmac 对不上，
 * 平台因此报「AK/SK签名校验失败」）。所以这里按 RFC 2104 自己拼 ipad/opad，
 * 摘要用注入的 sha256 函数（生产环境传 cryptoFramework 的 Md）。
 */

export type Sha256Fn = (data: Uint8Array) => Uint8Array;

const BLOCK: number = 64;

export function hmacSha256(key: Uint8Array, message: Uint8Array, sha256: Sha256Fn): Uint8Array {
  const k: Uint8Array = new Uint8Array(BLOCK);
  if (key.length > BLOCK) {
    const hashed: Uint8Array = sha256(key);
    for (let i = 0; i < hashed.length; i++) {
      k[i] = hashed[i];
    }
  } else {
    for (let i = 0; i < key.length; i++) {
      k[i] = key[i];
    }
  }
  const inner: Uint8Array = new Uint8Array(BLOCK + message.length);
  for (let i = 0; i < BLOCK; i++) {
    inner[i] = k[i] ^ 0x36;
  }
  for (let i = 0; i < message.length; i++) {
    inner[BLOCK + i] = message[i];
  }
  const innerHash: Uint8Array = sha256(inner);

  const outer: Uint8Array = new Uint8Array(BLOCK + innerHash.length);
  for (let i = 0; i < BLOCK; i++) {
    outer[i] = k[i] ^ 0x5c;
  }
  for (let i = 0; i < innerHash.length; i++) {
    outer[BLOCK + i] = innerHash[i];
  }
  return sha256(outer);
}

/** 字节 → 小写十六进制。 */
export function toHex(bytes: Uint8Array): string {
  let hex: string = '';
  for (let i = 0; i < bytes.length; i++) {
    const h: string = bytes[i].toString(16);
    hex += h.length === 1 ? `0${h}` : h;
  }
  return hex;
}

/** UTF-8 编码（不依赖 util.TextEncoder，便于测试）。 */
export function utf8(text: string): Uint8Array {
  const out: number[] = [];
  for (let i = 0; i < text.length; i++) {
    let code: number = text.charCodeAt(i);
    if (code >= 0xd800 && code <= 0xdbff && i + 1 < text.length) {
      const low: number = text.charCodeAt(i + 1);
      if (low >= 0xdc00 && low <= 0xdfff) {
        code = ((code - 0xd800) << 10) + (low - 0xdc00) + 0x10000;
        i++;
      }
    }
    if (code < 0x80) {
      out.push(code);
    } else if (code < 0x800) {
      out.push(0xc0 | (code >> 6), 0x80 | (code & 0x3f));
    } else if (code < 0x10000) {
      out.push(0xe0 | (code >> 12), 0x80 | ((code >> 6) & 0x3f), 0x80 | (code & 0x3f));
    } else {
      out.push(0xf0 | (code >> 18), 0x80 | ((code >> 12) & 0x3f),
        0x80 | ((code >> 6) & 0x3f), 0x80 | (code & 0x3f));
    }
  }
  return new Uint8Array(out);
}

/** 平台签名用的 message：字段顺序固定 accessKey,timestamp,user。 */
export function hpcSignMessage(accessKey: string, timestamp: string, user: string): string {
  return `{"accessKey":"${accessKey}","timestamp":"${timestamp}","user":"${user}"}`;
}
