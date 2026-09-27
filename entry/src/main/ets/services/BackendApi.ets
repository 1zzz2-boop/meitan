/**
 * ========================================
 * 后端 API 客户端 - Backend API Client
 * ========================================
 *
 * 功能说明：
 * 1. HTTP 请求封装（登录、传感器、预警、分析、监管）
 * 2. WebSocket 实时数据通道（与 PC 三端共用后端数据源，实现双端数据互通）
 *
 * 服务器地址说明：
 * - 模拟器运行时：后端运行在 PC 上，模拟器通过 10.0.2.2 访问宿主机
 * - 真机运行时：改为 PC 的局域网 IP，如 http://192.168.x.x:3000
 */
import { http } from '@kit.NetworkKit';
import { webSocket } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;
const TAG = 'BackendApi';

// 后端 HTTP 服务地址（PC 三端 + 鸿蒙端共用）
export const API_BASE = 'http://10.0.2.2:3000';
// 后端 WebSocket 实时通道地址
export const WS_URL = 'ws://10.0.2.2:8080';

// 通用错误响应体
interface ApiErrorBody {
  message?: string;
  error?: string;
}

// 会话令牌（登录成功后由服务端签发，接口请求自动携带）
let authToken: string = '';

/** 记录当前会话令牌（登录成功后调用，退出登录调用 clearAuthToken） */
export function setAuthToken(token: string): void {
  authToken = token || '';
}

/** 读取当前会话令牌 */
export function getAuthToken(): string {
  return authToken;
}

/** 清除会话令牌（退出登录） */
export function clearAuthToken(): void {
  authToken = '';
}

/**
 * 发起 HTTP 请求（GET/POST），自动解析 JSON
 * 已登录则自动携带 `Authorization: Bearer <token>` 交由后端会话鉴权
 */
export async function apiRequest<T>(path: string, method: http.RequestMethod = http.RequestMethod.GET, body?: object): Promise<T> {
  const httpRequest = http.createHttp();
  try {
    const header: Record<string, string> = {
      'Content-Type': 'application/json'
    };
    if (authToken.length > 0) {
      header['Authorization'] = 'Bearer ' + authToken;
    }
    const options: http.HttpRequestOptions = {
      method,
      header,
      connectTimeout: 5000,
      readTimeout: 8000,
      expectDataType: http.HttpDataType.STRING
    };
    if (body !== undefined) {
      options.extraData = JSON.stringify(body);
    }
    const response = await httpRequest.request(API_BASE + path, options);
    const result: string = response.result as string;
    const code: number = response.responseCode;

    if (code < 200 || code >= 300) {
      let msg: string = '';
      try {
        const eb = JSON.parse(result) as ApiErrorBody;
        msg = eb.message || eb.error || '';
      } catch (e) {
        msg = '';
      }
      throw new Error(msg || `请求失败(${code})`);
    }
    if (!result || result.length === 0) {
      throw new Error('服务器返回为空');
    }
    const json: T = JSON.parse(result) as T;
    return json;
  } catch (err) {
    hilog.error(DOMAIN, TAG, 'HTTP 请求失败 %{public}s: %{public}s', API_BASE + path, JSON.stringify(err));
    throw new Error('网络请求异常');
  } finally {
    httpRequest.destroy();
  }
}

// ========================================
// 认证
// ========================================
export interface BackendUser {
  id: number;
  username: string;
  displayName: string;
  role: string;
  endName: string;
}

export interface LoginResult {
  ok: boolean;
  token: string;
  user: BackendUser;
}

interface LoginPayload {
  username: string;
  password: string;
  captchaId: string;
  captchaCode: string;
}

// 服务端图形验证码
export interface CaptchaResult {
  captchaId: string;
  code: string;
  expiresIn: number;
}

// 获取验证码（服务端生成）
export function apiCaptcha(): Promise<CaptchaResult> {
  return apiRequest<CaptchaResult>('/api/auth/captcha', http.RequestMethod.GET);
}

// 登录原始返回：区分「验证码被拒」「凭据被拒(401)」与「网络不可达」
export interface LoginRawResult {
  ok: boolean;
  token: string;                      // 会话令牌（服务端签发，后续请求携带）
  captchaRejected: boolean;    // 验证码错误或过期
  credentialRejected: boolean; // 后端可达但账号/密码错误
  reachable: boolean;          // 后端是否可达
  user: BackendUser;
  message: string;
}

