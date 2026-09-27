const { query, queryOne } = require('../config/database');

/**
 * 预警服务（PostgreSQL）
 */
const alertService = {
    // 统一返回的预警字段（含升级状态机相关列）
    SELECT_COLUMNS:
        `id, sensor_id, sensor_name, level, message, value, threshold,
         handled, handler, handled_at, mine_id, raised_count, escalated_at, escalation_note, created_at`,

    async getAllAlerts() {
        return await query(
            `SELECT ${this.SELECT_COLUMNS} FROM alerts ORDER BY created_at DESC`
        );
    },

    async getUnhandledAlerts() {
        return await query(
            `SELECT ${this.SELECT_COLUMNS} FROM alerts WHERE handled = FALSE ORDER BY created_at DESC`
        );
    },

    async getUnhandledCount() {
        const rows = await query(`SELECT COUNT(*)::int AS count FROM alerts WHERE handled = FALSE`);
        return rows[0].count;
    },

    async handleAlert(alertId, handledBy, handleNote) {
        const rows = await query(
            `UPDATE alerts SET handled = TRUE, handler = $2, handled_at = now()
             WHERE id = $1
             RETURNING ${this.SELECT_COLUMNS}`,
            [alertId, handledBy || 'system']
        );
        return rows[0] || null;
    },

    async clearAll() {
        await query(`UPDATE alerts SET handled = TRUE, handler = 'system', handled_at = now() WHERE handled = FALSE`);
        return { success: true };
    },

    async createAlert(data) {
        const rows = await query(
            `INSERT INTO alerts (id, sensor_id, sensor_name, level, message, value, threshold, mine_id, escalated_at)
             VALUES ($1, $2, $3, $4, $5, $6, $7, $8, now())
             RETURNING ${this.SELECT_COLUMNS}`,
            [data.id, data.sensor_id, data.sensor_name, data.level, data.message,
             data.value, data.threshold, data.mine_id || 1]
        );
        return rows[0];
    },

    /**
     * 判断某传感器是否已有未处理的预警（用于模拟器去重）
     */
    async hasOpenAlert(sensorId) {
        const rows = await query(
            `SELECT id FROM alerts WHERE sensor_id = $1 AND handled = FALSE LIMIT 1`, [sensorId]
        );
        return rows.length > 0;
    }
};

module.exports = alertService;
