/**
 * 公共组件：用户管理 / 系统管理 / 退出登录
 * 供三端 Dashboard 复用，消除三份重复代码。
 * 通过 @Prop 传入端角色名、强调色，主题跟随全局 AppStorage。
 */
import { router } from '@kit.ArkUI';
import { promptAction } from '@kit.ArkUI';
import dataPreferences from '@ohos.data.preferences';
import { Palette, ThemeMode, paletteFor } from '../services/Theme';
import { SystemInfo, apiChangePassword, apiGetSystemInfo, apiUpdateUser } from '../services/BackendApi';

@Component
export struct AccountPanel {
  @Prop mode: number = 5;            // 1=用户管理 2=系统管理，默认系统管理
  @Prop defaultName: string = '用户';
  @Prop roleText: string = '未知端';
  @Prop accent: string = '#FF8C2A';
  @StorageProp('theme_mode') themeMode: number = ThemeMode.NIGHT;

  @State userName: string = '用户';
  @State userId: number = 0;
  @State sessionUsername: string = '';
  @State inputDisplayName: string = '';
  @State inputEndName: string = '';
  @State oldPwd: string = '';
  @State newPwd: string = '';
  @State confirmPwd: string = '';
  @State infoTip: string = '';
  @State pwdTip: string = '';
  @State sysInfo: SystemInfo | null = null;
  @State systemLoading: boolean = false;

  // 昵称保存成功后回调，用于同步父级头部显示名
  onProfileSaved: (name: string) => void = () => { };

  aboutToAppear() {
    this.loadSession();
    if (this.mode === 2) {
      this.loadSystemInfo();
    }
  }

  private pal(): Palette {
    return paletteFor(this.themeMode as ThemeMode);
  }

  private async loadSession() {
    try {
      const ctx = getContext(this);
      const prefs = await dataPreferences.getPreferences(ctx, 'user_session');
      this.userName = await prefs.get('displayName', this.defaultName) as string;
      this.sessionUsername = await prefs.get('username', '') as string;
      this.userId = await prefs.get('userId', 0) as number;
      this.inputDisplayName = this.userName;
      this.inputEndName = await prefs.get('endName', '') as string;
    } catch (e) {
      this.userName = this.defaultName;
    }
  }

  private doLogout() {
    this.clearSession();
    router.clear();
    router.replaceUrl({ url: 'pages/LoginPage' });
  }

  private async clearSession() {
    try {
      const ctx = getContext(this);
      const prefs = await dataPreferences.getPreferences(ctx, 'user_session');
      await prefs.clear();
      await prefs.flush();
    } catch (e) {
      console.log('AccountPanel 清除会话失败: ' + JSON.stringify(e));
    }
  }

  build() {
    if (this.mode === 1) {
      this.UserManager()
    } else {
      this.SystemManager()
    }
  }

