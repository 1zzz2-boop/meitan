const reportService = require('../services/report.service');
const auditService = require('../services/audit.service');

const reportController = {
    /** 模板与矿井列表 */
    async getTemplates(req, res, next) {
        try {
            res.json(await reportService.getTemplates());
        } catch (error) { next(error); }
    },

    /** 生成报表（智库端） */
    async generate(req, res, next) {
        try {
            const { template, mineId, from, to } = req.body;
            const report = await reportService.generateReport(template, {
                mineId, from, to,
                author: (req.auth && req.auth.username) || '智库端'
            });
            auditService.log('REPORT_GENERATE', `生成报表[${report.templateName}]：${report.title}`, { req });
            res.status(201).json(report);
        } catch (error) { next(error); }
    },

    /** 报表列表 */
    async getReports(req, res, next) {
        try {
            res.json(await reportService.getReports());
        } catch (error) { next(error); }
    },

    /** 导出报表（csv / xlsx） */
    async download(req, res, next) {
        try {
            const id = parseInt(req.params.id);
            const fmt = (req.query.fmt || 'csv').toLowerCase();
            const report = await reportService.getReport(id);
            if (!report || !report.data) {
                const err = new Error('报表不存在或缺少结构化数据，无法导出');
                err.statusCode = 404;
                throw err;
            }
            if (fmt === 'xlsx') {
                const buf = await reportService.toExcel(report);
                res.setHeader('Content-Type', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
                res.setHeader('Content-Disposition', `attachment; filename="report_${id}.xlsx"`);
                return res.send(Buffer.from(buf));
            }
            if (fmt === 'csv') {
                res.setHeader('Content-Type', 'text/csv; charset=utf-8');
                res.setHeader('Content-Disposition', `attachment; filename="report_${id}.csv"`);
                return res.send(reportService.toCsv(report));
            }
            const err = new Error(`暂不支持的导出格式: ${fmt}（支持 csv / xlsx）`);
            err.statusCode = 400;
            throw err;
        } catch (error) { next(error); }
    }
};

module.exports = reportController;