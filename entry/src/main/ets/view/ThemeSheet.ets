/**
 * 主题色选择。改完立刻生效：写 preferences + bump AppStorage('themeVersion')，
 * 订阅了该键的页面会重建，build 里读到的就是新颜色。
 */
import { Theme, PALETTES, Palette } from '../common/Theme';
import { store } from '../service/Store';

@Component
export struct ThemeSheet {
  @StorageLink('themeVersion') themeVersion: number = 0;
  onClose: () => void = () => {
  };
  /** 选完主题后回调：宿主用 router.replaceUrl 重建自己，保证静态色值重新求值 */
  onChanged: (id: string) => void = () => {
  };

  private pick(palette: Palette): void {
    Theme.applyPalette(palette.id);
    store.setTheme(palette.id);
    this.themeVersion = this.themeVersion + 1;
    Theme.bumpRev();
    this.onChanged(palette.id);
  }

  @Builder
  swatch(palette: Palette) {
    Column({ space: 6 }) {
      Stack() {
        Circle()
          .width(44)
          .height(44)
          .fill(palette.accent)
        if (Theme.paletteId === palette.id) {
          Text('✓')
            .fontSize(16)
            .fontColor('#FFFFFF')
            .fontWeight(FontWeight.Bold)
        }
      }
      .width(44)
      .height(44)
      Text(palette.name)
        .fontSize(Theme.fTiny)
        .fontColor(Theme.paletteId === palette.id ? Theme.accent : Theme.textSub)
    }
    .width('25%')
    .padding({ top: 8, bottom: 8 })
    .onClick(() => {
      this.pick(palette);
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
          Text('主题色').fontSize(Theme.fTitle).fontFamily(Theme.fontDisplay).fontColor(Theme.text)
          Text('选中即刻生效，会记住') .fontSize(Theme.fTiny).fontColor(Theme.textFaint)
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
      .padding({ left: 4, right: 4, bottom: 8 })

      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(PALETTES, (palette: Palette) => {
          this.swatch(palette)
        }, (palette: Palette) => palette.id)
      }
      .width('100%')

      // 预览：用户气泡 + 按钮 + 引用块，让用户先看到效果
      Column({ space: 8 }) {
        Text('预览').fontSize(10).fontColor(Theme.textFaint).width('100%')
        Row() {
          Text('这是一条示例消息')
            .fontSize(Theme.fSmall)
            .fontColor(Theme.textOnAccent)
            .padding({ left: 12, right: 12, top: 8, bottom: 8 })
            .backgroundColor(Theme.accent)
            .borderRadius({ topLeft: Theme.rLg, topRight: Theme.rLg, bottomLeft: Theme.rLg, bottomRight: 4 })
        }
        .width('100%')
        .justifyContent(FlexAlign.End)

        Row({ space: 8 }) {
          Text('主要按钮')
            .fontSize(Theme.fSmall)
            .fontColor(Theme.textOnAccent)
            .layoutWeight(1)
            .textAlign(TextAlign.Center)
            .padding({ top: 9, bottom: 9 })
            .backgroundColor(Theme.accent)
            .borderRadius(Theme.rSm)
          Text('次要')
            .fontSize(Theme.fSmall)
            .fontColor(Theme.accent)
            .layoutWeight(1)
            .textAlign(TextAlign.Center)
            .padding({ top: 9, bottom: 9 })
            .backgroundColor(Theme.accentGhost)
            .borderRadius(Theme.rSm)
        }
        .width('100%')
      }
      .width('100%')
      .padding(12)
      .margin({ top: 6 })
      .backgroundColor(Theme.bg)
      .borderRadius(Theme.rMd)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding({ left: 16, right: 16, bottom: 26 })
    .backgroundColor(Theme.surface)
    .borderRadius({ topLeft: Theme.rXl, topRight: Theme.rXl })
    .shadow(Theme.shadowSheet)
  }
}