export async function apiLogin(username: string, password: string, captchaId: string, captchaCode: string): Promise<LoginRawResult> {
  const payload: LoginPayload = { username, password, captchaId, captchaCode };
  try {
    const result = await apiRequest<LoginResult>('/api/auth/login', http.RequestMethod.POST, payload);
    setAuthToken(result.token);
    return { ok: true, token: result.token, captchaRejected: false, credentialRejected: false, reachable: true, user: result.user, message: '' };
  } catch (err) {
    const msg = (err instanceof Error) ? err.message : '';
    // 验证码错误 / 过期 / 未输入 → 需刷新验证码
    if (msg.indexOf('验证码') >= 0) {
      return { ok: false, token: '', captchaRejected: true, credentialRejected: false, reachable: true, user: {} as BackendUser, message: msg };
    }
    // 401 携带后端中文提示（账号不存在 / 密码错误）
    if (msg === '账号不存在' || msg === '密码错误') {
      return { ok: false, token: '', captchaRejected: false, credentialRejected: true, reachable: true, user: {} as BackendUser, message: msg };
    }
    // 其余（超时/连接失败/非 2xx 未知）视为网络不可达
    return { ok: false, token: '', captchaRejected: false, credentialRejected: false, reachable: false, user: {} as BackendUser, message: '网络异常' };
  }
}

// 注册三端账号
export interface RegisterResult {
  ok: boolean;
  user: BackendUser;
}

interface RegisterPayload {
  username: string;
  password: string;
  role: string;
  display_name: string;
}

export function apiRegister(username: string, password: string, role: string, displayName: string): Promise<RegisterResult> {
  const payload: RegisterPayload = { username, password, role, display_name: displayName || username };
  return apiRequest<RegisterResult>('/api/auth/register', http.RequestMethod.POST, payload);
}

export interface ChangePasswordResult {
  success: boolean;
  message: string;
}

interface ChangePasswordPayload {
  username: string;
  oldPassword: string;
  newPassword: string;
}

export function apiChangePassword(username: string, oldPassword: string, newPassword: string): Promise<ChangePasswordResult> {
  const payload: ChangePasswordPayload = { username, oldPassword, newPassword };
  return apiRequest<ChangePasswordResult>('/api/auth/change-password', http.RequestMethod.POST, payload);
}

// ========================================
// 系统信息
// ========================================
export interface SystemInfo {
  name: string;
  version: string;
  build: string;
  platform: string;
  nodeVersion: string;
  database: string;
  apiSdkVersion: string;
  serverTime: string;
  copyright: string;
}

export function apiGetSystemInfo(): Promise<SystemInfo> {
  return apiRequest<SystemInfo>('/api/system/info');
}

// ========================================
// 用户管理（修改用户信息）
// ========================================
export interface UserProfile {
  id: number;
  username: string;
  role: string;
  display_name: string;
  end_name: string;
  mine_id: number | null;
  created_at: string;
}

interface UpdateUserPayload {
  display_name: string;
  end_name: string;
}

export function apiUpdateUser(id: number, displayName: string, endName: string): Promise<UserProfile> {
  const payload: UpdateUserPayload = { display_name: displayName, end_name: endName };
  return apiRequest<UserProfile>(`/api/users/${id}`, http.RequestMethod.PUT, payload);
}

// ========================================
// 传感器
// ========================================
export interface BackendSensor {
  id: string;
  type: string;
  name: string;
  unit: string;
  threshold: number | null;
  value: number;
  status: string;
  description: string;
  updated_at: string;
}

export function apiGetSensors(): Promise<BackendSensor[]> {
  return apiRequest<BackendSensor[]>('/api/sensor/all');
}

// 历史趋势（P0-历史趋势分析 + 数据来源溯源）
export interface SensorHistoryPoint {
  ts: string;       // 聚合时间点
  interval: string; // minute | hour | day
  avg: number;
  min: number;
  max: number;
  samples: number;
}

export interface SensorSourceInfo {
  source: string;      // mqtt | udp | simulator | legacy
  source_addr: string; // 来源地址（mqtt broker URL / UDP 对端 IP:端口）
  samples: number;
}

export interface SensorHistoryResult {
  sensorId: string;
  name: string;
  interval: string;
  points: SensorHistoryPoint[];
  sources: SensorSourceInfo[];
}

/** 查询历史趋势，interval=minute|hour|day，from/to 为 ISO 时间（可省略） */
export function apiGetSensorHistory(sensorId: string, interval: string = 'hour', from?: string, to?: string): Promise<SensorHistoryResult> {
  const q: string[] = [`interval=${encodeURIComponent(interval)}`];
  if (from !== undefined && from !== null && from.length > 0) {
    q.push(`from=${encodeURIComponent(from)}`);
  }
  if (to !== undefined && to !== null && to.length > 0) {
    q.push(`to=${encodeURIComponent(to)}`);
  }
  return apiRequest<SensorHistoryResult>(`/api/sensor/${encodeURIComponent(sensorId)}/history?${q.join('&')}`);
}

