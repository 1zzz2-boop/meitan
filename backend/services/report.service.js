/**
 * 智库端 · 报表模板/导出服务（P2-3.6）
 *
 * 预置三类模板：
 *   security   安全监测态势报告：传感器总览 + 预警分布 + 顶板压力统计
 *   device     设备运行报告    ：各传感器 当前值/阈值/状态 运行情况
 *   statistics 统计汇总报告    ：时间窗内各传感器 均值/峰谷/样本数
 *
 * generateReport(template, opts) 经 PostgreSQL 聚合出结构化 JSON，并写入 analysis_reports。
 * toCsv() / toExcel(xlsx) 将该结构化数据渲染为可下载字节流。
 */
const { query, queryOne } = require('../config/database');
const sensorService = require('./sensor.service');

/** 模板元信息注册表 */
const TEMPLATES = {
    security: {
        key: 'security',
        name: '安全监测态势报告',
        desc: '传感器总览、预警级别分布、顶板压力实时统计'
    },
    device: {
        key: 'device',
        name: '设备运行报告',
        desc: '各传感器当前值、阈值、运行状态'
    },
    statistics: {
        key: 'statistics',
        name: '统计汇总报告',
        desc: '时间窗内各传感器均值、峰谷、样本数'
    }
};

/** 默认时间窗：最近 24 小时 */
function defaultRange() {
    const to = new Date();
    const from = new Date(Date.now() - 24 * 3600 * 1000);
    return { from: from.toISOString(), to: to.toISOString() };
}

function parseBool(v) {
    return v === true || v === 'true' || v === '1' || v === 1;
}

