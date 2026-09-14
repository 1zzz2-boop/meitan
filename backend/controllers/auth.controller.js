const authService = require('../services/auth.service');
const captchaService = require('../services/captcha.service');
const auditService = require('../services/audit.service');
const rateLimit = require('../utils/rate-limit');

/** 取客户端 IP（兼容反向代理） */
function clientIp(req) {
    const fwd = req.headers['x-forwarded-for'];
    if (fwd) return String(fwd).split(',')[0].trim();
    return req.ip || req.socket && req.socket.remoteAddress || 'unknown';
}

const authController = {
    /** 获取图形验证码（服务端生成），限频防刷 */
    async captcha(req, res, next) {
        try {
            const rl = await rateLimit.check('captcha:' + clientIp(req), { limit: 30, windowSec: 60 });
            if (!rl.allowed) {
                return res.status(429).json({ error: 'Too Many Requests', message: `验证码获取过于频繁，请 ${rl.retryAfterSec} 秒后再试` });
            }
            res.json(captchaService.create());
        } catch (error) {
            next(error);
        }
    },

    async login(req, res, next) {
        try {
            const { username, password, captchaId, captchaCode } = req.body;
            if (!username || !password) {
                return res.status(400).json({ error: 'Bad Request', message: '用户名和密码不能为空' });
            }
            if (!captchaId || !captchaCode) {
                return res.status(400).json({ error: 'Bad Request', message: '请输入验证码' });
            }
            // 防爆破：同一账号 5 次/分钟 + 同一 IP 20 次/分钟（双因子限流）
            const ip = clientIp(req);
            const rlAccount = await rateLimit.check('login:' + String(username).toLowerCase(), { limit: 5, windowSec: 60 });
            if (!rlAccount.allowed) {
                auditService.log('LOGIN_LOCKED', `${username} 因尝试次数过多被短暂锁定`, { req });
                return res.status(429).json({ error: 'Too Many Requests', message: `账号尝试过于频繁，请 ${rlAccount.retryAfterSec} 秒后再试` });
            }
            const rlIp = await rateLimit.check('loginip:' + ip, { limit: 20, windowSec: 60 });
            if (!rlIp.allowed) {
                auditService.log('LOGIN_LOCKED', `IP ${ip} 登录尝试过于频繁`, { req });
                return res.status(429).json({ error: 'Too Many Requests', message: `尝试过于频繁，请 ${rlIp.retryAfterSec} 秒后再试` });
            }
            const result = await authService.login(username, password, captchaId, captchaCode);
            if (!result.ok) {
                auditService.log('LOGIN_FAIL', `${username} 登录失败：${result.message}`, { req });
                // 验证码错误 / 账号密码错误统一 401，通过 message 区分，调用方均需重新获取验证码
                return res.status(401).json({ error: 'Unauthorized', message: result.message });
            }
            // 登录成功，释放该账号与 IP 的失败计数
            await rateLimit.reset('login:' + String(username).toLowerCase());
            await rateLimit.reset('loginip:' + ip);
            auditService.log('LOGIN_SUCCESS', `${username}（${result.user.endName || result.user.role}）登录成功`, { req });
            res.json(result);
        } catch (error) {
            next(error);
        }
    },

    async changePassword(req, res, next) {
        try {
            const { username, oldPassword, newPassword } = req.body;
            const result = await authService.changePassword(username, oldPassword, newPassword);
            if (result.success) {
                auditService.log('CHANGE_PASSWORD', `${username} 修改了密码`, { req });
            }
            // 统一返回 200 + success 标志，便于鸿蒙端直接读取中文提示
            res.json(result);
        } catch (error) {
            next(error);
        }
    },

    async register(req, res, next) {
        try {
            const { username, password, role, display_name } = req.body;
            const result = await authService.register(username, password, role, display_name);
            if (!result.ok) {
                auditService.log('REGISTER_FAIL', `注册失败：${result.message}`, { req });
                return res.status(409).json({ error: 'Conflict', message: result.message });
            }
            auditService.log('REGISTER', `${username} 注册为 ${result.user.endName || result.user.role}`, { req });
            res.status(201).json(result);
        } catch (error) {
            next(error);
        }
    }
};

module.exports = authController;