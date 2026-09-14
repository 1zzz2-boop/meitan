/* ============================================================
   深地智控 · 综合态势大屏逻辑（bigscreen）
   数字孪生场景联动：图层切换 / 点位选中 / 按住爬升-松开回落 /
   多源融合卡 / 阈值滑杆 / 预警定位处置 / 全流程闭环状态
   ============================================================ */
'use strict';

/* ---------------- 场景点位布局（映射数据库传感器 ID） ---------------- */
const SCENE_POINTS = [
  { sid: 'sensor_film_pressure', x: 184, y: 268, label: '支架测点Ⅰ', grp: 'face' },
  { sid: 'sensor_film_pressure', x: 184, y: 336, label: '支架测点Ⅱ', grp: 'face' },
  { sid: 'sensor_film_pressure', x: 184, y: 404, label: '支架测点Ⅲ', grp: 'face' },
  { sid: 'sensor_ultrasonic',    x: 330, y: 470, label: '位移测点A', grp: 'road' },
  { sid: 'sensor_ultrasonic',    x: 520, y: 470, label: '位移测点B', grp: 'road' },
  { sid: 'sensor_ultrasonic',    x: 710, y: 470, label: '位移测点C', grp: 'road' },
  { sid: 'sensor_strain',        x: 350, y: 220, label: '锚杆测点Ⅰ', grp: 'road' },
  { sid: 'sensor_strain',        x: 650, y: 220, label: '锚杆测点Ⅱ', grp: 'road' },
  { sid: 'sensor_vibration',     x: 290, y: 345, label: '震动测点Ⅰ', grp: 'face' },
  { sid: 'sensor_vibration',     x: 430, y: 345, label: '震动测点Ⅱ', grp: 'road' },
  { sid: 'sensor_water_pressure',x: 330, y: 195, label: '岩溶水测点Ⅰ', grp: 'karst' },
  { sid: 'sensor_water_pressure',x: 520, y: 180, label: '岩溶水测点Ⅱ', grp: 'karst' },
  { sid: 'sensor_temperature',   x: 800, y: 470, label: '温度测点', grp: 'env' },
  { sid: 'sensor_humidity',      x: 840, y: 220, label: '湿度测点', grp: 'env' },
  { sid: 'sensor_co2',           x: 830, y: 470, label: 'CO₂测点', grp: 'env' },
  { sid: 'sensor_so2',           x: 860, y: 220, label: 'SO₂测点', grp: 'env' },
  { sid: 'lora_module',          x: 100, y: 530, label: 'LoRa网关', grp: 'net' },
];

/* 可"按住演示"的传感器类型（dir：+1 数值爬升 / -1 数值下降表示下沉加深）
 * 上限取"明显越限但仍属物理合理"的危险区间（威胁度 100% 对应值远低于上限），
 * 避免演示数值冲到离谱量程、松开后回落耗时过长。 */
const DEMO_TYPES = {
  FILM_PRESSURE:       { dir: 1,  rate: 0.60,  max: 20,   hint: '按住：顶板压力爬升' },
  WATER_PRESSURE:      { dir: 1,  rate: 0.06,  max: 1.6,  hint: '按住：岩溶水压爬升' },
  VIBRATION:           { dir: 1,  rate: 0.06,  max: 0.85, hint: '按住：震动强度爬升' },
  STRAIN_GAUGE:        { dir: 1,  rate: 0.008, max: 0.085,hint: '按住：锚杆应力爬升' },
  ULTRASONIC_DISTANCE: { dir: -1, rate: 0.06,  min: 1.2,  hint: '按住：顶板下沉加深' },
};

/* 阈值滑杆（仅 threshold_config 可配置项） */
const SLIDER_KEYS = {
  sensor_water_pressure: { keyName: 'water_pressure', min: 0.2, max: 2.0, step: 0.05, unit: 'MPa' },
  sensor_ultrasonic:     { keyName: 'roof_sink',      min: 0.5, max: 5.0, step: 0.1,  unit: 'm' },
  sensor_vibration:      { keyName: 'vibration',      min: 0.1, max: 1.0, step: 0.05, unit: 'g' },
};

/* 力学机理说明（预警依据弹窗用） */
const MECHANISM = {
  FILM_PRESSURE:       '液压支架工作阻力持续升高，超过阈值表明顶板压力集中、老顶活动加剧，可能诱发顶板断裂来压。',
  WATER_PRESSURE:      '岩溶水压异常升高，喀斯特含水层水体沿断层/裂隙通道渗入巷道，突水风险上升。',
  ULTRASONIC_DISTANCE: '顶板下沉量持续增大并逼近阈值，巷道围岩变形失稳风险升高。',
  STRAIN_GAUGE:        '锚杆弯折量超限，支护体系锚固力下降，顶板离层风险增大。',
  VIBRATION:           '震动强度超限，反映冲击地压倾向，煤岩体弹性能积聚释放风险升高。',
  TEMPERATURE:         '环境温度异常，可能存在热害或设备过热隐患。',
  HUMIDITY:            '环境湿度异常，需结合水压判断渗水风险。',
  CO2_LEVEL:           'CO₂浓度升高，通风不良或煤体氧化征兆。',
  SO2_LEVEL:           'SO₂浓度超限，存在有害气体泄漏风险。',
};
const HANDLE_SUGGEST = {
  FILM_PRESSURE:       '建议：加强支架初撑力补压，必要时停机观测、安排顶板离层监测加密。',
  WATER_PRESSURE:      '建议：启动排水泵，加密岩溶水观测，布置探放水孔验证。',
  ULTRASONIC_DISTANCE: '建议：加强巷道支护（锚索补强），缩小监测间隔，安排人员巡查。',
  STRAIN_GAUGE:        '建议：补打锚杆/锚索，检查支护参数，控制掘进速度。',
  VIBRATION:           '建议：启动卸压爆破预案，撤出危险区域人员。',
};
const LAYOUT_INFO = {
  face:  { pos: '综采工作面液压支架立柱，间距1.5m', cov: '覆盖工作面 200m 采长', link: 'CAN总线 → LoRa网关',
           sel: '薄膜压力传感器 · 量程0-40kN · 精度±0.5%FS · 支架工作阻力直测' },
  road:  { pos: '运输巷/回风巷顶板与两帮', cov: '每50m 一个测站', link: 'RS485 → LoRa网关',
           sel: '超声波测距仪（量程0.2-6m）+ 锚杆应变片 · 顶板下沉/弯折监测' },
  karst: { pos: '回风巷岩溶水富集区顶板钻孔', cov: '覆盖溶洞发育区', link: '4-20mA → LoRa网关',
           sel: '投入式压力变送器 · 量程0-3MPa · 4-20mA标准信号 · 钻孔水压监测' },
  env:   { pos: '巷道风流断面', cov: '全断面监测', link: 'RS485 → LoRa网关',
           sel: 'DHT11温湿度 + CO₂/SO₂电化学传感器 · 环境耦合判据' },
  net:   { pos: '运输巷端部设备硐室', cov: '覆盖全矿井监测网', link: 'LoRa → 边缘网关 → 平台',
           sel: 'LoRa无线mesh自组网 + 边缘计算网关 · 与安全监控/生产系统标准接口' },
};

