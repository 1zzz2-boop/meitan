/**
 * ========================================
 * 物联设备接口模块 - IoT Device Interface Module
 * ========================================
 * 
 * 功能说明：
 * 1. 传感器数据采集与管理
 * 2. 设备状态监控
 * 3. LoRa通讯协议处理
 * 4. 数据缓存与同步
 * 
 * 设备列表：
 * - 水压传感器 (Water Pressure Sensor)
 * - 薄膜传感器 (Film Pressure Sensor)
 * - DHT11温湿度传感器 (Temperature & Humidity Sensor)
 * - CO2浓度传感器 (CO2 Sensor)
 * - SO2浓度传感器 (SO2 Sensor)
 * - 超声波测距传感器 (Ultrasonic Distance Sensor)
 * - 应变片传感器 (Strain Gauge Sensor)
 * - 震动传感器 (Vibration Sensor)
 * - LoRa通讯模块 (LoRa Communication Module)
 * - OLED显示屏 (OLED Display)
 */

import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  apiGetSensors, apiGetAlerts, apiHandleAlert,
  realtimeClient, BackendSensor, BackendAlert
} from './BackendApi';

const DOMAIN = 0x0000;
const TAG = 'IoTDeviceService';

// ========================================
// 物联设备接口定义
// ========================================

/**
 * 传感器数据接口
 */
export interface SensorData {
  id: string;                    // 传感器ID
  name: string;                  // 传感器名称
  type: SensorType;              // 传感器类型
  value: number;                 // 当前值
  unit: string;                  // 单位
  timestamp: number;             // 时间戳
  status: DeviceStatus;          // 设备状态
  threshold?: number;            // 预警阈值
  isWarning?: boolean;           // 是否预警
  description?: string;          // 描述信息
}

/**
 * 传感器类型枚举
 */
export enum SensorType {
  WATER_PRESSURE = 'WATER_PRESSURE',           // 水压传感器
  FILM_PRESSURE = 'FILM_PRESSURE',             // 薄膜传感器（顶板压力）
  TEMPERATURE = 'TEMPERATURE',                 // 温度传感器
  HUMIDITY = 'HUMIDITY',                       // 湿度传感器
  CO2_LEVEL = 'CO2_LEVEL',                     // CO2浓度传感器
  SO2_LEVEL = 'SO2_LEVEL',                     // SO2浓度传感器
  ULTRASONIC_DISTANCE = 'ULTRASONIC_DISTANCE', // 超声波测距传感器
  STRAIN_GAUGE = 'STRAIN_GAUGE',               // 应变片传感器
  VIBRATION = 'VIBRATION',                     // 震动传感器
  LORA_MODULE = 'LORA_MODULE',                 // LoRa通讯模块
  OLED_DISPLAY = 'OLED_DISPLAY'                // OLED显示屏
}

// 后端传感器类型名 -> 本地枚举映射
const SENSOR_TYPE_BY_NAME: Record<string, SensorType> = {
  'WATER_PRESSURE': SensorType.WATER_PRESSURE,
  'FILM_PRESSURE': SensorType.FILM_PRESSURE,
  'TEMPERATURE': SensorType.TEMPERATURE,
  'HUMIDITY': SensorType.HUMIDITY,
  'CO2_LEVEL': SensorType.CO2_LEVEL,
  'SO2_LEVEL': SensorType.SO2_LEVEL,
  'ULTRASONIC_DISTANCE': SensorType.ULTRASONIC_DISTANCE,
  'STRAIN_GAUGE': SensorType.STRAIN_GAUGE,
  'VIBRATION': SensorType.VIBRATION,
  'LORA_MODULE': SensorType.LORA_MODULE,
  'OLED_DISPLAY': SensorType.OLED_DISPLAY
};

/**
 * 设备状态枚举
 */
export enum DeviceStatus {
  ONLINE = 'ONLINE',       // 在线
  OFFLINE = 'OFFLINE',     // 离线
  WARNING = 'WARNING',     // 预警
  ERROR = 'ERROR'          // 故障
}

/**
 * 预警等级枚举
 */
export enum AlertLevel {
  NORMAL = '正常',
  YELLOW = '黄色预警',
  ORANGE = '橙色预警',
  RED = '红色预警'
}

/**
 * 预警信息接口
 */
export interface AlertInfo {
  id: string;
  sensorId: string;
  sensorName: string;
  level: AlertLevel;
  message: string;
  timestamp: number;
  isHandled: boolean;
  value: number;
  threshold: number;
}

/**
 * 设备控制命令接口
 */
