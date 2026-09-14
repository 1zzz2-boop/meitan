const express = require('express');
const router = express.Router();
const analysisController = require('../controllers/analysis.controller');
const { authorize } = require('../middleware/auth');

router.get('/trend', analysisController.getTrend);
router.get('/threat', analysisController.getThreat);
router.get('/stats', analysisController.getStats);
router.get('/model-metrics', analysisController.getModelMetrics);
// 重新训练预警模型：仅智库端（专家分析）
router.post('/retrain', authorize('thinktank'), analysisController.retrainModel);
router.get('/reports', analysisController.getReports);
// 生成分析报表：仅智库端（专家分析）
router.post('/reports', authorize('thinktank'), analysisController.createReport);

module.exports = router;
