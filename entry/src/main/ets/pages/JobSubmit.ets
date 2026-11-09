/**
 * 提交作业（表单 → 校验 → sbatch 预览 → 二次确认）。
 *
 * 安全设计：真正提交（会真计费）默认**关闭**。
 * 页面上有一个明确的开关「允许真正提交」，开启后仍需在确认弹层里再确认一次；
 * 关闭状态下只做校验与脚本预览，并把将要发送的请求体打到 hilog 里，便于核对。
 */
import { router } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Theme } from '../common/Theme';
import { L } from '../common/I18n';
import { store } from '../service/Store';
import { hpc, HpcContext, HpcQueue, HpcQuota, JobPlan, renderSbatch, validatePlan } from '../service/Hpc';

const TAG: string = 'SCNetLite';

@Entry
@Component
struct JobSubmit {
  @StorageProp('themeRev') themeRev: number = 0;
  @State loading: boolean = true;
  @State errorMsg: string = '';
  @State ctx: HpcContext | null = null;
  @State queues: HpcQueue[] = [];
  @State quota: HpcQuota | null = null;

  // 表单
  @State name: string = 'scnet-lite-job';
  @State queue: string = '';
  @State nodes: number = 1;
  @State cpus: number = 1;
  @State gpus: number = 0;
  @State dcus: number = 0;
  @State memory: string = '4G';
  @State walltime: string = '00:10:00';
  @State workDir: string = '';
  @State command: string = 'hostname && date';
  @State exclusive: boolean = false;

  // 提交流程
  @State allowSubmit: boolean = false;
  @State showConfirm: boolean = false;
  @State submitting: boolean = false;
  @State submittedId: string = '';

  aboutToAppear(): void {
    this.load();
  }

  private async load(): Promise<void> {
    this.loading = true;
    this.errorMsg = '';
    try {
      const clusterId: string = `${store.getClusterId()}`;
      const ctx: HpcContext = await hpc.context(clusterId.length > 0 && clusterId !== '0' ? clusterId : '11250', false);
      this.ctx = ctx;
      this.queues = await hpc.queues(ctx);
      this.quota = await hpc.quota(ctx);
      if (this.queues.length > 0) {
        this.queue = this.queues[0].name;
      }
      this.workDir = ctx.homePath.length > 0 ? ctx.homePath : '';
      hilog.info(0x0000, TAG, 'submit page: queues=%{public}d home=%{public}d',
        this.queues.length, this.workDir.length);
    } catch (e) {
      const err = e as Error;
      this.errorMsg = err.message ?? L.t('加载集群信息失败', 'Failed to load cluster');
    }
    this.loading = false;
  }

  private plan(): JobPlan {
    const out: JobPlan = {
      name: this.name.trim(),
      queue: this.queue,
      nodes: this.nodes,
      cpus: this.cpus,
      gpus: this.gpus,
      dcus: this.dcus,
      memory: this.memory.trim(),
      walltime: this.walltime.trim(),
      workDir: this.workDir.trim(),
      command: this.command,
      exclusive: this.exclusive
    };
    return out;
  }

  private stdout(): string {
    return `${this.workDir.replace(/\/+$/, '')}/std.out.%j`;
  }

  private stderr(): string {
    return `${this.workDir.replace(/\/+$/, '')}/std.err.%j`;
  }

  private queueNames(): string[] {
    const out: string[] = [];
    for (let i = 0; i < this.queues.length; i++) {
      out.push(this.queues[i].name);
    }
    return out;
  }

  private freeCpus(): string {
    for (let i = 0; i < this.queues.length; i++) {
      if (this.queues[i].name === this.queue) {
        return this.queues[i].freeCpus;
      }
    }
    return '';
  }

