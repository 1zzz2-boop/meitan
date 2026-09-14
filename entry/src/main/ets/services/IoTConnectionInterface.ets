/**
 * ========================================
 * 物联网连接接口定义 - IoT Connection Interface
 * ========================================
 * 
 * 功能说明：
 * 1. 定义物联网设备连接的标准接口
 * 2. 支持多种连接协议（MQTT、HTTP、WebSocket、蓝牙、串口等）
 * 3. 预留扩展接口，便于后续实现真实连接
 * 
 * 设计原则：
 * - 接口优先，实现可替换
 * - 支持同步和异步操作
 * - 统一的错误处理机制
 */

import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;
const TAG = 'IoTConnectionInterface';

// ========================================
// 连接配置接口
// ========================================

/**
 * 连接协议类型
 */
export enum ConnectionProtocol {
  MQTT = 'MQTT',              // MQTT协议
  HTTP = 'HTTP',              // HTTP/HTTPS协议
  WEBSOCKET = 'WEBSOCKET',    // WebSocket协议
  BLUETOOTH = 'BLUETOOTH',    // 蓝牙连接
  SERIAL = 'SERIAL',         // 串口连接
  LORA = 'LORA',             // LoRa无线
  WIFI_DIRECT = 'WIFI_DIRECT' // WiFi直连
}

/**
 * 连接状态
 */
export enum ConnectionState {
  DISCONNECTED = 'DISCONNECTED',   // 未连接
  CONNECTING = 'CONNECTING',       // 连接中
  CONNECTED = 'CONNECTED',         // 已连接
  RECONNECTING = 'RECONNECTING',   // 重连中
  ERROR = 'ERROR'                  // 连接错误
}

/**
 * 基础连接配置
 */
export interface BaseConnectionConfig {
  protocol: ConnectionProtocol;     // 连接协议
  deviceId: string;                 // 设备ID
  timeout: number;                  // 超时时间（毫秒）
  retryCount: number;               // 重试次数
  retryInterval: number;            // 重试间隔（毫秒）
}

/**
 * MQTT连接配置
 */
export interface MQTTConnectionConfig extends BaseConnectionConfig {
  protocol: ConnectionProtocol.MQTT;
  brokerUrl: string;                // MQTT代理地址
  port: number;                     // 端口号
  clientId: string;                 // 客户端ID
  username?: string;                // 用户名
  password?: string;                // 密码
  keepAlive: number;                // 心跳间隔（秒）
  cleanSession: boolean;            // 清除会话
  qos: 0 | 1 | 2;                   // 服务质量等级
}

/**
 * HTTP连接配置
 */
export interface HTTPConnectionConfig extends BaseConnectionConfig {
  protocol: ConnectionProtocol.HTTP;
  baseUrl: string;                  // 基础URL
  apiKey?: string;                  // API密钥
  headers?: Record<string, string>; // 自定义请求头
}

/**
 * WebSocket连接配置
 */
export interface WebSocketConnectionConfig extends BaseConnectionConfig {
  protocol: ConnectionProtocol.WEBSOCKET;
  wsUrl: string;                    // WebSocket地址
  protocols?: string[];             // 子协议列表
}

/**
 * 蓝牙连接配置
 */
export interface BluetoothConnectionConfig extends BaseConnectionConfig {
  protocol: ConnectionProtocol.BLUETOOTH;
  deviceMac: string;                // 设备MAC地址
  serviceUUID: string;              // 服务UUID
  characteristicUUID: string;       // 特征UUID
}

/**
 * 串口连接配置
 */
export interface SerialConnectionConfig extends BaseConnectionConfig {
  protocol: ConnectionProtocol.SERIAL;
  port: string;                     // 串口号（如：/dev/ttyUSB0）
  baudRate: number;                 // 波特率
  dataBits: 5 | 6 | 7 | 8;          // 数据位
  stopBits: 1 | 2;                  // 停止位
  parity: 'none' | 'odd' | 'even';  // 校验位
}

/**
 * LoRa连接配置
 */
export interface LoRaConnectionConfig extends BaseConnectionConfig {
  protocol: ConnectionProtocol.LORA;
  frequency: number;                // 频率（MHz）
  spreadingFactor: number;          // 扩频因子
  bandwidth: number;                // 带宽（kHz）
  txPower: number;                  // 发射功率（dBm）
}

/**
 * 统一连接配置类型
 */
export type ConnectionConfig = 
  | MQTTConnectionConfig 
  | HTTPConnectionConfig 
  | WebSocketConnectionConfig 
  | BluetoothConnectionConfig 
  | SerialConnectionConfig 
  | LoRaConnectionConfig;

// ========================================
// 消息和数据接口
// ========================================

/**
 * 设备消息接口
 */
export interface DeviceMessage {
  deviceId: string;                 // 设备ID
  type: MessageType;                // 消息类型
  topic?: string;                   // 主题（MQTT）
  payload: string | Record<string, Object>; // 消息内容
  timestamp: number;                // 时间戳
  qos?: 0 | 1 | 2;                  // QoS等级
}

/**
 * 消息类型
 */
