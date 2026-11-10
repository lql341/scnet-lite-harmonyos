import { common } from '@kit.AbilityKit';
import { router } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Gateway, ChatMessage, StreamHandlers } from '../service/Gateway';
import { store, DEFAULT_BASE_URL, DEFAULT_MODEL } from '../service/Store';
import { auth } from '../service/Auth';
import { apiKeys, GatewayAccess } from '../service/ApiKeys';
import { sessions, SessionData, SessionMeta, StoredMessage, titleFrom } from '../service/Sessions';
import { agentChat } from '../service/AgentChat';
import { uploader, UploadedFile } from '../service/Upload';
import { picker } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { AgentService, KIND_AGENT, PickItem, agentItems, llmItems } from '../model/Pick';
import { Conversation, ChatConfig, UserInfo, HistoryPage, HistoryMessage } from '../model/Types';
import { Theme, prettyModel, safe } from '../common/Theme';
import { L } from '../common/I18n';
import { ChatTurn, TrimResult, trimHistory } from '../common/Chat';
import { pasteboard } from '@kit.BasicServicesKit';
import { MarkdownView } from '../view/MarkdownView';
import { ModelSheet } from '../view/ModelSheet';
import { ScenarioSheet } from '../view/ScenarioSheet';
import { Avatar } from '../view/Avatar';
import { scenarios, ScenarioCategory, ScenarioItem } from '../service/Scenarios';
import { scenes, SceneBoard, SceneTab, AdItem } from '../service/Scenes';

const TAG: string = 'SCNetLite';

/** LazyForEach 数据源：长会话只渲染可视区的消息。 */
class MsgSource implements IDataSource {
  private items: RenderMsg[] = [];
  private listeners: DataChangeListener[] = [];

  totalCount(): number {
    return this.items.length;
  }

  getData(index: number): RenderMsg {
    return this.items[index];
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener);
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const idx: number = this.listeners.indexOf(listener);
    if (idx >= 0) {
      this.listeners.splice(idx, 1);
    }
  }

  /** 整体替换（追加消息用 pushOne 更省）。 */
  reset(items: RenderMsg[]): void {
    this.items = items;
    for (let i = 0; i < this.listeners.length; i++) {
      this.listeners[i].onDataReloaded();
    }
  }

  pushOne(item: RenderMsg): void {
    const index: number = this.items.length;
    this.items.push(item);
    for (let i = 0; i < this.listeners.length; i++) {
      this.listeners[i].onDataAdd(index);
    }
  }

  snapshot(): RenderMsg[] {
    return this.items;
  }
}

interface RenderMsg {
  role: string;
  content: string;
  /** 该条回答实际走的通道（多通道并存后必须逐条记） */
  via?: string;
}

function msg(role: string, content: string): RenderMsg {
  const item: RenderMsg = { role: role, content: content, via: '' };
  return item;
}

