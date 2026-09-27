/**
 * UDP 网关服务（上位机数据收口）
 * 通过 UDP 接收硬件端 / VR 端发送的 JSON 数据帧，写入数据库并通过 WebSocket 广播到 PC / 鸿蒙三端。
 *
 * 数据帧格式（UDP 无 topic）：
 *   JSON（必须自带 sensorId）：{"sensorId":"sensor_x","value":12.5}
 *     {"sensor_id":"sensor_x","value":12.5}   // 兼容下划线命名
 *     {"value":12.5}                          // 无法定位传感器 → 丢弃并告警
 *   逗号分隔多字段（CSV，硬件多路采集一帧发送）：
 *     12.3,1024,350,20.5,890,25,48
 *     按 UDP_CSV_MAP 把各下标映射到 sensorId，缺映射/缺传感器 → 跳过该字段并告警
 *
 * 通过环境变量配置（默认即可本地演示）：
 *   UDP_HOST  默认 0.0.0.0（监听所有网卡，硬件/VR 端经热点/局域网才能发进来；切勿设为 127.0.0.1）
 *   UDP_PORT  默认 8890（避开 3000/8080/1883/8883）
 *   UDP_CSV_MAP  逗号分隔多字段帧的下标→sensorId 映射，格式 "下标=sensorId,下标=sensorId"
 */
const dgram = require('dgram');
const sensorService = require('./sensor.service');
const wsHub = require('../utils/wsHub');
const { query } = require('../config/database');
const { parsePayload } = require('../utils/payload-parser');

const HOST = process.env.UDP_HOST || '0.0.0.0';
const PORT = parseInt(process.env.UDP_PORT, 10) || 8890;

/**
 * 逗号分隔多字段帧的「下标 → sensorId」映射。
 * 默认对应 STM32 采集顺序：weight,yewei,fsr,distance,mq2_adc,temp,humi。
 * 仅已入库的传感器有映射，其余下标跳过。可用 UDP_CSV_MAP 覆盖。
 */
const CSV_MAP = parseCsvMap(
  process.env.UDP_CSV_MAP ||
    '0=sensor_weight,1=sensor_water_level,2=sensor_film_pressure,3=sensor_ultrasonic,4=sensor_mq2,5=sensor_temperature,6=sensor_humidity'
);

/**
 * 换算层（对照硬件换算公式表）
 * 单片机/传感模块输出原始值后，上位机再换算为物理量入库。
 * 默认直通（不改数值），避免破坏现有环境与硬件链路；标定系数可用 env 覆盖：
 *   YEWEI_K    液位两点线性插值斜率  H = H0 + (adc - ADC0) * K
 *   YEWEI_ADC0
 *   YEWEI_H0
 *   FSR 表 / MQ2 曲线需先实物标定，标定完成前保持直通。
 */
const YEWEI_K = parseFloat(process.env.YEWEI_K) || 1;
const YEWEI_ADC0 = parseFloat(process.env.YEWEI_ADC0) || 0;
const YEWEI_H0 = parseFloat(process.env.YEWEI_H0) || 0;

/** 将传感器原始值按换算表转成物理量。无公式/未标定 → 直通返回。 */
function convertValue(sensorId, raw) {
  const v = Number(raw);
  if (Number.isNaN(v)) return raw;
  switch (sensorId) {
    // 两点线性插值：H = H0 + (adc - ADC0) * K（默认直通）
    case 'sensor_water_level':
      return YEWEI_H0 + (v - YEWEI_ADC0) * YEWEI_K;
    // weight(film 已换算)/distance/temp/humi 由硬件完成，直通
    // fsr(查表)、mq2(标定曲线) 待实物标定，标定前直通
    default:
      return v;
  }
}

/** 解析 "2=sensor_a,3=sensor_b" → { 下标: sensorId } */
function parseCsvMap(raw) {
  const map = {};
  String(raw)
    .split(',')
    .forEach((part) => {
      const idx = part.indexOf('=');
      if (idx <= 0) return;
      const key = parseInt(part.slice(0, idx).trim(), 10);
      const sensorId = part.slice(idx + 1).trim();
      if (!Number.isNaN(key) && sensorId) map[key] = sensorId;
    });
  return map;
}

let socket = null;
let startedAt = null;
let msgCount = 0;
let sendCount = 0;

/** 从逗号分隔多字段帧解析 → [{ sensorId, value }]（忽略无法映射/非数字的字段） */
function parseCsvFrame(text) {
  const parts = String(text).split(',').map((p) => p.trim());
  const items = [];
  parts.forEach((raw, idx) => {
    const sensorId = CSV_MAP[idx];
    const value = parseFloat(raw);
    if (!sensorId || Number.isNaN(value)) {
      if (sensorId) console.warn(`[udp] CSV 字段 ${idx}(=${raw}) 非数字，跳过`);
      else console.warn(`[udp] CSV 下标 ${idx} 未映射 sensorId，跳过 (${raw})`);
      return;
    }
    // 应用换算层（换算后入库；默认直通）
    items.push({ sensorId, value: convertValue(sensorId, value) });
  });
  return items;
}

