/**
 * 固定窗口限流器（分布式）
 * - 配置 REDIS_URL 时基于 Redis INCR+TTL 计数（多实例共享，防分布式爆破）。
 * - 无 Redis 时回退进程内固定窗口（单实例）。
 * 用于登录 / 验证码等高频或可爆破接口。
 */
const kv = require('./kv-store');

/**
 * 尝试通过限流
 * @param {string} key  限流标识（建议 ip / ip+username）
 * @param {object} opts { limit, windowSec }
 * @returns {{ allowed: boolean, retryAfterSec: number, remaining: number }}
 */
async function check(key, opts = {}) {
    const limit = opts.limit || 5;
    const windowSec = opts.windowSec || 60;
    const count = await kv.incrWithTtl(key, windowSec);
    if (count > limit) {
        return { allowed: false, retryAfterSec: await kv.ttlSeconds(key), remaining: 0 };
    }
    return { allowed: true, retryAfterSec: 0, remaining: Math.max(0, limit - count) };
}

/** 成功登录后释放限流 */
async function reset(key) {
    await kv.resetKey(key);
}

module.exports = { check, reset };