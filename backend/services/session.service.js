/**
 * 会话服务（服务端绑定登录身份）
 * 登录成功后签发 token，并在 KV 存储（配置 REDIS_URL 则 Redis，否则内存）中保存
 * userId/username/role，后续请求以 token 为准，客户端无法通过改请求头/切 Tab 冒充别的端角色。
 * 支持 TTL，多实例部署时由 Redis 共享会话。
 */
const crypto = require('crypto');
const kv = require('../utils/kv-store');

const TTL_SEC = 12 * 3600; // 12 小时
const SESSION_KEY = (token) => 'session:' + token;

/** 签发会话 */
async function issue(user) {
    const token = crypto.randomBytes(24).toString('hex');
    await kv.set(SESSION_KEY(token), {
        userId: user.id,
        username: user.username,
        role: user.role,
        endName: user.end_name || user.endName
    }, TTL_SEC);
    return token;
}

/** 校验并返回会话（无/过期返回 null） */
async function get(token) {
    if (!token) return null;
    return await kv.get(SESSION_KEY(token));
}

/** 注销会话 */
async function revoke(token) {
    if (token) await kv.resetKey(SESSION_KEY(token));
}

/** 清理全部（测试用 / 简单全量下线） */
async function clear() {
    // 内存态可清空；Redis 无法通配删除时按 path 直删即可（本实现无去重）。
    // 实际登出走 revoke 单键，此处保留接口兼容。
}

module.exports = { issue, get, revoke, clear };