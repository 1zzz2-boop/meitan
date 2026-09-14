import { router } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { promptAction } from '@kit.ArkUI';
import { apiRegister } from '../services/BackendApi';

const DOMAIN = 0x0000;

// 三端选择
const ROLES: RoleOption[] = [
  { key: 'enterprise', label: '企业端', color: '#FF8C2A', desc: '生产矿井' },
  { key: 'thinktank', label: '智库端', color: '#3DDC84', desc: '科研机构' },
  { key: 'supervision', label: '监管端', color: '#F5C542', desc: '集团安监' }
];

interface RoleOption {
  key: string;
  label: string;
  color: string;
  desc: string;
}

@Entry
@Component
struct RegisterPage {
  @State username: string = '';
  @State password: string = '';
  @State confirmPassword: string = '';
  @State phoneNumber: string = '';
  @State role: string = 'enterprise';
  @State agreeTerms: boolean = false;
  @State isLoading: boolean = false;

  build() {
    Column() {
      // 标题区域
      Column() {
        Text('注册账号')
          .fontSize(32)
          .fontWeight(FontWeight.Bold)
          .fontColor('#333333')
          .margin({ top: 60, bottom: 10 })
        
        Text('创建您的新账号')
          .fontSize(14)
          .fontColor('#999999')
          .margin({ bottom: 40 })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)

      // 注册表单区域
      Column() {
        // 用户名输入框
        this.InputField('👤', '请输入用户名', (value: string) => {
          this.username = value;
        })

        // 选择端角色（企业/智库/监管）
        Column() {
          Row() {
            ForEach(ROLES, (r: RoleOption) => {
              Column({ space: 2 }) {
                Text(r.label)
                  .fontSize(14)
                  .fontColor(this.role === r.key ? '#FFFFFF' : '#666666')
                Text(r.desc)
                  .fontSize(9)
                  .fontColor(this.role === r.key ? '#EEEEEE' : '#999999')
              }
              .layoutWeight(1)
              .padding({ top: 10, bottom: 10 })
              .backgroundColor(this.role === r.key ? r.color : '#F0F0F0')
              .borderRadius(8)
              .onClick(() => {
                this.role = r.key;
              })
            })
          }
          .width('100%')
        }
        .width('90%')
        .margin({ bottom: 16 })

        // 手机号输入框
        this.InputField('📱', '请输入手机号', (value: string) => {
          this.phoneNumber = value;
        })

        // 密码输入框
        this.PasswordInputField('🔒', '请输入密码（至少6位）', (value: string) => {
          this.password = value;
        })

        // 确认密码输入框
        this.PasswordInputField('🔒', '请再次输入密码', (value: string) => {
          this.confirmPassword = value;
        })

        // 用户协议
        Row() {
          Checkbox()
            .select(this.agreeTerms)
            .onChange((isChecked: boolean) => {
              this.agreeTerms = isChecked;
            })
            .margin({ right: 5 })
          
          Text('我已阅读并同意')
            .fontSize(12)
            .fontColor('#666666')
          
          Text('《用户协议》')
            .fontSize(12)
            .fontColor('#007DFF')
            .onClick(() => {
              promptAction.showToast({
                message: '查看用户协议',
                duration: 2000
              });
            })
          
          Text('和')
            .fontSize(12)
            .fontColor('#666666')
          
          Text('《隐私政策》')
            .fontSize(12)
            .fontColor('#007DFF')
            .onClick(() => {
              promptAction.showToast({
                message: '查看隐私政策',
                duration: 2000
              });
            })
        }
        .width('90%')
        .padding({ left: 12, right: 12 })
        .margin({ bottom: 30 })

        // 注册按钮
        Button(this.isLoading ? '注册中...' : '注册')
          .width('90%')
          .height(48)
          .fontSize(16)
          .fontColor(Color.White)
          .backgroundColor(this.canRegister() ? '#007DFF' : '#CCCCCC')
          .enabled(this.canRegister())
          .onClick(() => {
            this.handleRegister();
          })
          .borderRadius(24)
          .margin({ bottom: 16 })
      }
      .width('100%')

      Blank()

      // 返回登录链接
      Row() {
        Text('已有账号？')
          .fontSize(14)
          .fontColor('#666666')
        
        Text('立即登录')
          .fontSize(14)
          .fontColor('#007DFF')
          .onClick(() => {
            router.back();
          })
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .padding({ bottom: 30 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.White)
  }

  // 输入框组件
  @Builder
  InputField(icon: string, placeholder: string, onChange: (value: string) => void) {
    Column() {
      Row() {
        Text(icon)
          .fontSize(20)
          .margin({ right: 10 })
        
        TextInput({ placeholder: placeholder })
          .layoutWeight(1)
          .backgroundColor(Color.Transparent)
          .onChange(onChange)
      }
      .padding(12)
      .borderRadius(8)
      .backgroundColor('#F5F5F5')
    }
    .width('90%')
    .margin({ bottom: 16 })
  }

  // 密码输入框组件
  @Builder
  PasswordInputField(icon: string, placeholder: string, onChange: (value: string) => void) {
    Column() {
      Row() {
        Text(icon)
          .fontSize(20)
          .margin({ right: 10 })
        
        TextInput({ placeholder: placeholder })
          .layoutWeight(1)
          .backgroundColor(Color.Transparent)
          .type(InputType.Password)
          .onChange(onChange)
      }
      .padding(12)
      .borderRadius(8)
      .backgroundColor('#F5F5F5')
    }
    .width('90%')
    .margin({ bottom: 16 })
  }

  // 判断是否可以注册
  private canRegister(): boolean {
    return this.username.length > 0 && 
           this.phoneNumber.length === 11 &&
           this.password.length >= 6 &&
           this.password === this.confirmPassword &&
           this.agreeTerms;
  }

  // 处理注册逻辑（三端 + 真实后端接口）
  private async handleRegister() {
    if (!this.canRegister()) {
      return;
    }

    // 验证密码是否一致
    if (this.password !== this.confirmPassword) {
      promptAction.showToast({
        message: '两次密码输入不一致',
        duration: 2000
      });
      return;
    }

    this.isLoading = true;
    hilog.info(DOMAIN, 'RegisterPage', '开始注册，用户名: %{public}s，端: %{public}s', this.username, this.role);

    try {
      const result = await apiRegister(this.username, this.password, this.role, this.phoneNumber);
      promptAction.showToast({
        message: '注册成功，请返回登录',
        duration: 2000
      });
      // 注册成功返回登录页
      setTimeout(() => {
        router.back();
      }, 1000);
    } catch (err) {
      const msg = (err instanceof Error) ? err.message : '';
      promptAction.showToast({
        message: msg || '注册失败，请确认后端服务已启动',
        duration: 2500
      });
    } finally {
      this.isLoading = false;
    }
  }
}
