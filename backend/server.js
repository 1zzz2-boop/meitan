const app = require('./src/app');
const http = require('http');
const https = require('https');
const fs = require('fs');
const path = require('path');
const { connectToDatabase, closeDatabaseConnection, query } = require('./config/database');
const { WebSocketServer } = require('ws');
const url = require('url');
const wsHub = require('./utils/wsHub');
const simulator = require('./utils/simulator');
const kvStore = require('./utils/kv-store');
const mqttBridge = require('./services/mqtt-bridge');
const udpBridge = require('./services/udp-bridge');
const escalationService = require('./services/escalation.service');
const sensorService = require('./services/sensor.service');
const archiverService = require('./services/archiver.service');
const { runMigrations } = require('./utils/migrate');
require('dotenv').config();

const PORT = process.env.PORT || 3000;
const WS_PORT = parseInt(process.env.WS_PORT) || 8080;

// HTTPS（正式部署时启用）
const HTTPS_ENABLED = process.env.HTTPS_ENABLED === 'true';
const HTTPS_PORT = parseInt(process.env.HTTPS_PORT) || 8443;
const SSL_CERT_FILE = process.env.SSL_CERT_FILE || path.join(__dirname, 'certs', 'cert.pem');
const SSL_KEY_FILE = process.env.SSL_KEY_FILE || path.join(__dirname, 'certs', 'key.pem');
// 是否将明文 HTTP 请求 301 到 HTTPS（仅 HTTPS_ENABLED 时生效）
const REDIRECT_HTTPS = process.env.REDIRECT_HTTPS === 'true';

/** 启动 HTTPS（配置了证书才生效）；返回是否启动成功 */
function startHttps() {
    if (!HTTPS_ENABLED) return false;
    if (!fs.existsSync(SSL_CERT_FILE) || !fs.existsSync(SSL_KEY_FILE)) {
        console.warn(`[HTTPS] 已启用但未找到证书 ${SSL_CERT_FILE} / ${SSL_KEY_FILE}，跳过 HTTPS（可用 scripts/generate-selfsigned-cert 生成自签证书）`);
        return false;
    }
    const sslOpts = {
        key: fs.readFileSync(SSL_KEY_FILE),
        cert: fs.readFileSync(SSL_CERT_FILE)
    };
    const server = https.createServer(sslOpts, app);
    server.listen(HTTPS_PORT, () => {
        console.log(`HTTPS server is running on port ${HTTPS_PORT} (TLS enabled)`);
    });
    server.on('error', (e) => console.error(`[HTTPS] 启动失败: ${e.message}`));
    return true;
}

/** 明文 HTTP → HTTPS 重定向服务（配合反向代理/域名） */
function startRedirect() {
    if (!HTTPS_ENABLED || !REDIRECT_HTTPS) return null;
    const redirectPort = parseInt(process.env.HTTP_REDIRECT_PORT) || PORT;
    const targetPort = HTTPS_PORT;
    const server = http.createServer((req, res) => {
        const host = req.headers.host ? req.headers.host.split(':')[0] : 'localhost';
        res.writeHead(301, { Location: `https://${host}:${targetPort}${req.url}` });
        res.end();
    });
    server.listen(redirectPort, () => {
        console.log(`HTTP redirect (:${redirectPort}) -> HTTPS (:${targetPort}) active`);
    });
    server.on('error', (e) => console.error(`[HTTPS] 重定向服务失败: ${e.message}`));
    return server;
}

/**
 * 启动服务
 */
