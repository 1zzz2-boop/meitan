const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const morgan = require('morgan');

// Import routes
const healthRoutes = require('../routes/health.routes');
const userRoutes = require('../routes/user.routes');
const sensorRoutes = require('../routes/sensor.routes');
const alertRoutes = require('../routes/alert.routes');
const authRoutes = require('../routes/auth.routes');
const analysisRoutes = require('../routes/analysis.routes');
const supervisionRoutes = require('../routes/supervision.routes');
const reportRoutes = require('../routes/report.routes');
const systemRoutes = require('../routes/system.routes');
const auditRoutes = require('../routes/audit.routes');
const udpRoutes = require('../routes/udp.routes');

// Auth middleware（服务端会话鉴权）
const { authenticate } = require('../middleware/auth');

// Initialize Express app
const app = express();

// Middleware
app.use(helmet());
app.use(cors());
app.use(express.json());
app.use(express.urlencoded({ extended: true }));
app.use(morgan('dev'));

// 静态托管前端目录（企业端/监管端/数据接入监视窗口等），置于 404 兜底之前
app.use(express.static(require('path').join(__dirname, '..', '..', 'qianduanyemian')));

// Basic route
app.get('/', (req, res) => {
    res.json({
        message: '煤矿顶板灾变智能预警与可视化决策系统 · 后端 API',
        version: '2.0.0',
        endpoints: ['/api/auth/login', '/api/sensor', '/api/alert', '/api/analysis', '/api/supervision', '/api/users', '/api/health']
    });
});

// API routes
app.use('/api/health', healthRoutes);
app.use('/api/auth', authRoutes); // 登录/注册/验证码公开
app.use('/api/system', systemRoutes); // 系统信息公开
app.use('/api/udp', udpRoutes);       // VR↔硬件 UDP 转发（公开组，与硬件匿名上报同性质）

// 以下业务路由需登录（令牌鉴权，身份以服务端会话为准）
app.use('/api/users', authenticate, userRoutes);
app.use('/api/sensor', authenticate, sensorRoutes);
app.use('/api/alert', authenticate, alertRoutes);
app.use('/api/analysis', authenticate, analysisRoutes);
app.use('/api/supervision', authenticate, supervisionRoutes);
app.use('/api/report', authenticate, reportRoutes);
app.use('/api/audit', authenticate, auditRoutes);

// 404 handler
app.use((req, res, next) => {
    res.status(404).json({ error: 'Not Found', message: `Cannot ${req.method} ${req.url}` });
});

// Error handling middleware
app.use((err, req, res, next) => {
    console.error(err.stack);
    const statusCode = err.statusCode || 500;
    const message = err.message || 'Internal Server Error';
    res.status(statusCode).json({ error: 'Server Error', message });
});

module.exports = app;
