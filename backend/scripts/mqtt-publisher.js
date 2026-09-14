/**
 * MQTT 发布演示端（模拟井下网关/传感器向上报数据）
 * 从数据库读取现有传感器，周期性向 broker 发布传感器当前类型的合理取值。
 *
 * 用法：
 *   node scripts/mqtt-publisher.js            # 每 2s 发布一轮
 *   node scripts/mqtt-publisher.js once my_sensor 12.5   # 单条手动上报（验证用）
 *
 * 环境变量：MQTT_URL 默认 tcp://localhost:1883
 */
const mqtt = require('mqtt');
const fs = require('fs');
const path = require('path');
const { query } = require('../config/database');
require('dotenv').config();

const URL = process.env.MQTT_URL || 'tcp://localhost:1883';
const INTERVAL_MS = parseInt(process.env.PUBLISH_INTERVAL_MS, 10) || 2000;

/** 组装连接选项（账号 + TLS CA） */
function opts(extra = {}) {
  const o = { reconnectPeriod: 3000, connectTimeout: 8000, ...extra };
  if (process.env.MQTT_USER) o.username = process.env.MQTT_USER;
  if (process.env.MQTT_PASS) o.password = process.env.MQTT_PASS;
  const caFile = process.env.MQTT_CA_FILE || path.join(__dirname, '..', 'certs', 'mqtt-ca.crt');
  if (/^(mqtts|ssl|tls):/i.test(URL) && fs.existsSync(caFile)) o.ca = fs.readFileSync(caFile);
  return o;
}

// 各传感器类型的合理取值区间（按 id 关键字粗分）
function randomValue(id) {
  const u = Math.random;
  if (id.includes('water') || id.includes('pressure')) return +((2 + u() * 6).toFixed(2));        // 水压 MPa
  if (id.includes('ultrasonic') || id.includes('roof') || id.includes('distance')) return +(Math.max(5, 40 - u() * 30).toFixed(2)); // 顶板下沉距离/mm
  if (id.includes('vibrat')) return +(0.5 + u() * 6).toFixed(2);                                 // 震动 mm/s
  if (id.includes('gas') || id.includes('ch4')) return +(0.1 + u() * 0.6).toFixed(2);            // 瓦斯 %
  if (id.includes('co')) return +(0.5 + u() * 15).toFixed(1);                                    // 一氧化碳 ppm
  if (id.includes('temp') || id.includes('temperate')) return +(15 + u() * 15).toFixed(1);       // 温度 ℃
  if (id.includes('wind') || id.includes('air')) return +(0.5 + u() * 4).toFixed(2);             // 风速 m/s
  return +(Math.random() * 100).toFixed(2);
}

async function once(sensorId, value) {
  const client = mqtt.connect(URL, opts({ reconnectPeriod: 0 }));
  await new Promise((resolve, reject) => {
    client.on('connect', resolve);
    client.on('error', reject);
    client.on('close', reject);
  });
  await new Promise((resolve) => {
    client.publish(`sensor/${sensorId}/data`, JSON.stringify({ value }), { qos: 1 }, resolve);
  });
  console.log(`[publisher] 发布 sensor/${sensorId}/data = ${value}`);
  await new Promise((r) => setTimeout(r, 200));
  client.end(false, { reasonCode: 0 });
}

async function loop() {
  const client = mqtt.connect(URL, opts({ clientId: 'coal-publisher-demo' }));
  client.on('connect', () => console.log(`[publisher] 已连接 ${URL}`));
  client.on('error', (e) => console.warn('[publisher] broker 错误:', e.message));

  const run = async () => {
    let rows = [];
    try {
      rows = await query(`SELECT id FROM sensors WHERE status='ONLINE' OR TRUE`);
    } catch (e) { console.warn('[publisher] 读取传感器失败:', e.message); return; }
    for (const r of rows) {
      const v = randomValue(r.id);
      client.publish(`sensor/${r.id}/data`, JSON.stringify({ value: v }), { qos: 1 });
      console.log(`[publisher] -> sensor/${r.id} = ${v}`);
    }
  };
  await run();
  setInterval(run, INTERVAL_MS);
}

const [mode, a, b] = process.argv.slice(2);
if (mode === 'once') {
  once(a, parseFloat(b)).then(() => process.exit(0)).catch((e) => { console.error('发布失败:', e.message); process.exit(1); });
} else {
  loop();
}