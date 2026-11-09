/**
 * 内嵌浏览器：用 ArkWeb 打开平台网页（AIHub 智能体等）。
 *
 * 为什么要它：AIHub 的智能体是 link / host / build 三种第三方形态，
 * 没有原生可调的对话接口，正确做法是把它的页面嵌进来。
 * 关键点是**注入登录态**：我们已经有 jsessionid cookie，别让用户在 Web 里再登一次。
 */
import { webview } from '@kit.ArkWeb';
import { router } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { credentials } from '../service/Http';
import { Theme } from '../common/Theme';

const TAG: string = 'SCNetLite';
const HOST: string = 'https://www.scnet.cn';

interface WebParams {
  url?: string;
  title?: string;
}

@Entry
@Component
struct WebPage {
  @State title: string = '';
  @State url: string = HOST;
  @State progress: number = 0;
  private controller: webview.WebviewController = new webview.WebviewController();

  aboutToAppear(): void {
    const params = router.getParams() as WebParams;
    if (params !== null && params !== undefined) {
      this.url = params.url !== undefined && params.url.length > 0 ? params.url : HOST;
      this.title = params.title ?? '';
    }
    this.injectCookies();
  }

  /** 把我们登录得到的 jsessionid / Token 注入到 WebView 的 cookie 罐里。 */
  private injectCookies(): void {
    try {
      const cookie: string = credentials.cookie;
      if (cookie.length > 0) {
        webview.WebCookieManager.configCookieSync(HOST, cookie);
        hilog.info(0x0000, TAG, 'webview cookie injected len=%{public}d', cookie.length);
      }
    } catch (e) {
      hilog.warn(0x0000, TAG, 'webview cookie inject failed');
    }
  }

  build() {
    Column() {
      Row({ space: 10 }) {
        Text('‹')
          .fontSize(22)
          .fontColor(Theme.textSub)
          .width(32)
          .height(32)
          .textAlign(TextAlign.Center)
          .onClick(() => {
            try {
              router.back();
            } catch (e) {
              router.replaceUrl({ url: 'pages/Index' });
            }
          })
        Column({ space: 1 }) {
          Text(this.title.length > 0 ? this.title : 'AI 社区')
            .fontSize(Theme.fBody)
            .fontWeight(FontWeight.Medium)
            .fontColor(Theme.text)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.hostOf(this.url))
            .fontSize(10)
            .fontColor(Theme.textFaint)
            .maxLines(1)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Text('⟳')
          .fontSize(16)
          .fontColor(Theme.textSub)
          .width(32)
          .height(32)
          .textAlign(TextAlign.Center)
          .onClick(() => {
            try {
              this.controller.refresh();
            } catch (e) {
              hilog.warn(0x0000, TAG, 'webview refresh failed');
            }
          })
      }
      .width('100%')
      .height(52)
      .padding({ left: 8, right: 12 })
      .backgroundColor(Theme.surface)
      .border({ width: { bottom: 1 }, color: Theme.hairline })

      if (this.progress > 0 && this.progress < 100) {
        Progress({ value: this.progress, total: 100, type: ProgressType.Linear })
          .width('100%')
          .height(2)
          .color(Theme.accent)
      }

      Web({ src: this.url, controller: this.controller })
        .width('100%')
        .layoutWeight(1)
        .darkMode(WebDarkMode.Off)
        .mixedMode(MixedMode.All)
        .domStorageAccess(true)
        .onPageEnd(() => {
          hilog.info(0x0000, TAG, 'webview page end');
        })
        .onProgressChange((event) => {
          this.progress = event.newProgress;
        })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.bg)
  }

  private hostOf(url: string): string {
    const stripped: string = url.replace('https://', '').replace('http://', '');
    const slash: number = stripped.indexOf('/');
    return slash > 0 ? stripped.substring(0, slash) : stripped;
  }
}
