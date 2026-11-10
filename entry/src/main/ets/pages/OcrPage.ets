/**
 * OCR 页：从相册选图 → 选识别类型 → 识别 → 展示文字（可复制/发送到对话）。
 */
import { router } from '@kit.ArkUI';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Theme } from '../common/Theme';
import { L } from '../common/I18n';
import { store } from '../service/Store';
import { apiKeys, GatewayAccess } from '../service/ApiKeys';
import { auth } from '../service/Auth';
import { ocr, OCR_TYPES, OcrType, OcrResult } from '../service/Ocr';
import { isOcrSupported, mimeOf } from '../service/Upload';
import { docAi, DocTask, CONVERT_PDF_TO_WORD, CONVERT_PDF_TO_EXCEL, CONVERT_PDF_TO_PPT } from '../service/DocAi';
import { picker } from '@kit.CoreFileKit';

const TAG: string = 'SCNetLite';

@Entry
@Component
struct OcrPage {
  @StorageProp('themeRev') themeRev: number = 0;
  @State ocrType: string = 'GENERAL';
  /** 'ocr' 通用识别 / 'parse' 文档解析 / 'convert' 格式转换 */
  @State mode: string = 'ocr';
  /** 文档解析/转换任务状态（异步接口，要轮询） */
  @State taskStatus: string = '';
  @State taskId: string = '';
  @State convertTarget: string = CONVERT_PDF_TO_WORD;
  @State fileName: string = '';
  @State previewUri: string = '';
  @State busy: boolean = false;
  @State errorMsg: string = '';
  @State lines: string[] = [];
  @State traceId: string = '';
  @State copied: boolean = false;
  @State notice: string = '';

  private async pickImage(): Promise<void> {
    try {
      const options = new photoAccessHelper.PhotoSelectOptions();
      options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      options.maxSelectNumber = 1;
      const picker = new photoAccessHelper.PhotoViewPicker();
      const result: photoAccessHelper.PhotoSelectResult = await picker.select(options);
      if (result.photoUris.length === 0) {
        return;
      }
      this.previewUri = result.photoUris[0];
      this.fileName = this.previewUri.substring(this.previewUri.lastIndexOf('/') + 1);
      this.lines = [];
      this.traceId = '';
      this.errorMsg = '';
    } catch (e) {
      hilog.warn(0x0000, TAG, 'ocr pick failed');
    }
  }

  /** 选 PDF（实测 OCR 端点支持 PDF：服务端会先转 PNG 再识别）。 */
  private async pickPdf(): Promise<void> {
    try {
      const options = new picker.DocumentSelectOptions();
      options.maxSelectNumber = 1;
      options.fileSuffixFilters = ['PDF|.pdf'];
      const documentPicker = new picker.DocumentViewPicker();
      const uris: string[] = await documentPicker.select(options);
      if (uris.length === 0) {
        return;
      }
      const uri: string = uris[0];
      const slash: number = uri.lastIndexOf('/');
      let name: string = slash >= 0 ? uri.substring(slash + 1) : 'document.pdf';
      if (name.indexOf('?') >= 0) {
        name = name.substring(0, name.indexOf('?'));
      }
      if (!isOcrSupported(name)) {
        this.errorMsg = L.t('这个格式 OCR 不支持，请用「文档解析」',
          'This format is not supported by OCR; use Parse');
        return;
      }
      this.previewUri = uri;
      this.fileName = name;
      this.lines = [];
      this.traceId = '';
      this.errorMsg = '';
    } catch (e) {
      hilog.warn(0x0000, TAG, 'pdf picker failed');
    }
  }

  /** 文档解析/转换的文件选择（不限 pdf）。 */
  private async pickDoc(): Promise<void> {
    try {
      const options = new picker.DocumentSelectOptions();
      options.maxSelectNumber = 1;
      options.fileSuffixFilters = ['文档 (.pdf, .doc, .docx, .xls, .xlsx, .ppt, .pptx, .png, .jpg)|' +
        '.pdf,.doc,.docx,.xls,.xlsx,.ppt,.pptx,.png,.jpg,.jpeg'];
      const documentPicker = new picker.DocumentViewPicker();
      const uris: string[] = await documentPicker.select(options);
      if (uris.length === 0) {
        return;
      }
      const uri: string = uris[0];
      const slash: number = uri.lastIndexOf('/');
      let name: string = slash >= 0 ? uri.substring(slash + 1) : 'document';
      if (name.indexOf('?') >= 0) {
        name = name.substring(0, name.indexOf('?'));
      }
      this.previewUri = uri;
      this.fileName = name;
      this.taskStatus = '';
      this.taskId = '';
      this.lines = [];
      this.errorMsg = '';
    } catch (e) {
      hilog.warn(0x0000, TAG, 'doc picker failed');
    }
  }