export interface DeviceCommand {
  deviceId: string;
  command: string;
  params?: Record<string, string | number | boolean>;
  timestamp: number;
}

/**
 * 批量更新数据接口
 */
export interface BatchUpdateData {
  id: string;
  value: number;
}

/**
 * 传感器数据导出接口
 */
export interface SensorDataExport {
  timestamp: number;
  sensors: SensorData[];
  alerts: AlertInfo[];
}

// ========================================
// 物联设备服务类
// ========================================

/**
 * 物联设备服务类
 * 负责管理所有传感器设备的数据采集、状态监控和通讯
 */
export class IoTDeviceService {
  private static instance: IoTDeviceService;
  private sensors: Map<string, SensorData> = new Map();
  private alerts: AlertInfo[] = [];
  private dataUpdateInterval: number = 10000; // 10秒更新一次
  private isAutoUpdate: boolean = true;
  private updateCallback: ((sensors: SensorData[]) => void) | null = null;
  private alertCallback: ((alerts: AlertInfo[]) => void) | null = null;

  private constructor() {
    this.initializeSensors();
    hilog.info(DOMAIN, TAG, '物联设备服务初始化完成');
  }

  /**
   * 获取单例实例
   */
  public static getInstance(): IoTDeviceService {
    if (!IoTDeviceService.instance) {
      IoTDeviceService.instance = new IoTDeviceService();
    }
    return IoTDeviceService.instance;
  }

  /**
   * 初始化传感器设备
   */
  private initializeSensors(): void {
    const defaultSensors: SensorData[] = [
      {
        id: 'sensor_water_pressure',
        name: '水压传感器',
        type: SensorType.WATER_PRESSURE,
        value: 0.85,
        unit: 'MPa',
        timestamp: Date.now(),
        status: DeviceStatus.ONLINE,
        threshold: 1.0,
        isWarning: false,
        description: '检测矿洞渗水情况'
      },
      {
        id: 'sensor_film_pressure',
        name: '薄膜传感器',
        type: SensorType.FILM_PRESSURE,
        value: 12.5,
        unit: 'kN',
        timestamp: Date.now(),
        status: DeviceStatus.ONLINE,
        threshold: 15.0,
        isWarning: false,
        description: '顶板压力检测'
      },
      {
        id: 'sensor_temperature',
        name: 'DHT11温度',
        type: SensorType.TEMPERATURE,
        value: 25.3,
        unit: '℃',
        timestamp: Date.now(),
        status: DeviceStatus.ONLINE,
        threshold: 35.0,
        isWarning: false,
        description: '环境温度监测'
      },
      {
        id: 'sensor_humidity',
        name: 'DHT11湿度',
        type: SensorType.HUMIDITY,
        value: 68.2,
        unit: '%',
        timestamp: Date.now(),
        status: DeviceStatus.ONLINE,
        threshold: 85.0,
        isWarning: false,
        description: '环境湿度监测'
      },
      {
        id: 'sensor_co2',
        name: 'CO2浓度传感器',
        type: SensorType.CO2_LEVEL,
        value: 0.04,
        unit: '%',
        timestamp: Date.now(),
        status: DeviceStatus.ONLINE,
        threshold: 0.05,
        isWarning: false,
        description: '空气质量监测'
      },
      {
        id: 'sensor_so2',
        name: 'SO2浓度传感器',
        type: SensorType.SO2_LEVEL,
        value: 0.001,
        unit: '%',
        timestamp: Date.now(),
        status: DeviceStatus.ONLINE,
        threshold: 0.002,
        isWarning: false,
        description: '有害气体监测'
      },
      {
        id: 'sensor_ultrasonic',
        name: '超声波测距',
        type: SensorType.ULTRASONIC_DISTANCE,
        value: 2.85,
        unit: 'm',
        timestamp: Date.now(),
        status: DeviceStatus.ONLINE,
        threshold: 2.5,
        isWarning: false,
        description: '顶板下沉监测'
      },
      {
        id: 'sensor_strain',
        name: '锚杆弯折传感器',
        type: SensorType.STRAIN_GAUGE,
        value: 0.02,
        unit: 'mm',
        timestamp: Date.now(),
        status: DeviceStatus.ONLINE,
        threshold: 0.05,
        isWarning: false,
        description: '锚杆应力监测'
      },
      {
        id: 'sensor_vibration',
        name: '震动传感器',
        type: SensorType.VIBRATION,
        value: 0.15,
        unit: 'g',
        timestamp: Date.now(),
        status: DeviceStatus.ONLINE,
        threshold: 0.5,
        isWarning: false,
        description: '冲击地压监测'
      },
      {
        id: 'module_lora',
        name: 'LoRa通讯模块',
        type: SensorType.LORA_MODULE,
        value: 1,
        unit: '',
        timestamp: Date.now(),
        status: DeviceStatus.ONLINE,
        description: '数据传输模块'
      },
      {
        id: 'display_oled',
        name: 'OLED显示屏',
        type: SensorType.OLED_DISPLAY,
        value: 1,
        unit: '',
        timestamp: Date.now(),
        status: DeviceStatus.ONLINE,
        description: '数据显示模块'
      }
    ];

    defaultSensors.forEach(sensor => {
      this.sensors.set(sensor.id, sensor);
    });
  }

