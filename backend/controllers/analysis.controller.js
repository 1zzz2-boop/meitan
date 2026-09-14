const analysisService = require('../services/analysis.service');
const auditService = require('../services/audit.service');
const modelService = require('../services/model.service');

const analysisController = {
    async getTrend(req, res, next) {
        try {
            const hours = parseInt(req.query.hours) || 24;
            res.json(await analysisService.getTrend(hours));
        } catch (error) { next(error); }
    },

    async getThreat(req, res, next) {
        try {
            res.json(await analysisService.getThreat());
        } catch (error) { next(error); }
    },

    async getStats(req, res, next) {
        try {
            res.json(await analysisService.getStats());
        } catch (error) { next(error); }
    },

    async getModelMetrics(req, res, next) {
        try {
            res.json(await analysisService.getModelMetrics());
        } catch (error) { next(error); }
    },

    async retrainModel(req, res, next) {
        try {
            const metrics = await modelService.train();
            auditService.log('MODEL_RETRAIN', `模型重训完成 v${metrics.modelVersion}，准确率 ${metrics.accuracy}%`, { req });
            res.json(metrics);
        } catch (error) { next(error); }
    },

    async getReports(req, res, next) {
        try {
            res.json(await analysisService.getReports());
        } catch (error) { next(error); }
    },

    async createReport(req, res, next) {
        try {
            const report = await analysisService.createReport(req.body);
            auditService.log('REPORT_CREATE', `生成报表：${req.body.title || req.body.report_title || ''}`, { req });
            res.status(201).json(report);
        } catch (error) { next(error); }
    }
};

module.exports = analysisController;