export interface SensorStats {
  total: number;
  online: number;
  warning: number;
}

export function apiGetSensorStats(): Promise<SensorStats> {
  return apiRequest<SensorStats>('/api/sensor/stats');
}

export interface ThresholdSetting {
  id: number;
  key_name: string;
  name: string;
  value: number;
  unit: string;
  description: string;
}

export function apiGetThresholds(): Promise<ThresholdSetting[]> {
  return apiRequest<ThresholdSetting[]>('/api/sensor/thresholds');
}

interface ThresholdPayload {
  keyName: string;
  value: number;
}

export function apiSetThreshold(keyName: string, value: number): Promise<Object> {
  const payload: ThresholdPayload = { keyName, value };
  return apiRequest<Object>('/api/sensor/thresholds', http.RequestMethod.POST, payload);
}

// ========================================
// 预警
// ========================================
export interface BackendAlert {
  id: string;
  sensor_id: string;
  sensor_name: string;
  level: string; // RED / ORANGE / YELLOW
  message: string;
  value: number;
  threshold: number;
  handled: boolean;
  handler: string;
  created_at: string;
  raised_count: number;   // 已升级次数（预警升级状态机）
  escalation_note: string; // 升级说明
}

export interface CountResult {
  count: number;
}

interface HandleAlertPayload {
  alertId: string;
  handledBy: string;
}

export function apiGetAlerts(): Promise<BackendAlert[]> {
  return apiRequest<BackendAlert[]>('/api/alert/all');
}

export function apiGetUnhandledAlertCount(): Promise<CountResult> {
  return apiRequest<CountResult>('/api/alert/unhandled/count');
}

export function apiHandleAlert(id: string, handler?: string): Promise<Object> {
  const payload: HandleAlertPayload = { alertId: id, handledBy: handler || '鸿蒙端' };
  return apiRequest<Object>('/api/alert/handle', http.RequestMethod.POST, payload);
}

export function apiClearAlerts(): Promise<Object> {
  return apiRequest<Object>('/api/alert/clear', http.RequestMethod.POST);
}

// ========================================
// 数据分析（智库端）
// ========================================
export interface TrendPoint {
  value: number;
  created_at: string;
}

export function apiGetTrend(hours?: number): Promise<TrendPoint[]> {
  const q = hours ? `?hours=${hours}` : '';
  return apiRequest<TrendPoint[]>(`/api/analysis/trend${q}`);
}

export interface ThreatItem {
  id: string;
  name: string;
  unit: string;
  value: number;
  threshold: number;
  pct: number;
  color: string;
  isWarning: boolean;
}

export function apiGetThreat(): Promise<ThreatItem[]> {
  return apiRequest<ThreatItem[]>('/api/analysis/threat');
}

export interface AnalysisStats {
  currentPressure: number;
  peakPressure: number;
  avgPressure: number;
  alertTotal: number;
  unhandled: number;
  riskIndex: number;
  modelAccuracy: number;
  falseRate: number;
}

export function apiGetAnalysisStats(): Promise<AnalysisStats> {
  return apiRequest<AnalysisStats>('/api/analysis/stats');
}

export interface ModelMetrics {
  accuracy: number;
  falseRate: number;
  sampleSize: number;
  algorithm: string;
  modelVersion: string;
  lastTrainAt: string;
}

export function apiGetModelMetrics(): Promise<ModelMetrics> {
  return apiRequest<ModelMetrics>('/api/analysis/model-metrics');
}

export interface AnalysisReport {
  id: number;
  title: string;
  author: string;
  content: string;
  created_at: string;
}

export function apiGetReports(): Promise<AnalysisReport[]> {
  return apiRequest<AnalysisReport[]>('/api/analysis/reports');
}

interface ReportPayload {
  title: string;
  content: string;
}

export function apiCreateReport(title: string, content: string): Promise<AnalysisReport> {
  const payload: ReportPayload = { title, content };
  return apiRequest<AnalysisReport>('/api/analysis/reports', http.RequestMethod.POST, payload);
}

// ========================================
// 报表模板/导出（智库端，P2-3.6）
// ========================================
export interface ReportTemplate {
  key: string;
  name: string;
  desc: string;
}

export interface ReportMineChoice {
  id: number;
  name: string;
  location: string;
  owner: string;
  status: string;
}

