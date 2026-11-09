/**
 * 统一选择面板：智能体服务（平台）+ 模型（网关）两组，带搜索。
 * 两组共用同一个数据结构 PickItem，选中后由 Index 决定走哪条通道。
 */
import { Theme } from '../common/Theme';
import { KIND_AGENT, PickItem } from '../model/Pick';

@Component
export struct ModelSheet {
  @Prop items: PickItem[] = [];
  @Prop currentKey: string = '';
  @State query: string = '';
  onPick: (item: PickItem) => void = () => {
  };
  onClose: () => void = () => {
  };

  private filtered(kind: string): PickItem[] {
    const q: string = this.query.trim().toLowerCase();
    const out: PickItem[] = [];
    for (let i = 0; i < this.items.length; i++) {
      const item: PickItem = this.items[i];
      if (item.kind !== kind) {
        continue;
      }
      if (q.length === 0 || item.label.toLowerCase().indexOf(q) >= 0 ||
        item.sub.toLowerCase().indexOf(q) >= 0) {
        out.push(item);
      }
    }
    return out;
  }

  private total(): number {
    return this.filtered(KIND_AGENT).length + this.filtered('llm').length;
  }

  private listHeight(): number {
    const count: number = this.total();
    const wanted: number = count * 44 + 56;
    return wanted > 330 ? 330 : wanted;
  }

  @Builder
  sectionTitle(text: string, hint: string) {
    Row({ space: 6 }) {
      Text(text).fontSize(Theme.fTiny).fontColor(Theme.textFaint)
      Text(hint).fontSize(10).fontColor(Theme.textFaint).opacity(0.8)
    }
    .width('100%')
    .padding({ left: 4, top: 10, bottom: 2 })
  }

  @Builder
  row(item: PickItem) {
    Row({ space: 8 }) {
      Column({ space: 2 }) {
        Row({ space: 6 }) {
          Text(item.label)
            .fontSize(Theme.fBody)
            .fontColor(item.key === this.currentKey ? Theme.accent : Theme.text)
            .fontWeight(item.key === this.currentKey ? FontWeight.Medium : FontWeight.Normal)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          if (item.free) {
            Text('免费')
              .fontSize(10)
              .fontColor(Theme.ok)
              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
              .backgroundColor('#E8F8F0')
              .borderRadius(5)
          }
        }
        Text(item.sub)
          .fontSize(10)
          .fontColor(Theme.textFaint)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      if (item.key === this.currentKey) {
        Text('✓').fontSize(14).fontColor(Theme.accent).fontWeight(FontWeight.Bold)
      }
    }
    .width('100%')
    .padding({ left: 4, right: 4, top: 9, bottom: 9 })
  }

  build() {
    Column() {
      Row()
        .width(36)
        .height(4)
        .borderRadius(2)
        .backgroundColor(Theme.surfaceSunken)
        .margin({ top: 8, bottom: 6 })

      Row() {
        Column({ space: 2 }) {
          Text('选择通道').fontSize(Theme.fTitle).fontWeight(FontWeight.Medium).fontColor(Theme.text)
          Text('智能体走平台服务，模型走网关（SCNet Max 免费）')
            .fontSize(Theme.fTiny)
            .fontColor(Theme.textFaint)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Text('✕')
          .fontSize(14)
          .fontColor(Theme.textFaint)
          .width(30)
          .height(30)
          .textAlign(TextAlign.Center)
          .borderRadius(15)
          .backgroundColor(Theme.surfaceAlt)
          .onClick(() => {
            this.onClose();
          })
      }
      .width('100%')
      .padding({ left: 4, right: 4, bottom: 10 })

      Row({ space: 8 }) {
        TextInput({ text: this.query, placeholder: '搜索智能体或模型' })
          .height(36)
          .padding(0)
          .fontSize(Theme.fSmall)
          .backgroundColor(Color.Transparent)
          .placeholderColor(Theme.textFaint)
          .layoutWeight(1)
          .onChange((value: string) => {
            this.query = value;
          })
      }
      .width('100%')
      .padding({ left: 14, right: 10 })
      .backgroundColor(Theme.surfaceAlt)
      .borderRadius(Theme.rPill)
      .margin({ bottom: 2 })

      if (this.total() === 0) {
        Column() {
          Text('没有匹配项').fontSize(Theme.fSmall).fontColor(Theme.textFaint)
        }
        .width('100%')
        .height(120)
        .justifyContent(FlexAlign.Center)
      } else {
        List() {
          if (this.filtered(KIND_AGENT).length > 0) {
            ListItem() {
              this.sectionTitle('智能体服务', '平台运行时，领域任务由服务端路由')
            }
          }
          ForEach(this.filtered(KIND_AGENT), (item: PickItem) => {
            ListItem() {
              this.row(item)
            }
            .onClick(() => {
              this.onPick(item);
            })
          }, (item: PickItem) => `a-${item.key}`)

          if (this.filtered('llm').length > 0) {
            ListItem() {
              this.sectionTitle('模型', '网关 OpenAI 兼容')
            }
          }
          ForEach(this.filtered('llm'), (item: PickItem) => {
            ListItem() {
              this.row(item)
            }
            .onClick(() => {
              this.onPick(item);
            })
          }, (item: PickItem) => `m-${item.key}`)
        }
        .width('100%')
        .height(this.listHeight())
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, bottom: 26 })
    .backgroundColor(Theme.surface)
    .borderRadius({ topLeft: Theme.rXl, topRight: Theme.rXl })
    .shadow(Theme.shadowSheet)
  }
}
