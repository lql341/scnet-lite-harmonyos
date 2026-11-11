/**
 * Markdown 渲染组件：块级用原生组件排版，行内用 Span 段。
 * 只引 @kit.BasicServicesKit 的 pasteboard（代码块复制），不引入任何三方库。
 */
import { pasteboard } from '@kit.BasicServicesKit';
import { Theme } from '../common/Theme';
import {
  MdBlock, MdKind, MdSeg, normalizeImageUrl, parseInline, parseMarkdown
} from '../common/Markdown';

const MONO: string = 'HarmonyOS Sans Mono';

@Component
export struct MarkdownView {
  @Prop content: string = '';
  /** 流式输出中：末尾画一个光标块 */
  @Prop streaming: boolean = false;
  /** 主题版本：变化时强制重建，否则内部静态 Theme 色值不会重新求值 */
  @Prop rev: number = 0;
  @State copiedIndex: number = -1;

  private async copyCode(code: string, index: number): Promise<void> {
    try {
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, code);
      await pasteboard.getSystemPasteboard().setData(data);
      this.copiedIndex = index;
      setTimeout(() => {
        this.copiedIndex = -1;
      }, 1600);
    } catch (e) {
      // 复制失败不影响阅读
    }
  }

  /** 行内 Markdown：**粗** / *斜* / `码`，交给 Text 统一换行排版。 */
  @Builder
  inline(text: string, size: number, lineHeight: number, color: string) {
    Text() {
      ForEach(parseInline(text), (seg: MdSeg) => {
        Span(seg.text)
          .fontWeight(seg.bold ? FontWeight.Bold : FontWeight.Normal)
          .fontStyle(seg.italic ? FontStyle.Italic : FontStyle.Normal)
          .fontFamily(seg.code ? MONO : 'HarmonyOS Sans')
          .fontColor(seg.code ? Theme.text : color)
          .fontSize(seg.code ? size - 1 : size)
          .textBackgroundStyle(seg.code
            ? { color: Theme.surfaceSunken, radius: 4 }
            : { color: Color.Transparent, radius: 0 })
          .decoration({
            type: seg.strike === true ? TextDecorationType.LineThrough
              : (seg.link !== undefined && seg.link.length > 0 ? TextDecorationType.Underline
                : TextDecorationType.None),
            color: seg.link !== undefined && seg.link.length > 0 ? Theme.accent : color
          })
          .fontColor(seg.link !== undefined && seg.link.length > 0 ? Theme.accent : color)
      }, (seg: MdSeg, index: number) => `${index}-${seg.text.length}`)
    }
    .width('100%')
    .fontSize(size)
    .lineHeight(lineHeight)
    .fontColor(color)
  }

  @Builder
  heading(block: MdBlock) {
    Row() {
      if (block.kind === MdKind.H1) {
        Column()
          .width(3)
          .height(16)
          .borderRadius(2)
          .backgroundColor(Theme.accent)
          .margin({ right: 8 })
      }
      this.inline(
        block.text,
        block.kind === MdKind.H1 ? Theme.fH1 : (block.kind === MdKind.H2 ? Theme.fH2 : Theme.fTitle),
        block.kind === MdKind.H1 ? 28 : 24,
        Theme.text)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({ top: block.kind === MdKind.H1 ? 6 : 4, bottom: 2 })
  }

  @Builder
  bullet(block: MdBlock) {
    Row() {
      Column()
        .width(block.kind === MdKind.Ordered ? 0 : 5)
        .height(block.kind === MdKind.Ordered ? 0 : 5)
        .borderRadius(3)
        .backgroundColor(Theme.textFaint)
        .margin({ top: 9, right: 9 })
      if (block.kind === MdKind.Ordered) {
        Text(`${block.order}.`)
          .fontSize(Theme.fBody)
          .lineHeight(23)
          .fontColor(Theme.textFaint)
          .margin({ right: 6 })
      }
      Column() {
        this.inline(block.text, Theme.mdBody, Theme.mdLine - 1, Theme.text)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .padding({ left: 4 + block.level * 14, top: 1, bottom: 1 })
  }

  /**
   * 表格：手机上不做横向滚动（实测嵌套 Scroll 会被外层消息列表抢手势），
   * 改成「一整张卡 + 行分隔」的紧凑表格：
   *   - 表头一行深色底
   *   - 每行「首列标题 + 其余列 键:值」
   * 比逐行分开的卡片更像表格，也不会被截断。
   */
  @Builder
  table(block: MdBlock) {
    Column() {
      // 表头
      Row({ space: 8 }) {
        ForEach(block.rows[0], (header: string, index: number) => {
          Column() {
            this.inline(header, Theme.fTiny, 16, Theme.textSub)
          }
          .layoutWeight(index === 0 ? 3 : 4)
          .alignItems(HorizontalAlign.Start)
          .padding({ left: index === 0 ? 12 : 4, right: 4, top: 8, bottom: 8 })
        }, (header: string, index: number) => `h-${index}`)
      }
      .width('100%')
      .backgroundColor(Theme.surfaceAlt)
      .borderRadius({ topLeft: Theme.rMd, topRight: Theme.rMd })

      Divider().color(Theme.hairline)

      // 数据行
      ForEach(block.rows, (row: string[], rowIndex: number) => {
        if (rowIndex > 0) {
          Column({ space: 4 }) {
            // 首列当行标题
            if (row.length > 0) {
              this.inline(row[0], Theme.mdBody - 1, Theme.mdLine - 6, Theme.text)
            }
            // 其余列按表头列名展示
            if (row.length > 1) {
              Row({ space: 6 }) {
                ForEach(block.rows[0], (header: string, cellIndex: number) => {
                  if (cellIndex > 0 && cellIndex < row.length) {
                    Column({ space: 2 }) {
                      Text(header)
                        .fontSize(Theme.fTiny - 1)
                        .fontColor(Theme.textFaint)
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                      this.inline(row[cellIndex], Theme.mdBody - 2, Theme.mdLine - 8, Theme.textSub)
                    }
                    .alignItems(HorizontalAlign.Start)
                    .layoutWeight(1)
                  }
                }, (header: string, cellIndex: number) => `c-${rowIndex}-${cellIndex}`)
              }
              .width('100%')
              .alignItems(VerticalAlign.Top)
            }
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding({ left: 12, right: 12, top: 10, bottom: 10 })
          .backgroundColor(rowIndex % 2 === 0 ? Theme.surfaceAlt : Color.Transparent)

          if (rowIndex < block.rows.length - 1) {
            Divider().color(Theme.hairline)
          }
        }
      }, (row: string[], rowIndex: number) => `t-${rowIndex}`)
    }
    .width('100%')
    .clip(true)
    .margin({ top: 6, bottom: 6 })
    .borderRadius(Theme.rMd)
    .border({ width: 1, color: Theme.border })
  }

  /** 图片：oss:/// 自动映射到公共资源域名；失败时给出链接文字，不留白。 */
  @Builder
  image(block: MdBlock) {
    Column() {
      Image(normalizeImageUrl(block.url === undefined ? '' : block.url))
        .width('100%')
        .constraintSize({ maxHeight: 420 })
        .objectFit(ImageFit.Contain)
        .borderRadius(Theme.rSm)
        .backgroundColor(Theme.surfaceAlt)
        .alt($r('app.media.app_icon'))
      Text(block.url === undefined ? '' : block.url)
        .fontSize(Theme.fTiny - 1)
        .fontColor(Theme.textFaint)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: 2 })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ top: 4, bottom: 4 })
  }

  @Builder
  quote(block: MdBlock) {
    Row() {
      Column()
        .width(3)
        .borderRadius(2)
        .backgroundColor(Theme.accentSoft)
        .margin({ right: 10, top: 2, bottom: 2 })
      Column() {
        this.inline(block.text, Theme.mdBody, Theme.mdLine - 1, Theme.textSub)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .padding({ top: 2, bottom: 2 })
  }

  @Builder
  codeBlock(block: MdBlock, index: number) {
    Column() {
      Row() {
        Text(block.lang.length > 0 ? block.lang : 'code')
          .fontSize(Theme.fTiny)
          .fontColor(Theme.codeLabel)
          .fontFamily(MONO)
          .layoutWeight(1)
        Text(this.copiedIndex === index ? '已复制' : '复制')
          .fontSize(Theme.fTiny)
          .fontColor(this.copiedIndex === index ? Theme.ok : Theme.codeLabel)
          .onClick(() => {
            this.copyCode(block.code, index);
          })
      }
      .width('100%')
      .margin({ bottom: 8 })

      // 手机上横向滚动看代码很别扭：直接换行，长行按字符断
      Text(block.code)
        .fontSize(12.5)
        .lineHeight(19)
        .fontColor(Theme.codeText)
        .fontFamily(MONO)
        .width('100%')
        .wordBreak(WordBreak.BREAK_ALL)
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 10, bottom: 12 })
    .backgroundColor(Theme.codeBg)
    .borderRadius(Theme.rMd)
    .margin({ top: 4, bottom: 4 })
  }

  build() {
    Column({ space: 2 }) {
      ForEach(parseMarkdown(this.content), (block: MdBlock, index: number) => {
        if (block.kind === MdKind.Code) {
          this.codeBlock(block, index)
        } else if (block.kind === MdKind.Hr) {
          Divider().color(Theme.hairline).margin({ top: 8, bottom: 8 })
        } else if (block.kind === MdKind.H1 || block.kind === MdKind.H2 || block.kind === MdKind.H3) {
          this.heading(block)
        } else if (block.kind === MdKind.Bullet || block.kind === MdKind.Ordered) {
          this.bullet(block)
        } else if (block.kind === MdKind.Table) {
          this.table(block)
        } else if (block.kind === MdKind.Image) {
          this.image(block)
        } else if (block.kind === MdKind.Quote) {
          this.quote(block)
        } else {
          Row() {
            this.inline(block.text, Theme.mdBody, Theme.mdLine, Theme.text)
            if (this.streaming) {
              Text('▍')
                .fontSize(Theme.fBody)
                .fontColor(Theme.accent)
            }
          }
          .width('100%')
          .alignItems(VerticalAlign.Bottom)
        }
      }, (block: MdBlock, index: number) => `${index}-${block.kind}-${block.text.length}`)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .key(`md-${this.rev}-${this.streaming}`)
  }
}
