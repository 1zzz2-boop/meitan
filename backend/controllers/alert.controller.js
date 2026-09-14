const alertService = require('../services/alert.service');
const auditService = require('../services/audit.service');

const alertController = {
    async getAllAlerts(req, res, next) {
        try {
            res.json(await alertService.getAllAlerts());
        } catch (error) { next(error); }
    },

    async getUnhandledAlerts(req, res, next) {
        try {
            res.json(await alertService.getUnhandledAlerts());
        } catch (error) { next(error); }
    },

    async getUnhandledCount(req, res, next) {
        try {
            res.json({ count: await alertService.getUnhandledCount() });
        } catch (error) { next(error); }
    },

    async handleAlert(req, res, next) {
        try {
            const { alertId, handledBy } = req.body;
            const alert = await alertService.handleAlert(alertId, handledBy);
            if (!alert) return res.status(404).json({ error: 'Alert not found' });
            auditService.log('ALERT_HANDLE', `预警#${alertId} 由 ${handledBy || req.auth.username} 处置`, { req });
            res.json(alert);
        } catch (error) { next(error); }
    },

    async clearAll(req, res, next) {
        try {
            res.json(await alertService.clearAll());
            auditService.log('ALERT_CLEAR', '清空全部预警', { req });
        } catch (error) { next(error); }
    }
};

module.exports = alertController;