/* 多场耦合联动：按住某类测点 → 关联云图扩张（多源信息融合的物理力学机理） */
const FIELD_BOOST = {
  FILM_PRESSURE:       { fields: ['stress'],                 factor: 1.45, ring: '顶板压力集中 → 应力场扩张' },
  VIBRATION:           { fields: ['stress'],                 factor: 1.30, ring: '震动冲击 → 应力集中加剧' },
  WATER_PRESSURE:      { fields: ['stress', 'water'],        factor: 1.35, ring: '岩溶水压升高 → 应力场/溶洞区响应' },
  STRAIN_GAUGE:        { fields: ['disp'],                   factor: 1.35, ring: '锚杆应力升高 → 位移场扩张' },
  ULTRASONIC_DISTANCE: { fields: ['disp'],                   factor: 1.45, ring: '顶板下沉加深 → 位移场扩张' },
};

/* 地质素描资料（来自典型矿井历史脱敏数据集 · 地质素描） */
const GEO_INFO = {
  f1:       { name: 'F₁ 断层 · 导水通道', lv: 'lv3',
              type: '正断层 · 走向 NNE，倾角 62°',
              nature: '断层带破碎、渗透性增强，为岩溶水垂向运移主通道',
              danger: '导水危险性 高',
              relation: '断层带应力集中，采动扰动下易诱发顶板断裂与突水',
              sketch: '地质素描：两盘岩层错动明显，断层泥半充填，见裂隙渗水与铁锈色析出物' },
  karst1:   { name: '岩溶溶洞 · 突水风险源', lv: 'lv3',
              type: '溶蚀空洞 · 发育于灰岩层',
              nature: '溶洞顶板薄化，上覆岩层自稳性差',
              danger: '突水危险性 高',
              relation: '溶洞与巷道导通时水压突增，顶板失稳与突水叠加',
              sketch: '地质素描：洞体椭圆状，见钙华沉积，顶板裂隙与巷道贯通' },
  karst2:   { name: '岩溶水压 · 富水异常区', lv: 'lv2',
              type: '富水区 · 裂隙网络发育',
              nature: '含水层水压高，受采动影响易活化',
              danger: '水压危险性 中高',
              relation: '水压升高 → 裂隙扩展 → 应力集中 → 顶板离层（多场耦合链）',
              sketch: '地质素描：钻孔见涌水，实测水压 0.8-1.2MPa，水质矿化度高' },
  aquifer:  { name: '灰岩含水层 · 喀斯特发育', lv: 'lv1',
              type: '岩溶含水层 · 富水性强',
              nature: '含水层与 F₁ 断层导水通道相连',
              danger: '突水危险性 中',
              relation: '采动导水裂隙带沟通含水层时发生突水',
              sketch: '地质素描：岩溶发育，溶蚀裂隙网格状分布，溶孔密集' },
  interbed: { name: '砂泥岩互层 · 弱结构面', lv: 'lv1',
              type: '沉积岩互层 · 层理发育',
              nature: '层间结合力弱，易离层滑移',
              danger: '离层危险性 中',
              relation: '层理面为顶板离层/断裂的优势面，控制垮落形态',
              sketch: '地质素描：砂岩夹泥岩薄层，见层间错动擦痕与镜面' },
};

/* ---------------- 状态 ---------------- */
const FALLBACK = {
  sensor_water_pressure: { type: 'WATER_PRESSURE', name: '水压传感器', unit: 'MPa', threshold: 1.0,  value: 0.85, status: 'ONLINE' },
  sensor_film_pressure:  { type: 'FILM_PRESSURE',  name: '薄膜传感器', unit: 'kN',  threshold: 15.0, value: 12.5, status: 'ONLINE' },
  sensor_temperature:    { type: 'TEMPERATURE',    name: 'DHT11温度',  unit: '℃',  threshold: 35.0, value: 25.3, status: 'ONLINE' },
  sensor_humidity:       { type: 'HUMIDITY',       name: 'DHT11湿度',  unit: '%',  threshold: 85.0, value: 68.2, status: 'ONLINE' },
  sensor_co2:            { type: 'CO2_LEVEL',      name: 'CO2浓度',    unit: '%',  threshold: 0.05, value: 0.04, status: 'ONLINE' },
  sensor_so2:            { type: 'SO2_LEVEL',      name: 'SO2浓度',    unit: '%',  threshold: 0.002,value: 0.001,status: 'ONLINE' },
  sensor_ultrasonic:     { type: 'ULTRASONIC_DISTANCE', name: '超声波测距', unit: 'm', threshold: 2.5, value: 2.85, status: 'ONLINE' },
  sensor_strain:         { type: 'STRAIN_GAUGE',   name: '锚杆弯折',   unit: 'mm', threshold: 0.05, value: 0.02, status: 'ONLINE' },
  sensor_vibration:      { type: 'VIBRATION',      name: '震动传感器', unit: 'g',  threshold: 0.5,  value: 0.15, status: 'ONLINE' },
  lora_module:           { type: 'LORA_MODULE',    name: 'LoRa通讯模块', unit: '%', threshold: null, value: 100, status: 'ONLINE' },
};
const SENSORS = {};           // id → sensor
let ALERTS = [];
let STATS = null;
let THREATS = [];
let SELECTED = null;          // 当前选中点位（SCENE_POINTS 项）
let HISTORY = {};             // id → [{v,t}] 客户端历史（sparkline）
const LOCAL_THR = {};         // 大屏本地演示调整的阈值（sid → v），不落库，刷新后恢复
const demo = { sid: null, phase: 'idle', base: 0, cur: 0, dir: 1, rate: 0, timers: [] };
const CORE_TYPES = ['FILM_PRESSURE', 'ULTRASONIC_DISTANCE', 'WATER_PRESSURE', 'VIBRATION', 'STRAIN_GAUGE'];
const FLOW_STAGES = ['数据采集', '数据传输', '数据处理', '智能分析', '预警发布', '可视化呈现', '管控反馈'];
let SAFE_START = new Date('2023-01-01');

