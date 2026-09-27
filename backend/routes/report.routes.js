const express = require('express');
const router = express.Router();
const reportController = require('../controllers/report.controller');
const { authorize } = require('../middleware/auth');

router.get('/templates', reportController.getTemplates);
// 生成报表：仅智库端（专家分析）
router.post('/generate', authorize('thinktank'), reportController.generate);
router.get('/reports', reportController.getReports);
// 导出报表（csv / xlsx）：智库端/监管端可读导出
router.get('/:id/download', authorize('thinktank', 'supervision'), reportController.download);

module.exports = router;