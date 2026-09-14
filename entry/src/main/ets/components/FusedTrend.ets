/**
 * 多源融合趋势组件 —— 企业端数据分析
 * 在同一个坐标系上叠加 力(顶板压力) / 位移(巷道形变) / 震动(微震) 三条物理曲线，
 * 展示多源监测数据融合后的演变规律。
 * 数据：以 DataStore 趋势为基准，经确定性变换生成三条物理量序列（离线兜底）。
 */
import { TrendPoint } from '../services/BackendApi';
import { Palette, ThemeMode, paletteFor } from '../services/Theme';

// 三条物理量曲线对应的颜色与中文名
const FORCE_COLOR = '#FF8C2A';
const DISP_COLOR = '#3DDC84';
const VIB_COLOR = '#4A9CFF';

interface FusedSeries {
  label: string;
  unit: string;
  color: string;
  data: number[];   // 归一化 0~100
}

@Component
export struct FusedTrend {
  @Prop trend: TrendPoint[] = [];
  @State showForce: boolean = true;
  @State showDisp: boolean = true;
  @State showVib: boolean = true;
  @StorageProp('theme_mode') themeMode: number = ThemeMode.NIGHT;

  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);

  private pal(): Palette {
    return paletteFor(this.themeMode as ThemeMode);
  }

  // 由趋势基准值生成三条物理量序列并各自归一化到 0~100
  private series(): FusedSeries[] {
    const n = this.trend.length;
    const base: number[] = new Array<number>(n);
    for (let i = 0; i < n; i++) {
      base[i] = this.trend[i] ? this.trend[i].value : 50;
    }
    // 确定性变换：力=基准；位移=基准*0.6+20（带有基线抬升）；震动=基准*1.25-15（波动更大）
    const force = this.normalize(base.map((b: number) => b));
    const disp = this.normalize(base.map((b: number) => b * 0.6 + 20));
    const vib = this.normalize(base.map((b: number) => b * 1.25 - 15));
    return [
      { label: '力 / 顶板压力', unit: 'kN', color: FORCE_COLOR, data: force },
      { label: '位移 / 巷道形变', unit: 'mm', color: DISP_COLOR, data: disp },
      { label: '震动 / 微震强度', unit: 'm/s²', color: VIB_COLOR, data: vib }
    ];
  }

  // 最小-最大归一化到 0~100，全等值时归零
  private normalize(arr: number[]): number[] {
    if (arr.length === 0) {
      return [];
    }
    let min = arr[0];
    let max = arr[0];
    for (let i = 1; i < arr.length; i++) {
      if (arr[i] < min) min = arr[i];
      if (arr[i] > max) max = arr[i];
    }
    const span = max - min;
    const out: number[] = new Array<number>(arr.length);
    if (span <= 0.0001) {
      for (let i = 0; i < arr.length; i++) out[i] = 50;
      return out;
    }
    for (let i = 0; i < arr.length; i++) {
      out[i] = ((arr[i] - min) / span) * 100;
    }
    return out;
  }

  private draw() {
    const w = 340;
    const h = 180;
    const padL = 24;
    const padR = 12;
    const padT = 16;
    const padB = 24;
    const ctx = this.ctx;
    ctx.clearRect(0, 0, w, h);

    const series = this.series();
    const visible = (f: FusedSeries): boolean => {
      if (f.color === FORCE_COLOR) return this.showForce;
      if (f.color === DISP_COLOR) return this.showDisp;
      return this.showVib;
    };

    // 网格
    ctx.strokeStyle = this.pal().accentSoft;
    ctx.lineWidth = 1;
    for (let g = 0; g <= 4; g++) {
      const y = padT + (h - padT - padB) * (g / 4);
      ctx.beginPath();
      ctx.moveTo(padL, y);
      ctx.lineTo(w - padR, y);
      ctx.stroke();
    }

    // 各可见曲线
    for (let s = 0; s < series.length; s++) {
      const f = series[s];
      if (!visible(f) || f.data.length < 2) {
        continue;
      }
      const len = f.data.length;
      const stepX = (w - padL - padR) / (len - 1);
      ctx.strokeStyle = f.color;
      ctx.lineWidth = 2;
      ctx.beginPath();
      for (let i = 0; i < len; i++) {
        const x = padL + i * stepX;
        const y = padT + (h - padT - padB) * ((100 - f.data[i]) / 100);
        if (i === 0) {
          ctx.moveTo(x, y);
        } else {
          ctx.lineTo(x, y);
        }
      }
      ctx.stroke();
    }
  }

  @Builder
  LegendItem(color: string, label: string, on: boolean, key: string) {
    Row() {
      Row()
        .width(10)
        .height(10)
        .borderRadius(3)
        .backgroundColor(on ? color : this.pal().accentSoft)
      Text(label)
        .fontSize(11)
        .fontColor(on ? this.pal().textMain : this.pal().textDim)
        .margin({ left: 5 })
    }
    .padding({ left: 8, right: 8, top: 4, bottom: 4 })
    .borderRadius(8)
    .backgroundColor(this.pal().field)
    .onClick(() => {
      if (key === 'force') this.showForce = !this.showForce;
      if (key === 'disp') this.showDisp = !this.showDisp;
      if (key === 'vib') this.showVib = !this.showVib;
    })
  }

  build() {
    Column() {
      Canvas(this.ctx)
        .width('100%')
        .height(180)
        .onReady(() => this.draw())

      Row({ space: 8 }) {
        this.LegendItem(FORCE_COLOR, '力', this.showForce, 'force')
        this.LegendItem(DISP_COLOR, '位移', this.showDisp, 'disp')
        this.LegendItem(VIB_COLOR, '震动', this.showVib, 'vib')
        Blank()
        Text(this.trend.length + ' 点')
          .fontSize(10)
          .fontColor(this.pal().textDim)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .margin({ top: 8 })
    }
    .width('100%')
  }
}