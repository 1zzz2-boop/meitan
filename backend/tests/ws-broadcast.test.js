/**
 * 集成测试：WebSocket 实时广播链路
 * 验证 wsHub.emit → setBroadcast 回调 → 真实 wss.clients.send 的完整链路（与生产代码路径一致）。
 */
const { WebSocketServer, WebSocket } = require('ws');
const wsHub = require('../utils/wsHub');

describe('WebSocket 广播链路（集成）', () => {
  let wss;
  let port;

  beforeEach(async () => {
    wss = new WebSocketServer({ port: 0 });
    await new Promise((resolve) => wss.on('listening', resolve));
    port = wss.address().port;
    wsHub.setBroadcast((type, payload) => {
      const msg = JSON.stringify({ type, payload });
      wss.clients.forEach((c) => { if (c.readyState === c.OPEN) c.send(msg); });
    });
  });

  afterEach(async () => {
    wsHub.setBroadcast(() => {});
    await new Promise((resolve) => wss.close(resolve));
  });

  function connectClient() {
    return new Promise((resolve, reject) => {
      const ws = new WebSocket(`ws://localhost:${port}`);
      ws.once('open', () => resolve(ws));
      ws.once('error', reject);
    });
  }

  function nextMessage(ws) {
    return new Promise((resolve) => ws.once('message', (d) => resolve(JSON.parse(d.toString()))));
  }

  test('wsHub.emit 广播可达真实 WS 客户端', async () => {
    const client = await connectClient();
    const p = nextMessage(client);
    wsHub.emit('sensor_update', [{ id: 'sensor_x', value: 12.5, unit: 'MPa' }]);
    const msg = await p;
    expect(msg.type).toBe('sensor_update');
    expect(msg.payload).toEqual([{ id: 'sensor_x', value: 12.5, unit: 'MPa' }]);
    client.close();
  });

  test('多客户端同时接收广播', async () => {
    const c1 = await connectClient();
    const c2 = await connectClient();
    const m1 = nextMessage(c1);
    const m2 = nextMessage(c2);
    wsHub.emit('alert_update', { level: 'RED', sensorId: 'sensor_x' });
    const [a, b] = await Promise.all([m1, m2]);
    expect(a.type).toBe('alert_update');
    expect(b.type).toBe('alert_update');
    c1.close();
    c2.close();
  });

  test('无客户端连接时 emit 不抛错', async () => {
    expect(() => wsHub.emit('sensor_stats', { total: 1 })).not.toThrow();
  });
});
