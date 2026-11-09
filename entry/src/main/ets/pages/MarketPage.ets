/**
 * 插件页（仿桌面客户端「插件」）：连接器 / 技能两个 Tab，
 * 搜索 + 排序 + 列表，点卡片用内嵌 Web 打开 AIHub 详情。
 */
import { router } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Theme } from '../common/Theme';
import { L } from '../common/I18n';
import { market, MarketItem, MarketResult, SORT_HOT, SORT_NEW, SORT_DOWNLOAD } from '../service/Market';

const TAG: string = 'SCNetLite';

@Entry
@Component
struct MarketPage {
  @StorageProp('themeRev') themeRev: number = 0;
  @State kind: string = 'mcp';
  @State sortField: string = SORT_HOT;
  @State keyword: string = '';
  @State items: MarketItem[] = [];
  @State total: number = 0;
  @State page: number = 1;
  @State pages: number = 0;
  @State loading: boolean = false;
  @State errorMsg: string = '';

  aboutToAppear(): void {
    this.load(true);
  }

  private async load(reset: boolean): Promise<void> {
    if (this.loading) {
      return;
    }
    this.loading = true;
    this.errorMsg = '';
    const page: number = reset ? 1 : this.page + 1;
    const result: MarketResult = this.kind === 'mcp'
      ? await market.connectors(this.keyword, page, this.sortField)
      : await market.skills(this.keyword, page, this.sortField);
    if (result.items.length === 0 && page === 1) {
      this.errorMsg = L.t('没有结果（换个关键词试试）', 'No results (try another keyword)');
    }
    this.items = reset ? result.items : this.items.concat(result.items);
    this.total = result.total;
    this.pages = result.pages;
    this.page = page;
    this.loading = false;
    hilog.info(0x0000, TAG, 'market page %{public}d/%{public}d items=%{public}d',
      page, result.pages, this.items.length);
  }

  private switchKind(kind: string): void {
    if (this.kind === kind) {
      return;
    }
    this.kind = kind;
    this.items = [];
    this.load(true);
  }

  @Builder
  tab(label: string, kind: string) {
    Text(label)
      .fontSize(Theme.fSmall)
      .fontColor(this.kind === kind ? Theme.text : Theme.textFaint)
      .fontWeight(this.kind === kind ? FontWeight.Medium : FontWeight.Normal)
      .padding({ left: 2, right: 2, top: 8, bottom: 8 })
      .border({
        width: { bottom: this.kind === kind ? 2 : 0 },
        color: Theme.accent
      })
      .onClick(() => {
        this.switchKind(kind);
      })
  }