/** 解析单条 UDP 帧 → { sensorId, value } | null（JSON，要求自带 sensorId） */
function parseFrame(buf) {
  const msg = parsePayload(buf.toString().trim());
  if (!msg || !msg.sensorId || Number.isNaN(msg.value)) {
    console.warn('[udp] 忽略无法解析/缺 sensorId 的数据帧:', buf.toString());
    return null;
  }
  return msg;
}

/** 校验传感器存在后写值 + 记历史 + 广播。返回是否成功。 */
async function writeOne(msg, rinfo) {
  const updated = await sensorService.updateSensorData(msg.sensorId, msg.value);
  if (!updated) {
    console.warn(`[udp] 传感器不存在，跳过: ${msg.sensorId} (来自 ${rinfo.address}:${rinfo.port})`);
    return false;
  }
  // 记入历史，供趋势曲线使用；标记来源为 UDP 及对端地址（数据来源溯源 P0）
  try {
    await query(
      `INSERT INTO sensor_history (sensor_id, value, source, source_addr) VALUES ($1, $2, 'udp', $3)`,
      [msg.sensorId, msg.value, `${rinfo.address}:${rinfo.port}`]
    );
  } catch (e) {
    console.warn('[udp] 写入历史失败:', e.message);
  }
  msgCount += 1;
  wsHub.emit('sensor_update', { ...updated, source: 'udp', source_addr: `${rinfo.address}:${rinfo.port}` });
  return true;
}

/** 校验传感器存在后写值 + 记历史 + 广播。返回是否成功。 */
async function ingest(buf, rinfo) {
  const text = buf.toString().trim();
  // 逗号分隔多字段帧（含多个逗号且非 JSON）→ 逐字段入库
  if (text.includes(',') && !text.includes('{')) {
    const items = parseCsvFrame(text);
    if (!items.length) {
      console.warn('[udp] CSV 帧无有效字段:', text);
      return false;
    }
    let ok = 0;
    for (const it of items) {
      if (await writeOne(it, rinfo)) ok += 1;
    }
    wsHub.emit('sensor_stats', await sensorService.getStats().catch(() => null));
    return ok > 0;
  }
  // 标准 JSON / 单值帧
  const msg = parseFrame(buf);
  if (!msg) return false;
  const ok = await writeOne(msg, rinfo);
  wsHub.emit('sensor_stats', await sensorService.getStats().catch(() => null));
  return ok;
}

/** 启动 UDP 监听（绑定失败只告警不退出，不影响后端其它服务） */
function start() {
  if (socket) return;
  console.log(`[udp] 正在监听 ${HOST}:${PORT} ...`);
  socket = dgram.createSocket('udp4');

  socket.on('message', (buf, rinfo) => {
    ingest(buf, rinfo).catch((e) =>
      console.warn('[udp] 处理数据帧出错:', e.message)
    );
  });

  socket.on('listening', () => {
    startedAt = Date.now();
    const a = socket.address();
    console.log(`[udp] UDP 网关已就绪 ${a.address}:${a.port}`);
  });

  socket.on('error', (err) => {
    console.warn(`[udp] 监听 ${HOST}:${PORT} 失败: ${err.message}`);
    socket = null;
  });

  socket.bind(PORT, HOST);
}

/** 向指定 ip:port 发送 UDP 数据（VR 端↔硬件的控制指令经后端转发）。
 *  使用独立零绑定 socket 发送（目标 ip:port 显式指定，源端口由系统分配），
 *  不与收口 8890 socket 混淆；发送后即关闭。返回 { ok, bytes, to }。 */
function sendCommand(ip, port, payload) {
  return new Promise((resolve) => {
    let client = null;
    try {
      client = dgram.createSocket('udp4');
      const buf = payload instanceof Buffer ? payload : Buffer.from(String(payload));
      client.send(buf, Number(port), ip, (err) => {
        try { client.close(); } catch (e) { /* 忽略 */ }
        if (err) {
          console.warn(`[udp] 发送命令失败 → ${ip}:${port}: ${err.message}`);
          resolve({ ok: false, error: err.message });
        } else {
          sendCount += 1;
          resolve({ ok: true, to: `${ip}:${port}`, bytes: buf.length });
        }
      });
    } catch (e) {
      if (client) { try { client.close(); } catch (err) { /* 忽略 */ } }
      console.warn(`[udp] 发送命令异常 → ${ip}:${port}: ${e.message}`);
      resolve({ ok: false, error: e.message });
    }
  });
}

/** 停止 UDP 监听 */
function stop() {
  if (socket) {
    try { socket.close(); } catch (e) { /* 忽略 */ }
    socket = null;
    console.log('[udp] 已停止');
  }
}

/** 运行状态信息 */
function status() {
  let listening = false;
  try { listening = !!(socket && socket.address()); } catch (e) { listening = false; }
  return {
    enabled: true,
    host: HOST,
    port: PORT,
    listening,
    startedAt,
    msgCount,
    sendCount
  };
}

module.exports = { start, stop, status, ingest, parseFrame, sendCommand };