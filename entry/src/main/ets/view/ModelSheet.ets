/**
 * 智能体服务选择面板。
 * v2 对话的 modelId 是"服务"级（aiagent-router / aiagent-general / aiagent-science …），
 * 不是 config/list 里的 LLM 模型（那些只在网关 /api/llm/v1 用得上）。
 */
import { AgentService } from '../model/Types';

@Component
export struct ModelSheet {
  @Prop services: AgentService[] = [];
  @Prop currentModelId: number = 0;
  onPick: (service: AgentService) => void = () => {
  };
  onClose: () => void = () => {
  };

  build() {
    Column() {
      Row() {
        Text('选择智能体服务').fontSize(14).fontWeight(FontWeight.Medium).layoutWeight(1)
        Text('✕').fontSize(14).fontColor('#8A8F99').onClick(() => {
          this.onClose();
        })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 8 })

      Divider().color('#EEF0F3')

      List({ space: 0 }) {
        ForEach(this.services, (item: AgentService) => {
          ListItem() {
            Row({ space: 8 }) {
              Column() {
                Text(item.aiAssistantName ?? item.identify ?? '')
                  .fontSize(14)
                  .fontColor('#1F2329')
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                if ((item.description ?? '').length > 0) {
                  Text(item.description)
                    .fontSize(11)
                    .fontColor('#8A8F99')
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              if (Number(item.modelId ?? '0') === this.currentModelId) {
                Text('✓').fontSize(14).fontColor('#0A7EA4')
              }
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 10, bottom: 10 })
          }
          .onClick(() => {
            this.onPick(item);
          })
        }, (item: AgentService) => `${item.identify ?? ''}`)
      }
      .width('100%')
      .height(320)
    }
    .width('100%')
    .backgroundColor('#FFFFFF')
    .borderRadius({ topLeft: 16, topRight: 16 })
  }
}
