/**
 * ========================================
 * 物联网设备控制服务 - IoT Control Service
 * ========================================
 * 
 * 功能说明：
 * 1. 设备控制命令发送
 * 2. 控制结果反馈
 * 3. 批量控制操作
 * 4. 控制历史记录
 */

import { hilog } from '@kit.PerformanceAnalysisKit';
import { 
  IoTConnectionManager, 
  ControlCommand, 
  CommandResponse,
  ConnectionState 
} from './IoTConnectionInterface';
import { SensorData, SensorType, DeviceStatus } from './IoTDeviceService';

const DOMAIN = 0x0000;
const TAG = 'IoTControlService';

// ========================================
// 控制命令定义
// ========================================

/**
 * 传感器控制命令枚举
 */
export enum SensorCommand {
  // 基础控制
  TURN_ON = 'TURN_ON',             // 开启
  TURN_OFF = 'TURN_OFF',           // 关闭
  RESET = 'RESET',                 // 重置
  CALIBRATE = 'CALIBRATE',         // 校准
  
  // 参数设置
  SET_THRESHOLD = 'SET_THRESHOLD', // 设置阈值
  SET_INTERVAL = 'SET_INTERVAL',   // 设置采样间隔
  SET_MODE = 'SET_MODE',           // 设置工作模式
  
  // 数据操作
  REQUEST_DATA = 'REQUEST_DATA',   // 请求数据
  CLEAR_DATA = 'CLEAR_DATA',       // 清除数据
  EXPORT_DATA = 'EXPORT_DATA',     // 导出数据
  
  // 高级功能
  ENABLE_ALERT = 'ENABLE_ALERT',   // 启用预警
  DISABLE_ALERT = 'DISABLE_ALERT', // 禁用预警
  TEST_ALERT = 'TEST_ALERT',       // 测试预警
  FIRMWARE_UPDATE = 'FIRMWARE_UPDATE' // 固件更新
}

/**
 * 工作模式枚举
 */
export enum WorkMode {
  NORMAL = 'NORMAL',               // 正常模式
  LOW_POWER = 'LOW_POWER',         // 低功耗模式
  HIGH_PRECISION = 'HIGH_PRECISION', // 高精度模式
  CONTINUOUS = 'CONTINUOUS',       // 连续采样模式
  INTERVAL = 'INTERVAL'            // 间隔采样模式
}

/**
 * 控制参数接口
 */
export interface ControlParams {
  threshold?: number;              // 阈值
  interval?: number;               // 采样间隔（毫秒）
  mode?: WorkMode;                 // 工作模式
  duration?: number;               // 持续时间（毫秒）
  alertEnabled?: boolean;          // 是否启用预警
  sensitivity?: number;            // 灵敏度（0-1）
  range?: [number, number];        // 测量范围
}

/**
 * 阈值设置接口
 */
export interface ThresholdSetting {
  deviceId: string;
  threshold: number;
}

/**
 * 控制记录接口
 */
export interface ControlRecord {
  recordId: string;                // 记录ID
  deviceId: string;                // 设备ID
  command: string;                 // 命令
  params?: ControlParams;          // 参数
  success: boolean;                // 是否成功
  result?: Record<string, Object>; // 结果
  timestamp: number;               // 时间戳
  operator?: string;               // 操作者
}

// ========================================
// 设备控制服务类
// ========================================

/**
 * 物联网设备控制服务
 */
export class IoTControlService {
  private static instance: IoTControlService;
  private connectionManager: IoTConnectionManager;
  private controlHistory: ControlRecord[] = [];
  private maxHistorySize: number = 100;
  private pendingCommands: Map<string, ControlCommand> = new Map();
  
  private constructor() {
    this.connectionManager = IoTConnectionManager.getInstance();
    hilog.info(DOMAIN, TAG, '设备控制服务初始化完成');
  }
  
  /**
   * 获取单例实例
   */
  public static getInstance(): IoTControlService {
    if (!IoTControlService.instance) {
      IoTControlService.instance = new IoTControlService();
    }
    return IoTControlService.instance;
  }
  
  // ========================================
  // 基础控制方法
  // ========================================
  
  /**
   * 开启设备
   * @param deviceId 设备ID
   */
  public async turnOn(deviceId: string): Promise<CommandResponse> {
    hilog.info(DOMAIN, TAG, '开启设备: %{public}s', deviceId);
    return await this.executeCommand(deviceId, SensorCommand.TURN_ON);
  }
  
  /**
   * 关闭设备
   * @param deviceId 设备ID
   */
  public async turnOff(deviceId: string): Promise<CommandResponse> {
    hilog.info(DOMAIN, TAG, '关闭设备: %{public}s', deviceId);
    return await this.executeCommand(deviceId, SensorCommand.TURN_OFF);
  }
  
  /**
   * 重置设备
   * @param deviceId 设备ID
   */
  public async reset(deviceId: string): Promise<CommandResponse> {
    hilog.info(DOMAIN, TAG, '重置设备: %{public}s', deviceId);
    return await this.executeCommand(deviceId, SensorCommand.RESET);
  }
  
