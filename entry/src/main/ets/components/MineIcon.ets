/**
 * MineIcon —— 统一工业风格线性图标组件
 * 24×24 坐标系 · stroke 描边风格，路径与 PC 端 assets/app.js 内联 SVG sprite 一一对应，
 * 保证双端图标视觉一致（无 emoji、无霓虹）。
 */
import { SEM_RED, SEM_ORANGE, SEM_AMBER, SEM_GREEN } from '../services/Theme';

// 图标路径表（与 PC 端 ICONS 一致，SVG path 语法）
const ICON_PATHS: Record<string, string> = {
  'pick': 'M13.5 12 6 19.5 M6 19.5C6 18.6 6.2 17.7 6.9 16.9 M6 19.5l-2 1.2 M21 3l-6.2 6.2 M21 3c-.3-1.6-2-2.4-3.6-2.1l-3.4 8.1 M14.4 9.1l2.4-5.9',
  'mine': 'M3 21h18 M5 21V8l7-5 7 5v13 M9 21v-6h6v6 M10 5h4',
  'cap': 'M22 10 12 5 2 10l10 5 10-5Z M6 12v6c0 1.7 2.7 3 6 3s6-1.3 6-3v-6',
  'gov': 'M3 21h18 M5 21V7l7-4 7 4v14 M9 21v-5h6v5 M9 9h.01M15 9h.01M12 9h.01M12 13h.01M15 13h.01M9 13h.01',
  'screen': 'M2 3h20v14H2z M8 21h8 M12 17v4 M7 9l3 3-3 3 M13 15h4',
  'dashboard': 'M3 3h7v9H3z M14 3h7v5h-7z M14 12h7v9h-7z M3 16h7v5H3z',
  'monitor': 'M4.9 16.1C1 12.2 1 5.8 4.9 1.9 M7.8 20.7a9 9 0 0 1 0-13.4 M12 7a3 3 0 1 1 0 6a3 3 0 0 1 0-6 M16.2 7.3a9 9 0 0 1 0 13.4 M19.1 16.1c3.9-3.9 3.9-10.3 0-14.2',
  'siren': 'M11 2h2v2h-2z M4 22h16v-3H4z M4 17a8 8 0 0 1 16 0 M12 5v4',
  'trend': 'M22 7 13.5 15.5 8.5 10.5 2 17 M16 7h6v6',
  'analysis': 'M3 3v18h18 M18 17V9 M13 17V5 M8 17v-3',
  'globe': 'M12 2a10 10 0 1 1 0 20a10 10 0 0 1 0-20 M2 12h20 M12 2a15.3 15.3 0 0 1 4 10a15.3 15.3 0 0 1-4 10a15.3 15.3 0 0 1-4-10a15.3 15.3 0 0 1 4-10Z',
  'settings': 'M21 4H14 M10 4H3 M21 12H12 M8 12H3 M21 20H16 M12 20H3 M14 2v4 M8 10v4 M16 18v4',
  'user': 'M19 21v-2a4 4 0 0 0-4-4H9a4 4 0 0 0-4 4v2 M12 3a4 4 0 1 1 0 8a4 4 0 0 1 0-8',
  'lock': 'M19 11H5a2 2 0 0 0-2 2v7a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-7a2 2 0 0 0-2-2Z M7 11V7a5 5 0 0 1 10 0v4',
  'shield': 'M20 13c0 5-3.5 7.5-7.66 8.95a1 1 0 0 1-.67-.01C7.5 20.5 4 18 4 13V6a1 1 0 0 1 1-1c2 0 4.5-1.2 6.24-2.72a1.17 1.17 0 0 1 1.52 0C14.51 3.81 17 5 19 5a1 1 0 0 1 1 1Z M12 8v4 M12 16h.01',
  'antenna': 'M20 4 3 20 M6 10l8 8 M14 2l-4 8 M8 6l-2 4 M16 8l6 6',
  'online': 'M12 2a10 10 0 1 1 0 20a10 10 0 0 1 0-20 M12 10a2 2 0 1 1 0 4a2 2 0 0 1 0-4',
  'alert': 'M21.73 18 13.73 4a2 2 0 0 0-3.46 0L2.27 18A2 2 0 0 0 4 21h16a2 2 0 0 0 1.73-3 M12 9v4 M12 17h.01',
  'check': 'M12 2a10 10 0 1 1-.7 19.94 M22 4 12 14.01 9 11.01',
  'layers': 'm12.83 2.18a2 2 0 0 0-1.66 0L2.6 6.08a1 1 0 0 0 0 1.83l8.58 3.91a2 2 0 0 0 1.66 0l8.58-3.9a1 1 0 0 0 0-1.83Z m9.17 11.57-9.17 4.16a2 2 0 0 1-1.66 0L2 17.65 m20-5-9.17 4.16a2 2 0 0 1-1.66 0L2 12.65',
  'droplets': 'M7 16.3c2.2 0 4-1.83 4-4.05 0-1.16-.57-2.26-1.71-3.19S7.29 6.75 7 5.3c-.29 1.45-1.14 2.84-2.29 3.76S3 11.1 3 12.25c0 2.22 1.8 4.05 4 4.05z M12.56 6.6A10.97 10.97 0 0 0 14 3.02c.5 2.5 2 4.9 4 6.5s3 3.5 3 5.5a6.98 6.98 0 0 1-11.91 4.97',
  'thermo': 'M14 4v10.54a4 4 0 1 1-4 0V4a2 2 0 0 1 4 0Z',
  'wind': 'M12.8 19.6A2 2 0 1 0 14 16H2 M17.5 8a2.5 2.5 0 1 1 2 4H2 M9.8 4.4A2 2 0 1 1 11 8H2',
  'ruler': 'M21.3 15.3a2.4 2.4 0 0 1 0 3.4l-2.6 2.6a2.4 2.4 0 0 1-3.4 0L2.7 8.7a2.41 2.41 0 0 1 0-3.4l2.6-2.6a2.41 2.41 0 0 1 3.4 0Z m-6.8 4.2 2-2 m-3-3 2-2 m-3-3 2-2 m9 9 2-2',
  'wrench': 'M14.7 6.3a1 1 0 0 0 0 1.4l1.6 1.6a1 1 0 0 0 1.4 0l3.77-3.77a6 6 0 0 1-7.94 7.94l-6.91 6.91a2.12 2.12 0 0 1-3-3l6.91-6.91a6 6 0 0 1 7.94-7.94l-3.76 3.76z',
  'vibration': 'M2 8v8 M6 4v16 M10 2v20 M14 6v12 M18 4v16 M22 8v8',
  'vr': 'M3 5h18a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2h-4l-1.5-2h-7L7 17H3a2 2 0 0 1-2-2V7a2 2 0 0 1 2-2Z M7 11h.01 M17 11h.01',
  'activity': 'M22 12h-2.48a2 2 0 0 0-1.93 1.46l-2.35 8.36a.25.25 0 0 1-.48 0L9.24 2.18a.25.25 0 0 0-.48 0l-2.35 8.36A2 2 0 0 1 4.48 12H2',
  'sensor': 'M3 7V5a2 2 0 0 1 2-2h2 M17 3h2a2 2 0 0 1 2 2v2 M21 17v2a2 2 0 0 1-2 2h-2 M7 21H5a2 2 0 0 1-2-2v-2 M12 9a3 3 0 1 1 0 6a3 3 0 0 1 0-6',
  'clock': 'M12 2a10 10 0 1 1 0 20a10 10 0 0 1 0-20 M12 6v6l4 2',
  'gauge': 'M12 14l4-4 M3.34 19a10 10 0 1 1 17.32 0'
};

