import { common } from '@kit.AbilityKit';
import { Gateway, ChatMessage, StreamHandlers } from '../service/Gateway';
import { store, DEFAULT_BASE_URL } from '../service/Store';
import { auth } from '../service/Auth';
import { router } from '@kit.ArkUI';
import { MODELS, ModelInfo, modelLabel } from '../model/Models';
import { ModelItem, Conversation, ChatConfig, UserInfo } from '../model/Types';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { api, ApiError, ConversationSummary } from '../service/Api';
import { chat } from '../service/Chat';

interface RenderMsg {
  role: string;
  content: string;
}

function message(role: string, content: string): RenderMsg {
  const item: RenderMsg = { role: role, content: content };
  return item;
}

@Entry
@Component
struct Index {
  @State apiKey: string = '';
  @State baseUrl: string = DEFAULT_BASE_URL;
  @State model: string = 'glm-5.3-flash';
  @State messages: RenderMsg[] = [];
  @State streaming: string = '';
  @State reasoning: string = '';
  @State busy: boolean = false;
  @State showSettings: boolean = false;
  @State draftKey: string = '';
  @State draftUrl: string = DEFAULT_BASE_URL;
  @State errorMsg: string = '';
  @State input: string = '';
  @State draftCloud: string = '';
  @State cloudStatus: string = '';
  @State userName: string = '';
  @State platformName: string = '';
  @State platformModelId: number = 0;
  @State platformModels: ModelItem[] = [];
  @State conversations: Conversation[] = [];
  @State showConversations: boolean = false;
  @State modelOptions: SelectOption[] = [];

