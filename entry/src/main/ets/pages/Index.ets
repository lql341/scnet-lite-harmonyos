import { common } from '@kit.AbilityKit';
import { router } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Gateway, ChatMessage, StreamHandlers } from '../service/Gateway';
import { store, DEFAULT_BASE_URL, DEFAULT_MODEL } from '../service/Store';
import { auth } from '../service/Auth';
import { apiKeys, GatewayAccess } from '../service/ApiKeys';
import { Conversation, ChatConfig, UserInfo, HistoryPage, HistoryMessage } from '../model/Types';
import { Theme, prettyModel, safe } from '../common/Theme';
import { MarkdownView } from '../view/MarkdownView';
import { ModelSheet } from '../view/ModelSheet';

const TAG: string = 'SCNetLite';

interface RenderMsg {
  role: string;
  content: string;
}

function msg(role: string, content: string): RenderMsg {
  const item: RenderMsg = { role: role, content: content };
  return item;
}

/** 空状态没有服务端推荐时用的兜底示例（都是超算场景，点一下就能发）。 */
const FALLBACK_SUGGEST: string[] = [
  '用三句话说明 SLURM 是做什么的',
  '帮我写一个提交 VASP 任务的 sbatch 脚本',
  'HPC 作业排队很久，有哪些常见原因？',
  '解释一下 MPI 和 OpenMP 的区别'
];

/**
 * 对话页。结构：顶栏 → 消息流（Markdown）→ 错误卡 → 输入区 → 免责声明。
 * 抽屉放账号与历史会话，底部面板选模型。
 */
@Entry
@Component
struct Index {
  @State messages: RenderMsg[] = [];
  @State input: string = '';
  @State streaming: string = '';
  @State progressText: string = '';
  @State busy: boolean = false;
  @State errorMsg: string = '';
  @State userName: string = '';
  @State suggest: string[] = FALLBACK_SUGGEST;
  @State gatewayAccess: GatewayAccess = { key: '', baseUrl: '', model: '', source: 'none' };
  @State gatewayNotice: string = '';
  @State currentCloudId: string = '';
  @State gatewayModels: string[] = [];
  @State conversations: Conversation[] = [];
  @State drawerOpen: boolean = false;
  @State showSettings: boolean = false;
  @State apiKey: string = '';
  @State baseUrl: string = DEFAULT_BASE_URL;
  @State gatewayModel: string = DEFAULT_MODEL;
  @State draftKey: string = '';
  @State draftUrl: string = DEFAULT_BASE_URL;
  @State showModelSheet: boolean = false;

