/**
 * 综合风险仪表盘（公共组件）——三端总览驾驶舱复用
 * Canvas 半圆刻度弧 + 风险着色 + 数值中心显示，随全局主题联动。
 */
import { Palette, ThemeMode, paletteFor } from '../services/Theme';

@Component
export struct RiskGauge {
  @Prop risk: number = 0;               // 0~100 风险指数
  @StorageProp('theme_mode') themeMode: number = ThemeMode.NIGHT;

  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);

  private pal(): Palette {
    return paletteFor(this.themeMode as ThemeMode);
  }

  // 风险分级着色：<35 绿 / <70 黄 / 其余红
  private riskColor(): string {
    if (this.risk < 35) {
      return '#3DDC84';
    }
    if (this.risk < 70) {
      return '#F5C542';
    }
    return '#E5484D';
  }

  private draw() {
    const w = 220;
    const h = 120;
    const cx = w / 2;
    const cy = 108;
    const r = 86;
    const ctx = this.ctx;
    ctx.clearRect(0, 0, w, h);
    // 底槽弧
    ctx.strokeStyle = this.pal().field;
    ctx.lineWidth = 12;
    ctx.lineCap = 'round';
    ctx.beginPath();
    ctx.arc(cx, cy, r, Math.PI, 2 * Math.PI);
    ctx.stroke();
    // 风险值弧
    const frac = Math.max(0, Math.min(1, (this.risk || 0) / 100));
    ctx.strokeStyle = this.riskColor();
    ctx.lineWidth = 12;
    ctx.lineCap = 'round';
    ctx.beginPath();
    ctx.arc(cx, cy, r, Math.PI, Math.PI + Math.PI * frac);
    ctx.stroke();
  }

  build() {
    Stack() {
      Canvas(this.ctx)
        .width(220)
        .height(120)
        .onReady(() => this.draw())
      Column() {
        Text(Math.round(this.risk || 0) + '')
          .fontSize(28)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.riskColor())
        Text('风险指数')
          .fontSize(11)
          .fontColor(this.pal().textDim)
          .margin({ top: 2 })
      }
      .align(Alignment.Center)
      .margin({ top: 4 })
    }
    .width('100%')
    .height(124)
    .alignContent(Alignment.Center)
  }
}