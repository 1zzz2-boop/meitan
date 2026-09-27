const udpBridge = require('../services/udp-bridge');

/**
 * UDP 转发控制器（VR 虚拟端↔硬件双向交互，经本机后端转发）。
 * 网页/鸿蒙无法直接发 UDP，/api/udp/forward 让前端把帧或控制指令交给后端，
 * 由后端用 dgram 真实转发：mode='frame' 落库广播，mode='cmd' 发送到硬件。
 */
const udpController = {
    /** POST /api/udp/forward  body: { mode, ip, port, sensorId, value, payload } */
    async forward(req, res, next) {
        try {
            const { mode, ip, port, sensorId, value, payload } = req.body || {};
            const m = String(mode || '').toLowerCase();

            if (m === 'frame') {
                // VR 虚拟帧：落库（source='udp'）并广播，模拟硬件上报
                const sid = String(sensorId || '');
                const val = Number(value);
                if (!sid || Number.isNaN(val)) {
                    return res.status(400).json({ error: 'frame 模式需 sensorId 与合法 value' });
                }
                const buf = Buffer.from(JSON.stringify({ sensorId: sid, value: val }));
                const rinfo = { address: req.ip || req.socket?.remoteAddress || 'unknown', port: 0 };
                const ok = await udpBridge.ingest(buf, rinfo);
                return res.json({ ok, mode: 'frame', sensorId: sid, value: val });
            }

            if (m === 'cmd') {
                // 控制指令：后端真实发送 UDP 到指定 ip:port（如硬件 192.168.137.x）
                const targetIp = String(ip || '');
                const p = Number(port);
                const pl = payload !== undefined && payload !== null ? String(payload) : '';
                if (!targetIp || !p || p <= 0 || p > 65535) {
                    return res.status(400).json({ error: 'cmd 模式需合法 ip 与 port(1-65535)' });
                }
                const result = await udpBridge.sendCommand(targetIp, p, pl);
                if (!result.ok) {
                    return res.status(502).json({ error: 'UDP 发送失败', detail: result.error });
                }
                return res.json(result);
            }

            return res.status(400).json({ error: 'mode 必须是 "frame" 或 "cmd"' });
        } catch (error) { next(error); }
    }
};

module.exports = udpController;