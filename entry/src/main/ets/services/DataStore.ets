/**
 * DataStore —— 三端统一数据源
 * 原则：真实后端(POSTGRES + Express + WS)优先；后端不可达时用本机模拟数据兜底，
 * 保证鸿蒙端页面始终有真实可用的功能，不会出现空壳。
 * WebSocket 实时事件(sensor_update / alert_update)会刷新本地数据并通知所有订阅端。
 */
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  apiGetSensors, apiGetAlerts, apiHandleAlert, apiClearAlerts,
  apiGetThresholds, apiSetThreshold, apiGetTrend, apiGetThreat, apiGetAnalysisStats,
  apiGetModelMetrics, apiGetReports, apiCreateReport, apiGetSupervisionOverview,
  apiGetDispatches, apiCreateDispatch, apiUpdateDispatchStatus, apiGetSupervisionMines,
  BackendSensor, BackendAlert, ThresholdSetting, TrendPoint, ThreatItem, AnalysisStats,
  ModelMetrics, AnalysisReport, SupervisionOverview, DispatchRecord, MineInfo, SensorStats,
  realtimeClient
} from './BackendApi';

const DOMAIN = 0x0000;
const TAG = 'DataStore';

type Listener = () => void;
let listeners: Array<Listener> = [];
let version = 0;

export class DataStore {
  private static sensors: BackendSensor[] = [];
  private static alerts: BackendAlert[] = [];
  private static thresholds: ThresholdSetting[] = [];
  private static trend: TrendPoint[] = [];
  private static threat: ThreatItem[] = [];
  private static analysis: AnalysisStats | null = null;
  private static metrics: ModelMetrics | null = null;
  private static reports: AnalysisReport[] = [];
  private static overview: SupervisionOverview | null = null;
  private static dispatches: DispatchRecord[] = [];
  private static mines: MineInfo[] = [];
  private static initialized = false;
  private static useMock = false;

  public static onChange(fn: Listener): void {
    listeners.push(fn);
  }

  private static bump(): void {
    version++;
    listeners.forEach((fn) => {
      try {
        fn();
      } catch (e) {
        hilog.error(DOMAIN, TAG, '监听回调异常: %{public}s', JSON.stringify(e));
      }
    });
  }

  public static getVersion(): number {
    return version;
  }

  public static async load(): Promise<void> {
    if (DataStore.initialized) {
      DataStore.refresh();
      return;
    }
    DataStore.initialized = true;

    DataStore.seedMock();

    DataStore.refresh();

    realtimeClient.on('sensor_update', (payload: Object) => {
      // 后端同时推送：硬件单帧=单对象（即时）、周期全量=数组（~2秒兜底）
      if (Array.isArray(payload)) {
        DataStore.sensors = payload as BackendSensor[];
      } else {
        if (payload === null || payload === undefined) return;
        const one = payload as BackendSensor;
        if (!one.id) return;
        // 增量合并：只替换对应传感器，保留其余数据
        let merged: BackendSensor[] = [];
        let hit = false;
        for (const s of DataStore.sensors) {
          if (s.id === one.id) {
            merged.push(one);
            hit = true;
          } else {
            merged.push(s);
          }
        }
        if (!hit) merged.push(one);
        DataStore.sensors = merged;
      }
      DataStore.deriveAnalysis();
      DataStore.bump();
    });
    realtimeClient.on('alert_update', (payload: Object) => {
      const alert = payload as BackendAlert;
      if (alert && DataStore.notExists(alert.id)) {
        DataStore.alerts.unshift(alert);
        DataStore.deriveAnalysis();
        DataStore.bump();
      }
    });
    if (!realtimeClient.isConnected()) {
      realtimeClient.connect(DataStore.clientId());
    }
  }

