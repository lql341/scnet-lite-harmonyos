import { common } from '@kit.AbilityKit';
import { http } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { router } from '@kit.ArkUI';
import { Gateway, ChatMessage, StreamHandlers } from '../service/Gateway';
import { store, DEFAULT_BASE_URL } from '../service/Store';
import { auth } from '../service/Auth';
import { credentials } from '../service/Http';
import { chat } from '../service/Chat';
import { apiKeys, LLM_BASE } from '../service/ApiKeys';
import { MODELS, ModelInfo, modelLabel } from '../model/Models';
import { ModelItem, Conversation, ChatConfig, UserInfo } from '../model/Types';

interface RenderMsg {
  role: string;
  content: string;
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
  @State busy: boolean = false;
  @State errorMsg: string = '';
  @State userName: string = '';
  @State platformName: string = '';
  @State modelId: number = 0;
  @State platformModels: ModelItem[] = [];
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
      const list: ModelItem[] = cfg.modelList ?? [];
      this.platformModels = list;
      if (list.length > 0) {
        this.platformName = list[0].name ?? '';
        this.modelId = list[0].id ?? 0;
      }
      hilog.info(0x0000, 'SCNetLite', 'models %{public}d', list.length);
    } catch (e) {
      hilog.warn(0x0000, 'SCNetLite', 'config failed');
    }
    // 手机端真正走的是网关：平台会自动下发一个 key，拿到就用它（v2 agent 接口实测回「系统繁忙」）
    try {
      const key: string = await apiKeys.ensureKey();
      hilog.info(0x0000, 'SCNetLite', 'gateway key len=%{public}d', key.length);
      if (key.length > 0) {
        const probe = await apiKeys.probeGateway(key);
        hilog.info(0x0000, 'SCNetLite', 'gateway probe ok=%{public}s status=%{public}d model=%{public}s',
          String(probe.ok), probe.status, probe.models);
        if (probe.ok) {
          this.apiKey = key;
          // 手机 APK 走的是 /api/llm/v1（实测 models 200，33 个模型）
          this.baseUrl = LLM_BASE;
          this.gatewayModel = probe.models;
          store.setApiKey(key);
          store.setBaseUrl(this.baseUrl);
          store.setModel(this.gatewayModel);
        }
      }
    } catch (e) {
      hilog.warn(0x0000, 'SCNetLite', 'ensureKey failed');
    }
    await this.reloadConversations();
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
    this.busy = true;
    this.messages = this.messages.concat([msg('user', text)]);
    this.scrollToEnd();

    const handlers: StreamHandlers = {
      onDelta: (content: string, reasoning: string) => {
        if (content.length > 0) {
          this.streaming = this.streaming + content;
        }
        this.scrollToEnd();
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

    if (this.apiKey.length > 0) {
      const history: ChatMessage[] = this.messages.map((m: RenderMsg): ChatMessage => {
        const item: ChatMessage = { role: m.role, content: m.content };
        return item;
      });
      this.gateway.stream(this.baseUrl, this.apiKey, this.gatewayModel, history, handlers);
    } else if (this.modelId > 0) {
      chat.stream(this.modelId, text, handlers);
    } else {
      this.errorMsg = '没有可用通道：模型目录未加载，且没有网关 key';
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
    .padding({ top: 80 })
  }

  @Builder
  composer() {
    Column({ space: 6 }) {
      Row({ space: 8 }) {
        Text('＋')
          .fontSize(20)
          .fontColor('#3B4048')
          .width(32)
          .height(32)
          .textAlign(TextAlign.Center)
        TextArea({ text: this.input, placeholder: '发消息…' })
          .layoutWeight(1)
          .height(40)
          .backgroundColor(Color.Transparent)
          .padding(0)
          .fontSize(15)
          .onChange((value: string) => {
            this.input = value;
          })
        if (this.busy) {
          Text('■')
            .fontSize(14)
            .fontColor('#C0392B')
            .width(32)
            .height(32)
            .textAlign(TextAlign.Center)
            .onClick(() => {
              chat.cancel();
              this.gateway.cancel();
              this.finishStream();
            })
        } else {
          Text('↑')
            .fontSize(18)
            .fontColor('#FFFFFF')
            .width(32)
            .height(32)
            .textAlign(TextAlign.Center)
            .borderRadius(16)
            .backgroundColor(this.input.trim().length > 0 ? '#0E2A47' : '#C7CCD4')
            .onClick(() => {
              this.send();
            })
        }
      }
      .width('100%')
      .padding({ left: 6, right: 6, top: 6, bottom: 6 })
      .backgroundColor('#FFFFFF')
      .borderRadius(14)
      .border({ width: 1, color: '#E6E8EB' })

      Row({ space: 6 }) {
        Text(this.platformName.length > 0 ? this.platformName : modelLabel(this.gatewayModel))
          .fontSize(11)
          .fontColor('#3B4048')
          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
          .backgroundColor('#F1F3F5')
          .borderRadius(10)
          .onClick(() => {
            this.showModelSheet = !this.showModelSheet;
          })
        Text('内容由 AI 生成，请仔细甄别').fontSize(10).fontColor('#A8ADB6').layoutWeight(1)
          .textAlign(TextAlign.End)
      }
      .width('100%')
    }
    .width('100%')
    .padding({ left: 12, right: 12, bottom: 10 })
  }

  @Builder
  modelSheet() {
    Column({ space: 4 }) {
      ForEach(this.platformModels, (item: ModelItem) => {
        Row() {
          Text(item.name ?? `模型 ${item.id}`).fontSize(14).layoutWeight(1)
          if (item.id === this.modelId) {
            Text('✓').fontSize(14).fontColor('#0A7EA4')
          }
        }
        .width('100%')
        .padding({ top: 10, bottom: 10 })
        .onClick(() => {
          this.modelId = item.id ?? 0;
          this.platformName = item.name ?? '';
          this.showModelSheet = false;
        })
      }, (item: ModelItem) => `${item.id}`)
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 8, bottom: 8 })
    .backgroundColor('#FFFFFF')
    .borderRadius(12)
    .border({ width: 1, color: '#E6E8EB' })
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
            chat.conversationId = '';
            this.drawerOpen = false;
          })
        Text('刷新').fontSize(12).fontColor('#8A8F99').onClick(() => {
          this.reloadConversations();
        })
      }
      .width('100%')
      .padding({ top: 10, bottom: 10 })

      Text(`云端会话 ${this.conversations.length}`).fontSize(11).fontColor('#A8ADB6')
        .width('100%').padding({ bottom: 4 })

      List({ space: 2 }) {
        ForEach(this.conversations, (item: Conversation) => {
          ListItem() {
            Text(item.title ?? '(无标题)')
              .fontSize(13)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
              .padding({ top: 8, bottom: 8 })
          }
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
            .padding({ left: 14, right: 14, top: 6, bottom: 6 })
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
                this.bubble(msg('assistant', this.streaming.length > 0 ? this.streaming : '…'))
              }
            }
          }
          .layoutWeight(1)
          .width('100%')
          .padding({ left: 12, right: 12, top: 8 })
        }

        if (this.showModelSheet) {
          this.modelSheet()
        }
        this.composer()
      }
      .width('100%')
      .height('100%')
      .backgroundColor('#F7F8FA')

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