  @Builder
  card(item: MarketItem) {
    Row({ space: 10 }) {
      if (item.iconUrl.length > 0) {
        Image(item.iconUrl)
          .width(36)
          .height(36)
          .borderRadius(9)
          .objectFit(ImageFit.Cover)
          .backgroundColor(Theme.surfaceAlt)
          .alt($r('app.media.app_icon'))
      } else {
        Text(item.name.substring(0, 1))
          .fontSize(15)
          .fontColor(Theme.accent)
          .width(36)
          .height(36)
          .textAlign(TextAlign.Center)
          .borderRadius(9)
          .backgroundColor(Theme.accentGhost)
      }
      Column({ space: 3 }) {
        Row({ space: 6 }) {
          Text(item.name)
            .fontSize(Theme.fSmall)
            .fontWeight(FontWeight.Medium)
            .fontColor(Theme.text)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          if (item.category.length > 0) {
            Text(item.category)
              .fontSize(9)
              .fontColor(Theme.textFaint)
              .padding({ left: 5, right: 5, top: 1, bottom: 1 })
              .backgroundColor(Theme.surfaceAlt)
              .borderRadius(4)
          }
        }
        .width('100%')
        Text(item.desc)
          .fontSize(10)
          .lineHeight(15)
          .fontColor(Theme.textFaint)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(`${item.author} · ${this.kind === 'mcp' ? L.t(`${item.browseCount} 次浏览`,
          `${item.browseCount} views`) : L.t(`${item.downloadCount} 次下载`, `${item.downloadCount} downloads`)}`)
          .fontSize(9)
          .fontColor(Theme.textFaint)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Text('›').fontSize(15).fontColor(Theme.textFaint)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({ left: 12, right: 12, top: 11, bottom: 11 })
    .backgroundColor(Theme.surface)
    .borderRadius(Theme.rMd)
    .border({ width: 1, color: Theme.hairline })
    .onClick(() => {
      router.pushUrl({
        url: 'pages/WebPage',
        params: { url: item.detailUrl, title: item.name }
      });
    })
  }

  build() {
    Column() {
      Row({ space: 8 }) {
        Text('‹')
          .fontSize(22)
          .fontColor(Theme.textSub)
          .width(32)
          .height(32)
          .textAlign(TextAlign.Center)
          .onClick(() => {
            router.replaceUrl({ url: 'pages/Index' });
          })
        Column({ space: 1 }) {
          Text(L.t('插件', 'Plugins'))
            .fontSize(Theme.fTitle)
            .fontFamily(Theme.fontDisplay)
            .fontColor(Theme.text)
          Text(L.t('连接器与技能，来自 AI 社区', 'Connectors and skills from AI community'))
            .fontSize(10)
            .fontColor(Theme.textFaint)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .width('100%')
      .height(52)
      .padding({ left: 8, right: 12 })

      // Tab + 排序
      Row({ space: 16 }) {
        this.tab(L.t('连接器', 'Connectors'), 'mcp')
        this.tab(L.t('技能', 'Skills'), 'skills')
        Blank().layoutWeight(1)
        Text(this.sortField === SORT_HOT ? L.t('最热', 'Hot')
          : (this.sortField === SORT_NEW ? L.t('最新', 'New') : L.t('最多下载', 'Downloads')))
          .fontSize(Theme.fTiny)
          .fontColor(Theme.accent)
          .onClick(() => {
            this.sortField = this.sortField === SORT_HOT ? SORT_NEW
              : (this.sortField === SORT_NEW ? SORT_DOWNLOAD : SORT_HOT);
            this.load(true);
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16 })
      .backgroundColor(Theme.bg)

      // 搜索
      Row({ space: 8 }) {
        TextInput({ text: this.keyword, placeholder: L.t('搜索连接器', 'Search connectors') })
          .height(36)
          .padding(0)
          .fontSize(Theme.fSmall)
          .backgroundColor(Color.Transparent)
          .placeholderColor(Theme.textFaint)
          .layoutWeight(1)
          .onChange((v: string) => {
            this.keyword = v;
          })
        Text(L.t('搜索', 'Go'))
          .fontSize(Theme.fTiny)
          .fontColor(Theme.accent)
          .onClick(() => {
            this.load(true);
          })
      }
      .width('100%')
      .padding({ left: 14, right: 10 })
      .margin({ left: 14, right: 14, top: 8, bottom: 6 })
      .backgroundColor(Theme.surfaceAlt)
      .borderRadius(Theme.rPill)
      .constraintSize({ maxWidth: '94%' })

      Row({ space: 6 }) {
        Text(L.t(`共 ${this.total} 个`, `${this.total} total`))
          .fontSize(10)
          .fontColor(Theme.textFaint)
          .layoutWeight(1)
        if (this.loading) {
          Text(L.t('加载中…', 'Loading…')).fontSize(10).fontColor(Theme.textFaint)
        }
      }
      .width('100%')
      .padding({ left: 18, right: 18, bottom: 4 })

      if (this.errorMsg.length > 0 && this.items.length === 0) {
        Column({ space: 10 }) {
          Text(this.errorMsg).fontSize(Theme.fSmall).fontColor(Theme.textFaint)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        List({ space: 8 }) {
          ForEach(this.items, (item: MarketItem) => {
            ListItem() {
              this.card(item)
            }
          }, (item: MarketItem) => `${item.id}-${item.name}`)

          if (this.page < this.pages) {
            ListItem() {
              Text(this.loading ? L.t('加载中…', 'Loading…') : L.t('加载更多', 'Load more'))
                .fontSize(Theme.fSmall)
                .fontColor(Theme.accent)
                .width('100%')
                .textAlign(TextAlign.Center)
                .padding({ top: 12, bottom: 16 })
                .onClick(() => {
                  this.load(false);
                })
            }
          }
        }
        .layoutWeight(1)
        .width('100%')
        .padding({ left: 14, right: 14, bottom: 12 })
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.bg)
    .key(`market-${this.themeRev}`)
  }
}
