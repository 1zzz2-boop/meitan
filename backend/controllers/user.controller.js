const userService = require('../services/user.service');
const auditService = require('../services/audit.service');

const userController = {
    async getAllUsers(req, res, next) {
        try {
            const users = await userService.getAllUsers();
            res.json(users);
        } catch (error) { next(error); }
    },

    async getUserById(req, res, next) {
        try {
            const user = await userService.getUserById(parseInt(req.params.id));
            if (!user) return res.status(404).json({ error: 'User not found' });
            res.json(user);
        } catch (error) { next(error); }
    },

    async createUser(req, res, next) {
        try {
            const user = await userService.createUser(req.body);
            auditService.log('USER_CREATE', `新增用户 ${req.body.username} (${req.body.role})`, { req });
            res.status(201).json(user);
        } catch (error) { next(error); }
    },

    async updateUser(req, res, next) {
        try {
            const user = await userService.updateUser(parseInt(req.params.id), req.body);
            if (!user) return res.status(404).json({ error: 'User not found' });
            auditService.log('USER_UPDATE', `更新用户 #${req.params.id}`, { req });
            res.json(user);
        } catch (error) { next(error); }
    },

    async deleteUser(req, res, next) {
        try {
            const deleted = await userService.deleteUser(parseInt(req.params.id));
            if (!deleted) return res.status(404).json({ error: 'User not found' });
            auditService.log('USER_DELETE', `删除用户 #${req.params.id}`, { req });
            res.json({ success: true });
        } catch (error) { next(error); }
    }
};

module.exports = userController;
