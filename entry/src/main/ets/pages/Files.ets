/**
 * 文件与日志浏览（HPC efile + hpc file/content）。
 *
 * 契约（本机 curl 实测）：
 *   GET  {efile}/efile/openapi/v2/file/list?path=<dir>   → data.children[{path,id,label}]
 *        ⚠️ 根目录 `/` 返回 911030 无权限，必须从 homePath 起浏览
 *   POST {hpc}/hpc/openapi/v2/file/content  (form)
 *        hostName= & dirPath=<file> & triggerNum=1 & rollDirection=UP|DOWN
 *        → data.data = 文本内容，data.allLineTotal = 总行数
 */
import { router } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Theme } from '../common/Theme';
import { L } from '../common/I18n';
import { store } from '../service/Store';
import { hpc, HpcContext, RemoteEntry } from '../service/Hpc';

const TAG: string = 'SCNetLite';

@Entry
@Component
struct Files {
  @StorageProp('themeRev') themeRev: number = 0;
  @State loading: boolean = true;
  @State errorMsg: string = '';
  @State ctx: HpcContext | null = null;
  @State cwd: string = '';
  @State entries: RemoteEntry[] = [];
  @State filePath: string = '';
  @State content: string = '';
  @State reading: boolean = false;

  aboutToAppear(): void {
    this.init();
  }

  private async init(): Promise<void> {
    this.loading = true;
    this.errorMsg = '';
    try {
      const cid: string = `${store.getClusterId()}`;
      const ctx: HpcContext = await hpc.context(cid.length > 0 && cid !== '0' ? cid : '11250', false);
      this.ctx = ctx;
      this.cwd = ctx.homePath.length > 0 ? ctx.homePath : '/public/home';
      await this.browse(this.cwd);
    } catch (e) {
      const err = e as Error;
      this.errorMsg = err.message ?? L.t('读取失败', 'Failed');
    }
    this.loading = false;
  }

  private async browse(path: string): Promise<void> {
    if (this.ctx === null) {
      return;
    }
    this.loading = true;
    this.errorMsg = '';
    try {
      this.entries = await hpc.listDir(this.ctx, path);
      this.cwd = path;
      this.filePath = '';
      this.content = '';
    } catch (e) {
      const err = e as Error;
      this.errorMsg = err.message ?? L.t('无法读取目录', 'Cannot read directory');
    }
    this.loading = false;
  }

  private async openFile(entry: RemoteEntry): Promise<void> {
    if (this.ctx === null) {
      return;
    }
    this.reading = true;
    this.filePath = entry.path;
    this.content = '';
    this.errorMsg = '';
    try {
      this.content = await hpc.readFile(this.ctx, entry.path, false);
      if (this.content.length === 0) {
        this.content = L.t('（空文件或超出预览上限）', '(empty file or beyond preview limit)');
      }
    } catch (e) {
      const err = e as Error;
      this.errorMsg = err.message ?? L.t('读取文件失败', 'Failed to read file');
    }
    this.reading = false;
    hilog.info(0x0000, TAG, 'file preview %{public}s len=%{public}d', entry.path, this.content.length);
  }

