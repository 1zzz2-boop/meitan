/**
 * 冒烟测试：核心 API 连通（依赖真实数据库）
 * authenticate 打桩放行，验证路由 → 控制器 → 数据库全链路返回 200 且为数组。
 */
jest.mock('../middleware/auth', () => ({
  authenticate: (req, res, next) => {
    req.auth = { token: 'test-token', role: 'supervision', user: { id: 1 } };
    next();
  },
  authorize: (...roles) => (req, res, next) => next()
}));

const request = require('supertest');
const app = require('../src/app');

describe('Sensor API', () => {
  test('GET /api/sensor/all returns 200 with sensor list', async () => {
    const res = await request(app).get('/api/sensor/all');
    expect(res.status).toBe(200);
    expect(Array.isArray(res.body)).toBe(true);
  });
});

describe('Alert API', () => {
  test('GET /api/alert/all returns 200 with alert list', async () => {
    const res = await request(app).get('/api/alert/all');
    expect(res.status).toBe(200);
    expect(Array.isArray(res.body)).toBe(true);
  });
});
