const { query } = require('../config/database');
const alertService = require('../services/alert.service');
const wsHub = require('./wsHub');

/**
 * 数据模拟器
 * 每 10 秒对非设备类传感器做平滑游走更新，写入数据库并记录历史；
 * 若超阈值则生成预警并广播，实现鸿蒙端 / PC 三端的实时数据互通。
 */

const DEVICE_TYPES = ['LORA_MODULE', 'OLED_DISPLAY'];
const TICK_MS = 10000;
let timer = null;

/**
 * 机理传感器标定（与模型 model.service.js 的 SENSOR_DEFS 保持一致）：
 * 正常段均值 + 波动幅度。模拟器以此为锚做均值回归平滑游走，
 * 避免乘性随机游走（× (1±5%)）在对数空间的负漂移导致数值长期衰减到 0、
 * 与模型标定量纲严重不符（曾导致真实数据特征全为"安全"方向，模型召回率归零）。
 */
const MODEL_CAL = {
    sensor_film_pressure:  { normal: 12.0,  spread: 3.0  }, // 支架工作阻力 kN
    sensor_water_pressure: { normal: 0.50,  spread: 0.15 }, // 岩溶水压 MPa
    sensor_vibration:      { normal: 0.12,  spread: 0.06 }, // 震动强度 g
    sensor_strain:         { normal: 0.025, spread: 0.012 },// 锚杆弯折 mm
    sensor_ultrasonic:     { normal: 2.60,  spread: 0.20 }, // 顶板下沉 m
    sensor_temperature:    { normal: 25.3,  spread: 1.5  }, // 环境温度 ℃
    sensor_humidity:       { normal: 68.2,  spread: 4.0  }, // 环境湿度 %
    sensor_co2:            { normal: 0.04,  spread: 0.005 },// CO2 浓度 %
    sensor_so2:            { normal: 0.001, spread: 0.0003 }// SO2 浓度 %
};

/* 平滑游走状态：id → { vel: 每 tick 漂移速度, phase: 当前趋势段剩余 tick 数, target: 阶段目标速度 } */
const WALK = {};

/** 传感器下一采样值：带惯性/趋势的缓变游走（均值回归锚定标定正常段）
 *  - 速度平滑收敛到目标（惯性），不再每步独立随机跳
 *  - 每 40~130s 随机翻转一次趋势方向/幅度，形成缓升缓降的真实曲线
 *  - 弱均值回归防止长期漂移脱离物理量程 */
function nextValue(s) {
    const cal = MODEL_CAL[s.id];
    let st = WALK[s.id] || (WALK[s.id] = { vel: 0, phase: 0, target: 0 });
    if (!cal) {
        // 无标定传感器：小幅平滑扰动
        if (st.phase <= 0) { st.phase = 4 + Math.floor(Math.random() * 8); st.target = (Math.random() - 0.5) * 0.004; }
        st.phase--;
        st.vel += (st.target - st.vel) * 0.35;
        return Number(Math.max(0, s.value * (1 + st.vel)).toFixed(4));
    }
    const anchor = cal.normal, spread = cal.spread;
    // 新趋势段：设定目标速度与持续时长
    if (st.phase <= 0) {
        st.phase = 4 + Math.floor(Math.random() * 10);          // 每段持续 40~130s
        st.target = (Math.random() - 0.5) * 0.10 * spread;      // 阶段漂移速度
    }
    st.phase--;
    st.vel += (st.target - st.vel) * 0.35;                       // 速度惯性逼近目标
    st.vel += (anchor - s.value) * 0.02;                         // 弱均值回归锚定
    const vcap = 0.06 * spread;
    st.vel = Math.max(-vcap, Math.min(vcap, st.vel));
    const jitter = (Math.random() - 0.5) * 0.02 * spread;        // 极小噪声，保留传感器读数感
    let nv = s.value + st.vel + jitter;
    // 物理量程软边界：normal ± 3.2·spread 内缓行，触边减速反弹
    const lo = Math.max(0, anchor - 3.2 * spread), hi = anchor + 3.2 * spread;
    if (nv < lo) { nv = lo; st.vel = Math.abs(st.vel) * 0.5; }
    if (nv > hi) { nv = hi; st.vel = -Math.abs(st.vel) * 0.5; }
    return Number(Math.max(0, nv).toFixed(4));
}

function isDevice(type) {
    return DEVICE_TYPES.includes(type);
}

function isOverThreshold(s) {
    if (s.threshold === null || s.threshold === undefined) return false;
    if (s.type === 'ULTRASONIC_DISTANCE') return s.value < s.threshold;
    return s.value > s.threshold;
}

function alertLevelOf(s) {
    const ratio = Math.abs(s.value - s.threshold) / s.threshold;
    if (ratio > 0.5) return 'RED';
    if (ratio > 0.3) return 'ORANGE';
    return 'YELLOW';
}

async function tick() {
    try {
        const sensors = await query(`SELECT * FROM sensors`);
        const newAlerts = [];

        for (const s of sensors) {
            if (isDevice(s.type)) continue;
            const nv = nextValue(s);
            s.value = nv;

            await query(`UPDATE sensors SET value = $2, updated_at = now() WHERE id = $1`, [s.id, nv]);
            await query(`INSERT INTO sensor_history (sensor_id, value) VALUES ($1, $2)`, [s.id, nv]);

            if (isOverThreshold(s) && !(await alertService.hasOpenAlert(s.id))) {
                const alert = await alertService.createAlert({
                    id: `alert_${Date.now()}_${s.id}`,
                    sensor_id: s.id,
                    sensor_name: s.name,
                    level: alertLevelOf(s),
                    message: `${s.name}超过预警阈值，当前值 ${nv} ${s.unit || ''}`,
                    value: nv,
                    threshold: s.threshold,
                    mine_id: s.mine_id || 1
                });
                newAlerts.push(alert);
            }
        }

        // 广播最新传感器状态
        const latest = await query(`SELECT * FROM sensors`);
        wsHub.emit('sensor_update', latest.map(x => ({
            ...x,
            isWarning: isOverThreshold(x)
        })));

        // 广播新预警
        for (const a of newAlerts) {
            wsHub.emit('alert_update', a);
        }
    } catch (err) {
        console.error('[Simulator] tick failed:', err.message);
    }
}

function start() {
    if (timer) return;
    console.log(`[Simulator] 数据模拟器已启动（每 ${TICK_MS / 1000}s 更新一次）`);
    timer = setInterval(tick, TICK_MS);
}

function stop() {
    if (timer) { clearInterval(timer); timer = null; }
}

module.exports = { start, stop, tick, nextValue, MODEL_CAL };