  private parentOf(path: string): string {
    const trimmed: string = path.replace(/\/+$/, '');
    const idx: number = trimmed.lastIndexOf('/');
    return idx > 0 ? trimmed.substring(0, idx) : trimmed;
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
            if (this.filePath.length > 0) {
              this.filePath = '';
              this.content = '';
              return;
            }
            if (this.cwd !== this.parentOf(this.cwd) &&
              (this.ctx === null || this.cwd !== this.ctx.homePath)) {
              this.browse(this.parentOf(this.cwd));
              return;
            }
            router.replaceUrl({ url: 'pages/Jobs' });
          })
        Column({ space: 1 }) {
          Text(this.filePath.length > 0 ? this.filePath.substring(this.filePath.lastIndexOf('/') + 1)
            : L.t('文件', 'Files'))
            .fontSize(Theme.fTitle)
            .fontFamily(Theme.fontDisplay)
            .fontColor(Theme.text)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.filePath.length > 0 ? this.filePath : this.cwd)
            .fontSize(10)
            .fontColor(Theme.textFaint)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Text('⟳')
          .fontSize(15)
          .fontColor(Theme.textSub)
          .width(30)
          .height(30)
          .textAlign(TextAlign.Center)
          .onClick(() => {
            if (this.filePath.length > 0) {
              this.openFile({ name: '', path: this.filePath });
            } else {
              this.browse(this.cwd);
            }
          })
      }
      .width('100%')
      .height(52)
      .padding({ left: 8, right: 12 })

      if (this.errorMsg.length > 0) {
        Text(this.errorMsg)
          .fontSize(Theme.fSmall)
          .fontColor(Theme.danger)
          .width('100%')
          .padding(12)
          .backgroundColor(Theme.dangerSoft)
          .borderRadius(Theme.rMd)
          .margin({ left: 14, right: 14, bottom: 6 })
      }

      if (this.loading || this.reading) {
        Column({ space: 10 }) {
          LoadingProgress().width(22).height(22).color(Theme.accent)
          Text(this.reading ? L.t('读取文件…', 'Reading file…') : L.t('读取目录…', 'Loading…'))
            .fontSize(Theme.fSmall)
            .fontColor(Theme.textFaint)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.filePath.length > 0) {
        Scroll() {
          Text(this.content)
            .fontSize(11)
            .lineHeight(17)
            .fontFamily('HarmonyOS Sans Mono')
            .fontColor('#E6EDF3')
            .width('100%')
            .padding(12)
            .backgroundColor('#111A26')
            .borderRadius(Theme.rMd)
            .copyOption(CopyOptions.LocalDevice)
        }
        .layoutWeight(1)
        .width('100%')
        .padding({ left: 14, right: 14, bottom: 14 })
        .scrollBar(BarState.Off)
      } else {
        List({ space: 6 }) {
          if (this.ctx !== null && this.cwd !== this.ctx.homePath) {
            ListItem() {
              Row({ space: 8 }) {
                Text('↰').fontSize(14).fontColor(Theme.textSub)
                Text('..').fontSize(Theme.fSmall).fontColor(Theme.textSub)
              }
              .width('100%')
              .padding({ left: 12, right: 12, top: 10, bottom: 10 })
              .backgroundColor(Theme.surface)
              .borderRadius(Theme.rSm)
              .onClick(() => {
                this.browse(this.parentOf(this.cwd));
              })
            }
          }
          ForEach(this.entries, (entry: RemoteEntry) => {
            ListItem() {
              Row({ space: 8 }) {
                Text('▸').fontSize(11).fontColor(Theme.accent)
                Text(entry.name)
                  .fontSize(Theme.fSmall)
                  .fontColor(Theme.text)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .layoutWeight(1)
                Text('›').fontSize(14).fontColor(Theme.textFaint)
              }
              .width('100%')
              .padding({ left: 12, right: 12, top: 10, bottom: 10 })
              .backgroundColor(Theme.surface)
              .borderRadius(Theme.rSm)
              .border({ width: 1, color: Theme.hairline })
              .onClick(() => {
                // efile 只给 path，没有明确的 isDirectory 标记：
                // 先按目录试，失败再按文件读（读失败会给出错误）
                this.guessOpen(entry);
              })
            }
          }, (entry: RemoteEntry) => entry.path)

          if (this.entries.length === 0) {
            ListItem() {
              Text(L.t('目录为空', 'Empty directory'))
                .fontSize(Theme.fSmall)
                .fontColor(Theme.textFaint)
                .width('100%')
                .textAlign(TextAlign.Center)
                .padding({ top: 24, bottom: 24 })
            }
          }
        }
        .layoutWeight(1)
        .width('100%')
        .padding({ left: 14, right: 14, bottom: 14 })
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.bg)
    .key(`files-${this.themeRev}`)
  }

  /** 目录优先：能列出子项就是目录，否则当文件读。 */
  private async guessOpen(entry: RemoteEntry): Promise<void> {
    if (this.ctx === null) {
      return;
    }
    try {
      const children: RemoteEntry[] = await hpc.listDir(this.ctx, entry.path);
      if (children.length > 0) {
        this.browse(entry.path);
        return;
      }
    } catch (e) {
      // 不是目录（或无法列出）→ 当文件处理
    }
    await this.openFile(entry);
  }
}
