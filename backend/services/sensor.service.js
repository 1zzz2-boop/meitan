const { query, queryOne } = require('../config/database');

/**
 * 预警阈值判定（与移动端 IoTDeviceService 逻辑一致）
 * - ULTRASONIC_DISTANCE（超声波测距/顶板下沉）：值越小越危险，value < threshold 预警
 * - 其余传感器：value > threshold 预警
 */
function isOverThreshold(sensor) {
    if (sensor.threshold === null || sensor.threshold === undefined) return false;
    // PG numeric 由 node-postgres 返回为字符串，需转数值再比较，避免字典序错误
    const value = Number(sensor.value);
    const threshold = Number(sensor.threshold);
    if (Number.isNaN(value) || Number.isNaN(threshold)) return false;
    if (sensor.type === 'ULTRASONIC_DISTANCE') return value < threshold;
    return value > threshold;
}

function alertLevelOf(sensor) {
    if (!isOverThreshold(sensor)) return null;
    const ratio = Math.abs(sensor.value - sensor.threshold) / sensor.threshold;
    if (ratio > 0.5) return 'RED';
    if (ratio > 0.3) return 'ORANGE';
    return 'YELLOW';
}

/**
 * 传感器服务（PostgreSQL）
 */
const sensorService = {
    async getAllSensors() {
        const rows = await query(
            `SELECT id, type, name, unit, threshold, value, status, description, mine_id, updated_at
             FROM sensors ORDER BY id`
        );
        return rows.map(s => ({ ...s, isWarning: isOverThreshold(s) }));
    },

    async getSensorById(id) {
        const s = await queryOne(
            `SELECT id, type, name, unit, threshold, value, status, description, mine_id, updated_at
             FROM sensors WHERE id = $1`, [id]
        );
        if (!s) return null;
        return { ...s, isWarning: isOverThreshold(s) };
    },

    async getSensorsByType(type) {
        const rows = await query(
            `SELECT id, type, name, unit, threshold, value, status, description, mine_id, updated_at
             FROM sensors WHERE type = $1 ORDER BY id`, [type]
        );
        return rows.map(s => ({ ...s, isWarning: isOverThreshold(s) }));
    },

    async updateSensorData(sensorId, value) {
        const rows = await query(
            `UPDATE sensors SET value = $2, updated_at = now() WHERE id = $1
             RETURNING id, type, name, unit, threshold, value, status, description, mine_id, updated_at`,
            [sensorId, value]
        );
        if (!rows.length) return null;
        const s = rows[0];
        return { ...s, isWarning: isOverThreshold(s) };
    },

    async getStats() {
        const rows = await query(`SELECT id, type, threshold, value, status FROM sensors`);
        const sensors = rows.map(s => ({ ...s, isWarning: isOverThreshold(s) }));
        return {
            total: sensors.length,
            online: sensors.filter(s => s.status === 'ONLINE').length,
            warning: sensors.filter(s => s.isWarning).length,
            offline: sensors.filter(s => s.status !== 'ONLINE').length
        };
    },

    async getThresholds() {
        const rows = await query(`SELECT key_name, name, value, unit, description FROM threshold_config ORDER BY key_name`);
        return rows;
    },

    async updateThreshold(keyName, value) {
        const rows = await query(
            `UPDATE threshold_config SET value = $2 WHERE key_name = $1
             RETURNING key_name, name, value, unit, description`,
            [keyName, value]
        );
        if (!rows.length) return null;
        // 同步更新对应传感器的阈值字段（水压/顶板下沉/震动）
        const map = { water_pressure: 'sensor_water_pressure', roof_sink: 'sensor_ultrasonic', vibration: 'sensor_vibration' };
        if (map[keyName]) {
            await query(`UPDATE sensors SET threshold = $2 WHERE id = $1`, [map[keyName], value]);
        }
        return rows[0];
    },

    /**
     * 历史趋势查询（P0-历史趋势分析，P2-3.7 兼容归档）
     * 按 interval(minute/hour/day) 聚合指定时间窗内的平均/最大/最小/样本数。
     * 超过 ARCHIVE_DAYS 天的明细已被聚合进 sensor_history_archive；
     * 这里把「近期明细聚合」与「归档桶」UNION，保证归档后趋势仍可读。
     * @param {string} id 传感器 ID
     * @param {object} opts { from?:ISO, to?:ISO, interval?:'minute'|'hour'|'day' }
     */
    async getHistory(id, opts = {}) {
        const interval = ['minute', 'hour', 'day'].includes(opts.interval) ? opts.interval : 'minute';
        const from = opts.from;
        const to = opts.to;

        // 归档只冗余 hour/day 粒度；minute 粒度（近实时查看）无归档，仅查明细表
        const archiveDim = { hour: 'hour', day: 'day' }[interval];

        // 归档阈值：ARCHIVE_DAYS 天之前的数据记为「旧数据」，命中归档表
        const archiveDays = parseInt(process.env.ARCHIVE_DAYS) || 7;
        const cutoff = new Date(Date.now() - archiveDays * 24 * 3600 * 1000).toISOString();

        // 明细表侧：聚合时间窗内数据
        const params = [];
        let histWhere = `sensor_id = $${params.length + 1}`;
        params.push(id);
        if (from) { params.push(from); histWhere += ` AND created_at >= $${params.length}`; }
        if (to) { params.push(to); histWhere += ` AND created_at <= $${params.length}`; }
        const histAgg = `
            SELECT date_trunc('${interval}', created_at) AS ts,
                   round(avg(value)::numeric, 4) AS avg,
                   round(min(value)::numeric, 4) AS min,
                   round(max(value)::numeric, 4) AS max,
                   count(*) AS samples
            FROM sensor_history WHERE ${histWhere}
            GROUP BY 1`;

        // 归档表侧：读取已聚合的旧数据桶（仅当区间起点早于 cutoff 才可能有命中）
        // archiveDim 来自白名单 {hour,day}，可直接内联；各子查询参数号独立递增。
        let archivePart = '';
        if (archiveDim) {
            let aw = `dim = '${archiveDim}' AND sensor_id = $${params.length + 1}`;
            params.push(id);
            aw += ` AND bucket_start < $${params.length + 1}`;
            params.push(cutoff);
            if (from) { params.push(from); aw += ` AND bucket_start >= $${params.length}`; }
            if (to) { params.push(to); aw += ` AND bucket_start <= $${params.length}`; }
            archivePart = `
                UNION ALL
                SELECT bucket_start AS ts, avg, min, max, samples::int AS samples
                FROM sensor_history_archive WHERE ${aw}`;
        }

        const sql = `
            SELECT ts,
                   round(avg(avg)::numeric, 4) AS avg,
                   round(min(min)::numeric, 4) AS min,
                   round(max(max)::numeric, 4) AS max,
                   sum(samples)::int AS samples
            FROM ( ${histAgg} ${archivePart} ) u
            GROUP BY 1 ORDER BY 1 ASC`;

        const rows = await query(sql, params);
        return rows.map(r => ({
            ts: r.ts,
            interval,
            avg: Number(r.avg),
            min: Number(r.min),
            max: Number(r.max),
            samples: Number(r.samples)
        }));
    },

    /**
     * 数据来源溯源（P0-数据来源）、
     * 统计指定时间窗内该传感器历史数据的来源分布（来源+来源地址+样本数），用于前端展示来源溯源。
     * @param {string} id 传感器 ID
     * @param {object} opts { from?:ISO, to?:ISO }
     */
    async getSourceDistribution(id, opts = {}) {
        const { from, to } = opts;
        let where = `sensor_id = $1`;
        const params = [id];
        if (from) {
            params.push(from);
            where += ` AND created_at >= $${params.length}`;
        }
        if (to) {
            params.push(to);
            where += ` AND created_at <= $${params.length}`;
        }
        const rows = await query(
            `SELECT COALESCE(source, 'legacy') AS source,
                    COALESCE(source_addr, '') AS source_addr,
                    count(*) AS samples
             FROM sensor_history
             WHERE ${where}
             GROUP BY source, source_addr
             ORDER BY samples DESC`,
            params
        );
        return rows.map(r => ({
            source: r.source,
            source_addr: r.source_addr,
            samples: Number(r.samples)
        }));
    },

    isOverThreshold,
    alertLevelOf
};

module.exports = sensorService;
