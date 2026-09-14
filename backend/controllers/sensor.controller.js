const sensorService = require('../services/sensor.service');
const auditService = require('../services/audit.service');
const wsHub = require('../utils/wsHub');

const sensorController = {
    async getAllSensors(req, res, next) {
        try {
            const sensors = await sensorService.getAllSensors();
            res.json(sensors);
        } catch (error) { next(error); }
    },

    async getSensorById(req, res, next) {
        try {
            const sensor = await sensorService.getSensorById(req.params.id);
            if (!sensor) return res.status(404).json({ error: 'Sensor not found' });
            res.json(sensor);
        } catch (error) { next(error); }
    },

    async getSensorsByType(req, res, next) {
        try {
            const sensors = await sensorService.getSensorsByType(req.params.type);
            res.json(sensors);
        } catch (error) { next(error); }
    },

    async updateSensorData(req, res, next) {
        try {
            const { sensorId, value } = req.body;
            const sensor = await sensorService.updateSensorData(sensorId, value);
            if (!sensor) return res.status(404).json({ error: 'Sensor not found' });
            // 手动干预写入后立即广播，实现三端实时联动（大屏交互演示用）
            try {
                const all = await sensorService.getAllSensors();
                wsHub.emit('sensor_update', all);
            } catch (e) { /* 广播失败不影响主流程 */ }
            res.json(sensor);
        } catch (error) { next(error); }
    },

    async getStats(req, res, next) {
        try {
            const stats = await sensorService.getStats();
            res.json(stats);
        } catch (error) { next(error); }
    },

    async getThresholds(req, res, next) {
        try {
            res.json(await sensorService.getThresholds());
        } catch (error) { next(error); }
    },

    async updateThreshold(req, res, next) {
        try {
            const { keyName, value } = req.body;
            const threshold = await sensorService.updateThreshold(keyName, value);
            if (!threshold) return res.status(404).json({ error: 'Threshold not found' });
            auditService.log('THRESHOLD_UPDATE', `阈值 ${keyName} 设置为 ${value}`, { req });
            res.json(threshold);
        } catch (error) { next(error); }
    }
};

module.exports = sensorController;