  /** 校验 + （可选）提交。 */
  private async confirmSubmit(): Promise<void> {
    const plan: JobPlan = this.plan();
    const bad: string = validatePlan(plan, this.queueNames());
    if (bad.length > 0) {
      this.errorMsg = bad;
      this.showConfirm = false;
      return;
    }
    if (this.ctx === null) {
      this.errorMsg = L.t('集群上下文缺失', 'No cluster context');
      return;
    }
    const body: Record<string, Object> = hpc.buildSubmitBody(this.ctx, plan, this.stdout(), this.stderr());
    if (!this.allowSubmit) {
      // 只预览：把将要发送的请求体打出来，方便对照 CLI/文档
      hilog.info(0x0000, TAG, 'submit dry-run body=%{public}s', JSON.stringify(body).substring(0, 800));
      this.showConfirm = false;
      this.errorMsg = L.t('已生成提交体（试运行，未真正提交）。开启上方开关后可真实提交。',
        'Payload generated (dry run). Enable the switch above to submit for real.');
      return;
    }
    this.submitting = true;
    try {
      const jobId: string = await hpc.submit(this.ctx, plan, this.stdout(), this.stderr());
      this.submittedId = jobId;
      this.showConfirm = false;
      this.errorMsg = '';
      hilog.info(0x0000, TAG, 'submitted job %{public}s', jobId);
    } catch (e) {
      const err = e as Error;
      this.errorMsg = err.message ?? L.t('提交失败', 'Submit failed');
      hilog.warn(0x0000, TAG, 'submit failed: %{public}s', this.errorMsg);
    }
    this.submitting = false;
  }