  // ========================================
  // 数据采集接口方法
  // ========================================

  /**
   * 获取所有传感器数据
   */
  public getAllSensors(): SensorData[] {
    return Array.from(this.sensors.values());
  }

  /**
   * 获取指定传感器数据
   */
  public getSensorById(id: string): SensorData | undefined {
    return this.sensors.get(id);
  }

  /**
   * 获取指定类型的传感器数据
   */
  public getSensorsByType(type: SensorType): SensorData[] {
    return this.getAllSensors().filter(sensor => sensor.type === type);
  }

  /**
   * 更新传感器数据
   */
  public updateSensorData(id: string, value: number): boolean {
    const sensor = this.sensors.get(id);
    if (!sensor) {
      hilog.warn(DOMAIN, TAG, '传感器不存在: %{public}s', id);
      return false;
    }

    sensor.value = value;
    sensor.timestamp = Date.now();
    
    // 检查是否超过阈值
    if (sensor.threshold !== undefined) {
      sensor.isWarning = this.checkThreshold(sensor);
      if (sensor.isWarning) {
        this.generateAlert(sensor);
      }
    }

    this.sensors.set(id, sensor);
    
    // 触发数据更新回调
    if (this.updateCallback) {
      this.updateCallback(this.getAllSensors());
    }

    hilog.info(DOMAIN, TAG, '传感器数据更新: %{public}s = %{public}f', id, value);
    return true;
  }

  /**
   * 批量更新传感器数据
   */
  public batchUpdateSensorData(data: BatchUpdateData[]): void {
    data.forEach(item => {
      this.updateSensorData(item.id, item.value);
    });
  }

  /**
   * 模拟数据更新（用于测试）
   */
  public simulateDataUpdate(): void {
    this.sensors.forEach((sensor, id) => {
      if (sensor.type !== SensorType.LORA_MODULE && sensor.type !== SensorType.OLED_DISPLAY) {
        // 添加随机波动
        const fluctuation = (Math.random() - 0.5) * 0.1;
        const newValue = sensor.value * (1 + fluctuation);
        this.updateSensorData(id, Math.max(0, newValue));
      }
    });
  }

  // ========================================
  // 设备状态监控接口方法
  // ========================================

  /**
   * 获取设备状态
   */
  public getDeviceStatus(id: string): DeviceStatus | undefined {
    const sensor = this.sensors.get(id);
    return sensor?.status;
  }

  /**
   * 设置设备状态
   */
  public setDeviceStatus(id: string, status: DeviceStatus): boolean {
    const sensor = this.sensors.get(id);
    if (!sensor) {
      return false;
    }

    sensor.status = status;
    this.sensors.set(id, sensor);
    hilog.info(DOMAIN, TAG, '设备状态更新: %{public}s = %{public}s', id, status);
    return true;
  }

  /**
   * 获取在线设备数量
   */
  public getOnlineDeviceCount(): number {
    return this.getAllSensors().filter(sensor => sensor.status === DeviceStatus.ONLINE).length;
  }

  /**
   * 获取设备总数
   */
  public getTotalDeviceCount(): number {
    return this.sensors.size;
  }

  // ========================================
  // 预警管理接口方法
  // ========================================

  /**
   * 检查阈值
   */
  private checkThreshold(sensor: SensorData): boolean {
    if (!sensor.threshold) {
      return false;
    }

    // 特殊处理：超声波测距传感器，值越小越危险
    if (sensor.type === SensorType.ULTRASONIC_DISTANCE) {
      return sensor.value < sensor.threshold;
    }

    // 其他传感器，值越大越危险
    return sensor.value > sensor.threshold;
  }

