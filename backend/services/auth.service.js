const userService = require('./user.service');
const captchaService = require('./captcha.service');
const sessionService = require('./session.service');
const { hashPassword, verifyPassword, isHashed } = require('../utils/password');

const ROLE_META = {
    enterprise: { end_name: '企业端 · 生产矿井' },
    thinktank: { end_name: '智库端 · 高校科研机构' },
    supervision: { end_name: '监管端 · 集团/安监部门' }
};

/**
 * 认证服务（三端账号登录）
 */
const authService = {
    /**
     * 登录：先校验验证码，再校验账号密码
     * @param {string} username
     * @param {string} password
     * @param {string} captchaId
     * @param {string} captchaCode
     */
    async login(username, password, captchaId, captchaCode) {
        if (!captchaService.verifyAndConsume(captchaId, captchaCode)) {
            return { ok: false, captchaRejected: true, message: '验证码错误或已过期，请刷新验证码' };
        }
        const user = await userService.findByUsername(username);
        if (!user) return { ok: false, captchaRejected: false, message: '账号不存在' };
        if (!verifyPassword(password, user.password)) return { ok: false, captchaRejected: false, message: '密码错误' };
        // 旧版明文种子账号校验通过后，自动迁移为加盐哈希存储
        if (!isHashed(user.password)) {
            await userService.updateUser(user.id, { password: hashPassword(password) });
        }
        const endName = user.end_name || (ROLE_META[user.role] && ROLE_META[user.role].end_name) || user.end_name;
        const token = await sessionService.issue({
            id: user.id,
            username: user.username,
            role: user.role,
            end_name: endName
        });
        return {
            ok: true,
            token,
            user: {
                id: user.id,
                username: user.username,
                displayName: user.display_name,
                role: user.role,
                endName
            }
        };
    },

    /**
     * 注册三端账号
     */
    async register(username, password, role, displayName) {
        if (!username || !password || !role) {
            return { ok: false, message: '参数不完整' };
        }
        if (String(password).length < 6) {
            return { ok: false, message: '密码至少 6 位' };
        }
        if (!ROLE_META[role]) {
            return { ok: false, message: '无效的端角色' };
        }
        const exist = await userService.findByUsername(username);
        if (exist) {
            return { ok: false, message: '用户名已存在' };
        }
        const user = await userService.createUser({
            username,
            password: hashPassword(password),
            role,
            display_name: displayName || username,
            end_name: ROLE_META[role].end_name
        });
        return {
            ok: true,
            user: {
                id: user.id,
                username: user.username,
                displayName: user.display_name,
                role: user.role,
                endName: user.end_name
            }
        };
    },

    /**
     * 修改密码（校验旧密码，三端共用）
     */
    async changePassword(username, oldPassword, newPassword) {
        if (!username || !oldPassword || !newPassword) {
            return { success: false, message: '参数不完整' };
        }
        const user = await userService.findByUsername(username);
        if (!user) return { success: false, message: '账号不存在' };
        if (user.password !== oldPassword && !verifyPassword(oldPassword, user.password)) {
            return { success: false, message: '原密码错误' };
        }
        if (String(newPassword).length < 6) { return { success: false, message: '新密码至少 6 位' }; }
        await userService.updateUser(user.id, { password: hashPassword(newPassword) });
        // 同步更新"记住密码"所用的登录凭据由鸿蒙端本地管理，此处仅更新数据库
        return { success: true, message: '密码修改成功，请重新登录' };
    }
};

module.exports = authService;
