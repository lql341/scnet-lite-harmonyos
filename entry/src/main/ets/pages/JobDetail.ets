/**
 * 作业详情：状态/资源/时间 + stdout&stderr 日志 + 取消。
 *
 * 契约（本机 curl 实测）：
 *   GET    {hpc}/hpc/openapi/v2/jobs/{id}   → data{jobStatus,jobSubmitTime,jobStartTime,
 *                                               jobEndTime,exitCode,nodeUsed,procNumUsed,
 *                                               gpuNumUsed,dcuNumUsed,outputPath,errorPath,workDir}
 *   DELETE {hpc}/hpc/openapi/v2/jobs        form: jobMethod=5&strJobInfoMap=<sched>,<user>:<id>:
 *          ⚠️ 对不存在的 jobId 也回 code 0 → 取消必须有二次确认
 *   日志   POST {hpc}/hpc/openapi/v2/file/content（outputPath / errorPath）
 */
import { router } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Theme } from '../common/Theme';
import { L } from '../common/I18n';
import { store } from '../service/Store';
import { hpc, HpcContext } from '../service/Hpc';

const TAG: string = 'SCNetLite';

interface DetailRow {
  label: string;
  value: string;
}

@Entry
@Component
struct JobDetail {
  @StorageProp('themeRev') themeRev: number = 0;
  @State jobId: string = '';
  @State loading: boolean = true;
  @State errorMsg: string = '';
  @State ctx: HpcContext | null = null;
  @State rows: DetailRow[] = [];
  @State status: string = '';
  @State logPath: string = '';
  @State logText: string = '';
  @State logLoading: boolean = false;
  @State showCancel: boolean = false;
  @State cancelling: boolean = false;
  @State cancelled: boolean = false;

  aboutToAppear(): void {
    const params = router.getParams() as Record<string, string> | undefined;
    if (params !== undefined && params !== null && params['jobId'] !== undefined) {
      this.jobId = params['jobId'];
    }
    this.load();
  }

  private async load(): Promise<void> {
    this.loading = true;
    this.errorMsg = '';
    try {
      const cid: string = `${store.getClusterId()}`;
      const ctx: HpcContext = await hpc.context(cid.length > 0 && cid !== '0' ? cid : '11250', false);
      this.ctx = ctx;
      const detail: Record<string, Object> | null = await hpc.jobDetail(ctx, this.jobId);
      if (detail === null) {
        this.errorMsg = L.t('读不到作业详情（可能已结束，去历史里找）',
          'No detail (job may have finished)');
      } else {
        this.applyDetail(detail);
      }
    } catch (e) {
      const err = e as Error;
      this.errorMsg = err.message ?? L.t('加载失败', 'Failed');
    }
    this.loading = false;
  }

  private applyDetail(detail: Record<string, Object>): void {
    this.status = String(detail['jobStatus'] ?? '');
    const out: DetailRow[] = [];
    const push = (label: string, key: string): void => {
      const value: string = String(detail[key] ?? '');
      if (value.length > 0 && value !== 'null') {
        const row: DetailRow = { label: label, value: value };
        out.push(row);
      }
    };
    push(L.t('作业名', 'Name'), 'jobName');
    push(L.t('状态', 'Status'), 'jobStatus');
    push(L.t('队列', 'Queue'), 'queue');
    push(L.t('用户', 'User'), 'user');
    push(L.t('提交时间', 'Submitted'), 'jobSubmitTime');
    push(L.t('开始时间', 'Started'), 'jobStartTime');
    push(L.t('结束时间', 'Ended'), 'jobEndTime');
    push(L.t('退出码', 'Exit code'), 'exitCode');
    push(L.t('节点', 'Nodes'), 'nodeUsed');
    push(L.t('核数', 'Cores'), 'procNumUsed');
    push(L.t('GPU', 'GPU'), 'gpuNumUsed');
    push(L.t('DCU', 'DCU'), 'dcuNumUsed');
    push(L.t('工作目录', 'Work dir'), 'workDir');
    push(L.t('输出文件', 'Output'), 'outputPath');
    this.rows = out;
    const path: string = String(detail['outputPath'] ?? '');
    this.logPath = path.length > 0 ? path : String(detail['errorPath'] ?? '');
  }

