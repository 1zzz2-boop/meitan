/**
 * 审计/操作留痕服务
 * 关键操作（登录、改密、派单、预警处置、阈值调整、报表生成、用户管理、越权尝试）内存写入并异步落库，
 * 供监管端 /api/audit 查询。写库失败仅打印告警，不影响主流程。
 */
const { query } = require('../config/database');

/** 记录一条审计日志（fire-and-forget） */
async function log(action, detail = '', ctx = {}) {
    const username = (ctx.username) || (ctx.auth && ctx.auth.username) || 'anonymous';
    const role = (ctx.role) || (ctx.auth && ctx.auth.role) || 'unknown';
    const ip = (ctx.ip) || (ctx.req && ctx.req.ip) || '-';
    const record = { action, username, role, ip, detail: String(detail || '') };
    // 内存留底一份，便于查询接口与重启前即时可见（主要落库在 DB）
    try {
        await query(
            `INSERT INTO audit_logs (action, username, role, ip, detail, created_at)
             VALUES ($1, $2, $3, $4, $5, NOW()) RETURNING id`,
            [record.action, record.username, record.role, record.ip, record.detail]
        );
    } catch (e) {
        console.warn(`[audit] 写入审计失败(${record.action}): ${e.message}`);
    }
    return record;
}

/** 分页查询审计日志（监管端） */
async function list({ limit = 200, offset = 0 } = {}) {
    const rows = await query(
        `SELECT id, action, username, role, ip, detail, created_at
         FROM audit_logs ORDER BY id DESC LIMIT $1 OFFSET $2`,
        [Math.min(Number(limit) || 200, 500), Number(offset) || 0]
    );
    return rows || [];
}

module.exports = { log, list };