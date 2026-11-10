import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window, KeyboardAvoidMode } from '@kit.ArkUI';
import { auth } from '../service/Auth';
import { setUnauthorizedHandler } from '../service/Http';
import { store } from '../service/Store';
import { Theme } from '../common/Theme';
import { L } from '../common/I18n';

const TAG: string = 'SCNetLite';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(0x0000, TAG, 'ability created');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    const loggedIn: boolean = auth.restore(this.context);
    // 主题必须在首帧之前应用，否则会先闪一下默认色
    Theme.applyPalette(store.getTheme());
    Theme.applyFontLevel(store.getFontLevel());
    L.zh = store.getLang() !== 'en';
    AppStorage.setOrCreate('themeVersion', 0);
    const entryPage: string = loggedIn ? 'pages/Index' : 'pages/Login';
    windowStage.loadContent(entryPage, (err) => {
      if (err.code) {
        hilog.error(0x0000, TAG, 'loadContent failed: %{public}s', JSON.stringify(err));
        return;
      }
      // 会话中途 401：清凭据 + 回登录页，并让登录页显示「登录已过期」。
      // 以前这里什么都不做，401 只变成一条普通报错，用户看不懂。
      let redirecting: boolean = false;
      const uiContext = windowStage.getMainWindowSync().getUIContext();
      setUnauthorizedHandler(() => {
        if (redirecting) {
          return;
        }
        redirecting = true;
        auth.noteSessionExpired();
        uiContext.getRouter().replaceUrl({ url: 'pages/Login' }).catch(() => {
          // 已经在登录页时会失败，忽略
        }).finally(() => {
          setTimeout(() => {
            redirecting = false;
          }, 1500);
        });
      });

      // 键盘弹出时压缩页面而不是整体上移：顶栏留在原位，输入区贴着键盘上沿。
      // 默认是 OFFSET（整页上移），会把顶栏推出屏幕、输入区压到 IME 下面。
      try {
        windowStage.getMainWindowSync().getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE);
      } catch (e) {
        hilog.warn(0x0000, TAG, 'setKeyboardAvoidMode failed');
      }
      hilog.info(0x0000, TAG, 'content loaded: %{public}s', entryPage);
    });
  }
}
