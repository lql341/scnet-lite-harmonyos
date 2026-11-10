/**
 * 本地会话持久化。
 *
 * 为什么不用 preferences：preferences 的字符串值有长度上限，聊天记录很容易超。
 * 这里直接落文件（沙箱 `filesDir/sessions/`）：
 *
 *   filesDir/sessions/index.json      → [{id,title,model,updatedAt,count}]
 *   filesDir/sessions/<id>.json       → {id,title,model,createdAt,updatedAt,messages:[{role,content}]}
 *
 * 所有 IO 都吞异常：存储坏掉不能让人打不开 App。
 */
import { fileIo as fs } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { common } from '@kit.AbilityKit';

const TAG: string = 'SCNetLite';
const DIR: string = 'sessions';

export interface StoredMessage {
  role: string;
  content: string;
  /** 这条回答来自哪条通道（'智能体服务' / 'SCNet Max'），用户消息为空 */
  via?: string;
}

/** 抽屉列表用的摘要（不含正文，避免扫目录时读大文件）。 */
export interface SessionMeta {
  id: string;
  title: string;
  model: string;
  updatedAt: number;
  count: number;
}

export interface SessionData {
  id: string;
  title: string;
  model: string;
  createdAt: number;
  updatedAt: number;
  messages: StoredMessage[];
}

function now(): number {
  return Date.now();
}

/** 首条用户消息 → 标题（去掉换行、截断）。 */
export function titleFrom(messages: StoredMessage[]): string {
  for (let i = 0; i < messages.length; i++) {
    if (messages[i].role === 'user') {
      const text: string = messages[i].content.replace(/\s+/g, ' ').trim();
      if (text.length > 0) {
        return text.length > 24 ? `${text.substring(0, 24)}…` : text;
      }
    }
  }
  return '新对话';
}

class Sessions {
  private root: string = '';

  init(context: common.UIAbilityContext): void {
    this.root = `${context.filesDir}/${DIR}`;
    try {
      if (!fs.accessSync(this.root)) {
        fs.mkdirSync(this.root);
      }
    } catch (e) {
      hilog.error(0x0000, TAG, 'sessions dir init failed');
    }
  }

  private indexPath(): string {
    return `${this.root}/index.json`;
  }

  private filePath(id: string): string {
    return `${this.root}/${id}.json`;
  }

  private readText(path: string): string {
    try {
      if (!fs.accessSync(path)) {
        return '';
      }
      return fs.readTextSync(path);
    } catch (e) {
      return '';
    }
  }

  private writeText(path: string, text: string): void {
    try {
      const file = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, text);
      fs.fsyncSync(file.fd);
      fs.closeSync(file);
    } catch (e) {
      hilog.error(0x0000, TAG, 'sessions write failed');
    }
  }

  /** 按 updatedAt 倒序列出会话摘要。 */
  list(): SessionMeta[] {
    const text: string = this.readText(this.indexPath());
    if (text.length === 0) {
      return [];
    }
    try {
      const list: SessionMeta[] = JSON.parse(text) as SessionMeta[];
      if (!Array.isArray(list)) {
        return [];
      }
      list.sort((a: SessionMeta, b: SessionMeta) => b.updatedAt - a.updatedAt);
      return list;
    } catch (e) {
      hilog.warn(0x0000, TAG, 'sessions index unparsable');
      return [];
    }
  }

  load(id: string): SessionData | null {
    const text: string = this.readText(this.filePath(id));
    if (text.length === 0) {
      return null;
    }
    try {
      return JSON.parse(text) as SessionData;
    } catch (e) {
      return null;
    }
  }

  /** 保存（新建或覆盖），同时刷新索引。 */
  save(data: SessionData): void {
    const record: SessionData = {
      id: data.id,
      title: data.title,
      model: data.model,
      createdAt: data.createdAt,
      updatedAt: now(),
      messages: data.messages
    };
    this.writeText(this.filePath(record.id), JSON.stringify(record));

    const list: SessionMeta[] = this.list();
    const meta: SessionMeta = {
      id: record.id,
      title: record.title,
      model: record.model,
      updatedAt: record.updatedAt,
      count: record.messages.length
    };
    let found: boolean = false;
    for (let i = 0; i < list.length; i++) {
      if (list[i].id === record.id) {
        list[i] = meta;
        found = true;
        break;
      }
    }
    if (!found) {
      list.push(meta);
    }
    this.writeText(this.indexPath(), JSON.stringify(list));
  }

  /** 只改标题（会话内容不动）。 */
  rename(id: string, title: string): boolean {
    const data: SessionData | null = this.load(id);
    if (data === null) {
      return false;
    }
    const updated: SessionData = {
      id: data.id,
      title: title,
      model: data.model,
      createdAt: data.createdAt,
      updatedAt: data.updatedAt,
      messages: data.messages
    };
    this.save(updated);
    return true;
  }

  remove(id: string): void {
    try {
      if (fs.accessSync(this.filePath(id))) {
        fs.unlinkSync(this.filePath(id));
      }
    } catch (e) {
      hilog.warn(0x0000, TAG, 'sessions remove file failed');
    }
    const list: SessionMeta[] = this.list().filter((item: SessionMeta) => item.id !== id);
    this.writeText(this.indexPath(), JSON.stringify(list));
  }

  clear(): void {
    const list: SessionMeta[] = this.list();
    for (let i = 0; i < list.length; i++) {
      this.remove(list[i].id);
    }
    this.writeText(this.indexPath(), '[]');
  }

  newId(): string {
    return `s_${now()}_${Math.floor(Math.random() * 1000)}`;
  }
}

export const sessions: Sessions = new Sessions();
