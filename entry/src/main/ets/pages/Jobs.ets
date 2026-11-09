/**
 * 作业页（P3）：集群 → 队列空闲核数 → 配额 → 运行中作业。
 *
 * 数据来自 HPC OpenAPI（AK/SK 签名），与对话通道完全独立。
 * 首次进入要填 AK/SK（账号页 → HPC 凭据，或本页引导）。
 */
import { router } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Theme, safe } from '../common/Theme';
import { L } from '../common/I18n';
import { store } from '../service/Store';
import { hpc, HpcContext, HpcQueue, HpcQuota, HpcRegion, HpcError, cryptoSelfCheck } from '../service/Hpc';

const TAG: string = 'SCNetLite';

interface JobRow {
  id: string;
  name: string;
  status: string;
  queue: string;
  nodes: string;
  cpus: string;
}

@Entry
@Component
struct Jobs {
  @StorageProp('themeRev') themeRev: number = 0;
  @State loading: boolean = true;
  @State errorMsg: string = '';
  @State ctx: HpcContext | null = null;
  @State queues: HpcQueue[] = [];
  @State quota: HpcQuota | null = null;
  @State jobs: JobRow[] = [];
  @State jobsUnavailable: boolean = false;
  @State regions: HpcRegion[] = [];
  @State clusterId: string = '';
  @State needCreds: boolean = false;
  @State showCreds: boolean = false;
  @State ak: string = '';
  @State sk: string = '';
  /** AK:SK 一次性粘贴的内容 */
  @State pasted: string = '';
  @State user: string = '';
  @State saving: boolean = false;

  aboutToAppear(): void {
    this.ak = store.getHpcAk();
    this.sk = store.getHpcSk();
    this.user = store.getHpcUser();
    this.clusterId = `${store.getClusterId()}`;
    cryptoSelfCheck();
    this.refresh();
  }

  private async refresh(): Promise<void> {
    this.loading = true;
    this.errorMsg = '';
    this.jobsUnavailable = false;
    if (!hpc.hasCredentials()) {
      this.needCreds = true;
      this.loading = false;
      return;
    }
    this.needCreds = false;
    try {
      const list: HpcRegion[] = await hpc.regions(false);
      this.regions = list.filter((r: HpcRegion) => String(r.clusterId) !== '0');
      if (this.regions.length === 0) {
        this.errorMsg = L.t('没有可用集群', 'No regions available');
        this.loading = false;
        return;
      }
      let target: string = this.clusterId;
      let found: boolean = false;
      for (let i = 0; i < this.regions.length; i++) {
        if (String(this.regions[i].clusterId) === target) {
          found = true;
        }
      }
      if (!found) {
        target = String(this.regions[0].clusterId);
        this.clusterId = target;
      }
      const ctx: HpcContext = await hpc.context(target, false);
      this.ctx = ctx;
      this.queues = await hpc.queues(ctx);
      this.quota = await hpc.quota(ctx);
      try {
        const raw: Record<string, Object>[] = await hpc.jobs(ctx, 20);
        this.jobs = this.mapJobs(raw);
      } catch (e) {
        this.jobsUnavailable = true;
        this.jobs = [];
        hilog.warn(0x0000, TAG, 'jobs unavailable');
      }
      hilog.info(0x0000, TAG, 'jobs page: queues=%{public}d jobs=%{public}d',
        this.queues.length, this.jobs.length);
    } catch (e) {
      const err = e as HpcError;
      this.errorMsg = err.message ?? L.t('加载失败', 'Failed to load');
      hilog.warn(0x0000, TAG, 'jobs refresh failed: %{public}s', this.errorMsg);
    }
    this.loading = false;
  }

