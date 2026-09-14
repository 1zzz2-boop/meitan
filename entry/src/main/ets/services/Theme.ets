/**
 * 全局主题服务：日 / 夜间模式
 * 基于 AppStorage 实现跨页面响应式状态（值变化自动刷新 @StorageProp 绑定的组件）。
 * - 夜间（默认）：深岩灰 + 矿工橙 工业监测风
 * - 日间：改为白色浅色系，保证内容可读
 * 通过 dataPreferences 持久化选择。
 */
import dataPreferences from '@ohos.data.preferences';

/**
 * 品牌与预警语义色（双端统一，与 PC 端 style.css 一致）
 * 品牌主色：矿工橙（深岩灰底上的信号色）
 * 预警语义：红 / 橙 / 黄 / 绿
 */
export const BRAND_ACCENT = '#FF8C2A';       // 矿工橙（品牌主色）
export const BRAND_ACCENT_DIM = '#d4711c';   // 按压 / 悬停暗化
export const SEM_RED = '#E5484D';            // 预警：红色
export const SEM_ORANGE = '#FF8C2A';         // 预警：橙色（同品牌色）
export const SEM_AMBER = '#F5C542';          // 预警：黄色
export const SEM_GREEN = '#3DDC84';          // 正常 / 在线：绿色
export const SEM_INFO = '#2F7CFF';           // 信息 / 中性强调
export const MINE_GRAY = '#16171B';          // 深岩灰（背景基色）

export enum ThemeMode {
  NIGHT = 0,
  DAY = 1
}

export interface Palette {
  bgApp: string;        // 页面背景
  headerBg: string;     // 顶部状态栏 / 底部 Tab 栏背景
  card: string;         // 卡片背景
  field: string;        // 输入框 / 进度底槽背景
  textMain: string;     // 主文本
  textSub: string;      // 次级文本
  textDim: string;      // 弱化文本
  placeholder: string;  // 输入框占位符
  accentSoft: string;   // 次级按钮 / 底色块
  overlay: string;      // 弹层遮罩
}

// 夜间模式：深岩灰 + 矿工橙（与 PC 端设计系统一致）
const NIGHT_PALETTE: Palette = {
  bgApp: '#16171B',
  headerBg: '#1B1D22',
  card: '#1E2026',
  field: '#26292F',
  textMain: '#FFFFFF',
  textSub: '#CFD9E8',
  textDim: '#9AA1AB',
  placeholder: '#5A616B',
  accentSoft: '#3A3D44',
  overlay: 'rgba(0,0,0,0.6)'
};

// 日间模式：白色浅色系
const DAY_PALETTE: Palette = {
  bgApp: '#F2F4F7',
  headerBg: '#FFFFFF',
  card: '#FFFFFF',
  field: '#E9EBEE',
  textMain: '#1A1D26',
  textSub: '#41464F',
  textDim: '#6B7280',
  placeholder: '#9AA1AB',
  accentSoft: '#E5E7EB',
  overlay: 'rgba(0,0,0,0.45)'
};

const STORAGE_KEY = 'theme_mode';
const PREF_NAME = 'theme_pref';
const PREF_MODE_KEY = 'mode';

// 按模式返回配色（供页面 pal() 使用）
export function paletteFor(mode: ThemeMode): Palette {
  return mode === ThemeMode.DAY ? DAY_PALETTE : NIGHT_PALETTE;
}

// 当前是否日间
export function isDay(): boolean {
  const m = AppStorage.get<number>(STORAGE_KEY);
  return m === ThemeMode.DAY;
}

// 模式切换按钮文字
export function modeLabel(): string {
  return isDay() ? '夜间' : '日间';
}

// 初始化 AppStorage 主题状态（幂等，仅首次读取持久化）
export async function ensureThemeInit(ctx: Context): Promise<void> {
  try {
    const prefs = await dataPreferences.getPreferences(ctx, PREF_NAME);
    const m = await prefs.get(PREF_MODE_KEY, ThemeMode.NIGHT) as number;
    AppStorage.setOrCreate<number>(STORAGE_KEY, m);
  } catch (e) {
    AppStorage.setOrCreate<number>(STORAGE_KEY, ThemeMode.NIGHT);
  }
}

// 切换模式并持久化
export function switchThemeMode(ctx: Context): void {
  const cur = AppStorage.get<number>(STORAGE_KEY);
  const next = cur === ThemeMode.DAY ? ThemeMode.NIGHT : ThemeMode.DAY;
  AppStorage.set<number>(STORAGE_KEY, next);
  dataPreferences.getPreferences(ctx, PREF_NAME).then((prefs) => {
    prefs.put(PREF_MODE_KEY, next);
    return prefs.flush();
  }).catch(() => {
    console.log('保存主题失败');
  });
}