function msgVia(role: string, content: string, via: string): RenderMsg {
  const item: RenderMsg = { role: role, content: content, via: via };
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
  private msgSource: MsgSource = new MsgSource();
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
  @State localSessions: SessionMeta[] = [];
  @State currentSessionId: string = '';
  @State gatewayModels: string[] = [];
  @State agentServices: AgentService[] = [];
  @State pickItems: PickItem[] = [];
  /** 'agent' = 平台智能体服务，'llm' = 网关模型 */
  @State channel: string = 'agent';
  @State agentKey: string = 'aiagent-router';
  @State agentModelId: number = 0;
  @State agentName: string = '';
  @State sessionTitle: string = '';
  /** 待发送的附件（已上传到 OSS，拿到平台 fileName） */
  @State attachments: UploadedFile[] = [];
  @State uploading: boolean = false;
  /** 中性提示（附件就绪等），与红色错误分开 */
  @State notice: string = '';
  /** 智能体通道的平台会话 id（新对话时清空） */
  @State agentConversationId: string = '';
  /** 本次请求用的通道名，流结束时写进消息 */
  private pendingVia: string = '';
  @State conversations: Conversation[] = [];
  @State drawerOpen: boolean = false;
  @State apiKey: string = '';
  @State baseUrl: string = DEFAULT_BASE_URL;
  @State gatewayModel: string = DEFAULT_MODEL;
  @State draftKey: string = '';
  @State draftUrl: string = DEFAULT_BASE_URL;
  @State showModelSheet: boolean = false;
  @State scenarioCategories: ScenarioCategory[] = [];
  @State scenarioCategory: string = 'science';
  @State scenarioItems: ScenarioItem[] = [];
  @State showScenarioSheet: boolean = false;
  /** 服务端场景分类（桌面端算法：featured + vibeCodingScenes 按 question.scene 过滤） */
  @State sceneTabs: SceneTab[] = [];
  @State sceneTabId: string = 'featured';
  @State sceneQuestions: string[] = [];
  @State sceneOffset: number = 0;
  /** 首页 banner（平台推荐位，config/list.recommendAD） */
  @State ads: AdItem[] = [];
  @State avatar: string = '';
  /** 重命名弹层：target 为 'local' 或 'cloud' */
  @State renameTarget: string = '';
  @State renameId: string = '';
  @State renameDraft: string = '';
  /** 本次请求被裁掉的历史条数（>0 时提示用户） */
  private trimmedCount: number = 0;
  @State showRename: boolean = false;
  /** 订阅主题版本：换主题后本页重建，读到新的 Theme 颜色 */
  @StorageLink('themeVersion') themeVersion: number = 0;
  /** 外观（主题/字号/语言）版本：变化时整棵子树重建，静态色值与字号才会重算 */
  @StorageProp('themeRev') themeRev: number = 0;

  private gateway: Gateway = new Gateway();
  private scroller: Scroller = new Scroller();

  onPageShow(): void {
    // 从设置页返回时刷新头像（顶栏与抽屉共用 this.avatar，改完要重新读一次）
    this.avatar = store.getAvatar();
    // 外观（深色/浅色）或配色可能在设置页改过：这里对比一次，
    // 不一致就 bumpRev 强制重建整棵树 —— 否则 Markdown 内容会保留旧文字色
    // （实测：深色切回浅色后，表格标题/正文变成近白，看不清）。
    const mode: string = store.getColorMode();
    // system 模式不在这里判断（系统切换由 onConfigurationUpdate 处理）
    const wantDark: boolean = mode === 'dark';
    const paletteChanged: boolean = Theme.paletteId !== store.getTheme();
    if ((mode !== 'system' && wantDark !== Theme.dark) || paletteChanged) {
      Theme.applyPalette(paletteChanged ? store.getTheme() : Theme.paletteId);
      Theme.applyDark(wantDark);
      Theme.bumpRev();
      hilog.info(0x0000, TAG, 'appearance changed on return: dark=%{public}s', String(wantDark));
    }
    // OCR 页「发送到对话」会把文字带回来
    const params = router.getParams() as Record<string, string> | undefined;
    if (params !== undefined && params !== null && params['prefill'] !== undefined) {
      this.input = params['prefill'];
    }
  }

  aboutToAppear(): void {
    store.init(getContext(this) as common.UIAbilityContext);
    if (!auth.isLoggedIn()) {
      // 原因已在 auth.loginReason 里（expired / unauthenticated），登录页会据此提示
      router.replaceUrl({ url: 'pages/Login' });
      return;
    }
    this.apiKey = store.getApiKey();
    this.baseUrl = store.getBaseUrl();
    this.gatewayModel = store.getModel();
    this.channel = store.getChannel();
    this.agentKey = store.getAgent();
    this.avatar = store.getAvatar();
    this.draftKey = this.apiKey;
    this.draftUrl = this.baseUrl;
    const context = getContext(this) as common.UIAbilityContext;
    sessions.init(context);
    scenarios.load(context.resourceManager).then(() => {
      this.scenarioCategories = scenarios.list();
      if (this.scenarioCategories.length > 0) {
        this.scenarioCategory = this.scenarioCategories[0].id;
        this.scenarioItems = scenarios.top(this.scenarioCategory, 3);
      }
    });
    this.localSessions = sessions.list();
    hilog.info(0x0000, TAG, 'sessions on start: %{public}d', this.localSessions.length);
    if (this.localSessions.length > 0) {
      this.openLocal(this.localSessions[0]);
    }
    this.loadCloud();
  }

  private async loadCloud(): Promise<void> {
    try {
      const me: UserInfo = await auth.refreshUser();
      this.userName = safe(me.fullName).length > 0 ? safe(me.fullName) : safe(me.userName);
      if (safe(me.userName).length > 0) {
        store.setPlatformUserName(safe(me.userName));
      }
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
      const services: AgentService[] = await auth.agentServices();
      this.agentServices = services;
      hilog.info(0x0000, TAG, 'agent services: %{public}d', services.length);
    } catch (e) {
      hilog.warn(0x0000, TAG, 'agent services failed');
    }
    try {
      this.gatewayAccess = await apiKeys.ensureAccess(await auth.clusterIdentity());
      if (this.gatewayAccess.key.length > 0) {
        this.apiKey = this.gatewayAccess.key;
        this.baseUrl = this.gatewayAccess.baseUrl;
        this.avatar = store.getAvatar();
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
    this.rebuildPickItems();
    this.applySelection();
    await this.loadScenes();
    await this.reloadConversations();
  }

  /** 把服务表与网关模型合成一张选择表（智能体在前）。 */
  private rebuildPickItems(): void {
    const merged: PickItem[] = agentItems(this.agentServices);
    const models: PickItem[] = llmItems(this.gatewayModels, prettyModel);
    for (let i = 0; i < models.length; i++) {
      merged.push(models[i]);
    }
    this.pickItems = merged;
    hilog.debug(0x0000, TAG, 'pick items: agents=%{public}d llm=%{public}d',
      agentItems(this.agentServices).length, models.length);
  }

  /** 依据 channel/agentKey 找到当前选中项；找不到就退回两端各自默认。 */
  private applySelection(): void {
    let current: PickItem | null = null;
    for (let i = 0; i < this.pickItems.length; i++) {
      const item: PickItem = this.pickItems[i];
      if (item.kind === KIND_AGENT && item.key === this.agentKey && this.channel === 'agent') {
        current = item;
        break;
      }
      if (item.kind !== KIND_AGENT && item.key === this.gatewayModel && this.channel === 'llm') {
        current = item;
        break;
      }
    }
    if (current === null) {
      // 没选过：智能体优先（平台助手就是产品默认），否则回落到免费模型
      let agentDefault: PickItem | null = null;
      for (let i = 0; i < this.pickItems.length; i++) {
        if (this.pickItems[i].kind === KIND_AGENT) {
          agentDefault = this.pickItems[i];
          break;
        }
      }
      if (agentDefault !== null) {
        current = agentDefault;
        this.channel = 'agent';
      } else if (this.gatewayModels.length > 0) {
        this.channel = 'llm';
        this.gatewayModel = this.pickModel(this.gatewayModels, this.gatewayModel);
      }
    }
    if (current !== null) {
      this.applyPick(current);
    }
  }

  private applyPick(item: PickItem): void {
    if (item.kind === KIND_AGENT) {
      this.channel = 'agent';
      this.agentKey = item.key;
      this.agentModelId = item.modelId;
      this.agentName = item.label;
      store.setChannel('agent');
      store.setAgent(item.key);
    } else {
      this.channel = 'llm';
      this.gatewayModel = item.key;
      store.setChannel('llm');
      store.setModel(item.key);
    }
    hilog.debug(0x0000, TAG, 'channel=%{public}s key=%{public}s', this.channel, item.key);
  }

  /** 当前选中项的展示名（输入框左侧 chip）。 */
  private currentLabel(): string {
    if (this.channel === 'agent') {
      return this.agentName.length > 0 ? this.agentName : '智能体服务';
    }
    return prettyModel(this.gatewayModel);
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

  /** 选附件：系统文件选择器 → 上传到 OSS → 变成待发送的 chip。 */
  @State showAttachSheet: boolean = false;

  /**
   * 选附件：统一走文件选择器，并把图片后缀也放进过滤条件 ——
   * 分「图片/文件」两个入口对用户没意义（实测两者都能上传），合并。
   */
  private async pickAttachmentAny(): Promise<void> {
    this.showAttachSheet = false;
    if (this.uploading) {
      return;
    }
    let uris: string[] = [];
    try {
      const options = new picker.DocumentSelectOptions();
      options.maxSelectNumber = 3;
      options.fileSuffixFilters = [
        '全部常用 (.pdf, .doc, .docx, .xls, .xlsx, .ppt, .pptx, .png, .jpg, .jpeg)|' +
          '.pdf,.doc,.docx,.xls,.xlsx,.ppt,.pptx,.png,.jpg,.jpeg,.webp,.gif,.bmp',
        '文档 (.pdf, .doc, .docx)|.pdf,.doc,.docx',
        '表格 (.xls, .xlsx, .csv, .tsv)|.xls,.xlsx,.csv,.tsv',
        '演示 (.ppt, .pptx)|.ppt,.pptx',
        '文本 (.txt, .md, .json, .log, .xml, .yaml)|.txt,.md,.markdown,.json,.log,.xml,.yaml,.yml',
        '代码 (.py, .js, .ts, .sh, .c, .h, .cpp, .rs, .go, .java, .f90, .inp)|' +
          '.py,.js,.ts,.sh,.c,.h,.cpp,.hpp,.rs,.go,.java,.f90,.f,.inp',
        '图片 (.png, .jpg, .jpeg, .webp, .gif, .bmp)|.png,.jpg,.jpeg,.webp,.gif,.bmp',
        '压缩包 (.zip, .tar, .gz)|.zip,.tar,.gz'
      ];
      const documentPicker = new picker.DocumentViewPicker();
      uris = await documentPicker.select(options);
    } catch (e) {
      const err = e as BusinessError;
      hilog.warn(0x0000, TAG, 'document picker failed code=%{public}s', String(err.code ?? '?'));
      this.errorMsg = L.t(`选择失败(${err.code ?? '?'})`, `Picker failed (${err.code ?? '?'})`);
      return;
    }
    await this.uploadUris(uris);
  }

  /** 从相册选图片（保留给"只想要相册"的场景，目前未挂 UI）。 */
  private async pickImage(): Promise<void> {
    this.showAttachSheet = false;
    if (this.uploading) {
      return;
    }
    let uris: string[] = [];
    try {
      const options = new photoAccessHelper.PhotoSelectOptions();
      options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      options.maxSelectNumber = 3;
      const photoPicker = new photoAccessHelper.PhotoViewPicker();
      const result: photoAccessHelper.PhotoSelectResult = await photoPicker.select(options);
      uris = result.photoUris;
    } catch (e) {
      const err = e as BusinessError;
      hilog.warn(0x0000, TAG, 'photo picker failed code=%{public}s', String(err.code ?? '?'));
      this.errorMsg = L.t(`相册选择失败(${err.code ?? '?'})`, `Photo picker failed (${err.code ?? '?'})`);
      return;
    }
    await this.uploadUris(uris);
  }

  /** 从文件管理器选文件（csv/pdf/docx 等）。 */
  private async pickFile(): Promise<void> {
    this.showAttachSheet = false;
    if (this.uploading) {
      return;
    }
    let uris: string[] = [];
    try {
      const options = new picker.DocumentSelectOptions();
      options.maxSelectNumber = 3;
      // 常见办公/科研文档 + 文本 + 压缩包（不限死，未识别的类型也能传，由服务端判定）
      options.fileSuffixFilters = [
        '文档 (.pdf, .doc, .docx)|.pdf,.doc,.docx',
        '表格 (.xls, .xlsx, .csv, .tsv)|.xls,.xlsx,.csv,.tsv',
        '演示 (.ppt, .pptx)|.ppt,.pptx',
        '文本 (.txt, .md, .json, .log, .xml, .yaml)|.txt,.md,.markdown,.json,.log,.xml,.yaml,.yml',
        '代码 (.py, .js, .ts, .sh, .c, .h, .cpp, .rs, .go, .java, .f90, .inp)|.py,.js,.ts,.sh,.c,.h,.cpp,.hpp,.rs,.go,.java,.f90,.f,.inp',
        '图片 (.png, .jpg, .jpeg, .webp, .gif, .bmp)|.png,.jpg,.jpeg,.webp,.gif,.bmp',
        '压缩包 (.zip, .tar, .gz)|.zip,.tar,.gz'
      ];
      const documentPicker = new picker.DocumentViewPicker();
      uris = await documentPicker.select(options);
    } catch (e) {
      const err = e as BusinessError;
      hilog.warn(0x0000, TAG, 'document picker failed code=%{public}s', String(err.code ?? '?'));
      this.errorMsg = L.t(`文件选择失败(${err.code ?? '?'})`, `File picker failed (${err.code ?? '?'})`);
      return;
    }
    await this.uploadUris(uris);
  }

  private async uploadUris(uris: string[]): Promise<void> {
    if (uris.length === 0) {
      return;
    }
    this.uploading = true;
    this.errorMsg = '';
    let ok: number = 0;
    for (let i = 0; i < uris.length; i++) {
      const uri: string = uris[i];
      const slash: number = uri.lastIndexOf('/');
      let name: string = slash >= 0 ? uri.substring(slash + 1) : `file-${i}`;
      if (name.indexOf('?') >= 0) {
        name = name.substring(0, name.indexOf('?'));
      }
      if (name.indexOf('.') < 0) {
        name = `${name}.dat`;
      }
      const uploaded: UploadedFile | null = await uploader.uploadFile(uri, name);
      if (uploaded !== null) {
        this.attachments = this.attachments.concat([uploaded]);
        ok++;
      } else {
        // 直接展示底层原因（0 字节 / 权限 / OSS 状态码），不要只写"上传失败"
        this.errorMsg = uploader.lastError.length > 0
          ? uploader.lastError
          : L.t(`附件上传失败：${name}`, `Upload failed: ${name}`);
        hilog.warn(0x0000, TAG, 'attach failed: %{public}s', this.errorMsg);
      }
    }
    this.uploading = false;
    if (ok > 0) {
      this.notice = L.t(`已添加 ${ok} 个附件`, `${ok} attachment(s) added`);
    }
  }

  private removeAttachment(name: string): void {
    this.attachments = this.attachments.filter((item: UploadedFile) => item.name !== name);
  }

  /** 长按 ＋ 走一次上传自检（诊断用）。 */
  private async runUploadSelfTest(): Promise<void> {
    this.errorMsg = '';
    this.notice = L.t('正在上传测试附件…', 'Uploading test file…');
    const result: UploadedFile | null = await uploader.selfTest();
    if (result === null) {
      hilog.warn(0x0000, TAG, 'upload selftest failed');
      this.notice = '';
      this.errorMsg = L.t('附件上传失败，请重试', 'Upload failed, please retry');
      return;
    }
    // 顺手挂成待发送附件，这样能直接验证「附件 → 智能体读到」的完整路径
    this.attachments = this.attachments.concat([result]);
    hilog.info(0x0000, TAG, 'upload selftest ok: %{public}s', result.name);
    this.errorMsg = '';
    this.notice = L.t(`附件已就绪：${result.localName}`, `Attached: ${result.localName}`);
  }

  /** 选场景：把预置 prompt 填进输入框并直接发送（与桌面端行为一致）。 */
  private pickScenario(item: ScenarioItem): void {
    this.showScenarioSheet = false;
    this.errorMsg = '';
    if (item.prompt.length === 0) {
      this.input = item.title;
      return;
    }
    this.input = item.prompt;
    if (item.inputCount > 0 && this.attachments.length === 0) {
      // 场景需要附件（如 standard-doe.csv）。没附件时直接发会让 agent 干等文件，
      // 所以先把指令填进输入框，并提示用户点 ＋ 选文件。
      this.errorMsg = L.t(
        `「${item.title}」需要 ${item.inputCount} 个附件，请点 ＋ 选择文件后再发送`,
        `"${item.title}" needs ${item.inputCount} attachment(s). Tap + to pick files first.`);
      return;
    }
    this.send();
  }

  private switchScenarioCategory(id: string): void {
    this.scenarioCategory = id;
    this.scenarioItems = scenarios.top(id, 3);
  }

  private rotateScenarios(): void {
    const all: ScenarioItem[] = scenarios.rotate(this.scenarioCategory, 3, Date.now() % 7);
    if (all.length > 0) {
      this.scenarioItems = all;
    }
  }

  /** 打开本地会话。 */
  private openLocal(meta: SessionMeta): void {
    const data: SessionData | null = sessions.load(meta.id);
    if (data === null) {
      return;
    }
    const restored: RenderMsg[] = [];
    for (let i = 0; i < data.messages.length; i++) {
      const item: StoredMessage = data.messages[i];
      restored.push(msgVia(item.role, item.content, item.via ?? ''));
    }
    this.messages = restored;
    this.msgSource.reset(restored);
    this.currentSessionId = data.id;
    this.sessionTitle = data.title;
    this.currentCloudId = '';
    this.errorMsg = '';
    this.drawerOpen = false;
    setTimeout(() => this.scrollToEnd(), 80);
  }

  /** 把当前 messages 落盘（首条消息时顺便起标题）。 */
  private persistSession(): void {
    if (this.messages.length === 0) {
      return;
    }
    const stored: StoredMessage[] = this.messages.map((m: RenderMsg): StoredMessage => {
      const item: StoredMessage = { role: m.role, content: m.content, via: m.via ?? '' };
      return item;
    });
    if (this.currentSessionId.length === 0) {
      this.currentSessionId = sessions.newId();
    }
    const data: SessionData = {
      id: this.currentSessionId,
      title: this.sessionTitle.length > 0 ? this.sessionTitle : titleFrom(stored),
      model: this.gatewayModel,
      createdAt: Date.now(),
      updatedAt: Date.now(),
      messages: stored
    };
    sessions.save(data);
    this.localSessions = sessions.list();
    hilog.debug(0x0000, TAG, 'session saved msgs=%{public}d list=%{public}d',
      stored.length, this.localSessions.length);
  }

  private removeLocal(meta: SessionMeta): void {
    sessions.remove(meta.id);
    if (meta.id === this.currentSessionId) {
      this.messages = [];
      this.msgSource.reset([]);
      this.currentSessionId = '';
    }
    this.localSessions = sessions.list();
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
      this.msgSource.reset(rendered);
      this.currentCloudId = id;
      setTimeout(() => this.scrollToEnd(), 80);
    } catch (e) {
      this.errorMsg = '加载会话历史失败';
    }
  }

  /** 拉服务端场景分类；拿不到就回落到本地场景目录。 */
  private async loadScenes(): Promise<void> {
    const board: SceneBoard = await scenes.load();
    this.ads = board.ads;
    this.sceneTabs = board.tabs;
    if (board.tabs.length > 0) {
      this.sceneTabId = board.tabs[0].id;
      this.sceneQuestions = board.tabs[0].questions;
      this.sceneOffset = 0;
    }
  }

  private pickSceneTab(id: string): void {
    this.sceneTabId = id;
    for (let i = 0; i < this.sceneTabs.length; i++) {
      if (this.sceneTabs[i].id === id) {
        this.sceneQuestions = this.sceneTabs[i].questions;
        break;
      }
    }
    this.sceneOffset = 0;
  }

  private shuffleScenes(): void {
    if (this.sceneQuestions.length <= 3) {
      return;
    }
    this.sceneOffset = (this.sceneOffset + 3) % this.sceneQuestions.length;
  }

  /** 当前展示的 3 条问题（循环轮转）。 */
  private visibleQuestions(): string[] {
    const out: string[] = [];
    const total: number = this.sceneQuestions.length;
    if (total === 0) {
      return out;
    }
    for (let i = 0; i < 3 && i < total; i++) {
      out.push(this.sceneQuestions[(this.sceneOffset + i) % total]);
    }
    return out;
  }

  private async reloadConversations(): Promise<void> {
    try {
      const page = await auth.conversationList();
      this.conversations = page.records ?? [];
    } catch (e) {
      hilog.warn(0x0000, TAG, 'conversation list failed');
    }
  }

  /** 点消息区时收起软键盘（TextArea 不会因为点别处自动失焦）。 */
  private hideKeyboard(): void {
    try {
      this.getUIContext().getFocusController().clearFocus();
    } catch (e) {
      // 低版本没有这个 API，忽略
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
      this.messages = this.messages.concat([msgVia('assistant', this.streaming, this.pendingVia)]);
    this.msgSource.pushOne(msgVia('assistant', this.streaming, this.pendingVia));
    }
    this.streaming = '';
    this.progressText = '';
    this.busy = false;
    this.agentConversationId = agentChat.conversationId;
    this.persistSession();
    setTimeout(() => this.scrollToEnd(), 50);
  }

  private send(): void {
    const text: string = this.input.trim();
    if (text.length === 0 || this.busy) {
      return;
    }
    this.errorMsg = '';
    this.notice = '';
    this.input = '';
    this.streaming = '';
    this.progressText = '';
    this.busy = true;
    this.currentCloudId = '';
    this.pendingVia = this.currentLabel();
    this.messages = this.messages.concat([msg('user', text)]);
    this.msgSource.pushOne(msg('user', text));
    this.persistSession();
    this.scrollToEnd();

    this.sessionTitle = '';
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
        // 智能体通道会用服务端生成的标题，本地会话跟着改
        this.sessionTitle = title;
        this.persistSession();
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

    const history: ChatMessage[] = this.buildHistory(this.messages);

    if (this.trimmedCount > 0) {
      this.notice = L.t(`上下文较长，已省略最近 ${this.trimmedCount} 条之前的历史`,
        `Long context: omitted history before the last ${this.trimmedCount} messages`);
    }
    // 自定义 provider：走 OpenAI 兼容端点，模型/baseUrl/key 全部来自用户配置
    if (store.getModelProvider() === 'custom' && store.getCustomBaseUrl().length > 0) {
      const customModel: string = store.getCustomModel();
      this.gateway.stream(store.getCustomBaseUrl(), store.getCustomApiKey(),
        customModel.length > 0 ? customModel : 'gpt-4o-mini', history, handlers);
      return;
    }
    if (this.channel === 'agent' && this.agentModelId > 0) {
      agentChat.conversationId = this.agentConversationId;
      agentChat.stream(this.agentModelId, text, this.attachments, handlers);
      this.attachments = [];
    } else if (this.apiKey.length > 0) {
      this.gateway.stream(this.baseUrl, this.apiKey, this.gatewayModel, history, handlers);
    } else {
      this.errorMsg = this.gatewayNotice.length > 0 ? this.gatewayNotice : '没有可用通道，请重新登录';
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
    this.msgSource.reset([]);
    this.streaming = '';
    this.errorMsg = '';
    this.currentCloudId = '';
    this.currentSessionId = '';
    this.agentConversationId = '';
    this.sessionTitle = '';
    agentChat.conversationId = '';
    agentChat.lastTitle = '';
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
  avatarBox(boxSize: number, fontSize: number) {
    Avatar({
      avatarSize: boxSize,
      fontSize: fontSize,
      name: this.userName,
      avatar: this.avatar,
      onTap: () => {
        this.openProfile();
      }
    })
  }

  private openProfile(): void {
    this.drawerOpen = false;
    router.pushUrl({ url: 'pages/Profile' }).catch((err: Error) => {
      hilog.warn(0x0000, TAG, 'open profile failed: %{public}s', err.message);
    });
  }

  @Builder
  topBar() {
    Row({ space: 12 }) {
      this.iconButton('☰', () => {
        this.drawerOpen = true;
      })

      Column({ space: 1 }) {
        Text(L.t('超级计算智能体', 'SCNet Supercomputing'))
          .fontSize(Theme.fTitle)
          .fontWeight(FontWeight.Medium)
          .fontFamily(Theme.fontDisplay)
          .fontColor(Theme.text)
        Row({ space: 4 }) {
          Column()
            .width(5)
            .height(5)
            .borderRadius(3)
            .backgroundColor(store.getModelProvider() === 'custom'
              ? (store.getCustomBaseUrl().length > 0 ? Theme.ok : Theme.danger)
              : (this.apiKey.length > 0 ? Theme.ok : Theme.textFaint))
          Text(store.getModelProvider() === 'custom'
            ? L.t(`自定义 · ${store.getCustomName().length > 0 ? store.getCustomName() : '未配置'}`,
              `Custom · ${store.getCustomName().length > 0 ? store.getCustomName() : 'unset'}`)
            : (this.apiKey.length > 0 ? L.t('网关已就绪', 'Gateway ready') : L.t('未就绪', 'Not ready')))
            .fontSize(10)
            .fontColor(Theme.textFaint)
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      this.avatarBox(32, 13)
    }
    .width('100%')
    .height(56)
    .padding({ left: 14, right: 14 })
    .backgroundColor(Theme.bg)
  }

  // ---------------------------------------------------------------- 消息
  @Builder
  assistantBubble(content: string, isStreaming: boolean, via: string) {
    Column({ space: 5 }) {
      // 元信息行：模型名 · AI，比一个看不清的小圆标更实用
      Row({ space: 5 }) {
        Text(via.length > 0 ? via : this.currentLabel())
          .fontSize(10)
          .fontColor(Theme.textFaint)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (isStreaming) {
          Column().width(4).height(4).borderRadius(2).backgroundColor(Theme.ok)
          Text('生成中').fontSize(10).fontColor(Theme.ok)
        }
      }
      .padding({ left: 4 })

      Column() {
        MarkdownView({ content: content, streaming: isStreaming, rev: this.themeRev })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding({ left: 2, right: 2, top: 2, bottom: 2 })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ top: 6, bottom: 10 })
    .bindContextMenu(this.messageMenu(content), ResponseType.LongPress)
  }

  @Builder
  userBubble(content: string) {
    Row() {
      Text(content)
        .fontSize(Theme.fBody)
        .lineHeight(24)
        .fontColor(Theme.text)
        .padding({ left: 14, right: 14, top: 10, bottom: 10 })
        .backgroundColor(Theme.surfaceAlt)
        .borderRadius({ topLeft: Theme.rXl, topRight: Theme.rXl, bottomLeft: Theme.rXl, bottomRight: 6 })
        .constraintSize({ maxWidth: '82%' })
    }
    .width('100%')
    .justifyContent(FlexAlign.End)
    .padding({ top: 5, bottom: 5 })
    .bindContextMenu(this.messageMenu(content), ResponseType.LongPress)
  }

  @Builder
  thinking() {
    Column({ space: 5 }) {
      Text(prettyModel(this.gatewayModel))
        .fontSize(10)
        .fontColor(Theme.textFaint)
        .padding({ left: 4 })
      Row({ space: 8 }) {
        LoadingProgress().width(18).height(18).color(Theme.accent)
        Text(this.progressText.length > 0 ? this.progressText : '正在生成…')
          .fontSize(Theme.fSmall)
          .fontColor(Theme.textFaint)
      }
      .padding({ left: 2, right: 16, top: 4, bottom: 4 })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ top: 8, bottom: 4 })
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
    Scroll() {
      Column() {
        Column({ space: 10 }) {
          Image($r('app.media.app_icon'))
            .width(68)
            .height(68)
            .borderRadius(19)
            .objectFit(ImageFit.Cover)
            .shadow({ radius: 18, color: '#0B1F3322', offsetY: 6 })
          Text(L.t('你好，我是超级计算智能体', 'Hi, I am your SCNet agent'))
            .fontSize(24)
            .fontWeight(FontWeight.Normal)
            .fontFamily(Theme.fontDisplay)
            .fontColor(Theme.text)
            .margin({ top: 6 })
          Text(L.t('作业调度、模型训练、数据分析，说一声就开始',
            'Job scheduling, training, data analysis — just ask'))
            .fontSize(Theme.fSmall)
            .fontColor(Theme.textFaint)
            .textAlign(TextAlign.Center)
        }
        .padding({ top: 12, bottom: 18 })

        // AI 生成风险提示（主窗口常驻，不只藏在输入框下）
        Row({ space: 6 }) {
          Text('ⓘ').fontSize(10).fontColor(Theme.textFaint)
          Text(L.t('AI 生成内容可能不准确或有遗漏，涉及计算、作业与法律医学等结论请自行核实',
            'AI output may be inaccurate; verify before relying on it'))
            .fontSize(10)
            .lineHeight(15)
            .fontColor(Theme.textFaint)
            .layoutWeight(1)
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 8, bottom: 8 })
        .margin({ bottom: 12 })
        .backgroundColor(Theme.surfaceAlt)
        .borderRadius(Theme.rSm)

        if (this.scenarioCategories.length > 0) {
          // 7 类场景目录（同步自桌面客户端 home-scenarios）
          Scroll() {
            Row({ space: 8 }) {
              ForEach(this.scenarioCategories, (category: ScenarioCategory) => {
                Text(category.title)
                  .fontSize(Theme.fSmall)
                  .fontColor(category.id === this.scenarioCategory ? Theme.textOnAccent : Theme.textSub)
                  .padding({ left: 12, right: 12, top: 7, bottom: 7 })
                  .backgroundColor(category.id === this.scenarioCategory ? Theme.accent : Theme.surface)
                  .borderRadius(Theme.rPill)
                  .border({
                    width: 1,
                    color: category.id === this.scenarioCategory ? Theme.accent : Theme.hairline
                  })
                  .onClick(() => {
                    this.switchScenarioCategory(category.id);
                  })
              }, (category: ScenarioCategory) => category.id)
            }
            .padding({ left: 2, right: 2 })
          }
          .scrollable(ScrollDirection.Horizontal)
          .scrollBar(BarState.Off)
          .width('100%')
          .margin({ top: 2, bottom: 10 })

          Column({ space: 8 }) {
            ForEach(this.scenarioItems, (item: ScenarioItem) => {
              Row({ space: 10 }) {
                Column({ space: 3 }) {
                  Text(item.title)
                    .fontSize(Theme.fSmall)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(Theme.text)
                    .maxLines(2)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(item.summary)
                    .fontSize(Theme.fTiny)
                    .fontColor(Theme.textFaint)
                    .lineHeight(17)
                    .maxLines(2)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)
                if (item.inputCount > 0) {
                  Text(`附件 ${item.inputCount}`)
                    .fontSize(9)
                    .fontColor(Theme.warn)
                    .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                    .backgroundColor('#FFF4E5')
                    .borderRadius(5)
                }
                Text('›').fontSize(16).fontColor(Theme.textFaint)
              }
              .width('100%')
              .alignItems(VerticalAlign.Center)
              .padding({ left: 14, right: 12, top: 11, bottom: 11 })
              .backgroundColor(Theme.surface)
              .borderRadius(Theme.rMd)
              .border({ width: 1, color: Theme.hairline })
              .onClick(() => {
                this.pickScenario(item);
              })
            }, (item: ScenarioItem) => item.id)
          }
          .width('100%')

          Row({ space: 14 }) {
            Text(L.t('换一批', 'Shuffle'))
              .fontSize(Theme.fTiny)
              .fontColor(Theme.accent)
              .onClick(() => {
                this.rotateScenarios();
              })
            Text(L.t('更多场景', 'More scenes'))
              .fontSize(Theme.fTiny)
              .fontColor(Theme.textFaint)
              .onClick(() => {
                this.showScenarioSheet = true;
              })
            Blank().layoutWeight(1)
          }
          .width('100%')
          .padding({ top: 12, left: 4 })
        } else if (this.sceneTabs.length > 0) {
          Scroll() {
            Row({ space: 8 }) {
              ForEach(this.sceneTabs, (tab: SceneTab) => {
                Text(tab.title)
                  .fontSize(Theme.fSmall)
                  .fontColor(tab.id === this.sceneTabId ? Theme.textOnAccent : Theme.textSub)
                  .padding({ left: 12, right: 12, top: 7, bottom: 7 })
                  .backgroundColor(tab.id === this.sceneTabId ? Theme.accent : Theme.surface)
                  .borderRadius(Theme.rPill)
                  .border({ width: 1, color: tab.id === this.sceneTabId ? Theme.accent : Theme.hairline })
                  .onClick(() => {
                    this.pickSceneTab(tab.id);
                  })
              }, (tab: SceneTab) => tab.id)
            }
            .padding({ left: 2, right: 2 })
          }
          .scrollable(ScrollDirection.Horizontal)
          .scrollBar(BarState.Off)
          .width('100%')
          .margin({ top: 2, bottom: 10 })

          Column({ space: 8 }) {
            ForEach(this.visibleQuestions(), (question: string) => {
              Row({ space: 10 }) {
                Text(question)
                  .fontSize(Theme.fSmall)
                  .lineHeight(19)
                  .fontColor(Theme.textSub)
                  .maxLines(2)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .layoutWeight(1)
                Text('›').fontSize(16).fontColor(Theme.textFaint)
              }
              .width('100%')
              .alignItems(VerticalAlign.Center)
              .padding({ left: 14, right: 12, top: 10, bottom: 10 })
              .backgroundColor(Theme.surface)
              .borderRadius(Theme.rMd)
              .border({ width: 1, color: Theme.hairline })
              .onClick(() => {
                this.input = question;
                this.send();
              })
            }, (question: string) => question)
          }
          .width('100%')

          Row({ space: 14 }) {
            Text(L.t('换一批', 'Shuffle'))
              .fontSize(Theme.fTiny)
              .fontColor(Theme.accent)
              .onClick(() => {
                this.shuffleScenes();
              })
            Blank().layoutWeight(1)
          }
          .width('100%')
          .padding({ top: 12, left: 4 })
        } else {
          Column({ space: 8 }) {
            ForEach(this.suggest, (item: string, index: number) => {
              Row({ space: 10 }) {
                Text(`${index + 1}`)
                  .fontSize(10)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(Theme.accent)
                  .width(18)
                  .height(18)
                  .textAlign(TextAlign.Center)
                  .borderRadius(9)
                  .backgroundColor(Theme.accentGhost)
                Text(item)
                  .fontSize(Theme.fSmall)
                  .lineHeight(19)
                  .fontColor(Theme.textSub)
                  .maxLines(2)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .layoutWeight(1)
                Text('›').fontSize(16).fontColor(Theme.textFaint)
              }
              .width('100%')
              .alignItems(VerticalAlign.Center)
              .padding({ left: 14, right: 12, top: 10, bottom: 10 })
              .backgroundColor(Theme.surface)
              .borderRadius(Theme.rMd)
              .border({ width: 1, color: Theme.hairline })
              .onClick(() => {
                this.input = item;
                this.send();
              })
            }, (item: string, index: number) => `${index}-${item}`)
          }
          .width('100%')
        }
      }
      .width('100%')
      .padding({ left: 18, right: 18, top: 4, bottom: 20 })
    }
    .layoutWeight(1)
    .width('100%')
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .align(Alignment.Top)
  }

  @Builder
  composer() {
    Column() {
      Column() {
        if (this.attachments.length > 0 || this.uploading) {
          Scroll() {
            Row({ space: 8 }) {
              if (this.uploading) {
                Row({ space: 6 }) {
                  LoadingProgress().width(12).height(12).color(Theme.accent)
                  Text(L.t('上传中…', 'Uploading…'))
                    .fontSize(Theme.fTiny)
                    .fontColor(Theme.textFaint)
                }
                .padding({ left: 10, right: 10, top: 6, bottom: 6 })
                .backgroundColor(Theme.surfaceAlt)
                .borderRadius(Theme.rPill)
              }
              ForEach(this.attachments, (file: UploadedFile) => {
                Row({ space: 6 }) {
                  Text(file.localName)
                    .fontSize(Theme.fTiny)
                    .fontColor(Theme.textSub)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .constraintSize({ maxWidth: 150 })
                  Text('✕')
                    .fontSize(10)
                    .fontColor(Theme.textFaint)
                    .onClick(() => {
                      this.removeAttachment(file.name);
                    })
                }
                .padding({ left: 10, right: 10, top: 6, bottom: 6 })
                .backgroundColor(Theme.accentGhost)
                .borderRadius(Theme.rPill)
                .border({ width: 1, color: Theme.accentSoft })
              }, (file: UploadedFile) => file.name)
            }
            .padding({ left: 12, right: 12, top: 10 })
          }
          .scrollable(ScrollDirection.Horizontal)
          .scrollBar(BarState.Off)
          .width('100%')
        }

        TextArea({ text: this.input, placeholder: L.t('发消息…', 'Message…') })
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
          Text(this.uploading ? '…' : '＋')
            .fontSize(17)
            .fontColor(Theme.textSub)
            .width(28)
            .height(28)
            .textAlign(TextAlign.Center)
            .borderRadius(14)
            .backgroundColor(Theme.surfaceAlt)
            .onClick(() => {
              this.showAttachSheet = true;
            })
            .gesture(LongPressGesture({ repeat: false }).onAction(() => {
              this.runUploadSelfTest();
            }))

          Row({ space: 4 }) {
            Text(L.t('场景', 'Scenes'))
              .fontSize(Theme.fTiny)
              .fontColor(Theme.textSub)
            Text('▸').fontSize(9).fontColor(Theme.textFaint)
          }
          .padding({ left: 10, right: 10, top: 5, bottom: 5 })
          .backgroundColor(Theme.surfaceAlt)
          .borderRadius(Theme.rPill)
          .onClick(() => {
            this.showScenarioSheet = true;
          })

          Row({ space: 5 }) {
            Text(this.currentLabel())
              .fontSize(Theme.fTiny)
              .fontColor(Theme.accent)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .constraintSize({ maxWidth: 150 })
            Text('▾').fontSize(10).fontColor(Theme.accent)
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
              // 智能体通道必须显式 stop，否则服务端任务还在跑
              if (this.channel === 'agent') {
                agentChat.stop(this.agentModelId);
                agentChat.cancel();
              } else {
                this.gateway.cancel();
              }
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
              .backgroundColor(Theme.accent)
              .opacity(this.input.trim().length > 0 ? 1 : 0.34)
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

      Text(L.t('内容由 AI 生成，请自行核对', 'AI-generated · please verify'))
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
  /** 会话状态中文 + 日期（createTime 形如 2026-11-09 12:00:16）。 */
  private statusText(item: Conversation): string {
    const status: string = safe(item.taskStatus);
    let label: string = '历史';
    if (status === 'completed') {
      label = '已完成';
    } else if (status === 'running') {
      label = '进行中';
    } else if (status.length > 0) {
      label = status;
    }
    const time: string = safe(item.createTime);
    if (time.length >= 10) {
      return `${label} · ${time.substring(5, 10)}`;
    }
    return label;
  }

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
      Text(this.statusText(item))
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
  localItem(meta: SessionMeta) {
    Row({ space: 6 }) {
      Column({ space: 3 }) {
        Text(meta.title.length > 0 ? meta.title : '新对话')
          .fontSize(Theme.fSmall)
          .fontColor(meta.id === this.currentSessionId ? Theme.accent : Theme.text)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(`${meta.count} 条 · ${prettyModel(meta.model)}`)
          .fontSize(10)
          .fontColor(Theme.textFaint)
          .maxLines(1)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Text('✕')
        .fontSize(11)
        .fontColor(Theme.textFaint)
        .width(22)
        .height(22)
        .textAlign(TextAlign.Center)
        .borderRadius(11)
        .onClick(() => {
          this.removeLocal(meta);
        })
    }
    .width('100%')
    .padding({ left: 10, right: 6, top: 9, bottom: 9 })
    .backgroundColor(meta.id === this.currentSessionId ? Theme.accentGhost : Color.Transparent)
    .borderRadius(Theme.rSm)
    .gesture(LongPressGesture({ repeat: false }).onAction(() => {
      this.openRename('local', meta.id, meta.title);
    }))
  }

  /**
   * 上下文裁剪（逻辑在 common/Chat.trimHistory，已单测）。
   * 被裁掉时提示用户，避免"它怎么忘了"。
   */
  private buildHistory(messages: RenderMsg[]): ChatMessage[] {
    const turns: ChatTurn[] = [];
    for (let i = 0; i < messages.length; i++) {
      const turn: ChatTurn = { role: messages[i].role, content: messages[i].content };
      turns.push(turn);
    }
    const result: TrimResult = trimHistory(turns);
    this.trimmedCount = result.dropped;
    const out: ChatMessage[] = [];
    for (let i = 0; i < result.turns.length; i++) {
      const item: ChatMessage = { role: result.turns[i].role, content: result.turns[i].content };
      out.push(item);
    }
    return out;
  }

  /** 长按消息的上下文菜单：复制（原生菜单，不会被列表滚动手势吃掉）。 */
  @Builder
  messageMenu(text: string) {
    Menu() {
      MenuItem({ content: L.t('复制', 'Copy') })
        .onClick(() => {
          this.copyMessage(text);
        })
    }
  }

  /** 长按消息复制全文。 */
  private async copyMessage(text: string): Promise<void> {
    try {
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
      await pasteboard.getSystemPasteboard().setData(data);
      this.notice = L.t('已复制', 'Copied');
      setTimeout(() => {
        this.notice = '';
      }, 1500);
    } catch (e) {
      hilog.warn(0x0000, TAG, 'copy failed');
    }
  }

  /** 打开重命名弹层（本地会话 / 平台历史都走这里）。 */
  private openRename(target: string, id: string, current: string): void {
    this.renameTarget = target;
    this.renameId = id;
    this.renameDraft = current;
    this.showRename = true;
  }

  private async applyRename(): Promise<void> {
    const title: string = this.renameDraft.trim();
    if (title.length === 0) {
      return;
    }
    if (this.renameTarget === 'local') {
      sessions.rename(this.renameId, title);
      if (this.renameId === this.currentSessionId) {
        this.sessionTitle = title;
      }
      this.localSessions = sessions.list();
    } else {
      const ok: boolean = await auth.renameConversation(this.renameId, title);
      if (ok) {
        await this.reloadConversations();
      } else {
        this.errorMsg = L.t('重命名失败（平台接口）', 'Rename failed');
      }
    }
    this.showRename = false;
  }

  @Builder
  drawer() {
    Column() {
      Row({ space: 10 }) {
        this.avatarBox(40, 15)
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
        .onClick(() => {
          this.openProfile();
        })
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
        Text(L.t('新对话', 'New chat'))
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

      // 服务入口（顺序与 PC 客户端一致：算力服务 → 插件 → AI 社区 → 应用商城）
      Row({ space: 8 }) {
        Text('HPC')
          .fontSize(9)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.accent)
          .width(24)
          .height(24)
          .textAlign(TextAlign.Center)
          .borderRadius(7)
          .backgroundColor(Theme.accentGhost)
        Column({ space: 1 }) {
          Text(L.t('算力服务', 'Compute service')).fontSize(Theme.fSmall).fontColor(Theme.text)
          Text(L.t('集群 · 队列 · 作业 · 文件', 'Clusters · queues · jobs')).fontSize(10).fontColor(Theme.textFaint)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Text('›').fontSize(14).fontColor(Theme.textFaint)
      }
      .width('100%')
      .padding({ left: 10, right: 10, top: 9, bottom: 9 })
      .margin({ top: 12 })
      .backgroundColor(Theme.surfaceAlt)
      .borderRadius(Theme.rSm)
      .onClick(() => {
        this.drawerOpen = false;
        router.pushUrl({ url: 'pages/Jobs' });
      })

      Row({ space: 8 }) {
        Text('＋')
          .fontSize(13)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.accent)
          .width(24)
          .height(24)
          .textAlign(TextAlign.Center)
          .borderRadius(7)
          .backgroundColor(Theme.accentGhost)
        Column({ space: 1 }) {
          Text(L.t('插件', 'Plugins')).fontSize(Theme.fSmall).fontColor(Theme.text)
          Text(L.t('精选连接器 / 技能', 'Featured connectors & skills')).fontSize(10).fontColor(Theme.textFaint)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Text('›').fontSize(14).fontColor(Theme.textFaint)
      }
      .width('100%')
      .padding({ left: 10, right: 10, top: 9, bottom: 9 })
      .margin({ top: 6 })
      .backgroundColor(Theme.surfaceAlt)
      .borderRadius(Theme.rSm)
      .onClick(() => {
        this.drawerOpen = false;
        router.pushUrl({ url: 'pages/MarketPage' });
      })

      Row({ space: 8 }) {
        Text('AI')
          .fontSize(11)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.accent)
          .width(24)
          .height(24)
          .textAlign(TextAlign.Center)
          .borderRadius(7)
          .backgroundColor(Theme.accentGhost)
        Column({ space: 1 }) {
          Text(L.t('AI 社区', 'AI community')).fontSize(Theme.fSmall).fontColor(Theme.text)
          Text(L.t('领域智能体 / 应用市场', 'Domain agents & apps')).fontSize(10).fontColor(Theme.textFaint)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Text('›').fontSize(14).fontColor(Theme.textFaint)
      }
      .width('100%')
      .padding({ left: 10, right: 10, top: 9, bottom: 9 })
      .margin({ top: 6 })
      .backgroundColor(Theme.surfaceAlt)
      .borderRadius(Theme.rSm)
      .onClick(() => {
        this.drawerOpen = false;
        router.pushUrl({ url: 'pages/AiHubPage' });
      })

      Row({ space: 8 }) {
        Text('OCR')
          .fontSize(9)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.accent)
          .width(24)
          .height(24)
          .textAlign(TextAlign.Center)
          .borderRadius(7)
          .backgroundColor(Theme.accentGhost)
        Column({ space: 1 }) {
          Text(L.t('文字识别', 'OCR')).fontSize(Theme.fSmall).fontColor(Theme.text)
          Text(L.t('识别 · 文档解析 · 格式转换', 'OCR · parse · convert')).fontSize(10).fontColor(Theme.textFaint)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Text('›').fontSize(14).fontColor(Theme.textFaint)
      }
      .width('100%')
      .padding({ left: 10, right: 10, top: 9, bottom: 9 })
      .margin({ top: 6, bottom: 6 })
      .backgroundColor(Theme.surfaceAlt)
      .borderRadius(Theme.rSm)
      .onClick(() => {
        this.drawerOpen = false;
        router.pushUrl({ url: 'pages/OcrPage' });
      })

      Row({ space: 6 }) {
        Text(L.t('本机会话', 'Local chats'))
          .fontSize(Theme.fTiny)
          .fontColor(Theme.textFaint)
          .layoutWeight(1)
        Text(`${this.localSessions.length}`)
          .fontSize(Theme.fTiny)
          .fontColor(Theme.textFaint)
      }
      .width('100%')
      .padding({ top: 14, bottom: 4, left: 2, right: 2 })

      if (this.localSessions.length === 0) {
        Text('还没有本机会话，发一条消息就会自动保存')
          .fontSize(10)
          .fontColor(Theme.textFaint)
          .width('100%')
          .padding({ left: 10, top: 2, bottom: 6 })
      } else {
        List() {
          ForEach(this.localSessions, (meta: SessionMeta) => {
            ListItem() {
              this.localItem(meta)
            }
            .onClick(() => {
              this.openLocal(meta);
            })
          }, (meta: SessionMeta) => meta.id)
        }
        .width('100%')
        .constraintSize({ maxHeight: 190 })
        .scrollBar(BarState.Off)
      }

      Row({ space: 6 }) {
        Text(L.t('平台历史', 'Platform history'))
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
          .gesture(LongPressGesture({ repeat: false }).onAction(() => {
            this.openRename('cloud', item.id ?? '', safe(item.title));
          }))
        }, (item: Conversation) => `${item.id}`)
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Off)

      Divider().color(Theme.hairline).margin({ top: 6, bottom: 6 })

      Text(L.t('退出登录', 'Sign out'))
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
            LazyForEach(this.msgSource, (item: RenderMsg) => {
              ListItem() {
                if (item.role === 'user') {
                  this.userBubble(item.content)
                } else {
                  this.assistantBubble(item.content, false, item.via ?? '')
                }
              }
            }, (item: RenderMsg) => `${item.role}-${item.content.length}-${item.content.substring(0, 12)}`)

            if (this.busy) {
              ListItem() {
                if (this.streaming.length > 0) {
                  this.assistantBubble(this.streaming, true, this.pendingVia)
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
          .onClick(() => {
            this.hideKeyboard();
          })
        }

        if (this.notice.length > 0 && this.errorMsg.length === 0) {
          Row({ space: 6 }) {
            Text(this.notice)
              .fontSize(10)
              .fontColor(Theme.textSub)
              .layoutWeight(1)
              .maxLines(2)
            Text('✕')
              .fontSize(10)
              .fontColor(Theme.textFaint)
              .onClick(() => {
                this.notice = '';
              })
          }
          .width('100%')
          .padding({ left: 16, right: 16, bottom: 4 })
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

      if (this.showAttachSheet) {
        Column() {
          Blank().layoutWeight(1).width('100%').onClick(() => {
            this.showAttachSheet = false;
          })
          Column({ space: 10 }) {
            Text(L.t('添加附件', 'Add attachment'))
              .fontSize(Theme.fTitle)
              .fontFamily(Theme.fontDisplay)
              .fontColor(Theme.text)
              .width('100%')
            Text(L.t('支持 PDF / Office / 文本 / 代码 / 图片 / 压缩包',
              'PDF, Office, text, code, images, archives'))
              .fontSize(10)
              .fontColor(Theme.textFaint)
              .width('100%')
            Row({ space: 10 }) {
              Text('📎').fontSize(20)
              Text(L.t('选择文件', 'Choose file')).fontSize(Theme.fSmall).fontColor(Theme.text)
                .layoutWeight(1)
              Text('›').fontSize(14).fontColor(Theme.textFaint)
            }
            .width('100%')
            .padding({ left: 14, right: 12, top: 14, bottom: 14 })
            .backgroundColor(Theme.surfaceAlt)
            .borderRadius(Theme.rMd)
            .onClick(() => {
              this.pickAttachmentAny();
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

      if (this.showRename) {
        Column() {
          Blank().layoutWeight(1).width('100%').onClick(() => {
            this.showRename = false;
          })
          Column({ space: 12 }) {
            Text(L.t('重命名会话', 'Rename chat'))
              .fontSize(Theme.fTitle)
              .fontFamily(Theme.fontDisplay)
              .fontColor(Theme.text)
            TextInput({ text: this.renameDraft, placeholder: L.t('会话标题', 'Title') })
              .height(42)
              .fontSize(Theme.fSmall)
              .backgroundColor(Theme.surfaceAlt)
              .borderRadius(Theme.rSm)
              .padding({ left: 12, right: 12 })
              .onChange((v: string) => {
                this.renameDraft = v;
              })
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
                  this.showRename = false;
                })
              Text(L.t('保存', 'Save'))
                .fontSize(Theme.fSmall)
                .fontColor(Theme.textOnAccent)
                .layoutWeight(1)
                .textAlign(TextAlign.Center)
                .padding({ top: 10, bottom: 10 })
                .backgroundColor(Theme.accent)
                .borderRadius(Theme.rSm)
                .onClick(() => {
                  this.applyRename();
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

      if (this.showScenarioSheet) {
        Column() {
          Blank().layoutWeight(1).width('100%').onClick(() => {
            this.showScenarioSheet = false;
          })
          ScenarioSheet({
            categories: this.scenarioCategories,
            currentCategory: this.scenarioCategory,
            onPick: (item: ScenarioItem) => {
              this.pickScenario(item);
            },
            onPickCategory: (id: string) => {
              this.switchScenarioCategory(id);
            },
            onClose: () => {
              this.showScenarioSheet = false;
            }
          })
        }
        .width('100%')
        .height('100%')
        .backgroundColor('#0B1F3355')
      }

      if (this.showModelSheet) {
        Column() {
          Blank().layoutWeight(1).width('100%').onClick(() => {
            this.showModelSheet = false;
          })
          ModelSheet({
            items: this.pickItems,
            currentKey: this.channel === 'agent' ? this.agentKey : this.gatewayModel,
            onPick: (item: PickItem) => {
              this.applyPick(item);
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
    .key(`root-${this.themeRev}`)
  }
}