// 语义圆点（填色，用于在线/预警等级等状态，替代 emoji 色块）
export const DOT_COLORS: Record<string, string> = {
  'dot-red': SEM_RED,
  'dot-orange': SEM_ORANGE,
  'dot-amber': SEM_AMBER,
  'dot-green': SEM_GREEN
};

@Component
export struct MineIcon {
  @Prop name: string = 'pick';
  @Prop iconSize: number = 16;
  @Prop color: string = '#E6E9EE';
  @Prop strokeWidth: number = 1.7;

  build() {
    if (this.name === 'dot-red' || this.name === 'dot-orange' ||
      this.name === 'dot-amber' || this.name === 'dot-green') {
      Circle()
        .width(this.iconSize)
        .height(this.iconSize)
        .fill(DOT_COLORS[this.name] as string)
    } else {
      Shape() {
        Path()
          .commands(ICON_PATHS[this.name] as string)
          .fill('none')
          .stroke(this.color)
          .strokeWidth(this.strokeWidth * 24 / this.iconSize)
          .strokeLineCap(LineCapStyle.Round)
          .strokeLineJoin(LineJoinStyle.Round)
          .width(24)
          .height(24)
          .scale({ x: this.iconSize / 24, y: this.iconSize / 24 })
      }
      .width(this.iconSize)
      .height(this.iconSize)
    }
  }
}