  /** 提交文档任务并轮询（解析→拉结果 json 抽文本；转换→给结果链接）。 */
  private async runDoc(): Promise<void> {
    if (this.previewUri.length === 0) {
      this.errorMsg = L.t('先选择一个文件', 'Pick a file first');
      return;
    }
    this.busy = true;
    this.errorMsg = '';
    this.lines = [];
    this.taskStatus = '';
    try {
      let key: string = store.getAutoKey();
      if (key.length === 0) {
        const access: GatewayAccess = await apiKeys.ensureAccess(await auth.clusterIdentity());
        key = access.key;
      }
      // 读文件
      const file = fs.openSync(this.previewUri, fs.OpenMode.READ_ONLY);
      const stat = fs.statSync(file.fd);
      const buffer: ArrayBuffer = new ArrayBuffer(stat.size);
      fs.readSync(file.fd, buffer);
      fs.closeSync(file);
      const bytes: Uint8Array = new Uint8Array(buffer);
      const mime: string = mimeOf(this.fileName);

      let task: DocTask = this.mode === 'parse'
        ? await docAi.submitParse(key, bytes, this.fileName, mime)
        : await docAi.submitConvert(key, bytes, this.fileName, mime, this.convertTarget);
      this.taskId = task.taskId;
      this.taskStatus = task.status;

      // 轮询（最长 ~3 分钟）
      for (let i = 0; i < 30; i++) {
        if (task.status === 'succeeded' || task.status === 'failed') {
          break;
        }
        await new Promise<void>((resolve) => {
          setTimeout(() => resolve(), 4000);
        });
        task = await docAi.query(key, task.taskId);
        this.taskStatus = task.status;
      }

      if (task.status === 'failed') {
        this.errorMsg = task.errorMessage.length > 0 ? task.errorMessage
          : L.t('任务失败', 'Task failed');
      } else if (task.status === 'succeeded' && task.results.length > 0) {
        const url: string = task.results[0];
        if (this.mode === 'convert') {
          // 转换结果是文件：直接给链接（可复制/打开）
          this.lines = [url];
          this.notice = L.t('转换完成，结果链接已放在下方（3 天内有效）',
            'Converted. Result URL below (valid 3 days)');
        } else {
          const raw: string = await docAi.fetchResult(url);
          const text: string = docAi.extractText(raw);
          this.lines = text.length > 0 ? text.split('\n') : [url];
          this.notice = L.t('解析完成', 'Parsed');
        }
      } else {
        this.errorMsg = L.t('任务已提交但还没有结果，稍后再试', 'Submitted, no result yet');
      }
      hilog.info(0x0000, TAG, 'doc task %{public}s done status=%{public}s',
        this.taskId, this.taskStatus);
    } catch (e) {
      const err = e as Error;
      this.errorMsg = err.message ?? L.t('任务提交失败', 'Submit failed');
    }
    this.busy = false;
  }

  private async run(): Promise<void> {
    if (this.previewUri.length === 0) {
      this.errorMsg = L.t('先选一张图片', 'Pick an image first');
      return;
    }
    this.busy = true;
    this.errorMsg = '';
    this.lines = [];
    try {
      // OCR 走网关 sk- key；没有就现取一次（AIHub/OCR 共用这把 key）
      let key: string = store.getAutoKey();
      if (key.length === 0) {
        const access: GatewayAccess = await apiKeys.ensureAccess(await auth.clusterIdentity());
        key = access.key;
      }
      if (key.length === 0) {
        this.errorMsg = L.t('没有可用的网关 key，请先登录', 'No gateway key, please sign in');
        this.busy = false;
        return;
      }
      // 读图
      const file = fs.openSync(this.previewUri, fs.OpenMode.READ_ONLY);
      const stat = fs.statSync(file.fd);
      const buffer: ArrayBuffer = new ArrayBuffer(stat.size);
      fs.readSync(file.fd, buffer);
      fs.closeSync(file);
      const bytes: Uint8Array = new Uint8Array(buffer);
      const mime: string = mimeOf(this.fileName.length > 0 ? this.fileName : 'image.jpg');
      if (!isOcrSupported(this.fileName)) {
        this.errorMsg = L.t('OCR 只支持图片和 PDF；word/excel/ppt/md 请用「文档解析」',
          'OCR supports images and PDF only; use Parse for Office/Markdown');
        this.busy = false;
        return;
      }
      const result: OcrResult = await ocr.recognize(key, bytes, this.fileName.length > 0 ? this.fileName : 'image.jpg',
        mime.length > 0 ? mime : 'image/jpeg', this.ocrType);
      this.lines = result.lines;
      this.traceId = result.traceId;
      if (result.lines.length === 0) {
        this.errorMsg = L.t('没有识别到文字（换类型或换图试试）', 'No text found (try another type or image)');
      }
    } catch (e) {
      const err = e as Error;
      this.errorMsg = err.message ?? L.t('识别失败', 'Recognition failed');
      hilog.warn(0x0000, TAG, 'ocr failed: %{public}s', this.errorMsg);
    }
    this.busy = false;
  }

