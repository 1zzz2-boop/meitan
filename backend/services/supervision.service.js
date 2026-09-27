const { query } = require('../config/database');
const sensorService = require('./sensor.service');

/**
 * 监管端 · 远程管控服务
 */
const supervisionService = {
    /**
     * 矿井列表（含在线/预警统计）
     */
    async getMines() {
        const mines = await query(`SELECT id, name, location, owner, status FROM mine ORDER BY id`);
        const sensors = await sensorService.getAllSensors();
        return mines.map(m => {
            const mineSensors = sensors.filter(s => s.mine_id === m.id);
            return {
                ...m,
                sensorTotal: mineSensors.length,
                online: mineSensors.filter(s => s.status === 'ONLINE').length,
                warning: mineSensors.filter(s => s.isWarning).length
            };
        });
    },

    /**
     * 监管总览 KPI
     */
    async getOverview() {
        const mines = await this.getMines();
        const alertRows = await query(`SELECT level, COUNT(*)::int AS cnt FROM alerts WHERE handled = FALSE GROUP BY level`);
        const unhandled = await query(`SELECT COUNT(*)::int AS cnt FROM alerts WHERE handled = FALSE`);
        const dispatch = await query(`SELECT COUNT(*)::int AS cnt FROM dispatch_records WHERE status <> 'DONE'`);
        const alertStat = { RED: 0, ORANGE: 0, YELLOW: 0 };
        alertRows.forEach(r => { if (alertStat[r.level] !== undefined) alertStat[r.level] = r.cnt; });
        return {
            mineCount: mines.length,
            sensorTotal: mines.reduce((a, m) => a + m.sensorTotal, 0),
            unhandledAlert: unhandled[0].cnt,
            activeDispatch: dispatch[0].cnt,
            alertStat,
            mines
        };
    },

    /**
     * 监管端 · 多矿井横向对比看板
     * 每矿聚合：在线率、平均测值、未处置预警数、处置率、预警等级分布
     */
    async getMineComparison() {
        const mines = await this.getMines();

        // 预警按矿井聚合（max_level 按严重度 RED>ORANGE>YELLOW）
        const alertAgg = await query(
            `SELECT mine_id,
                    COUNT(*)::int AS total,
                    COUNT(*) FILTER (WHERE handled = FALSE)::int AS unhandled,
                    COUNT(*) FILTER (WHERE handled = TRUE)::int AS handled,
                    (MAX(CASE level WHEN 'RED' THEN 3 WHEN 'ORANGE' THEN 2 WHEN 'YELLOW' THEN 1 END) FILTER (WHERE handled = FALSE)) AS max_sev
             FROM alerts GROUP BY mine_id`
        );
        const alertMap = {};
        alertAgg.forEach(r => {
            alertMap[r.mine_id] = { ...r, max_level: r.max_sev === 3 ? 'RED' : r.max_sev === 2 ? 'ORANGE' : r.max_sev === 1 ? 'YELLOW' : null };
        });

        const zeroValue = { total: 0, unhandled: 0, handled: 0, max_level: null };

        return mines.map(m => {
            const agg = alertMap[m.id] || zeroValue;
            const handledRate = agg.total > 0 ? agg.handled / agg.total : 1;
            const onlineRate = m.sensorTotal > 0 ? m.online / m.sensorTotal : 0;

            return {
                ...m,
                onlineRate: +onlineRate.toFixed(2),
                handledRate: +handledRate.toFixed(2),
                totalAlerts: agg.total,
                unhandledAlert: agg.unhandled,
                handledAlert: agg.handled,
                maxLevel: agg.max_level
            };
        });
    },

    /**
     * 应急调度记录
     */
    async getDispatches() {
        return await query(`SELECT id, title, level, content, target_mine, status, creator, created_at
                            FROM dispatch_records ORDER BY created_at DESC`);
    },

    async createDispatch(data) {
        const rows = await query(
            `INSERT INTO dispatch_records (title, level, content, target_mine, status, creator)
             VALUES ($1, $2, $3, $4, $5, $6) RETURNING *`,
            [data.title, data.level || 'ORANGE', data.content || '', data.target_mine || '中建筑港青岛西海岸示范矿井',
             data.status || 'PENDING', data.creator || '监管调度员']
        );
        return rows[0];
    },

    async updateDispatchStatus(id, status) {
        const rows = await query(
            `UPDATE dispatch_records SET status = $2 WHERE id = $1 RETURNING *`, [id, status]
        );
        return rows[0] || null;
    }
};

module.exports = supervisionService;
