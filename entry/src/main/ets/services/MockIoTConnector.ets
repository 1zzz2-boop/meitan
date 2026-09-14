/**
 * ========================================
 * 模拟物联网连接器 - Mock IoT Connector
 * ========================================
 * 
 * 功能说明：
 * 1. 实现IIoTConnector接口
 * 2. 模拟设备连接、断开、发送命令等操作
 * 3. 用于演示和测试物联网功能
 */

import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  IIoTConnector,
  ConnectionProtocol,
  ConnectionState,
  ConnectionConfig,
  DeviceMessage,
  ControlCommand,
  CommandResponse,
  MessageType
} from './IoTConnectionInterface';

const DOMAIN = 0x0000;
const TAG = 'MockIoTConnector';

/**
 * 模拟物联网连接器
 * 实现IIoTConnector接口，用于演示和测试
 */
export class MockIoTConnector implements IIoTConnector {
  private deviceId: string;
  private state: ConnectionState = ConnectionState.DISCONNECTED;
  private stateCallbacks: ((state: ConnectionState) => void)[] = [];
  private errorCallbacks: ((error: Error) => void)[] = [];
  private subscriptions: Map<string, (message: DeviceMessage) => void> = new Map();
  private heartbeatInterval: number = -1;
  private config: ConnectionConfig | null = null;
  
  constructor(deviceId: string) {
    this.deviceId = deviceId;
    hilog.info(DOMAIN, TAG, '模拟连接器创建: %{public}s', deviceId);
  }
  
  /**
   * 获取连接协议类型
   */
  public getProtocol(): ConnectionProtocol {
    return ConnectionProtocol.MQTT; // 模拟MQTT协议
  }
  
  /**
   * 获取当前连接状态
   */
  public getState(): ConnectionState {
    return this.state;
  }
  
  /**
   * 连接设备
   */
  public async connect(config: ConnectionConfig): Promise<boolean> {
    hilog.info(DOMAIN, TAG, '开始连接设备: %{public}s', this.deviceId);
    
    // 更新状态为连接中
    this.updateState(ConnectionState.CONNECTING);
    
    // 模拟连接延迟
    await this.delay(1000 + Math.random() * 1000);
    
    // 模拟连接成功（90%成功率）
    if (Math.random() > 0.1) {
      this.config = config;
      this.updateState(ConnectionState.CONNECTED);
      this.startHeartbeat();
      hilog.info(DOMAIN, TAG, '设备连接成功: %{public}s', this.deviceId);
      return true;
    } else {
      this.updateState(ConnectionState.ERROR);
      this.notifyError(new Error('连接失败：模拟网络错误'));
      hilog.error(DOMAIN, TAG, '设备连接失败: %{public}s', this.deviceId);
      return false;
    }
  }
  
  /**
   * 断开连接
   */
  public async disconnect(): Promise<void> {
    hilog.info(DOMAIN, TAG, '断开设备连接: %{public}s', this.deviceId);
    
    // 停止心跳
    this.stopHeartbeat();
    
    // 模拟断开延迟
    await this.delay(500);
    
    this.updateState(ConnectionState.DISCONNECTED);
    this.config = null;
    hilog.info(DOMAIN, TAG, '设备已断开: %{public}s', this.deviceId);
  }
  
  /**
   * 发送消息
   */
  public async send(message: DeviceMessage): Promise<boolean> {
    if (this.state !== ConnectionState.CONNECTED) {
      hilog.warn(DOMAIN, TAG, '设备未连接，无法发送消息');
      return false;
    }
    
    // 模拟发送延迟
    await this.delay(100 + Math.random() * 200);
    
    hilog.info(DOMAIN, TAG, '消息发送成功: %{public}s -> %{public}s', 
      this.deviceId, message.type);
    return true;
  }
  
  /**
   * 发送控制命令
   */
  public async sendCommand(command: ControlCommand): Promise<CommandResponse> {
    hilog.info(DOMAIN, TAG, '发送控制命令: %{public}s -> %{public}s', 
      this.deviceId, command.command);
    
    if (this.state !== ConnectionState.CONNECTED) {
      return {
        commandId: command.commandId,
        deviceId: command.deviceId,
        success: false,
        error: '设备未连接',
        timestamp: Date.now()
      };
    }
    
    // 模拟命令执行延迟
    await this.delay(200 + Math.random() * 300);
    
    // 模拟命令执行结果（95%成功率）
    const success = Math.random() > 0.05;
    
    if (success) {
      const result: Record<string, Object> = this.simulateCommandResult(command);
      
      // 触发数据订阅回调
      this.notifySubscribers({
        deviceId: this.deviceId,
        type: MessageType.RESPONSE,
        payload: result,
        timestamp: Date.now()
      });
      
      return {
        commandId: command.commandId,
        deviceId: command.deviceId,
        success: true,
        result: result,
        timestamp: Date.now()
      };
    } else {
      return {
        commandId: command.commandId,
        deviceId: command.deviceId,
        success: false,
        error: '命令执行失败：模拟设备错误',
        timestamp: Date.now()
      };
    }
  }
  
