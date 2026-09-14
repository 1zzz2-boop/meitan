/**
 * 验证码服务（服务端生成/校验，一次性消费）
 * 内存 Map 存储：captchaId -> { code, expiresAt }
 * 避免指纹/随机碰撞，并带过期时间与使用即焚，防止绕过与重放。
 */
const crypto = require('crypto');

const CHARS = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789'; // 去除易混淆字符 0O1IL
const CODE_LEN = 4;
const TTL_MS = 5 * 60 * 1000; // 5 分钟有效
const MAX_SIZE = 10000;       // 防止 Map 无限增长

// captchaId -> { code, expiresAt }
const store = new Map();

function _now() {
    return Date.now();
}

/** 清理过期项（简单惰性清理） */
function _purge() {
    const now = _now();
    for (const [id, item] of store) {
        if (item.expiresAt <= now) store.delete(id);
    }
}

/**
 * 生成验证码
 * @returns {{ captchaId: string, code: string, expiresIn: number }}
 */
function create() {
    _purge();
    // 防止地址华存储过大：先淘汰最旧的一批
    while (store.size >= MAX_SIZE) {
        const oldestKey = store.keys().next().value;
        if (oldestKey === undefined) break;
        store.delete(oldestKey);
    }

    let code = '';
    for (let i = 0; i < CODE_LEN; i++) {
        code += CHARS.charAt(Math.floor(Math.random() * CHARS.length));
    }
    const captchaId = crypto.randomBytes(16).toString('hex');
    store.set(captchaId, { code, expiresAt: _now() + TTL_MS });
    return { captchaId, code, expiresIn: Math.floor(TTL_MS / 1000) };
}

/**
 * 校验并消费验证码
 * 校验成功即删除（一次性），失败也删除该 captcha 防止爆破
 * @param {string} captchaId
 * @param {string} captchaCode
 * @returns {boolean}
 */
function verifyAndConsume(captchaId, captchaCode) {
    if (!captchaId || !captchaCode) return false;
    const item = store.get(captchaId);
    if (item) store.delete(captchaId); // 无论成败都消费，避免同一验证码重放
    if (!item) return false;
    if (item.expiresAt <= _now()) return false;
    return String(item.code).toUpperCase() === String(captchaCode).trim().toUpperCase();
}

/** 清理全部（测试用） */
function clear() {
    store.clear();
}

module.exports = { create, verifyAndConsume, clear };