const express = require('express');
const router = express.Router();
const { connectToDatabase } = require('../config/database');

/**
 * @route GET /api/health
 * @desc 健康检查（校验 PostgreSQL 连通性）
 * @access Public
 */
router.get('/', async (req, res) => {
    try {
        await connectToDatabase();
        res.json({
            status: 'OK',
            timestamp: new Date().toISOString(),
            database: 'Connected',
            uptime: process.uptime()
        });
    } catch (error) {
        res.status(503).json({
            status: 'ERROR',
            timestamp: new Date().toISOString(),
            database: 'Disconnected',
            error: error.message,
            uptime: process.uptime()
        });
    }
});

/**
 * @route GET /api/health/detailed
 * @desc 详细健康检查
 * @access Public
 */
router.get('/detailed', (req, res) => {
    res.json({
        status: 'OK',
        timestamp: new Date().toISOString(),
        system: {
            platform: process.platform,
            nodeVersion: process.version,
            memory: process.memoryUsage(),
            uptime: process.uptime()
        },
        environment: process.env.NODE_ENV,
        database: {
            host: process.env.DB_HOST,
            database: process.env.DB_DATABASE,
            user: process.env.DB_USER
        }
    });
});

module.exports = router;