  /**
   * SLURM 状态码 → 可读文案。
   * 平台返回的是 `statR/statC/statE…` 这种缩写（stat + 首字母大写）。
   */
  private statusLabel(code: string): string {
    const map: string[] = [];
    if (code === 'statR') {
      return L.t('运行中', 'Running');
    }
    if (code === 'statPD' || code === 'statP') {
      return L.t('排队中', 'Pending');
    }
    if (code === 'statC') {
      return L.t('已完成', 'Completed');
    }
    if (code === 'statE') {
      return L.t('异常退出', 'Failed');
    }
    if (code === 'statS' || code === 'statST') {
      return L.t('已停止', 'Stopped');
    }
    if (code === 'statCA') {
      return L.t('已取消', 'Cancelled');
    }
    if (code === 'statTO') {
      return L.t('超时', 'Timeout');
    }
    if (code === 'statQ') {
      return L.t('排队中', 'Queued');
    }
    if (code === 'statCG') {
      return L.t('正在退出', 'Completing');
    }
    if (code === 'statNF') {
      return L.t('节点失效', 'Node failure');
    }
    if (code === 'statOOM') {
      return L.t('内存超限', 'Out of memory');
    }
    return code;
  }

  private statusColor(code: string): string {
    if (code === 'statR') {
      return Theme.ok;
    }
    if (code === 'statE' || code === 'statTO') {
      return Theme.danger;
    }
    if (code === 'statPD' || code === 'statP' || code === 'statQ' || code === 'statCG') {
      return Theme.warn;
    }
    if (code === 'statNF' || code === 'statOOM') {
      return Theme.danger;
    }
    return Theme.textFaint;
  }

  private mapJobs(raw: Record<string, Object>[]): JobRow[] {
    const out: JobRow[] = [];
    for (let i = 0; i < raw.length; i++) {
      const row = raw[i];
      const id: string = safe(row['jobId'] ?? row['id'] ?? row['job_id']);
      if (id.length === 0) {
        continue;
      }
      const item: JobRow = {
        id: id,
        name: safe(row['jobName'] ?? row['name']),
        status: safe(row['jobStatus'] ?? row['status'] ?? row['state']),
        queue: safe(row['queueName'] ?? row['queue']),
        nodes: safe(row['nodes'] ?? row['nodeNum']),
        cpus: safe(row['cpus'] ?? row['cpuNum'] ?? row['nproc'])
      };
      out.push(item);
    }
    return out;
  }

  private pickCluster(id: string): void {
    this.clusterId = id;
    const num: number = parseInt(id, 10);
    if (Number.isFinite(num)) {
      store.setClusterId(num);
    }
    this.refresh();
  }

  /** 从 "AK:SK" / "AK,SK" / "AK SK" / 两行 里拆出 AK 和 SK。 */
  private parseCreds(raw: string): void {
    const cleaned: string = raw.replace(/[\s,;]+/g, ':').replace(/:+/g, ':').trim();
    const parts: string[] = cleaned.split(':');
    if (parts.length >= 2) {
      this.ak = parts[0].trim();
      this.sk = parts[1].trim();
    } else if (cleaned.length === 64) {
      // 直接连着粘了两段 32 位
      this.ak = cleaned.substring(0, 32);
      this.sk = cleaned.substring(32);
    } else {
      this.ak = cleaned;
      this.sk = '';
    }
  }

  private saveCreds(): void {
    if (this.ak.trim().length === 0 || this.sk.trim().length === 0) {
      this.errorMsg = L.t('AK 与 SK 都不能为空', 'AK and SK are required');
      return;
    }
    const bad: string = hpc.validateCreds(this.ak.trim(), this.sk.trim());
    if (bad.length > 0) {
      this.errorMsg = bad;
      hilog.warn(0x0000, TAG, 'creds invalid: ak=%{public}d sk=%{public}d',
        this.ak.trim().length, this.sk.trim().length);
      return;
    }
    store.setHpcAk(this.ak.trim());
    store.setHpcSk(this.sk.trim());
    // 用户名不用填：签名用的 user 取登录账号（见 Store.getPlatformUserName）
    this.showCreds = false;
    this.refresh();
  }

  @Builder
  statCard(label: string, value: string, hint: string) {
    Column({ space: 3 }) {
      Text(value)
        .fontSize(22)
        .fontWeight(FontWeight.Medium)
        .fontFamily(Theme.fontDisplay)
        .fontColor(Theme.text)
      Text(label).fontSize(Theme.fTiny).fontColor(Theme.textSub)
      Text(hint).fontSize(9).fontColor(Theme.textFaint).maxLines(1)
    }
    .alignItems(HorizontalAlign.Start)
    .layoutWeight(1)
    .padding({ left: 12, right: 12, top: 12, bottom: 12 })
    .backgroundColor(Theme.surface)
    .borderRadius(Theme.rMd)
    .border({ width: 1, color: Theme.hairline })
  }

