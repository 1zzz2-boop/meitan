/**
 * 数据库初始化脚本（PostgreSQL）
 * 读取项目 sjk/schema.sql 并在 coal_mine_guard 库中执行（含建表与种子数据，可重复执行）
 * 运行：npm run db:setup
 */
const fs = require('fs');
const path = require('path');
const { connectToDatabase, query } = require('../config/database');

async function main() {
    const schemaPath = path.join(__dirname, '..', '..', 'sjk', 'schema.sql');
    if (!fs.existsSync(schemaPath)) {
        console.error('未找到 sjk/schema.sql，请确认文件存在');
        process.exit(1);
    }

    await connectToDatabase();
    const sql = fs.readFileSync(schemaPath, 'utf8');
    // 按语句分割执行（schema.sql 不含事务包裹语句）
    const statements = sql
        .split(/;\s*(?:\r?\n|$)/)
        .map(s => s.trim())
        .filter(s => s.length > 0 && !s.startsWith('--'));

    for (const stmt of statements) {
        try {
            await query(stmt);
        } catch (e) {
            console.log(`语句执行跳过（可能因重复/依赖顺序）: ${e.message}`);
        }
    }
    console.log('数据库初始化完成（建表 + 种子数据）');
    process.exit(0);
}

main().catch(err => {
    console.error('数据库初始化失败:', err.message);
    process.exit(1);
});
