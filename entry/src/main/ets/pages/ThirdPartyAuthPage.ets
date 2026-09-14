import { router } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { promptAction } from '@kit.ArkUI';

const DOMAIN = 0x0000;

@Entry
@Component
struct ThirdPartyAuthPage {
  @State provider: string = '微信';
  @State loading: boolean = false;

  private providerColors: Record<string, string> = {
    '微信': '#07C160',
    'QQ': '#12B7F5',
    '华为': '#E8362D'
  };

  aboutToAppear() {
    const params = router.getParams() as Record<string, string>;
    if (params && params.provider) {
      this.provider = params.provider;
    }
    hilog.info(DOMAIN, 'ThirdPartyAuthPage', '第三方授权页打开: %{public}s', this.provider);
  }

  private getColor(): string {
    return this.providerColors[this.provider] || '#007DFF';
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      // 授权页面主内容
      Column() {
        Blank()

        // 品牌 Logo
        Column() {
          Column() {
            Text(this.provider.charAt(0))
              .fontSize(30)
              .fontWeight(FontWeight.Bold)
              .fontColor(Color.White)
          }
          .width(64)
          .height(64)
          .justifyContent(FlexAlign.Center)
          .backgroundColor(this.getColor())
          .borderRadius(32)
          .shadow({ radius: 16, color: '#33555555', offsetX: 0, offsetY: 6 })

          Text(this.provider)
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor('#1F2329')
            .margin({ top: 12 })
        }
        .margin({ bottom: 36 })

        // 授权说明
        Column() {
          Row() {
            Column() {
              Text(String('用户').charAt(0))
                .fontSize(20)
                .fontColor('#007DFF')
            }
            .width(48)
            .height(48)
            .justifyContent(FlexAlign.Center)
            .backgroundColor('#E8F3FF')
            .borderRadius(24)

            Text(`${this.provider} · 矿洞智能监测`)
              .fontSize(14)
              .fontColor('#666666')
              .margin({ left: 12 })
          }
          .width('100%')

          Divider()
            .color('#EEEEEE')
            .margin({ top: 18, bottom: 18 })

          Text('矿洞智能监测 申请获得以下权限：')
            .fontSize(13)
            .fontColor('#666666')
            .alignSelf(ItemAlign.Start)

          Column() {
            this.PermissionRow('✅', '获取你的公开信息（用户名、头像）')
            this.PermissionRow('✅', '获知你的账号安全等级')
            this.PermissionRow('✅', '访问你的登录状态')
          }
          .width('100%')
          .margin({ top: 14 })

          Text('我们只会使用上述信息用于登录验证，不会泄露你的隐私。')
            .fontSize(10)
            .fontColor('#BBBBBB')
            .alignSelf(ItemAlign.Start)
            .margin({ top: 14 })
        }
        .width('92%')
        .padding(18)
        .backgroundColor(Color.White)
        .borderRadius(16)
        .shadow({ radius: 20, color: '#22000000', offsetX: 0, offsetY: 8 })
        .margin({ bottom: 30 })

        // 操作按钮
        Column() {
          Button(this.loading ? '授权中...' : `同意并登录`)
            .width('86%')
            .height(48)
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.White)
            .backgroundColor(this.getColor())
            .borderRadius(24)
            .enabled(!this.loading)
            .onClick(() => this.confirmAuth())

          Button('拒绝授权')
            .width('86%')
            .height(48)
            .fontSize(16)
            .fontColor('#999999')
            .backgroundColor('#F5F5F5')
            .borderRadius(24)
            .margin({ top: 12 })
            .onClick(() => router.back())
        }
        .width('100%')
        .margin({ bottom: 40 })
      }
      .width('100%')
      .height('100%')
      .backgroundColor('#F7F8FA')
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  PermissionRow(icon: string, text: string) {
    Row() {
      Text(icon)
        .fontSize(14)
        .margin({ right: 8 })
      Text(text)
        .fontSize(13)
        .fontColor('#333333')
    }
    .width('100%')
    .margin({ top: 8 })
  }

  private confirmAuth() {
    this.loading = true;
    // 模拟第三方授权与登录
    setTimeout(() => {
      this.loading = false;
      promptAction.showToast({
        message: `${this.provider}授权成功`,
        duration: 1500
      });
      setTimeout(() => {
        router.replaceUrl({ url: 'pages/LoginPage' });
      }, 800);
    }, 1200);
  }
}