export interface ReportTemplatesResult {
  templates: ReportTemplate[];
  mines: ReportMineChoice[];
}

export interface ReportOverview {
  sensorCount: number;
  online: number;
  warning: number;
  offline: number;
}

export interface ReportAlertLevels {
  YELLOW: number;
  ORANGE: number;
  RED: number;
}

export interface ReportAlertSummary {
  total: number;
  unhandled: number;
  byLevel: ReportAlertLevels;
}

export interface ReportRange {
  from: string;
  to: string;
}

export interface ReportSensorHist {
  avg: number;
  min: number;
  max: number;
  samples: number;
  lastAt: string;
}

export interface ReportSensorRow {
  id: string;
  name: string;
  type: string;
  unit: string;
  value: number;
  threshold: number | null;
  status: string;
  isWarning: boolean;
  mine_id: number;
  hist: ReportSensorHist | null;
}

export interface GeneratedReport {
  reportId: number;
  template: string;
  title: string;
  templateName: string;
  mineId: number | null;
  mineName: string;
  author: string;
  range: ReportRange;
  generatedAt: string;
  overview: ReportOverview;
  alertSummary: ReportAlertSummary;
  sensors: ReportSensorRow[];
  createdAt: string;
}

export function apiGetReportTemplates(): Promise<ReportTemplatesResult> {
  return apiRequest<ReportTemplatesResult>('/api/report/templates');
}

export interface ReportGeneratePayload {
  template: string;
  mineId?: number | null;
  from?: string;
  to?: string;
}

export function apiGenerateReport(template: string, mineId?: number | null, from?: string, to?: string): Promise<GeneratedReport> {
  const payload: ReportGeneratePayload = { template };
  if (mineId !== undefined && mineId !== null) {
    payload.mineId = mineId;
  }
  if (from !== undefined && from !== null) {
    payload.from = from;
  }
  if (to !== undefined && to !== null) {
    payload.to = to;
  }
  return apiRequest<GeneratedReport>('/api/report/generate', http.RequestMethod.POST, payload);
}

export function apiGetReportList(): Promise<AnalysisReport[]> {
  return apiRequest<AnalysisReport[]>('/api/report/reports');
}

// ========================================
// 监管端
// ========================================
export interface MineInfo {
  id: string;
  name: string;
  location: string;
  owner: string;
  status: string;
  sensorTotal: number;
  online: number;
  warning: number;
}

export function apiGetSupervisionMines(): Promise<MineInfo[]> {
  return apiRequest<MineInfo[]>('/api/supervision/mines');
}

export interface MineCompareItem {
  id: number;
  name: string;
  location: string;
  owner: string;
  status: string;
  sensorTotal: number;
  online: number;
  warning: number;
  onlineRate: number;   // 在线率 0~1
  handledRate: number;  // 处置率 0~1
  totalAlerts: number;
  unhandledAlert: number;
  handledAlert: number;
  maxLevel: string;     // RED/ORANGE/YELLOW/null
}

export function apiGetMineComparison(): Promise<MineCompareItem[]> {
  return apiRequest<MineCompareItem[]>('/api/supervision/compare');
}

export interface SupervisionOverview {
  mineCount: number;
  sensorTotal: number;
  unhandledAlert: number;
  activeDispatch: number;
  alertStat: AlertStat;
  mines: MineInfo[];
}

export interface AlertStat {
  RED: number;
  ORANGE: number;
  YELLOW: number;
}

export function apiGetSupervisionOverview(): Promise<SupervisionOverview> {
  return apiRequest<SupervisionOverview>('/api/supervision/overview');
}

export interface DispatchRecord {
  id: number;
  title: string;
  level: string;
  content: string;
  target_mine: string;
  status: string;
  creator: string;
  created_at: string;
}

export function apiGetDispatches(): Promise<DispatchRecord[]> {
  return apiRequest<DispatchRecord[]>('/api/supervision/dispatches');
}

interface DispatchPayload {
  title: string;
  level: string;
  content: string;
  target_mine: string;
  creator: string;
}

export function apiCreateDispatch(title: string, level: string, content: string, targetMine: string): Promise<DispatchRecord> {
  const payload: DispatchPayload = { title, level, content, target_mine: targetMine, creator: '鸿蒙-监管端' };
  return apiRequest<DispatchRecord>('/api/supervision/dispatches', http.RequestMethod.POST, payload);
}

interface DispatchStatusPayload {
  id: number;
  status: string;
}