export enum MessageType {
  DATA = 'DATA',                    // 数据消息
  COMMAND = 'COMMAND',              // 命令消息
  RESPONSE = 'RESPONSE',            // 响应消息
  STATUS = 'STATUS',                // 状态消息
  ALERT = 'ALERT',                  // 预警消息
  HEARTBEAT = 'HEARTBEAT'           // 心跳消息
}

/**
 * 控制命令接口
 */
export interface ControlCommand {
  commandId: string;                // 命令ID
  deviceId: string;                 // 设备ID
  command: string;                  // 命令名称
  params?: Record<string, string | number | boolean>; // 命令参数
  timestamp: number;                // 时间戳
  timeout?: number;                 // 超时时间
}

/**
 * 命令响应接口
 */
export interface CommandResponse {
  commandId: string;                // 命令ID
  deviceId: string;                 // 设备ID
  success: boolean;                 // 是否成功
  result?: Record<string, Object>;  // 返回结果
  error?: string;                   // 错误信息
  timestamp: number;                // 时间戳
}

// ========================================
// 连接器接口定义
// ========================================

/**
 * 物联网连接器接口（核心接口）
 * 所有具体的连接实现都需要实现此接口
 */
export interface IIoTConnector {
  /**
   * 获取连接协议类型
   */
  getProtocol(): ConnectionProtocol;
  
  /**
   * 获取当前连接状态
   */
  getState(): ConnectionState;
  
  /**
   * 连接设备
   * @param config 连接配置
   * @returns 连接是否成功
   */
  connect(config: ConnectionConfig): Promise<boolean>;
  
  /**
   * 断开连接
   */
  disconnect(): Promise<void>;
  
  /**
   * 发送消息
   * @param message 消息内容
   * @returns 是否发送成功
   */
  send(message: DeviceMessage): Promise<boolean>;
  
  /**
   * 发送控制命令
   * @param command 控制命令
   * @returns 命令响应
   */
  sendCommand(command: ControlCommand): Promise<CommandResponse>;
  
  /**
   * 订阅消息
   * @param topic 主题（MQTT）或事件类型
   * @param callback 消息回调
   */
  subscribe(topic: string, callback: (message: DeviceMessage) => void): void;
  
  /**
   * 取消订阅
   * @param topic 主题
   */
  unsubscribe(topic: string): void;
  
  /**
   * 设置连接状态变化回调
   * @param callback 状态变化回调
   */
  onStateChange(callback: (state: ConnectionState) => void): void;
  
  /**
   * 设置错误回调
   * @param callback 错误回调
   */
  onError(callback: (error: Error) => void): void;
}

// ========================================
// 设备管理接口
// ========================================

/**
 * 设备信息接口
 */
export interface IotDeviceInfo {
  deviceId: string;                 // 设备ID
  deviceName: string;               // 设备名称
  deviceType: string;               // 设备类型
  manufacturer?: string;            // 制造商
  model?: string;                   // 型号
  firmwareVersion?: string;         // 固件版本
  protocol: ConnectionProtocol;     // 支持的协议
  capabilities: string[];           // 设备能力列表
  connectionState: ConnectionState; // 连接状态
  lastSeen: number;                 // 最后在线时间
  metadata?: Record<string, Object>; // 其他元数据
}

/**
 * 设备管理器接口
 */
export interface IDeviceManager {
  /**
   * 扫描设备
   * @param timeout 扫描超时时间
   * @returns 发现的设备列表
   */
  scanDevices(timeout: number): Promise<IotDeviceInfo[]>;
  
  /**
   * 获取已配对的设备列表
   */
  getPairedDevices(): IotDeviceInfo[];
  
  /**
   * 配对设备
   * @param deviceId 设备ID
   * @param config 连接配置
   */
  pairDevice(deviceId: string, config: ConnectionConfig): Promise<boolean>;
  
  /**
   * 取消配对
   * @param deviceId 设备ID
   */
  unpairDevice(deviceId: string): Promise<void>;
  
  /**
   * 连接设备
   * @param deviceId 设备ID
   */
  connectDevice(deviceId: string): Promise<boolean>;
  
  /**
   * 断开设备
   * @param deviceId 设备ID
   */
  disconnectDevice(deviceId: string): Promise<void>;
  
  /**
   * 获取设备连接器
   * @param deviceId 设备ID
   */
  getConnector(deviceId: string): IIoTConnector | null;
}

// ========================================
// 数据处理接口
// ========================================

/**
 * 数据解析器接口
 */
export interface IDataParser {
  /**
   * 解析接收到的数据
   * @param rawdata 原始数据
   * @returns 解析后的数据
   */
  parse(rawdata: string | ArrayBuffer): Record<string, Object>;
  
  /**
   * 序列化要发送的数据
   * @param data 数据对象
   * @returns 序列化后的数据
   */
  serialize(data: Record<string, Object>): string;
}

/**
 * 数据过滤器接口
 */
export interface IDataFilter {
  /**
   * 过滤数据
   * @param data 原始数据
   * @returns 过滤后的数据
   */
  filter(data: Record<string, Object>): boolean;
  
