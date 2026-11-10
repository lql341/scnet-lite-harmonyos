/**
 * SSE 行缓冲（纯逻辑，**不 import 任何 kit**，因此能被 Node 单测直接跑）。
 *
 * 这里固定两个真实踩过的坑：
 *  1. **跨块多字节**：数据块可能把 UTF-8 汉字切成两半。解码器必须用 stream 模式，
 *     不能对每块单独解码。解码器由调用方注入（ArkTS 传 `util.TextDecoder`，测试传 Node 的）。
 *  2. **无换行的残留**：网关错误体（402/401）是**单行 JSON 且末尾没有换行**，
 *     只按 `\n` 切行永远等不到它，流结束时必须 `flush()`。
 *
 * 用法（Gateway.ets / AgentChat.ets）：
 *   const decoder = util.TextDecoder.create('utf-8', { ignoreBOM: true });
 *   const buf = new SseBuffer((bytes: Uint8Array) => decoder.decodeToString(bytes, { stream: true }));
 *   request.on('dataReceive', (chunk) => buf.pushBytes(new Uint8Array(chunk)).forEach(handleLine));
 *   request.on('dataEnd', () => { buf.flush().forEach(handleLine); ... });
 */

export type SseDecodeFn = (bytes: Uint8Array) => string;

export class SseBuffer {
  private decode: SseDecodeFn;
  private buffer: string = '';

  constructor(decode: SseDecodeFn) {
    this.decode = decode;
  }

  /** 喂一块字节（跨块多字节由注入的解码器负责），返回本次凑齐的完整行。 */
  pushBytes(chunk: Uint8Array): string[] {
    this.buffer += this.decode(chunk);
    return this.drain();
  }

  /** 喂一段已解码文本（测试 / 非字节来源）。 */
  pushText(text: string): string[] {
    this.buffer += text;
    return this.drain();
  }

  /** 流结束：把没有结尾换行的残留作为最后一行吐出。幂等。 */
  flush(): string[] {
    const rest: string = this.buffer.trim();
    this.buffer = '';
    return rest.length > 0 ? [rest] : [];
  }

  /** 当前未消费的残留长度（诊断用）。 */
  pending(): number {
    return this.buffer.length;
  }

  private drain(): string[] {
    const out: string[] = [];
    let index: number = this.buffer.indexOf('\n');
    while (index >= 0) {
      const line: string = this.buffer.substring(0, index).replace(/\r$/, '').trim();
      this.buffer = this.buffer.substring(index + 1);
      if (line.length > 0) {
        out.push(line);
      }
      index = this.buffer.indexOf('\n');
    }
    return out;
  }
}

/** 从 `data: {...}` 行里取 payload；不是 data 行返回空串。 */
export function ssePayload(line: string): string {
  if (!line.startsWith('data:')) {
    return '';
  }
  return line.substring(5).trim();
}
