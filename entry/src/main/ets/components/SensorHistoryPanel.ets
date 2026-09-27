/**
 * 传感器历史趋势面板（P0-历史趋势分析 + 数据来源溯源）
 * 通过弹层展示单个传感器的历史聚合趋势（avg 柱状）与数据来源分布。
 * 数据来自后端 GET /api/sensor/:id/history（含 points 聚合点 + sources 来源分布）。
 */
import { promptAction } from '@kit.ArkUI';
import {
  apiGetSensorHistory,
  SensorHistoryResult,
  SensorHistoryPoint,
  SensorSourceInfo
} from '../services/BackendApi';
import { Palette, ThemeMode, paletteFor } from '../services/Theme';

const ACCENT = '#FF8C2A';   // 矿业橙（与三端主题一致）

@Component
export struct SensorHistoryPanel {
  @Prop sensorId: string = '';
  @Prop sensorName: string = '';
  onClose: () => void = () => {};
  @State interval: string = 'hour';
  @State points: SensorHistoryPoint[] = [];
  @State sources: SensorSourceInfo[] = [];
  @State loading: boolean = true;
  @StorageProp('theme_mode') themeMode: number = ThemeMode.NIGHT;

  aboutToAppear() {
    this.load();
  }

  private pal(): Palette {
    return paletteFor(this.themeMode as ThemeMode);
  }

  async load() {
    this.loading = true;
    try {
      const r: SensorHistoryResult = await apiGetSensorHistory(this.sensorId, this.interval);
      this.points = r.points;
      this.sources = r.sources;
    } catch (err) {
      this.points = [];
      this.sources = [];
      promptAction.showToast({ message: '历史数据获取失败', duration: 1500 });
    } finally {
      this.loading = false;
    }
  }

  async switchInterval(iv: string) {
    this.interval = iv;
    await this.load();
  }

  // 归一化高度到 0~100
  private barHeight(v: number): string {
    if (this.points.length === 0) {
      return '6%';
    }
    let min = this.points[0].avg;
    let max = this.points[0].avg;
    for (let i = 1; i < this.points.length; i++) {
      const a = this.points[i].avg;
      if (a < min) min = a;
      if (a > max) max = a;
    }
    const span = max - min;
    const h = (span <= 0.0001) ? 50 : ((v - min) / span) * 100;
    const clamped = Math.max(6, Math.min(100, h));
    return clamped.toString() + '%';
  }

  private sourceLabel(src: string): string {
    if (src === 'mqtt') return 'MQTT';
    if (src === 'udp') return 'UDP';
    if (src === 'simulator') return '模拟器';
    if (src === 'legacy') return '存量库';
    return src.toUpperCase();
  }

  private sourceColor(src: string): string {
    if (src === 'mqtt') return '#3DDC84';
    if (src === 'udp') return '#4A9CFF';
    if (src === 'simulator') return '#FF8C2A';
    return '#8A8F98';
  }

  private totalSamples(): number {
    let total = 0;
    for (let i = 0; i < this.sources.length; i++) {
      total += this.sources[i].samples;
    }
    return total;
  }

  @Builder
  IntervalTab(label: string, value: string) {
    Text(label)
      .fontSize(12)
      .fontColor(this.interval === value ? Color.White : this.pal().textDim)
      .padding({ left: 12, right: 12, top: 5, bottom: 5 })
      .backgroundColor(this.interval === value ? ACCENT : this.pal().field)
      .borderRadius(12)
      .onClick(() => this.switchInterval(value))
  }

  build() {
    Column() {
      // 标题栏
      Row() {
        Column() {
          Text(this.sensorName)
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.pal().textMain)
          Text('历史趋势分析 · ' + this.sensorId)
            .fontSize(11)
            .fontColor(this.pal().textDim)
            .margin({ top: 2 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Row({ space: 6 }) {
          this.IntervalTab('时', 'hour')
          this.IntervalTab('日', 'day')
        }

        Text('✕')
          .fontSize(18)
          .fontColor(this.pal().textDim)
          .padding(6)
          .onClick(() => this.onClose())
      }
      .width('100%')
      .margin({ bottom: 10 })

      if (this.loading) {
        Text('加载中...')
          .fontSize(13)
          .fontColor(this.pal().textDim)
          .padding(30)
          .width('100%')
          .textAlign(TextAlign.Center)
      } else if (this.points.length === 0) {
        Text('当前时段暂无历史数据')
          .fontSize(13)
          .fontColor(this.pal().textDim)
          .padding(30)
          .width('100%')
          .textAlign(TextAlign.Center)
      } else {
        // 柱状趋势（avg）
        Row() {
          ForEach(this.points, (p: SensorHistoryPoint, idx: number) => {
            Column() {
              Blank()
              Column()
                .width('55%')
                .height(this.barHeight(p.avg))
                .borderRadius({ topLeft: 4, topRight: 4 })
                .backgroundColor(idx % 2 === 0 ? ACCENT : this.pal().accentSoft)
            }
            .width('4.2%')
            .height(160)
            .justifyContent(FlexAlign.End)
            .margin({ left: 2, right: 2 })
          })
        }
        .width('100%')
        .height(160)
        .padding({ left: 8, right: 8, top: 14, bottom: 14 })
        .backgroundColor(this.pal().card)
        .borderRadius(10)

        Row() {
          Text(this.points.length + ' 个聚合点')
            .fontSize(11)
            .fontColor(this.pal().textDim)
        }
        .width('100%')
        .justifyContent(FlexAlign.End)
        .margin({ top: 8 })

        // 数据来源溯源
        Column() {
          Row() {
            Text('数据来源溯源')
              .fontSize(13)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.pal().textMain)
            Blank()
            Text('样本 ' + this.totalSamples() + ' 条')
              .fontSize(11)
              .fontColor(this.pal().textDim)
          }
          .width('100%')

          ForEach(this.sources, (s: SensorSourceInfo) => {
            Row() {
              Text(this.sourceLabel(s.source))
                .fontSize(11)
                .fontWeight(FontWeight.Bold)
                .fontColor(Color.White)
                .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                .backgroundColor(this.sourceColor(s.source))
                .borderRadius(10)
              Text(s.samples + ' 条')
                .fontSize(12)
                .fontColor(this.pal().textMain)
                .margin({ left: 8 })
              Blank()
              if (s.source_addr && s.source_addr.length > 0) {
                Text(s.source_addr)
                  .fontSize(10)
                  .fontColor(this.pal().textDim)
              } else {
                Text('—')
                  .fontSize(10)
                  .fontColor(this.pal().textDim)
              }
            }
            .width('100%')
            .padding({ top: 7, bottom: 7 })
          })
          if (this.sources.length === 0) {
            Text('无来源标签（存量数据）')
              .fontSize(12)
              .fontColor(this.pal().textDim)
              .padding({ top: 6 })
          }
        }
        .width('100%')
        .padding(12)
        .backgroundColor(this.pal().field)
        .borderRadius(10)
        .margin({ top: 10 })
      }
    }
    .width('100%')
    .padding(14)
    .backgroundColor(this.pal().card)
    .borderRadius(16)
  }
}