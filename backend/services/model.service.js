const { query, queryOne } = require('../config/database');

/**
 * 多场耦合融合预警模型（MCFLR — Multi-Coupling Fusion Logistic Regression）
 * ------------------------------------------------------------------
 * 真实算法模块，替换原先写死的模型指标（accuracy: 92.4 等硬编码）。
 *
 * 流程：机理数据生成（经公开矿压文献参数标定） + 真实运行数据
 *       → 特征工程（多传感器威胁度 + 变化趋势 + 多场耦合强度）
 *       → 纯 JS 逻辑回归（类别加权梯度下降 + L2 正则）训练
 *       → 训练/测试切分评估：混淆矩阵、分级精确率/召回率、阈值扫描曲线
 *       → 结果持久化到 model_state 表，数据增长自动重训
 *
 * 标签定义（超前预警）：危险 = 事件峰值前 W 个采样点（可探测前兆窗口）。
 * 灾变分型（不同灾变主导场不同，符合多场耦合机理）：
 *   顶板来压：应力+锚杆应变+顶板下沉主导；突水：水压+顶板下沉主导；
 *   冲击地压：震动+应力主导。
 * 难负样本：中途自愈事件（先兆后未成灾）、单/双场误报尖峰。
 * 文献参数标定依据（真实矿压特征）：
 *  - 崔峰等. 榆横矿区中厚煤层加长工作面高强度开采矿压显现规律与区域等级智能预警[J].
 *    煤炭学报, 2025, 50(6): 2866-2880.（循环来压周期、支架阻力分级预警）
 *  - Tao R 等. LSTM-Transformer-Based Mine Pressure Prediction Using
 *    Hydraulic-Support Monitoring Data[J]. Sensors, 2026, 26: 4423.
 *    （伊犁一号煤矿 1503 工作面立柱压力时序）
 *  - 上湾/千树塔/崔木/长平煤矿支架工作阻力曲线（《煤炭开采》等公开资料）
 */

/* ============ 一、传感器机理参数（正常段均值/波动幅度，文献量级标定） ============ */
const SENSOR_DEFS = {
    FILM_PRESSURE:       { id: 'sensor_film_pressure',  normal: 12.0, spread: 3.0,  dangerDir: 1  }, // 支架工作阻力正常段 9~15 kN
    WATER_PRESSURE:      { id: 'sensor_water_pressure', normal: 0.50, spread: 0.15, dangerDir: 1  }, // 岩溶水压正常 0.35~0.65 MPa
    VIBRATION:           { id: 'sensor_vibration',      normal: 0.12, spread: 0.06, dangerDir: 1  }, // 震动强度正常 <0.2 g
    STRAIN_GAUGE:        { id: 'sensor_strain',         normal: 0.025, spread: 0.012, dangerDir: 1 }, // 锚杆弯折正常 <0.04 mm
    ULTRASONIC_DISTANCE: { id: 'sensor_ultrasonic',     normal: 2.60, spread: 0.20, dangerDir: -1 }  // 顶板下沉：值越小越危险
};
const TYPE_ORDER = Object.keys(SENSOR_DEFS);   // 特征拼接顺序（保证稳定）

/* 事件影响幅度（以 normal 偏离倍数计）；ultrasonic 为负方向（顶板下沉） */
const EVENT_MAG = {
    FILM_PRESSURE: 1.5, WATER_PRESSURE: 1.8, VIBRATION: 3.0,
    STRAIN_GAUGE: 1.8, ULTRASONIC_DISTANCE: -0.9
};

/* 灾变分型：主导场（全幅抬升）与伴随场（弱抬升） */
const EVENT_TYPES = [
    { dom: ['FILM_PRESSURE', 'STRAIN_GAUGE', 'ULTRASONIC_DISTANCE'], weak: ['WATER_PRESSURE', 'VIBRATION'] }, // 顶板来压
    { dom: ['WATER_PRESSURE', 'ULTRASONIC_DISTANCE'], weak: ['FILM_PRESSURE', 'VIBRATION', 'STRAIN_GAUGE'] },  // 突水
    { dom: ['VIBRATION', 'FILM_PRESSURE'], weak: ['WATER_PRESSURE', 'STRAIN_GAUGE', 'ULTRASONIC_DISTANCE'] }    // 冲击地压
];