  private async loadLog(): Promise<void> {
    if (this.ctx === null || this.logPath.length === 0) {
      return;
    }
    this.logLoading = true;
    this.errorMsg = '';
    try {
      const text: string = await hpc.readFile(this.ctx, this.logPath, true);
      this.logText = text.length > 0 ? text : L.t('（日志为空）', '(empty log)');
    } catch (e) {
      const err = e as Error;
      this.errorMsg = err.message ?? L.t('读取日志失败', 'Failed to read log');
    }
    this.logLoading = false;
    hilog.debug(0x0000, TAG, 'job log %{public}s len=%{public}d', this.logPath, this.logText.length);
  }

  private async doCancel(): Promise<void> {
    if (this.ctx === null) {
      return;
    }
    this.cancelling = true;
    try {
      await hpc.cancel(this.ctx, this.jobId);
      this.cancelled = true;
      this.showCancel = false;
      this.errorMsg = '';
      await this.load();
    } catch (e) {
      const err = e as Error;
      this.errorMsg = err.message ?? L.t('取消失败', 'Cancel failed');
    }
    this.cancelling = false;
  }

  private statusLabel(): string {
    const code: string = this.status;
    if (code === 'statR') {
      return L.t('运行中', 'Running');
    }
    if (code === 'statPD' || code === 'statP' || code === 'statQ') {
      return L.t('排队中', 'Pending');
    }
    if (code === 'statC') {
      return L.t('已完成', 'Completed');
    }
    if (code === 'statE') {
      return L.t('异常退出', 'Failed');
    }
    if (code === 'statCA') {
      return L.t('已取消', 'Cancelled');
    }
    return code.length > 0 ? code : '—';
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        Row({ space: 8 }) {
          Text('‹')
            .fontSize(22)
            .fontColor(Theme.textSub)
            .width(32)
            .height(32)
            .textAlign(TextAlign.Center)
            .onClick(() => {
              router.replaceUrl({ url: 'pages/Jobs' });
            })
          Column({ space: 1 }) {
            Text(`${L.t('作业', 'Job')} ${this.jobId}`)
              .fontSize(Theme.fTitle)
              .fontFamily(Theme.fontDisplay)
              .fontColor(Theme.text)
            Text(this.statusLabel())
              .fontSize(10)
              .fontColor(this.status === 'statR' ? Theme.ok
                : (this.status === 'statE' ? Theme.danger : Theme.textFaint))
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
              this.load();
            })
          if (this.status === 'statR' || this.status === 'statPD' || this.status === 'statP') {
            Text(L.t('取消作业', 'Cancel'))
              .fontSize(Theme.fTiny)
              .fontColor(Theme.danger)
              .padding({ left: 10, right: 10, top: 5, bottom: 5 })
              .backgroundColor(Theme.dangerSoft)
              .borderRadius(Theme.rPill)
              .onClick(() => {
                this.showCancel = true;
              })
          }
        }
        .width('100%')
        .height(52)
        .padding({ left: 8, right: 12 })

