import { router } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { MineIcon } from '../components/MineIcon';
import { BRAND_ACCENT, BRAND_ACCENT_DIM, SEM_GREEN, SEM_INFO } from '../services/Theme';

const DOMAIN = 0x0000;
const ORANGE = BRAND_ACCENT;
const DEEP_GRAY = '#16171B';
const CARD_GRAY = '#1E2026';
const TEXT_DIM = '#9AA1AB';

@Entry
@Component
struct HomePage {
  @State showContent: boolean = false;
  private tunnelCtx: CanvasRenderingContext2D =
    new CanvasRenderingContext2D(new RenderingContextSettings(true));

  aboutToAppear() {
    setTimeout(() => {
      animateTo({ duration: 650, curve: Curve.EaseOut }, () => {
        this.showContent = true;
      });
    }, 80);
  }

  build() {
    Stack() {
      // 矿井氛围背景（深岩灰，无光晕）
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(DEEP_GRAY)

      Column() {
        // 顶栏：品牌区（统一品牌名）
        Column() {
          Row() {
            MineIcon({ name: 'pick', iconSize: 20, color: ORANGE })
              .margin({ right: 8 })
            Text('深地智控 · 煤矿顶板智能预警平台')
              .fontSize(12)
              .fontColor(TEXT_DIM)
          }
          .alignItems(VerticalAlign.Center)
          .margin({ bottom: 10 })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ left: 24, right: 24, top: 60 })
        .opacity(this.showContent ? 1 : 0)
        .translate({ y: this.showContent ? 0 : -14 })

        Blank()

        // 中央主视觉区
        Column() {
          // 主视觉：矿井巷道剖面实体图形（Canvas 自绘，无发光无光环）
          Stack() {
            Canvas(this.tunnelCtx)
              .width(250)
              .height(150)
              .onReady(() => {
                this.drawTunnel();
              })
          }
          .width(250)
          .height(150)
          .borderRadius(8)
          .border({ width: 1, color: '#26313F' })
          .backgroundColor('#1B1D22')
          .clip(true)
          .margin({ bottom: 22 })

          Text('智慧矿洞 · 主动安全')
            .fontSize(30)
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.White)

          // 工业感下划线
          Row() {
            Row()
              .width(34)
              .height(3)
              .borderRadius(1)
              .backgroundColor(ORANGE)
            Row()
              .width(18)
              .height(3)
              .borderRadius(1)
              .backgroundColor('#4DFFFFFF')
              .margin({ left: 6 })
          }
          .margin({ top: 12, bottom: 12 })

          Text('实时感知井下环境，预警隐患，守护每一位矿工的生命安全')
            .fontSize(14)
            .fontColor(TEXT_DIM)
            .textAlign(TextAlign.Center)
            .margin({ bottom: 26 })
            .padding({ left: 32, right: 32 })

          // 实时状态标签（紧凑、像监控系统）
          Row() {
            this.StatusTag('vr', 'VR巡检', '12路在线', ORANGE)
            this.StatusTag('antenna', '传感网络', '87节点', SEM_INFO)
            this.StatusTag('siren', '智能预警', '0条告警', SEM_GREEN)
          }
          .width('90%')
          .justifyContent(FlexAlign.SpaceBetween)
        }
        .width('100%')
        .opacity(this.showContent ? 1 : 0)
        .translate({ y: this.showContent ? 0 : 22 })

        Blank()

        // 底部操作区
        Column() {
          // 主按钮：实底 + 细描边 + 按压态（无外发光）
          Button('进入监测系统 →')
            .width('82%')
            .height(52)
            .fontSize(17)
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.White)
            .backgroundColor(ORANGE)
            .borderRadius(8)
            .border({ width: 1, color: 'rgba(255,255,255,0.22)' })
            .stateStyles({
              pressed: {
                backgroundColor: BRAND_ACCENT_DIM
              }
            })
            .onClick(() => this.goToLogin())

          Row() {
            Circle()
              .width(7)
              .height(7)
              .fill(SEM_GREEN)
              .margin({ right: 6 })
            Text('系统运行中 · 数据实时同步')
              .fontSize(11)
              .fontColor(TEXT_DIM)
          }
          .margin({ top: 18, bottom: 14 })

          Row() {
            Text('暂无账号？')
              .fontSize(14)
              .fontColor(TEXT_DIM)
            Text('立即注册')
              .fontSize(14)
              .fontColor(ORANGE)
              .fontWeight(FontWeight.Medium)
              .onClick(() => this.goToRegister())
          }
          .margin({ bottom: 26 })
        }
        .width('100%')
        .opacity(this.showContent ? 1 : 0)
        .translate({ y: this.showContent ? 0 : 20 })
      }
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor(DEEP_GRAY)
  }

  // 实时状态标签
  @Builder
  StatusTag(icon: string, title: string, value: string, color: string) {
    Column() {
      Row() {
        MineIcon({ name: icon, iconSize: 13, color: color, strokeWidth: 1.8 })
          .margin({ right: 5 })
        Text(title)
          .fontSize(11)
          .fontColor(TEXT_DIM)
      }
      Text(value)
        .fontSize(13)
        .fontWeight(FontWeight.Bold)
        .fontColor(color)
        .margin({ top: 5 })
    }
    .layoutWeight(1)
    .padding({ top: 12, bottom: 12 })
    .backgroundColor(CARD_GRAY)
    .borderRadius(6)
    .border({ width: 1, color: '#232A35' })
    .margin({ left: 4, right: 4 })
  }

  // 巷道剖面绘制：拱形巷道 + 岩层节理 + 支架立柱 + 顶部测点 + 矿工
  private drawTunnel() {
    const ctx = this.tunnelCtx;
    const W = 250;
    const H = 150;
    const cx = 125;          // 巷道中心 x
    const gy = 128;          // 地面 y
    const R = 54;            // 巷道内腔半径

    ctx.clearRect(0, 0, W, H);

    // 巷道内腔填充
    ctx.beginPath();
    ctx.moveTo(cx - R, gy);
    ctx.lineTo(cx - R, gy - 16);
    ctx.arc(cx, gy, R, Math.PI, 2 * Math.PI, false);
    ctx.lineTo(cx + R, gy);
    ctx.closePath();
    ctx.fillStyle = '#23262D';
    ctx.fill();

    // 内腔描边（信号橙）
    ctx.beginPath();
    ctx.moveTo(cx - R, gy);
    ctx.lineTo(cx - R, gy - 16);
    ctx.arc(cx, gy, R, Math.PI, 2 * Math.PI, false);
    ctx.lineTo(cx + R, gy);
    ctx.strokeStyle = 'rgba(255,140,42,0.75)';
    ctx.lineWidth = 1.6;
    ctx.stroke();

    // 岩层线（同心弧，模拟煤岩分层）
    ctx.strokeStyle = '#3A4149';
    ctx.lineWidth = 1;
    ctx.beginPath();
    ctx.arc(cx, gy, R + 9, Math.PI, 2 * Math.PI, false);
    ctx.stroke();
    ctx.beginPath();
    ctx.arc(cx, gy, R + 18, Math.PI, 2 * Math.PI, false);
    ctx.stroke();
    ctx.beginPath();
    ctx.arc(cx, gy, R + 27, Math.PI, 2 * Math.PI, false);
    ctx.stroke();

    // 节理纹理（短斜线）
    ctx.strokeStyle = 'rgba(152,162,179,0.28)';
    ctx.beginPath();
    ctx.moveTo(cx - R + 4, gy - R - 8); ctx.lineTo(cx - R + 10, gy - R - 16);
    ctx.moveTo(cx - R + 22, gy - R - 18); ctx.lineTo(cx - R + 28, gy - R - 26);
    ctx.moveTo(cx + R - 14, gy - R - 12); ctx.lineTo(cx + R - 8, gy - R - 20);
    ctx.moveTo(cx + R - 30, gy - R - 22); ctx.lineTo(cx + R - 24, gy - R - 30);
    ctx.stroke();

    // 支架立柱（U 型钢，两侧）
    ctx.strokeStyle = '#5C6675';
    ctx.lineWidth = 3;
    ctx.beginPath();
    ctx.moveTo(cx - R + 5, gy);
    ctx.lineTo(cx - R + 5, gy - 24);
    ctx.moveTo(cx + R - 5, gy);
    ctx.lineTo(cx + R - 5, gy - 24);
    ctx.stroke();

    // 顶板测点（3 个橙色圆点 + 十字）
    const pts = [
      [cx - R * 0.62, gy - R * 0.5],
      [cx, gy - R - 4],
      [cx + R * 0.62, gy - R * 0.5]
    ];
    ctx.fillStyle = '#FF8C2A';
    pts.forEach((p: number[]) => {
      ctx.beginPath();
      ctx.arc(p[0], p[1], 2.6, 0, 2 * Math.PI, false);
      ctx.fill();
    });
    ctx.strokeStyle = 'rgba(255,140,42,0.5)';
    ctx.lineWidth = 1;
    pts.forEach((p: number[]) => {
      ctx.beginPath();
      ctx.moveTo(p[0] - 4.5, p[1]);
      ctx.lineTo(p[0] + 4.5, p[1]);
      ctx.moveTo(p[0], p[1] - 4.5);
      ctx.lineTo(p[0], p[1] + 4.5);
      ctx.stroke();
    });

    // 地面
    ctx.strokeStyle = '#39424F';
    ctx.lineWidth = 1.5;
    ctx.beginPath();
    ctx.moveTo(cx - R - 34, gy);
    ctx.lineTo(cx + R + 34, gy);
    ctx.stroke();

    // 矿工（安全帽 + 头 + 工装 + 腿）
    const mx = cx;
    const my = gy - 2;
    ctx.strokeStyle = '#CFD9E8';
    ctx.lineWidth = 2;
    ctx.beginPath();
    // 帽
    ctx.moveTo(mx - 6, my - 20);
    ctx.quadraticCurveTo(mx, my - 26, mx + 6, my - 20);
    // 头
    ctx.moveTo(mx - 3.2, my - 19);
    ctx.arc(mx, my - 16, 3.2, 0, 2 * Math.PI, false);
    // 身
    ctx.moveTo(mx - 5, my - 13);
    ctx.lineTo(mx + 5, my - 13);
    ctx.moveTo(mx, my - 13);
    ctx.lineTo(mx, my - 5);
    // 腿
    ctx.moveTo(mx, my - 5);
    ctx.lineTo(mx - 4, my - 1);
    ctx.moveTo(mx, my - 5);
    ctx.lineTo(mx + 4, my - 1);
    ctx.stroke();

    // 顶部标签
    ctx.fillStyle = '#5C6675';
    ctx.font = '10px sans-serif';
    ctx.fillText('顶板应力监测 · 巷道剖面', cx - 58, 14);
  }

  // 跳转到登录页
  private goToLogin() {
    router.replaceUrl({
      url: 'pages/LoginPage'
    }).catch((err: Error) => {
      hilog.error(DOMAIN, 'HomePage', '跳转登录页失败: %{public}s', err.message);
    });
  }

  // 跳转到注册页
  private goToRegister() {
    router.pushUrl({
      url: 'pages/RegisterPage'
    }).catch((err: Error) => {
      hilog.error(DOMAIN, 'HomePage', '跳转注册页失败: %{public}s', err.message);
    });
  }
}
