const express = require('express');
const router = express.Router();
const auditService = require('../services/audit.service');
const { authorize } = require('../middleware/auth');

/** 查询审计日志（仅监管端） */
router.get('/', authorize('supervision'), async (req, res, next) => {
    try {
        const rows = await auditService.list({ limit: req.query.limit, offset: req.query.offset });
        res.json({ ok: true, rows });
    } catch (error) {
        next(error);
    }
});

/** 查询本人相关审计（任意已登录角色） */
router.get('/me', (req, res, next) => {
    try {
        // 当前会话直接返回最近一次关键操作即可，完整列表走 /api/audit（监管端）
        res.json({ ok: true, username: req.auth.username, role: req.auth.role });
    } catch (error) {
        next(error);
    }
});

module.exports = router;