import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { router } from '@kit.ArkUI';
import { auth, describeAuthError } from '../service/Auth';
import { L } from '../common/I18n';
import { ApiError } from '../service/Http';
import { store } from '../service/Store';
import { Theme } from '../common/Theme';

/**
 * 登录页：账号密码 / 手机验证码两个 Tab，首屏必须勾选协议。
 * 视觉与对话页共用 Theme，输入框做成大圆角浅底，主按钮满宽。
 */
@Entry
@Component
struct Login {
  @State mode: number = 0;
  @State userName: string = '';
  @State password: string = '';
  @State phone: string = '';
  @State smsCode: string = '';
  @State agreed: boolean = false;
  @State busy: boolean = false;
  @State errorMsg: string = '';
  @State tip: string = '';
  /** 'expired' → 顶部显示「登录已过期」而不是让用户莫名回到登录页 */
  @State reason: string = '';

  aboutToAppear(): void {
    store.init(getContext(this) as common.UIAbilityContext);
    this.reason = auth.loginReason;
    // 过期/重登时带出上次账号，用户只需要输密码
    if (this.userName.length === 0) {
      this.userName = store.getPlatformUserName();
    }
    if (this.reason === 'expired') {
      this.tip = '';
    }
  }

  private guard(): boolean {
    if (!this.agreed) {
      this.errorMsg = '请先阅读并同意《用户协议》和《隐私政策》';
      return false;
    }
    return true;
  }

  private async doPasswordLogin(): Promise<void> {
    if (!this.guard()) {
      return;
    }
    if (this.userName.trim().length === 0 || this.password.length === 0) {
      this.errorMsg = '请输入账号和密码';
      return;
    }
    this.busy = true;
    this.errorMsg = '';
    this.tip = '';
    try {
      await auth.loginByPassword(this.userName.trim(), this.password);
      this.enterApp();
    } catch (e) {
      const err = e as ApiError;
      this.errorMsg = describeAuthError(err.code, err.message);
    } finally {
      this.busy = false;
    }
  }

  private async sendCode(): Promise<void> {
    if (this.phone.length !== 11) {
      this.errorMsg = '请输入 11 位手机号';
      return;
    }
    this.errorMsg = '';
    this.busy = true;
    try {
      await auth.sendSmsCode(this.phone.trim());
      this.tip = '验证码已发送，请查看短信';
    } catch (e) {
      const err = e as ApiError;
      this.errorMsg = err.message.length > 0 ? err.message : '验证码发送失败';
    } finally {
      this.busy = false;
    }
  }

  private async doSmsLogin(): Promise<void> {
    if (!this.guard()) {
      return;
    }
    if (this.phone.length === 0 || this.smsCode.length === 0) {
      this.errorMsg = '请输入手机号和验证码';
      return;
    }
    this.busy = true;
    this.errorMsg = '';
    try {
      await auth.loginBySmsCode(this.phone.trim(), this.smsCode.trim());
      this.enterApp();
    } catch (e) {
      const err = e as ApiError;
      this.errorMsg = describeAuthError(err.code, err.message);
    } finally {
      this.busy = false;
    }
  }

  private enterApp(): void {
    this.reason = '';
    router.replaceUrl({ url: 'pages/Index' }).catch((err: Error) => {
      hilog.error(0x0000, 'SCNetLite', 'router failed: %{public}s', err.message);
    });
  }