  /**
   * 生成预警信息
   */
  private generateAlert(sensor: SensorData): void {
    if (!sensor.threshold) {
      return;
    }

    const alert: AlertInfo = {
      id: `alert_${Date.now()}`,
      sensorId: sensor.id,
      sensorName: sensor.name,
      level: this.calculateAlertLevel(sensor),
      message: `${sensor.name}超过预警阈值，当前值: ${sensor.value.toFixed(2)}${sensor.unit}`,
      timestamp: Date.now(),
      isHandled: false,
      value: sensor.value,
      threshold: sensor.threshold
    };

    this.alerts.unshift(alert);
    
    // 触发预警回调
    if (this.alertCallback) {
      this.alertCallback(this.alerts);
    }

    hilog.warn(DOMAIN, TAG, '生成预警: %{public}s', alert.message);
  }

  /**
   * 计算预警等级
   */
  private calculateAlertLevel(sensor: SensorData): AlertLevel {
    if (!sensor.threshold) {
      return AlertLevel.NORMAL;
    }

    const ratio = Math.abs(sensor.value - sensor.threshold) / sensor.threshold;
    
    if (ratio > 0.5) {
      return AlertLevel.RED;
    } else if (ratio > 0.3) {
      return AlertLevel.ORANGE;
    } else {
      return AlertLevel.YELLOW;
    }
  }

  /**
   * 获取所有预警信息
   */
  public getAllAlerts(): AlertInfo[] {
    return this.alerts;
  }

  /**
   * 获取未处理预警数量
   */
  public getUnhandledAlertCount(): number {
    return this.alerts.filter(alert => !alert.isHandled).length;
  }

  /**
   * 处理预警
   */
  public handleAlert(alertId: string): boolean {
    const alert = this.alerts.find(a => a.id === alertId);
    if (!alert) {
      return false;
    }

    alert.isHandled = true;
    hilog.info(DOMAIN, TAG, '预警已处理: %{public}s', alertId);
    return true;
  }

  /**
   * 清除所有预警
   */
  public clearAllAlerts(): void {
    this.alerts = [];
    hilog.info(DOMAIN, TAG, '所有预警已清除');
  }

  // ========================================
  // LoRa通讯接口方法
  // ========================================

  /**
   * 发送设备控制命令
   */
  public sendCommand(command: DeviceCommand): Promise<boolean> {
    return new Promise((resolve, reject) => {
      // 模拟LoRa通讯延迟
      setTimeout(() => {
        const sensor = this.sensors.get(command.deviceId);
        if (!sensor) {
          hilog.error(DOMAIN, TAG, '设备不存在: %{public}s', command.deviceId);
          reject(new Error('设备不存在'));
          return;
        }

        // 模拟命令执行
        hilog.info(DOMAIN, TAG, '命令发送成功: %{public}s -> %{public}s', 
          command.deviceId, command.command);
        resolve(true);
      }, 500);
    });
  }

  /**
   * 获取LoRa模块状态
   */
  public getLoRaStatus(): DeviceStatus {
    const loraModule = this.sensors.get('module_lora');
    return loraModule?.status || DeviceStatus.OFFLINE;
  }

  // ========================================
  // 数据同步与缓存接口方法
  // ========================================

  /**
   * 导出传感器数据
   */
  public exportSensorData(): string {
    const data: SensorDataExport = {
      timestamp: Date.now(),
      sensors: this.getAllSensors(),
      alerts: this.alerts
    };
    return JSON.stringify(data, null, 2);
  }

  /**
   * 设置数据更新回调
   */
  public setDataUpdateCallback(callback: (sensors: SensorData[]) => void): void {
    this.updateCallback = callback;
  }

  /**
   * 设置预警回调
   */
  public setAlertCallback(callback: (alerts: AlertInfo[]) => void): void {
    this.alertCallback = callback;
  }

  /**
   * 设置自动更新状态
   */
  public setAutoUpdate(enabled: boolean): void {
    this.isAutoUpdate = enabled;
    hilog.info(DOMAIN, TAG, '自动更新状态: %{public}s', enabled ? '开启' : '关闭');
  }

  /**
   * 获取自动更新状态
   */
  public getAutoUpdateStatus(): boolean {
    return this.isAutoUpdate;
  }

  /**
   * 设置数据更新间隔
   */
  public setUpdateInterval(interval: number): void {
    this.dataUpdateInterval = interval;
    hilog.info(DOMAIN, TAG, '数据更新间隔: %{public}d ms', interval);
  }

  /**
   * 获取数据更新间隔
   */
  public getUpdateInterval(): number {
    return this.dataUpdateInterval;
  }

  // ========================================
  // 后端数据同步接口（与 PC 三端数据互通）
  // ========================================

