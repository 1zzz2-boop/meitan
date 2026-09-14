const express = require('express');
const router = express.Router();
const sensorController = require('../controllers/sensor.controller');
const { authorize } = require('../middleware/auth');

router.get('/all', sensorController.getAllSensors);
router.get('/stats', sensorController.getStats);
router.get('/thresholds', sensorController.getThresholds);
router.get('/type/:type', sensorController.getSensorsByType);
router.get('/:id', sensorController.getSensorById);
// 实时数据写入：可被数据采集/模拟器推送，保持登录鉴权
router.post('/update', sensorController.updateSensorData);
// 阈值配置：仅企业端（生产运维）/监管端（审核）可改
router.post('/thresholds', authorize('enterprise', 'supervision'), sensorController.updateThreshold);

module.exports = router;
