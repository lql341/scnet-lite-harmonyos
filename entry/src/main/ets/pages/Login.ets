import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { auth, describeAuthError } from '../service/Auth';
import { ApiError } from '../service/Http';
import { store } from '../service/Store';
import { router } from '@kit.ArkUI';

/**
 * 登录页。两种方式对齐 APK：账号密码、手机验证码。
 * 首屏协议同意（用户协议 + 隐私政策）未同意不允许进入。
 */
@Entry
@Component
struct Login {
  @State mode: number = 0; // 0=密码, 1=短信
  @State userName: string = '';
  @State password: string = '';
  @State phone: string = '';
  @State smsCode: string = '';
  @State agreed: boolean = false;
  @State busy: boolean = false;
  @State errorMsg: string = '';
  @State tip: string = '';

  aboutToAppear(): void {
    store.init(getContext(this) as common.UIAbilityContext);
  }

  private async doPasswordLogin(): Promise<void> {
    if (!this.agreed) {
      this.errorMsg = '请先阅读并同意《用户协议》和《隐私政策》';
      return;
    }
    if (this.userName.length === 0 || this.password.length === 0) {
      this.errorMsg = '请输入账号和密码';
      return;
    }
    this.busy = true;
    this.errorMsg = '';
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
      this.tip = '验证码已发送';
    } catch (e) {
      const err = e as ApiError;
      this.errorMsg = err.message.length > 0 ? err.message : '验证码发送失败';
    } finally {
      this.busy = false;
    }
  }

  private async doSmsLogin(): Promise<void> {
    if (!this.agreed) {
      this.errorMsg = '请先阅读并同意《用户协议》和《隐私政策》';
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
    router.replaceUrl({ url: 'pages/Index' }).catch((err: Error) => {
      hilog.error(0x0000, 'SCNetLite', 'router failed: %{public}s', err.message);
    });
  }

  @Builder
  passwordForm() {
    Column({ space: 12 }) {
      TextInput({ text: this.userName, placeholder: '账号（手机号 / 用户名）' })
        .onChange((value: string) => {
          this.userName = value;
        })
      TextInput({ text: this.password, placeholder: '密码（6~30 位，至少 3 类字符）' })
        .type(InputType.Password)
        .onChange((value: string) => {
          this.password = value;
        })
      Button(this.busy ? '登录中…' : '登录')
        .width('100%')
        .enabled(!this.busy)
        .onClick(() => {
          this.doPasswordLogin();
        })
    }
    .width('100%')
  }

  @Builder
  smsForm() {
    Column({ space: 12 }) {
      TextInput({ text: this.phone, placeholder: '手机号' })
        .type(InputType.PhoneNumber)
        .onChange((value: string) => {
          this.phone = value;
        })
      Row({ space: 8 }) {
        TextInput({ text: this.smsCode, placeholder: '短信验证码' })
          .type(InputType.Number)
          .layoutWeight(1)
          .onChange((value: string) => {
            this.smsCode = value;
          })
        Button('获取验证码')
          .height(40)
          .enabled(!this.busy)
          .backgroundColor('#E9ECEF')
          .fontColor('#111')
          .onClick(() => {
            this.sendCode();
          })
      }
      .width('100%')
      Button(this.busy ? '登录中…' : '登录 / 注册')
        .width('100%')
        .enabled(!this.busy)
        .onClick(() => {
          this.doSmsLogin();
        })
    }
    .width('100%')
  }

  build() {
    Column({ space: 14 }) {
      Blank().layoutWeight(1)
      Text('SCNet').fontSize(30).fontWeight(FontWeight.Bold)
      Text('超算互联网 · 非官方客户端').fontSize(12).fontColor('#8A8F99')
      Blank().height(20)

      Row({ space: 0 }) {
        Text('账号密码')
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
          .padding(10)
          .fontColor(this.mode === 0 ? '#111' : '#8A8F99')
          .backgroundColor(this.mode === 0 ? '#FFFFFF' : '#F1F3F5')
          .borderRadius(8)
          .onClick(() => {
            this.mode = 0;
          })
        Text('短信验证')
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
          .padding(10)
          .fontColor(this.mode === 1 ? '#111' : '#8A8F99')
          .backgroundColor(this.mode === 1 ? '#FFFFFF' : '#F1F3F5')
          .borderRadius(8)
          .onClick(() => {
            this.mode = 1;
          })
      }
      .width('100%')
      .padding(4)
      .backgroundColor('#F1F3F5')
      .borderRadius(10)

      if (this.mode === 0) {
        this.passwordForm()
      } else {
        this.smsForm()
      }

      Row({ space: 6 }) {
        Checkbox()
          .select(this.agreed)
          .onChange((value: boolean) => {
            this.agreed = value;
          })
        Text('我已阅读并同意《用户协议》和《隐私政策》')
          .fontSize(12)
          .fontColor('#6B7280')
          .layoutWeight(1)
      }
      .width('100%')

      if (this.errorMsg.length > 0) {
        Text(this.errorMsg).fontSize(12).fontColor('#C0392B').width('100%')
      }
      if (this.tip.length > 0) {
        Text(this.tip).fontSize(12).fontColor('#0A7EA4').width('100%')
      }
      Blank().layoutWeight(2)
    }
    .width('100%')
    .height('100%')
    .padding({ left: 24, right: 24, top: 40, bottom: 24 })
    .backgroundColor('#F7F8FA')
  }
}
