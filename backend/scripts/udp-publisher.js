/**
 * UDP 数据发布演示端（模拟硬件端 / VR 端向上位机上报数据）
 * 向 UDP 网关发送 JSON 数据帧，用于验证「入库 + 广播」链路。
 *
 * 用法：
 *   node scripts/udp-publisher.js                          # 每 2s 发送一轮 {value}（无 sensorId，会被网关丢弃，用于确认容错）
 *   node scripts/udp-publisher.js my_sensor 12.5           # 单条手动上报（验证用）
 *
 * 环境变量：UDP_HOST 默认 127.0.0.1，UDP_PORT 默认 8890
 */
const dgram = require('dgram');
require('dotenv').config();

const HOST = process.env.UDP_TARGET_HOST || '127.0.0.1';
const PORT = parseInt(process.env.UDP_PORT, 10) || 8890;
const INTERVAL_MS = parseInt(process.env.PUBLISH_INTERVAL_MS, 10) || 2000;

function sendOnce(sensorId, value) {
  const client = dgram.createSocket('udp4');
  const payload = sensorId
    ? { sensorId, value }
    : { value }; // 无 sensorId → 网关无法定位传感器，会被丢弃（预期容错演示）
  const buf = Buffer.from(JSON.stringify(payload));
  client.send(buf, PORT, HOST, (err) => {
    if (err) { console.error('[udp-publisher] 发送失败:', err.message); process.exitCode = 1; }
    else console.log(`[udp-publisher] -> ${HOST}:${PORT} ${buf.toString()}`);
    client.close();
  });
}

function loop() {
  console.log(`[udp-publisher] 每 ${INTERVAL_MS}ms 向 ${HOST}:${PORT} 发送一轮...`);
  setInterval(() => {
    // 从数据库读取真实传感器随机上报，模拟硬件端
    const { query } = require('../config/database');
    query(`SELECT id FROM sensors ORDER BY id LIMIT 1`).then((rows) => {
      const sensorId = rows.length ? rows[0].id : null;
      sendOnce(sensorId, +(Math.random() * 30).toFixed(2));
    }).catch((e) => console.warn('[udp-publisher] 读取传感器失败:', e.message));
  }, INTERVAL_MS);
}

const [sensorId, value] = process.argv.slice(2);
if (!process.argv.slice(2).length) {
  loop();
} else {
  sendOnce(sensorId, value !== undefined ? parseFloat(value) : +(Math.random() * 30).toFixed(2));
}