async function startServer() {
    try {
        // 连接数据库
        try {
            await connectToDatabase();
            console.log('Database connection established');
        } catch (dbError) {
            console.error('数据库连接失败，服务无法正常提供数据：', dbError.message);
            process.exit(1);
        }

        // 轻量字段迁移（幂等；DDL 权限不足时自动跳过）
        await runMigrations();

        // 静态托管前端目录已注入 src/app.js（置于 404 兜底之前）

        // 启动 Express（HTTP）
        app.listen(PORT, () => {
            console.log(`Server is running on port ${PORT}`);
            console.log(`Environment: ${process.env.NODE_ENV}`);
        });

        // 可选 HTTPS + 重定向
        startHttps();
        startRedirect();

        // WebSocket 服务器：向所有客户端广播实时数据（PC 三端 + 鸿蒙）
        const wss = new WebSocketServer({ port: WS_PORT });
        console.log(`WebSocket server is running on port ${WS_PORT}`);

        wsHub.setBroadcast((type, payload) => {
            const msg = JSON.stringify({ type, payload });
            wss.clients.forEach((client) => {
                if (client.readyState === client.OPEN) {
                    client.send(msg);
                }
            });
            // 单对象感知更新时，节流补发一份「全量数组快照」，确保前端数组刷新路径必然触发
            if (!Array.isArray(payload) && payload && payload.id) {
                pushFullSnapshot();
            }
        });

        // 每 ~2 秒补发一次全量传感器快照（俗称全集推送，兼容前端数组刷新路径）
        let lastFullTs = 0;
        function pushFullSnapshot() {
            if (Date.now() - lastFullTs < 2000) return;
            lastFullTs = Date.now();
            // 附上 isWarning，避免全量快照(每2秒)覆盖单对象广播(带 isWarning)导致前端预警态抖动
            query('SELECT * FROM sensors ORDER BY id')
                .then((rows) => {
                    const payload = rows.map((s) => ({ ...s, isWarning: sensorService.isOverThreshold(s) }));
                    const out = JSON.stringify({ type: 'sensor_update', payload });
                    wss.clients.forEach((c) => {
                        if (c.readyState === c.OPEN) c.send(out);
                    });
                })
                .catch((e) => console.warn('[full-snapshot] 失败:', e.message));
        }

        wss.on('connection', (ws, req) => {
            const params = url.parse(req.url, true).query;
            const clientId = params.clientId || params.userId || 'anonymous';
            console.log(`[WS] Client connected: ${clientId}`);

            ws.send(JSON.stringify({
                type: 'connection_status',
                payload: { connected: true, clientId, message: '已连接深地智控实时数据通道' }
            }));

            ws.on('message', (data) => {
                try {
                    const msg = JSON.parse(data.toString());
                    if (msg.type === 'ping') {
                        ws.send(JSON.stringify({ type: 'pong', payload: { t: Date.now() } }));
                    }
                } catch (e) {
                    console.warn('[WS] Invalid message:', e.message);
                }
            });

            ws.on('close', () => console.log(`[WS] Client disconnected: ${clientId}`));
            ws.on('error', (err) => console.error(`[WS] Error for ${clientId}:`, err.message));
        });

        wss.on('error', (err) => {
            console.error('WebSocket server error:', err.message);
        });

        // 启动数据模拟器（为鸿蒙端与 PC 端提供统一实时数据源）
        // SIMULATOR_ENABLED=0/false 时禁用，让实时监测只反映真实硬件数据
        const simEnabled = process.env.SIMULATOR_ENABLED !== '0' && process.env.SIMULATOR_ENABLED !== 'false';
        if (simEnabled) simulator.start();
        else console.log('[simulator] 已禁用（SIMULATOR_ENABLED=0）');

        // 启动 MQTT 桥接（broker 不可达时自动重连，不阻塞后端）
        mqttBridge.start();

        // 启动 UDP 网关（上位机接收硬件端/VR端数据；绑定失败仅告警不阻塞启动）
        udpBridge.start();

        // 启动预警升级状态机（未处置预警按级别自动升级并广播）
        escalationService.start();

        // 启动历史数据归档任务（明细超期聚合入归档表）
        archiverService.start();
    } catch (error) {
        console.error('Failed to start server:', error);
        process.exit(1);
    }
}

process.on('SIGINT', async () => {
    console.log('SIGINT received. Shutting down gracefully...');
    simulator.stop();
    mqttBridge.stop();
    udpBridge.stop();
    escalationService.stop();
    archiverService.stop();
    await kvStore.quit();
    await closeDatabaseConnection();
    process.exit(0);
});

process.on('SIGTERM', async () => {
    console.log('SIGTERM received. Shutting down gracefully...');
    simulator.stop();
    mqttBridge.stop();
    udpBridge.stop();
    escalationService.stop();
    archiverService.stop();
    await kvStore.quit();
    await closeDatabaseConnection();
    process.exit(0);
});

startServer();