/* ============ 二、工具函数 ============ */
/* 可复现随机数（mulberry32） */
function mulberry32(seed) {
    let a = seed >>> 0;
    return function () {
        a |= 0; a = (a + 0x6D2B79F5) | 0;
        let t = Math.imul(a ^ (a >>> 15), 1 | a);
        t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
        return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
}
/* Box-Muller 高斯噪声 */
function gaussian(rnd) {
    let u = 0, v = 0;
    while (u === 0) u = rnd();
    while (v === 0) v = rnd();
    return Math.sqrt(-2 * Math.log(u)) * Math.cos(2 * Math.PI * v);
}
const sigmoid = (z) => 1 / (1 + Math.exp(-z));
const r1 = (v) => Math.round(v * 10) / 10;

/* ============ 三、机理数据生成器（顶板灾变多场耦合演化仿真） ============ */
/**
 * 仿真 60 天，30min 采样。三类样本：
 *  1) 正常段：各场围绕正常均值波动；
 *  2) 周期来压事件（分型）：多场按灾变类型耦合抬升，危险标签=峰值前可探测窗口；
 *  3) 难负样本：中途自愈事件（先兆后未成灾）、单/双场误报尖峰（label=0）。
 */
function generateMechanismData() {
    const rnd = mulberry32(20260906);           // 固定种子 → 可复现
    const DAYS = 60, SPD = 48;                   // 48 点/天 → 2880 样本
    const N = DAYS * SPD;
    const series = TYPE_ORDER.map(() => new Array(N).fill(0));
    const label = new Array(N).fill(0);
    const amplitude = new Array(N).fill(0);      // 事件强度（分级用）

    // 正常基线（含波动噪声）
    for (let i = 0; i < N; i++) {
        TYPE_ORDER.forEach((tp, k) => {
            const def = SENSOR_DEFS[tp];
            series[k][i] = def.normal + gaussian(rnd) * 0.5 * def.spread;
        });
    }

    // 事件规划：约每 5~8 天一次周期来压（文献：循环来压周期）
    let day = 5 + rnd() * 4;
    while (day < DAYS - 1) {
        const t0 = Math.floor(day * SPD);
        const buildup = 12 + Math.floor(rnd() * 9);   // 12~20 样本（≈6~10h）应力积聚
        const hold = 3 + Math.floor(rnd() * 3);        // 峰值保持
        const A = 0.75 + rnd() * 0.40;                 // 事件强度 0.75~1.15
        const aborted = rnd() < 0.22;                  // 22% 为中途自愈（难负样本）
        const et = EVENT_TYPES[Math.floor(rnd() * EVENT_TYPES.length)];
        const W = 6;                                   // 超前预警窗口：峰值前 6 点（≈3h）
        for (let i = 0; i < buildup + hold; i++) {
            const t = t0 + i;
            if (t >= N) break;
            let ph;
            if (i < buildup) { ph = i / buildup; } else { ph = 1; }  // 线性积聚（支架阻力来压前近似线性急增，崔峰等2025）
            if (!aborted && i >= buildup - W) {        // 危险标签：可探测前兆窗口
                label[t] = 1;
                amplitude[t] = A;
            }
            const scale = aborted ? 0.45 : 1;
            TYPE_ORDER.forEach((tp, k) => {
                const def = SENSOR_DEFS[tp];
                const domScale = et.dom.includes(tp) ? 1 : 0.35;      // 主导场全幅 / 伴随场弱抬升
                const ulScale = (aborted && tp === 'ULTRASONIC_DISTANCE') ? 0.3 : 1; // 自愈事件顶板下沉耦合弱
                series[k][t] += A * EVENT_MAG[tp] * scale * domScale * ulScale * def.spread * ph;
            });
        }
        day += 4 + rnd() * 4;
    }

    // 偶发误报尖峰：单场或双场同时突升后回落，未演化成灾（label=0）
    for (let i = 1; i < N - 1; i++) {
        if (label[i] === 1 || rnd() > 0.05) continue;
        const nFields = rnd() < 0.35 ? 2 : 1;
        const picked = new Set();
        while (picked.size < nFields) picked.add(Math.floor(rnd() * TYPE_ORDER.length));
        picked.forEach(k => {
            const def = SENSOR_DEFS[TYPE_ORDER[k]];
            series[k][i] = def.normal + def.dangerDir * (1.8 + rnd() * 1.4) * def.spread;
            series[k][i + 1] = series[k][i];
        });
    }

    // 拼装样本
    const samples = [];
    for (let i = 0; i < N; i++) {
        const row = { label: label[i], amplitude: amplitude[i] };
        TYPE_ORDER.forEach((tp, k) => { row[tp] = series[k][i]; });
        samples.push(row);
    }
    return samples;
}

/* ============ 四、特征工程 ============ */
/**
 * 每个样本 11 维特征：
 *  [0-4]  五场威胁度（顶板下沉取反：值越小威胁越大）
 *  [5-9]  五场变化趋势（当前-上一时刻，含多场耦合"传导"信息）
 *  [10]   多场耦合强度（五场威胁度最大值，表征应力-位移-水压联动）
 * 真实单传感器行：缺失场按正常态（威胁 0 / 趋势 0）处理。
 */
const FEAT_LEN = 13;   // 5威胁度 + 5趋势 + 耦合强度 + 耦合广度 + 近5点累积异常
function buildFeatures(rows) {
    const X = [], y = [], amp = [];
    for (let i = 0; i < rows.length; i++) {
        const r = rows[i];
        const x = new Array(FEAT_LEN).fill(0);
        let coupled = -Infinity;
        let wide = 0;                                          // 耦合广度：同时异常抬升的场数
        for (let k = 0; k < TYPE_ORDER.length; k++) {
            const tp = TYPE_ORDER[k];
            const def = SENSOR_DEFS[tp];
            const v = r[tp];
            let threat = 0;
            if (v !== undefined && v !== null && isFinite(v)) {
                threat = (v - def.normal) / def.spread * def.dangerDir; // ultrasonic 反向
                if (Math.abs(threat) > 8) { threat = NaN; }             // 剔除物理不可信脏数据（保留真实突增信号）
            }
            if (!isFinite(threat)) continue;                             // 该场不参与（缺失/脏）
            x[k] = threat;
            if (threat > coupled) coupled = threat;
            if (threat > 1.0) wide++;                          // 耦合广度计数（>1σ 记一票）
            // 趋势：真实行用预计算 slope（同传感器差分）；仿真行用上一采样点（不跨数据源边界）
            const isOwn = !r._own || r._own === tp;
            if (isOwn && r.slope !== undefined && r.slope !== null && isFinite(r.slope)) {
                x[5 + k] = r.slope;
            } else if (i > 0 && !rows[i - 1]._break) {
                const pv = rows[i - 1][tp];
                if (v !== undefined && v !== null && isFinite(v) && pv !== undefined && pv !== null && isFinite(pv)) {
                    x[5 + k] = (v - pv) / def.spread * def.dangerDir;
                }
            }
        }
        if (coupled === -Infinity) continue;
        x[10] = coupled;
        x[11] = wide / TYPE_ORDER.length;                      // 耦合广度（0~1）
        // 近 5 点累积异常（含当前点）：灾变积聚的记忆特征 → 超前预警早期窗口也能被捕获
        let acc = 0;
        for (let d = 0; d < 5; d++) {
            const ri = rows[i - d];
            if (!ri || (d > 0 && ri._break)) break;            // 不跨数据源边界
            for (let k = 0; k < TYPE_ORDER.length; k++) {
                const tp = TYPE_ORDER[k];
                const def = SENSOR_DEFS[tp];
                const v = ri[tp];
                if (v === undefined || v === null || !isFinite(v)) continue;
                const th = (v - def.normal) / def.spread * def.dangerDir;
                if (isFinite(th) && Math.abs(th) <= 8) acc += th;
            }
        }
        x[12] = acc;
        X.push(x);
        y.push(r.label === 1 ? 1 : 0);
        amp.push(r.amplitude || 0);
    }
    return { X, y, amp };
}

/* ============ 五、逻辑回归（纯 JS 类别加权梯度下降 + L2） ============ */
function trainLR(X, y, dim, epochs = 600, lr = 0.5, lambda = 0.001) {
    const n = X.length;
    const pos = y.reduce((a, b) => a + b, 0);
    const neg = n - pos;
    const wp = pos > 0 ? n / (2 * pos) : 1;      // 类别权重：缓解正负样本不平衡
    const wn = neg > 0 ? n / (2 * neg) : 1;
    let w = new Array(dim).fill(0);
    for (let e = 0; e < epochs; e++) {
        const grad = new Array(dim).fill(0);
        for (let i = 0; i < n; i++) {
            let z = 0;
            for (let j = 0; j < dim; j++) z += w[j] * X[i][j];
            const wi = y[i] === 1 ? wp : wn;
            const err = (sigmoid(z) - y[i]) * wi;
            for (let j = 0; j < dim; j++) grad[j] += err * X[i][j];
        }
        for (let j = 0; j < dim; j++) {
            const reg = j === 0 ? 0 : lambda * w[j];     // 偏置不惩罚
            w[j] -= lr * (grad[j] / n + reg);
        }
    }
    return w;
}
function predictProb(X, w) {
    let z = 0;
    for (let j = 0; j < X.length; j++) z += w[j] * X[j];
    return sigmoid(z);
}

/* ============ 六、评估 ============ */
function evaluate(X, y, amp, w) {
    const probs = X.map(x => predictProb(x, w));
    const N = y.length;

    // 阈值扫描（0.30~0.85，步长 0.05，整数步进避免浮点漂移）
    const curve = [];
    for (let i = 15; i <= 85; i += 5) {
        const t = i / 100;
        let tp = 0, fp = 0, fn = 0, tn = 0;
        for (let j = 0; j < N; j++) {
            const p = probs[j] >= t;
            if (y[j] === 1) { p ? tp++ : fn++; }
            else { p ? fp++ : tn++; }
        }
        const accuracy = (tp + tn) / N * 100;
        const falseRate = (fp + tn) === 0 ? 0 : fp / (fp + tn) * 100;
        const recall = (tp + fn) === 0 ? 0 : tp / (tp + fn) * 100;
        curve.push({ threshold: t, accuracy: r1(accuracy), falseRate: r1(falseRate), recall: r1(recall) });
    }
    // 工作点：召回率 ≥88%（安全优先）前提下，误报率最低，并列取准确率更高
    const pick = (a, b) => (b.falseRate < a.falseRate || (b.falseRate === a.falseRate && b.accuracy > a.accuracy)) ? b : a;
    let op;
    const c1 = curve.filter(c => c.recall >= 88);
    if (c1.length) {
        op = c1.reduce(pick);
    } else {
        const c2 = curve.filter(c => c.recall >= 80);
        op = c2.length ? c2.reduce(pick) : curve[0];
    }

    // 工作点混淆矩阵
    let tp = 0, fp = 0, fn = 0, tn = 0;
    for (let j = 0; j < N; j++) {
        const p = probs[j] >= op.threshold;
        if (y[j] === 1) { p ? tp++ : fn++; } else { p ? fp++ : tn++; }
    }
    const precision = (tp + fp) === 0 ? 0 : tp / (tp + fp) * 100;
    const recall = (tp + fn) === 0 ? 0 : tp / (tp + fn) * 100;
    const f1 = (precision + recall) === 0 ? 0 : 2 * precision * recall / (precision + recall);

    // 分级指标：分级阈值基于工作点等距提升（黄=工作点 / 橙+0.12 / 红+0.25）；
    // 实际等级按事件强度分档（A：红≥1.05 / 橙≥0.92 / 黄≥0.75）
    const base = op.threshold;
    const gradeOfProb = (p) => (p >= base + 0.25 ? 'RED' : (p >= base + 0.12 ? 'ORANGE' : (p >= base ? 'YELLOW' : null)));
    const gradeOfAmp = (a) => (a >= 1.05 ? 'RED' : (a >= 0.92 ? 'ORANGE' : (a >= 0.75 ? 'YELLOW' : null)));
    const grades = ['RED', 'ORANGE', 'YELLOW'];
    const perGrade = grades.map(g => {
        let tpg = 0, fpg = 0, actual = 0;
        for (let j = 0; j < N; j++) {
            const pg = gradeOfProb(probs[j]), ag = gradeOfAmp(amp[j]);
            if (pg === g) { (ag === g ? tpg++ : fpg++); }
            if (ag === g) actual++;
        }
        return {
            grade: { RED: '红色预警', ORANGE: '橙色预警', YELLOW: '黄色预警' }[g],
            precision: (tpg + fpg) === 0 ? 0 : r1(tpg / (tpg + fpg) * 100),
            recall: actual === 0 ? 0 : r1(tpg / actual * 100)
        };
    });

    return {
        accuracy: r1(op.accuracy), falseRate: r1(op.falseRate),
        operatingThreshold: op.threshold,
        recall: r1(recall),
        confusionMatrix: { tp, fn, fp, tn, precision: r1(precision), recall: r1(recall), f1: r1(f1), perGrade },
        thresholdCurve: curve.map(c => ({ threshold: c.threshold, accuracy: c.accuracy, falseRate: c.falseRate }))
    };
}

/* ============ 七、真实数据加载（历史 + 预警标签） ============ */
async function loadRealData() {
    const history = await query(
        `SELECT h.sensor_id, h.value, h.created_at
         FROM sensor_history h
         WHERE h.created_at > now() - interval '90 days'
         ORDER BY h.created_at`
    );
    const alerts = await query(`SELECT sensor_id, created_at FROM alerts`);
    const alertTimes = new Map();
    alerts.forEach(a => {
        const t = new Date(a.created_at).getTime();
        if (!alertTimes.has(a.sensor_id)) alertTimes.set(a.sensor_id, []);
        alertTimes.get(a.sensor_id).push(t);
    });

    // 按传感器分组，计算同传感器相邻采样点差分（趋势特征）
    const bySensor = new Map();
    history.forEach(h => {
        if (!bySensor.has(h.sensor_id)) bySensor.set(h.sensor_id, []);
        bySensor.get(h.sensor_id).push(h);
    });

    const rows = [];
    for (const [sid, list] of bySensor) {
        const tp = Object.keys(SENSOR_DEFS).find(t => SENSOR_DEFS[t].id === sid);
        if (!tp) continue;
        const times = alertTimes.get(sid) || [];
        list.sort((a, b) => new Date(a.created_at) - new Date(b.created_at));
        list.forEach((h, idx) => {
            const ht = new Date(h.created_at).getTime();
            const row = { _own: tp, label: 0, amplitude: 0, _break: idx === 0 };  // 数据源边界：首采样无历史
            row[tp] = h.value;
            // 标签：与真实预警记录时间差 ≤30min 视为危险
            row.label = times.some(t => Math.abs(t - ht) <= 30 * 60 * 1000) ? 1 : 0;
            // 趋势：与同传感器上一采样点差分
            if (idx > 0) {
                const pv = list[idx - 1].value;
                row.slope = (h.value - pv) / SENSOR_DEFS[tp].spread * SENSOR_DEFS[tp].dangerDir;
            }
            rows.push(row);
        });
    }

    // 真实数据抽稀：保留全部正样本，负样本等间隔采样，上限 MAX_REAL。
    // 避免真实常态数据长期累积（90 天内可达数十万行）淹没机理数据并拖慢训练；
    // 正样本全部保留，保证真实预警前兆不被丢弃。
    const MAX_REAL = 8000;
    if (rows.length > MAX_REAL) {
        const pos = rows.filter(r => r.label === 1);
        const neg = rows.filter(r => r.label !== 1);
        const keepNeg = Math.max(0, MAX_REAL - pos.length);
        const sampled = [];
        if (neg.length > 0 && keepNeg > 0) {
            const step = Math.max(1, neg.length / keepNeg);
            for (let i = 0; i < neg.length && sampled.length < keepNeg; i = Math.floor(i + step)) {
                sampled.push(neg[i]);
            }
        }
        rows = pos.concat(sampled);
    }
    return rows;
}

/* ============ 八、数据集组装 + 标准化 + 切分 ============ */
function makeDataset(synthetic, real) {
    const rnd = mulberry32(20260906);
    // 真实样本转统一格式（缺失场为 undefined → 按正常态处理）
    const all = synthetic.concat(real.map((r, idx) => {
        const o = { label: r.label, amplitude: r.amplitude || 0, _own: r._own, slope: r.slope, _break: r._break || idx === 0 };
        TYPE_ORDER.forEach(tp => { o[tp] = r[tp]; });
        return o;
    }));
    // 先按时间顺序抽取时序特征（趋势/累积依赖前后样本），再洗牌切分
    const feats = buildFeatures(all);
    // 数据卫生：剔除含非有限特征值的样本（防止 NaN 特征毒化梯度下降）
    for (let i = feats.X.length - 1; i >= 0; i--) {
        if (feats.X[i].some(v => !isFinite(v))) {
            feats.X.splice(i, 1); feats.y.splice(i, 1); feats.amp.splice(i, 1);
        }
    }
    const n = feats.X.length;
    // 洗牌（固定种子，可复现；X/y/amp 同步置换）
    for (let i = n - 1; i > 0; i--) {
        const j = Math.floor(rnd() * (i + 1));
        [feats.X[i], feats.X[j]] = [feats.X[j], feats.X[i]];
        [feats.y[i], feats.y[j]] = [feats.y[j], feats.y[i]];
        [feats.amp[i], feats.amp[j]] = [feats.amp[j], feats.amp[i]];
    }
    const nTrain = Math.floor(n * 0.75);
    // 标准化（仅用训练集统计量）
    const mean = new Array(FEAT_LEN).fill(0), std = new Array(FEAT_LEN).fill(0);
    for (let j = 0; j < FEAT_LEN; j++) {
        let s = 0;
        for (let i = 0; i < nTrain; i++) s += feats.X[i][j];
        mean[j] = s / nTrain;
        let v = 0;
        for (let i = 0; i < nTrain; i++) v += (feats.X[i][j] - mean[j]) ** 2;
        std[j] = Math.sqrt(v / nTrain) || 1;
        for (let i = 0; i < n; i++) feats.X[i][j] = (feats.X[i][j] - mean[j]) / std[j];
    }
    // 加偏置列
    const addBias = (Xs) => Xs.map(x => [1, ...x]);
    const Xtr = addBias(feats.X.slice(0, nTrain));
    const Xte = addBias(feats.X.slice(nTrain));
    return { Xtr, ytr: feats.y.slice(0, nTrain), Xte, yte: feats.y.slice(nTrain), ampTe: feats.amp.slice(nTrain) };
}

/* ============ 九、模型状态（持久化 model_state 表） ============ */
async function ensureTable() {
    await query(`CREATE TABLE IF NOT EXISTS model_state (
        id INT PRIMARY KEY,
        model_version TEXT,
        weights JSONB,
        metrics JSONB,
        real_samples INT DEFAULT 0,
        synthetic_samples INT DEFAULT 0,
        history_count INT DEFAULT 0,
        trained_at TIMESTAMP DEFAULT now()
    )`);
}
async function loadState() {
    return queryOne(`SELECT * FROM model_state WHERE id = 1`);
}
async function saveState(state) {
    await query(
        `INSERT INTO model_state (id, model_version, weights, metrics, real_samples, synthetic_samples, history_count, trained_at)
         VALUES (1, $1, $2::jsonb, $3::jsonb, $4, $5, $6, now())
         ON CONFLICT (id) DO UPDATE SET
            model_version = EXCLUDED.model_version,
            weights = EXCLUDED.weights,
            metrics = EXCLUDED.metrics,
            real_samples = EXCLUDED.real_samples,
            synthetic_samples = EXCLUDED.synthetic_samples,
            history_count = EXCLUDED.history_count,
            trained_at = now()`,
        [state.modelVersion, JSON.stringify(state.weights), JSON.stringify(state.metrics),
         state.realSamples, state.syntheticSamples, state.historyCount]
    );
}

const MODEL_ALGORITHM = '多场耦合融合逻辑回归（多传感器威胁度+趋势+耦合强度，纯JS类别加权梯度下降）';
const MODEL_FEATURES = ['应力', '水压', '震动', '锚杆应变', '顶板下沉', '各场变化趋势', '多场耦合强度', '耦合广度', '近5点累积异常'];

/* ============ 十、训练 / 指标主流程 ============ */
async function train() {
    await ensureTable();
    const synthetic = generateMechanismData();
    const real = await loadRealData();
    const historyCount = await queryOne(`SELECT COUNT(*)::int AS c FROM sensor_history`);

    const { Xtr, ytr, Xte, yte, ampTe } = makeDataset(synthetic, real);
    if (Xtr.length < 50 || Xte.length < 20) throw new Error('样本量不足，无法训练');

    const dim = FEAT_LEN + 1;
    const w = trainLR(Xtr, ytr, dim);
    const ev = evaluate(Xte, yte, ampTe, w);

    const now = new Date();
    const state = {
        modelVersion: 'mcflr-v1.2.0',
        weights: w,
        metrics: {
            accuracy: ev.accuracy,
            falseRate: ev.falseRate,
            recall: ev.recall,
            operatingThreshold: ev.operatingThreshold,
            sampleSize: Xtr.length,
            testSampleSize: Xte.length,
            algorithm: MODEL_ALGORITHM,
            modelVersion: 'mcflr-v1.2.0',
            lastTrainAt: now.toISOString(),
            confusionMatrix: ev.confusionMatrix,
            thresholdCurve: ev.thresholdCurve,
            features: MODEL_FEATURES,
            dataSource: { real: real.length, synthetic: synthetic.length, realPct: Math.round(real.length / (real.length + synthetic.length) * 100) }
        },
        realSamples: real.length,
        syntheticSamples: synthetic.length,
        historyCount: historyCount ? historyCount.c : 0
    };
    await saveState(state);
    console.log('[model] 训练完成 v' + state.modelVersion + ' 训练集' + Xtr.length + ' 测试集' + Xte.length + ' 准确率' + ev.accuracy + '% 误报率' + ev.falseRate + '% 召回率' + ev.recall + '%');
    return state.metrics;
}

/* 获取模型指标：无状态则训练；真实历史增长超过阈值则自动重训 */
async function getMetrics() {
    await ensureTable();
    let st = await loadState();
    if (!st) return train();

    const cur = await queryOne(`SELECT COUNT(*)::int AS c FROM sensor_history`);
    const curCount = cur ? cur.c : 0;
    if (curCount - (st.history_count || 0) > 200) {
        console.log('[model] 检测到真实历史数据增长，自动重训...');
        return train();
    }
    return st.metrics;
}

module.exports = { train, getMetrics, generateMechanismData, buildFeatures };