  @Builder
  field(label: string, value: string, placeholder: string, isSecret: boolean, numeric: boolean,
    onInput: (v: string) => void) {
    Column({ space: 6 }) {
      Text(label)
        .fontSize(Theme.fTiny)
        .fontColor(Theme.textFaint)
        .padding({ left: 2 })
      TextInput({ text: value, placeholder: placeholder })
        .type(isSecret ? InputType.Password : (numeric ? InputType.Number : InputType.Normal))
        .height(46)
        .fontSize(Theme.fBody)
        .fontColor(Theme.text)
        .placeholderColor(Theme.textFaint)
        .backgroundColor(Theme.surfaceAlt)
        .borderRadius(Theme.rMd)
        .padding({ left: 14, right: 14 })
        .onChange(onInput)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  primaryButton(text: string, onTap: () => void) {
    Row() {
      if (this.busy) {
        LoadingProgress().width(18).height(18).color(Theme.textOnAccent)
      } else {
        Text(text)
          .fontSize(Theme.fBody)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.textOnAccent)
      }
    }
    .width('100%')
    .height(46)
    .justifyContent(FlexAlign.Center)
    .backgroundColor(this.busy ? '#7FA6C6' : Theme.accent)
    .borderRadius(Theme.rMd)
    .onClick(() => {
      if (!this.busy) {
        onTap();
      }
    })
  }

  @Builder
  passwordForm() {
    Column({ space: 14 }) {
      this.field('账号', this.userName, '用户名 / 手机号', false, false, (v: string) => {
        this.userName = v;
      })
      this.field('密码', this.password, '登录密码', true, false, (v: string) => {
        this.password = v;
      })
      this.primaryButton('登录', () => {
        this.doPasswordLogin();
      })
    }
    .width('100%')
  }

  @Builder
  smsForm() {
    Column({ space: 14 }) {
      this.field('手机号', this.phone, '11 位手机号', false, true, (v: string) => {
        this.phone = v;
      })
      Column({ space: 6 }) {
        Text('验证码').fontSize(Theme.fTiny).fontColor(Theme.textFaint).padding({ left: 2 })
        Row({ space: 8 }) {
          TextInput({ text: this.smsCode, placeholder: '短信验证码' })
            .type(InputType.Number)
            .height(46)
            .fontSize(Theme.fBody)
            .backgroundColor(Theme.surfaceAlt)
            .borderRadius(Theme.rMd)
            .padding({ left: 14, right: 14 })
            .layoutWeight(1)
            .onChange((value: string) => {
              this.smsCode = value;
            })
          Text('获取验证码')
            .fontSize(Theme.fSmall)
            .fontColor(Theme.accent)
            .textAlign(TextAlign.Center)
            .height(46)
            .padding({ left: 12, right: 12 })
            .backgroundColor(Theme.accentGhost)
            .borderRadius(Theme.rMd)
            .onClick(() => {
              if (!this.busy) {
                this.sendCode();
              }
            })
        }
        .width('100%')
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      this.primaryButton('登录 / 注册', () => {
        this.doSmsLogin();
      })
    }
    .width('100%')
  }

  build() {
    Column() {
      Blank().layoutWeight(1)

      // 品牌区
      Column({ space: 12 }) {
        Image($r('app.media.app_icon'))
          .width(68)
          .height(68)
          .borderRadius(20)
          .shadow({ radius: 22, color: '#0B1F3326', offsetY: 8 })
        Text('SCNet 智能体')
          .fontSize(24)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.text)
        Text('国家超算互联网 · 科研计算助手')
          .fontSize(Theme.fSmall)
          .fontColor(Theme.textFaint)
      }
      .width('100%')
      .padding({ top: 24, bottom: 28 })

      if (this.reason === 'expired') {
        Row({ space: 8 }) {
          Text('ⓘ').fontSize(12).fontColor(Theme.warn)
          Column({ space: 2 }) {
            Text(L.t('登录已过期', 'Session expired'))
              .fontSize(Theme.fSmall)
              .fontWeight(FontWeight.Medium)
              .fontColor(Theme.warn)
            Text(L.t('为保护账号，长时间未使用需要重新登录；密码 / 短信验证码都可以',
              'Please sign in again; password or SMS code both work'))
              .fontSize(10)
              .lineHeight(15)
              .fontColor(Theme.textSub)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
        }
        .width('100%')
        .padding(12)
        .backgroundColor('#FFF8EC')
        .borderRadius(Theme.rMd)
        .border({ width: 1, color: '#F3D9A4' })
        .margin({ bottom: 12 })
      }

      // 卡片
      Column({ space: 16 }) {
        Row() {
          Text('账号密码')
            .fontSize(Theme.fSmall)
            .fontColor(this.mode === 0 ? Theme.text : Theme.textFaint)
            .fontWeight(this.mode === 0 ? FontWeight.Medium : FontWeight.Normal)
            .textAlign(TextAlign.Center)
            .layoutWeight(1)
            .padding({ top: 8, bottom: 8 })
            .backgroundColor(this.mode === 0 ? Theme.surface : Color.Transparent)
            .borderRadius(Theme.rSm)
            .shadow(this.mode === 0 ? { radius: 6, color: '#0B1F3312', offsetY: 1 } : { radius: 0, color: '#00000000' })
            .onClick(() => {
              this.mode = 0;
              this.errorMsg = '';
            })
          Text('短信验证')
            .fontSize(Theme.fSmall)
            .fontColor(this.mode === 1 ? Theme.text : Theme.textFaint)
            .fontWeight(this.mode === 1 ? FontWeight.Medium : FontWeight.Normal)
            .textAlign(TextAlign.Center)
            .layoutWeight(1)
            .padding({ top: 8, bottom: 8 })
            .backgroundColor(this.mode === 1 ? Theme.surface : Color.Transparent)
            .borderRadius(Theme.rSm)
            .shadow(this.mode === 1 ? { radius: 6, color: '#0B1F3312', offsetY: 1 } : { radius: 0, color: '#00000000' })
            .onClick(() => {
              this.mode = 1;
              this.errorMsg = '';
            })
        }
        .width('100%')
        .padding(4)
        .backgroundColor(Theme.surfaceAlt)
        .borderRadius(Theme.rMd)

        if (this.mode === 0) {
          this.passwordForm()
        } else {
          this.smsForm()
        }

        if (this.errorMsg.length > 0) {
          Row({ space: 8 }) {
            Text('!')
              .fontSize(11)
              .fontWeight(FontWeight.Bold)
              .fontColor(Theme.danger)
              .width(18)
              .height(18)
              .textAlign(TextAlign.Center)
              .borderRadius(9)
              .backgroundColor(Theme.dangerSoft)
            Text(this.errorMsg)
              .fontSize(Theme.fSmall)
              .lineHeight(18)
              .fontColor(Theme.danger)
              .layoutWeight(1)
          }
          .width('100%')
          .alignItems(VerticalAlign.Top)
        } else if (this.tip.length > 0) {
          Text(this.tip).fontSize(Theme.fSmall).fontColor(Theme.textSub).width('100%')
        }

        Row({ space: 6 }) {
          Checkbox()
            .select(this.agreed)
            .selectedColor(Theme.accent)
            .width(18)
            .height(18)
            .onChange((value: boolean) => {
              this.agreed = value;
            })
          Text('我已阅读并同意《用户协议》和《隐私政策》')
            .fontSize(Theme.fTiny)
            .fontColor(Theme.textFaint)
            .layoutWeight(1)
        }
        .width('100%')
      }
      .width('100%')
      .padding({ left: 18, right: 18, top: 16, bottom: 18 })
      .backgroundColor(Theme.surface)
      .borderRadius(Theme.rXl)
      .border({ width: 1, color: Theme.hairline })
      .shadow(Theme.shadowSoft)

      Blank().layoutWeight(2)

      Text('非官方客户端 · 仅调用公开接口')
        .fontSize(10)
        .fontColor(Theme.textFaint)
        .width('100%')
        .textAlign(TextAlign.Center)
        .padding({ bottom: 8 })
    }
    .width('100%')
    .height('100%')
    .padding({ left: 22, right: 22, top: 32, bottom: 16 })
    .backgroundColor(Theme.bg)
  }
}