  /** 用内置小图跑一次 OCR，验证「multipart + 端点 + 解析」整条链路（诊断用）。 */
  private async selfTest(): Promise<void> {
    this.busy = true;
    this.errorMsg = '';
    try {
      const raw = await getContext(this).resourceManager.getRawFileContent('ocr-selftest.png');
      let key: string = store.getAutoKey();
      if (key.length === 0) {
        const access: GatewayAccess = await apiKeys.ensureAccess(await auth.clusterIdentity());
        key = access.key;
      }
      const result: OcrResult = await ocr.recognize(key, raw, 'ocr-selftest.png', 'image/png', 'GENERAL');
      hilog.info(0x0000, TAG, 'ocr selftest ok trace=%{public}s lines=%{public}d',
        result.traceId, result.lines.length);
      this.errorMsg = L.t(`自检通过（trace ${result.traceId.substring(0, 8)}，无文字属正常）`,
        `Self-test ok (trace ${result.traceId.substring(0, 8)}, no text is expected)`);
    } catch (e) {
      const err = e as Error;
      this.errorMsg = L.t(`自检失败：${err.message}`, `Self-test failed: ${err.message}`);
      hilog.warn(0x0000, TAG, 'ocr selftest failed: %{public}s', err.message);
    }
    this.busy = false;
  }

  private async copyAll(): Promise<void> {
    try {
      const text: string = this.lines.join('\n');
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
      await pasteboard.getSystemPasteboard().setData(data);
      this.copied = true;
      setTimeout(() => {
        this.copied = false;
      }, 1500);
    } catch (e) {
      hilog.warn(0x0000, TAG, 'ocr copy failed');
    }
  }

  build() {
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
          Text(L.t('文字识别', 'OCR'))
            .fontSize(Theme.fTitle)
            .fontFamily(Theme.fontDisplay)
            .fontColor(Theme.text)
          Text(L.t('支持图片与 PDF（证照/票据/手写）', 'Images and PDF: cards, invoices, handwriting'))
            .fontSize(10)
            .fontColor(Theme.textFaint)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Text(L.t('自检', 'Test'))
          .fontSize(Theme.fTiny)
          .fontColor(Theme.accent)
          .padding({ left: 10, right: 10, top: 5, bottom: 5 })
          .backgroundColor(Theme.accentGhost)
          .borderRadius(Theme.rPill)
          .onClick(() => {
            if (!this.busy) {
              this.selfTest();
            }
          })
      }
      .width('100%')
      .height(52)
      .padding({ left: 8, right: 12 })

