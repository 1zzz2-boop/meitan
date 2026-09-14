/**
 * 认证/鉴权中间件
 * authenticate : 解析 `Authorization: Bearer <token>`（也兼容 x-auth-token 请求头），
 *                 从服务端会话取身份，挂到 req.auth。无效/过期 -> 401。
 * authorize(...roles) : 基于会话绑定的角色做接口级鉴权，子集外 -> 403。
 * 所有身份以服务端签发的 token 为准，客户端无法通过改请求头/切 Tab 冒充其他端角色。
 */
const sessionService = require('../services/session.service');

const ROLE_NAMES = {
    enterprise: '企业端',
    thinktank: '智库端',
    supervision: '监管端'
};

async function authenticate(req, res, next) {
    let token = null;
    const authHeader = req.headers.authorization;
    if (authHeader && authHeader.startsWith('Bearer ')) {
        token = authHeader.slice(7).trim();
    } else if (req.headers['x-auth-token']) {
        token = String(req.headers['x-auth-token']);
    }
    const session = await sessionService.get(token);
    if (!session) {
        return res.status(401).json({ error: 'Unauthorized', message: '未登录或登录已过期，请重新登录' });
    }
    req.auth = session;
    req.authToken = token;
    next();
}

function authorize(...roles) {
    return (req, res, next) => {
        if (!req.auth) {
            return res.status(401).json({ error: 'Unauthorized', message: '未登录或登录已过期，请重新登录' });
        }
        if (roles.length === 0 || roles.includes(req.auth.role)) {
            return next();
        }
        const expected = roles.map((r) => ROLE_NAMES[r] || r).join(' / ');
        auditRejectIfAvailable(req, roles, expected);
        return res.status(403).json({ error: 'Forbidden', message: `无权限访问：该接口仅限${expected}调用` });
    };
}

let auditService = null;
function auditRejectIfAvailable(req, roles, expected) {
    if (!auditService) {
        try { auditService = require('../services/audit.service'); } catch (e) { return; }
    }
    auditService.log('FORBIDDEN', `越权尝试：需[${expected}]，当前[${req.auth ? req.auth.role : 'anonym'}] ${req.method} ${req.originalUrl}`, { req });
}

module.exports = { authenticate, authorize };