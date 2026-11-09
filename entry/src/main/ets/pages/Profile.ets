/**
 * 账号页（头像点进来）。
 * 展示身份 / 集群账号 / 当前通道 / 网关 key 状态，提供主题色与退出登录。
 */
import { router } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Theme, prettyModel, safe } from '../common/Theme';
import { store, DEFAULT_MODEL } from '../service/Store';
import { auth, ClusterIdentity, ClusterInfo } from '../service/Auth';
import { credentials } from '../service/Http';
import { UserInfo } from '../model/Types';
import { ThemeSheet } from '../view/ThemeSheet';

const TAG: string = 'SCNetLite';

/** 信息行。⚠️ 不能用 @Builder(label, value) 渲染：ArkUI 的 @Builder 按值传参
 *  不会随状态刷新，数据到了 UI 还是旧值（踩过）。用 @State 数组 + ForEach。 */
interface InfoRow {
  label: string;
  value: string;
}

@Entry
@Component
struct Profile {
  @StorageLink('themeVersion') themeVersion: number = 0;
  @State userName: string = '';
  @State userId: string = '';
  @State clusterAccount: string = '';
  @State clusterName: string = '';
  @State showThemeSheet: boolean = false;
  @State rows: InfoRow[] = [];
  @State clusters: ClusterInfo[] = [];
  @State clusterId: number = 0;
  @State showClusterSheet: boolean = false;
  /** 本次进来换过主题 → 返回时要用 replaceUrl 重建对话页，否则还是旧配色 */
  private themeChanged: boolean = false;

  aboutToAppear(): void {
    Theme.applyPalette(store.getTheme());
    this.load();
  }

  private async load(): Promise<void> {
    try {
      const me: UserInfo = await auth.refreshUser();
      this.userName = safe(me.fullName).length > 0 ? safe(me.fullName) : safe(me.userName);
      // id 在平台侧是数字，这里统一转字符串（直接赋给 string 状态会变成 undefined 判断为假）
      this.userId = safe(me.id).length > 0 ? safe(me.id) : safe(me.userId);
      hilog.info(0x0000, TAG, 'profile user: name=%{public}d id=%{public}d',
        this.userName.length, this.userId.length);
    } catch (e) {
      hilog.warn(0x0000, TAG, 'profile user failed');
    }
    this.rebuildRows();
    try {
      const list: ClusterInfo[] = await auth.clusters();
      this.clusters = list;
      const saved: number = store.getClusterId();
      let picked: number = saved;
      let pickedName: string = '';
      for (let i = 0; i < list.length; i++) {
        if (list[i].clusterId === saved) {
          pickedName = list[i].clusterName;
        }
      }
      if (pickedName.length === 0 && list.length > 0) {
        picked = list[0].clusterId;
        pickedName = list[0].clusterName;
        store.setClusterId(picked);
      }
      this.clusterId = picked;
      this.clusterName = pickedName;
      const identity: ClusterIdentity = await auth.clusterIdentity();
      this.clusterAccount = safe(identity.accountId);
      hilog.info(0x0000, TAG, 'profile cluster: acc=%{public}d name=%{public}d',
        this.clusterAccount.length, this.clusterName.length);
    } catch (e) {
      hilog.warn(0x0000, TAG, 'profile cluster failed');
    }
    this.rebuildRows();
  }

  private rebuildRows(): void {
    const rows: InfoRow[] = [
      { label: '账号', value: this.userId },
      { label: '集群账号', value: this.clusterAccount },
      { label: '集群', value: this.clusterName.length > 0
          ? `${this.clusterName}（${this.clusters.length} 个可选）` : '' },
      { label: '当前通道', value: this.channelLabel() },
      { label: '网关 key', value: this.maskedKey() }
    ];
    this.rows = rows;
  }

  private maskedKey(): string {
    const key: string = store.getAutoKey();
    if (key.length === 0) {
      return '未获取';
    }
    if (key.length <= 8) {
      return '***';
    }
    return `${key.substring(0, 5)}…${key.substring(key.length - 3)}`;
  }

