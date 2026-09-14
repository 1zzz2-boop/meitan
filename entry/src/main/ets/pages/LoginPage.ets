/**
 * 登录页 —— 矿工橙 + 深岩灰 工业监测风
 * 集成"三端"角色登录：企业端 / 智库端 / 监管端，三种不同的登录主题效果
 */
import { router } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { promptAction } from '@kit.ArkUI';
import dataPreferences from '@ohos.data.preferences';
import { apiLogin, apiCaptcha, BackendUser, setAuthToken } from '../services/BackendApi';
import { Palette, ThemeMode, paletteFor, modeLabel, ensureThemeInit, switchThemeMode, BRAND_ACCENT_DIM, SEM_GREEN } from '../services/Theme';
import { MineIcon } from '../components/MineIcon';

const DOMAIN = 0x0000;
const PREFERENCES_NAME = 'user_login_info';

// 三端角色定义（角色色与 PC 端三端卡片语义一致：企业=橙 / 智库=绿 / 监管=黄）
interface RoleItem {
  key: string;
  label: string;
  accent: string;
  sceneIcon: string;
  tagline: string;
  welcome: string;
}

@Entry
@Component
struct LoginPage {
  @State roles: RoleItem[] = [
    { key: 'enterprise', label: '企业端', accent: '#FF8C2A',
      tagline: '生产矿井 · 顶板安全与设备监测', welcome: '进入矿区生产监测', sceneIcon: 'mine' },
    { key: 'thinktank', label: '智库端', accent: '#3DDC84',
      tagline: '科研机构 · 数据分析与风险评估', welcome: '进入决策分析中心', sceneIcon: 'cap' },
    { key: 'supervision', label: '监管端', accent: '#F5C542',
      tagline: '集团与安监部门 · 远程指挥与预警', welcome: '进入监管指挥中心', sceneIcon: 'gov' }
  ];
  @State roleIndex: number = 0;
  @State accentColor: string = '#FF8C2A';

  @State username: string = '';
  @State password: string = '';
  @State rememberPassword: boolean = false;
  @State captchaId: string = '';
  @State captchaCode: string = '';
  @State captchaInput: string = '';
  @State isLoading: boolean = false;
  @StorageProp('theme_mode') themeMode: number = ThemeMode.NIGHT;

  aboutToAppear() {
    ensureThemeInit(getContext(this));
    this.fetchCaptcha();
    this.loadSavedLoginInfo();
  }

  private pal(): Palette {
    return paletteFor(this.themeMode as ThemeMode);
  }

  private toggleTheme() {
    switchThemeMode(getContext(this));
  }

  private switchRole(index: number) {
    this.roleIndex = index;
    this.accentColor = this.roles[index].accent;
  }

  // 加载保存的登录信息
  private async loadSavedLoginInfo() {
    try {
      const context = getContext(this);
      const preferences = await dataPreferences.getPreferences(context, PREFERENCES_NAME);
      const savedUsername = await preferences.get('username', '');
      const savedPassword = await preferences.get('password', '');
      const savedRemember = await preferences.get('rememberPassword', false);
      if (savedRemember) {
        this.username = savedUsername as string;
        this.password = savedPassword as string;
        this.rememberPassword = savedRemember as boolean;
      }
    } catch (err) {
      hilog.error(DOMAIN, 'LoginPage', '加载登录信息失败: %{public}s', JSON.stringify(err));
    }
  }

  // 保存登录信息
  private async saveLoginInfo() {
    try {
      const context = getContext(this);
      const preferences = await dataPreferences.getPreferences(context, PREFERENCES_NAME);
      if (this.rememberPassword) {
        await preferences.put('username', this.username);
        await preferences.put('password', this.password);
        await preferences.put('rememberPassword', true);
      } else {
        await preferences.put('username', '');
        await preferences.put('password', '');
        await preferences.put('rememberPassword', false);
      }
      await preferences.flush();
    } catch (err) {
      hilog.error(DOMAIN, 'LoginPage', '保存登录信息失败: %{public}s', JSON.stringify(err));
    }
  }