  private gateway: Gateway = new Gateway();
  private scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    store.init(getContext(this) as common.UIAbilityContext);
    if (!auth.isLoggedIn()) {
      router.replaceUrl({ url: 'pages/Login' });
      return;
    }
    this.apiKey = store.getApiKey();
    this.baseUrl = store.getBaseUrl();
    this.gatewayModel = store.getModel();
    this.draftKey = this.apiKey;
    this.draftUrl = this.baseUrl;
    this.loadCloud();
  }

  private async loadCloud(): Promise<void> {
    try {
      const me: UserInfo = await auth.refreshUser();
      this.userName = me.fullName ?? (me.userName ?? '');
    } catch (e) {
      hilog.warn(0x0000, TAG, 'user info failed');
    }
    try {
      const cfg: ChatConfig = await auth.chatConfig();
      const questions: string[] = cfg.recommendQuestion ?? [];
      const usable: string[] = [];
      for (let i = 0; i < questions.length && usable.length < 4; i++) {
        const q: string = safe(questions[i]);
        if (q.length > 0) {
          usable.push(q);
        }
      }
      if (usable.length > 0) {
        this.suggest = usable;
      }
    } catch (e) {
      hilog.warn(0x0000, TAG, 'config failed');
    }
    try {
      this.gatewayAccess = await apiKeys.ensureAccess(await auth.clusterIdentity());
      if (this.gatewayAccess.key.length > 0) {
        this.apiKey = this.gatewayAccess.key;
        this.baseUrl = this.gatewayAccess.baseUrl;
        this.draftKey = this.apiKey;
        this.draftUrl = this.baseUrl;
        this.gatewayModels = await apiKeys.listModels(this.baseUrl, this.apiKey);
        this.gatewayModel = this.pickModel(this.gatewayModels, this.gatewayModel);
        store.setModel(this.gatewayModel);
      }
      if (apiKeys.lastBlocked.length > 0) {
        this.gatewayNotice = apiKeys.lastBlocked;
      }
    } catch (e) {
      hilog.warn(0x0000, TAG, 'gateway access failed');
    }
    await this.reloadConversations();
  }

  /** 上次选择 → SCNet-Max（免费） → 列表首个。 */
  private pickModel(list: string[], preferred: string): string {
    if (preferred.length > 0) {
      for (let i = 0; i < list.length; i++) {
        if (list[i] === preferred) {
          return preferred;
        }
      }
    }
    for (let i = 0; i < list.length; i++) {
      if (list[i] === DEFAULT_MODEL) {
        return DEFAULT_MODEL;
      }
    }
    return list.length > 0 ? list[0] : preferred;
  }

  private async openConversation(item: Conversation): Promise<void> {
    const id: string = item.id ?? '';
    if (id.length === 0) {
      return;
    }
    this.drawerOpen = false;
    this.errorMsg = '';
    try {
      const page: HistoryPage = await auth.loadHistory(id);
      const list: HistoryMessage[] = page.messages ?? [];
      const rendered: RenderMsg[] = [];
      for (let i = 0; i < list.length; i++) {
        const m: HistoryMessage = list[i];
        let text: string = safe(m.text);
        if (text.length === 0 && m.inputs !== undefined) {
          const inputs = m.inputs;
          for (let j = 0; j < inputs.length; j++) {
            const t: string = safe(inputs[j].text);
            if (t.length > 0) {
              text = t;
              break;
            }
          }
        }
        if (text.length === 0) {
          continue;
        }
        rendered.push(msg(m.role === 'user' ? 'user' : 'assistant', text));
      }
      this.messages = rendered;
      this.currentCloudId = id;
      setTimeout(() => this.scrollToEnd(), 80);
    } catch (e) {
      this.errorMsg = '加载会话历史失败';
    }
  }

  private async reloadConversations(): Promise<void> {
    try {
      const page = await auth.conversationList();
      this.conversations = page.records ?? [];
    } catch (e) {
      hilog.warn(0x0000, TAG, 'conversation list failed');
    }
  }

  private scrollToEnd(): void {
    try {
      this.scroller.scrollEdge(Edge.Bottom);
    } catch (e) {
      // 列表不可滚动时忽略
    }
  }

  private finishStream(): void {
    if (this.streaming.length > 0) {
      this.messages = this.messages.concat([msg('assistant', this.streaming)]);
    }
    this.streaming = '';
    this.progressText = '';
    this.busy = false;
    setTimeout(() => this.scrollToEnd(), 50);
  }

  private send(): void {
    const text: string = this.input.trim();
    if (text.length === 0 || this.busy) {
      return;
    }
    this.errorMsg = '';
    this.input = '';
    this.streaming = '';
    this.progressText = '';
    this.busy = true;
    this.currentCloudId = '';
    this.messages = this.messages.concat([msg('user', text)]);
    this.scrollToEnd();

    const handlers: StreamHandlers = {
      onDelta: (content: string, reasoning: string) => {
        if (content.length > 0) {
          this.streaming = this.streaming + content;
          this.progressText = '';
        }
        this.scrollToEnd();
      },
      onProgress: (value: string) => {
        this.progressText = value;
      },
      onTitle: (title: string) => {
        hilog.info(0x0000, TAG, 'title_gen: %{public}d', title.length);
      },
      onDone: () => {
        this.finishStream();
        this.reloadConversations();
      },
      onError: (message: string) => {
        this.errorMsg = message;
        this.finishStream();
      }
    };

    const history: ChatMessage[] = this.messages.map((m: RenderMsg): ChatMessage => {
      const item: ChatMessage = { role: m.role, content: m.content };
      return item;
    });

    if (this.apiKey.length > 0) {
      this.gateway.stream(this.baseUrl, this.apiKey, this.gatewayModel, history, handlers);
    } else {
      this.errorMsg = this.gatewayNotice.length > 0 ? this.gatewayNotice : '没有可用的网关 key，请重新登录';
      this.busy = false;
    }
  }

  private async doLogout(): Promise<void> {
    await auth.logout();
    this.drawerOpen = false;
    router.replaceUrl({ url: 'pages/Login' });
  }

  private newChat(): void {
    this.messages = [];
    this.streaming = '';
    this.errorMsg = '';
    this.currentCloudId = '';
    this.drawerOpen = false;
  }

  // ---------------------------------------------------------------- 顶栏
  @Builder
  iconButton(glyph: string, onTap: () => void) {
    Text(glyph)
      .fontSize(16)
      .fontColor(Theme.textSub)
      .width(34)
      .height(34)
      .textAlign(TextAlign.Center)
      .borderRadius(Theme.rPill)
      .backgroundColor(Theme.surface)
      .border({ width: 1, color: Theme.border })
      .onClick(onTap)
  }

  @Builder
  avatar(size: number, fontSize: number) {
    Text(this.userName.length > 0 ? this.userName.substring(0, 1) : '我')
      .fontSize(fontSize)
      .fontColor(Theme.textOnAccent)
      .width(size)
      .height(size)
      .textAlign(TextAlign.Center)
      .borderRadius(size / 2)
      .backgroundColor(Theme.accent)
  }

  @Builder
  topBar() {
    Row({ space: 12 }) {
      this.iconButton('☰', () => {
        this.drawerOpen = true;
      })

      Column({ space: 1 }) {
        Text('智能体')
          .fontSize(Theme.fTitle)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.text)
        Row({ space: 4 }) {
          Column()
            .width(5)
            .height(5)
            .borderRadius(3)
            .backgroundColor(this.apiKey.length > 0 ? Theme.ok : Theme.textFaint)
          Text(this.apiKey.length > 0 ? '网关已就绪' : '未就绪')
            .fontSize(10)
            .fontColor(Theme.textFaint)
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      this.avatar(32, 13)
    }
    .width('100%')
    .height(56)
    .padding({ left: 14, right: 14 })
    .backgroundColor(Theme.bg)
  }

  // ---------------------------------------------------------------- 消息
  @Builder
  assistantBubble(content: string, isStreaming: boolean) {
    Row({ space: 8 }) {
      Text('S')
        .fontSize(11)
        .fontWeight(FontWeight.Bold)
        .fontColor(Theme.accent)
        .width(26)
        .height(26)
        .textAlign(TextAlign.Center)
        .borderRadius(Theme.rSm)
        .backgroundColor(Theme.accentGhost)
        .border({ width: 1, color: Theme.accentSoft })

      Column() {
        MarkdownView({ content: content, streaming: isStreaming })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .padding({ left: 12, right: 12, top: 10, bottom: 10 })
      .backgroundColor(Theme.surface)
      .borderRadius({ topLeft: 4, topRight: Theme.rLg, bottomLeft: Theme.rLg, bottomRight: Theme.rLg })
      .border({ width: 1, color: Theme.hairline })
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .justifyContent(FlexAlign.Start)
    .padding({ top: 5, bottom: 5 })
  }

  @Builder
  userBubble(content: string) {
    Row() {
      Text(content)
        .fontSize(Theme.fBody)
        .lineHeight(23)
        .fontColor(Theme.textOnAccent)
        .padding({ left: 13, right: 13, top: 9, bottom: 9 })
        .backgroundColor(Theme.accent)
        .borderRadius({ topLeft: Theme.rLg, topRight: 4, bottomLeft: Theme.rLg, bottomRight: Theme.rLg })
        .constraintSize({ maxWidth: '80%' })
    }
    .width('100%')
    .justifyContent(FlexAlign.End)
    .padding({ top: 5, bottom: 5 })
  }

  @Builder
  thinking() {
    Row({ space: 8 }) {
      Text('S')
        .fontSize(11)
        .fontWeight(FontWeight.Bold)
        .fontColor(Theme.accent)
        .width(26)
        .height(26)
        .textAlign(TextAlign.Center)
        .borderRadius(Theme.rSm)
        .backgroundColor(Theme.accentGhost)
        .border({ width: 1, color: Theme.accentSoft })
      Row({ space: 8 }) {
        LoadingProgress().width(18).height(18).color(Theme.accent)
        Text(this.progressText.length > 0 ? this.progressText : '正在生成…')
          .fontSize(Theme.fSmall)
          .fontColor(Theme.textFaint)
      }
      .padding({ left: 12, right: 14, top: 10, bottom: 10 })
      .backgroundColor(Theme.surface)
      .borderRadius({ topLeft: 4, topRight: Theme.rLg, bottomLeft: Theme.rLg, bottomRight: Theme.rLg })
      .border({ width: 1, color: Theme.hairline })
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .padding({ top: 5, bottom: 5 })
  }

  @Builder
  errorCard() {
    Row({ space: 10 }) {
      Text('!')
        .fontSize(12)
        .fontWeight(FontWeight.Bold)
        .fontColor(Theme.danger)
        .width(20)
        .height(20)
        .textAlign(TextAlign.Center)
        .borderRadius(10)
        .backgroundColor(Theme.dangerSoft)
      Text(this.errorMsg)
        .fontSize(Theme.fSmall)
        .lineHeight(18)
        .fontColor(Theme.danger)
        .layoutWeight(1)
      Text('知道了')
        .fontSize(Theme.fSmall)
        .fontColor(Theme.textSub)
        .padding({ left: 8, right: 8, top: 4, bottom: 4 })
        .backgroundColor(Theme.surfaceAlt)
        .borderRadius(Theme.rSm)
        .onClick(() => {
          this.errorMsg = '';
        })
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({ left: 12, right: 10, top: 10, bottom: 10 })
    .backgroundColor(Theme.surface)
    .borderRadius(Theme.rMd)
    .border({ width: 1, color: Theme.dangerBorder })
    .margin({ left: 14, right: 14, top: 4, bottom: 6 })
  }

  // ---------------------------------------------------------------- 空状态
  @Builder
  emptyState() {
    Column() {
      Column({ space: 10 }) {
        Image($r('app.media.app_icon'))
          .width(64)
          .height(64)
          .borderRadius(18)
          .shadow({ radius: 18, color: '#0B1F3320', offsetY: 6 })
        Text('你好，我是 SCNet 智能体')
          .fontSize(21)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.text)
          .margin({ top: 4 })
        Text('面向科研计算的助手：作业调度、模型训练、数据分析')
          .fontSize(Theme.fSmall)
          .fontColor(Theme.textFaint)
          .textAlign(TextAlign.Center)
      }
      .padding({ top: 40, bottom: 26 })

      Column({ space: 8 }) {
        ForEach(this.suggest, (item: string) => {
          Row({ space: 10 }) {
            Text(item)
              .fontSize(Theme.fSmall)
              .fontColor(Theme.textSub)
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
            Text('›').fontSize(15).fontColor(Theme.textFaint)
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
          .padding({ left: 14, right: 12, top: 11, bottom: 11 })
          .backgroundColor(Theme.surface)
          .borderRadius(Theme.rMd)
          .border({ width: 1, color: Theme.hairline })
          .onClick(() => {
            this.input = item;
            this.send();
          })
        }, (item: string) => item)
      }
      .width('100%')
    }
    .width('100%')
    .layoutWeight(1)
    .padding({ left: 18, right: 18 })
    .justifyContent(FlexAlign.Start)
  }

  // ---------------------------------------------------------------- 输入区
  @Builder
  composer() {
    Column() {
      Column() {
        TextArea({ text: this.input, placeholder: '发消息…' })
          .width('100%')
          .constraintSize({ minHeight: 42, maxHeight: 132 })
          .backgroundColor(Color.Transparent)
          .padding({ left: 14, right: 14, top: 9, bottom: 4 })
          .fontSize(Theme.fBody)
          .lineHeight(22)
          .fontColor(Theme.text)
          .placeholderColor(Theme.textFaint)
          .onChange((value: string) => {
            this.input = value;
          })

        Row({ space: 8 }) {
          Row({ space: 5 }) {
            Text(prettyModel(this.gatewayModel))
              .fontSize(Theme.fTiny)
              .fontColor(Theme.accent)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .constraintSize({ maxWidth: 150 })
            Text('⌄').fontSize(11).fontColor(Theme.accent)
          }
          .padding({ left: 10, right: 10, top: 5, bottom: 5 })
          .backgroundColor(Theme.accentGhost)
          .borderRadius(Theme.rPill)
          .onClick(() => {
            this.showModelSheet = true;
          })

          Blank().layoutWeight(1)

          if (this.busy) {
            Row() {
              Column()
                .width(11)
                .height(11)
                .borderRadius(2)
                .backgroundColor(Theme.textOnAccent)
            }
            .width(34)
            .height(34)
            .justifyContent(FlexAlign.Center)
            .backgroundColor(Theme.danger)
            .borderRadius(Theme.rPill)
            .onClick(() => {
              this.gateway.cancel();
              this.finishStream();
            })
          } else {
            Text('↑')
              .fontSize(17)
              .fontWeight(FontWeight.Medium)
              .fontColor(Theme.textOnAccent)
              .width(34)
              .height(34)
              .textAlign(TextAlign.Center)
              .borderRadius(Theme.rPill)
              .backgroundColor(this.input.trim().length > 0 ? Theme.accent : '#C3CBD6')
              .onClick(() => {
                this.send();
              })
          }
        }
        .width('100%')
        .padding({ left: 10, right: 8, bottom: 8 })
      }
      .width('100%')
      .backgroundColor(Theme.surface)
      .borderRadius(Theme.rXl)
      .border({ width: 1, color: Theme.border })
      .shadow(Theme.shadowSoft)

      Text('内容由 AI 生成，请自行核对')
        .fontSize(10)
        .fontColor(Theme.textFaint)
        .width('100%')
        .textAlign(TextAlign.Center)
        .margin({ top: 6, bottom: 2 })
    }
    .width('100%')
    .padding({ left: 14, right: 14, bottom: 8 })
  }

  // ---------------------------------------------------------------- 抽屉
  @Builder
  drawerItem(item: Conversation) {
    Column({ space: 3 }) {
      Row({ space: 6 }) {
        Text(safe(item.title).length > 0 ? safe(item.title) : '(无标题会话)')
          .fontSize(Theme.fSmall)
          .fontColor(item.id === this.currentCloudId ? Theme.accent : Theme.text)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        if (safe(item.taskStatus) === 'completed') {
          Column().width(5).height(5).borderRadius(3).backgroundColor(Theme.ok)
        }
      }
      Text(safe(item.taskStatus).length > 0 ? safe(item.taskStatus) : '历史')
        .fontSize(10)
        .fontColor(Theme.textFaint)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 10, right: 10, top: 9, bottom: 9 })
    .backgroundColor(item.id === this.currentCloudId ? Theme.accentGhost : Color.Transparent)
    .borderRadius(Theme.rSm)
  }

  @Builder
  drawer() {
    Column() {
      Row({ space: 10 }) {
        this.avatar(40, 15)
        Column({ space: 2 }) {
          Text(this.userName.length > 0 ? this.userName : '未命名用户')
            .fontSize(Theme.fBody)
            .fontWeight(FontWeight.Medium)
            .fontColor(Theme.text)
          Text('已登录 · 超算互联网')
            .fontSize(Theme.fTiny)
            .fontColor(Theme.textFaint)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Text('✕')
          .fontSize(13)
          .fontColor(Theme.textFaint)
          .width(28)
          .height(28)
          .textAlign(TextAlign.Center)
          .borderRadius(14)
          .backgroundColor(Theme.surfaceAlt)
          .onClick(() => {
            this.drawerOpen = false;
          })
      }
      .width('100%')
      .padding({ top: 6, bottom: 14 })

      Row({ space: 8 }) {
        Text('＋')
          .fontSize(15)
          .fontColor(Theme.textOnAccent)
        Text('新对话')
          .fontSize(Theme.fBody)
          .fontColor(Theme.textOnAccent)
          .fontWeight(FontWeight.Medium)
        Blank().layoutWeight(1)
      }
      .width('100%')
      .padding({ left: 14, right: 14, top: 11, bottom: 11 })
      .backgroundColor(Theme.accent)
      .borderRadius(Theme.rMd)
      .onClick(() => {
        this.newChat();
      })

      Row({ space: 6 }) {
        Text('历史会话')
          .fontSize(Theme.fTiny)
          .fontColor(Theme.textFaint)
          .layoutWeight(1)
        Text(`${this.conversations.length}`)
          .fontSize(Theme.fTiny)
          .fontColor(Theme.textFaint)
        Text('刷新')
          .fontSize(Theme.fTiny)
          .fontColor(Theme.accent)
          .onClick(() => {
            this.reloadConversations();
          })
      }
      .width('100%')
      .padding({ top: 16, bottom: 6, left: 2, right: 2 })

      List() {
        ForEach(this.conversations, (item: Conversation) => {
          ListItem() {
            this.drawerItem(item)
          }
          .onClick(() => {
            this.openConversation(item);
          })
        }, (item: Conversation) => `${item.id}`)
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Off)

      Divider().color(Theme.hairline).margin({ top: 6, bottom: 6 })

      Row({ space: 10 }) {
        Text('设置')
          .fontSize(Theme.fSmall)
          .fontColor(Theme.textSub)
          .layoutWeight(1)
          .onClick(() => {
            this.showSettings = !this.showSettings;
          })
        Text(this.showSettings ? '收起' : '网关参数')
          .fontSize(Theme.fTiny)
          .fontColor(Theme.textFaint)
          .onClick(() => {
            this.showSettings = !this.showSettings;
          })
      }
      .width('100%')
      .padding({ top: 4, bottom: 8 })

      if (this.showSettings) {
        Column({ space: 8 }) {
          TextInput({ text: this.draftKey, placeholder: 'API Key（留空则用登录自动获取的 key）' })
            .type(InputType.Password)
            .height(38)
            .fontSize(Theme.fSmall)
            .backgroundColor(Theme.surfaceAlt)
            .borderRadius(Theme.rSm)
            .padding({ left: 10, right: 10 })
            .onChange((value: string) => {
              this.draftKey = value;
            })
          TextInput({ text: this.draftUrl, placeholder: 'Base URL' })
            .height(38)
            .fontSize(Theme.fSmall)
            .backgroundColor(Theme.surfaceAlt)
            .borderRadius(Theme.rSm)
            .padding({ left: 10, right: 10 })
            .onChange((value: string) => {
              this.draftUrl = value;
            })
          Row({ space: 8 }) {
            Text('保存')
              .fontSize(Theme.fSmall)
              .fontColor(Theme.textOnAccent)
              .textAlign(TextAlign.Center)
              .layoutWeight(1)
              .padding({ top: 9, bottom: 9 })
              .backgroundColor(Theme.accent)
              .borderRadius(Theme.rSm)
              .onClick(() => {
                this.apiKey = this.draftKey.trim();
                this.baseUrl = this.draftUrl.trim().length > 0 ? this.draftUrl.trim() : DEFAULT_BASE_URL;
                store.setApiKey(this.apiKey);
                store.setBaseUrl(this.baseUrl);
                this.showSettings = false;
              })
            Text('重置')
              .fontSize(Theme.fSmall)
              .fontColor(Theme.textSub)
              .textAlign(TextAlign.Center)
              .layoutWeight(1)
              .padding({ top: 9, bottom: 9 })
              .backgroundColor(Theme.surfaceAlt)
              .borderRadius(Theme.rSm)
              .onClick(() => {
                this.draftKey = store.getAutoKey();
                this.draftUrl = store.getBaseUrl();
              })
          }
          .width('100%')
        }
        .width('100%')
        .padding({ bottom: 8 })
      }

      Text('退出登录')
        .fontSize(Theme.fSmall)
        .fontColor(Theme.danger)
        .width('100%')
        .textAlign(TextAlign.Center)
        .padding({ top: 10, bottom: 10 })
        .backgroundColor(Theme.dangerSoft)
        .borderRadius(Theme.rMd)
        .onClick(() => {
          this.doLogout();
        })
    }
    .width(296)
    .height('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 16 })
    .backgroundColor(Theme.surface)
    .borderRadius({ topRight: Theme.rXl, bottomRight: Theme.rXl })
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        this.topBar()

        if (this.gatewayNotice.length > 0 && this.errorMsg.length === 0) {
          Row({ space: 6 }) {
            Text('ⓘ').fontSize(11).fontColor(Theme.warn)
            Text(this.gatewayNotice)
              .fontSize(10)
              .fontColor(Theme.warn)
              .layoutWeight(1)
              .maxLines(2)
          }
          .width('100%')
          .padding({ left: 14, right: 14, bottom: 4 })
        }

        if (this.messages.length === 0 && this.streaming.length === 0) {
          this.emptyState()
        } else {
          List({ space: 0, scroller: this.scroller }) {
            ForEach(this.messages, (item: RenderMsg, index: number) => {
              ListItem() {
                if (item.role === 'user') {
                  this.userBubble(item.content)
                } else {
                  this.assistantBubble(item.content, false)
                }
              }
            }, (item: RenderMsg, index: number) => `${index}-${item.role}-${item.content.length}`)

            if (this.busy) {
              ListItem() {
                if (this.streaming.length > 0) {
                  this.assistantBubble(this.streaming, true)
                } else {
                  this.thinking()
                }
              }
            }
          }
          .layoutWeight(1)
          .width('100%')
          .padding({ left: 14, right: 14, top: 2, bottom: 6 })
          .scrollBar(BarState.Off)
          .edgeEffect(EdgeEffect.Spring)
        }

        if (this.errorMsg.length > 0) {
          this.errorCard()
        }

        this.composer()
      }
      .width('100%')
      .height('100%')
      .backgroundColor(Theme.bg)

      if (this.drawerOpen) {
        Row() {
          this.drawer()
          Blank()
            .layoutWeight(1)
            .height('100%')
            .backgroundColor('#0B1F3366')
            .onClick(() => {
              this.drawerOpen = false;
            })
        }
        .width('100%')
        .height('100%')
      }

      if (this.showModelSheet) {
        Column() {
          Blank().layoutWeight(1).width('100%').onClick(() => {
            this.showModelSheet = false;
          })
          ModelSheet({
            models: this.gatewayModels,
            current: this.gatewayModel,
            onPick: (name: string) => {
              this.gatewayModel = name;
              store.setModel(name);
              this.showModelSheet = false;
            },
            onClose: () => {
              this.showModelSheet = false;
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
