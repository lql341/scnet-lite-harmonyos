import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { auth } from '../service/Auth';

const TAG: string = 'SCNetLite';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(0x0000, TAG, 'ability created');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    const loggedIn: boolean = auth.restore(this.context);
    const entryPage: string = loggedIn ? 'pages/Index' : 'pages/Login';
    windowStage.loadContent(entryPage, (err) => {
      if (err.code) {
        hilog.error(0x0000, TAG, 'loadContent failed: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(0x0000, TAG, 'content loaded: %{public}s', entryPage);
    });
  }
}
