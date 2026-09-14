const supervisionService = require('../services/supervision.service');
const auditService = require('../services/audit.service');

const supervisionController = {
    async getMines(req, res, next) {
        try {
            res.json(await supervisionService.getMines());
        } catch (error) { next(error); }
    },

    async getOverview(req, res, next) {
        try {
            res.json(await supervisionService.getOverview());
        } catch (error) { next(error); }
    },

    async getDispatches(req, res, next) {
        try {
            res.json(await supervisionService.getDispatches());
        } catch (error) { next(error); }
    },

    async createDispatch(req, res, next) {
        try {
            const dispatch = await supervisionService.createDispatch(req.body);
            auditService.log('DISPATCH_CREATE', JSON.stringify({ title: req.body.title, targetMine: req.body.target_mine }), { req });
            res.status(201).json(dispatch);
        } catch (error) { next(error); }
    },

    async updateDispatchStatus(req, res, next) {
        try {
            const { id, status } = req.body;
            const dispatch = await supervisionService.updateDispatchStatus(id, status);
            if (!dispatch) return res.status(404).json({ error: 'Dispatch not found' });
            auditService.log('DISPATCH_UPDATE', `派单#${id} 状态更新为 ${status}`, { req });
            res.json(dispatch);
        } catch (error) { next(error); }
    }
};

module.exports = supervisionController;
