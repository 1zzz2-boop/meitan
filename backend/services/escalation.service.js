/**
 * 预警升级状态机
 *
 * 对未处置的预警按级别随时间自动升级：
 *   YELLOW --(ESCALATE_YELLOW_SEC 秒)--> ORANGE --(ESCALATE_ORANGE_SEC 秒)--> RED
 * RED 为最高级，不再升级，仅标记为「已上报监管端」。
 *
 * 每次升级：level 升高、raised_count+1、escalated_at 重置为当前时间、写入 escalation_note，
 * 最后通过 wsHub 广播 alert_update 供三端实时刷新。
 */
const { query, queryOne } = require('../config/database');
const wsHub = require('../utils/wsHub');

const LEVEL_ORDER = { YELLOW: 1, ORANGE: 2, RED: 3 };

const escalationService = {
    _timer: null,

    // 阈值（可被 .env 覆盖）
    getConfig() {
        return {
            yellowSec: parseInt(process.env.ESCALATE_YELLOW_SEC) || 600,
            orangeSec: parseInt(process.env.ESCALATE_ORANGE_SEC) || 1200
        };
    },

    /**
     * 单次升级扫描：找出应升级且未处置的预警并执行升级。
     * 返回本次升级的预警 id 列表。
     */
    async sweep() {
        const { yellowSec, orangeSec } = this.getConfig();

        // 取所有未处置且未到最高级的预警
        const rows = await query(
            `SELECT id, level, escalated_at, created_at
             FROM alerts
             WHERE handled = FALSE AND level <> 'RED'`
        );

        const now = new Date();
        const escalated = [];

        for (const row of rows) {
            const start = row.escalated_at || row.created_at;
            if (!start) continue;
            const elapsedSec = (now - new Date(start)) / 1000;

            let nextLevel = null;
            let note = null;

            if (row.level === 'YELLOW' && elapsedSec >= yellowSec) {
                nextLevel = 'ORANGE';
                note = `超过 ${Math.round(yellowSec / 60)} 分钟未处置，由黄色预警自动升级为橙色预警`;
            } else if (row.level === 'ORANGE' && elapsedSec >= orangeSec) {
                nextLevel = 'RED';
                note = `超过 ${Math.round(orangeSec / 60)} 分钟未处置，已升级为最高级红色预警并上报监管端`;
            }

            if (nextLevel) {
                const updated = await queryOne(
                    `UPDATE alerts
                     SET level = $2, raised_count = raised_count + 1,
                         escalated_at = now(), escalation_note = $3
                     WHERE id = $1 AND handled = FALSE
                     RETURNING id, sensor_id, sensor_name, level, message, value, threshold,
                               handled, handler, handled_at, mine_id, created_at,
                               raised_count, escalated_at, escalation_note`,
                    [row.id, nextLevel, note]
                );
                if (updated) escalated.push(updated);
            }
        }

        if (escalated.length > 0) {
            console.log(`[escalation] 升级 ${escalated.length} 条预警`);
            wsHub.emit('alert_update', { escalated, level: escalated.some(a => a.level === 'RED') ? 'RED' : 'ORANGE' });
        }

        return escalated;
    },

    start() {
        if (this._timer) return;
        // 立即执行一次，再按周期扫描
        this.sweep().catch(e => console.error('[escalation] 初次扫描失败:', e.message));
        const interval = parseInt(process.env.ESCALATION_SWEEP_MS) || 30000;
        this._timer = setInterval(() => {
            this.sweep().catch(e => console.error('[escalation] 扫描失败:', e.message));
        }, interval);
        console.log(`[escalation] 预警升级状态机已启动（每 ${interval}ms 扫描）`);
    },

    stop() {
        if (this._timer) {
            clearInterval(this._timer);
            this._timer = null;
            console.log('[escalation] 预警升级状态机已停止');
        }
    }
};

module.exports = escalationService;