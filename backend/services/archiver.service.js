/**
 * 历史数据归档服务（P2-3.7）
 *
 * 定期把超过 ARCHIVE_DAYS 天的 sensor_history 明细按 「小时 / 天」维度聚合，
 * 写入 sensor_history_archive（upsert 更新），并按需删除原始明细，从而控制明细表增长。
 *
 * 被归档后的数据仍可通过 sensor_service.getHistory() 的「近期+归档 union」查询读到，
 * 保证趋势分析 / 报表统计不受归档影响。
 *
 * 环境变量（.env）：
 *   ARCHIVE_DAYS       归档阈值（默认 7，超过该天数的明细被聚合归档）
 *   ARCHIVE_SWEEP_MS   归档扫描周期（默认 3600000 = 1 小时）
 *   ARCHIVE_KEEP_RAW   'true' 时归档后保留原始明细，否则删除（默认 false 删除）
 */
const { query } = require('../config/database');

const archiverService = {
    _timer: null,

    getConfig() {
        return {
            days: parseInt(process.env.ARCHIVE_DAYS) || 7,
            sweepMs: parseInt(process.env.ARCHIVE_SWEEP_MS) || 3600000,
            keepRaw: (process.env.ARCHIVE_KEEP_RAW || '').toLowerCase() === 'true'
        };
    },

    /**
     * 单次归档扫描。返回 { hourBuckets, dayBuckets, deletedRows }。
     */
    async sweep() {
        const { days, keepRaw } = this.getConfig();
        const cutoff = new Date(Date.now() - days * 24 * 3600 * 1000).toISOString();

        const hourRes = await query(
            `INSERT INTO sensor_history_archive (dim, sensor_id, bucket_start, avg, min, max, samples, updated_at)
             SELECT 'hour', sensor_id, date_trunc('hour', created_at),
                    round(avg(value)::numeric, 4), round(min(value)::numeric, 4),
                    round(max(value)::numeric, 4), count(*), now()
             FROM sensor_history
             WHERE created_at < $1
             GROUP BY sensor_id, date_trunc('hour', created_at)
             ON CONFLICT (dim, sensor_id, bucket_start) DO UPDATE
               SET avg = EXCLUDED.avg, min = EXCLUDED.min, max = EXCLUDED.max,
                   samples = EXCLUDED.samples, updated_at = now()`,
            [cutoff]
        );

        const dayRes = await query(
            `INSERT INTO sensor_history_archive (dim, sensor_id, bucket_start, avg, min, max, samples, updated_at)
             SELECT 'day', sensor_id, date_trunc('day', created_at),
                    round(avg(value)::numeric, 4), round(min(value)::numeric, 4),
                    round(max(value)::numeric, 4), count(*), now()
             FROM sensor_history
             WHERE created_at < $1
             GROUP BY sensor_id, date_trunc('day', created_at)
             ON CONFLICT (dim, sensor_id, bucket_start) DO UPDATE
               SET avg = EXCLUDED.avg, min = EXCLUDED.min, max = EXCLUDED.max,
                   samples = EXCLUDED.samples, updated_at = now()`,
            [cutoff]
        );

        let deletedRows = 0;
        if (!keepRaw) {
            const del = await query(`DELETE FROM sensor_history WHERE created_at < $1`, [cutoff]);
            deletedRows = del.rowCount || 0;
        }

        const hourBuckets = hourRes.rowCount || 0;
        const dayBuckets = dayRes.rowCount || 0;
        if (hourBuckets || dayBuckets || deletedRows) {
            console.log(`[archiver] 归档完成：小时桶=${hourBuckets}，日桶=${dayBuckets}，删除明细=${deletedRows}（阈值 ${days} 天${keepRaw ? '，保留原始' : ''}）`);
        }
        return { hourBuckets, dayBuckets, deletedRows };
    },

    start() {
        if (this._timer) return;
        const { sweepMs } = this.getConfig();
        this.sweep().catch(e => console.error('[archiver] 初次归档失败:', e.message));
        this._timer = setInterval(() => {
            this.sweep().catch(e => console.error('[archiver] 归档失败:', e.message));
        }, sweepMs);
        console.log(`[archiver] 历史数据归档服务已启动（每 ${(sweepMs / 60000).toFixed(0)} 分钟扫描，阈值 ${process.env.ARCHIVE_DAYS || 7} 天）`);
    },

    stop() {
        if (this._timer) {
            clearInterval(this._timer);
            this._timer = null;
            console.log('[archiver] 历史数据归档服务已停止');
        }
    }
};

module.exports = archiverService;