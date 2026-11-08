import { common } from '@kit.AbilityKit';
import { Gateway, ChatMessage, StreamHandlers } from '../service/Gateway';
import { store, DEFAULT_BASE_URL } from '../service/Store';
import { MODELS, ModelInfo, modelLabel } from '../model/Models';

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

  private gateway: Gateway = new Gateway();
  private scroller: Scroller = new Scroller();
  private modelOptions: SelectOption[] = MODELS.map((m: ModelInfo): SelectOption => {
    const option: SelectOption = { value: m.label };
    return option;
  });

  aboutToAppear(): void {
    store.init(getContext(this) as common.UIAbilityContext);
    this.apiKey = store.getApiKey();
    this.baseUrl = store.getBaseUrl();
    this.model = store.getModel();
    this.draftKey = this.apiKey;
    this.draftUrl = this.baseUrl;
    if (this.apiKey.length === 0) {
      this.showSettings = true;
    }
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

    this.gateway.stream(this.baseUrl, this.apiKey, this.model, history, handlers);
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
        Text('SCNet Lite').fontSize(18).fontWeight(FontWeight.Medium).layoutWeight(1)
        Text(modelLabel(this.model)).fontSize(12).fontColor('#6B7280')
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