export function apiUpdateDispatchStatus(id: number, status: string): Promise<DispatchRecord> {
  const payload: DispatchStatusPayload = { id, status };
  return apiRequest<DispatchRecord>('/api/supervision/dispatches/status', http.RequestMethod.POST, payload);
}

// ========================================
// VR 虚拟端双向 UDP 转发（经后端 /api/udp/forward，公开组免登录）
// ========================================
export interface UdpForwardResult {
  sent?: boolean;
  ok?: boolean;
  to?: string;
  bytes?: number;
  error?: string;
  message?: string;
}

export interface UdpForwardFramePayload {
  mode: string;
  sensorId?: string;
  value?: number;
  ip?: string;
  port?: number;
  payload?: string;
}

/** 发送 VR 虚拟帧 / 控制指令到后端，由后端 UDP 转发 */
export function apiUdpForward(payload: UdpForwardFramePayload): Promise<UdpForwardResult> {
  return apiRequest<UdpForwardResult>('/api/udp/forward', http.RequestMethod.POST, payload);
}

// ========================================
// 实时 WebSocket 通道
// ========================================
export interface WsEvent {
  type: string;
  payload: Object;
}

export class RealtimeClient {
  private static instance: RealtimeClient;
  private ws: webSocket.WebSocket | null = null;
  private handlers: Map<string, Array<(payload: Object) => void>> = new Map();
  private connected: boolean = false;
  private reconnectTimer: number = -1;
  private retryCount: number = 0;
  private clientId: string = 'harmony';

  private constructor() {
  }

  public static getInstance(): RealtimeClient {
    if (!RealtimeClient.instance) {
      RealtimeClient.instance = new RealtimeClient();
    }
    return RealtimeClient.instance;
  }

  public on(type: string, fn: (payload: Object) => void): void {
    const list = this.handlers.get(type) || [];
    list.push(fn);
    this.handlers.set(type, list);
  }

  /** 移除指定回调（避免页面反复进入时回调累积） */
  public off(type: string, fn: (payload: Object) => void): void {
    const list = this.handlers.get(type);
    if (!list) return;
    const next = list.filter((f) => f !== fn);
    if (next.length > 0) {
      this.handlers.set(type, next);
    } else {
      this.handlers.delete(type);
    }
  }

  public connect(clientId?: string): void {
    if (clientId) this.clientId = clientId;
    if (this.ws || this.connected) return;
    try {
      const ws = webSocket.createWebSocket();
      this.ws = ws;

      ws.on('open', (err, data) => {
        this.connected = true;
        this.retryCount = 0;
        hilog.info(DOMAIN, TAG, '实时通道已连接');
      });

      ws.on('message', (err, data) => {
        try {
          const msg = JSON.parse(data as string) as WsEvent;
          this.dispatch(msg.type, msg.payload);
        } catch (e) {
          hilog.error(DOMAIN, TAG, 'WS 消息解析失败: %{public}s', JSON.stringify(e));
        }
      });

      ws.on('close', (err, data) => {
        this.connected = false;
        this.scheduleReconnect();
      });

      ws.on('error', (err) => {
        hilog.error(DOMAIN, TAG, 'WS 错误: %{public}s', JSON.stringify(err));
      });

      ws.connect(WS_URL + '?clientId=' + encodeURIComponent(this.clientId), (err, value) => {
        if (err) {
          hilog.error(DOMAIN, TAG, 'WS 连接失败: %{public}s', JSON.stringify(err));
          this.scheduleReconnect();
        }
      });
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'WS 创建失败: %{public}s', JSON.stringify(e));
      this.scheduleReconnect();
    }
  }

  public disconnect(): void {
    if (this.ws) {
      this.ws.close();
      this.ws = null;
    }
    this.connected = false;
    if (this.reconnectTimer !== -1) {
      clearTimeout(this.reconnectTimer);
      this.reconnectTimer = -1;
    }
  }

  public isConnected(): boolean {
    return this.connected;
  }

  private dispatch(type: string, payload: Object): void {
    const list = this.handlers.get(type) || [];
    list.forEach((fn) => {
      try {
        fn(payload);
      } catch (e) {
        hilog.error(DOMAIN, TAG, '事件处理失败: %{public}s', JSON.stringify(e));
      }
    });
  }

  private scheduleReconnect(): void {
    if (this.reconnectTimer !== -1) return;
    const delay = Math.min(10000, 1500 * Math.pow(2, this.retryCount++));
    this.reconnectTimer = setTimeout(() => {
      this.reconnectTimer = -1;
      this.ws = null;
      this.connect();
    }, delay);
  }
}

export const realtimeClient = RealtimeClient.getInstance();