  /**
   * 校准设备
   * @param deviceId 设备ID
   */
  public async calibrate(deviceId: string): Promise<CommandResponse> {
    hilog.info(DOMAIN, TAG, '校准设备: %{public}s', deviceId);
    return await this.executeCommand(deviceId, SensorCommand.CALIBRATE);
  }
  
  // ========================================
  // 参数设置方法
  // ========================================
  
  /**
   * 设置预警阈值
   * @param deviceId 设备ID
   * @param threshold 阈值
   */
  public async setThreshold(deviceId: string, threshold: number): Promise<CommandResponse> {
    hilog.info(DOMAIN, TAG, '设置阈值: %{public}s = %{public}f', deviceId, threshold);
    const params: Record<string, number> = { 'threshold': threshold };
    return await this.executeCommand(deviceId, SensorCommand.SET_THRESHOLD, params);
  }
  
  /**
   * 设置采样间隔
   * @param deviceId 设备ID
   * @param interval 间隔（毫秒）
   */
  public async setInterval(deviceId: string, interval: number): Promise<CommandResponse> {
    hilog.info(DOMAIN, TAG, '设置采样间隔: %{public}s = %{public}d', deviceId, interval);
    const params: Record<string, number> = { 'interval': interval };
    return await this.executeCommand(deviceId, SensorCommand.SET_INTERVAL, params);
  }
  
  /**
   * 设置工作模式
   * @param deviceId 设备ID
   * @param mode 工作模式
   */
  public async setMode(deviceId: string, mode: WorkMode): Promise<CommandResponse> {
    hilog.info(DOMAIN, TAG, '设置工作模式: %{public}s = %{public}s', deviceId, mode);
    const params: Record<string, string> = { 'mode': mode };
    return await this.executeCommand(deviceId, SensorCommand.SET_MODE, params);
  }
  
  /**
   * 批量设置参数
   * @param deviceId 设备ID
   * @param params 参数对象
   */
  public async setParams(deviceId: string, params: ControlParams): Promise<CommandResponse> {
    hilog.info(DOMAIN, TAG, '批量设置参数: %{public}s', deviceId);
    
    const results: Record<string, Object> = {};
    let allSuccess = true;
    
    // 设置阈值
    if (params.threshold !== undefined) {
      const response = await this.setThreshold(deviceId, params.threshold);
      results['threshold'] = response.success;
      if (!response.success) allSuccess = false;
    }
    
    // 设置采样间隔
    if (params.interval !== undefined) {
      const response = await this.setInterval(deviceId, params.interval);
      results['interval'] = response.success;
      if (!response.success) allSuccess = false;
    }
    
    // 设置工作模式
    if (params.mode !== undefined) {
      const response = await this.setMode(deviceId, params.mode);
      results['mode'] = response.success;
      if (!response.success) allSuccess = false;
    }
    
    return {
      commandId: `batch_${Date.now()}`,
      deviceId: deviceId,
      success: allSuccess,
      result: results,
      timestamp: Date.now()
    };
  }
  
  // ========================================
  // 数据操作方法
  // ========================================
  
  /**
   * 请求数据
   * @param deviceId 设备ID
   */
  public async requestData(deviceId: string): Promise<CommandResponse> {
    hilog.info(DOMAIN, TAG, '请求数据: %{public}s', deviceId);
    return await this.executeCommand(deviceId, SensorCommand.REQUEST_DATA);
  }
  
  /**
   * 清除数据
   * @param deviceId 设备ID
   */
  public async clearData(deviceId: string): Promise<CommandResponse> {
    hilog.info(DOMAIN, TAG, '清除数据: %{public}s', deviceId);
    return await this.executeCommand(deviceId, SensorCommand.CLEAR_DATA);
  }
  
  /**
   * 导出数据
   * @param deviceId 设备ID
   */
  public async exportData(deviceId: string): Promise<CommandResponse> {
    hilog.info(DOMAIN, TAG, '导出数据: %{public}s', deviceId);
    return await this.executeCommand(deviceId, SensorCommand.EXPORT_DATA);
  }
  
  // ========================================
  // 预警控制方法
  // ========================================
  
  /**
   * 启用预警
   * @param deviceId 设备ID
   */
  public async enableAlert(deviceId: string): Promise<CommandResponse> {
    hilog.info(DOMAIN, TAG, '启用预警: %{public}s', deviceId);
    return await this.executeCommand(deviceId, SensorCommand.ENABLE_ALERT);
  }
  
  /**
   * 禁用预警
   * @param deviceId 设备ID
   */
  public async disableAlert(deviceId: string): Promise<CommandResponse> {
    hilog.info(DOMAIN, TAG, '禁用预警: %{public}s', deviceId);
    return await this.executeCommand(deviceId, SensorCommand.DISABLE_ALERT);
  }
  
