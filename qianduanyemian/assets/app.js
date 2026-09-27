/* ============================================================
   深地智控 · 共享前端逻辑（PC 三端门户通用）
   负责：后端 API 客户端、WebSocket 实时数据、通用工具、SVG 图表
   ============================================================ */
'use strict';

/* ---------------- 配置 ---------------- */
// 生产以 HTTPS 访问时自动切到 https/wss；开发仍 http/ws。
// 注意：反向代理部署（带域名）时需把 host 改为实际域名。
const _proto  = (location.protocol === 'https:') ? 'https' : 'http';
const _wsProto = _proto === 'https' ? 'wss' : 'ws';
const _host   = location.hostname || 'localhost';
const API_BASE = _proto + '://' + _host + ':3000/api';
const WS_URL   = _wsProto + '://' + _host + ':8080';

/* ---------------- 工具函数 ---------------- */
const $ = (s) => document.querySelector(s);
function fmt2(v) { return Number(v == null ? 0 : v).toFixed(2); }
function esc(s) {
  return String(s == null ? '' : s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
}
function fmtTime(ts) {
  if (!ts) return '--';
  const d = new Date(ts);
  if (isNaN(d.getTime())) return String(ts).slice(5, 16).replace('T', ' ');
  const p = (n) => String(n).padStart(2, '0');
  return `${d.getMonth() + 1}-${d.getDate()} ${p(d.getHours())}:${p(d.getMinutes())}:${p(d.getSeconds())}`;
}
function showToast(msg) {
  let t = $('#toast');
  if (!t) {
    t = document.createElement('div');
    t.className = 'toast';
    t.id = 'toast';
    document.body.appendChild(t);
  }
  t.innerHTML = esc(msg);
  t.classList.add('show');
  clearTimeout(t._t);
  t._t = setTimeout(() => t.classList.remove('show'), 2200);
}
function openModal(html) {
  $('#modalBox').innerHTML = html;
  $('#modalMask').classList.add('show');
}
function closeModal() { $('#modalMask').classList.remove('show'); }

/* ---------------- 统一图标库（内联 SVG sprite，stroke 描边风格） ----------------
   双端共享同一套几何图形：24×24 网格、stroke=currentColor、圆头线帽。
   用途：替换 emoji 图标，保证工业感与跨端一致性。 */
const ICONS = {
  'pick':        'M13.5 12 6 19.5 M6 19.5C6 18.6 6.2 17.7 6.9 16.9 M6 19.5l-2 1.2 M21 3l-6.2 6.2 M21 3c-.3-1.6-2-2.4-3.6-2.1l-3.4 8.1 M14.4 9.1l2.4-5.9',
  'mine':        '<path d="M3 21h18"/><path d="M5 21V8l7-5 7 5v13"/><path d="M9 21v-6h6v6"/><path d="M10 5h4"/>',
  'cap':         '<path d="M22 10 12 5 2 10l10 5 10-5Z"/><path d="M6 12v6c0 1.7 2.7 3 6 3s6-1.3 6-3v-6"/>',
  'gov':         '<path d="M3 21h18"/><path d="M5 21V7l7-4 7 4v14"/><path d="M9 21v-5h6v5"/><path d="M9 9h.01M15 9h.01M12 9h.01M12 13h.01M15 13h.01M9 13h.01"/>',
  'screen':      '<rect x="2" y="3" width="20" height="14" rx="2"/><path d="M8 21h8"/><path d="M12 17v4"/><path d="M7 9l3 3-3 3"/><path d="M13 15h4"/>',
  'dashboard':   '<rect x="3" y="3" width="7" height="9" rx="1"/><rect x="14" y="3" width="7" height="5" rx="1"/><rect x="14" y="12" width="7" height="9" rx="1"/><rect x="3" y="16" width="7" height="5" rx="1"/>',
  'monitor':     '<path d="M4.9 16.1C1 12.2 1 5.8 4.9 1.9"/><path d="M7.8 20.7a9 9 0 0 1 0-13.4"/><circle cx="12" cy="10" r="3"/><path d="M16.2 7.3a9 9 0 0 1 0 13.4"/><path d="M19.1 16.1c3.9-3.9 3.9-10.3 0-14.2"/>',
  'alert':       '<path d="m21.73 18-8-14a2 2 0 0 0-3.48 0l-8 14A2 2 0 0 0 4 21h16a2 2 0 0 0 1.73-3Z"/><path d="M12 9v4"/><path d="M12 17h.01"/>',
  'trend':       '<polyline points="22 7 13.5 15.5 8.5 10.5 2 17"/><polyline points="16 7 22 7 22 13"/>',
  'analysis':    '<path d="M3 3v18h18"/><path d="M18 17V9"/><path d="M13 17V5"/><path d="M8 17v-3"/>',
  'globe':       '<circle cx="12" cy="12" r="10"/><path d="M2 12h20"/><path d="M12 2a15.3 15.3 0 0 1 4 10 15.3 15.3 0 0 1-4 10 15.3 15.3 0 0 1-4-10 15.3 15.3 0 0 1 4-10z"/>',
  'layers':      '<path d="m12.83 2.18a2 2 0 0 0-1.66 0L2.6 6.08a1 1 0 0 0 0 1.83l8.58 3.91a2 2 0 0 0 1.66 0l8.58-3.9a1 1 0 0 0 0-1.83Z"/><path d="m22 17.65-9.17 4.16a2 2 0 0 1-1.66 0L2 17.65"/><path d="m22 12.65-9.17 4.16a2 2 0 0 1-1.66 0L2 12.65"/>',
  'repeat':      '<path d="m17 2 4 4-4 4"/><path d="M3 11v-1a4 4 0 0 1 4-4h14"/><path d="m7 22-4-4 4-4"/><path d="M21 13v1a4 4 0 0 1-4 4H3"/>',
  'send':        '<path d="m22 2-7 20-4-9-9-4Z"/><path d="M22 2 11 13"/>',
  'settings':    '<line x1="21" x2="14" y1="4" y2="4"/><line x1="10" x2="3" y1="4" y2="4"/><line x1="21" x2="12" y1="12" y2="12"/><line x1="8" x2="3" y1="12" y2="12"/><line x1="21" x2="16" y1="20" y2="20"/><line x1="12" x2="3" y1="20" y2="20"/><line x1="14" x2="14" y1="2" y2="6"/><line x1="8" x2="8" y1="10" y2="14"/><line x1="16" x2="16" y1="18" y2="22"/>',
  'user':        '<path d="M19 21v-2a4 4 0 0 0-4-4H9a4 4 0 0 0-4 4v2"/><circle cx="12" cy="7" r="4"/>',
  'users':       '<path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M22 21v-2a4 4 0 0 0-3-3.87"/><path d="M16 3.13a4 4 0 0 1 0 7.75"/>',
  'file':        '<path d="M15 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V7Z"/><path d="M14 2v4a2 2 0 0 0 2 2h4"/><path d="M10 9H8"/><path d="M16 13H8"/><path d="M16 17H8"/>',
  'database':    '<ellipse cx="12" cy="5" rx="9" ry="3"/><path d="M3 5V19A9 3 0 0 0 21 19V5"/><path d="M3 12A9 3 0 0 0 21 12"/>',
  'cpu':         '<rect x="4" y="4" width="16" height="16" rx="2"/><rect x="9" y="9" width="6" height="6"/><path d="M15 2v2M9 2v2M15 20v2M9 20v2M2 15h2M2 9h2M20 15h2M20 9h2"/>',
  'shield':      '<path d="M20 13c0 5-3.5 7.5-7.66 8.95a1 1 0 0 1-.67-.01C7.5 20.5 4 18 4 13V6a1 1 0 0 1 1-1c2 0 4.5-1.2 6.24-2.72a1.17 1.17 0 0 1 1.52 0C14.51 3.81 17 5 19 5a1 1 0 0 1 1 1z"/><path d="M12 8v4"/><path d="M12 16h.01"/>',
  'siren':       '<path d="M11 2h2v2h-2z"/><path d="M4 22h16v-3H4z"/><path d="M4 17a8 8 0 0 1 16 0"/><path d="M12 5v4"/>',
  'droplets':    '<path d="M7 16.3c2.2 0 4-1.83 4-4.05 0-1.16-.57-2.26-1.71-3.19S7.29 6.75 7 5.3c-.29 1.45-1.14 2.84-2.29 3.76S3 11.1 3 12.25c0 2.22 1.8 4.05 4 4.05z"/><path d="M12.56 6.6A10.97 10.97 0 0 0 14 3.02c.5 2.5 2 4.9 4 6.5s3 3.5 3 5.5a6.98 6.98 0 0 1-11.91 4.97"/>',
  'thermo':      '<path d="M14 4v10.54a4 4 0 1 1-4 0V4a2 2 0 0 1 4 0Z"/>',
  'wind':        '<path d="M12.8 19.6A2 2 0 1 0 14 16H2"/><path d="M17.5 8a2.5 2.5 0 1 1 2 4H2"/><path d="M9.8 4.4A2 2 0 1 1 11 8H2"/>',
  'ruler':       '<path d="M21.3 15.3a2.4 2.4 0 0 1 0 3.4l-2.6 2.6a2.4 2.4 0 0 1-3.4 0L2.7 8.7a2.41 2.41 0 0 1 0-3.4l2.6-2.6a2.41 2.41 0 0 1 3.4 0Z"/><path d="m14.5 12.5 2-2"/><path d="m11.5 9.5 2-2"/><path d="m8.5 6.5 2-2"/><path d="m17.5 15.5 2-2"/>',
  'wrench':      '<path d="M14.7 6.3a1 1 0 0 0 0 1.4l1.6 1.6a1 1 0 0 0 1.4 0l3.77-3.77a6 6 0 0 1-7.94 7.94l-6.91 6.91a2.12 2.12 0 0 1-3-3l6.91-6.91a6 6 0 0 1 7.94-7.94l-3.76 3.76z"/>',
  'activity':    '<path d="M22 12h-2.48a2 2 0 0 0-1.93 1.46l-2.35 8.36a.25.25 0 0 1-.48 0L9.24 2.18a.25.25 0 0 0-.48 0l-2.35 8.36A2 2 0 0 1 4.48 12H2"/>',
  'antenna':     '<path d="M20 4 3 20"/><path d="M6 10l8 8"/><path d="M14 2l-4 8"/><path d="M8 6l-2 4"/><path d="M16 8l6 6"/>',
  'monitor-sm':  '<rect x="2" y="3" width="20" height="14" rx="2"/><path d="M8 21h8"/><path d="M12 17v4"/>',
  'bar-chart':   '<path d="M3 3v18h18"/><path d="M18 17V9"/><path d="M13 17V5"/><path d="M8 17v-3"/>',
  'truck':       '<path d="M14 18V6a2 2 0 0 0-2-2H4a2 2 0 0 0-2 2v11a1 1 0 0 0 1 1h2"/><path d="M15 18H9"/><path d="M19 18h2a1 1 0 0 0 1-1v-3.65a1 1 0 0 0-.22-.62l-3.48-4.35A1 1 0 0 0 17.52 8H14"/><circle cx="17" cy="18" r="2"/><circle cx="7" cy="18" r="2"/><path d="M10 12h4M12 10v4"/>',
  'link':        '<path d="M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.71"/><path d="M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07l1.71-1.71"/>',
  'download':    '<path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="7 10 12 15 17 10"/><line x1="12" y1="15" x2="12" y2="3"/>',
  'sensor':      '<path d="M3 7V5a2 2 0 0 1 2-2h2"/><path d="M17 3h2a2 2 0 0 1 2 2v2"/><path d="M21 17v2a2 2 0 0 1-2 2h-2"/><path d="M7 21H5a2 2 0 0 1-2-2v-2"/><circle cx="12" cy="12" r="3"/>',
  'flag':        '<path d="M4 15s1-1 4-1 5 2 8 2 4-1 4-1V3s-1 1-4 1-5-2-8-2-4 1-4 1z"/><line x1="4" x2="4" y1="22" y2="15"/>',
  'list':        '<line x1="8" x2="21" y1="6" y2="6"/><line x1="8" x2="21" y1="12" y2="12"/><line x1="8" x2="21" y1="18" y2="18"/><line x1="3" x2="3.01" y1="6" y2="6"/><line x1="3" x2="3.01" y1="12" y2="12"/><line x1="3" x2="3.01" y1="18" y2="18"/>',
  'zap':         '<polygon points="13 2 3 14 12 14 11 22 21 10 12 10 13 2"/>',
  'online':      '<circle cx="12" cy="12" r="10"/><circle cx="12" cy="12" r="2" fill="currentColor" stroke="none"/>',
  'eye':         '<path d="M2 12s3-7 10-7 10 7 10 7-3 7-10 7-10-7-10-7Z"/><circle cx="12" cy="12" r="3"/>',
  'check':       '<path d="M22 11.08V12a10 10 0 1 1-5.93-9.14"/><polyline points="22 4 12 14.01 9 11.01"/>',
  'x':           '<circle cx="12" cy="12" r="10"/><path d="m15 9-6 6"/><path d="m9 9 6 6"/>',
  'bell':        '<path d="M6 8a6 6 0 0 1 12 0c0 7 3 9 3 9H3s3-2 3-9"/><path d="M10.3 21a1.94 1.94 0 0 0 3.4 0"/>',
  'clock':       '<circle cx="12" cy="12" r="10"/><polyline points="12 6 12 12 16 14"/>',
  'gauge':       '<path d="m12 14 4-4"/><path d="M3.34 19a10 10 0 1 1 17.32 0"/>'
};

let _iconsInjected = false;
function ensureIcons() {
  if (_iconsInjected) return;
  _iconsInjected = true;
  let svg = '<svg xmlns="http://www.w3.org/2000/svg" style="display:none" aria-hidden="true">';
  for (const k of Object.keys(ICONS)) {
    svg += `<symbol id="i-${k}" viewBox="0 0 24 24">${ICONS[k]}</symbol>`;
  }
  svg += '</svg>';
  document.body.insertAdjacentHTML('beforeend', svg);
}
/** 内联 SVG 图标：ico('antenna', 16) */
function ico(name, size, cls) {
  ensureIcons();
  const s = size || 16;
  return `<svg class="ico${cls ? ' ' + cls : ''}" width="${s}" height="${s}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><use href="#i-${name}"/></svg>`;
}
window.ico = ico;
window.ensureIcons = ensureIcons;
if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', ensureIcons);
else ensureIcons();

/* ---------------- 传感器元数据（与移动端 IoTDeviceService 一致） ---------------- */
const SENSOR_TYPES = {
  WATER_PRESSURE: { icon: 'droplets', name: '水压传感器', unit: 'MPa' },
  FILM_PRESSURE:  { icon: 'layers', name: '薄膜传感器', unit: 'kN' },
  TEMPERATURE:    { icon: 'thermo', name: 'DHT11温度', unit: '℃' },
  HUMIDITY:       { icon: 'droplets', name: 'DHT11湿度', unit: '%' },
  CO2_LEVEL:      { icon: 'wind', name: 'CO2浓度', unit: '%' },
  SO2_LEVEL:      { icon: 'wind', name: 'SO2浓度', unit: '%' },
  ULTRASONIC_DISTANCE: { icon: 'ruler', name: '超声波测距', unit: 'm' },
  STRAIN_GAUGE:   { icon: 'wrench', name: '锚杆弯折', unit: 'mm' },
  VIBRATION:      { icon: 'activity', name: '震动传感器', unit: 'g' },
  LORA_MODULE:    { icon: 'antenna', name: 'LoRa通讯模块', unit: '' },
  OLED_DISPLAY:   { icon: 'monitor-sm', name: 'OLED显示屏', unit: '' }
};
function sensorMeta(t) { return SENSOR_TYPES[t] || { icon: 'bar-chart', name: t, unit: '' }; }
/** 传感器类型图标（SVG）：sensorIco(t, size) */
function sensorIco(t, size) { return ico(sensorMeta(t).icon, size); }
function isDevice(t) { return t === 'LORA_MODULE' || t === 'OLED_DISPLAY'; }

/* ---------------- 阈值判定（与后端/移动端逻辑一致） ---------------- */
function isOverThreshold(s) {
  if (s.threshold === null || s.threshold === undefined) return false;
  if (s.type === 'ULTRASONIC_DISTANCE') return s.value < s.threshold;
  return s.value > s.threshold;
}
function alertLevelOf(s) {
  if (!isOverThreshold(s)) return null;
  const ratio = Math.abs(s.value - s.threshold) / s.threshold;
  if (ratio > 0.5) return 'RED';
  if (ratio > 0.3) return 'ORANGE';
  return 'YELLOW';
}
const LEVEL_TXT = { RED: '红色', ORANGE: '橙色', YELLOW: '黄色', GREEN: '绿色' };
function levelClass(l) { return l === 'RED' ? 'red' : (l === 'ORANGE' ? 'orange' : 'amber'); }
function alertLevelColor(l) { return l === 'RED' ? 'var(--red)' : (l === 'ORANGE' ? 'var(--orange)' : 'var(--amber)'); }
/** 阈值方向说明：值为低于还是高于阈值时触发预警 */
function thresholdDir(s) {
  if (!s || s.threshold === null || s.threshold === undefined) return '';
  return s.type === 'ULTRASONIC_DISTANCE' ? '低于阈值预警' : '高于阈值预警';
}
/** 阈值展示（含方向）：如「阈值 2.50 m · 低于预警」 */
function thresholdTxt(s) {
  if (!s || s.threshold === null || s.threshold === undefined) return '阈值 --';
  return '阈值 ' + fmt2(s.threshold) + (s.unit || '') + ' · ' + thresholdDir(s);
}

/* ---------------- API 客户端 ---------------- */
// 从本地会话读取令牌，自动附加 Authorization，避免手写 token
function _sessionToken() {
  const s = getSession();
  return (s && s.token) ? s.token : null;
}
/** 令牌过期/未登录时清会话并回到入口（已在入口则刷新，不重复跳转） */
function _handleUnauthorized() {
  localStorage.removeItem('td_session');
  if (!location.pathname.endsWith('index.html')) location.href = 'index.html?expired=1';
}
async function api(path, options = {}) {
  const { method = 'GET', body, headers = {} } = options;
  const h = { 'Content-Type': 'application/json', ...headers };
  const token = _sessionToken();
  if (token) h.Authorization = 'Bearer ' + token;
  const cfg = { method, headers: h };
  if (body !== undefined) cfg.body = JSON.stringify(body);
  let res;
  try {
    res = await fetch(API_BASE + path, cfg);
  } catch (e) {
    throw new Error('无法连接后端服务');
  }
  if (res.status === 401) _handleUnauthorized();
  if (!res.ok) {
    let msg = '请求失败 (' + res.status + ')';
    try { const j = await res.json(); msg = j.message || j.error || msg; } catch (e) { /* ignore */ }
    throw new Error(msg);
  }
  return res.json();
}

/** 获取服务端图形验证码（登录用） */
async function apiCaptcha() {
  const res = await fetch(API_BASE + '/auth/captcha');
  if (!res.ok) {
    let msg = '验证码获取失败';
    try { const j = await res.json(); msg = j.message || msg; } catch (e) { /* ignore */ }
    throw new Error(msg);
  }
  return res.json();
}

/* ---------------- WebSocket 客户端（自动重连 + 事件分发） ---------------- */
const wsClient = {
  ws: null,
  connected: false,
  _handlers: {},
  _reconnectTimer: null,
  _retry: 0,
  on(type, fn) { (this._handlers[type] = this._handlers[type] || []).push(fn); },
  connect(clientId) {
    const url = WS_URL + '?clientId=' + encodeURIComponent(clientId || 'pc');
    try { this.ws = new WebSocket(url); } catch (e) { this._scheduleReconnect(); return; }
    this.ws.onopen = () => {
      this.connected = true;
      this._retry = 0;
      this._emit('connection_status', { connected: true });
      this._emit('open', {});
    };
    this.ws.onmessage = (ev) => {
      let msg;
      try { msg = JSON.parse(ev.data); } catch (e) { return; }
      this._emit(msg.type, msg.payload);
    };
    this.ws.onclose = () => {
      this.connected = false;
      this._emit('close', {});
      this._scheduleReconnect();
    };
    this.ws.onerror = () => { /* onclose 会处理重连 */ };
  },
  _scheduleReconnect() {
    if (this._reconnectTimer) return;
    const delay = Math.min(10000, 1500 * Math.pow(2, this._retry++));
    this._reconnectTimer = setTimeout(() => {
      this._reconnectTimer = null;
      this.connect(this._clientId);
    }, delay);
  },
  _emit(type, payload) {
    (this._handlers[type] || []).forEach((fn) => { try { fn(payload); } catch (e) { console.error(e); } });
  },
  send(obj) { if (this.ws && this.connected) this.ws.send(JSON.stringify(obj)); }
};
wsClient._clientId = 'pc';
wsClient.connect = wsClient.connect.bind(wsClient);
wsClient.on('connection_status', (p) => {
  const led = $('#connLed'), txt = $('#connText');
  if (led && txt) {
    if (p.connected) { led.className = 'led'; txt.textContent = '实时数据通道 · 在线'; }
    else { led.className = 'led gray'; txt.textContent = '实时数据通道 · 离线'; }
  }
});

/* ============================================================
   SVG 图表
   ============================================================ */

/* 折线/面积图：顶板压力趋势 */
function renderLineChart(sel, data, opts = {}) {
  const el = $(sel);
  if (!el) return;
  const W = 720, H = 210, padL = 40, padB = 26, padT = 12, padR = 10;
  const iw = W - padL - padR, ih = H - padT - padB;
  const max = opts.max != null ? opts.max : Math.ceil(Math.max(...data) * 1.15);
  const min = opts.min != null ? opts.min : 0;
  const x = (i) => padL + iw * (data.length <= 1 ? 0.5 : i / (data.length - 1));
  const y = (v) => padT + ih * (1 - (v - min) / (max - min));
  let pts = data.map((v, i) => `${x(i).toFixed(1)},${y(v).toFixed(1)}`).join(' ');
  let area = `${padL},${padT + ih} ` + pts + ` ${x(data.length - 1).toFixed(1)},${padT + ih}`;
  let html = `<svg viewBox="0 0 ${W} ${H}" style="width:100%;height:100%">`;
  html += `<defs><linearGradient id="pg${opts.gid || 'a'}" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="rgba(88,166,160,.20)"/><stop offset="1" stop-color="rgba(88,166,160,0)"/></linearGradient></defs>`;
  for (let i = 0; i <= 5; i++) {
    const v = min + (max - min) * i / 5, yy = y(v);
    html += `<line x1="${padL}" y1="${yy}" x2="${W - padR}" y2="${yy}" stroke="rgba(255,255,255,.06)"/>`;
    html += `<text x="${padL - 6}" y="${yy + 4}" font-size="10" fill="#5c6675" text-anchor="end" font-family="IBM Plex Mono">${Math.round(v)}</text>`;
  }
  if (opts.threshold != null) {
    const ty = y(opts.threshold);
    html += `<line x1="${padL}" y1="${ty}" x2="${W - padR}" y2="${ty}" stroke="rgba(201,100,100,.6)" stroke-dasharray="4 4"/>`;
    html += `<text x="${W - padR}" y="${ty - 5}" font-size="10" fill="#c96464" text-anchor="end" font-family="IBM Plex Mono">${opts.thresholdText || '阈值 ' + opts.threshold}</text>`;
  }
  html += `<polygon points="${area}" fill="url(#pg${opts.gid || 'a'})"/>`;
  html += `<polyline points="${pts}" fill="none" stroke="${opts.stroke || '#FF8C2A'}" stroke-width="2.5" stroke-linejoin="round" stroke-linecap="round"/>`;
  data.forEach((v, i) => {
    const c = opts.threshold != null && v >= opts.threshold ? '#E5484D' : (opts.stroke || '#FF8C2A');
    html += `<circle cx="${x(i).toFixed(1)}" cy="${y(v).toFixed(1)}" r="3.5" fill="${c}"/>`;
  });
  if (opts.labels) {
    opts.labels.forEach((l, i) => html += `<text x="${x(i).toFixed(1)}" y="${H - 6}" font-size="10" fill="#5c6675" text-anchor="middle" font-family="IBM Plex Mono">${l}</text>`);
  }
  html += '</svg>';
  el.innerHTML = html;
}

/* 半圆仪表盘 */
function renderGauge(sel, risk) {
  const el = $(sel);
  if (!el) return;
  const r = 54, cx = 75, cy = 78, start = -210, end = 30;
  const ang = (v) => ((start + (end - start) * v / 100) * Math.PI / 180);
  const pt = (v, rr) => { const a = ang(v); return `${(cx + rr * Math.cos(a)).toFixed(1)},${(cy + rr * Math.sin(a)).toFixed(1)}`; };
  let html = `<svg viewBox="0 0 150 160" style="width:100%">`;
  html += `<path d="M ${pt(0, r - 8)} A ${r - 8} ${r - 8} 0 0 1 ${pt(100, r - 8)}" fill="none" stroke="rgba(255,255,255,.06)" stroke-width="10" stroke-linecap="round"/>`;
  [[0, 60, '#3DDC84'], [60, 80, '#F5C542'], [80, 100, '#E5484D']].forEach((s) => {
    html += `<path d="M ${pt(s[0], r - 8)} A ${r - 8} ${r - 8} 0 0 1 ${pt(s[1], r - 8)}" fill="none" stroke="${s[2]}" stroke-width="10" stroke-linecap="round" opacity=".85"/>`;
  });
  const pa = ang(risk);
  const px = cx + (r - 18) * Math.cos(pa), py = cy + (r - 18) * Math.sin(pa);
  html += `<line x1="${cx}" y1="${cy}" x2="${px}" y2="${py}" stroke="#fff" stroke-width="3" stroke-linecap="round"/>`;
  html += `<circle cx="${cx}" cy="${cy}" r="5" fill="#58a6a0"/>`;
  html += `<text x="${cx}" y="${cy + 30}" font-size="11" fill="#98a2b3" text-anchor="middle" font-family="IBM Plex Mono">${risk}%</text>`;
  html += '</svg>';
  el.innerHTML = html;
}

/* 横向条形图（威胁度等） */
function renderHBar(sel, items) {
  const el = $(sel);
  if (!el) return;
  el.innerHTML = items.map((it) => {
    const c = it.color || (it.pct >= 100 ? 'var(--red)' : (it.pct >= 80 ? 'var(--orange)' : (it.pct >= 60 ? 'var(--amber)' : 'var(--green)')));
    return `<div style="margin-bottom:12px">
      <div style="display:flex;justify-content:space-between;font-size:12px;margin-bottom:5px">
        <span>${esc(it.label)}</span>
        ${it.pct > 0
          ? `<span style="font-family:var(--mono)"><span style="color:${c};font-weight:700">${it.pct}%</span>${(it.hint ? ' <span style="color:var(--muted)">' + esc(it.hint) + '</span>' : '')}</span>`
          : `<span style="font-family:var(--mono);color:var(--muted)">${it.hint || '暂无数据'}</span>`}
      </div>
      <div class="bar" style="height:9px"><i style="width:${Math.min(100, it.pct)}%;background:${c}"></i></div>
    </div>`;
  }).join('') || `<div class="empty" style="padding:30px 0">${ico('bar-chart', 26)}<div>暂无数据</div></div>`;
}

/* 雷达图（模型指标） */
function renderRadar(sel, labels, values) {
  const el = $(sel);
  if (!el) return;
  const W = 320, H = 260, cx = W / 2, cy = H / 2 + 4, R = 88;
  const n = labels.length;
  const pt = (i, v) => {
    const a = -Math.PI / 2 + i * 2 * Math.PI / n;
    return `${(cx + R * v * Math.cos(a)).toFixed(1)},${(cy + R * v * Math.sin(a)).toFixed(1)}`;
  };
  let html = `<svg viewBox="0 0 ${W} ${H}" style="width:100%;height:100%">`;
  for (let ring = 1; ring <= 4; ring++) {
    let poly = labels.map((_, i) => pt(i, ring / 4)).join(' ');
    html += `<polygon points="${poly}" fill="none" stroke="rgba(255,255,255,.08)"/>`;
  }
  labels.forEach((_, i) => {
    const p = pt(i, 1);
    html += `<line x1="${cx}" y1="${cy}" x2="${p}" stroke="rgba(255,255,255,.08)"/>`;
  });
  const poly = labels.map((_, i) => pt(i, Math.max(0.05, Math.min(1, values[i])))).join(' ');
  html += `<polygon points="${poly}" fill="rgba(88,166,160,.15)" stroke="#58a6a0" stroke-width="2"/>`;
  labels.forEach((l, i) => {
    const p = pt(i, 1.12);
    html += `<text x="${p.split(',')[0]}" y="${p.split(',')[1] + 4}" font-size="11" fill="#e6e9ee" text-anchor="middle" font-family="Noto Sans SC">${esc(l)}</text>`;
  });
  html += '</svg>';
  el.innerHTML = html;
}

/* 通用 DOM 辅助：为进入门户后统一挂载 */
function initCommonShell(portal, pageMeta) {
  const navItems = document.querySelectorAll('.nav-item');
  navItems.forEach((el) => el.addEventListener('click', () => {
    if (el.dataset.link) { window.open(el.dataset.link, '_blank'); return; } // 外部页面入口（如综合态势大屏）
    switchView(el.dataset.view);
  }));
  const bsLinkIco = document.querySelector('.nav-item[data-link] .ico');
  if (bsLinkIco) bsLinkIco.innerHTML = ico('screen', 16);
  const brand = document.querySelector('.brand');
  if (brand) brand.addEventListener('click', () => { location.href = 'index.html'; });
  const logout = $('#logoutBtn');
  if (logout) logout.addEventListener('click', () => { if (confirm('确定要退出登录吗？')) { localStorage.removeItem('td_session'); location.href = 'index.html'; } });
  window.switchView = function (v) {
    navItems.forEach((e) => e.classList.toggle('active', e.dataset.view === v));
    document.querySelectorAll('.view').forEach((e) => e.classList.toggle('active', e.id === 'view-' + v));
    const m = (pageMeta && pageMeta[v]) || ['', ''];
    const t = $('#pageTitle'), s = $('#pageSub');
    if (t) t.textContent = m[0];
    if (s) s.textContent = m[1];
  };
  // 时钟
  const clock = $('#clock');
  if (clock) {
    const tick = () => {
      const d = new Date(), p = (n) => String(n).padStart(2, '0');
      clock.textContent = `${p(d.getHours())}:${p(d.getMinutes())}:${p(d.getSeconds())}`;
    };
    tick(); setInterval(tick, 1000);
  }
  // 展示当前登录用户
  const sess = getSession();
  if (sess && sess.user) {
    const un = $('#sideUserName'), ur = $('#sideUserRole'), hu = $('#headerUserName');
    if (un) un.textContent = sess.user.displayName || sess.user.username;
    if (ur) ur.textContent = sess.user.endName || portal;
    if (hu) hu.textContent = sess.user.displayName || sess.user.username;
  } else {
    const un = $('#sideUserName');
    if (un) un.textContent = '未登录';
  }
}
function getSession() {
  try { return JSON.parse(localStorage.getItem('td_session') || 'null'); } catch (e) { return null; }
}
function setSession(s) { localStorage.setItem('td_session', JSON.stringify(s)); }
function requireLogin(page) {
  const s = getSession();
  if (!s || !s.token) { location.href = 'index.html?target=' + page; return null; }
  return s;
}