  /**
   * 从后端同步全部传感器数据与预警数据（失败时保留本地模拟数据兜底）
   */
  public async syncFromBackend(): Promise<void> {
    try {
      const list = await apiGetSensors();
      const sensors = this.mapBackendSensors(list);
      sensors.forEach((s) => {
        this.sensors.set(s.id, s);
      });
      hilog.info(DOMAIN, TAG, '后端传感器同步成功: %{public}d 台', sensors.length);
    } catch (err) {
      hilog.warn(DOMAIN, TAG, '后端传感器同步失败，使用本地数据: %{public}s', JSON.stringify(err));
    }

    try {
      const alerts = await apiGetAlerts();
      this.alerts = this.mapBackendAlerts(alerts);
      hilog.info(DOMAIN, TAG, '后端预警同步成功: %{public}d 条', this.alerts.length);
    } catch (err) {
      hilog.warn(DOMAIN, TAG, '后端预警同步失败，使用本地数据: %{public}s', JSON.stringify(err));
    }

    // 通知各页面刷新
    if (this.updateCallback) this.updateCallback(this.getAllSensors());
    if (this.alertCallback) this.alertCallback(this.alerts);
  }

  /**
   * 开启与后端 WebSocket 的实时数据通道（双端数据互通核心）
   * 后端每 10 秒推送传感器数据，预警产生时实时推送 alert_update
   */
  public startRealtime(): void {
    realtimeClient.connect('harmony');
    realtimeClient.on('sensor_update', (payload: Object) => {
      if (Array.isArray(payload)) {
        const list = this.mapBackendSensors(payload as BackendSensor[]);
        list.forEach((s) => this.sensors.set(s.id, s));
        if (this.updateCallback) this.updateCallback(this.getAllSensors());
      }
    });
    realtimeClient.on('alert_update', (payload: Object) => {
      if (!payload) return;
      const alert = this.mapBackendAlert(payload as BackendAlert);
      if (!this.alerts.some((a) => a.id === alert.id)) {
        this.alerts.unshift(alert);
      }
      if (this.alertCallback) this.alertCallback(this.alerts);
    });
  }

  /**
   * 是否已建立与后端的实时通道（用于避免本地模拟覆盖后端数据）
   */
  public isRealtimeConnected(): boolean {
    return realtimeClient.isConnected();
  }

  /**
   * 通过后端处理预警（与 PC 三端处置记录互通）
   */
  public async handleAlertViaBackend(alertId: string): Promise<boolean> {
    try {
      await apiHandleAlert(alertId, '鸿蒙端');
      this.handleAlert(alertId);
      return true;
    } catch (err) {
      hilog.error(DOMAIN, TAG, '后端预警处理失败: %{public}s', JSON.stringify(err));
      return this.handleAlert(alertId);
    }
  }

  // ========================================
  // 后端数据映射（内部工具）
  // ========================================

  private mapBackendSensors(list: BackendSensor[]): SensorData[] {
    return list.map((s) => {
      const type: SensorType = SENSOR_TYPE_BY_NAME[s.type] || SensorType.TEMPERATURE;
      const threshold = s.threshold !== null && s.threshold !== undefined ? s.threshold : undefined;
      const sensor: SensorData = {
        id: s.id,
        name: s.name,
        type: type,
        value: s.value,
        unit: s.unit || '',
        timestamp: Date.parse(s.updated_at) || Date.now(),
        status: s.status === 'ONLINE' ? DeviceStatus.ONLINE : DeviceStatus.OFFLINE,
        threshold: threshold,
        description: s.description || ''
      };
      if (threshold !== undefined) {
        sensor.isWarning = this.checkThreshold(sensor);
      }
      return sensor;
    });
  }

  private mapBackendAlerts(list: BackendAlert[]): AlertInfo[] {
    return list.map((a) => this.mapBackendAlert(a));
  }

  private mapBackendAlert(a: BackendAlert): AlertInfo {
    let level: AlertLevel = AlertLevel.YELLOW;
    if (a.level === 'RED') level = AlertLevel.RED;
    else if (a.level === 'ORANGE') level = AlertLevel.ORANGE;
    return {
      id: a.id,
      sensorId: a.sensor_id,
      sensorName: a.sensor_name,
      level: level,
      message: a.message || `${a.sensor_name}超过预警阈值`,
      timestamp: Date.parse(a.created_at) || Date.now(),
      isHandled: !!a.handled,
      value: a.value || 0,
      threshold: a.threshold || 0
    };
  }
}

// ========================================
// 导出单例实例
// ========================================

export const iotDeviceService = IoTDeviceService.getInstance();
