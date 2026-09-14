const app = require('./src/app');
const http = require('http');
const https = require('https');
const fs = require('fs');
const path = require('path');
const { connectToDatabase, closeDatabaseConnection } = require('./config/database');
const { WebSocketServer } = require('ws');
const url = require('url');
const wsHub = require('./utils/wsHub');
const simulator = require('./utils/simulator');
const kvStore = require('./utils/kv-store');
const mqttBridge = require('./services/mqtt-bridge');
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
        });

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
        simulator.start();

        // 启动 MQTT 桥接（broker 不可达时自动重连，不阻塞后端）
        mqttBridge.start();
    } catch (error) {
        console.error('Failed to start server:', error);
        process.exit(1);
    }
}

process.on('SIGINT', async () => {
    console.log('SIGINT received. Shutting down gracefully...');
    simulator.stop();
    mqttBridge.stop();
    await kvStore.quit();
    await closeDatabaseConnection();
    process.exit(0);
});

process.on('SIGTERM', async () => {
    console.log('SIGTERM received. Shutting down gracefully...');
    simulator.stop();
    mqttBridge.stop();
    await kvStore.quit();
    await closeDatabaseConnection();
    process.exit(0);
});

startServer();