  /**
   * 转换数据
   * @param data 原始数据
   * @returns 转换后的数据
   */
  transform(data: Record<string, Object>): Record<string, Object>;
}

// ========================================
// 连接器工厂接口
// ========================================

/**
 * 连接器工厂接口
 */
export interface IConnectorFactory {
  /**
   * 创建连接器
   * @param protocol 协议类型
   * @returns 连接器实例
   */
  createConnector(protocol: ConnectionProtocol): IIoTConnector;
  
  /**
   * 注册连接器构造函数
   * @param protocol 协议类型
   * @param creator 构造函数
   */
  registerConnector(protocol: ConnectionProtocol, creator: () => IIoTConnector): void;
}

// ========================================
// 预留的回调类型定义
// ========================================

/**
 * 连接状态变化回调
 */
export type ConnectionStateCallback = (deviceId: string, state: ConnectionState) => void;

/**
 * 数据接收回调
 */
export type DataReceivedCallback = (deviceId: string, data: Record<string, Object>) => void;

/**
 * 命令响应回调
 */
export type CommandResponseCallback = (response: CommandResponse) => void;

/**
 * 错误回调
 */
export type ErrorCallback = (deviceId: string, error: Error) => void;

// ========================================
// 连接管理器（预留实现）
// ========================================

/**
 * 物联网连接管理器
 * 统一管理所有设备连接
 */
export class IoTConnectionManager {
  private static instance: IoTConnectionManager;
  private connectors: Map<string, IIoTConnector> = new Map();
  private deviceConfigs: Map<string, ConnectionConfig> = new Map();
  private stateCallbacks: ConnectionStateCallback[] = [];
  private dataCallbacks: DataReceivedCallback[] = [];
  private errorCallbacks: ErrorCallback[] = [];
  
  private constructor() {
    hilog.info(DOMAIN, TAG, '物联网连接管理器初始化');
  }
  
  /**
   * 获取单例实例
   */
  public static getInstance(): IoTConnectionManager {
    if (!IoTConnectionManager.instance) {
      IoTConnectionManager.instance = new IoTConnectionManager();
    }
    return IoTConnectionManager.instance;
  }
  
  /**
   * 注册连接器
   * @param deviceId 设备ID
   * @param connector 连接器实例
   */
  public registerConnector(deviceId: string, connector: IIoTConnector): void {
    this.connectors.set(deviceId, connector);
    hilog.info(DOMAIN, TAG, '注册连接器: %{public}s', deviceId);
  }
  
  /**
   * 获取连接器
   * @param deviceId 设备ID
   */
  public getConnector(deviceId: string): IIoTConnector | null {
    return this.connectors.get(deviceId) ?? null;
  }
  
  /**
   * 保存设备配置
   */
  public saveDeviceConfig(deviceId: string, config: ConnectionConfig): void {
    this.deviceConfigs.set(deviceId, config);
  }
  
  /**
   * 获取设备配置
   */
  public getDeviceConfig(deviceId: string): ConnectionConfig | null {
    return this.deviceConfigs.get(deviceId) ?? null;
  }
  
  /**
   * 连接设备
   * @param deviceId 设备ID
   * @param config 连接配置
   */
  public async connectDevice(deviceId: string, config: ConnectionConfig): Promise<boolean> {
    const connector = this.connectors.get(deviceId);
    if (!connector) {
      hilog.error(DOMAIN, TAG, '连接器不存在: %{public}s', deviceId);
      return false;
    }
    
    this.saveDeviceConfig(deviceId, config);
    return await connector.connect(config);
  }
  
  /**
   * 断开设备
   */
  public async disconnectDevice(deviceId: string): Promise<void> {
    const connector = this.connectors.get(deviceId);
    if (connector) {
      await connector.disconnect();
    }
  }
  
  /**
   * 发送控制命令
   * @param command 控制命令
   */
  public async sendCommand(command: ControlCommand): Promise<CommandResponse> {
    const connector = this.connectors.get(command.deviceId);
    if (!connector) {
      return {
        commandId: command.commandId,
        deviceId: command.deviceId,
        success: false,
        error: '连接器不存在',
        timestamp: Date.now()
      };
    }
    
    return await connector.sendCommand(command);
  }
  
  /**
   * 广播数据
   */
  public broadcastData(deviceId: string, data: Record<string, Object>): void {
    this.dataCallbacks.forEach(callback => {
      callback(deviceId, data);
    });
  }
  
  /**
   * 注册状态变化回调
   */
  public onStateChange(callback: ConnectionStateCallback): void {
    this.stateCallbacks.push(callback);
  }
  
  /**
   * 注册数据接收回调
   */
  public onDataReceived(callback: DataReceivedCallback): void {
    this.dataCallbacks.push(callback);
  }
  
  /**
   * 注册错误回调
   */
  public onError(callback: ErrorCallback): void {
    this.errorCallbacks.push(callback);
  }
  
  /**
   * 获取所有已连接的设备
   */
  public getConnectedDevices(): string[] {
    const connected: string[] = [];
    this.connectors.forEach((connector, deviceId) => {
      if (connector.getState() === ConnectionState.CONNECTED) {
        connected.push(deviceId);
      }
    });
    return connected;
  }
}
