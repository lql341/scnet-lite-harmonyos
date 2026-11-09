/**
 * 场景面板（领域智能体）。
 * 分类 Tab + 场景卡：点一张卡就把它的预置 prompt 发出去（与桌面端一致）。
 */
import { Theme } from '../common/Theme';
import { ScenarioCategory, ScenarioItem } from '../service/Scenarios';

@Component
export struct ScenarioSheet {
  @Prop categories: ScenarioCategory[] = [];
  @Prop currentCategory: string = '';
  onPick: (item: ScenarioItem) => void = () => {
  };
  onClose: () => void = () => {
  };

  private items(): ScenarioItem[] {
    for (let i = 0; i < this.categories.length; i++) {
      if (this.categories[i].id === this.currentCategory) {
        return this.categories[i].items;
      }
    }
    return this.categories.length > 0 ? this.categories[0].items : [];
  }

  @Builder
  card(item: ScenarioItem) {
    Row({ space: 10 }) {
      Column({ space: 3 }) {
        Text(item.title)
          .fontSize(Theme.fBody)
          .fontColor(Theme.text)
          .fontWeight(FontWeight.Medium)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(item.summary)
          .fontSize(Theme.fTiny)
          .fontColor(Theme.textFaint)
          .lineHeight(17)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      if (item.inputCount > 0) {
        Text(`附件 ${item.inputCount}`)
          .fontSize(9)
          .fontColor(Theme.warn)
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .backgroundColor('#FFF4E5')
          .borderRadius(5)
      }
      Text('›').fontSize(16).fontColor(Theme.textFaint)
    }
    .width('100%')
    .padding({ left: 12, right: 10, top: 10, bottom: 10 })
    .backgroundColor(Theme.surface)
    .borderRadius(Theme.rMd)
    .border({ width: 1, color: Theme.hairline })
    .onClick(() => {
      this.onPick(item);
    })
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
          Text('场景').fontSize(Theme.fTitle).fontWeight(FontWeight.Medium).fontColor(Theme.text)
          Text('选一个领域任务，直接带着指令开始')
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

      Scroll() {
        Row({ space: 8 }) {
          ForEach(this.categories, (category: ScenarioCategory) => {
            Text(category.title)
              .fontSize(Theme.fSmall)
              .fontColor(category.id === this.currentCategory ? Theme.textOnAccent : Theme.textSub)
              .padding({ left: 12, right: 12, top: 7, bottom: 7 })
              .backgroundColor(category.id === this.currentCategory ? Theme.accent : Theme.surfaceAlt)
              .borderRadius(Theme.rPill)
              .onClick(() => {
                this.onPickCategory(category.id);
              })
          }, (category: ScenarioCategory) => category.id)
        }
        .padding({ left: 4, right: 4 })
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%')
      .margin({ bottom: 10 })

      List({ space: 8 }) {
        ForEach(this.items(), (item: ScenarioItem) => {
          ListItem() {
            this.card(item)
          }
        }, (item: ScenarioItem) => item.id)
      }
      .width('100%')
      .height(360)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .padding({ left: 16, right: 16, bottom: 26 })
    .backgroundColor(Theme.surface)
    .borderRadius({ topLeft: Theme.rXl, topRight: Theme.rXl })
    .shadow(Theme.shadowSheet)
  }

  onPickCategory: (id: string) => void = () => {
  };
}