/* ---------------- 工具 ---------------- */
/* 传感器正常段标定（与模型 model.service.js 的 SENSOR_DEFS 一致），用于威胁度基准 */
const NORMAL = {
  sensor_film_pressure:  12.0,
  sensor_water_pressure: 0.50,
  sensor_vibration:      0.12,
  sensor_strain:         0.025,
  sensor_ultrasonic:     2.60,
  sensor_temperature:    25.3,
  sensor_humidity:       68.2,
  sensor_co2:            0.04,
  sensor_so2:            0.001,
};
function clampPct(v) { return Math.max(0, Math.min(100, v)); }
function levelOf(s) {
  // 预报警：未超阈值但威胁度 ≥70%（安全裕度不足 30%），提前黄色提示
  if (s && s.threshold != null && !isOverThreshold(s)) {
    if (threatOf(s) >= 70) return 'YELLOW';
    return null;
  }
  if (!s || !isOverThreshold(s)) return null;
  const ratio = Math.abs(s.value - s.threshold) / s.threshold;
  if (ratio > 0.5) return 'RED';
  if (ratio > 0.3) return 'ORANGE';
  return 'YELLOW';
}
const LV_CLASS = { RED: 'lv3', ORANGE: 'lv2', YELLOW: 'lv1' };
/* 威胁度（0~100%）：正常段为 0%，预警阈值为 80%，阈值再偏移 25% 裕度为 100%。
 * 长按演示时随数值爬升平滑增长，避免"一到阈值就锁死 100%"的体验问题。 */
function threatOf(s) {
  if (!s || s.threshold == null) return 0;
  const n = NORMAL[s.id], t = s.threshold;
  if (n == null || t === n) {   // 无标定/标定退化：退回简单比例
    return clampPct(Math.round(s.value / t * 100));
  }
  let pct;
  if (s.type === 'ULTRASONIC_DISTANCE') {
    // 值越小越危险：正常处 0%，阈值处 80%，再降 (正常-阈值)×25% 处 100%
    const span = n - t;
    if (span <= 0) return s.value <= t ? 100 : 0;
    if (s.value >= n) return 0;
    pct = s.value >= t ? (n - s.value) / span * 80 : 80 + (t - s.value) / span * 20;
  } else {
    // 值越大越危险：正常处 0%，阈值处 80%，再升 (阈值-正常)×25% 处 100%
    const span = t - n;
    if (span <= 0) return s.value >= t ? 100 : 0;
    if (s.value <= n) return 0;
    pct = s.value <= t ? (s.value - n) / span * 80 : 80 + (s.value - t) / span * 20;
  }
  return clampPct(Math.round(pct));
}
function pushHistory(sid, v) {
  (HISTORY[sid] = HISTORY[sid] || []).push({ v, t: Date.now() });
  if (HISTORY[sid].length > 60) HISTORY[sid].shift();
}
function flashSel(sel, cls) {
  const el = $(sel);
  if (!el) return;
  el.classList.add('bs-flash');
  setTimeout(() => el.classList.remove('bs-flash'), 1400);
}
function toast(msg) { showToast(msg); }

/* ---------------- 场景渲染 ---------------- */
function renderScene() {
  const dotG = $('#sceneDots'), labG = $('#sceneLabels'), alertG = $('#sceneAlerts'), netG = $('#layer-network');
  dotG.innerHTML = ''; labG.innerHTML = ''; alertG.innerHTML = '';
  const netOn = $('#layer-network').classList.contains('on');

  // 监测网络链路（需在点位之下）
  let net = '';
  if (netOn) {
    const gw = SCENE_POINTS.find(p => p.sid === 'lora_module');
    net += `<line x1="100" y1="96" x2="100" y2="530" stroke="#58a6a0" stroke-width="2" stroke-dasharray="4 4" opacity=".7"/>`;
    net += `<text x="108" y="300" font-size="10" fill="#58a6a0" opacity=".75" transform="rotate(90 108 300)">LoRa无线传输</text>`;
    SCENE_POINTS.forEach(p => {
      if (p.sid === 'lora_module') return;
      net += `<line x1="${p.x}" y1="${p.y}" x2="${gw.x}" y2="${gw.y}" stroke="#3f5b66" stroke-width="1" stroke-dasharray="3 4" opacity=".5"/>`;
    });
  }
  netG.innerHTML = net;

  SCENE_POINTS.forEach(p => {
    const s = SENSORS[p.sid];
    if (!s) return;
    const lv = levelOf(s);
    const cls = LV_CLASS[lv] || 'lv0';
    const isSel = SELECTED && SELECTED.sid === p.sid && SELECTED.label === p.label;
    if (lv && $('#layer-alertzone').classList.contains('on')) {
      alertG.innerHTML += `<circle class="shalo ${cls}" cx="${p.x}" cy="${p.y}" r="13"/>`;
    }
    dotG.innerHTML += `<circle class="sdot ${cls}${isSel ? ' sel' : ''}" data-sid="${p.sid}" data-label="${p.label}"
      cx="${p.x}" cy="${p.y}" r="${isSel ? 9 : 7}"/>`;
    const unit = s.unit || '';
    labG.innerHTML += `<g class="slab" data-sid="${p.sid}" data-label="${p.label}">
      <text x="${p.x}" y="${p.y + 20}" text-anchor="middle" class="slab-name">${p.label}</text>
      <text x="${p.x}" y="${p.y + 35}" text-anchor="middle" class="slab-val ${cls}">${fmt2(s.value)}${unit}</text>
    </g>`;
  });
  renderSensorList();
}

function renderSensorList() {
  const ul = $('#bsSensorList');
  const items = SCENE_POINTS.filter(p => p.sid !== 'lora_module' && SENSORS[p.sid])
    .map(p => {
      const s = SENSORS[p.sid];
      const lv = levelOf(s);
      const cls = LV_CLASS[lv] || 'lv0';
      return `<li class="bs-sitem ${cls}" data-sid="${p.sid}" data-label="${p.label}">
        <i class="bs-dot ${cls}"></i><span class="bs-sname">${esc(p.label)}</span>
        <b class="bs-sval">${fmt2(s.value)}<i>${s.unit || ''}</i></b>
      </li>`;
    }).join('');
  ul.innerHTML = items || '<li class="bs-empty">暂无可显示传感器</li>';
  $('#bsSensorCount').textContent = SCENE_POINTS.filter(p => p.sid !== 'lora_module' && SENSORS[p.sid]).length;
  // 点击传感器 → 定位场景点位
  ul.querySelectorAll('.bs-sitem').forEach(el => {
    el.addEventListener('click', () => {
      const sid = el.dataset.sid, label = el.dataset.label;
      selectPoint(SCENE_POINTS.find(p => p.sid === sid && p.label === label) || SCENE_POINTS.find(p => p.sid === sid));
      flashPoint(sid);
    });
  });
}

