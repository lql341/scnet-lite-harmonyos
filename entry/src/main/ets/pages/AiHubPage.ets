/**
 * AI 社区（AIHub）智能体市场。
 *
 * 数据来自 `POST /acx/aihub/selected/agent/list`（6 个，带 avatar/desc/sourceType）。
 * 点卡片 → 内嵌 Web 打开 `/ui/aihub/agent/{createUser}/{nameEn}`，并注入登录 cookie。
 */
import { router } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Theme } from '../common/Theme';
import { AiAgent, agentWebUrl, aiHub, sourceLabel } from '../service/AiHub';

const TAG: string = 'SCNetLite';

@Entry
@Component
struct AiHubPage {
  @State agents: AiAgent[] = [];
  @State loading: boolean = true;
  @State errorMsg: string = '';

  aboutToAppear(): void {
    this.load();
  }

  private async load(): Promise<void> {
    this.loading = true;
    this.errorMsg = '';
    const list: AiAgent[] = await aiHub.selectedAgents();
    this.agents = list;
    if (list.length === 0) {
      this.errorMsg = '没能加载智能体列表，检查网络或登录态';
    }
    this.loading = false;
    hilog.info(0x0000, TAG, 'aihub page: %{public}d', list.length);
  }

  private open(agent: AiAgent): void {
    const url: string = agentWebUrl(agent);
    router.pushUrl({
      url: 'pages/WebPage',
      params: { url: url, title: agent.nameCn ?? '智能体' }
    });
  }

  @Builder
  card(agent: AiAgent) {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Image(agent.avatarUrl !== undefined ? agent.avatarUrl : '')
          .width(36)
          .height(36)
          .borderRadius(10)
          .backgroundColor(Theme.surfaceAlt)
          .objectFit(ImageFit.Cover)
          .alt($r('app.media.app_icon'))
        Column({ space: 2 }) {
          Text(agent.nameCn ?? agent.nameEn ?? '未命名智能体')
            .fontSize(Theme.fSmall)
            .fontWeight(FontWeight.Medium)
            .fontColor(Theme.text)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(agent.createUser ?? '')
            .fontSize(10)
            .fontColor(Theme.textFaint)
            .maxLines(1)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .width('100%')

      Text(agent.desc ?? '')
        .fontSize(11)
        .lineHeight(16)
        .fontColor(Theme.textSub)
        .maxLines(3)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')

      Row({ space: 6 }) {
        Text(sourceLabel(agent.sourceType ?? ''))
          .fontSize(9)
          .fontColor(Theme.accent)
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .backgroundColor(Theme.accentGhost)
          .borderRadius(5)
        Blank().layoutWeight(1)
        Text('打开 ›').fontSize(10).fontColor(Theme.textFaint)
      }
      .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(12)
    .backgroundColor(Theme.surface)
    .borderRadius(Theme.rMd)
    .border({ width: 1, color: Theme.hairline })
    .onClick(() => {
      this.open(agent);
    })
  }

  build() {
    Column() {
      Row({ space: 10 }) {
        Text('‹')
          .fontSize(22)
          .fontColor(Theme.textSub)
          .width(32)
          .height(32)
          .textAlign(TextAlign.Center)
          .onClick(() => {
            try {
              router.back();
            } catch (e) {
              router.replaceUrl({ url: 'pages/Index' });
            }
          })
        Column({ space: 1 }) {
          Text('AI 社区')
            .fontSize(Theme.fTitle)
            .fontFamily(Theme.fontDisplay)
            .fontColor(Theme.text)
          Text('领域智能体 · 由平台与第三方提供')
            .fontSize(10)
            .fontColor(Theme.textFaint)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Text('市场')
          .fontSize(Theme.fTiny)
          .fontColor(Theme.accent)
          .padding({ left: 10, right: 10, top: 5, bottom: 5 })
          .backgroundColor(Theme.accentGhost)
          .borderRadius(Theme.rPill)
          .onClick(() => {
            router.pushUrl({
              url: 'pages/WebPage',
              params: { url: 'https://www.scnet.cn/ui/aihub/agent', title: 'AI 社区' }
            });
          })
      }
      .width('100%')
      .height(56)
      .padding({ left: 8, right: 14 })
      .backgroundColor(Theme.surface)
      .border({ width: { bottom: 1 }, color: Theme.hairline })

      if (this.loading) {
        Column({ space: 10 }) {
          LoadingProgress().width(26).height(26).color(Theme.accent)
          Text('正在加载智能体…').fontSize(Theme.fSmall).fontColor(Theme.textFaint)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.errorMsg.length > 0) {
        Column({ space: 12 }) {
          Text(this.errorMsg).fontSize(Theme.fSmall).fontColor(Theme.danger)
          Text('重试')
            .fontSize(Theme.fSmall)
            .fontColor(Theme.textOnAccent)
            .padding({ left: 18, right: 18, top: 8, bottom: 8 })
            .backgroundColor(Theme.accent)
            .borderRadius(Theme.rSm)
            .onClick(() => {
              this.load();
            })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        Scroll() {
          Column({ space: 10 }) {
            ForEach(this.agents, (agent: AiAgent) => {
              this.card(agent)
            }, (agent: AiAgent) => agent.agentId ?? '')
          }
          .width('100%')
          .padding({ left: 14, right: 14, top: 12, bottom: 20 })
        }
        .layoutWeight(1)
        .width('100%')
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.bg)
  }
}
