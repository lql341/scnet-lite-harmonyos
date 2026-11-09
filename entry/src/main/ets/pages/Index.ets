import { common } from '@kit.AbilityKit';
import { http } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { router } from '@kit.ArkUI';
import { Gateway, ChatMessage, StreamHandlers } from '../service/Gateway';
import { store, DEFAULT_BASE_URL, DEFAULT_MODEL } from '../service/Store';
import { auth } from '../service/Auth';
import { credentials } from '../service/Http';
import { apiKeys, GatewayAccess } from '../service/ApiKeys';
import { ModelSheet } from '../view/ModelSheet';
import { MODELS, ModelInfo, modelLabel } from '../model/Models';
import { Conversation, ChatConfig, UserInfo, HistoryPage, HistoryMessage } from '../model/Types';

interface RenderMsg {
  role: string;
  content: string;
}

/** 网关模型 id 形如 DeepSeek-V4.1-Flash-1017，展示时去掉末尾日期后缀并换成空格分词的短名。 */
function prettyModel(name: string): string {
  let out: string = name;
  const dash: number = out.lastIndexOf('-');
  if (dash > 0) {
    const tail: string = out.substring(dash + 1);
    if (tail.length >= 4 && Number.isNaN(Number(tail)) === false) {
      out = out.substring(0, dash);
    }
  }
  return out.replace(/-/g, ' ');
}

/** 平台字段经常是 null 而不是 undefined，ArkTS 里 .length 会直接抛，统一收口。 */
function safe(value: Object | undefined | null): string {
  if (value === undefined || value === null) {
    return '';
  }
  if (typeof value === 'string') {
    return value as string;
  }
  return `${value}`;
}

function msg(role: string, content: string): RenderMsg {
  const item: RenderMsg = { role: role, content: content };
  return item;
}

