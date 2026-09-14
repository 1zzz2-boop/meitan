/**
 * 服务健康监控脚本（Windows / Deepin 通用，依赖 node + ws）
 *
 * 用法：
 *   node scripts/monitor.js                  # 单次检查，全部正常退出码 0，任一异常退出码 1
 *   node scripts/monitor.js --loop 5         # 每 5 秒循环检查（Ctrl+C 退出）
 *   node scripts/monitor.js --host 192.168.137.1 --http 3000 --ws 8080 --mqtt 1883 --db 5432
 *
 * 环境变量（.env 中已配置的会优先读取，命令行参数 > 环境变量 > 默认值）：
 *   PORT / WS_PORT / MQTT_PORT / MONITOR_HOST
 *
 * 退出码便于接入任务计划（schtasks）或 systemd 定时器做自动告警。
 */
require('dotenv').config();
const net = require('net');
const http = require('http');
const { WebSocket } = require('ws');

function parseArgs() {
  const args = {};
  const arr = process.argv.slice(2);
  for (let i = 0; i < arr.length; i++) {
    if (arr[i].startsWith('--')) args[arr[i].slice(2)] = arr[i + 1];
  }
  return args;
}

const args = parseArgs();
const HOST = args.host || process.env.MONITOR_HOST || 'localhost';
const HTTP_PORT = parseInt(args.http, 10) || parseInt(process.env.PORT, 10) || 3000;
const WS_PORT = parseInt(args.ws, 10) || parseInt(process.env.WS_PORT, 10) || 8080;
const MQTT_PORT = parseInt(args.mqtt, 10) || 1883;
const DB_PORT = parseInt(args.db, 10) || 5432;
const LOOP_SEC = args.loop ? Math.max(1, parseInt(args.loop, 10)) : 0;

/** TCP 连通性检查 */
function tcp(port, timeout = 3000) {
  return new Promise((resolve) => {
    const t0 = Date.now();
    const sock = net.connect({ host: HOST, port });
    const fail = (err) => { sock.destroy(); resolve({ ok: false, ms: Date.now() - t0, err }); };
    const ok = () => { sock.destroy(); resolve({ ok: true, ms: Date.now() - t0 }); };
    sock.setTimeout(timeout);
    sock.once('connect', ok);
    sock.once('timeout', () => fail('timeout'));
    sock.once('error', (e) => fail(e.code || e.message));
  });
}

/** HTTP 健康检查（GET /api/health） */
function httpHealth(timeout = 3000) {
  return new Promise((resolve) => {
    const t0 = Date.now();
    const req = http.get({ host: HOST, port: HTTP_PORT, path: '/api/health', timeout }, (res) => {
      res.resume();
      resolve({ ok: res.statusCode === 200, ms: Date.now() - t0, status: res.statusCode });
    });
    req.setTimeout(timeout, () => { req.destroy(); resolve({ ok: false, ms: Date.now() - t0, err: 'timeout' }); });
    req.once('error', (e) => resolve({ ok: false, ms: Date.now() - t0, err: e.code || e.message }));
  });
}

/** WebSocket 连通性检查 */
function wsCheck(timeout = 3000) {
  return new Promise((resolve) => {
    const t0 = Date.now();
    const ws = new WebSocket(`ws://${HOST}:${WS_PORT}`);
    const done = (ok, err) => { try { ws.close(); } catch (_) { /* noop */ } resolve({ ok, ms: Date.now() - t0, err }); };
    ws.once('open', () => done(true));
    ws.once('error', (e) => done(false, e.code || e.message));
    setTimeout(() => done(false, 'timeout'), timeout);
  });
}

async function checkOnce() {
  const [db, mqtt, httpR, ws] = await Promise.all([tcp(DB_PORT), tcp(MQTT_PORT), httpHealth(), wsCheck()]);
  const items = [
    { name: `HTTP :${HTTP_PORT} /api/health`, ok: httpR.ok, ms: httpR.ms, detail: httpR.ok ? `status ${httpR.status}` : (httpR.err || '') },
    { name: `WebSocket :${WS_PORT}`, ok: ws.ok, ms: ws.ms, detail: ws.ok ? '' : (ws.err || '') },
    { name: `MQTT :${MQTT_PORT}`, ok: mqtt.ok, ms: mqtt.ms, detail: mqtt.ok ? '' : (mqtt.err || '') },
    { name: `PostgreSQL :${DB_PORT}`, ok: db.ok, ms: db.ms, detail: db.ok ? '' : (db.err || '') }
  ];
  const failed = items.filter((i) => !i.ok);
  const ts = new Date().toLocaleString('zh-CN', { hour12: false });
  console.log(`\n[监控] ${ts}`);
  for (const i of items) {
    console.log(`  ${i.ok ? '✓' : '✗'} ${i.name}  ${i.ms}ms  ${i.detail}`);
  }
  console.log(failed.length ? `  → ${failed.length} 项异常，请参考运维手册《常见故障排查》` : '  → 全部正常');
  return failed.length === 0;
}

(async () => {
  if (!LOOP_SEC) {
    const ok = await checkOnce();
    process.exit(ok ? 0 : 1);
  }
  console.log(`每 ${LOOP_SEC}s 循环监控 ${HOST}（Ctrl+C 退出）`);
  for (;;) {
    await checkOnce();
    await new Promise((r) => setTimeout(r, LOOP_SEC * 1000));
  }
})();