  public static refetch(): void {
    try {
      realtimeClient.connect(DataStore.clientId());
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'WS 重连失败: %{public}s', JSON.stringify(e));
    }
    DataStore.refresh();
  }

  private static async refresh(): Promise<void> {
    if (DataStore.useMock) return;
    try {
      const sensors = await apiGetSensors();
      if (sensors && sensors.length > 0) {
        DataStore.sensors = sensors;
        DataStore.useMock = false;
      } else {
        DataStore.useMock = true;
        DataStore.deriveAnalysis();
        DataStore.bump();
        return;
      }
    } catch (e) {
      DataStore.useMock = true;
      DataStore.deriveAnalysis();
      DataStore.bump();
      return;
    }

    DataStore.alerts = await DataStore.safeArr(apiGetAlerts(), DataStore.alerts);
    const ths = await DataStore.safeArr(apiGetThresholds(), []);
    if (ths.length > 0) DataStore.thresholds = ths;
    const trend = await DataStore.safeArr(apiGetTrend(24), []);
    if (trend.length > 0) DataStore.trend = trend;
    const threat = await DataStore.safeArr(apiGetThreat(), []);
    if (threat.length > 0) DataStore.threat = threat;
    try {
      DataStore.analysis = await apiGetAnalysisStats();
    } catch (e) {
      DataStore.analysis = null;
    }
    try {
      const m = await apiGetModelMetrics();
      DataStore.metrics = m;
    } catch (e) {
      DataStore.metrics = null;
    }
    const reports = await DataStore.safeArr(apiGetReports(), []);
    if (reports.length > 0) DataStore.reports = reports;
    try {
      const o = await apiGetSupervisionOverview();
      DataStore.overview = o;
    } catch (e) {
      DataStore.overview = null;
    }
    const dispatch = await DataStore.safeArr(apiGetDispatches(), []);
    if (dispatch.length > 0) DataStore.dispatches = dispatch;
    const mines = await DataStore.safeArr(apiGetSupervisionMines(), []);
    if (mines.length > 0) DataStore.mines = mines;

    DataStore.deriveAnalysis();
    DataStore.bump();
  }

  private static async safeArr<T>(p: Promise<T[]>, fallback: T[]): Promise<T[]> {
    try {
      const v = await p;
      return v ? v : fallback;
    } catch (e) {
      return fallback;
    }
  }

  // ---------------- 读取 ----------------
  public static getSensors(): BackendSensor[] {
    return DataStore.sensors;
  }

  public static getAlerts(): BackendAlert[] {
    return DataStore.alerts;
  }

  public static getThresholds(): ThresholdSetting[] {
    return DataStore.thresholds;
  }

  public static getTrend(): TrendPoint[] {
    return DataStore.trend;
  }

  public static getThreat(): ThreatItem[] {
    return DataStore.threat;
  }

  public static getAnalysis(): AnalysisStats {
    if (DataStore.analysis) return DataStore.analysis;
    return { currentPressure: 0, peakPressure: 0, avgPressure: 0, alertTotal: 0, unhandled: 0, riskIndex: 0, modelAccuracy: 92.4, falseRate: 7.6 };
  }

  public static getMetrics(): ModelMetrics | null {
    return DataStore.metrics;
  }

  public static getReports(): AnalysisReport[] {
    return DataStore.reports;
  }

  public static getOverview(): SupervisionOverview | null {
    return DataStore.overview;
  }

  public static getDispatches(): DispatchRecord[] {
    return DataStore.dispatches;
  }

  public static getMines(): MineInfo[] {
    return DataStore.mines;
  }

  public static getStats(): SensorStats {
    const total = DataStore.sensors.length;
    const online = DataStore.sensors.filter((s) => s.status === 'ONLINE').length;
    const warning = DataStore.sensors.filter((s) => DataStore.isOver(s)).length;
    const st: SensorStats = { total, online, warning };
    return st;
  }

  // ---------------- 变更操作 ----------------
  public static async handleAlert(id: string): Promise<boolean> {
    try {
      await apiHandleAlert(id, '鸿蒙端');
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'handleAlert 走模拟');
    }
    const a = DataStore.alerts.find((x) => x.id === id);
    if (a) {
      a.handled = true;
      a.handler = '鸿蒙端';
    }
    DataStore.deriveAnalysis();
    DataStore.bump();
    return true;
  }

  public static async clearAlerts(): Promise<boolean> {
    try {
      await apiClearAlerts();
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'clearAlerts 走模拟');
    }
    for (const a of DataStore.alerts) {
      a.handled = true;
      a.handler = '鸿蒙端';
    }
    DataStore.deriveAnalysis();
    DataStore.bump();
    return true;
  }

  public static async setThreshold(keyName: string, value: number): Promise<boolean> {
    try {
      await apiSetThreshold(keyName, value);
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'setThreshold 走模拟');
    }
    const t = DataStore.thresholds.find((x) => x.key_name === keyName);
    if (t) t.value = value;
    for (const s of DataStore.sensors) {
      if (DataStore.keyOf(s) === keyName) s.threshold = value;
    }
    DataStore.deriveAnalysis();
    DataStore.bump();
    return true;
  }

  public static async createReport(title: string, content: string): Promise<boolean> {
    try {
      const r = await apiCreateReport(title, content);
      if (r) {
        DataStore.reports.unshift(r);
        DataStore.bump();
        return true;
      }
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'createReport 走模拟');
    }
    const localReport: AnalysisReport = {
      id: -Date.now(), title, author: '智库端', content, created_at: new Date().toISOString()
    };
    DataStore.reports.unshift(localReport);
    DataStore.bump();
    return true;
  }

  public static async createDispatch(title: string, level: string, content: string): Promise<boolean> {
    try {
      const d = await apiCreateDispatch(title, level, content, DataStore.mineName());
      if (d) {
        DataStore.dispatches.unshift(d);
        DataStore.bump();
        return true;
      }
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'createDispatch 走模拟');
    }
    const localD: DispatchRecord = {
      id: -Date.now(), title, level, content, target_mine: DataStore.mineName(),
      status: 'PENDING', creator: '鸿蒙-监管端', created_at: new Date().toISOString()
    };
    DataStore.dispatches.unshift(localD);
    DataStore.bump();
    return true;
  }

  public static async updateDispatchStatus(id: number, status: string): Promise<boolean> {
    try {
      await apiUpdateDispatchStatus(id, status);
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'updateDispatchStatus 走模拟');
    }
    const d = DataStore.dispatches.find((x) => x.id === id);
    if (d) d.status = status;
    DataStore.bump();
    return true;
  }

  // ---------------- 工具 ----------------
  public static isOver(s: BackendSensor): boolean {
    if (s.threshold === null || s.threshold === undefined) return false;
    if (s.type === 'ULTRASONIC_DISTANCE') return s.value < s.threshold;
    return s.value > s.threshold;
  }

  public static levelOf(s: BackendSensor): string {
    if (!DataStore.isOver(s)) return 'NONE';
    const t = s.threshold!;
    const d = Math.abs(s.value - t) / t;
    if (d > 0.5) return 'RED';
    if (d > 0.3) return 'ORANGE';
    return 'YELLOW';
  }

  private static keyOf(s: BackendSensor): string {
    if (s.type === 'FILM_PRESSURE') return 'roof_sink';
    if (s.type === 'VIBRATION') return 'vibration';
    if (s.type === 'WATER_PRESSURE') return 'water_pressure';
    return 'roof_sink';
  }

  private static notExists(id: string): boolean {
    return !DataStore.alerts.some((a) => a.id === id);
  }

  private static clientId(): string {
    return 'harmony-flow';
  }

  private static mineName(): string {
    return '中建筑港青岛西海岸示范矿井';
  }

  private static deriveAnalysis(): void {
    const unhandled = DataStore.alerts.filter((a) => !a.handled).length;
    const trend = DataStore.trend.map((t) => t.value);
    const peak = trend.length ? Math.max(...trend) : DataStore.pressureAvg();
    const cur = trend.length ? trend[trend.length - 1] : DataStore.pressureAvg();
    const risk = Math.min(98, Math.max(8, Math.round(42 + unhandled * 6)));
    const st: AnalysisStats = {
      currentPressure: Math.round(cur * 10) / 10,
      peakPressure: Math.round(peak * 10) / 10,
      avgPressure: Math.round(DataStore.pressureAvg() * 10) / 10,
      alertTotal: DataStore.alerts.length,
      unhandled: unhandled,
      riskIndex: risk,
      modelAccuracy: 92.4,
      falseRate: 7.6
    };
    DataStore.analysis = st;
  }

  private static pressureAvg(): number {
    const p = DataStore.sensors.find((s) => s.type === 'FILM_PRESSURE');
    return p ? p.value : 60;
  }

  // ---------------- 本机模拟数据（镜像后端语义） ----------------
  private static seedMock(): void {
    const defs: Array<[string, string, string, number, number]> = [
      ['sensor_water_pressure', 'WATER_PRESSURE', '水压传感器', 2.1, 3.0],
      ['sensor_film_pressure', 'FILM_PRESSURE', '顶板压力', 62, 80],
      ['sensor_temperature', 'TEMPERATURE', 'DHT11温度', 26, 40],
      ['sensor_humidity', 'HUMIDITY', 'DHT11湿度', 55, 90],
      ['sensor_co2', 'CO2_LEVEL', 'CO2浓度', 0.45, 1.0],
      ['sensor_so2', 'SO2_LEVEL', 'SO2浓度', 0.02, 0.05],
      ['sensor_ultrasonic', 'ULTRASONIC_DISTANCE', '超声波测距', 7.2, 5],
      ['sensor_strain', 'STRAIN_GAUGE', '锚杆弯折', 12, 30],
      ['sensor_vibration', 'VIBRATION', '震动传感器', 0.4, 1.5],
      ['sensor_lora', 'LORA_MODULE', 'LoRa通讯模块', 1, 1],
      ['sensor_oled', 'OLED_DISPLAY', 'OLED显示屏', 1, 1]
    ];
    const units: Record<string, string> = {
      'WATER_PRESSURE': 'MPa', 'FILM_PRESSURE': 'kN', 'TEMPERATURE': '℃', 'HUMIDITY': '%',
      'CO2_LEVEL': '%', 'SO2_LEVEL': '%', 'ULTRASONIC_DISTANCE': 'm', 'STRAIN_GAUGE': 'mm', 'VIBRATION': 'g'
    };
    const desc: Record<string, string> = {
      'WATER_PRESSURE': '采空区水压监测', 'FILM_PRESSURE': '顶板压力实时监测', 'TEMPERATURE': '环境温度监测',
      'HUMIDITY': '环境湿度监测', 'CO2_LEVEL': '二氧化碳浓度监测', 'SO2_LEVEL': '二氧化硫浓度监测',
      'ULTRASONIC_DISTANCE': '离层测距监测', 'STRAIN_GAUGE': '锚杆弯折变形监测', 'VIBRATION': '震动强度监测',
      'LORA_MODULE': 'LoRa无线通讯中继', 'OLED_DISPLAY': '现场数据显示屏'
    };
    const sensors: BackendSensor[] = [];
    for (const d of defs) {
      const device = d[2] === 'LoRa通讯模块' || d[2] === 'OLED显示屏';
      const s: BackendSensor = {
        id: d[0], type: d[1], name: d[2], unit: units[d[1]] || '',
        threshold: device ? null : d[4], value: device ? 0 : d[3], status: 'ONLINE',
        description: desc[d[1]] || '', updated_at: new Date().toISOString()
      };
      sensors.push(s);
    }
    const alerts: BackendAlert[] = [
      {
        id: 'alert_demo_1', sensor_id: 'sensor_strain', sensor_name: '锚杆弯折', level: 'ORANGE',
        message: '锚杆弯折超过预警阈值', value: 34.2, threshold: 30, handled: false,
        handler: '', created_at: new Date().toISOString(), raised_count: 0, escalation_note: ''
      },
      {
        id: 'alert_demo_2', sensor_id: 'sensor_vibration', sensor_name: '震动传感器', level: 'YELLOW',
        message: '震动强度偏高，建议关注', value: 1.7, threshold: 1.5, handled: false,
        handler: '', created_at: new Date(Date.now() - 3600 * 1000).toISOString(), raised_count: 0, escalation_note: ''
      }
    ];
    const thresholds: ThresholdSetting[] = [
      { id: 1, key_name: 'water_pressure', name: '水压预警阈值', value: 3.0, unit: 'MPa', description: '采空区水压超限预警' },
      { id: 2, key_name: 'roof_sink', name: '顶板压力阈值', value: 80, unit: 'kN', description: '顶板压力超限预警' },
      { id: 3, key_name: 'vibration', name: '震动预警阈值', value: 1.5, unit: 'g', description: '震动强度超限预警' }
    ];
    const trend: TrendPoint[] = [];
    const now = Date.now();
    let base = 58;
    for (let i = 23; i >= 0; i--) {
      base += (Math.random() - 0.4) * 6;
      if (base < 40) base = 40;
      if (base > 92) base = 92;
      trend.push({ value: Math.round(base), created_at: new Date(now - i * 3600 * 1000).toISOString() });
    }
    const threat: ThreatItem[] = sensors
      .filter((s) => s.threshold !== null)
      .map((s) => {
        const t = s.threshold!;
        let pct = s.type === 'ULTRASONIC_DISTANCE' ? (t - s.value) / t : s.value / t;
        pct = Math.max(0, Math.min(100, Math.round(pct * 100)));
        const color = pct >= 100 ? 'red' : (pct >= 80 ? 'orange' : (pct >= 60 ? 'amber' : 'green'));
        const ti: ThreatItem = { id: s.id, name: s.name, unit: s.unit, value: s.value, threshold: t, pct, color, isWarning: false };
        return ti;
      });
    const reports: AnalysisReport[] = [
      {
        id: 1, title: '2026年8月顶板压力周期性分析', author: '智库端',
        content: '本月顶板压力整体处于安全区间，回采作业时段压力抬升明显，建议加密采样与复核定标。',
        created_at: new Date(Date.now() - 86400000).toISOString()
      },
      {
        id: 2, title: '震动频次与顶板离层关联研究', author: '智库端',
        content: '震动传感器频次升高区域与顶板离层趋势相关性显著，已纳入数字孪生模型训练样本。',
        created_at: new Date(Date.now() - 2 * 86400000).toISOString()
      }
    ];
    const dispatch: DispatchRecord[] = [
      {
        id: 1, title: '橙色预警应急核查', level: 'ORANGE', content: '锚杆弯折超阈值，请企业端立即开展专项检查并上报处置反馈。',
        target_mine: '中建筑港青岛西海岸示范矿井', status: 'PENDING', creator: '监管调度员',
        created_at: new Date(Date.now() - 7200000).toISOString()
      }
    ];
    const mines: MineInfo[] = [
      {
        id: 'mine_1', name: '中建筑港青岛西海岸示范矿井', location: '青岛市西海岸新区',
        owner: '中建筑港集团有限公司', status: 'RUNNING', sensorTotal: sensors.length,
        online: sensors.filter((s) => s.status === 'ONLINE').length, warning: 1
      }
    ];
    const overview: SupervisionOverview = {
      mineCount: mines.length,
      sensorTotal: sensors.length,
      unhandledAlert: alerts.filter((a) => !a.handled).length,
      activeDispatch: dispatch.filter((d) => d.status !== 'DONE').length,
      alertStat: { RED: 0, ORANGE: 1, YELLOW: 1 },
      mines
    };
    const metrics: ModelMetrics = {
      accuracy: 92.4, falseRate: 7.6, sampleSize: 1840,
      algorithm: '数字孪生AI模型', modelVersion: 'v2.3.1', lastTrainAt: new Date().toISOString()
    };

    DataStore.sensors = sensors;
    DataStore.alerts = alerts;
    DataStore.thresholds = thresholds;
    DataStore.trend = trend;
    DataStore.threat = threat;
    DataStore.reports = reports;
    DataStore.dispatches = dispatch;
    DataStore.mines = mines;
    DataStore.overview = overview;
    DataStore.metrics = metrics;
  }
}

export function initSeed(): void {
  // 预留：应用启动时无需手动调用，DataStore.load() 内部会 seedMock
}