  private gateway: Gateway = new Gateway();
  private scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    store.init(getContext(this) as common.UIAbilityContext);
    if (!auth.isLoggedIn()) {
      // 入口判断漏掉时的兜底，保证未登录一定先看到登录页
      router.replaceUrl({ url: 'pages/Login' });
      return;
    }
    this.apiKey = store.getApiKey();
    this.baseUrl = store.getBaseUrl();
    this.model = store.getModel();
    this.draftKey = this.apiKey;
    this.draftUrl = this.baseUrl;
    this.draftCloud = store.getCloudToken();
    api.setToken(this.draftCloud);
    this.modelOptions = this.gatewayOptions();
    if (this.apiKey.length === 0) {
      this.showSettings = true;
    }
    this.loadCloud();
  }

  private gatewayOptions(): SelectOption[] {
    return MODELS.map((m: ModelInfo): SelectOption => {
      const option: SelectOption = { value: m.label };
      return option;
    });
  }

  /** 登录后拉平台侧数据：身份、模型目录、会话列表。失败不影响网关通道可用。 */
  private async loadCloud(): Promise<void> {
    try {
      const me: UserInfo = await auth.refreshUser();
      this.userName = me.fullName !== undefined ? me.fullName : (me.userName !== undefined ? me.userName : '已登录');
      hilog.info(0x0000, 'SCNetLite', 'user: %{public}s', this.userName);
    } catch (e) {
      const err = e as ApiError;
      hilog.warn(0x0000, 'SCNetLite', 'user info failed: %{public}s %{public}s', err.code, err.message);
    }
    try {
      const cfg: ChatConfig = await auth.chatConfig();
      const list: ModelItem[] = cfg.modelList === undefined ? [] : cfg.modelList;
      this.platformModels = list;
      const options: SelectOption[] = list.map((m: ModelItem): SelectOption => {
        const option: SelectOption = { value: m.name === undefined ? `模型 ${m.id}` : m.name };
        return option;
      });
      if (options.length > 0) {
        this.modelOptions = options;
        this.platformName = list[0].name === undefined ? '' : list[0].name as string;
        this.platformModelId = list[0].id === undefined ? 0 : list[0].id;
      }
      hilog.info(0x0000, 'SCNetLite', 'models: %{public}d', list.length);
    } catch (e) {
      const err = e as ApiError;
      this.cloudStatus = `模型目录失败 ${err.code}`;
      hilog.warn(0x0000, 'SCNetLite', 'config failed: %{public}s %{public}s', err.code, err.message);
    }
    try {
      const page = await auth.conversationList();
      const records: Conversation[] = page.records === undefined ? [] : page.records;
      this.conversations = records;
      hilog.info(0x0000, 'SCNetLite', 'conversations: %{public}d', records.length);
    } catch (e) {
      const err = e as ApiError;
      hilog.warn(0x0000, 'SCNetLite', 'conversations failed: %{public}s %{public}s', err.code, err.message);
    }
  }

  /** 平台上选中的数字 modelId（v2 stream 要的是 long）。 */
  private selectedPlatformId(): number {
    const name: string = this.platformName;
    for (let i = 0; i < this.platformModels.length; i++) {
      const item: ModelItem = this.platformModels[i];
      if (item.name === name) {
        return item.id === undefined ? 0 : item.id;
      }
    }
    return this.platformModels.length > 0 ? 0 : 0;
  }

  private selectedIndex(): number {
    for (let i = 0; i < MODELS.length; i++) {
      if (MODELS[i].id === this.model) {
        return i;
      }
    }
    return 0;
  }

  private scrollToEnd(): void {
    try {
      this.scroller.scrollEdge(Edge.Bottom);
    } catch (e) {
      // list may not be scrollable yet
    }
  }

  private finishStream(): void {
    if (this.streaming.length > 0) {
      this.messages = this.messages.concat([message('assistant', this.streaming)]);
    }
    this.streaming = '';
    this.reasoning = '';
    this.busy = false;
    setTimeout(() => this.scrollToEnd(), 50);
  }

  private send(): void {
    const text: string = this.input.trim();
    if (text.length === 0 || this.busy) {
      return;
    }
    if (this.apiKey.length === 0) {
      this.errorMsg = '请先在设置里填入 API Key';
      this.showSettings = true;
      return;
    }
    this.errorMsg = '';
    this.input = '';
    this.streaming = '';
    this.reasoning = '';
    this.busy = true;
    this.messages = this.messages.concat([message('user', text)]);
    this.scrollToEnd();

    const history: ChatMessage[] = this.messages.map((m: RenderMsg): ChatMessage => {
      const item: ChatMessage = { role: m.role, content: m.content };
      return item;
    });

    const platformId: number = this.selectedPlatformId();

    const handlers: StreamHandlers = {
      onDelta: (content: string, reason: string) => {
        if (content.length > 0) {
          this.streaming = this.streaming + content;
        }
        if (reason.length > 0) {
          this.reasoning = this.reasoning + reason;
        }
        this.scrollToEnd();
      },
      onDone: () => {
        this.finishStream();
      },
      onError: (msg: string) => {
        this.errorMsg = msg;
        this.finishStream();
      }
    };

    if (platformId > 0) {
      hilog.info(0x0000, 'SCNetLite', 'send via platform modelId=%{public}d', platformId);
      chat.stream(platformId, text, handlers);
    } else if (this.apiKey.length > 0) {
      this.gateway.stream(this.baseUrl, this.apiKey, this.model, history, handlers);
    } else {
      this.errorMsg = '没有可用的对话通道：平台模型未加载，且未填网关 key';
      this.busy = false;
    }
  }

  private async probeCloud(): Promise<void> {
    const token: string = this.draftCloud.trim();
    if (token.length === 0) {
      this.cloudStatus = '先填平台 accessToken';
      return;
    }
    this.cloudStatus = '请求中…';
    api.setToken(token);
    try {
      const list: ConversationSummary[] = await api.conversationList();
      this.cloudStatus = `OK：云端会话 ${list.length} 条`;
      store.setCloudToken(token);
    } catch (e) {
      const err = e as ApiError;
      this.cloudStatus = `失败 ${err.code}: ${err.message}`;
    }
  }

  @Builder
  bubbleView(role: string, text: string) {
    Row() {
      Text(text)
        .fontSize(15)
        .lineHeight(22)
        .padding({ left: 12, right: 12, top: 10, bottom: 10 })
        .backgroundColor(role === 'user' ? '#D6E9FF' : '#F1F3F5')
        .borderRadius(12)
        .textAlign(TextAlign.Start)
        .constraintSize({ maxWidth: '86%' })
    }
    .width('100%')
    .justifyContent(role === 'user' ? FlexAlign.End : FlexAlign.Start)
  }

  @Builder
  settingsPanel() {
    Column({ space: 10 }) {
      Text('设置').fontSize(16).fontWeight(FontWeight.Medium).width('100%')
      TextInput({ text: this.draftKey, placeholder: 'SCNet API Key（网关 Bearer）' })
        .type(InputType.Password)
        .onChange((value: string) => {
          this.draftKey = value;
        })
      TextInput({ text: this.draftUrl, placeholder: '网关 Base URL' })
        .type(InputType.URL)
        .onChange((value: string) => {
          this.draftUrl = value;
        })
      Row({ space: 10 }) {
        Text('模型').fontSize(14)
        Select(this.modelOptions)
          .selected(this.selectedIndex())
          .value(modelLabel(this.model))
          .layoutWeight(1)
          .onSelect((index: number) => {
            this.model = MODELS[index].id;
            store.setModel(this.model);
          })
      }
      .width('100%')
      TextInput({ text: this.draftCloud, placeholder: '平台 accessToken（www.scnet.cn，可空）' })
        .type(InputType.Password)
        .onChange((value: string) => {
          this.draftCloud = value;
        })
      Row({ space: 10 }) {
        Button('测试云端会话').fontSize(12).height(32).layoutWeight(1).onClick(() => {
          this.probeCloud();
        })
        Text(this.cloudStatus).fontSize(11).fontColor('#6B7280').layoutWeight(1)
      }
      .width('100%')
      Row({ space: 10 }) {
        Button('保存').layoutWeight(1).onClick(() => {
          this.apiKey = this.draftKey.trim();
          this.baseUrl = this.draftUrl.trim().length > 0 ? this.draftUrl.trim() : DEFAULT_BASE_URL;
          store.setApiKey(this.apiKey);
          store.setBaseUrl(this.baseUrl);
          this.showSettings = false;
        })
        Button('关闭').layoutWeight(1).backgroundColor('#E9ECEF').fontColor('#111').onClick(() => {
          this.showSettings = false;
        })
      }
      .width('100%')
      Text('Key 故意留作手动填写：它属于账号凭据，本应用不代登录、不上传，只存在本机 preferences。')
        .fontSize(11)
        .fontColor('#8A8F99')
    }
    .width('100%')
    .padding(14)
    .backgroundColor('#FFFFFF')
    .borderRadius(12)
    .border({ width: 1, color: '#E6E8EB' })
  }

  build() {
    Column() {
      Row({ space: 8 }) {
        Text('SCNet Lite').fontSize(18).fontWeight(FontWeight.Medium)
        if (this.userName.length > 0) {
          Text(`· ${this.userName}`).fontSize(12).fontColor('#6B7280')
        }
        Blank().layoutWeight(1)
        if (this.conversations.length > 0) {
          Text(`会话 ${this.conversations.length}`)
            .fontSize(12)
            .fontColor('#0A7EA4')
            .padding({ left: 6, right: 6 })
            .onClick(() => {
              this.showConversations = !this.showConversations;
            })
        }
        Text(this.platformName.length > 0 ? this.platformName : modelLabel(this.model))
          .fontSize(12)
          .fontColor('#6B7280')
          .constraintSize({ maxWidth: 120 })
        Button('设置').fontSize(12).height(30).backgroundColor('#E9ECEF').fontColor('#111')
          .onClick(() => {
            this.showSettings = !this.showSettings;
            this.draftKey = this.apiKey;
            this.draftUrl = this.baseUrl;
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 8 })

      if (this.showSettings) {
        this.settingsPanel()
      }

      if (this.showConversations) {
        Column({ space: 6 }) {
          Text(`云端会话（${this.conversations.length}）`).fontSize(13).fontWeight(FontWeight.Medium).width('100%')
          List({ space: 4 }) {
            ForEach(this.conversations, (item: Conversation) => {
              ListItem() {
                Row({ space: 8 }) {
                  Text(item.title === undefined ? '(无标题)' : item.title)
                    .fontSize(13)
                    .layoutWeight(1)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(item.taskStatus === undefined ? '' : item.taskStatus).fontSize(10).fontColor('#8A8F99')
                }
                .width('100%')
                .padding({ top: 6, bottom: 6 })
              }
            }, (item: Conversation) => `${item.id}`)
          }
          .height(160)
          .width('100%')
        }
        .width('100%')
        .padding(12)
        .margin({ left: 12, right: 12, bottom: 6 })
        .backgroundColor('#FFFFFF')
        .borderRadius(10)
      }

      if (this.errorMsg.length > 0) {
        Text(this.errorMsg).fontSize(12).fontColor('#C0392B').width('100%')
          .padding({ left: 16, right: 16, bottom: 6 })
      }

      List({ space: 8, scroller: this.scroller }) {
        ForEach(this.messages, (item: RenderMsg, index: number) => {
          ListItem() {
            this.bubbleView(item.role, item.content)
          }
        }, (item: RenderMsg, index: number) => `${index}-${item.role}`)

        if (this.busy) {
          ListItem() {
            this.bubbleView('assistant', this.streaming.length > 0 ? this.streaming : '…')
          }
        }
      }
      .layoutWeight(1)
      .width('100%')
      .padding({ left: 16, right: 16 })

      Row({ space: 8 }) {
        TextArea({ text: this.input, placeholder: '问点什么…' })
          .layoutWeight(1)
          .height(72)
          .fontSize(15)
          .onChange((value: string) => {
            this.input = value;
          })
        Column({ space: 6 }) {
          Button(this.busy ? '停止' : '发送')
            .width(72)
            .onClick(() => {
              if (this.busy) {
                this.gateway.cancel();
                chat.cancel();
                this.finishStream();
              } else {
                this.send();
              }
            })
        }
      }
      .width('100%')
      .padding(12)
      .alignItems(VerticalAlign.Bottom)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F7F8FA')
  }
}
