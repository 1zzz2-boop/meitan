const express = require('express');
const router = express.Router();
const { query } = require('../config/database');

/**
 * @route GET /api/system/info
 * @desc 系统版本与运行信息（PC 三端 + 鸿蒙端共用）
 * @access Public
 */
router.get('/info', async (req, res, next) => {
    try {
        let dbVersion = 'Unknown';
        try {
            const rows = await query(`SELECT current_setting('server_version') AS v`);
            dbVersion = rows[0] ? rows[0].v : 'Unknown';
        } catch (e) {
            dbVersion = 'Unavailable';
        }
        res.json({
            name: '煤矿顶板灾变智能预警与可视化决策系统',
            version: '2.0.0',
            build: '2026.09.03',
            platform: process.platform,
            nodeVersion: process.version,
            database: dbVersion,
            apiSdkVersion: 'HarmonyOS 6.0.2(22)',
            serverTime: new Date().toISOString(),
            copyright: '版权所有 © 2026'
        });
    } catch (error) {
        next(error);
    }
});

module.exports = router;