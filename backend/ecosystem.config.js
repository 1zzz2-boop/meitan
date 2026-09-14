/**
 * PM2 进程守护配置（后端 + 定时备份）
 * 用法：
 *   开发:   pm2 start ecosystem.config.js
 *   生产:   pm2 start ecosystem.config.js --env production
 *   查看:   pm2 status / pm2 logs coal-backend
 *   上线自启: pm2 save && pm2 startup
 *
 * 说明：
 * - coal-backend  意 Express 后端（HTTP + 可选 HTTPS + WebSocket）。
 *   默认 instances:1（fork）。只有配置了 REDIS_URL 使多实例共享会话/限流后，
 *   才建议把 instances 调大 / 改成 cluster 模式。
 * - coal-backup   独立的定时备份守护进程（脚本内自调度，默认 24h）。
 */
const path = require('path');

const BACKEND_DIR = __dirname;

module.exports = {
  apps: [
    {
      name: 'coal-backend',
      cwd: BACKEND_DIR,
      script: 'server.js',
      instances: 1,
      exec_mode: 'fork',
      autorestart: true,
      watch: false,
      max_memory_restart: '500M',
      restart_delay: 3000,
      exp_backoff_restart_delay: 2000,
      max_restarts: 30,          // 30s 内最多重启 30 次，超限 stop 避免死循环
      kill_timeout: 9000,        // 留给 server.js 优雅退出（关闭 WS/Redis/DB）
      listen_timeout: 10000,
      time: true,                // 日志带时间戳
      out_file: path.join(BACKEND_DIR, 'logs', 'coal-backend.out.log'),
      error_file: path.join(BACKEND_DIR, 'logs', 'coal-backend.err.log'),
      env: {
        NODE_ENV: 'development'
      },
      env_production: {
        NODE_ENV: 'production',
        HTTPS_ENABLED: 'true'    // 生产建议启用 TLS；cert 缺失时 server.js 会安全跳过
      }
    },
    {
      name: 'coal-backup',
      cwd: BACKEND_DIR,
      script: 'scripts/backup-db.js',
      args: '--daemon',
      instances: 1,
      exec_mode: 'fork',
      autorestart: true,
      max_memory_restart: '200M',
      restart_delay: 5000,
      kill_timeout: 60000,       // 预留 DDL 备份完成时间，避免强杀写一半
      time: true,
      out_file: path.join(BACKEND_DIR, 'logs', 'coal-backup.out.log'),
      error_file: path.join(BACKEND_DIR, 'logs', 'coal-backup.err.log'),
      env: {
        BACKUP_INTERVAL_HOURS: process.env.BACKUP_INTERVAL_HOURS || '24',
        BACKUP_RETENTION_DAYS: process.env.BACKUP_RETENTION_DAYS || '14'
      }
    }
  ]
};