  private channelLabel(): string {
    return store.getChannel() === 'agent' ? '智能体服务（平台）' : prettyModel(store.getModel());
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        Row({ space: 10 }) {
          Text('‹')
            .fontSize(22)
            .fontColor(Theme.textSub)
            .width(32)
            .height(32)
            .textAlign(TextAlign.Center)
            .onClick(() => {
              if (this.themeChanged) {
                router.replaceUrl({ url: 'pages/Index' });
                return;
              }
              try {
                router.back();
              } catch (e) {
                router.replaceUrl({ url: 'pages/Index' });
              }
            })
          Text('账号')
            .fontSize(Theme.fTitle)
            .fontFamily(Theme.fontDisplay)
            .fontWeight(FontWeight.Medium)
            .fontColor(Theme.text)
            .layoutWeight(1)
        }
        .width('100%')
        .height(52)
        .padding({ left: 8, right: 14 })

        Scroll() {
          Column({ space: 14 }) {
            // 头像卡
            Column({ space: 10 }) {
              Text(this.userName.length > 0 ? this.userName.substring(0, 1) : '我')
                .fontSize(26)
                .fontColor(Theme.textOnAccent)
                .width(72)
                .height(72)
                .textAlign(TextAlign.Center)
                .borderRadius(36)
                .backgroundColor(Theme.accent)
                .shadow({ radius: 18, color: '#0B1F3320', offsetY: 6 })
              Text(this.userName.length > 0 ? this.userName : '未命名用户')
                .fontSize(20)
                .fontWeight(FontWeight.Normal)
                .fontFamily(Theme.fontDisplay)
                .fontColor(Theme.text)
              Text('已登录 · 超算互联网')
                .fontSize(Theme.fTiny)
                .fontColor(Theme.textFaint)
            }
            .width('100%')
            .padding({ top: 12, bottom: 6 })

            Column() {
              ForEach(this.rows, (row: InfoRow, index: number) => {
                Row({ space: 12 }) {
                  Text(row.label).fontSize(Theme.fSmall).fontColor(Theme.textFaint).width(84)
                  Text(row.value.length > 0 ? row.value : '—')
                    .fontSize(Theme.fSmall)
                    .fontColor(Theme.text)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .layoutWeight(1)
                }
                .width('100%')
                .padding({ top: 11, bottom: 11 })
                .onClick(() => {
                  if (row.label === '集群' && this.clusters.length > 0) {
                    this.showClusterSheet = true;
                  }
                })

                if (index < this.rows.length - 1) {
                  Divider().color(Theme.hairline)
                }
              }, (row: InfoRow) => `${row.label}-${row.value}`)
            }
            .width('100%')
            .padding({ left: 14, right: 14 })
            .backgroundColor(Theme.surface)
            .borderRadius(Theme.rMd)
            .border({ width: 1, color: Theme.hairline })

            // 外观
            Row({ space: 10 }) {
              Text('主题色').fontSize(Theme.fSmall).fontColor(Theme.text).layoutWeight(1)
              Row({ space: 6 }) {
                Circle().width(16).height(16).fill(Theme.accent)
                Text(Theme.findPalette(store.getTheme()).name)
                  .fontSize(Theme.fTiny)
                  .fontColor(Theme.textSub)
                Text('›').fontSize(13).fontColor(Theme.textFaint)
              }
            }
            .width('100%')
            .padding({ left: 14, right: 12, top: 14, bottom: 14 })
            .backgroundColor(Theme.surface)
            .borderRadius(Theme.rMd)
            .border({ width: 1, color: Theme.hairline })
            .onClick(() => {
              this.showThemeSheet = true;
            })

            Text('退出登录')
              .fontSize(Theme.fSmall)
              .fontColor(Theme.danger)
              .width('100%')
              .textAlign(TextAlign.Center)
              .padding({ top: 12, bottom: 12 })
              .backgroundColor(Theme.dangerSoft)
              .borderRadius(Theme.rMd)
              .onClick(() => {
                auth.logout().then(() => {
                  router.replaceUrl({ url: 'pages/Login' });
                });
              })

            Text('非官方客户端 · 仅调用公开接口')
              .fontSize(10)
              .fontColor(Theme.textFaint)
              .width('100%')
              .textAlign(TextAlign.Center)
              .padding({ top: 4, bottom: 20 })
          }
          .width('100%')
          .padding({ left: 16, right: 16 })
        }
        .layoutWeight(1)
        .width('100%')
        .scrollBar(BarState.Off)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(Theme.bg)

      if (this.showClusterSheet) {
        Column() {
          Blank().layoutWeight(1).width('100%').onClick(() => {
            this.showClusterSheet = false;
          })
          Column() {
            Row()
              .width(36)
              .height(4)
              .borderRadius(2)
              .backgroundColor(Theme.surfaceSunken)
              .margin({ top: 8, bottom: 8 })
            Row() {
              Text(`集群（${this.clusters.length}）`)
                .fontSize(Theme.fTitle)
                .fontFamily(Theme.fontDisplay)
                .fontColor(Theme.text)
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
                  this.showClusterSheet = false;
                })
            }
            .width('100%')
            .padding({ left: 4, right: 4, bottom: 6 })

            List() {
              ForEach(this.clusters, (cluster: ClusterInfo) => {
                ListItem() {
                  Row({ space: 8 }) {
                    Column({ space: 2 }) {
                      Text(cluster.clusterName)
                        .fontSize(Theme.fBody)
                        .fontColor(cluster.clusterId === this.clusterId ? Theme.accent : Theme.text)
                        .fontWeight(cluster.clusterId === this.clusterId ? FontWeight.Medium : FontWeight.Normal)
                      Text(cluster.status === 'inactive' ? `${cluster.clusterId} · 已停用` : `${cluster.clusterId}`)
                        .fontSize(10)
                        .fontColor(cluster.status === 'inactive' ? Theme.danger : Theme.textFaint)
                    }
                    .alignItems(HorizontalAlign.Start)
                    .layoutWeight(1)
                    if (cluster.clusterId === this.clusterId) {
                      Text('✓').fontSize(14).fontColor(Theme.accent).fontWeight(FontWeight.Bold)
                    }
                  }
                  .width('100%')
                  .padding({ left: 4, right: 4, top: 11, bottom: 11 })
                }
                .onClick(() => {
                  this.clusterId = cluster.clusterId;
                  this.clusterName = cluster.clusterName;
                  store.setClusterId(cluster.clusterId);
                  this.rebuildRows();
                  this.showClusterSheet = false;
                })
              }, (cluster: ClusterInfo) => `${cluster.clusterId}`)
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
        .width('100%')
        .height('100%')
        .backgroundColor('#0B1F3355')
      }

      if (this.showThemeSheet) {
        Column() {
          Blank().layoutWeight(1).width('100%').onClick(() => {
            this.showThemeSheet = false;
          })
          ThemeSheet({
            onClose: () => {
              this.showThemeSheet = false;
            },
            onChanged: (id: string) => {
              // 静态色值不会被状态追踪，只能重建页面才能换掉整页配色
              this.themeChanged = true;
              this.showThemeSheet = false;
              router.replaceUrl({ url: 'pages/Profile' });
            }
          })
        }
        .width('100%')
        .height('100%')
        .backgroundColor('#0B1F3355')
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.bg)
  }
}
