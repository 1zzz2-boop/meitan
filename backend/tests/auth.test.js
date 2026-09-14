/**
 * 安全测试：认证/鉴权中间件 + API 级越权访问
 * 覆盖：无 token→401、无效 token→401、有效 token→放行；角色不匹配→403；企业端调监管接口→403。
 * session.service 为 mock，API 级用例无需数据库。
 */
jest.mock('../services/session.service', () => ({ get: jest.fn() }));
jest.mock('../services/audit.service', () => ({ log: jest.fn() }));

const { authenticate, authorize } = require('../middleware/auth');
const sessionService = require('../services/session.service');

function mockRes() {
  const res = { statusCode: 0, body: null };
  res.status = (code) => { res.statusCode = code; return res; };
  res.json = (body) => { res.body = body; return res; };
  return res;
}

describe('认证/鉴权（middleware/auth）', () => {
  beforeEach(() => jest.clearAllMocks());

  describe('authenticate', () => {
    test('无 token → 401', async () => {
      const res = mockRes();
      const next = jest.fn();
      await authenticate({ headers: {} }, res, next);
      expect(res.statusCode).toBe(401);
      expect(next).not.toHaveBeenCalled();
    });

    test('token 无效（会话不存在）→ 401', async () => {
      sessionService.get.mockResolvedValue(null);
      const res = mockRes();
      const next = jest.fn();
      await authenticate({ headers: { authorization: 'Bearer bad-token' } }, res, next);
      expect(res.statusCode).toBe(401);
      expect(next).not.toHaveBeenCalled();
    });

    test('token 有效 → 挂载 req.auth 并放行', async () => {
      sessionService.get.mockResolvedValue({ token: 't', role: 'enterprise', user: { id: 1 } });
      const req = { headers: { authorization: 'Bearer good-token' } };
      const res = mockRes();
      const next = jest.fn();
      await authenticate(req, res, next);
      expect(next).toHaveBeenCalled();
      expect(req.auth.role).toBe('enterprise');
    });
  });

  describe('authorize（角色鉴权）', () => {
    test('角色匹配 → 放行', () => {
      const next = jest.fn();
      authorize('supervision')({ auth: { role: 'supervision' } }, mockRes(), next);
      expect(next).toHaveBeenCalled();
    });

    test('角色不匹配 → 403 且提示无权限', () => {
      const res = mockRes();
      authorize('supervision')({ auth: { role: 'enterprise' } }, res, jest.fn());
      expect(res.statusCode).toBe(403);
      expect(res.body.message).toContain('无权限');
    });

    test('无认证信息 → 401', () => {
      const res = mockRes();
      authorize('supervision')({}, res, jest.fn());
      expect(res.statusCode).toBe(401);
    });
  });

  describe('API 级越权（集成）', () => {
    test('企业端角色调监管下发接口 → 403', async () => {
      sessionService.get.mockResolvedValue({ token: 't', role: 'enterprise' });
      const app = require('../src/app');
      const res = await require('supertest')(app)
        .post('/api/supervision/dispatches')
        .set('Authorization', 'Bearer t')
        .send({ mineId: 1, level: 'RED', content: '越权测试' });
      expect(res.status).toBe(403);
    });

    test('监管端角色调监管下发接口 → 放行（到达控制器）', async () => {
      sessionService.get.mockResolvedValue({ token: 't', role: 'supervision' });
      const app = require('../src/app');
      const res = await require('supertest')(app)
        .post('/api/supervision/dispatches')
        .set('Authorization', 'Bearer t')
        .send({ mineId: 1, level: 'RED', content: '越权测试' });
      // 鉴权通过后由控制器处理（此处仅验证不再是 403/401）
      expect([200, 400, 404, 500]).toContain(res.status);
    });

    test('未登录访问业务接口 → 401', async () => {
      sessionService.get.mockResolvedValue(null);
      const app = require('../src/app');
      const res = await require('supertest')(app).get('/api/sensor/all');
      expect(res.status).toBe(401);
    });
  });
});
