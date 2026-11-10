/**
 * 账号页（头像点进来）。
 * 展示身份 / 集群账号 / 当前通道 / 网关 key 状态，提供主题色与退出登录。
 */
import { router } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Theme, prettyModel, safe } from '../common/Theme';
import { L } from '../common/I18n';
import { store } from '../service/Store';
import { auth, ClusterIdentity, ClusterInfo } from '../service/Auth';
import { UserInfo } from '../model/Types';
import { ThemeSheet } from '../view/ThemeSheet';
import { AVATAR_PRESETS, Avatar, AvatarPreset, presetsOf, AvatarStyle } from '../view/Avatar';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { bundleManager, ConfigurationConstant } from '@kit.AbilityKit';
import { common } from '@kit.AbilityKit';

const TAG: string = 'SCNetLite';

/** 知名 provider 预设：点一下填好 baseUrl / 模型名，用户只需补 API Key。 */
interface ProviderPreset {
  name: string;
  baseUrl: string;
  model: string;
  hint: string;
}

const PROVIDER_PRESETS: ProviderPreset[] = [
  { name: 'DeepSeek', baseUrl: 'https://api.deepseek.com/v1', model: 'deepseek-chat', hint: 'platform.deepseek.com' },
  { name: 'Moonshot', baseUrl: 'https://api.moonshot.cn/v1', model: 'moonshot-v1-8k', hint: 'platform.moonshot.cn' },
  { name: '阿里通义', baseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1', model: 'qwen-plus', hint: 'bailian.console.aliyun.com' },
  { name: '智谱 GLM', baseUrl: 'https://open.bigmodel.cn/api/paas/v4', model: 'glm-4-plus', hint: 'bigmodel.cn' },
  { name: 'OpenAI', baseUrl: 'https://api.openai.com/v1', model: 'gpt-4o-mini', hint: 'platform.openai.com' },
  { name: 'SiliconFlow', baseUrl: 'https://api.siliconflow.cn/v1', model: 'Qwen/Qwen2.5-72B-Instruct', hint: 'siliconflow.cn' },
  { name: 'Ollama 本地', baseUrl: 'http://127.0.0.1:11434/v1', model: 'qwen2.5', hint: '本地无需 key' }
];

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
  @State fontLevel: number = 1;
  @State lang: string = 'zh';
  @State avatar: string = '';
  @State showAvatarSheet: boolean = false;
  @State showProviderSheet: boolean = false;
  @State showAbout: boolean = false;
  /** 当前应用版本（启动时读一次） */
  @State appVersion: string = '';
  @State colorMode: string = 'system';
  @State cpName: string = '';
  @State cpUrl: string = '';
  @State cpKey: string = '';
  @State cpModel: string = '';
  /** 本次进来换过主题 → 返回时要用 replaceUrl 重建对话页，否则还是旧配色 */
  private themeChanged: boolean = false;

  /** 系统返回手势也走同一套重建逻辑，否则对话页还是旧配色/旧字号 */
  onBackPress(): boolean {
    if (this.themeChanged) {
      router.replaceUrl({ url: 'pages/Index' });
      return true;
    }
    return false;
  }

  aboutToAppear(): void {
    Theme.applyPalette(store.getTheme());
    Theme.applyFontLevel(store.getFontLevel());
    L.zh = store.getLang() !== 'en';
    this.appVersion = this.readVersion();
    this.colorMode = store.getColorMode();
    this.avatar = store.getAvatar();
    this.cpName = store.getCustomName();
    this.cpUrl = store.getCustomBaseUrl();
    this.cpKey = store.getCustomApiKey();
    this.cpModel = store.getCustomModel();
    this.fontLevel = store.getFontLevel();
    this.lang = store.getLang();
    this.load();
  }

  /** 选中内置头像（面板里点任何一处都走这里，避免手势被内层吃掉）。 */
  private applyPreset(id: string): void {
    this.avatar = `preset:${id}`;
    store.setAvatar(this.avatar);
    Theme.bumpRev();
    hilog.info(0x0000, TAG, 'avatar preset applied id=%{public}s', id);
  }

  private async pickAvatarPhoto(): Promise<void> {
    try {
      const options = new photoAccessHelper.PhotoSelectOptions();
      options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      options.maxSelectNumber = 1;
      const picker = new photoAccessHelper.PhotoViewPicker();
      const result: photoAccessHelper.PhotoSelectResult = await picker.select(options);
      if (result.photoUris.length > 0) {
        this.avatar = `file:${result.photoUris[0]}`;
        store.setAvatar(this.avatar);
        this.showAvatarSheet = false;
        Theme.bumpRev();
      }
    } catch (e) {
      hilog.warn(0x0000, TAG, 'avatar picker failed');
    }
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
      { label: L.t('账号', 'Account'), value: this.userId },
      { label: L.t('集群账号', 'Cluster acct'), value: this.clusterAccount },
      {
        label: L.t('集群', 'Cluster'),
        value: this.clusterName.length > 0
          ? L.t(`${this.clusterName}（${this.clusters.length} 个可选）`,
            `${this.clusterName} (${this.clusters.length})`) : ''
      },
      { label: L.t('当前通道', 'Channel'), value: this.channelLabel() },
      { label: L.t('集群调度器', 'Scheduler'), value: this.agentRoute() }
    ];
    this.rows = rows;
  }

  /** 读自身版本号（用于「检查更新」显示基线）。 */
  private readVersion(): string {
    try {
      const info = bundleManager.getBundleInfoForSelfSync(
        bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
      return info.versionName ?? '';
    } catch (e) {
      return '';
    }
  }

  /** 当前通道/服务（替代原来暴露网关 key 那一行）。 */
  private agentRoute(): string {
    return store.getChannel() === 'agent' ? L.t('智能体服务', 'Agent router') : L.t('模型网关', 'Model gateway');
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
          Text(L.t('设置', 'Settings'))
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
              Stack() {
                Avatar({
                  avatarSize: 72,
                  fontSize: 26,
                  name: this.userName,
                  avatar: this.avatar,
                  onTap: () => {
                    this.showAvatarSheet = true;
                  }
                })
                  .shadow({ radius: 18, color: '#0B1F3320', offsetY: 6 })
              }
              Text(this.userName.length > 0 ? this.userName : L.t('未命名用户', 'Unnamed'))
                .fontSize(20)
                .fontWeight(FontWeight.Normal)
                .fontFamily(Theme.fontDisplay)
                .fontColor(Theme.text)
              Text(L.t('已登录 · 超算互联网', 'Signed in · SCNet'))
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

            // 自定义模型 provider
            Row({ space: 10 }) {
              Text(L.t('自定义模型', 'Custom model')).fontSize(Theme.fSmall).fontColor(Theme.text).layoutWeight(1)
              Text(store.getModelProvider() === 'custom'
                ? (store.getCustomName().length > 0 ? store.getCustomName() : L.t('已启用', 'On'))
                : L.t('平台网关', 'Platform gateway'))
                .fontSize(Theme.fTiny)
                .fontColor(Theme.textSub)
              Text('›').fontSize(13).fontColor(Theme.textFaint)
            }
            .width('100%')
            .padding({ left: 14, right: 12, top: 14, bottom: 14 })
            .backgroundColor(Theme.surface)
            .borderRadius(Theme.rMd)
            .border({ width: 1, color: Theme.hairline })
            .onClick(() => {
              this.showProviderSheet = true;
            })

            // 外观模式（浅色 / 深色 / 跟随系统）
            Row({ space: 8 }) {
              Text(L.t('外观', 'Appearance')).fontSize(Theme.fSmall).fontColor(Theme.text).layoutWeight(1)
              Row({ space: 6 }) {
                ForEach(['system', 'light', 'dark'], (m: string) => {
                  Text(m === 'system' ? L.t('跟随', 'Auto')
                    : (m === 'light' ? L.t('浅色', 'Light') : L.t('深色', 'Dark')))
                    .fontSize(Theme.fTiny)
                    .fontColor(this.colorMode === m ? Theme.textOnAccent : Theme.textSub)
                    .padding({ left: 10, right: 10, top: 6, bottom: 6 })
                    .backgroundColor(this.colorMode === m ? Theme.accent : Theme.surfaceAlt)
                    .borderRadius(Theme.rSm)
                    .onClick(() => {
                      this.colorMode = m;
                      store.setColorMode(m);
                      // 用系统级 setColorMode：既改应用深色，也影响系统组件（键盘/弹窗）
                      try {
                        const appCtx = getContext(this).getApplicationContext();
                        appCtx.setColorMode(m === 'dark'
                          ? ConfigurationConstant.ColorMode.COLOR_MODE_DARK
                          : (m === 'light' ? ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT
                            : ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET));
                      } catch (e) {
                        hilog.warn(0x0000, TAG, 'setColorMode failed');
                      }
                      Theme.applyDark(m === 'dark');
                      Theme.bumpRev();
                      router.replaceUrl({ url: 'pages/Profile' });
                    })
                }, (m: string) => m)
              }
            }
            .width('100%')
            .padding({ left: 14, right: 12, top: 12, bottom: 12 })
            .backgroundColor(Theme.surface)
            .borderRadius(Theme.rMd)
            .border({ width: 1, color: Theme.hairline })

            // 外观
            Row({ space: 10 }) {
              Text(L.t('主题色', 'Theme')).fontSize(Theme.fSmall).fontColor(Theme.text).layoutWeight(1)
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

            // 字号三档
            Row({ space: 10 }) {
              Text(L.t('字体大小', 'Text size')).fontSize(Theme.fSmall).fontColor(Theme.text).layoutWeight(1)
              Row({ space: 6 }) {
                ForEach([0, 1, 2], (level: number) => {
                  Text(level === 0 ? L.t('小', 'S') : (level === 1 ? L.t('标准', 'M') : L.t('大', 'L')))
                    .fontSize(Theme.fTiny)
                    .fontColor(this.fontLevel === level ? Theme.textOnAccent : Theme.textSub)
                    .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                    .backgroundColor(this.fontLevel === level ? Theme.accent : Theme.surfaceAlt)
                    .borderRadius(Theme.rSm)
                    .onClick(() => {
                      this.fontLevel = level;
                      store.setFontLevel(level);
                      Theme.applyFontLevel(level);
                      Theme.bumpRev();
                      router.replaceUrl({ url: 'pages/Profile' });
                    })
                }, (level: number) => `${level}`)
              }
            }
            .width('100%')
            .padding({ left: 14, right: 12, top: 12, bottom: 12 })
            .backgroundColor(Theme.surface)
            .borderRadius(Theme.rMd)
            .border({ width: 1, color: Theme.hairline })

            // 语言
            Row({ space: 10 }) {
              Text(L.t('语言', 'Language')).fontSize(Theme.fSmall).fontColor(Theme.text).layoutWeight(1)
              Row({ space: 6 }) {
                ForEach(['zh', 'en'], (code: string) => {
                  Text(code === 'zh' ? '中文' : 'English')
                    .fontSize(Theme.fTiny)
                    .fontColor(this.lang === code ? Theme.textOnAccent : Theme.textSub)
                    .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                    .backgroundColor(this.lang === code ? Theme.accent : Theme.surfaceAlt)
                    .borderRadius(Theme.rSm)
                    .onClick(() => {
                      this.lang = code;
                      store.setLang(code);
                      L.zh = code !== 'en';
                      Theme.bumpRev();
                      router.replaceUrl({ url: 'pages/Profile' });
                    })
                }, (code: string) => code)
              }
            }
            .width('100%')
            .padding({ left: 14, right: 12, top: 12, bottom: 12 })
            .backgroundColor(Theme.surface)
            .borderRadius(Theme.rMd)
            .border({ width: 1, color: Theme.hairline })

            // 检查更新 / 关于
            Row({ space: 10 }) {
              Column({ space: 2 }) {
                Text(L.t('检查更新', 'Check for updates')).fontSize(Theme.fSmall).fontColor(Theme.text)
                Text(this.appVersion.length > 0
                  ? L.t(`当前版本 ${this.appVersion} · 仓库私有，需在页面内登录 GitHub 查看`,
                    `v${this.appVersion} · private repo, sign in on the page`)
                  : L.t('仓库私有，需在页面内登录 GitHub 查看', 'Private repo; sign in on the page'))
                  .fontSize(10)
                  .fontColor(Theme.textFaint)
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
              Text('›').fontSize(13).fontColor(Theme.textFaint)
            }
            .width('100%')
            .padding({ left: 14, right: 12, top: 14, bottom: 14 })
            .backgroundColor(Theme.surface)
            .borderRadius(Theme.rMd)
            .border({ width: 1, color: Theme.hairline })
            .onClick(() => {
              router.pushUrl({
                url: 'pages/WebPage',
                params: {
                  url: 'https://github.com/lql341/scnet-lite-harmonyos/releases',
                  title: L.t('检查更新', 'Check for updates')
                }
              });
            })

            Row({ space: 10 }) {
              Text(L.t('关于', 'About')).fontSize(Theme.fSmall).fontColor(Theme.text).layoutWeight(1)
              Text('SCNet 智能体').fontSize(Theme.fTiny).fontColor(Theme.textFaint)
            }
            .width('100%')
            .padding({ left: 14, right: 12, top: 14, bottom: 14 })
            .backgroundColor(Theme.surface)
            .borderRadius(Theme.rMd)
            .border({ width: 1, color: Theme.hairline })
            .onClick(() => {
              this.showAbout = true;
            })

            Text(L.t('退出登录', 'Sign out'))
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

      if (this.showAbout) {
        Column() {
          Blank().layoutWeight(1).width('100%').onClick(() => {
            this.showAbout = false;
          })
          Column({ space: 12 }) {
            Image($r('app.media.app_icon'))
              .width(56)
              .height(56)
              .borderRadius(14)
            Text(L.t('SCNet 智能体', 'SCNet Agent'))
              .fontSize(Theme.fTitle)
              .fontFamily(Theme.fontDisplay)
              .fontColor(Theme.text)
            Text(L.t('非官方客户端，仅调用公开接口', 'Unofficial client, public APIs only'))
              .fontSize(10)
              .fontColor(Theme.textFaint)

            Divider().color(Theme.hairline).margin({ top: 4, bottom: 4 })

            Row({ space: 10 }) {
              Text(L.t('作者', 'Author')).fontSize(Theme.fSmall).fontColor(Theme.textFaint).width(72)
              Text('lql341').fontSize(Theme.fSmall).fontColor(Theme.text).layoutWeight(1)
            }
            .width('100%')
            Row({ space: 10 }) {
              Text('GitHub').fontSize(Theme.fSmall).fontColor(Theme.textFaint).width(72)
              Text('github.com/lql341').fontSize(Theme.fSmall).fontColor(Theme.accent).layoutWeight(1)
                .onClick(() => {
                  router.pushUrl({
                    url: 'pages/WebPage',
                    params: { url: 'https://github.com/lql341', title: 'lql341' }
                  });
                })
            }
            .width('100%')
            Row({ space: 10 }) {
              Text(L.t('项目', 'Project')).fontSize(Theme.fSmall).fontColor(Theme.textFaint).width(72)
              Text('scnet-lite-harmonyos').fontSize(Theme.fSmall).fontColor(Theme.accent).layoutWeight(1)
                .onClick(() => {
                  router.pushUrl({
                    url: 'pages/WebPage',
                    params: {
                      url: 'https://github.com/lql341/scnet-lite-harmonyos',
                      title: 'scnet-lite-harmonyos'
                    }
                  });
                })
            }
            .width('100%')

            Text(L.t('关闭', 'Close'))
              .fontSize(Theme.fSmall)
              .fontColor(Theme.textOnAccent)
              .width('100%')
              .textAlign(TextAlign.Center)
              .padding({ top: 10, bottom: 10 })
              .backgroundColor(Theme.accent)
              .borderRadius(Theme.rSm)
              .onClick(() => {
                this.showAbout = false;
              })
          }
          .width('100%')
          .padding({ left: 24, right: 24, top: 22, bottom: 26 })
          .backgroundColor(Theme.surface)
          .borderRadius({ topLeft: Theme.rXl, topRight: Theme.rXl })
          .shadow(Theme.shadowSheet)
          .alignItems(HorizontalAlign.Center)
        }
        .width('100%')
        .height('100%')
        .backgroundColor('#0B1F3355')
      }

      if (this.showProviderSheet) {
        Column() {
          Blank().layoutWeight(1).width('100%').onClick(() => {
            this.showProviderSheet = false;
          })
          Column({ space: 10 }) {
            Text(L.t('自定义模型', 'Custom model'))
              .fontSize(Theme.fTitle)
              .fontFamily(Theme.fontDisplay)
              .fontColor(Theme.text)
              .width('100%')
            Text(L.t('接入任意 OpenAI 兼容端点（DeepSeek / Kimi / 本地 Ollama 等）。密钥只存本机。',
              'Point it at any OpenAI-compatible endpoint. Key stays on this device.'))
              .fontSize(10)
              .fontColor(Theme.textFaint)
              .width('100%')

            Scroll() {
              Row({ space: 8 }) {
                ForEach(PROVIDER_PRESETS, (preset: ProviderPreset) => {
                  Text(preset.name)
                    .fontSize(Theme.fTiny)
                    .fontColor(this.cpName === preset.name ? Theme.textOnAccent : Theme.textSub)
                    .padding({ left: 10, right: 10, top: 6, bottom: 6 })
                    .backgroundColor(this.cpName === preset.name ? Theme.accent : Theme.surfaceAlt)
                    .borderRadius(Theme.rPill)
                    .onClick(() => {
                      this.cpName = preset.name;
                      this.cpUrl = preset.baseUrl;
                      this.cpModel = preset.model;
                    })
                }, (preset: ProviderPreset) => preset.name)
              }
            }
            .scrollable(ScrollDirection.Horizontal)
            .scrollBar(BarState.Off)
            .width('100%')

            TextInput({ text: this.cpName, placeholder: L.t('名称（如 deepseek）', 'Name') })
              .height(40).fontSize(Theme.fSmall).backgroundColor(Theme.surfaceAlt)
              .borderRadius(Theme.rSm).padding({ left: 12, right: 12 })
              .onChange((v: string) => {
                this.cpName = v;
              })
            TextInput({ text: this.cpUrl, placeholder: 'Base URL（…/v1）' })
              .height(40).fontSize(Theme.fSmall).backgroundColor(Theme.surfaceAlt)
              .borderRadius(Theme.rSm).padding({ left: 12, right: 12 })
              .onChange((v: string) => {
                this.cpUrl = v;
              })
            TextInput({ text: this.cpKey, placeholder: 'API Key' })
              .type(InputType.Password)
              .height(40).fontSize(Theme.fSmall).backgroundColor(Theme.surfaceAlt)
              .borderRadius(Theme.rSm).padding({ left: 12, right: 12 })
              .onChange((v: string) => {
                this.cpKey = v;
              })
            TextInput({ text: this.cpModel, placeholder: L.t('模型名（如 deepseek-chat）', 'Model id') })
              .height(40).fontSize(Theme.fSmall).backgroundColor(Theme.surfaceAlt)
              .borderRadius(Theme.rSm).padding({ left: 12, right: 12 })
              .onChange((v: string) => {
                this.cpModel = v;
              })

            Row({ space: 8 }) {
              Text(L.t('用平台网关', 'Use platform'))
                .fontSize(Theme.fSmall)
                .fontColor(Theme.textSub)
                .layoutWeight(1)
                .textAlign(TextAlign.Center)
                .padding({ top: 10, bottom: 10 })
                .backgroundColor(Theme.surfaceAlt)
                .borderRadius(Theme.rSm)
                .onClick(() => {
                  store.setModelProvider('platform');
                  this.showProviderSheet = false;
                  router.replaceUrl({ url: 'pages/Index' });
                })
              Text(L.t('保存并启用', 'Save & enable'))
                .fontSize(Theme.fSmall)
                .fontColor(Theme.textOnAccent)
                .layoutWeight(1)
                .textAlign(TextAlign.Center)
                .padding({ top: 10, bottom: 10 })
                .backgroundColor(Theme.accent)
                .borderRadius(Theme.rSm)
                .onClick(() => {
                  store.setCustomProvider(this.cpName.trim(), this.cpUrl.trim(),
                    this.cpKey.trim(), this.cpModel.trim());
                  store.setModelProvider('custom');
                  this.showProviderSheet = false;
                  router.replaceUrl({ url: 'pages/Index' });
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

      if (this.showAvatarSheet) {
        Column() {
          Blank().layoutWeight(1).width('100%').onClick(() => {
            this.showAvatarSheet = false;
          })
          Column({ space: 12 }) {
            Text(L.t('头像', 'Avatar'))
              .fontSize(Theme.fTitle)
              .fontFamily(Theme.fontDisplay)
              .fontColor(Theme.text)
              .width('100%')
            Text(L.t('选一个内置头像，或从相册选，或让智能体帮你画一个',
              'Pick a preset, choose a photo, or ask the agent to draw one'))
              .fontSize(10)
              .fontColor(Theme.textFaint)
              .width('100%')

            ForEach(['cartoon', 'scene', 'mono'], (style: string) => {
              Column({ space: 6 }) {
                Text(style === 'cartoon' ? L.t('卡通', 'Cartoon')
                  : (style === 'scene' ? L.t('风景', 'Scenery') : L.t('字母', 'Letter')))
                  .fontSize(10)
                  .fontColor(Theme.textFaint)
                  .width('100%')
                Flex({ wrap: FlexWrap.Wrap }) {
                  ForEach(presetsOf(style as AvatarStyle), (preset: AvatarPreset) => {
                    Column({ space: 3 }) {
                      Avatar({
                        avatarSize: 46,
                        fontSize: 18,
                        name: this.userName,
                        avatar: `preset:${preset.id}`,
                        onTap: () => {
                          this.applyPreset(preset.id);
                        }
                      })
                      if (this.avatar === `preset:${preset.id}`) {
                        Text('✓').fontSize(9).fontColor(Theme.accent)
                      }
                    }
                    .width('16.6%')
                    .padding({ top: 4, bottom: 4 })
                  }, (preset: AvatarPreset) => preset.id)
                }
                .width('100%')
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)
            }, (style: string) => style)

            Row({ space: 8 }) {
              Text(L.t('从相册选', 'From gallery'))
                .fontSize(Theme.fSmall)
                .fontColor(Theme.accent)
                .layoutWeight(1)
                .textAlign(TextAlign.Center)
                .padding({ top: 10, bottom: 10 })
                .backgroundColor(Theme.accentGhost)
                .borderRadius(Theme.rSm)
                .onClick(() => {
                  this.pickAvatarPhoto();
                })
              Text(L.t('恢复默认', 'Reset'))
                .fontSize(Theme.fSmall)
                .fontColor(Theme.textSub)
                .layoutWeight(1)
                .textAlign(TextAlign.Center)
                .padding({ top: 10, bottom: 10 })
                .backgroundColor(Theme.surfaceAlt)
                .borderRadius(Theme.rSm)
                .onClick(() => {
                  this.avatar = '';
                  store.setAvatar('');
                  Theme.bumpRev();
                })
            }
            .width('100%')

            Text(L.t('让智能体生成头像 →', 'Ask the agent to generate →'))
              .fontSize(Theme.fSmall)
              .fontColor(Theme.textOnAccent)
              .width('100%')
              .textAlign(TextAlign.Center)
              .padding({ top: 10, bottom: 10 })
              .backgroundColor(Theme.accent)
              .borderRadius(Theme.rSm)
              .onClick(() => {
                this.showAvatarSheet = false;
                // 生成式头像：把画面描述带进对话（图像生成能力由平台 MCP 提供）
                router.replaceUrl({
                  url: 'pages/Index',
                  params: {
                    prefill: '生成一个简洁的科技感头像：几何线条 + 深蓝橙配色，正方形 512x512，无文字'
                  }
                });
              })
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