  @Builder
  credsSheet() {
    Column() {
      Row()
        .width(36)
        .height(4)
        .borderRadius(2)
        .backgroundColor(Theme.surfaceSunken)
        .margin({ top: 8, bottom: 8 })
      Row() {
        Column({ space: 2 }) {
          Text(L.t('HPC 凭据', 'HPC credentials'))
            .fontSize(Theme.fTitle)
            .fontFamily(Theme.fontDisplay)
            .fontColor(Theme.text)
          Text(L.t('在控制台「个人设置 → AccessKey」获取，仅存本机',
            'Get it in console → AccessKey; stored locally'))
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
            this.showCreds = false;
          })
      }
      .width('100%')
      .padding({ left: 4, right: 4, bottom: 10 })

      Column({ space: 8 }) {
        // 一次粘贴 AK:SK（避免两个输入框重复输入导致签名失败）
        TextArea({ text: this.pasted, placeholder: L.t(
          '粘贴 AccessKey:SecretKey', 'Paste AccessKey:SecretKey') })
          .height(64)
          .fontSize(Theme.fTiny)
          .backgroundColor(Theme.surfaceAlt)
          .borderRadius(Theme.rSm)
          .padding({ left: 12, right: 12, top: 8, bottom: 8 })
          .onChange((v: string) => {
            this.pasted = v;
            this.parseCreds(v);
          })
        if (this.ak.length > 0 && this.sk.length > 0) {
          Text(L.t(`已识别：AK ${this.ak.length} 位 · SK ${this.sk.length} 位`,
            `Parsed: AK ${this.ak.length} · SK ${this.sk.length}`))
            .fontSize(10)
            .fontColor(Theme.ok)
        }
        Row({ space: 8 }) {
          Text(L.t('清除', 'Clear'))
            .fontSize(Theme.fSmall)
            .fontColor(Theme.textSub)
            .layoutWeight(1)
            .textAlign(TextAlign.Center)
            .padding({ top: 11, bottom: 11 })
            .backgroundColor(Theme.surfaceAlt)
            .borderRadius(Theme.rSm)
            .onClick(() => {
              this.ak = '';
              this.sk = '';
              store.setHpcAk('');
              store.setHpcSk('');
              this.errorMsg = '';
              this.needCreds = true;
              this.showCreds = false;
            })
          Text(L.t('保存', 'Save'))
          .fontSize(Theme.fSmall)
          .fontColor(Theme.textOnAccent)
          .width('100%')
            .fontColor(Theme.textOnAccent)
            .layoutWeight(1)
            .textAlign(TextAlign.Center)
            .padding({ top: 11, bottom: 11 })
            .backgroundColor(Theme.accent)
            .borderRadius(Theme.rSm)
            .onClick(() => {
              this.saveCreds();
            })
        }
        .width('100%')
      }
      .width('100%')
      .padding({ bottom: 22 })
    }
    .width('100%')
    .padding({ left: 16, right: 16 })
    .backgroundColor(Theme.surface)
    .borderRadius({ topLeft: Theme.rXl, topRight: Theme.rXl })
    .shadow(Theme.shadowSheet)
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
              router.replaceUrl({ url: 'pages/Index' });
            })
          Column({ space: 1 }) {
            Text(L.t('作业', 'Jobs'))
              .fontSize(Theme.fTitle)
              .fontFamily(Theme.fontDisplay)
              .fontColor(Theme.text)
            Text(this.ctx !== null ? this.ctx.clusterName : L.t('超算资源', 'HPC resources'))
              .fontSize(10)
              .fontColor(Theme.textFaint)
              .maxLines(1)
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
              this.refresh();
            })
          Text('AK')
            .fontSize(Theme.fTiny)
            .fontColor(Theme.accent)
            .padding({ left: 10, right: 10, top: 5, bottom: 5 })
            .backgroundColor(Theme.accentGhost)
            .borderRadius(Theme.rPill)
            .onClick(() => {
              this.showCreds = true;
            })
        }
        .width('100%')
        .height(52)
        .padding({ left: 8, right: 12 })

        if (this.loading) {
          Column({ space: 10 }) {
            LoadingProgress().width(24).height(24).color(Theme.accent)
            Text(L.t('正在读取集群…', 'Loading cluster…'))
              .fontSize(Theme.fSmall)
              .fontColor(Theme.textFaint)
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else if (this.needCreds) {
          Column({ space: 12 }) {
            Text(L.t('需要配置 HPC 凭据', 'HPC credentials required'))
              .fontSize(Theme.fBody)
              .fontColor(Theme.text)
            Text(L.t('作业面走 OpenAPI（AK/SK 签名），与聊天凭据是两套。',
              'The jobs page uses OpenAPI (AK/SK), separate from chat auth.'))
              .fontSize(Theme.fSmall)
              .fontColor(Theme.textFaint)
              .textAlign(TextAlign.Center)
            Text(L.t('填写 AK/SK', 'Add AK/SK'))
              .fontSize(Theme.fSmall)
              .fontColor(Theme.textOnAccent)
              .padding({ left: 18, right: 18, top: 10, bottom: 10 })
              .backgroundColor(Theme.accent)
              .borderRadius(Theme.rSm)
              .onClick(() => {
                this.showCreds = true;
              })
          }
          .width('100%')
          .layoutWeight(1)
          .padding({ left: 28, right: 28 })
          .justifyContent(FlexAlign.Center)
        } else {
          Scroll() {
            Column({ space: 12 }) {
              if (this.errorMsg.length > 0) {
                Row({ space: 8 }) {
                  Text(this.errorMsg)
                    .fontSize(Theme.fSmall)
                    .fontColor(Theme.danger)
                    .layoutWeight(1)
                }
                .width('100%')
                .padding(12)
                .backgroundColor(Theme.dangerSoft)
                .borderRadius(Theme.rMd)
              }

              // 集群切换
              if (this.regions.length > 1) {
                Scroll() {
                  Row({ space: 8 }) {
                    ForEach(this.regions, (region: HpcRegion) => {
                      Text(String(region.clusterName))
                        .fontSize(Theme.fTiny)
                        .fontColor(String(region.clusterId) === this.clusterId ? Theme.textOnAccent : Theme.textSub)
                        .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                        .backgroundColor(String(region.clusterId) === this.clusterId ? Theme.accent : Theme.surface)
                        .borderRadius(Theme.rPill)
                        .border({
                          width: 1,
                          color: String(region.clusterId) === this.clusterId ? Theme.accent : Theme.hairline
                        })
                        .onClick(() => {
                          this.pickCluster(String(region.clusterId));
                        })
                    }, (region: HpcRegion) => region.clusterId)
                  }
                }
                .scrollable(ScrollDirection.Horizontal)
                .scrollBar(BarState.Off)
                .width('100%')
              }

              // 概览
              Row({ space: 10 }) {
                this.statCard(L.t('空闲核', 'Free cores'),
                  this.totalFree(), L.t(`共 ${this.queues.length} 个队列`, `${this.queues.length} queues`))
                this.statCard(L.t('配额', 'Quota'),
                  this.quota !== null ? `${this.quota.accountMaxCpu}` : '—',
                  this.quota !== null ? `DCU ${this.quota.accountMaxDcu} · Job ${this.quota.accountMaxJob}` : '—')
              }
              .width('100%')

              // 队列
              Text(L.t('队列', 'Queues'))
                .fontSize(Theme.fTiny)
                .fontColor(Theme.textFaint)
                .width('100%')
                .padding({ left: 2, top: 4 })
              Column() {
                ForEach(this.queues, (queue: HpcQueue, index: number) => {
                  Row({ space: 8 }) {
                    Column({ space: 2 }) {
                      Text(queue.name).fontSize(Theme.fSmall).fontColor(Theme.text)
                      Text(L.t(`${queue.nodes} 节点 · 单节点最多 ${queue.maxPpn} 核`,
                        `${queue.nodes} nodes · max ${queue.maxPpn} cores/node`))
                        .fontSize(10)
                        .fontColor(Theme.textFaint)
                    }
                    .alignItems(HorizontalAlign.Start)
                    .layoutWeight(1)
                    Column({ space: 1 }) {
                      Text(queue.freeCpus)
                        .fontSize(Theme.fBody)
                        .fontWeight(FontWeight.Medium)
                        .fontColor(Number(queue.freeCpus) > 0 ? Theme.ok : Theme.textFaint)
                      Text(`/ ${queue.totalCpus}`).fontSize(9).fontColor(Theme.textFaint)
                    }
                    .alignItems(HorizontalAlign.End)
                  }
                  .width('100%')
                  .padding({ left: 12, right: 12, top: 10, bottom: 10 })
                  if (index < this.queues.length - 1) {
                    Divider().color(Theme.hairline)
                  }
                }, (queue: HpcQueue) => queue.name)
              }
              .width('100%')
              .backgroundColor(Theme.surface)
              .borderRadius(Theme.rMd)
              .border({ width: 1, color: Theme.hairline })

              // 作业
              Text(L.t('运行中作业', 'Running jobs'))
                .fontSize(Theme.fTiny)
                .fontColor(Theme.textFaint)
                .width('100%')
                .padding({ left: 2, top: 4 })
              if (this.jobsUnavailable) {
                Text(L.t('平台作业列表接口暂时返回 internal_error（10001），稍后刷新再试',
                  'Platform job-list endpoint returns internal_error (10001); retry later'))
                  .fontSize(10)
                  .fontColor(Theme.warn)
                  .width('100%')
                  .padding(12)
                  .backgroundColor(Theme.surfaceAlt)
                  .borderRadius(Theme.rMd)
              } else if (this.jobs.length === 0) {
                Text(L.t('当前没有运行中的作业', 'No running jobs'))
                  .fontSize(Theme.fSmall)
                  .fontColor(Theme.textFaint)
                  .width('100%')
                  .padding(16)
                  .textAlign(TextAlign.Center)
                  .backgroundColor(Theme.surface)
                  .borderRadius(Theme.rMd)
                  .border({ width: 1, color: Theme.hairline })
              } else {
                Column() {
                  ForEach(this.jobs, (job: JobRow, index: number) => {
                    Row({ space: 8 }) {
                      Column({ space: 2 }) {
                        Text(job.name.length > 0 ? job.name : job.id)
                          .fontSize(Theme.fSmall)
                          .fontColor(Theme.text)
                          .maxLines(1)
                        Text(`${job.id} · ${job.queue}`).fontSize(10).fontColor(Theme.textFaint)
                      }
                      .alignItems(HorizontalAlign.Start)
                      .layoutWeight(1)
                      Text(this.statusLabel(job.status))
                        .fontSize(10)
                        .fontColor(this.statusColor(job.status))
                    }
                    .width('100%')
                    .padding({ left: 12, right: 12, top: 10, bottom: 10 })
                    if (index < this.jobs.length - 1) {
                      Divider().color(Theme.hairline)
                    }
                  }, (job: JobRow) => job.id)
                }
                .width('100%')
                .backgroundColor(Theme.surface)
                .borderRadius(Theme.rMd)
                .border({ width: 1, color: Theme.hairline })
              }

              Text(L.t('提交作业（含 SLURM 脚本）正在开发中', 'Job submission (with SLURM script) is coming'))
                .fontSize(10)
                .fontColor(Theme.textFaint)
                .width('100%')
                .textAlign(TextAlign.Center)
                .padding({ top: 6, bottom: 16 })
            }
            .width('100%')
            .padding({ left: 14, right: 14, top: 4 })
          }
          .layoutWeight(1)
          .width('100%')
          .scrollBar(BarState.Off)
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(Theme.bg)

      if (this.showCreds) {
        Column() {
          Blank().layoutWeight(1).width('100%').onClick(() => {
            this.showCreds = false;
          })
          this.credsSheet()
        }
        .width('100%')
        .height('100%')
        .backgroundColor('#0B1F3355')
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.bg)
    .key(`jobs-${this.themeRev}`)
  }

  private totalFree(): string {
    let sum: number = 0;
    for (let i = 0; i < this.queues.length; i++) {
      const n: number = Number(this.queues[i].freeCpus);
      if (Number.isFinite(n)) {
        sum += n;
      }
    }
    return `${sum}`;
  }
}