function flashPoint(sid) {
  const svg = $('#twinScene');
  svg.querySelectorAll(`.sdot[data-sid="${sid}"]`).forEach(d => {
    d.classList.add('flash');
    setTimeout(() => d.classList.remove('flash'), 1600);
  });
  svg.querySelectorAll(`.slab[data-sid="${sid}"]`).forEach(d => {
    d.classList.add('flash');
    setTimeout(() => d.classList.remove('flash'), 1600);
  });
}

/* ---------------- 多场耦合联动（按住→关联云图扩张，松开→恢复） ---------------- */
function boostClouds(sid, on) {
  const s = SENSORS[sid];
  const cfg = s && FIELD_BOOST[s.type];
  const svg = $('#twinScene');
  if (!cfg || !svg) { if (svg) $('#cloudRings').innerHTML = ''; return; }
  svg.querySelectorAll('.cloud').forEach(c => {
    const f = c.dataset.field;
    if (!cfg.fields.includes(f)) return;
    const factor = cfg.factor;
    if (on) {
      if (c.tagName === 'ellipse') {
        if (!c.dataset.origRx) { c.dataset.origRx = c.getAttribute('rx'); c.dataset.origRy = c.getAttribute('ry'); }
        c.setAttribute('rx', (+c.dataset.origRx * factor).toFixed(1));
        c.setAttribute('ry', (+c.dataset.origRy * factor).toFixed(1));
      } else {
        if (!c.dataset.origR) c.dataset.origR = c.getAttribute('r');
        c.setAttribute('r', (+c.dataset.origR * factor).toFixed(1));
      }
      c.classList.add('hot');
    } else if (c.dataset.origR || c.dataset.origRx) {
      if (c.dataset.origR) { c.setAttribute('r', c.dataset.origR); delete c.dataset.origR; }
      if (c.dataset.origRx) { c.setAttribute('rx', c.dataset.origRx); c.setAttribute('ry', c.dataset.origRy); delete c.dataset.origRx; delete c.dataset.origRy; }
      c.classList.remove('hot');
    }
  });
  // 联动脉冲环：渲染在最靠近测点的云图中心
  if (on) {
    const p = SCENE_POINTS.find(q => q.sid === sid);
    let best = null, bd = 1e9;
    svg.querySelectorAll('.cloud').forEach(c => {
      if (!cfg.fields.includes(c.dataset.field)) return;
      const cx = +c.getAttribute('cx'), cy = +c.getAttribute('cy');
      const d = p ? Math.hypot(cx - p.x, cy - p.y) : 0;
      if (d < bd) { bd = d; best = c; }
    });
    if (best) {
      const r = best.tagName === 'ellipse' ? Math.max(+best.getAttribute('rx'), +best.getAttribute('ry')) : +best.getAttribute('r');
      $('#cloudRings').innerHTML = `<circle class="cloud-ring" cx="${best.getAttribute('cx')}" cy="${best.getAttribute('cy')}" r="${(r * 0.85).toFixed(1)}"/>`;
    }
  } else {
    $('#cloudRings').innerHTML = '';
  }
}

/* ---------------- 数据传输链路动画（LoRa 数据包流动） ---------------- */
const PACKETS = [];
function tickPackets() {
  const netG = $('#layer-network');
  if (!netG || !netG.classList.contains('on')) { PACKETS.length = 0; $('#netPackets').innerHTML = ''; return; }
  const gw = SCENE_POINTS.find(p => p.sid === 'lora_module');
  const targets = SCENE_POINTS.filter(p => p.sid !== 'lora_module');
  if (!gw) return;
  if (PACKETS.length < 12 && Math.random() < 0.55) {
    const p = targets[Math.floor(Math.random() * targets.length)];
    PACKETS.push({ fx: p.x, fy: p.y, tx: gw.x, ty: gw.y, t: 0, speed: 0.012 + Math.random() * 0.02 });
  }
  let html = '';
  for (let i = PACKETS.length - 1; i >= 0; i--) {
    const pk = PACKETS[i];
    pk.t += pk.speed;
    if (pk.t >= 1) { PACKETS.splice(i, 1); continue; }
    const x = pk.fx + (pk.tx - pk.fx) * pk.t;
    const y = pk.fy + (pk.ty - pk.fy) * pk.t;
    html += `<circle class="pkt" cx="${x.toFixed(1)}" cy="${y.toFixed(1)}" r="2.4"/>`;
  }
  $('#netPackets').innerHTML = html;
}

/* ---------------- 监测网络拓扑卡（点击 LoRa 网关） ---------------- */
function openNetModal() {
  const gw = SENSORS['lora_module'];
  const groups = ['face', 'road', 'karst', 'env'];
  const rows = groups.map(k => {
    const info = LAYOUT_INFO[k] || {};
    const pts = SCENE_POINTS.filter(p => p.grp === k && p.sid !== 'lora_module');
    const sids = [...new Set(pts.map(p => p.sid))];
    const online = sids.filter(id => SENSORS[id] && SENSORS[id].status === 'ONLINE').length;
    const rate = (0.6 + Math.random() * 3.2).toFixed(1);
    return `<div class="bs-net-row">
      <span class="bs-net-name">${esc(k)}</span>
      <span class="bs-net-link">${esc(info.link || '—')}</span>
      <b class="bs-net-rate">${rate} kb/s</b>
      <i class="bs-net-on ${online === sids.length ? 'ok' : ''}">${online}/${sids.length} 在线</i>
    </div>`;
  }).join('');
  $('#bsNetBody').innerHTML = `
    <div class="bs-net-head">
      <span>LoRa网关 · ${gw ? (gw.status === 'ONLINE' ? '在线' : '离线') : '在线'}</span>
      <span>mesh 自组网节点 ${SCENE_POINTS.length - 1} 个</span>
      <span>上行链路 10.0.2.2:3000 / :8080</span>
    </div>
    ${rows}
    <div class="bs-geo-tip">数据传输采用「CAN/RS485/4-20mA → LoRa → 边缘网关 → 平台」多协议融合；通过标准 JSON 接口与既有安全监控系统、生产系统对接，解决"信息孤岛"，实现多源数据共享。</div>`;
  $('#bsNetModal').classList.add('show');
}

