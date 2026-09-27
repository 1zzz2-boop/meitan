/**
 * 数据库轻量迁移（幂等，可在启动时安全执行）
 * 对已部署的库补充新增列，避免每次手动 psql。
 * PostgreSQL 12+ 支持 ADD COLUMN IF NOT EXISTS。
 */
const { query } = require('../config/database');

async function runMigrations() {
    // P0-数据来源溯源：sensor_history 增加 source / source_addr
    // P1-预警升级状态机：alerts 增加 raised_count / escalated_at / escalation_note
    const statements = [
        `ALTER TABLE sensor_history ADD COLUMN IF NOT EXISTS source VARCHAR(32)`,
        `ALTER TABLE sensor_history ADD COLUMN IF NOT EXISTS source_addr VARCHAR(128)`,
        `CREATE INDEX IF NOT EXISTS idx_history_source ON sensor_history(source)`,
        `ALTER TABLE alerts ADD COLUMN IF NOT EXISTS raised_count INT DEFAULT 0`,
        `ALTER TABLE alerts ADD COLUMN IF NOT EXISTS escalated_at TIMESTAMP`,
        `ALTER TABLE alerts ADD COLUMN IF NOT EXISTS escalation_note VARCHAR(255)`,
        // P2-3.7 历史归档表
        `CREATE TABLE IF NOT EXISTS sensor_history_archive (
            dim VARCHAR(16) NOT NULL CHECK (dim IN ('hour','day')),
            sensor_id VARCHAR(64) NOT NULL,
            bucket_start TIMESTAMP NOT NULL,
            avg FLOAT,
            min FLOAT,
            max FLOAT,
            samples BIGINT DEFAULT 0,
            updated_at TIMESTAMP DEFAULT now(),
            PRIMARY KEY (dim, sensor_id, bucket_start)
        )`,
        `CREATE INDEX IF NOT EXISTS idx_archive_sensor ON sensor_history_archive(sensor_id, bucket_start)`
    ];
    for (const sql of statements) {
        try {
            await query(sql);
        } catch (e) {
            // 低权限账号无 DDL 权限时降级为跳过（INSERT 已兼容缺列前的旧库由调用方兜底）
            console.warn('[migrate] 跳过（可能无 DDL 权限）:', e.message);
        }
    }
    console.log('[migrate] 字段迁移完成（sensor_history.source/source_addr，alerts.raised_count/escalated_at/escalation_note）');
}

module.exports = { runMigrations };