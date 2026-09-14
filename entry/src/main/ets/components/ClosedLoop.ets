/**
 * 全流程数据闭环（公共组件）——三端总览驾驶舱复用
 * 展示「采集→传输→处理→分析→预警→可视化→反馈」7 节点闭环，呼应方案"全流程闭环"得分点。
 */
import { Palette, ThemeMode, paletteFor } from '../services/Theme';

interface ClosedStep {
  icon: string;
  label: string;
}

const CLOSED_STEPS: ClosedStep[] = [
  { icon: '📡', label: '采集' },
  { icon: '🔗', label: '传输' },
  { icon: '⚙️', label: '处理' },
  { icon: '🧠', label: '分析' },
  { icon: '🚨', label: '预警' },
  { icon: '📊', label: '可视化' },
  { icon: '↩️', label: '反馈' }
];

@Component
export struct ClosedLoop {
  @StorageProp('theme_mode') themeMode: number = ThemeMode.NIGHT;

  private pal(): Palette {
    return paletteFor(this.themeMode as ThemeMode);
  }

  build() {
    Scroll() {
      Row({ space: 4 }) {
        ForEach(CLOSED_STEPS, (step: ClosedStep, index: number) => {
          Column() {
            Text(step.icon)
              .fontSize(18)
            Text(step.label)
              .fontSize(10)
              .fontColor(this.pal().textMain)
              .margin({ top: 4 })
          }
          .width(56)
          .height(64)
          .justifyContent(FlexAlign.Center)
          .backgroundColor(this.pal().field)
          .borderRadius(12)
          .border({ width: 1, color: '#22FF8C2A' })

          if (index < CLOSED_STEPS.length - 1) {
            Text('›')
              .fontSize(16)
              .fontColor(this.pal().accentSoft)
          }
        })
      }
      .alignItems(VerticalAlign.Top)
      .padding({ left: 12, right: 12 })
    }
    .width('100%')
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
  }
}