  /**
   * 订阅消息
   */
  public subscribe(topic: string, callback: (message: DeviceMessage) => void): void {
    this.subscriptions.set(topic, callback);
    hilog.info(DOMAIN, TAG, '订阅主题: %{public}s -> %{public}s', this.deviceId, topic);
  }
  
  /**
   * 取消订阅
   */
  public unsubscribe(topic: string): void {
    this.subscriptions.delete(topic);
    hilog.info(DOMAIN, TAG, '取消订阅: %{public}s -> %{public}s', this.deviceId, topic);
  }
  
  /**
   * 设置连接状态变化回调
   */
  public onStateChange(callback: (state: ConnectionState) => void): void {
    this.stateCallbacks.push(callback);
  }
  
  /**
   * 设置错误回调
   */
  public onError(callback: (error: Error) => void): void {
    this.errorCallbacks.push(callback);
  }
  
  // ========================================
  // 私有方法
  // ========================================
  
  /**
   * 更新连接状态
   */
  private updateState(newState: ConnectionState): void {
    this.state = newState;
    this.stateCallbacks.forEach(callback => callback(newState));
    hilog.info(DOMAIN, TAG, '连接状态变更: %{public}s -> %{public}s', 
      this.deviceId, newState);
  }
  
  /**
   * 通知错误
   */
  private notifyError(error: Error): void {
    this.errorCallbacks.forEach(callback => callback(error));
  }
  
  /**
   * 通知订阅者
   */
  private notifySubscribers(message: DeviceMessage): void {
    this.subscriptions.forEach(callback => callback(message));
  }
  
  /**
   * 模拟命令执行结果
   */
  private simulateCommandResult(command: ControlCommand): Record<string, Object> {
    const result: Record<string, Object> = {
      'command': command.command,
      'executedAt': Date.now()
    };
    
    switch (command.command) {
      case 'TURN_ON':
        result['status'] = 'ON';
        result['power'] = 100;
        break;
      case 'TURN_OFF':
        result['status'] = 'OFF';
        result['power'] = 0;
        break;
      case 'RESET':
        result['status'] = 'RESET';
        result['resetTime'] = Date.now();
        break;
      case 'CALIBRATE':
        result['status'] = 'CALIBRATED';
        result['calibrationValue'] = 0.0;
        break;
      case 'SET_THRESHOLD':
        result['threshold'] = command.params?.['threshold'] ?? 0;
        break;
      case 'SET_INTERVAL':
        result['interval'] = command.params?.['interval'] ?? 1000;
        break;
      case 'REQUEST_DATA':
        // 模拟传感器数据
        result['value'] = Math.random() * 100;
        result['unit'] = 'unknown';
        result['timestamp'] = Date.now();
        break;
      case 'ENABLE_ALERT':
        result['alertEnabled'] = true;
        break;
      case 'DISABLE_ALERT':
        result['alertEnabled'] = false;
        break;
      default:
        result['status'] = 'EXECUTED';
    }
    
    return result;
  }
  
  /**
   * 启动心跳
   */
  private startHeartbeat(): void {
    this.stopHeartbeat();
    
    this.heartbeatInterval = setInterval(() => {
      if (this.state === ConnectionState.CONNECTED) {
        // 模拟心跳消息
        this.notifySubscribers({
          deviceId: this.deviceId,
          type: MessageType.HEARTBEAT,
          payload: { 'timestamp': Date.now() },
          timestamp: Date.now()
        });
      }
    }, 30000); // 30秒心跳
    
    hilog.info(DOMAIN, TAG, '心跳已启动: %{public}s', this.deviceId);
  }
  
  /**
   * 停止心跳
   */
  private stopHeartbeat(): void {
    if (this.heartbeatInterval !== -1) {
      clearInterval(this.heartbeatInterval);
      this.heartbeatInterval = -1;
      hilog.info(DOMAIN, TAG, '心跳已停止: %{public}s', this.deviceId);
    }
  }
  
  /**
   * 延迟函数
   */
  private delay(ms: number): Promise<void> {
    return new Promise(resolve => setTimeout(resolve, ms));
  }
}
