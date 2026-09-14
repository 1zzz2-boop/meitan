const { query, queryOne } = require('../config/database');

/**
 * 预警阈值判定（与移动端 IoTDeviceService 逻辑一致）
 * - ULTRASONIC_DISTANCE（超声波测距/顶板下沉）：值越小越危险，value < threshold 预警
 * - 其余传感器：value > threshold 预警
 */
function isOverThreshold(sensor) {
    if (sensor.threshold === null || sensor.threshold === undefined) return false;
    if (sensor.type === 'ULTRASONIC_DISTANCE') return sensor.value < sensor.threshold;
    return sensor.value > sensor.threshold;
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

    isOverThreshold,
    alertLevelOf
};

module.exports = sensorService;