  @Builder
  field(label: string, value: string, hint: string, numeric: boolean, onChange: (v: string) => void) {
    Column({ space: 5 }) {
      Text(label).fontSize(10).fontColor(Theme.textFaint).padding({ left: 2 })
      TextInput({ text: value, placeholder: hint })
        .type(numeric ? InputType.Number : InputType.Normal)
        .height(42)
        .fontSize(Theme.fSmall)
        .fontColor(Theme.text)
        .backgroundColor(Theme.surfaceAlt)
        .borderRadius(Theme.rSm)
        .padding({ left: 12, right: 12 })
        .onChange(onChange)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  stepper(label: string, value: number, onStep: (delta: number) => void) {
    Row({ space: 8 }) {
      Text(label).fontSize(Theme.fSmall).fontColor(Theme.text).layoutWeight(1)
      Row({ space: 0 }) {
        Text('−')
          .fontSize(15)
          .fontColor(Theme.textSub)
          .width(32)
          .height(30)
          .textAlign(TextAlign.Center)
          .onClick(() => {
            onStep(-1);
          })
        Text(`${value}`)
          .fontSize(Theme.fSmall)
          .fontColor(Theme.text)
          .width(44)
          .height(30)
          .textAlign(TextAlign.Center)
          .backgroundColor(Theme.surfaceAlt)
        Text('＋')
          .fontSize(14)
          .fontColor(Theme.textSub)
          .width(32)
          .height(30)
          .textAlign(TextAlign.Center)
          .onClick(() => {
            onStep(1);
          })
      }
      .borderRadius(Theme.rSm)
      .backgroundColor(Theme.surfaceAlt)
      .clip(true)
    }
    .width('100%')
    .padding({ top: 8, bottom: 8 })
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
            Text(L.t('提交作业', 'Submit job'))
              .fontSize(Theme.fTitle)
              .fontFamily(Theme.fontDisplay)
              .fontColor(Theme.text)
            Text(this.ctx !== null ? `${this.ctx.clusterName} · ${this.ctx.userName}` : '')
              .fontSize(10)
              .fontColor(Theme.textFaint)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
        }
        .width('100%')
        .height(52)
        .padding({ left: 8, right: 12 })

        if (this.loading) {
          Column({ space: 10 }) {
            LoadingProgress().width(24).height(24).color(Theme.accent)
            Text(L.t('读取队列与配额…', 'Loading queues…'))
              .fontSize(Theme.fSmall)
              .fontColor(Theme.textFaint)
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
                  .lineHeight(18)
                  .fontColor(this.submittedId.length > 0 ? Theme.ok : (this.allowSubmit ? Theme.danger : Theme.textSub))
                  .width('100%')
                  .padding(12)
                  .backgroundColor(this.submittedId.length > 0 ? '#E8F8F0'
                    : (this.allowSubmit ? Theme.dangerSoft : Theme.surfaceAlt))
                  .borderRadius(Theme.rMd)
              }
              if (this.submittedId.length > 0) {
                Text(L.t(`已提交：作业 ${this.submittedId}`, `Submitted: job ${this.submittedId}`))
                  .fontSize(Theme.fSmall)
                  .fontColor(Theme.ok)
                  .width('100%')
              }

              // 队列
              Column({ space: 6 }) {
                Text(L.t('队列', 'Queue')).fontSize(10).fontColor(Theme.textFaint).padding({ left: 2 })
                Scroll() {
                  Row({ space: 8 }) {
                    ForEach(this.queues, (queue: HpcQueue) => {
                      Text(queue.name)
                        .fontSize(Theme.fTiny)
                        .fontColor(this.queue === queue.name ? Theme.textOnAccent : Theme.textSub)
                        .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                        .backgroundColor(this.queue === queue.name ? Theme.accent : Theme.surface)
                        .borderRadius(Theme.rPill)
                        .border({
                          width: 1,
                          color: this.queue === queue.name ? Theme.accent : Theme.hairline
                        })
                        .onClick(() => {
                          this.queue = queue.name;
                        })
                    }, (queue: HpcQueue) => queue.name)
                  }
                }
                .scrollable(ScrollDirection.Horizontal)
                .scrollBar(BarState.Off)
                .width('100%')
                Text(L.t(`空闲 ${this.freeCpus()} 核 · 配额 ${this.quota !== null ? this.quota.accountMaxCpu : '—'} 核`,
                  `free ${this.freeCpus()} cores · quota ${this.quota !== null ? this.quota.accountMaxCpu : '—'}`))
                  .fontSize(10)
                  .fontColor(Theme.textFaint)
                  .padding({ left: 2 })
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)

              // 资源
              Column() {
                this.stepper(L.t('节点数', 'Nodes'), this.nodes, (d: number) => {
                  this.nodes = Math.min(64, Math.max(1, this.nodes + d));
                })
                Divider().color(Theme.hairline)
                this.stepper(L.t('每节点核数', 'Cores / node'), this.cpus, (d: number) => {
                  this.cpus = Math.min(64, Math.max(1, this.cpus + d));
                })
                Divider().color(Theme.hairline)
                this.stepper('DCU', this.dcus, (d: number) => {
                  this.dcus = Math.min(8, Math.max(0, this.dcus + d));
                })
                Divider().color(Theme.hairline)
                this.stepper('GPU', this.gpus, (d: number) => {
                  this.gpus = Math.min(8, Math.max(0, this.gpus + d));
                })
              }
              .width('100%')
              .padding({ left: 14, right: 14, top: 4, bottom: 4 })
              .backgroundColor(Theme.surface)
              .borderRadius(Theme.rMd)
              .border({ width: 1, color: Theme.hairline })

              // 基础字段
              Column({ space: 10 }) {
                this.field(L.t('作业名', 'Job name'), this.name, 'scnet-lite-job', false, (v: string) => {
                  this.name = v;
                })
                this.field(L.t('运行时长 HH:MM:SS', 'Wall time'), this.walltime, '00:10:00', false, (v: string) => {
                  this.walltime = v;
                })
                this.field(L.t('内存', 'Memory'), this.memory, '4G', false, (v: string) => {
                  this.memory = v;
                })
                this.field(L.t('工作目录（绝对路径）', 'Work dir (absolute)'), this.workDir, '/home/luql', false,
                  (v: string) => {
                    this.workDir = v;
                  })
              }
              .width('100%')
              .padding(12)
              .backgroundColor(Theme.surface)
              .borderRadius(Theme.rMd)
              .border({ width: 1, color: Theme.hairline })

              // 命令
              Column({ space: 6 }) {
                Text(L.t('命令', 'Command')).fontSize(10).fontColor(Theme.textFaint).padding({ left: 2 })
                TextArea({ text: this.command, placeholder: 'hostname && date' })
                  .height(84)
                  .fontSize(Theme.fTiny)
                  .fontColor(Theme.text)
                  .backgroundColor(Theme.surfaceAlt)
                  .borderRadius(Theme.rSm)
                  .padding(10)
                  .onChange((v: string) => {
                    this.command = v;
                  })
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)

              // sbatch 预览
              Column({ space: 6 }) {
                Row({ space: 6 }) {
                  Text(L.t('等价 sbatch', 'Equivalent sbatch'))
                    .fontSize(10)
                    .fontColor(Theme.textFaint)
                    .layoutWeight(1)
                }
                Text(renderSbatch(this.plan(), this.stdout(), this.stderr()))
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
              .width('100%')
              .alignItems(HorizontalAlign.Start)

              // 危险开关
              Row({ space: 10 }) {
                Column({ space: 2 }) {
                  Text(L.t('允许真正提交', 'Allow real submission'))
                    .fontSize(Theme.fSmall)
                    .fontColor(Theme.danger)
                  Text(L.t('提交会占用配额并计费；默认只做校验与脚本预览',
                    'Submitting consumes quota and is billed; default is dry run'))
                    .fontSize(10)
                    .fontColor(Theme.textFaint)
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)
                Toggle({ type: ToggleType.Switch, isOn: this.allowSubmit })
                  .selectedColor(Theme.danger)
                  .onChange((on: boolean) => {
                    this.allowSubmit = on;
                  })
              }
              .width('100%')
              .padding(12)
              .backgroundColor(Theme.surface)
              .borderRadius(Theme.rMd)
              .border({ width: 1, color: this.allowSubmit ? Theme.dangerBorder : Theme.hairline })

              Text(this.allowSubmit ? L.t('提交（真实）', 'Submit (real)') : L.t('校验并生成提交体', 'Validate & build'))
                .fontSize(Theme.fSmall)
                .fontColor(Theme.textOnAccent)
                .width('100%')
                .textAlign(TextAlign.Center)
                .padding({ top: 12, bottom: 12 })
                .backgroundColor(this.allowSubmit ? Theme.danger : Theme.accent)
                .borderRadius(Theme.rMd)
                .onClick(() => {
                  this.showConfirm = true;
                })

              Text(L.t('当前未接入日志/产物查看；提交后可在作业列表看到状态',
                'Logs/artifacts are not wired yet; the job list shows status'))
                .fontSize(10)
                .fontColor(Theme.textFaint)
                .width('100%')
                .textAlign(TextAlign.Center)
                .padding({ top: 2, bottom: 18 })
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

      if (this.showConfirm) {
        Column() {
          Blank().layoutWeight(1).width('100%').onClick(() => {
            this.showConfirm = false;
          })
          Column({ space: 10 }) {
            Text(this.allowSubmit ? L.t('确认提交作业？', 'Submit this job?')
              : L.t('生成提交体', 'Build payload'))
              .fontSize(Theme.fTitle)
              .fontFamily(Theme.fontDisplay)
              .fontColor(Theme.text)
            Text(`${this.name} · ${this.queue} · ${this.nodes} 节点 × ${this.cpus} 核 · ${this.walltime}`)
              .fontSize(Theme.fSmall)
              .fontColor(Theme.textSub)
              .textAlign(TextAlign.Center)
            if (this.allowSubmit) {
              Text(L.t('这一步会真的占用配额并计费', 'This step consumes quota and is billed'))
                .fontSize(10)
                .fontColor(Theme.danger)
            }
            Row({ space: 8 }) {
              Text(L.t('取消', 'Cancel'))
                .fontSize(Theme.fSmall)
                .fontColor(Theme.textSub)
                .layoutWeight(1)
                .textAlign(TextAlign.Center)
                .padding({ top: 10, bottom: 10 })
                .backgroundColor(Theme.surfaceAlt)
                .borderRadius(Theme.rSm)
                .onClick(() => {
                  this.showConfirm = false;
                })
              Text(this.submitting ? L.t('处理中…', 'Working…')
                : (this.allowSubmit ? L.t('确认提交', 'Confirm') : L.t('生成', 'Build')))
                .fontSize(Theme.fSmall)
                .fontColor(Theme.textOnAccent)
                .layoutWeight(1)
                .textAlign(TextAlign.Center)
                .padding({ top: 10, bottom: 10 })
                .backgroundColor(this.allowSubmit ? Theme.danger : Theme.accent)
                .borderRadius(Theme.rSm)
                .onClick(() => {
                  if (!this.submitting) {
                    this.confirmSubmit();
                  }
                })
            }
            .width('100%')
            .margin({ top: 4 })
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
    .key(`submit-${this.themeRev}`)
  }
}
