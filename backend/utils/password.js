/**
 * 密码哈希工具（Node 内置 crypto.scrypt，零第三方依赖，跨平台）
 * 存储格式：scrypt$<salt>$<hash>
 * 兼容旧版明文：若存储值不是 scrypt 前缀，则认为是一次性明文，仅用于数据迁移过渡。
 */
const crypto = require('crypto');

const PREFIX = 'scrypt$';
const SALT_LEN = 16;   // 字节，hex 为 32 位
const KEY_LEN = 64;    // 字节，hex 为 128 位

/** 生成加盐哈希 */
function hashPassword(password) {
    const salt = crypto.randomBytes(SALT_LEN).toString('hex');
    const hash = crypto.scryptSync(String(password), salt, KEY_LEN).toString('hex');
    return `${PREFIX}${salt}$${hash}`;
}

/** 校验密码：兼容旧明文（校验成功后应在调用处将其迁移为哈希） */
function verifyPassword(password, stored) {
    if (!stored) return false;
    if (typeof stored !== 'string' || !stored.startsWith(PREFIX)) {
        // 旧版明文（种子数据 123456 等）
        return stored === String(password);
    }
    const parts = stored.split('$');
    if (parts.length !== 3) return false;
    const salt = parts[1];
    const hash = parts[2];
    const calc = crypto.scryptSync(String(password), salt, KEY_LEN).toString('hex');
    return crypto.timingSafeEqual(Buffer.from(hash, 'hex'), Buffer.from(calc, 'hex'));
}

/** 是否为哈希存储（非明文） */
function isHashed(stored) {
    return typeof stored === 'string' && stored.startsWith(PREFIX);
}

module.exports = { hashPassword, verifyPassword, isHashed };