      Scroll() {
        Column({ space: 12 }) {
          // 三种能力：OCR 走网关；文档解析/格式转换在平台 Web 端
          Row({ space: 8 }) {
            ForEach(['ocr', 'parse', 'convert'], (m: string) => {
              Text(m === 'ocr' ? L.t('通用文字识别', 'OCR')
                : (m === 'parse' ? L.t('文档解析', 'Parse') : L.t('格式转换', 'Convert')))
                .fontSize(Theme.fTiny)
                .fontColor(this.mode === m ? Theme.textOnAccent : Theme.textSub)
                .padding({ left: 12, right: 12, top: 7, bottom: 7 })
                .backgroundColor(this.mode === m ? Theme.accent : Theme.surface)
                .borderRadius(Theme.rPill)
                .border({ width: 1, color: this.mode === m ? Theme.accent : Theme.hairline })
                .onClick(() => {
                  this.mode = m;
                })
            }, (m: string) => m)
            Blank().layoutWeight(1)
          }
          .width('100%')

          if (this.mode !== 'ocr') {
            Column({ space: 10 }) {
              Text(this.mode === 'parse'
                ? L.t('文档解析（DOC_MIND）', 'Document parse (DOC_MIND)')
                : L.t('格式转换（DOC_CONVERSION）', 'Format convert (DOC_CONVERSION)'))
                .fontSize(Theme.fSmall)
                .fontColor(Theme.text)
              Text(this.mode === 'parse'
                ? L.t('支持 PDF / Word / Excel / PPT / 图片，输出结构化文本（含表格、公式）',
                  'PDF / Word / Excel / PPT / images → structured text')
                : L.t('选择转换方向后上传文件，结果是转换后的文件（OSS 链接）',
                  'Pick a direction, upload a file; result is a converted file URL'))
                .fontSize(10)
                .lineHeight(16)
                .fontColor(Theme.textFaint)
                .width('100%')

              if (this.mode === 'convert') {
                Scroll() {
                  Row({ space: 8 }) {
                    ForEach([CONVERT_PDF_TO_WORD, CONVERT_PDF_TO_EXCEL, CONVERT_PDF_TO_PPT], (t: string) => {
                      Text(t)
                        .fontSize(Theme.fTiny)
                        .fontColor(this.convertTarget === t ? Theme.textOnAccent : Theme.textSub)
                        .padding({ left: 10, right: 10, top: 6, bottom: 6 })
                        .backgroundColor(this.convertTarget === t ? Theme.accent : Theme.surfaceAlt)
                        .borderRadius(Theme.rPill)
                        .onClick(() => {
                          this.convertTarget = t;
                        })
                    }, (t: string) => t)
                  }
                }
                .scrollable(ScrollDirection.Horizontal)
                .scrollBar(BarState.Off)
                .width('100%')
              }

              Row({ space: 8 }) {
                Text(L.t('选择文件', 'Choose file'))
                  .fontSize(Theme.fSmall)
                  .fontColor(Theme.accent)
                  .layoutWeight(1)
                  .textAlign(TextAlign.Center)
                  .padding({ top: 10, bottom: 10 })
                  .backgroundColor(Theme.accentGhost)
                  .borderRadius(Theme.rSm)
                  .onClick(() => {
                    this.pickDoc();
                  })
                Text(this.mode === 'parse' ? L.t('开始解析', 'Parse') : L.t('开始转换', 'Convert'))
                  .fontSize(Theme.fSmall)
                  .fontColor(Theme.textOnAccent)
                  .layoutWeight(1)
                  .textAlign(TextAlign.Center)
                  .padding({ top: 10, bottom: 10 })
                  .backgroundColor(Theme.accent)
                  .borderRadius(Theme.rSm)
                  .opacity(this.busy ? 0.6 : 1)
                  .onClick(() => {
                    if (!this.busy) {
                      this.runDoc();
                    }
                  })
              }
              .width('100%')

              if (this.fileName.length > 0) {
                Text(this.fileName)
                  .fontSize(10)
                  .fontColor(Theme.textSub)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .width('100%')
              }
              if (this.taskStatus.length > 0) {
                Text(L.t(`任务 ${this.taskId}：${this.taskStatus}`, `Task ${this.taskId}: ${this.taskStatus}`))
                  .fontSize(10)
                  .fontColor(this.taskStatus === 'succeeded' ? Theme.ok : Theme.textFaint)
                  .width('100%')
              }
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
            .padding(12)
            .backgroundColor(Theme.surface)
            .borderRadius(Theme.rMd)
            .border({ width: 1, color: Theme.hairline })
          }

          // 图片选择
          Column({ space: 10 }) {
            if (this.previewUri.length > 0 && this.fileName.toLowerCase().endsWith('.pdf')) {
              Column({ space: 6 }) {
                Text('📄').fontSize(34)
                Text(this.fileName)
                  .fontSize(Theme.fSmall)
                  .fontColor(Theme.text)
                  .maxLines(2)
                  .textAlign(TextAlign.Center)
                Text(L.t('PDF（服务端会先转成图片再识别）', 'Server converts PDF pages first'))
                  .fontSize(10)
                  .fontColor(Theme.textFaint)
              }
              .width('100%')
              .height(190)
              .justifyContent(FlexAlign.Center)
              .backgroundColor(Theme.surfaceAlt)
              .borderRadius(Theme.rMd)
            } else if (this.previewUri.length > 0) {
              Image(this.previewUri)
                .width('100%')
                .height(190)
                .borderRadius(Theme.rMd)
                .objectFit(ImageFit.Contain)
                .backgroundColor(Theme.surfaceAlt)
            } else {
              // 未选文件：可点击占位区（等价于「选图片」），避免页面只剩一条提示
              Column({ space: 6 }) {
                Text('🖼').fontSize(26)
                Text(L.t('选择图片或 PDF 开始识别', 'Pick an image or PDF to start'))
                  .fontSize(Theme.fSmall)
                  .fontColor(Theme.textSub)
                Text(L.t('支持 PNG / JPG / WEBP 与 PDF', 'PNG, JPG, WEBP and PDF'))
                  .fontSize(10)
                  .fontColor(Theme.textFaint)
              }
              .width('100%')
              .height(132)
              .justifyContent(FlexAlign.Center)
              .backgroundColor(Theme.surfaceAlt)
              .borderRadius(Theme.rMd)
              .onClick(() => {
                this.pickImage();
              })
            }

            Row({ space: 8 }) {
              Text(L.t('选图片', 'Image'))
                .fontSize(Theme.fSmall)
                .fontColor(Theme.accent)
                .layoutWeight(1)
                .textAlign(TextAlign.Center)
                .padding({ top: 10, bottom: 10 })
                .backgroundColor(Theme.accentGhost)
                .borderRadius(Theme.rSm)
                .onClick(() => {
                  this.pickImage();
                })
              Text(L.t('选 PDF', 'PDF'))
                .fontSize(Theme.fSmall)
                .fontColor(Theme.accent)
                .layoutWeight(1)
                .textAlign(TextAlign.Center)
                .padding({ top: 10, bottom: 10 })
                .backgroundColor(Theme.accentGhost)
                .borderRadius(Theme.rSm)
                .onClick(() => {
                  this.pickPdf();
                })
              Text(this.busy ? L.t('识别中…', 'Working…') : L.t('开始识别', 'Recognize'))
                .fontSize(Theme.fSmall)
                .fontColor(Theme.textOnAccent)
                .layoutWeight(1)
                .textAlign(TextAlign.Center)
                .padding({ top: 10, bottom: 10 })
                .backgroundColor(Theme.accent)
                .borderRadius(Theme.rSm)
                .opacity(this.busy ? 0.6 : 1)
                .onClick(() => {
                  if (!this.busy) {
                    this.run();
                  }
                })
            }
            .width('100%')
          }
          .width('100%')

          // 类型（仅识别模式）
          if (this.mode === 'ocr') {
          Scroll() {
            Row({ space: 8 }) {
              ForEach(OCR_TYPES, (type: OcrType) => {
                Text(L.t(type.label, type.code))
                  .fontSize(Theme.fTiny)
                  .fontColor(this.ocrType === type.code ? Theme.textOnAccent : Theme.textSub)
                  .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                  .backgroundColor(this.ocrType === type.code ? Theme.accent : Theme.surface)
                  .borderRadius(Theme.rPill)
                  .border({ width: 1, color: this.ocrType === type.code ? Theme.accent : Theme.hairline })
                  .onClick(() => {
                    this.ocrType = type.code;
                  })
              }, (type: OcrType) => type.code)
            }
          }
          .scrollable(ScrollDirection.Horizontal)
          .scrollBar(BarState.Off)
          .width('100%')
          }

          if (this.errorMsg.length > 0) {
            Text(this.errorMsg)
              .fontSize(Theme.fSmall)
              .fontColor(Theme.danger)
              .width('100%')
              .padding(12)
              .backgroundColor(Theme.dangerSoft)
              .borderRadius(Theme.rMd)
          }

          if (this.lines.length > 0) {
            Column({ space: 8 }) {
              Row({ space: 8 }) {
                Text(L.t(`识别结果 ${this.lines.length} 行`, `${this.lines.length} lines`))
                  .fontSize(Theme.fTiny)
                  .fontColor(Theme.textFaint)
                  .layoutWeight(1)
                Text(this.copied ? L.t('已复制', 'Copied') : L.t('复制', 'Copy'))
                  .fontSize(Theme.fTiny)
                  .fontColor(Theme.accent)
                  .onClick(() => {
                    this.copyAll();
                  })
                Text(L.t('发送到对话', 'Send to chat'))
                  .fontSize(Theme.fTiny)
                  .fontColor(Theme.accent)
                  .onClick(() => {
                    router.replaceUrl({
                      url: 'pages/Index',
                      params: { prefill: this.lines.join('\n') }
                    });
                  })
              }
              .width('100%')
              Text(this.lines.join('\n'))
                .fontSize(Theme.mdBody)
                .lineHeight(Theme.mdLine)
                .fontColor(Theme.text)
                .width('100%')
                .copyOption(CopyOptions.LocalDevice)
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
            .padding(14)
            .backgroundColor(Theme.surface)
            .borderRadius(Theme.rMd)
            .border({ width: 1, color: Theme.hairline })
          }
        }
        .width('100%')
        .padding({ left: 14, right: 14, top: 4, bottom: 24 })
      }
      .layoutWeight(1)
      .width('100%')
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.bg)
    .key(`ocr-${this.themeRev}`)
  }
}