/* ---------------- 地质素描信息卡（点击断层/溶洞/含水层） ---------------- */
function openGeoModal(id) {
  const g = GEO_INFO[id];
  if (!g) return;
  $('#bsGeoName').textContent = g.name;
  $('#bsGeoName').className = 'bs-lv ' + g.lv;
  $('#bsGeoBody').innerHTML = `
    <div class="bs-geo-grid">
      <div><span>构造类型</span><b>${esc(g.type)}</b></div>
      <div><span>${esc(g.danger)}</span></div>
    </div>
    <div class="bs-geo-row"><span>构造性质</span><b>${esc(g.nature)}</b></div>
    <div class="bs-geo-row"><span>灾变关联</span><b>${esc(g.relation)}</b></div>
    <div class="bs-geo-row"><span>地质素描</span><b>${esc(g.sketch)}</b></div>
    <div class="bs-geo-tip">数据来源：典型矿井顶板安全监测历史脱敏数据集 · 地质素描资料；点击断层/溶洞/含水层可联动查看，按住岩溶水测点可演示水压耦合。</div>`;
  $('#bsGeoModal').classList.add('show');
}

/* ---------------- 预警发布滚动横幅 ---------------- */
function renderBanner() {
  const b = $('#bsBanner'), track = $('#bsBannerTrack');
  if (!b || !track) return;
  const un = ALERTS.filter(a => !a.handled);
  if (!un.length) { b.hidden = true; return; }
  b.hidden = false;
  track.innerHTML = un.slice(0, 12).map(a =>
    `<span class="bs-banner-item">${LEVEL_TXT[a.level] || '预警'} · ${esc(a.message)} · ${fmtTime(a.created_at)}</span>`
  ).join('');
}

/* ---------------- 点位选中 / 多源融合卡 ---------------- */
function selectPoint(p) {
  SELECTED = p;
  renderScene();
  renderFusion();
}

function sparkline(sid, cls) {
  const h = HISTORY[sid] || [];
  if (h.length < 2) return '<div class="bs-spark-empty">暂无历史样本</div>';
  const W = 200, H = 34, pad = 2;
  const vals = h.slice(-30).map(o => o.v);
  const min = Math.min(...vals), max = Math.max(...vals);
  const span = (max - min) || 1;
  const x = (i) => pad + (W - pad * 2) * i / (vals.length - 1);
  const y = (v) => H - pad - (H - pad * 2) * (v - min) / span;
  const pts = vals.map((v, i) => `${x(i).toFixed(1)},${y(v).toFixed(1)}`).join(' ');
  return `<svg viewBox="0 0 ${W} ${H}" class="bs-spark"><polyline points="${pts}" fill="none" stroke="var(--${cls === 'lv3' ? 'red' : cls === 'lv2' ? 'orange' : cls === 'lv1' ? 'amber' : 'accent'})" stroke-width="1.5"/></svg>`;
}

function coreBars() {
  const rows = CORE_TYPES.map(t => {
    const s = Object.values(SENSORS).find(x => x.type === t);
    if (!s) return '';
    const pct = threatOf(s), lv = levelOf(s);
    const cls = LV_CLASS[lv] || 'lv0';
    return `<div class="bs-mbar">
      <div class="bs-mbar-h"><span>${esc(s.name)}</span><b class="${cls}">${fmt2(s.value)} ${s.unit || ''}</b></div>
      <div class="bs-mbar-t"><i style="width:${pct}%" class="${cls}"></i><em>${pct}%</em></div>
    </div>`;
  }).join('');
  return rows;
}

function renderFusion() {
  const body = $('#bsFusionBody');
  if (!SELECTED) {
    // 总览：多源数据融合
    const core = coreBars();
    const risk = STATS && STATS.riskIndex != null ? STATS.riskIndex : 0;
    const riskLv = risk >= 80 ? '高' : risk >= 60 ? '中高' : risk >= 40 ? '中' : '低';
    const acc = STATS && STATS.modelAccuracy != null ? STATS.modelAccuracy : 92.4;
    const fr  = STATS && STATS.falseRate != null ? STATS.falseRate : 7.6;
    body.innerHTML = `
      <div class="bs-fusion-ov">
        <div class="bs-fusion-core">${core || '<div class="bs-empty">暂无数据</div>'}</div>
        <div class="bs-fusion-model">
          <span>数字孪生AI预警模型</span>
          <div class="bs-model-line"><b>测试集准确率</b><i>${acc}%</i></div>
          <div class="bs-model-line"><b>误报率</b><i>${fr}%</i></div>
          <div class="bs-model-line"><b>综合风险</b><i class="${riskLv === '高' ? 'lv3' : riskLv === '中高' ? 'lv2' : riskLv === '中' ? 'lv1' : 'lv0'}">${riskLv}</i></div>
        </div>
        <div class="bs-fusion-tip">单击孪生场景任一测点，查看该点多源融合状态与力学机理；按住压力/水压/震动/锚杆测点可演示压力爬升与回落。</div>
      </div>`;
    $('#bsFusionTag').textContent = '多源融合总览';
    return;
  }
  const p = SELECTED;
  const s = SENSORS[p.sid];
  if (!s) { body.innerHTML = '<div class="bs-empty">传感器离线</div>'; return; }
  const lv = levelOf(s), cls = LV_CLASS[lv] || 'lv0';
  const pct = threatOf(s);
  const layout = LAYOUT_INFO[p.grp] || {};
  const mech = MECHANISM[s.type] || '';
  const slider = SLIDER_KEYS[p.sid];
  const demoable = DEMO_TYPES[s.type];
  const demoLive = demo.sid === p.sid && demo.phase !== 'idle';
  $('#bsFusionTag').textContent = p.label;

  body.innerHTML = `
    <div class="bs-fuse-h">
      <b>${esc(p.label)}</b><i class="${cls} fuse-status">${esc(s.name)} · ${lv ? LEVEL_TXT[lv] + '预警' : '正常'}</i>
      ${demoLive ? '<span class="bs-tag red">演示中</span>' : ''}
    </div>
    <div class="bs-fuse-main">
      <span>实时值 <b class="${cls} fuse-val">${fmt2(s.value)} ${s.unit || ''}</b></span>
      <span>预警阈值 <b class="fuse-thr">${s.threshold != null ? s.threshold + ' ' + (s.unit || '') : '未设置'}</b></span>
      <span>威胁度 <b class="${cls} fuse-pct">${pct}%</b></span>
    </div>
    <div class="bs-mbar-t big"><i style="width:${pct}%" class="${cls} fuse-bar"></i></div>
    <div class="bs-spark-wrap">${sparkline(p.sid, cls)}</div>
    ${slider ? `
    <div class="bs-slider">
      <span>预警阈值调节（${slider.keyName}）</span>
      <input type="range" min="${slider.min}" max="${slider.max}" step="${slider.step}"
        value="${s.threshold}" data-key="${slider.keyName}" data-sid="${p.sid}">
      <b class="bs-slider-val">${s.threshold} ${slider.unit}</b>
    </div>` : ''}
    ${demoable ? `<div class="bs-demo-hint">${demoable.hint}，松开后逐步恢复${demoLive ? '（正在演示，即将回落）' : ''}</div>` : ''}
    <div class="bs-fuse-info">
      <div class="bs-info-row"><span>安装位置</span><b>${layout.pos || '—'}</b></div>
      <div class="bs-info-row"><span>覆盖范围</span><b>${layout.cov || '—'}</b></div>
      <div class="bs-info-row"><span>传输链路</span><b>${layout.link || '—'}</b></div>
      <div class="bs-info-row"><span>传感器选型</span><b>${layout.sel || '—'}</b></div>
    </div>
    <div class="bs-fuse-mech">力学机理：${mech || '—'}</div>`;
  // 阈值滑杆事件：仅本地演示调节，不写入数据库（正式改阈值请走企业端系统设置）
  const rg = body.querySelector('input[type=range]');
  if (rg) {
    rg.addEventListener('input', () => {
      const v = Number(rg.value);
      body.querySelector('.bs-slider-val').textContent = v + ' ' + (SLIDER_KEYS[rg.dataset.sid] || {}).unit;
      clearTimeout(rg._t);
      rg._t = setTimeout(() => {
        try {
          if (SENSORS[rg.dataset.sid]) {
            SENSORS[rg.dataset.sid].threshold = v;
            LOCAL_THR[rg.dataset.sid] = v;   // 记录本地演示阈值，WS 更新时保留
          }
          renderScene(); renderFusion();
          toast('阈值已本地演示调整（不保存，刷新后恢复）');
        } catch (e) { toast(e.message); }
      }, 400);
    });
  }
}

