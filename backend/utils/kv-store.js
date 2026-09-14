/**
 * 键值存储抽象（Redis 可选，降级为内存）
 * - 配置了 REDIS_URL 且可连接 → 使用 Redis，实现多实例共享会话 / 分布式限流。
 * - 未配置或连接失败 → 自动回退到进程内 Map（单实例，进程重启即失效）。
 * 对外暴露统一、异步的 KV 接口，供 session.service / rate-limit 使用。
 */
const { createClient } = require('redis');

const REDIS_URL = process.env.REDIS_URL || '';
const TTL_SEC = 3 * 3600; // 默认 3 小时

let redisClient = null;
let usingRedis = false;
let initPromise = null;

function memoryGet(key) {
    return storeMap.get(key) ?? null;
}

// ---------------- 进程内 Map 存储 ----------------
const storeMap = new Map();
function memorySet(key, value, ttlSec) {
    const expiresAt = Date.now() + (ttlSec * 1000);
    storeMap.set(key, { value, expiresAt });
}
function memoryDel(key) {
    storeMap.delete(key);
}
function memoryIncrWithTtl(key, ttlSec) {
    const now = Date.now();
    const cur = storeMap.get(key);
    if (!cur || cur.expiresAt <= now) {
        const expiresAt = now + (ttlSec * 1000);
        storeMap.set(key, { value: 1, expiresAt });
        return 1;
    }
    cur.value += 1;
    return cur.value;
}
function memoryClean() {
    const now = Date.now();
    for (const [k, v] of storeMap) {
        if (v.expiresAt <= now) storeMap.delete(k);
    }
}

// ---------------- Redis 客户端（惰性初始化） ----------------
function initRedis() {
    if (!REDIS_URL) return null;
    if (!initPromise) {
        initPromise = (async () => {
            try {
                const client = createClient({ url: REDIS_URL, socket: { reconnectStrategy: (retries) => Math.min(retries * 200, 2000) } });
                client.on('error', (e) => console.warn('[kv] Redis error:', e.message));
                await client.connect();
                redisClient = client;
                usingRedis = true;
                console.log('[kv] 已连接 Redis：' + REDIS_URL.replace(/:[^:@/]+@/, ':***@'));
                return client;
            } catch (e) {
                usingRedis = false;
                console.warn('[kv] Redis 不可用，回退内存存储：' + e.message);
                return null;
            }
        })();
    }
    return initPromise;
}

async function ensureRedis() {
    if (REDIS_URL && !redisClient && !initPromise) {
        await initRedis();
    }
    return redisClient;
}

// ---------------- 对外统一接口（异步） ----------------

/** 是否启用 Redis（false 表示当前为内存态） */
async function isRedis() {
    const c = await ensureRedis();
    return !!c;
}

async function get(key) {
    const c = await ensureRedis();
    if (c) {
        const v = await c.get(key);
        return v == null ? null : JSON.parse(v);
    }
    const rec = memoryGet(key);
    if (rec && rec.expiresAt > Date.now()) return rec.value;
    if (rec) memoryDel(key);
    return null;
}

async function set(key, value, ttlSec = TTL_SEC) {
    const c = await ensureRedis();
    if (c) {
        await c.setEx(key, ttlSec, JSON.stringify(value));
        return;
    }
    memorySet(key, value, ttlSec);
}

async function del(key) {
    const c = await ensureRedis();
    if (c) {
        await c.del(key);
        return;
    }
    memoryDel(key);
}

/**
 * 原子自增（带 TTL，用于限流）。首次调用从 1 开始计数。
 * 返回自增后的值。
 */
async function incrWithTtl(key, ttlSec = TTL_SEC) {
    const c = await ensureRedis();
    if (c) {
        const n = await c.incr(key);
        const ttl = await c.ttl(key);
        if (ttl < 0) await c.expire(key, ttlSec);
        return n;
    }
    memoryClean();
    const n = memoryIncrWithTtl(key, ttlSec);
    // 限制内存 Map 增长
    if (storeMap.size > 50000) memoryClean();
    return n;
}

/** 计数归零 / 清理单键 */
async function resetKey(key) {
    await del(key);
}

/** 返回键剩余存活秒数（无此键返回 -2 语义为不存在） */
async function ttlSeconds(key) {
    const c = await ensureRedis();
    if (c) {
        const ttl = await c.ttl(key);
        return ttl < 0 ? 0 : ttl;
    }
    const rec = memoryGet(key);
    if (rec && rec.expiresAt > Date.now()) {
        return Math.max(1, Math.ceil((rec.expiresAt - Date.now()) / 1000));
    }
    return 0;
}

/** 退出时释放连接 */
async function quit() {
    if (redisClient) {
        try { await redisClient.quit(); } catch (e) { /* ignore */ }
        redisClient = null;
    }
}

module.exports = { get, set, del, incrWithTtl, resetKey, isRedis, ttlSeconds, quit };