        if (this.loading) {
          Column({ space: 10 }) {
            LoadingProgress().width(22).height(22).color(Theme.accent)
            Text(L.t('读取中…', 'Loading…')).fontSize(Theme.fSmall).fontColor(Theme.textFaint)
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          Scroll() {
            Column({ space: 12 }) {
              if (this.errorMsg.length > 0) {
                Text(this.errorMsg)
                  .fontSize(Theme.fSmall)
                  .fontColor(Theme.danger)
                  .width('100%')
                  .padding(12)
                  .backgroundColor(Theme.dangerSoft)
                  .borderRadius(Theme.rMd)
              }
              if (this.cancelled) {
                Text(L.t('已提交取消请求', 'Cancel request sent'))
                  .fontSize(Theme.fSmall)
                  .fontColor(Theme.ok)
                  .width('100%')
                  .padding(12)
                  .backgroundColor('#E8F8F0')
                  .borderRadius(Theme.rMd)
              }

              Column() {
                ForEach(this.rows, (row: DetailRow, index: number) => {
                  Row({ space: 10 }) {
                    Text(row.label)
                      .fontSize(10)
                      .fontColor(Theme.textFaint)
                      .width(76)
                    Text(row.value)
                      .fontSize(Theme.fTiny)
                      .fontColor(Theme.text)
                      .maxLines(2)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .layoutWeight(1)
                      .copyOption(CopyOptions.LocalDevice)
                  }
                  .width('100%')
                  .alignItems(VerticalAlign.Top)
                  .padding({ top: 9, bottom: 9 })
                  if (index < this.rows.length - 1) {
                    Divider().color(Theme.hairline)
                  }
                }, (row: DetailRow) => `${row.label}-${row.value}`)
              }
              .width('100%')
              .padding({ left: 14, right: 14 })
              .backgroundColor(Theme.surface)
              .borderRadius(Theme.rMd)
              .border({ width: 1, color: Theme.hairline })

              // 日志
              Column({ space: 8 }) {
                Row({ space: 8 }) {
                  Text(L.t('输出日志', 'Output log'))
                    .fontSize(10)
                    .fontColor(Theme.textFaint)
                    .layoutWeight(1)
                  Text(this.logLoading ? L.t('读取中…', 'Loading…') : L.t('读取', 'Read'))
                    .fontSize(Theme.fTiny)
                    .fontColor(this.logPath.length > 0 ? Theme.accent : Theme.textFaint)
                    .onClick(() => {
                      if (!this.logLoading && this.logPath.length > 0) {
                        this.loadLog();
                      }
                    })
                }
                .width('100%')
                if (this.logPath.length === 0) {
                  Text(L.t('这个作业没有输出文件路径', 'No output path for this job'))
                    .fontSize(10)
                    .fontColor(Theme.textFaint)
                } else {
                  Text(this.logPath)
                    .fontSize(10)
                    .fontColor(Theme.textFaint)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  if (this.logText.length > 0) {
                    Text(this.logText)
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
                }
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)
              .padding(12)
              .backgroundColor(Theme.surface)
              .borderRadius(Theme.rMd)
              .border({ width: 1, color: Theme.hairline })

              Text(L.t('提示：日志文件在集群侧可能延迟落盘；作业结束前读到空属正常',
                'Logs may lag on the cluster side; empty before job end is normal'))
                .fontSize(10)
                .fontColor(Theme.textFaint)
                .width('100%')
                .padding({ bottom: 18 })
            }
            .width('100%')
            .padding({ left: 14, right: 14, top: 2 })
          }
          .layoutWeight(1)
          .width('100%')
          .scrollBar(BarState.Off)
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(Theme.bg)

      if (this.showCancel) {
        Column() {
          Blank().layoutWeight(1).width('100%').onClick(() => {
            this.showCancel = false;
          })
          Column({ space: 10 }) {
            Text(L.t('取消这个作业？', 'Cancel this job?'))
              .fontSize(Theme.fTitle)
              .fontFamily(Theme.fontDisplay)
              .fontColor(Theme.text)
            Text(`${this.jobId} · ${this.statusLabel()}`)
              .fontSize(Theme.fSmall)
              .fontColor(Theme.textSub)
            Row({ space: 8 }) {
              Text(L.t('保留', 'Keep'))
                .fontSize(Theme.fSmall)
                .fontColor(Theme.textSub)
                .layoutWeight(1)
                .textAlign(TextAlign.Center)
                .padding({ top: 10, bottom: 10 })
                .backgroundColor(Theme.surfaceAlt)
                .borderRadius(Theme.rSm)
                .onClick(() => {
                  this.showCancel = false;
                })
              Text(this.cancelling ? L.t('处理中…', 'Working…') : L.t('确认取消', 'Confirm'))
                .fontSize(Theme.fSmall)
                .fontColor(Theme.textOnAccent)
                .layoutWeight(1)
                .textAlign(TextAlign.Center)
                .padding({ top: 10, bottom: 10 })
                .backgroundColor(Theme.danger)
                .borderRadius(Theme.rSm)
                .onClick(() => {
                  if (!this.cancelling) {
                    this.doCancel();
                  }
                })
            }
            .width('100%')
          }
          .width('100%')
          .padding({ left: 20, right: 20, top: 18, bottom: 24 })
          .backgroundColor(Theme.surface)
          .borderRadius({ topLeft: Theme.rXl, topRight: Theme.rXl })
          .shadow(Theme.shadowSheet)
        }
        .width('100%')
        .height('100%')
        .backgroundColor('#0B1F3355')
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.bg)
    .key(`detail-${this.themeRev}`)
  }
}