const reportService = {
    TEMPLATES,

    /** 模板列表（含详情） */
    async getTemplates() {
        const mines = await query(`SELECT id, name, location, owner FROM mine ORDER BY id`);
        return {
            templates: Object.values(TEMPLATES),
            mines: mines || []
        };
    },

    /**
     * 按模板生成结构化报表数据并落库。
     * @param {string} template 模板 key
     * @param {object} opts { mineId?, from?, to?, author? }
     * @returns {object} 含结构数据与落库记录
     */
    async generateReport(template, opts = {}) {
        const tpl = TEMPLATES[template];
        if (!tpl) {
            const err = new Error(`未知报表模板: ${template}`);
            err.statusCode = 400;
            throw err;
        }

        const from = opts.from ? new Date(opts.from).toISOString() : defaultRange().from;
        const to = opts.to ? new Date(opts.to).toISOString() : defaultRange().to;

        const sensors = await sensorService.getAllSensors();
        const mineId = opts.mineId ? parseInt(opts.mineId) : null;
        const scopeSql = (prefix) => mineId ? `${prefix} mine_id = ${mineId}` : 'TRUE';

        // mine 名称
        const mine = mineId ? await queryOne(`SELECT name FROM mine WHERE id = $1`, [mineId]) : null;
        const mineName = mine ? mine.name : '全部矿井';

        // 预警分布（可选 mine 过滤）
        const alertWhere = `created_at BETWEEN $1 AND $2${mineId ? ` AND mine_id = ${mineId}` : ''}`;
        const alertRows = await query(
            `SELECT level, handled, count(*)::int AS cnt
             FROM alerts WHERE ${alertWhere} GROUP BY level, handled`,
            [from, to]
        );
        const byLevel = { YELLOW: 0, ORANGE: 0, RED: 0 };
        let alertTotal = 0;
        let unhandled = 0;
        (alertRows || []).forEach(r => {
            byLevel[r.level] = (byLevel[r.level] || 0) + r.cnt;
            alertTotal += r.cnt;
            if (!r.handled) unhandled += r.cnt;
        });

        // 时间窗内各传感器历史聚合（均值/峰谷/样本数）
        const histRows = await query(
            `SELECT sensor_id,
                    round(avg(value)::numeric, 4) AS avg,
                    round(min(value)::numeric, 4) AS min,
                    round(max(value)::numeric, 4) AS max,
                    count(*) AS samples,
                    max(created_at) AS last_at
             FROM sensor_history
             WHERE created_at BETWEEN $1 AND $2 AND ${scopeSql('')}
             GROUP BY sensor_id`,
            [from, to]
        );
        const histMap = {};
        (histRows || []).forEach(r => {
            histMap[r.sensor_id] = {
                avg: Number(r.avg),
                min: Number(r.min),
                max: Number(r.max),
                samples: Number(r.samples),
                lastAt: r.last_at
            };
        });

        // 当前值状态统计
        const overview = {
            sensorCount: sensors.length,
            online: sensors.filter(s => s.status === 'ONLINE').length,
            warning: sensors.filter(s => s.isWarning).length,
            offline: sensors.filter(s => s.status !== 'ONLINE').length
        };

        // 各传感器合并：当前值 + 时间窗统计
        const sensorRows = sensors.map(s => ({
            id: s.id,
            name: s.name,
            type: s.type,
            unit: s.unit || '-',
            value: s.value,
            threshold: s.threshold ?? '-',
            status: s.status,
            isWarning: s.isWarning,
            mine_id: s.mine_id,
            hist: histMap[s.id] || null
        }));

        // 组织结构化数据
        const data = {
            template: tpl.key,
            title: `${tpl.name}（${mineName}）`,
            templateName: tpl.name,
            mineId,
            mineName,
            author: opts.author || '智库端',
            range: { from, to },
            generatedAt: new Date().toISOString(),
            overview,
            alertSummary: { total: alertTotal, unhandled, byLevel },
            sensors: sensorRows
        };

        // 落库 analysis_reports（content 存 JSON）
        const inserted = await queryOne(
            `INSERT INTO analysis_reports (title, author, content) VALUES ($1, $2, $3) RETURNING id, title, author, created_at`,
            [data.title, data.author, JSON.stringify(data)]
        );

        return Object.assign({}, data, {
            reportId: inserted.id,
            createdAt: inserted.created_at
        });
    },

    /** 报表列表 */
    async getReports() {
        const rows = await query(
            `SELECT id, title, author, content, created_at FROM analysis_reports ORDER BY created_at DESC LIMIT 100`
        );
        return rows.map(r => {
            let data = null;
            try { data = JSON.parse(r.content); } catch (e) { /* 旧文本报表 */ }
            return {
                id: r.id,
                title: r.title,
                author: r.author,
                createdAt: r.created_at,
                data
            };
        });
    },

    /** 按 id 取单条报表（含结构化 data） */
    async getReport(id) {
        const r = await queryOne(
            `SELECT id, title, author, content, created_at FROM analysis_reports WHERE id = $1`, [id]
        );
        if (!r) return null;
        let data = null;
        try { data = JSON.parse(r.content); } catch (e) { data = null; }
        return { id: r.id, title: r.title, author: r.author, createdAt: r.created_at, data };
    },

    /**
     * 渲染为 CSV 字节串（按模板生成二维表）。
     */
    toCsv(report) {
        const d = report.data || report;
        const esc = (v) => {
            const s = v === null || v === undefined ? '' : String(v);
            return /[",\n]/.test(s) ? '"' + s.replace(/"/g, '""') + '"' : s;
        };
        const lines = [];
        lines.push(`报表标题,${d.title}`);
        lines.push(`矿井,${d.mineName},生成时间,${d.generatedAt},报告人,${d.author || ''}`);
        lines.push(`时间窗,${d.range && d.range.from}-${d.range && d.range.to}`);
        lines.push('');
        lines.push(`传感器总数,${d.overview.sensorCount},在线,${d.overview.online},预警,${d.overview.warning},离线,${d.overview.offline}`);
        lines.push(`预警合计,${d.alertSummary.total},未处置,${d.alertSummary.unhandled},黄色,${d.alertSummary.byLevel.YELLOW},橙色,${d.alertSummary.byLevel.ORANGE},红色,${d.alertSummary.byLevel.RED}`);
        lines.push('');
        lines.push(['传感器ID', '名称', '类型', '单位', '当前值', '阈值', '状态', '均值(窗口)', '最小(窗口)', '最大(窗口)', '样本数'].map(esc).join(','));
        (d.sensors || []).forEach(s => {
            const h = s.hist || {};
            lines.push([s.id, s.name, s.type, s.unit, s.value, s.threshold, s.status,
                h.avg ?? '', h.min ?? '', h.max ?? '', h.samples ?? ''].map(esc).join(','));
        });
        return '\uFEFF' + lines.join('\r\n');
    },

    /**
     * 渲染为 xlsx 字节 Buffer（exceljs）。
     */
    async toExcel(report) {
        const ExcelJS = require('exceljs');
        const d = report.data || report;
        const wb = new ExcelJS.Workbook();
        const ws = wb.addWorksheet('报表');

        const titleRows = [
            [{ value: d.title, font: { size: 16, bold: true } }],
            [`矿井：${d.mineName}`, `生成时间：${d.generatedAt}`, `报告人：${d.author || ''}`],
            [`时间窗：${d.range && d.range.from} - ${d.range && d.range.to}`],
            [],
            [`传感器总数：${d.overview.sensorCount}`, `在线：${d.overview.online}`, `预警：${d.overview.warning}`, `离线：${d.overview.offline}`],
            [`预警合计：${d.alertSummary.total}`, `未处置：${d.alertSummary.unhandled}`, `黄/橙/红：${d.alertSummary.byLevel.YELLOW}/${d.alertSummary.byLevel.ORANGE}/${d.alertSummary.byLevel.RED}`],
            [],
        ];
        titleRows.forEach(r => ws.addRow(r));

        ws.addRow(['传感器ID', '名称', '类型', '单位', '当前值', '阈值', '状态', '均值(窗口)', '最小(窗口)', '最大(窗口)', '样本数']).font = { bold: true };
        (d.sensors || []).forEach(s => {
            const h = s.hist || {};
            ws.addRow([s.id, s.name, s.type, s.unit, s.value, s.threshold, s.status, h.avg, h.min, h.max, h.samples]);
        });
        ws.columns.forEach(c => { c.width = 16; });
        return await wb.xlsx.writeBuffer();
    }
};

module.exports = reportService;