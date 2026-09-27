const express = require('express');
const router = express.Router();
const supervisionController = require('../controllers/supervision.controller');
const { authorize } = require('../middleware/auth');

router.get('/mines', supervisionController.getMines);
router.get('/overview', supervisionController.getOverview);
// 多矿井横向对比：监管端/智库端可读
router.get('/compare', authorize('supervision', 'thinktank'), supervisionController.getMineComparison);
router.get('/dispatches', supervisionController.getDispatches);
// 调度指令：仅监管端可下发/变更
router.post('/dispatches', authorize('supervision'), supervisionController.createDispatch);
router.post('/dispatches/status', authorize('supervision'), supervisionController.updateDispatchStatus);

module.exports = router;