/* 演示进行中：原位刷新数值/威胁度/走势，避免整块重建打断滑杆等交互 */
function updateFusionLive() {
  if (!SELECTED || SELECTED.sid !== demo.sid) return;
  const s = SENSORS[demo.sid], body = $('#bsFusionBody');
  if (!s || !body) return;
  const lv = levelOf(s), cls = LV_CLASS[lv] || 'lv0', pct = threatOf(s);
  const st = body.querySelector('.fuse-status');
  if (st) { st.textContent = `${s.name} · ${lv ? LEVEL_TXT[lv] + '预警' : '正常'}`; st.className = cls + ' fuse-status'; }
  const v = body.querySelector('.fuse-val');
  if (v) { v.textContent = fmt2(s.value) + ' ' + (s.unit || ''); v.className = cls + ' fuse-val'; }
  const p = body.querySelector('.fuse-pct');
  if (p) { p.textContent = pct + '%'; p.className = cls + ' fuse-pct'; }
  const b = body.querySelector('.fuse-bar');
  if (b) { b.style.width = pct + '%'; b.className = cls + ' fuse-bar'; }
  const sp = body.querySelector('.bs-spark-wrap');
  if (sp) sp.innerHTML = sparkline(demo.sid, cls);
}

/* ---------------- 风险环 ---------------- */
function renderRisk() {
  // 综合风险 = max(后端风险指数, 当前最大传感器威胁度)：演示爬升时风险环随之联动，
  // 避免出现"威胁度100%但风险指数只有66"的矛盾展示。
  const base = STATS && STATS.riskIndex != null ? STATS.riskIndex : 0;
  const maxThreat = Object.values(SENSORS).reduce((m, s) => Math.max(m, threatOf(s)), 0);
  const risk = Math.max(base, maxThreat);
  const lvTxt = risk >= 80 ? '高风险' : risk >= 60 ? '中高风险' : risk >= 40 ? '中等风险' : '低风险';
  const cls = risk >= 80 ? 'lv3' : risk >= 60 ? 'lv2' : risk >= 40 ? 'lv1' : 'lv0';
  const C = 2 * Math.PI * 50;
  $('#riskRing').innerHTML = `
    <circle cx="60" cy="60" r="50" fill="none" stroke="rgba(255,255,255,.07)" stroke-width="10"/>
    <circle cx="60" cy="60" r="50" fill="none" stroke="var(--${cls === 'lv3' ? 'red' : cls === 'lv2' ? 'orange' : cls === 'lv1' ? 'amber' : 'accent'})"
      stroke-width="10" stroke-linecap="round" stroke-dasharray="${(C * risk / 100).toFixed(1)} ${C.toFixed(1)}"
      transform="rotate(-90 60 60)"/>
    <text x="60" y="56" text-anchor="middle" class="bs-ring-txt">${risk}</text>
    <text x="60" y="72" text-anchor="middle" class="bs-ring-sub">风险指数</text>`;
  $('#bsRiskLevel').textContent = lvTxt;
  $('#bsRiskLevel').className = 'bs-tag ' + cls;
  $('#bsRiskNum').textContent = risk;
  $('#bsRiskSub').textContent = STATS ? `未处置预警 ${STATS.unhandled} 条 · 模型准确率 ${STATS.modelAccuracy}%` : '—';
}

/* ---------------- 预警列表 / 弹窗 ---------------- */
function renderAlerts() {
  const list = $('#bsAlertList');
  if (!ALERTS.length) { list.innerHTML = '<li class="bs-empty">暂无预警</li>'; }
  else {
    list.innerHTML = ALERTS.slice(0, 30).map(a => `
      <li class="bs-alert ${a.handled ? 'done' : ''}" data-id="${a.id}" data-sid="${a.sensor_id}">
        <i class="bs-alv ${LV_CLASS[a.level] || 'lv0'}">${LEVEL_TXT[a.level] || a.level}</i>
        <span class="bs-am">${esc(a.message)}</span>
        <em>${fmtTime(a.created_at)}</em>
      </li>`).join('');
  }
  const un = ALERTS.filter(a => !a.handled).length;
  $('#bsAlertCount').textContent = un;
  $('#bsAlertCount').className = 'bs-tag ' + (un ? 'red' : '');
  renderBanner();
  list.querySelectorAll('.bs-alert').forEach(el => {
    el.addEventListener('click', () => {
      const a = ALERTS.find(x => x.id === el.dataset.id);
      if (a) { openAlertModal(a); flashPoint(a.sensor_id); }
    });
  });
}

