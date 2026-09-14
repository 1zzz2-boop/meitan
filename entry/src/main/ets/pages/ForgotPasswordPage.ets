import { router } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { promptAction } from '@kit.ArkUI';

const DOMAIN = 0x0000;

@Entry
@Component
struct ForgotPasswordPage {
  @State username: string = '';
  @State newPassword: string = '';
  @State confirmPassword: string = '';
  @State isLoading: boolean = false;

  build() {
    Column() {
      // 顶部导航栏
      Row() {
        Button('‹')
          .width(36)
          .height(36)
          .fontSize(22)
          .fontColor(Color.White)
          .backgroundColor('#33FFFFFF')
          .borderRadius(18)
          .onClick(() => router.back())
        Blank()
        Text('重置密码')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.White)
        Blank()
        Text('🔑')
          .fontSize(22)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 48, bottom: 16 })
      .linearGradient({
        angle: 180,
        colors: [
          ['#1B3B6F', 0.0],
          ['#2B63C6', 0.6],
          ['#147BDB', 1.0]
        ]
      })
      .margin({ bottom: 40 })

      // 表单
      Column() {
        Text('设置新密码')
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor('#1F2329')
          .alignSelf(ItemAlign.Start)

        Text('请输入账号并设置新密码，重置后使用新密码登录')
          .fontSize(13)
          .fontColor('#999999')
          .alignSelf(ItemAlign.Start)
          .margin({ top: 6, bottom: 28 })

        this.InputField('👤', '请输入用户名/手机号', (v: string) => this.username = v, false)
        this.InputField('🔑', '请输入新密码（至少6位）', (v: string) => this.newPassword = v, true)
        this.InputField('🔒', '请再次确认新密码', (v: string) => this.confirmPassword = v, true)

        Button(this.isLoading ? '提交中...' : '确认重置')
          .width('100%')
          .height(48)
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.White)
          .backgroundColor(this.canSubmit() ? '#147BDB' : '#B9C8DE')
          .enabled(this.canSubmit())
          .borderRadius(24)
          .margin({ top: 30 })
          .onClick(() => this.handleReset())
      }
      .width('86%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F4F6FB')
  }

  @Builder
  InputField(icon: string, placeholder: string, onChange: (v: string) => void, isPassword: boolean) {
    Row() {
      Text(icon)
        .fontSize(18)
        .margin({ right: 10 })
      TextInput({ placeholder })
        .layoutWeight(1)
        .backgroundColor(Color.Transparent)
        .type(isPassword ? InputType.Password : InputType.Normal)
        .fontColor('#1F2329')
        .placeholderColor('#B0B7C3')
        .onChange(onChange)
    }
    .width('100%')
    .padding(14)
    .backgroundColor(Color.White)
    .borderRadius(12)
    .margin({ bottom: 16 })
  }

  private canSubmit(): boolean {
    return this.username.length > 0 &&
      this.newPassword.length >= 6 &&
      this.newPassword === this.confirmPassword;
  }

  private handleReset() {
    if (this.newPassword !== this.confirmPassword) {
      promptAction.showToast({ message: '两次输入的新密码不一致', duration: 2000 });
      return;
    }
    this.isLoading = true;
    // 模拟重置请求
    setTimeout(() => {
      this.isLoading = false;
      promptAction.showDialog({
        title: '重置成功',
        message: '密码已重置，请使用新密码登录',
        buttons: [{ text: '返回登录', color: '#007DFF' }]
      }).then(() => {
        router.replaceUrl({ url: 'pages/LoginPage' });
      });
    }, 1200);
  }
}