/**
 * 对话页。布局对齐官方移动端：顶栏（☰ / 标题 / 头像）、消息区、免责声明、圆角输入区（+ / 模型 / 发送），
 * 左侧抽屉放会话列表与账号操作。
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
  @State gatewayAccess: GatewayAccess = { key: '', baseUrl: '', model: '', source: 'none' };
  @State gatewayNotice: string = '';
  /** 抽屉里正在看的历史会话（只读，网关通道不复用它的上下文） */
  @State currentCloudId: string = '';
  @State gatewayModels: string[] = [];
  @State conversations: Conversation[] = [];
  @State drawerOpen: boolean = false;
  @State showSettings: boolean = false;
  @State apiKey: string = '';
  @State baseUrl: string = DEFAULT_BASE_URL;
  @State gatewayModel: string = 'glm-5.3-flash';
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
      hilog.info(0x0000, 'SCNetLite', 'user %{public}s', this.userName);
    } catch (e) {
      hilog.warn(0x0000, 'SCNetLite', 'user info failed');
    }
    try {
      const cfg: ChatConfig = await auth.chatConfig();
      hilog.info(0x0000, 'SCNetLite', 'config ok, defaultCluster=%{public}d',
        cfg.defaultCluster ?? 0);
    } catch (e) {
      hilog.warn(0x0000, 'SCNetLite', 'config failed');
    }
    // 网关模型链路：cluster-user-detail → config/status →（必要时 authorize）
    // → api-key/createActivityApiKey → /models。与官方客户端 / scnet-cli 同一条链路。
    try {
      this.gatewayAccess = await apiKeys.ensureAccess(await auth.clusterIdentity());
      if (this.gatewayAccess.key.length > 0) {
        this.apiKey = this.gatewayAccess.key;
        this.baseUrl = this.gatewayAccess.baseUrl;
        this.draftKey = this.apiKey;
        this.draftUrl = this.baseUrl;
        if (this.gatewayAccess.model.length > 0) {
          this.gatewayModel = this.gatewayAccess.model;
        }
        this.gatewayModels = await apiKeys.listModels(this.baseUrl, this.apiKey);
        this.gatewayModel = this.pickModel(this.gatewayModels, this.gatewayModel);
        store.setModel(this.gatewayModel);
        hilog.info(0x0000, 'SCNetLite', 'model=%{public}s (of %{public}d)',
          this.gatewayModel, this.gatewayModels.length);
      }
      if (apiKeys.lastBlocked.length > 0) {
        this.gatewayNotice = apiKeys.lastBlocked;
        hilog.warn(0x0000, 'SCNetLite', 'gateway blocked: %{public}s', this.gatewayNotice);
      }
    } catch (e) {
      hilog.warn(0x0000, 'SCNetLite', 'gateway access failed');
    }
    await this.reloadConversations();
  }

  /** 点会话 → 拉历史并渲染。 */
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
      hilog.info(0x0000, 'SCNetLite', 'history: %{public}d messages', rendered.length);
      setTimeout(() => this.scrollToEnd(), 80);
    } catch (e) {
      this.errorMsg = '加载会话历史失败';
    }
  }

  private async reloadConversations(): Promise<void> {
    try {
      const page = await auth.conversationList();
      this.conversations = page.records ?? [];
      hilog.info(0x0000, 'SCNetLite', 'conversations %{public}d', this.conversations.length);
    } catch (e) {
      hilog.warn(0x0000, 'SCNetLite', 'conversation list failed');
    }
  }

  /**
   * 选默认模型：优先用户上次选的 → 其次 `SCNet-Max`（平台自营、不扣余额）→ 最后列表第一个。
   * 余额为 0 的账号只有 SCNet-Max 能用，所以这个优先级很关键。
   */
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

  private scrollToEnd(): void {
    try {
      this.scroller.scrollEdge(Edge.Bottom);
    } catch (e) {
      // 列表可能还不可滚动
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
      onProgress: (text: string) => {
        this.progressText = text;
        this.scrollToEnd();
      },
      onTitle: (title: string) => {
        hilog.info(0x0000, 'SCNetLite', 'title_gen: %{public}d chars', title.length);
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
    // 网关 OpenAI 兼容通道（与官方客户端 / scnet-cli 同一条链路）
    if (this.apiKey.length > 0) {
      this.gateway.stream(this.baseUrl, this.apiKey, this.gatewayModel, history, handlers);
    } else {
      this.errorMsg = this.gatewayNotice.length > 0 ? this.gatewayNotice : '没有可用的网关 key：请重新登录';
      this.busy = false;
    }
  }

  private async doLogout(): Promise<void> {
    await auth.logout();
    this.drawerOpen = false;
    router.replaceUrl({ url: 'pages/Login' });
  }

  @Builder
  topBar() {
    Row({ space: 12 }) {
      Text('☰')
        .fontSize(20)
        .width(36)
        .height(36)
        .textAlign(TextAlign.Center)
        .onClick(() => {
          this.drawerOpen = true;
        })
      Text('智能体').fontSize(16).fontWeight(FontWeight.Medium).layoutWeight(1)
      Text(this.userName.length > 0 ? this.userName.substring(0, 1) : '我')
        .fontSize(13)
        .fontColor('#FFFFFF')
        .width(30)
        .height(30)
        .textAlign(TextAlign.Center)
        .borderRadius(15)
        .backgroundColor('#0E2A47')
        .onClick(() => {
          this.drawerOpen = true;
        })
    }
    .width('100%')
    .height(52)
    .padding({ left: 8, right: 12 })
    .backgroundColor('#FFFFFF')
    .border({ width: { bottom: 1 }, color: '#EEF0F3' })
  }

  @Builder
  bubble(item: RenderMsg) {
    Row() {
      Text(item.content)
        .fontSize(15)
        .lineHeight(23)
        .padding({ left: 12, right: 12, top: 10, bottom: 10 })
        .backgroundColor(item.role === 'user' ? '#DEEDFF' : '#F4F6F8')
        .borderRadius(14)
        .constraintSize({ maxWidth: '84%' })
    }
    .width('100%')
    .justifyContent(item.role === 'user' ? FlexAlign.End : FlexAlign.Start)
    .padding({ top: 4, bottom: 4 })
  }

  @Builder
  emptyState() {
    Column({ space: 10 }) {
      Image($r('app.media.app_icon')).width(56).height(56).borderRadius(14)
      Text('有什么可以帮你？').fontSize(16).fontColor('#3B4048')
      Text('可以问超算作业、SLURM 脚本、模型训练、数据分析…')
        .fontSize(12)
        .fontColor('#8A8F99')
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .padding({ left: 24, right: 24, bottom: 40 })
  }

  @Builder
  composer() {
    Column({ space: 0 }) {
      TextArea({ text: this.input, placeholder: '发消息…' })
        .constraintSize({ minHeight: 44, maxHeight: 132 })
        .width('100%')
        .backgroundColor(Color.Transparent)
        .padding({ left: 14, right: 14, top: 10, bottom: 6 })
        .fontSize(15)
        .lineHeight(21)
        .onChange((value: string) => {
          this.input = value;
        })

      Row({ space: 8 }) {
        Text('＋')
          .fontSize(18)
          .fontColor('#5B6270')
          .width(30)
          .height(30)
          .textAlign(TextAlign.Center)
          .borderRadius(15)
          .backgroundColor('#F1F3F5')

        Text(this.gatewayModel.length > 0 ? prettyModel(this.gatewayModel) : '选择模型')
          .fontSize(11)
          .fontColor('#3B4048')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .constraintSize({ maxWidth: 170 })
          .padding({ left: 10, right: 10, top: 5, bottom: 5 })
          .backgroundColor('#F1F3F5')
          .borderRadius(11)
          .onClick(() => {
            this.showModelSheet = true;
          })

        Blank().layoutWeight(1)

        if (this.busy) {
          Text('■')
            .fontSize(12)
            .fontColor('#FFFFFF')
            .width(30)
            .height(30)
            .textAlign(TextAlign.Center)
            .borderRadius(15)
            .backgroundColor('#C0392B')
            .onClick(() => {
              this.gateway.cancel();
              this.finishStream();
            })
        } else {
          Text('↑')
            .fontSize(17)
            .fontColor('#FFFFFF')
            .width(30)
            .height(30)
            .textAlign(TextAlign.Center)
            .borderRadius(15)
            .backgroundColor(this.input.trim().length > 0 ? '#0E2A47' : '#C7CCD4')
            .onClick(() => {
              this.send();
            })
        }
      }
      .width('100%')
      .padding({ left: 10, right: 10, bottom: 8 })
    }
    .width('100%')
    .backgroundColor('#FFFFFF')
    .borderRadius(18)
    .border({ width: 1, color: '#E6E8EB' })
    .shadow({ radius: 10, color: '#00000010', offsetY: 2 })
    .margin({ left: 12, right: 12, bottom: 8 })
  }

  @Builder
  drawer() {
    Column() {
      Row({ space: 10 }) {
        Text(this.userName.length > 0 ? this.userName.substring(0, 1) : '我')
          .fontSize(14)
          .fontColor('#FFFFFF')
          .width(34)
          .height(34)
          .textAlign(TextAlign.Center)
          .borderRadius(17)
          .backgroundColor('#0E2A47')
        Column() {
          Text(this.userName.length > 0 ? this.userName : '未命名用户').fontSize(14)
          Text(auth.isLoggedIn() ? '已登录 · 超算互联网' : '未登录').fontSize(11).fontColor('#8A8F99')
        }
        .alignItems(HorizontalAlign.Start)
        Blank().layoutWeight(1)
        Text('✕').fontSize(16).onClick(() => {
          this.drawerOpen = false;
        })
      }
      .width('100%')
      .padding({ top: 12, bottom: 12 })

      Divider().color('#EEF0F3')

      Row({ space: 8 }) {
        Text('＋ 新建对话').fontSize(14).fontColor('#0E2A47').layoutWeight(1)
          .onClick(() => {
            this.messages = [];
            this.streaming = '';
            this.currentCloudId = '';
            this.drawerOpen = false;
          })
        Text('刷新').fontSize(12).fontColor('#8A8F99').onClick(() => {
          this.reloadConversations();
        })
      }
      .width('100%')
      .padding({ top: 10, bottom: 10 })

      // 这些是平台侧的历史会话（chatbot 接口），当前只能看；发消息走的是网关，不会续写它们
      Text(`历史会话 ${this.conversations.length}（只读）`).fontSize(11).fontColor('#A8ADB6')
        .width('100%').padding({ bottom: 4 })

      List({ space: 2 }) {
        ForEach(this.conversations, (item: Conversation) => {
          ListItem() {
            Row({ space: 6 }) {
              Text(safe(item.title).length > 0 ? safe(item.title) : '(无标题)')
                .fontSize(13)
                .fontColor('#1F2329')
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1)
              Text(safe(item.taskStatus))
                .fontSize(10)
                .fontColor('#A8ADB6')
            }
            .width('100%')
            .padding({ left: 10, right: 10, top: 10, bottom: 10 })
            .borderRadius(8)
            .backgroundColor(item.id === this.currentCloudId ? '#EAF3FB' : '#FFFFFF')
          }
          .onClick(() => {
            this.openConversation(item);
          })
        }, (item: Conversation) => `${item.id}`)
      }
      .layoutWeight(1)
      .width('100%')

      Divider().color('#EEF0F3')
      Row({ space: 8 }) {
        Text('设置').fontSize(13).fontColor('#3B4048').layoutWeight(1)
          .onClick(() => {
            this.showSettings = !this.showSettings;
          })
        Text('退出登录').fontSize(13).fontColor('#C0392B').onClick(() => {
          this.doLogout();
        })
      }
      .width('100%')
      .padding({ top: 10, bottom: 14 })

      if (this.showSettings) {
        Column({ space: 8 }) {
          TextInput({ text: this.draftKey, placeholder: '网关 API Key（备用通道，可空）' })
            .type(InputType.Password)
            .height(38)
            .onChange((value: string) => {
              this.draftKey = value;
            })
          TextInput({ text: this.draftUrl, placeholder: '网关 Base URL' })
            .height(38)
            .onChange((value: string) => {
              this.draftUrl = value;
            })
          Button('保存').height(34).width('100%').onClick(() => {
            this.apiKey = this.draftKey.trim();
            this.baseUrl = this.draftUrl.trim().length > 0 ? this.draftUrl.trim() : DEFAULT_BASE_URL;
            store.setApiKey(this.apiKey);
            store.setBaseUrl(this.baseUrl);
            this.showSettings = false;
          })
        }
        .width('100%')
        .padding({ bottom: 10 })
      }
    }
    .width(280)
    .height('100%')
    .padding({ left: 14, right: 14 })
    .backgroundColor('#FFFFFF')
  }

  build() {
    Stack({ alignContent: Alignment.Start }) {
      Column() {
        this.topBar()

        if (this.errorMsg.length > 0) {
          Text(this.errorMsg)
            .fontSize(12)
            .fontColor('#C0392B')
            .width('100%')
            .padding({ left: 14, right: 14, top: 8, bottom: 8 })
            .backgroundColor('#FDECEA')
        }

        if (this.messages.length === 0 && this.streaming.length === 0) {
          this.emptyState()
        } else {
          List({ space: 6, scroller: this.scroller }) {
            ForEach(this.messages, (item: RenderMsg, index: number) => {
              ListItem() {
                this.bubble(item)
              }
            }, (item: RenderMsg, index: number) => `${index}-${item.role}`)

            if (this.busy) {
              ListItem() {
                this.bubble(msg('assistant', this.streaming.length > 0 ? this.streaming :
                  (this.progressText.length > 0 ? this.progressText : '…')))
              }
            }
          }
          .layoutWeight(1)
          .width('100%')
          .padding({ left: 12, right: 12, top: 8, bottom: 10 })
        }

        this.composer()
      }
      .width('100%')
      .height('100%')
      .backgroundColor('#F7F8FA')

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
        .backgroundColor('#00000033')
      }

      if (this.drawerOpen) {
        Row() {
          this.drawer()
          Blank().layoutWeight(1).backgroundColor('#00000033').onClick(() => {
            this.drawerOpen = false;
          })
        }
        .width('100%')
        .height('100%')
      }
    }
    .width('100%')
    .height('100%')
  }
}
