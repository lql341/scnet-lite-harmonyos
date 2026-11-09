import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window, KeyboardAvoidMode } from '@kit.ArkUI';
import { auth } from '../service/Auth';
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
