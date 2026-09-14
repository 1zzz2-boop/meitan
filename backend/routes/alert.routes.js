const express = require('express');
const router = express.Router();
const alertController = require('../controllers/alert.controller');
const { authorize } = require('../middleware/auth');

// 预警接口（供 PC 三端与鸿蒙端共用）
router.get('/all', alertController.getAllAlerts);
router.get('/unhandled', alertController.getUnhandledAlerts);
router.get('/unhandled/count', alertController.getUnhandledCount);
// 处置预警：企业端（现场处置）/监管端（监督）可操作
router.post('/handle', authorize('enterprise', 'supervision'), alertController.handleAlert);
router.post('/clear', authorize('enterprise', 'supervision'), alertController.clearAll);

module.exports = router;