function openAlertModal(a) {
  const lv = LV_CLASS[a.level] || 'lv0';
  const s = SENSORS[a.sensor_id];
  const mech = s ? (MECHANISM[s.type] || '') : '';
  const sug = s ? (HANDLE_SUGGEST[s.type] || '') : '';
  $('#bsAmLevel').textContent = LEVEL_TXT[a.level] + '预警';
  $('#bsAmLevel').className = 'bs-lv ' + lv;
  $('#bsAmBody').innerHTML = `
    <div class="bs-am-msg">${esc(a.message)}</div>
    <div class="bs-am-meta">
      <span>测点 <b>${esc(a.sensor_name || a.sensor_id)}</b></span>
      <span>实测值 <b>${a.value != null ? fmt2(a.value) : '--'}</b></span>
      <span>阈值 <b>${a.threshold != null ? a.threshold + (s ? ' · ' + thresholdDir(s) : '') : '--'}</b></span>
      <span>时间 <b>${fmtTime(a.created_at)}</b></span>
    </div>
    <div class="bs-am-mech">力学机理：${mech || '—'}</div>
    ${sug ? `<div class="bs-am-sug">${sug}</div>` : ''}`;
  $('#bsAlertModal').dataset.alertId = a.id;
  $('#bsAlertModal').classList.add('show');
}
$('#bsAmClose') && ($('#bsAmClose').onclick = () => $('#bsAlertModal').classList.remove('show'));
$('#bsAmHandle') && ($('#bsAmHandle').onclick = async () => {
  const id = $('#bsAlertModal').dataset.alertId;
  try {
    await api('/alert/handle', { method: 'POST', body: { alertId: id, handledBy: '综合态势大屏' } });
    const a = ALERTS.find(x => x.id === id);
    if (a) a.handled = true;
    $('#bsAlertModal').classList.remove('show');
    renderAlerts(); renderKpi(); renderFlow();
    toast('预警已处置，管控反馈已同步三端');
  } catch (e) { toast(e.message); }
});

/* ---------------- KPI 带 / 流程环 / 时钟 ---------------- */
function renderKpi() {
  const g = (id) => SENSORS[id];
  const film = g('sensor_film_pressure'), ult = g('sensor_ultrasonic'), wat = g('sensor_water_pressure'),
        tmp = g('sensor_temperature'), co2 = g('sensor_co2');
  $('#kpiPressure').textContent = film ? fmt2(film.value) : '--';
  $('#kpiPressure').className = LV_CLASS[levelOf(film)] || 'lv0';
  $('#kpiPressureUnit').textContent = film ? (film.unit || 'kN') : '';
  $('#kpiSink').textContent = ult ? fmt2(ult.value) : '--';
  $('#kpiSink').className = LV_CLASS[levelOf(ult)] || 'lv0';
  $('#kpiWater').textContent = wat ? fmt2(wat.value) : '--';
  $('#kpiWater').className = LV_CLASS[levelOf(wat)] || 'lv0';
  const online = Object.values(SENSORS).filter(s => s.status === 'ONLINE').length;
  const warn = Object.values(SENSORS).filter(s => levelOf(s)).length;
  $('#kpiDevice').textContent = online + '/' + Object.keys(SENSORS).length;
  $('#kpiDeviceUnit').textContent = warn ? warn + ' 预警' : '在线';
  $('#kpiTemp').textContent = tmp ? fmt2(tmp.value) : '--';
  $('#kpiGas').textContent = co2 ? co2.value.toFixed(3) : '--';
  const un = ALERTS.filter(a => !a.handled).length;
  $('#kpiUnhandled').textContent = un;
  $('#kpiResp').textContent = un ? (un * 2) + 's 处置中' : '正常';
}

function renderFlow() {
  const wrap = $('#bsFlowStages');
  const un = ALERTS.filter(a => !a.handled).length;
  wrap.innerHTML = FLOW_STAGES.map((st, i) => {
    const active = un > 0 ? (i === 4 || i === 6 ? ' warn' : i === 5 ? ' active' : '') : (i === 5 ? ' active' : '');
    return `<div class="bs-stage${active}" data-i="${i}"><span>${st}</span></div>`;
  }).join('');
  wrap.querySelectorAll('.bs-stage').forEach(el => {
    el.addEventListener('click', () => focusStage(Number(el.dataset.i)));
  });
}
function focusStage(i) {
  if (i === 0) flashSel('#sceneDots', 'bs-flash');
  if (i === 1) { $('#layer-network').classList.add('on'); syncLayerCheck(); flashPoint('lora_module'); }
  if (i === 2 || i === 3) flashSel('.bs-right .bs-panel:first-child', 'bs-flash');
  if (i === 4) { $('#layer-alertzone').classList.add('on'); syncLayerCheck(); flashSel('#sceneAlerts', 'bs-flash'); }
  if (i === 5) flashSel('.bs-scene-wrap', 'bs-flash');
  if (i === 6) flashSel('.bs-right .bs-panel', 'bs-flash');
}

function tickClock() {
  const d = new Date();
  const w = ['日', '一', '二', '三', '四', '五', '六'][d.getDay()];
  const p = (n) => String(n).padStart(2, '0');
  $('#bsDate').textContent = `${d.getFullYear()}年${d.getMonth() + 1}月${d.getDate()}日 星期${w}`;
  $('#bsTime').textContent = `${p(d.getHours())}:${p(d.getMinutes())}:${p(d.getSeconds())}`;
  $('#bsSafeDays').textContent = Math.max(1, Math.floor((d - SAFE_START) / 86400000));
}

/* ---------------- 图层开关 ---------------- */
function syncLayerCheck() {
  document.querySelectorAll('#bsLayers input[type=checkbox]').forEach(cb => {
    const layer = cb.dataset.layer;
    cb.checked = layer === 'basemap' || $('#' + (layer === 'stress' ? 'layer-stress' : layer === 'displacement' ? 'layer-displacement' : layer === 'geo' ? 'layer-geo' : layer === 'network' ? 'layer-network' : 'layer-alertzone')).classList.contains('on');
  });
}
function initLayers() {
  document.querySelectorAll('#bsLayers input[type=checkbox]').forEach(cb => {
    cb.addEventListener('change', () => {
      const layer = cb.dataset.layer;
      if (layer === 'basemap') { if (!cb.checked) { cb.checked = true; toast('矿山底图图层不可关闭'); } return; }
      const gid = layer === 'stress' ? 'layer-stress' : layer === 'displacement' ? 'layer-displacement' : layer === 'geo' ? 'layer-geo' : layer === 'network' ? 'layer-network' : 'layer-alertzone';
      const g = document.getElementById(gid);
      g.classList.toggle('on', cb.checked);
      if (layer === 'network' || layer === 'alertzone') renderScene();
    });
  });
}

