const express = require('express');
const router = express.Router();
const userController = require('../controllers/user.controller');
const { authorize } = require('../middleware/auth');

// 用户管理：列表/新增/删除仅监管端（防越权创建管理员账号）
router.get('/', authorize('supervision'), userController.getAllUsers);
router.get('/:id', authorize('supervision'), userController.getUserById);
router.post('/', authorize('supervision'), userController.createUser);
router.delete('/:id', authorize('supervision'), userController.deleteUser);

// 更新：仅本人可改自己的资料，或监管端代改
router.put('/:id', (req, res, next) => {
    if (!req.auth) return res.status(401).json({ error: 'Unauthorized', message: '未登录或登录已过期，请重新登录' });
    const targetId = parseInt(req.params.id, 10);
    if (targetId !== req.auth.userId && req.auth.role !== 'supervision') {
        return res.status(403).json({ error: 'Forbidden', message: '仅可修改自己的资料，或由监管端统一管理' });
    }
    return userController.updateUser(req, res, next);
});

module.exports = router;
