/**
 * MQTT 桥接服务
 * 订阅井下 MQTT 数据（sensor/<sensorId>/data），写入数据库并实时广播到所有端（PC/鸿蒙）。
 * 
 * 主题格式：sensor/<sensorId>/data
 * 载荷支持三种：
 *   - 纯数值字符串          例："12.5"
 *   - JSON 含 value         例：{"value":12.5}
 *   - JSON 含 sensorId+value 例：{"sensorId":"sensor_x","value":12.5}
 *
 * 通过环境变量配置（默认即可本地演示）：
 *   MQTT_URL              默认 tcp://localhost:1883
 *   MQTT_TOPIC            默认 sensor/+/data
 *   MQTT_USER / MQTT_PASS 需要鉴权的 broker 时填写
 */
const mqtt = require('mqtt');
const fs = require('fs');
const path = require('path');
const sensorService = require('./sensor.service');
const wsHub = require('../utils/wsHub');
const { query } = require('../config/database');

const URL = process.env.MQTT_URL || 'tcp://localhost:1883';
const TOPIC = process.env.MQTT_TOPIC || 'sensor/+/data';
// TLS/认证（broker 启用账号 + mqtts 时使用）
const USER = process.env.MQTT_USER || undefined;
const PASS = process.env.MQTT_PASS || undefined;
const CA_FILE = process.env.MQTT_CA_FILE || path.join(__dirname, '..', 'certs', 'mqtt-ca.crt');

/** 组装 mqtt 连接选项（TLS + 账号） */
function connectOptions() {
  const opts = { reconnectPeriod: 5000, connectTimeout: 8000, clientId: 'coal-backend-bridge' };
  if (USER) opts.username = USER;
  if (PASS) opts.password = PASS;
  const useTls = /^(mqtts|ssl|tls):/i.test(URL);
  if (useTls && fs.existsSync(CA_FILE)) {
    opts.ca = fs.readFileSync(CA_FILE);
  }
  return opts;
}

let client = null;
let startedAt = null;
let msgCount = 0;

/** 解析 MQTT 载荷 → { sensorId, value } | null */
function parsePayload(topic, payloadStr) {
  const m = TOPIC === 'sensor/+/data' ? /^sensor\/([^/]+)\/data$/.exec(topic) : null;
  const topicSensorId = m ? m[1] : null;
  const body = String(payloadStr).trim();
  // 纯数值
  if (/^[-+]?(\d+\.?\d*|\.\d+)$/.test(body)) {
    return { sensorId: topicSensorId, value: parseFloat(body) };
  }
  // JSON
  try {
    const o = JSON.parse(body);
    const value = parseFloat(o.value);
    if (Number.isNaN(value)) return null;
    return { sensorId: (o.sensorId || o.sensor_id || topicSensorId), value };
  } catch (e) {
    return null;
  }
}

/** 校验传感器存在后写值 + 记历史 + 广播。返回是否成功。 */
async function ingest(topic, payloadStr) {
  const msg = parsePayload(topic, payloadStr);
  if (!msg || !msg.sensorId || Number.isNaN(msg.value)) {
    console.warn('[mqtt] 忽略无法解析的消息', topic, payloadStr);
    return false;
  }
  const updated = await sensorService.updateSensorData(msg.sensorId, msg.value);
  if (!updated) {
    console.warn(`[mqtt] 传感器不存在，跳过: ${msg.sensorId}`);
    return false;
  }
  // 记入历史，供趋势曲线使用
  try {
    await query(
      `INSERT INTO sensor_history (sensor_id, value) VALUES ($1, $2)`,
      [msg.sensorId, msg.value]
    );
  } catch (e) {
    console.warn('[mqtt] 写入历史失败:', e.message);
  }
  msgCount += 1;
  wsHub.emit('sensor_update', updated);
  wsHub.emit('sensor_stats', await sensorService.getStats().catch(() => null));
  return true;
}

/** 启动 MQTT 订阅（broker 不可达时自动重连，不阻塞后端启动） */
function start() {
  if (client) return;
  console.log(`[mqtt] 正在连接 broker ${URL}，订阅 ${TOPIC} ...`);
  client = mqtt.connect(URL, connectOptions());

  client.on('connect', () => {
    startedAt = Date.now();
    console.log('[mqtt] broker 已连接');
    client.subscribe(TOPIC, { qos: 1 }, (err) => {
      if (err) console.warn('[mqtt] 订阅失败:', err.message);
      else console.log(`[mqtt] 已订阅 ${TOPIC}`);
    });
  });

  client.on('message', (topic, payload) => {
    ingest(topic, payload.toString()).catch((e) =>
      console.warn('[mqtt] 处理消息出错:', e.message)
    );
  });

  client.on('reconnect', () => console.log('[mqtt] 重连中...'));
  client.on('error', (err) => console.warn('[mqtt] 连接错误:', err.message));
  client.on('offline', () => console.warn('[mqtt] 已离线'));
}

/** 停止订阅 */
function stop() {
  if (client) {
    client.end(true);
    client = null;
    console.log('[mqtt] 已停止');
  }
}

/** 运行状态信息 */
function status() {
  const connected = !!(client && client.connected);
  return {
    enabled: true,
    url: URL,
    topic: TOPIC,
    connected,
    startedAt,
    msgCount
  };
}

module.exports = { start, stop, status, ingest };