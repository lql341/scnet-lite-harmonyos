/**
 * 模型选择底部面板：搜索 + 列表 + 免费标识。
 * 33 个模型不搜索要划三屏，所以搜索框是必需的。
 */
import { Theme, prettyModel } from '../common/Theme';

/** 平台自营、不扣余额的模型（详情见 docs/PROTOCOL.md §10.2.2） */
const FREE_MODEL: string = 'SCNet-Max';

@Component
export struct ModelSheet {
  @Prop models: string[] = [];
  @Prop current: string = '';
  @State query: string = '';
  onPick: (name: string) => void = () => {
  };
  onClose: () => void = () => {
  };

  private filtered(): string[] {
    const q: string = this.query.trim().toLowerCase();
    if (q.length === 0) {
      return this.models;
    }
    const out: string[] = [];
    for (let i = 0; i < this.models.length; i++) {
      if (this.models[i].toLowerCase().indexOf(q) >= 0) {
        out.push(this.models[i]);
      }
    }
    return out;
  }

  @Builder
  row(name: string) {
    Row({ space: 10 }) {
      Column({ space: 2 }) {
        Row({ space: 6 }) {
          Text(prettyModel(name))
            .fontSize(Theme.fBody)
            .fontColor(Theme.text)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          if (name === FREE_MODEL) {
            Text('免费')
              .fontSize(10)
              .fontColor(Theme.ok)
              .padding({ left: 5, right: 5, top: 1, bottom: 1 })
              .backgroundColor('#E8F8F0')
              .borderRadius(5)
          }
        }
        Text(name)
          .fontSize(Theme.fTiny)
          .fontColor(Theme.textFaint)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      if (name === this.current) {
        Text('✓')
          .fontSize(15)
          .fontColor(Theme.accent)
          .fontWeight(FontWeight.Bold)
      }
    }
    .width('100%')
    .padding({ left: 4, right: 4, top: 10, bottom: 10 })
  }

  build() {
    Column() {
      // 拖拽指示条
      Row()
        .width(36)
        .height(4)
        .borderRadius(2)
        .backgroundColor(Theme.surfaceSunken)
        .margin({ top: 8, bottom: 6 })

      Row() {
        Column({ space: 2 }) {
          Text('选择模型').fontSize(Theme.fTitle).fontWeight(FontWeight.Medium).fontColor(Theme.text)
          Text(`共 ${this.models.length} 个 · SCNet Max 免费，其余需余额`)
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
        Text('🔍').fontSize(12).fontColor(Theme.textFaint)
        TextInput({ text: this.query, placeholder: '搜索模型' })
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
      .padding({ left: 12, right: 8 })
      .backgroundColor(Theme.surfaceAlt)
      .borderRadius(Theme.rPill)
      .margin({ bottom: 6 })

      if (this.filtered().length === 0) {
        Column() {
          Text('没有匹配的模型').fontSize(Theme.fSmall).fontColor(Theme.textFaint)
        }
        .width('100%')
        .height(120)
        .justifyContent(FlexAlign.Center)
      } else {
        List() {
          ForEach(this.filtered(), (name: string) => {
            ListItem() {
              this.row(name)
            }
            .onClick(() => {
              this.onPick(name);
            })
          }, (name: string) => name)
        }
        .divider({ strokeWidth: 1, color: Theme.hairline, startMargin: 4, endMargin: 4 })
        .width('100%')
        .height(340)
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, bottom: 20 })
    .backgroundColor(Theme.surface)
    .borderRadius({ topLeft: Theme.rXl, topRight: Theme.rXl })
    .shadow(Theme.shadowSheet)
  }
}