/* ---------------- 按住爬升 / 松开回落 演示 ---------------- */
function demoable(sid) {
  const s = SENSORS[sid];
  return s && DEMO_TYPES[s.type];
}
function startClimb(p) {
  const s = SENSORS[p.sid];
  const cfg = DEMO_TYPES[s.type];
  demo.sid = p.sid; demo.base = s.value; demo.cur = s.value;
  demo.dir = cfg.dir; demo.rate = cfg.rate;
  demo.phase = 'climbing';
  boostClouds(p.sid, true);   // 多场耦合联动：关联云图扩张
  demo.timers.push(setInterval(() => {
    demo.cur += demo.rate * demo.dir;
    if (cfg.max != null && demo.cur > cfg.max) demo.cur = cfg.max;
    if (cfg.min != null && demo.cur < cfg.min) demo.cur = cfg.min;
    SENSORS[demo.sid].value = demo.cur;
    pushHistory(demo.sid, demo.cur);
    renderScene(); renderKpi(); renderRisk();
    if (SELECTED && SELECTED.sid === demo.sid) updateFusionLive();
  }, 300));
}
function stopClimb() {
  if (demo.phase !== 'climbing') return;
  demo.phase = 'recovering';
  boostClouds(demo.sid, false);   // 松开 → 关联云图逐步恢复
  demo.timers.push(setInterval(() => {
    const diff = demo.base - demo.cur;
    if (Math.abs(diff) < 0.05) {
      demo.cur = demo.base;
      finishDemo();
      return;
    }
    demo.cur += diff / 4;
    SENSORS[demo.sid].value = demo.cur;
    pushHistory(demo.sid, demo.cur);
    renderScene(); renderKpi(); renderRisk();
    if (SELECTED && SELECTED.sid === demo.sid) updateFusionLive();
  }, 250));
}
function finishDemo() {
  demo.phase = 'idle';
  demo.timers.forEach(t => clearInterval(t));
  demo.timers = [];
  if (SENSORS[demo.sid]) { SENSORS[demo.sid].value = demo.base; pushHistory(demo.sid, demo.base); }
  renderScene(); renderKpi(); renderFusion();
  demo.sid = null;
}

function attachSceneEvents() {
  const svg = $('#twinScene');
  let holdTimer = null, pressedPt = null;
  const start = (e) => {
    // 地质构造要素点击 → 地质素描信息卡
    const geo = e.target.closest ? e.target.closest('[data-geo]') : null;
    if (geo) { openGeoModal(geo.dataset.geo); return; }
    const el = e.target.closest ? e.target.closest('.sdot') : null;
    if (!el) return;
    const p = SCENE_POINTS.find(q => q.sid === el.dataset.sid && q.label === el.dataset.label) ||
              SCENE_POINTS.find(q => q.sid === el.dataset.sid);
    selectPoint(p);
    flashPoint(p.sid);
    if (p.sid === 'lora_module') { openNetModal(); return; }   // 点击LoRa网关 → 网络拓扑
    if (!demoable(p.sid) || demo.phase !== 'idle') return;
    pressedPt = p;
    holdTimer = setTimeout(() => { if (pressedPt) startClimb(pressedPt); }, 400);
  };
  const end = () => {
    if (holdTimer) { clearTimeout(holdTimer); holdTimer = null; }
    pressedPt = null;
    if (demo.phase === 'climbing') stopClimb();
  };
  svg.addEventListener('mousedown', start);
  svg.addEventListener('mouseup', end);
  svg.addEventListener('mouseleave', end);
  svg.addEventListener('touchstart', (e) => { const t = e.touches[0]; start({ target: document.elementFromPoint(t.clientX, t.clientY), clientX: t.clientX, clientY: t.clientY }); }, { passive: true });
  svg.addEventListener('touchend', end, { passive: true });
}

/* ---------------- 数据加载 / WS ---------------- */
async function loadData() {
  try {
    const [sen, ale, sta] = await Promise.allSettled([
      api('/sensor/all'), api('/alert/all'), api('/analysis/stats')
    ]);
    if (sen.status === 'fulfilled') {
      sen.value.forEach(s => { SENSORS[s.id] = s; pushHistory(s.id, s.value); });
    } else { applyFallback(); }
    if (ale.status === 'fulfilled') ALERTS = ale.value;
    if (sta.status === 'fulfilled') STATS = sta.value;
    try { THREATS = await api('/analysis/threat'); } catch (e) {}
  } catch (e) {
    applyFallback();
  }
  renderScene(); renderFusion(); renderRisk(); renderAlerts(); renderKpi(); renderFlow();
  wsClient.connect('bigscreen');
}
function applyFallback() {
  Object.entries(FALLBACK).forEach(([id, s]) => { SENSORS[id] = { ...s, id }; pushHistory(id, s.value); });
}

function connectWS() {
  wsClient.on('sensor_update', (data) => {
    if (!Array.isArray(data)) return;
    data.forEach(s => {
      if (demo.sid === s.id && demo.phase !== 'idle') return; // 演示期间忽略服务端覆盖
      if (LOCAL_THR[s.id] !== undefined) s = { ...s, threshold: LOCAL_THR[s.id] }; // 保留本地演示阈值
      SENSORS[s.id] = s;
      pushHistory(s.id, s.value);
    });
    renderScene(); renderKpi();
    if (SELECTED) {
      // 演示进行中：仅原位刷新，避免整块重建打断滑杆等交互
      if (demo.phase !== 'idle' && SELECTED.sid === demo.sid) updateFusionLive();
      else renderFusion();
    }
    if (!STATS) renderRisk();
  });
  wsClient.on('alert_update', (a) => {
    if (!a) return;
    if (!ALERTS.some(x => x.id === a.id)) ALERTS.unshift(a);
    renderAlerts(); renderKpi(); renderFlow(); renderRisk();
    flashPoint(a.sensor_id);
  });
  wsClient.on('connection_status', (p) => {
    const led = $('#bsLed'), txt = $('#bsConnText');
    if (!led || !txt) return;
    if (p.connected) { led.classList.remove('gray'); txt.textContent = '实时数据通道 · 在线'; }
    else { led.classList.add('gray'); txt.textContent = '实时数据通道 · 离线'; }
  });
}

/* ---------------- 初始化 ---------------- */
function init() {
  renderFlow();
  tickClock();
  setInterval(tickClock, 1000);
  initLayers();
  attachSceneEvents();
  setInterval(tickPackets, 60);   // 数据传输链路动画
  // 点击"未处置预警"KPI → 高亮右侧实时预警面板
  $('#kpiUnhandled') && ($('#kpiUnhandled').addEventListener('click', () => {
    const panel = $('.bs-alerts');
    if (panel) panel.classList.add('bs-flash');
    setTimeout(() => panel && panel.classList.remove('bs-flash'), 1400);
  }));
  const maskClose = (modalId) => {
    const m = $(modalId);
    if (m) m.addEventListener('click', (e) => { if (e.target === m) m.classList.remove('show'); });
  };
  maskClose('#bsAlertModal'); maskClose('#bsGeoModal'); maskClose('#bsNetModal');
  $('#bsGeoClose') && ($('#bsGeoClose').onclick = () => $('#bsGeoModal').classList.remove('show'));
  $('#bsNetClose') && ($('#bsNetClose').onclick = () => $('#bsNetModal').classList.remove('show'));
  connectWS();
  loadData();
}
document.addEventListener('DOMContentLoaded', init);