  // 获取验证码（服务端生成并校验）
  private async fetchCaptcha() {
    try {
      const cap = await apiCaptcha();
      this.captchaId = cap.captchaId;
      this.captchaCode = cap.code;
    } catch (err) {
      hilog.error(DOMAIN, 'LoginPage', '获取验证码失败: %{public}s', JSON.stringify(err));
    }
    this.captchaInput = '';
  }

  // 验证码字符随机颜色（工业场景低饱和度配色）
  private captchaCharColor(): string {
    const colors: string[] = ['#FF8C2A', '#2F7CFF', '#3DDC84', '#F5C542', '#E24A6B', '#9B6BFF'];
    return colors[Math.floor(Math.random() * colors.length)];
  }

  build() {
    Stack() {
      // 矿井氛围背景
      Column() {
        // 底部岩层（实体质感，无光晕）
        Column()
          .width('100%')
          .height(120)
          .linearGradient({
            angle: 180,
            colors: [['#0016161B', 0], ['#2E1F2126', 1]]
          })
          .position({ y: '100%' })
          .translate({ y: -120 })
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.pal().bgApp)

      Scroll() {
        Column() {
          // ===== 顶部品牌区（统一品牌名） =====
          Column() {
            Row() {
              MineIcon({ name: 'pick', size: 18, color: this.accentColor })
                .margin({ right: 8 })
              Text('深地智控 · 煤矿顶板智能预警平台')
                .fontSize(12)
                .fontColor(this.pal().textDim)
                .letterSpacing(1)
              Blank()
              Text(modeLabel())
                .fontSize(12)
                .fontColor(this.accentColor)
                .onClick(() => this.toggleTheme())
            }

            Text('安全监测与可视化决策平台')
              .fontSize(28)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.pal().textMain)
              .margin({ top: 14, bottom: 12 })

            // 工业感下划线
            Row() {
              Row()
                .width(34)
                .height(3)
                .borderRadius(1)
                .backgroundColor(this.accentColor)
              Row()
                .width(18)
                .height(3)
                .borderRadius(1)
                .backgroundColor('#4DFFFFFF')
                .margin({ left: 6 })
            }

            Text(this.roles[this.roleIndex].tagline)
              .fontSize(12)
              .fontColor(this.pal().textDim)
              .margin({ top: 12 })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding({ left: 22, top: 48 })

          // ===== 三端选择 =====
          Row() {
            ForEach(this.roles, (role: RoleItem, index: number) => {
              Column() {
                MineIcon({ name: role.sceneIcon, size: 16, color: this.roleIndex === index ? role.accent : this.pal().textDim })
                Text(role.label)
                  .fontSize(12)
                  .fontWeight(this.roleIndex === index ? FontWeight.Bold : FontWeight.Normal)
                  .fontColor(this.roleIndex === index ? role.accent : this.pal().textDim)
                  .margin({ top: 4 })
                Row()
                  .width(22)
                  .height(2)
                  .borderRadius(1)
                  .backgroundColor(this.roleIndex === index ? role.accent : Color.Transparent)
                  .margin({ top: 6 })
              }
              .layoutWeight(1)
              .padding({ top: 10, bottom: 10 })
              .onClick(() => this.switchRole(index))
            })
          }
          .width('94%')
          .backgroundColor(this.pal().card)
          .borderRadius(10)
          .border({ width: 1, color: '#232A35' })
          .padding(6)
          .margin({ top: 26 })

          // ===== 登录卡片 =====
          Column() {
            Row() {
              Row()
                .width(3)
                .height(15)
                .borderRadius(1)
                .backgroundColor(this.accentColor)
              Text(this.roles[this.roleIndex].welcome)
                .fontSize(15)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.pal().textMain)
                .margin({ left: 8 })
            }
            .alignSelf(ItemAlign.Start)
            .margin({ bottom: 16 })

            // 用户名输入框
            Row() {
              MineIcon({ name: 'user', size: 16, color: this.pal().textDim })
                .margin({ right: 10 })
              TextInput({ placeholder: '请输入用户名/手机号', text: this.username })
                .layoutWeight(1)
                .backgroundColor(Color.Transparent)
                .fontColor(this.pal().textMain)
                .placeholderColor(this.pal().placeholder)
                .onChange((value: string) => this.username = value)
            }
            .padding(12)
            .borderRadius(8)
            .backgroundColor(this.pal().field)
            .border({ width: 1, color: '#232A35' })
            .width('100%')
            .margin({ bottom: 12 })

            // 密码输入框
            Row() {
              MineIcon({ name: 'lock', size: 16, color: this.pal().textDim })
                .margin({ right: 10 })
              TextInput({ placeholder: '请输入密码', text: this.password })
                .layoutWeight(1)
                .backgroundColor(Color.Transparent)
                .type(InputType.Password)
                .fontColor(this.pal().textMain)
                .placeholderColor(this.pal().placeholder)
                .onChange((value: string) => this.password = value)
            }
            .padding(12)
            .borderRadius(8)
            .backgroundColor(this.pal().field)
            .border({ width: 1, color: '#232A35' })
            .width('100%')
            .margin({ bottom: 8 })

            // 验证码输入框 + 图形验证码
            Row() {
              MineIcon({ name: 'shield', size: 16, color: this.pal().textDim })
                .margin({ right: 10 })
              TextInput({ placeholder: '请输入验证码', text: this.captchaInput })
                .layoutWeight(1)
                .maxLength(4)
                .backgroundColor(Color.Transparent)
                .fontColor(this.pal().textMain)
                .placeholderColor(this.pal().placeholder)
                .onChange((value: string) => this.captchaInput = value)
              this.CaptchaBox()
            }
            .padding(8)
            .borderRadius(8)
            .backgroundColor(this.pal().field)
            .border({ width: 1, color: '#232A35' })
            .width('100%')
            .margin({ bottom: 10 })

            Row() {
              Row() {
                Checkbox()
                  .select(this.rememberPassword)
                  .selectedColor(this.accentColor)
                  .onChange((isChecked: boolean) => this.rememberPassword = isChecked)
                  .margin({ right: 5 })
                Text('记住密码')
                  .fontSize(12)
                  .fontColor(this.pal().textDim)
              }

              Blank()

              Text('忘记密码？')
                .fontSize(12)
                .fontColor(this.accentColor)
                .onClick(() => {
                  router.pushUrl({ url: 'pages/ForgotPasswordPage' });
                })
            }
            .width('100%')
            .padding({ left: 4, right: 4 })
            .margin({ bottom: 22 })

            // 登录按钮（实底 + 细描边 + 按压态，无外发光）
            Button(this.isLoading ? '正在验证...' : '进入监测系统 →')
              .width('100%')
              .height(50)
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.pal().textMain)
              .backgroundColor(this.canLogin() ? this.accentColor : this.pal().accentSoft)
              .enabled(!this.isLoading)
              .borderRadius(8)
              .border({ width: 1, color: 'rgba(255,255,255,0.22)' })
              .stateStyles({
                pressed: {
                  backgroundColor: BRAND_ACCENT_DIM
                }
              })
              .onClick(() => this.handleLogin())

            // 第三方登录
            Row() {
              Row()
                .layoutWeight(1)
                .height(1)
                .backgroundColor('#26FFFFFF')
              Text('  其他登录方式  ')
                .fontSize(11)
                .fontColor(this.pal().textDim)
              Row()
                .layoutWeight(1)
                .height(1)
                .backgroundColor('#26FFFFFF')
            }
            .width('100%')
            .margin({ top: 20 })

            Row() {
              this.ThirdPartyLoginIcon('微信', '#2C8C5F')
              this.ThirdPartyLoginIcon('QQ', '#2E7BB5')
              this.ThirdPartyLoginIcon('华为', '#C8302F')
            }
            .width('70%')
            .justifyContent(FlexAlign.SpaceAround)
            .margin({ top: 12 })
          }
          .width('88%')
          .padding(20)
          .backgroundColor(this.pal().card)
          .borderRadius(10)
          .border({ width: 1, color: '#232A35' })
          .margin({ top: 18 })

          // ===== 实时状态标签（紧凑） =====
          Row() {
            this.StatusTag('VR巡检', '12路在线', this.accentColor)
            this.StatusTag('传感网络', '87节点', '#2F7CFF')
            this.StatusTag('智能预警', '0条告警', '#3DDC84')
          }
          .width('88%')
          .justifyContent(FlexAlign.SpaceBetween)
          .margin({ top: 18 })

          // ===== 底部 =====
          Column() {
            Row() {
              Circle()
                .width(7)
                .height(7)
                .fill(SEM_GREEN)
                .margin({ right: 6 })
              Text('系统运行中 · 数据实时同步')
                .fontSize(11)
                .fontColor(this.pal().textDim)
            }
            .margin({ bottom: 14 })

            Row() {
              Text('还没有账号？')
                .fontSize(13)
                .fontColor(this.pal().textDim)
              Text('立即注册')
                .fontSize(13)
                .fontColor(this.accentColor)
                .onClick(() => {
                  router.pushUrl({ url: 'pages/RegisterPage' });
                })
            }
          }
          .width('100%')
          .alignItems(HorizontalAlign.Center)
          .padding({ top: 22, bottom: 36 })
        }
        .width('100%')
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.pal().bgApp)
  }

  // 状态标签
  @Builder
  StatusTag(label: string, value: string, color: string) {
    Column() {
      Text(label)
        .fontSize(10)
        .fontColor(this.pal().textDim)
      Text(value)
        .fontSize(13)
        .fontWeight(FontWeight.Bold)
        .fontColor(color)
        .margin({ top: 2 })
    }
    .layoutWeight(1)
    .padding({ top: 10, bottom: 10 })
    .backgroundColor(this.pal().headerBg)
    .borderRadius(6)
    .border({ width: 1, color: '#232A35' })
    .margin({ left: 4, right: 4 })
  }

  // 图形验证码展示框（点击刷新）
  @Builder
  CaptchaBox() {
    Column() {
      Row({ space: 1 }) {
        ForEach(this.captchaCode.split(''), (ch: string, index: number) => {
          Text(ch)
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.captchaCharColor())
            .width(21)
            .height(26)
            .textAlign(TextAlign.Center)
            .align(Alignment.Center)
        }, (ch: string, index: number): string => index.toString())
      }
      Text('刷新')
        .fontSize(8)
        .fontColor(this.pal().textDim)
        .margin({ top: 1 })
    }
    .width(92)
    .height(38)
    .justifyContent(FlexAlign.Center)
    .backgroundColor(this.pal().card)
    .borderRadius(6)
    .border({ width: 1, color: '#26FF8C2A' })
    .onClick(() => this.fetchCaptcha())
  }

  // 判断是否可以登录
  private canLogin(): boolean {
    return this.username.length > 0 && this.password.length >= 6;
  }

  // 处理登录逻辑（按三端角色分流）
  private async handleLogin() {
    if (this.isLoading) {
      return;
    }
    // 分层校验：先账号、再密码、最后验证码，不同错误给出不同提示
    if (this.username.trim().length === 0) {
      promptAction.showToast({ message: '请输入用户名/手机号', duration: 1500 });
      return;
    }
    if (this.password.length === 0) {
      promptAction.showToast({ message: '请输入密码', duration: 1500 });
      return;
    }
    if (this.password.length < 6) {
      promptAction.showToast({ message: '密码至少需要 6 位', duration: 1500 });
      return;
    }
    if (this.captchaInput.trim().length === 0) {
      promptAction.showToast({ message: '请输入验证码', duration: 1500 });
      return;
    }
    if (this.captchaId.length === 0) {
      promptAction.showToast({ message: '验证码加载中，请稍后再试', duration: 1500 });
      this.fetchCaptcha();
      return;
    }

    this.isLoading = true;
    hilog.info(DOMAIN, 'LoginPage', '开始登录，用户名: %{public}s，角色: %{public}s',
      this.username, this.roles[this.roleIndex].label);

    let user: BackendUser | null = null;
    const raw = await apiLogin(this.username, this.password, this.captchaId, this.captchaInput);
    if (raw.ok) {
      // 服务端签发会话令牌，由 BackendApi 记录并随请求携带
      setAuthToken(raw.token);
      user = raw.user;
    } else if (raw.captchaRejected) {
      // 服务端判定验证码错误/过期 → 刷新验证码并请用户重试
      this.isLoading = false;
      this.fetchCaptcha();
      promptAction.showToast({ message: raw.message || '验证码错误，请重新输入', duration: 2000 });
      return;
    } else if (raw.credentialRejected) {
      // 后端可达但账号/密码错误 → 明确拒绝，并刷新验证码避免继续被卡
      this.isLoading = false;
      this.fetchCaptcha();
      promptAction.showToast({ message: '用户名或密码错误，请重试', duration: 2000 });
      return;
    } else {
      // 后端不可达（无会话兜底）→ 拒绝登录，提示检查网络/服务
      this.isLoading = false;
      promptAction.showToast({ message: raw.message || '后端服务不可达，请检查网络后重试', duration: 2000 });
      return;
    }

    await this.saveLoginInfo();
    await this.saveSessionUser(user, raw.token);
    const endLabel = this.roles[this.roleIndex].label;
    promptAction.showToast({
      message: `${endLabel}登录成功，欢迎 ` + (user.displayName || user.username),
      duration: 2000
    });
    setTimeout(() => {
      router.replaceUrl({ url: this.dashboardUrl() });
    }, 800);
    this.isLoading = false;
  }

  // 三端分流：企业端 / 智库端 / 监管端 各自独立功能主页
  private dashboardUrl(): string {
    if (this.roleIndex === 1) return 'pages/ThinkTankDashboard';
    if (this.roleIndex === 2) return 'pages/SupervisionDashboard';
    return 'pages/EnterpriseDashboard';
  }

  // 保存会话用户信息（含三端角色与令牌）
  private async saveSessionUser(user: BackendUser, token: string): Promise<void> {
    try {
      const context = getContext(this);
      const preferences = await dataPreferences.getPreferences(context, 'user_session');
      await preferences.put('userId', user.id);
      await preferences.put('username', user.username);
      await preferences.put('displayName', user.displayName || user.username);
      await preferences.put('role', user.role);
      await preferences.put('endKey', this.roles[this.roleIndex].key);
      await preferences.put('endName', this.roles[this.roleIndex].label);
      await preferences.put('token', token);
      await preferences.flush();
    } catch (err) {
      hilog.error(DOMAIN, 'LoginPage', '保存会话失败: %{public}s', JSON.stringify(err));
    }
  }

  // 第三方登录图标
  @Builder
  ThirdPartyLoginIcon(name: string, color: string) {
    Column() {
      Text(name.substring(0, 1))
        .fontSize(16)
        .fontColor(color)
        .fontWeight(FontWeight.Bold)
    }
    .width(42)
    .height(42)
    .justifyContent(FlexAlign.Center)
    .backgroundColor(this.pal().field)
    .borderRadius(21)
    .onClick(() => {
      router.pushUrl({ url: 'pages/ThirdPartyAuthPage', params: { provider: name } });
    })
  }
}
