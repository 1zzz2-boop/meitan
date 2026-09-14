#!/usr/bin/env node
/**
 * PostgreSQL 定时备份脚本
 * - 用 pg_dump 对 coal_mine_guard 做全量备份并 gzip 压缩到 backups/。
 * - 按保留天数清理过期备份（BACKUP_RETENTION_DAYS，默认 14 天）。
 * - 支持两种调度方式：
 *    1) 常驻：node scripts/backup-db.js --daemon   按 BACKUP_INTERVAL_HOURS（默认 24h）定时备份
 *    2) 外部触发：node scripts/backup-db.js         执行一次后退出（配 cron / Windows 任务计划）
 *
 * 环境变量（从 .env/.env.local 读取）：
 *   DB_HOST / DB_PORT / DB_DATABASE / DB_USER / DB_PASSWORD
 *   PG_DUMP        pg_dump 路径，默认自动探测（含 E:\jindieAI\sqlapp）
 *   BACKUP_DIR     输出目录，默认 backend/backups
 *   BACKUP_RETENTION_DAYS   保留天数，默认 14
 *   BACKUP_INTERVAL_HOURS   --daemon 模式的间隔，默认 24
 */
const { execFile } = require('child_process');
const fs = require('fs');
const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '..', '.env') });
const localEnv = path.join(__dirname, '..', '.env.local');
if (fs.existsSync(localEnv)) {
    require('dotenv').config({ path: localEnv, override: true });
}

const HOST = process.env.DB_HOST || 'localhost';
const PORT = process.env.DB_PORT || '5432';
const DATABASE = process.env.DB_DATABASE || 'coal_mine_guard';
const USER = process.env.DB_USER || 'coal_app';
const PASSWORD = process.env.DB_PASSWORD || '';

const BACKUP_DIR = process.env.BACKUP_DIR || path.join(__dirname, '..', 'backups');
const RETENTION_DAYS = parseInt(process.env.BACKUP_RETENTION_DAYS) || 14;
const INTERVAL_HOURS = parseInt(process.env.BACKUP_INTERVAL_HOURS) || 24;
const LOG_FILE = path.join(BACKUP_DIR, 'backup.log');

const PG_DUMP = findPgDump();

function findGzip() {
    const gitUsr = path.join('C:', 'Program Files', 'Git', 'usr', 'bin', 'gzip.exe');
    if (fs.existsSync(gitUsr)) return gitUsr;
    const candidates = [
        path.join('C:', 'Program Files', 'Git', 'usr', 'bin', 'gzip.exe'),
        'C:\\msys64\\usr\\bin\\gzip.exe',
        'gzip'
    ];
    for (const c of candidates) {
        if (c !== 'gzip' && fs.existsSync(c)) return c;
    }
    return 'gzip'; // 走 PATH
}

function findPgDump() {
    if (process.env.PG_DUMP) return process.env.PG_DUMP;
    const candidates = [
        path.join('E:', 'jindieAI', 'sqlapp', 'bin', 'pg_dump.exe'),
        path.join('E:', 'jindieAI', 'sqlapp', 'bin', 'pg_dump'),
        'pg_dump'
    ];
    for (const c of candidates) {
        if (c !== 'pg_dump' && fs.existsSync(c)) return c;
    }
    return 'pg_dump'; // 走 PATH
}

function log(msg) {
    const line = `[${new Date().toISOString()}] ${msg}`;
    console.log(line);
    fs.mkdirSync(path.dirname(LOG_FILE), { recursive: true });
    fs.appendFileSync(LOG_FILE, line + '\n');
}

function timestamp() {
    const d = new Date();
    const p = (n) => String(n).padStart(2, '0');
    return `${d.getFullYear()}${p(d.getMonth() + 1)}${p(d.getDate())}_${p(d.getHours())}${p(d.getMinutes())}${p(d.getSeconds())}`;
}

function runBackup() {
    return new Promise((resolve, reject) => {
        fs.mkdirSync(BACKUP_DIR, { recursive: true });
        const gzip = findGzip();
        const compressible = gzip !== 'gzip'; // 找到具体 gzip 路径才使用压缩
        const ext = compressible ? 'sql.gz' : 'sql';
        const file = path.join(BACKUP_DIR, `${DATABASE}_${timestamp()}.${ext}`);
        const cmd = `pg_dump -h "${HOST}" -p "${PORT}" -U "${USER}" -d "${DATABASE}"`;
        log(`备份开始：${cmd}（输出到 ${file}${compressible ? '，gzip 压缩' : '，未压缩' }）`);

        const args = ['-h', HOST, '-p', PORT, '-U', USER, '-d', DATABASE];
        const child = execFile(PG_DUMP, args, {
            env: { ...process.env, PGPASSWORD: PASSWORD },
            maxBuffer: 1024 * 1024 * 1024 // 1GB 缓冲
        });

        const out = fs.createWriteStream(file);
        let streamOut = null;
        if (compressible) {
            const gz = execFile(gzip, ['-9', '-c'], { env: process.env, maxBuffer: 1024 * 1024 * 1024 });
            child.stdout.pipe(gz.stdin);
            gz.stdout.pipe(out);
            gz.on('error', (e) => reject(new Error('gzip 失败：' + e.message)));
            streamOut = gz.stdout;
        } else {
            child.stdout.pipe(out);
            streamOut = child.stdout;
        }

        child.on('error', (e) => {
            cleanupPartial(file);
            reject(new Error('pg_dump 启动失败：' + e.message));
        });
        out.on('finish', () => {
            const len = fs.statSync(file).size;
            if (len <= 0) {
                cleanupPartial(file);
                log('备份失败：产物为空（请检查 PGPASSWORD / 连接）');
                return reject(new Error('备份产物为空'));
            }
            log(`备份完成：${file}（${(len / 1024).toFixed(1)} KB）`);
            prune();
            resolve(file);
        });
        out.on('error', (e) => {
            cleanupPartial(file);
            reject(new Error('写入备份失败：' + e.message));
        });
        child.stderr.on('data', (d) => log('pg_dump stderr: ' + String(d).trim()));
    });
}

function cleanupPartial(file) {
    try { fs.unlinkSync(file); } catch (e) { /* 忽略 */ }
}

function prune() {
    // 删除超过保留天数的备份与对应 .log
    const cutoff = Date.now() - RETENTION_DAYS * 24 * 3600 * 1000;
    fs.readdirSync(BACKUP_DIR).forEach((f) => {
        const fp = path.join(BACKUP_DIR, f);
        if (!/\.sql\.gz$/.test(f)) return;
        const st = fs.statSync(fp);
        if (st.mtimeMs < cutoff) {
            fs.unlinkSync(fp);
            log(`已清理过期备份：${f}`);
        }
    });
}

async function main() {
    const isDaemon = process.argv.includes('--daemon');
    try {
        await runBackup();
    } catch (e) {
        log('备份失败：' + e.message);
        if (!isDaemon) process.exit(1);
    }
    if (isDaemon) {
        log(`进入定时模式，每 ${INTERVAL_HOURS} 小时备份一次（Ctrl+C 退出）`);
        setInterval(() => runBackup().catch((e) => log('备份失败：' + e.message)), INTERVAL_HOURS * 3600 * 1000);
    } else {
        process.exit(0);
    }
}

main();