  /**
   * 测试预警
   * @param deviceId 设备ID
   */
  public async testAlert(deviceId: string): Promise<CommandResponse> {
    hilog.info(DOMAIN, TAG, '测试预警: %{public}s', deviceId);
    return await this.executeCommand(deviceId, SensorCommand.TEST_ALERT);
  }
  
  // ========================================
  // 批量控制方法
  // ========================================
  
  /**
   * 批量开启设备
   * @param deviceIds 设备ID列表
   */
  public async batchTurnOn(deviceIds: string[]): Promise<Map<string, CommandResponse>> {
    const results = new Map<string, CommandResponse>();
    for (const deviceId of deviceIds) {
      const response = await this.turnOn(deviceId);
      results.set(deviceId, response);
    }
    return results;
  }
  
  /**
   * 批量关闭设备
   * @param deviceIds 设备ID列表
   */
  public async batchTurnOff(deviceIds: string[]): Promise<Map<string, CommandResponse>> {
    const results = new Map<string, CommandResponse>();
    for (const deviceId of deviceIds) {
      const response = await this.turnOff(deviceId);
      results.set(deviceId, response);
    }
    return results;
  }
  
  /**
   * 批量设置阈值
   * @param settings 设备阈值设置列表
   */
  public async batchSetThreshold(settings: ThresholdSetting[]): Promise<Map<string, CommandResponse>> {
    const results = new Map<string, CommandResponse>();
    for (const setting of settings) {
      const response = await this.setThreshold(setting.deviceId, setting.threshold);
      results.set(setting.deviceId, response);
    }
    return results;
  }
  
  // ========================================
  // 核心执行方法
  // ========================================
  
  /**
   * 执行控制命令
   * @param deviceId 设备ID
   * @param command 命令
   * @param params 参数
   */
  private async executeCommand(
    deviceId: string, 
    command: string, 
    params?: Record<string, string | number | boolean>
  ): Promise<CommandResponse> {
    const commandId = `cmd_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
    
    const controlCommand: ControlCommand = {
      commandId: commandId,
      deviceId: deviceId,
      command: command,
      params: params,
      timestamp: Date.now(),
      timeout: 10000
    };
    
    // 记录待处理命令
    this.pendingCommands.set(commandId, controlCommand);
    
    try {
      // 通过连接管理器发送命令
      const response = await this.connectionManager.sendCommand(controlCommand);
      
      // 记录控制历史
      this.addControlRecord({
        recordId: `record_${Date.now()}`,
        deviceId: deviceId,
        command: command,
        params: params as ControlParams,
        success: response.success,
        result: response.result,
        timestamp: Date.now()
      });
      
      return response;
    } catch (error) {
      const errorResponse: CommandResponse = {
        commandId: commandId,
        deviceId: deviceId,
        success: false,
        error: error instanceof Error ? error.message : '未知错误',
        timestamp: Date.now()
      };
      
      // 记录失败的控制历史
      const errorResult: Record<string, Object> = { 'error': errorResponse.error ?? '未知错误' };
      this.addControlRecord({
        recordId: `record_${Date.now()}`,
        deviceId: deviceId,
        command: command,
        params: params as ControlParams,
        success: false,
        result: errorResult,
        timestamp: Date.now()
      });
      
      return errorResponse;
    } finally {
      // 移除待处理命令
      this.pendingCommands.delete(commandId);
    }
  }
  
  // ========================================
  // 历史记录管理
  // ========================================
  
  /**
   * 添加控制记录
   */
  private addControlRecord(record: ControlRecord): void {
    this.controlHistory.push(record);
    
    // 限制历史记录数量
    if (this.controlHistory.length > this.maxHistorySize) {
      this.controlHistory.shift();
    }
  }
  
  /**
   * 获取控制历史
   * @param deviceId 设备ID（可选）
   * @param limit 数量限制
   */
  public getControlHistory(deviceId?: string, limit: number = 50): ControlRecord[] {
    let history = this.controlHistory;
    
    if (deviceId) {
      history = history.filter(record => record.deviceId === deviceId);
    }
    
    return history.slice(-limit);
  }
  
  /**
   * 清除控制历史
   */
  public clearControlHistory(): void {
    this.controlHistory = [];
    hilog.info(DOMAIN, TAG, '控制历史已清除');
  }
  
  // ========================================
  // 状态查询方法
  // ========================================
  
  /**
   * 获取待处理命令数量
   */
  public getPendingCommandCount(): number {
    return this.pendingCommands.size;
  }
  
  /**
   * 获取待处理命令列表
   */
  public getPendingCommands(): ControlCommand[] {
    return Array.from(this.pendingCommands.values());
  }
  
  /**
   * 检查设备是否可控
   * @param deviceId 设备ID
   */
  public async isControllable(deviceId: string): Promise<boolean> {
    const connector = this.connectionManager.getConnector(deviceId);
    if (!connector) {
      return false;
    }
    
    return connector.getState() === ConnectionState.CONNECTED;
  }
}
