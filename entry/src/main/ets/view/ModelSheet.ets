/** 模型选择面板：列表 + 选中态 + 关闭。抽成独立组件，登录页/对话页共用同一套样式。 */
@Component
export struct ModelSheet {
  @Prop models: string[] = [];
  @Prop current: string = '';
  onPick: (name: string) => void = () => {
  };
  onClose: () => void = () => {
  };

  build() {
    Column() {
      Row() {
        Text('选择模型').fontSize(14).fontWeight(FontWeight.Medium).layoutWeight(1)
        Text('✕').fontSize(14).fontColor('#8A8F99').onClick(() => {
          this.onClose();
        })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 8 })

      Divider().color('#EEF0F3')

      List({ space: 0 }) {
        ForEach(this.models, (name: string) => {
          ListItem() {
            Row({ space: 8 }) {
              Text(name)
                .fontSize(14)
                .fontColor('#1F2329')
                .layoutWeight(1)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              if (name === this.current) {
                Text('✓').fontSize(14).fontColor('#0A7EA4')
              }
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 12, bottom: 12 })
          }
          .onClick(() => {
            this.onPick(name);
          })
        }, (name: string) => name)
      }
      .width('100%')
      .height(320)
    }
    .width('100%')
    .backgroundColor('#FFFFFF')
    .borderRadius({ topLeft: 16, topRight: 16 })
  }
}