  // ================= 用户管理 =================
  @Builder
  UserManager() {
    Scroll() {
      Column() {
        Text('👤 用户信息')
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.pal().textMain)
        Column() {
          Row() {
            Text('用户名')
              .fontSize(13)
              .fontColor(this.pal().textDim)
              .layoutWeight(1)
            Text(this.sessionUsername)
              .fontSize(13)
              .fontColor(this.pal().textMain)
          }
          .width('100%')
          Row() {
            Text('角色')
              .fontSize(13)
              .fontColor(this.pal().textDim)
              .layoutWeight(1)
            Text(this.roleText)
              .fontSize(13)
              .fontColor(this.accent)
          }
          .width('100%')
          .margin({ top: 10 })
          Text('昵称')
            .fontSize(12)
            .fontColor(this.pal().textDim)
            .margin({ top: 12 })
          TextInput({ text: this.inputDisplayName, placeholder: '请输入昵称' })
            .width('100%')
            .backgroundColor(this.pal().field)
            .borderRadius(8)
            .fontColor(this.pal().textMain)
            .placeholderColor(this.pal().placeholder)
            .onChange((v: string) => this.inputDisplayName = v)
          Text('所属端')
            .fontSize(12)
            .fontColor(this.pal().textDim)
            .margin({ top: 12 })
          TextInput({ text: this.inputEndName, placeholder: '请输入所属端名称' })
            .width('100%')
            .backgroundColor(this.pal().field)
            .borderRadius(8)
            .fontColor(this.pal().textMain)
            .placeholderColor(this.pal().placeholder)
            .onChange((v: string) => this.inputEndName = v)
          if (this.infoTip.length > 0) {
            Text(this.infoTip)
              .fontSize(11)
              .fontColor(this.infoTip.indexOf('成功') >= 0 ? this.accent : '#E5484D')
              .margin({ top: 8 })
          }
          Button('保存用户信息')
            .width('100%')
            .height(42)
            .backgroundColor(this.accent)
            .fontColor(this.pal().textMain)
            .borderRadius(21)
            .margin({ top: 14 })
            .onClick(() => this.saveProfile())
        }
        .width('100%')
        .padding(14)
        .backgroundColor(this.pal().card)
        .borderRadius(14)
        .margin({ top: 10 })

        Text('🔒 修改密码')
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.pal().textMain)
          .margin({ top: 18 })
        Column() {
          TextInput({ text: this.oldPwd, placeholder: '原密码' })
            .type(InputType.Password)
            .width('100%')
            .backgroundColor(this.pal().field)
            .borderRadius(8)
            .fontColor(this.pal().textMain)
            .placeholderColor(this.pal().placeholder)
            .onChange((v: string) => this.oldPwd = v)
          TextInput({ text: this.newPwd, placeholder: '新密码（至少 6 位）' })
            .type(InputType.Password)
            .width('100%')
            .backgroundColor(this.pal().field)
            .borderRadius(8)
            .fontColor(this.pal().textMain)
            .placeholderColor(this.pal().placeholder)
            .margin({ top: 10 })
            .onChange((v: string) => this.newPwd = v)
          TextInput({ text: this.confirmPwd, placeholder: '确认新密码' })
            .type(InputType.Password)
            .width('100%')
            .backgroundColor(this.pal().field)
            .borderRadius(8)
            .fontColor(this.pal().textMain)
            .placeholderColor(this.pal().placeholder)
            .margin({ top: 10 })
            .onChange((v: string) => this.confirmPwd = v)
          if (this.pwdTip.length > 0) {
            Text(this.pwdTip)
              .fontSize(11)
              .fontColor(this.pwdTip.indexOf('成功') >= 0 ? this.accent : '#E5484D')
              .margin({ top: 8 })
          }
          Button('确认修改密码')
            .width('100%')
            .height(42)
            .backgroundColor(this.pal().card)
            .fontColor(this.pal().textMain)
            .borderRadius(21)
            .margin({ top: 14 })
            .onClick(() => this.changePassword())
        }
        .width('100%')
        .padding(14)
        .backgroundColor(this.pal().card)
        .borderRadius(14)
        .margin({ top: 10 })

        Button('退出登录')
          .width('100%')
          .height(46)
          .backgroundColor(this.pal().accentSoft)
          .fontColor('#E5484D')
          .borderRadius(23)
          .margin({ top: 20 })
          .onClick(() => this.doLogout())
      }
      .width('100%')
      .padding(12)
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
  }

  // ================= 系统管理 =================
  @Builder
  SystemManager() {
    Scroll() {
      Column() {
        Row() {
          Text('⚙️ 系统信息')
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.pal().textMain)
          Blank()
          Button('刷新')
            .fontSize(12)
            .backgroundColor(this.pal().card)
            .fontColor(this.accent)
            .borderRadius(14)
            .height(28)
            .onClick(() => this.loadSystemInfo())
        }
        .width('100%')
        .margin({ top: 4 })

        if (this.sysInfo !== null) {
          Column() {
            this.sysRow('系统名称', this.sysInfo!.name)
            this.sysRow('软件版本', this.sysInfo!.version)
            this.sysRow('构建日期', this.sysInfo!.build)
            this.sysRow('运行平台', this.sysInfo!.platform)
            this.sysRow('Node.js', this.sysInfo!.nodeVersion)
            this.sysRow('数据库', this.sysInfo!.database)
            this.sysRow('鸿蒙SDK', this.sysInfo!.apiSdkVersion)
            this.sysRow('服务器时间', this.sysInfo!.serverTime)
            this.sysRow('版权声明', this.sysInfo!.copyright)
          }
          .width('100%')
          .padding(14)
          .backgroundColor(this.pal().card)
          .borderRadius(14)
          .margin({ top: 10 })
        } else {
          Text(this.systemLoading ? '正在获取系统信息...' : '暂无系统信息')
            .fontSize(13)
            .fontColor(this.pal().textDim)
            .padding(24)
        }
      }
      .width('100%')
      .padding(12)
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
  }

  @Builder
  sysRow(label: string, value: string) {
    Row() {
      Text(label)
        .fontSize(12)
        .fontColor(this.pal().textDim)
        .width(84)
      Text(value)
        .fontSize(13)
        .fontColor(this.pal().textMain)
        .layoutWeight(1)
        .textAlign(TextAlign.End)
    }
    .width('100%')
    .padding({ top: 7, bottom: 7 })
  }

  // ================= 逻辑 =================
  private async saveProfile() {
    if (this.userId <= 0) {
      this.infoTip = '当前为离线会话，无法保存用户信息';
      return;
    }
    if (this.inputDisplayName.length === 0) {
      this.infoTip = '昵称不能为空';
      return;
    }
    try {
      await apiUpdateUser(this.userId, this.inputDisplayName, this.inputEndName);
      this.infoTip = '保存成功';
      this.userName = this.inputDisplayName;
      const ctx = getContext(this);
      const prefs = await dataPreferences.getPreferences(ctx, 'user_session');
      await prefs.put('displayName', this.inputDisplayName);
      await prefs.put('endName', this.inputEndName);
      await prefs.flush();
      this.onProfileSaved(this.inputDisplayName);
      promptAction.showToast({ message: '用户信息已保存', duration: 1500 });
    } catch (e) {
      this.infoTip = '保存失败：' + JSON.stringify(e);
    }
  }

  private async changePassword() {
    if (this.outOfSession()) {
      this.pwdTip = '当前为离线会话，请联网后重试';
      return;
    }
    if (this.oldPwd.length === 0 || this.newPwd.length === 0) {
      this.pwdTip = '请填写原密码与新密码';
      return;
    }
    if (this.newPwd !== this.confirmPwd) {
      this.pwdTip = '两次输入的新密码不一致';
      return;
    }
    try {
      const result = await apiChangePassword(this.sessionUsername, this.oldPwd, this.newPwd);
      this.pwdTip = result.message;
      if (result.success) {
        this.oldPwd = '';
        this.newPwd = '';
        this.confirmPwd = '';
        promptAction.showToast({ message: result.message, duration: 2000 });
      }
    } catch (e) {
      this.pwdTip = '修改失败：' + JSON.stringify(e);
    }
  }

  private outOfSession(): boolean {
    return this.userId <= 0 || this.sessionUsername.length === 0;
  }

  private async loadSystemInfo() {
    this.systemLoading = true;
    try {
      const info = await apiGetSystemInfo();
      this.sysInfo = info;
    } catch (e) {
      const now = new Date();
      const fallback: SystemInfo = {
        name: '煤矿顶板灾变智能预警与可视化决策系统',
        version: '2.0.0',
        build: '2026.09.03',
        platform: 'HarmonyOS',
        nodeVersion: '-',
        database: '离线（本地兜底）',
        apiSdkVersion: 'HarmonyOS 6.0.2(22)',
        serverTime: now.toISOString(),
        copyright: '版权所有 © 2026'
      };
      this.sysInfo = fallback;
    }
    this.systemLoading = false;
  }
}