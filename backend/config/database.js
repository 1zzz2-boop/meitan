const { Pool } = require('pg');
const fs = require('fs');
const path = require('path');

// 加载配置：先 .env（非敏感），再用 .env.local（凭据，gitignore 忽略）覆盖
require('dotenv').config({ path: path.join(__dirname, '..', '.env') });
const localEnv = path.join(__dirname, '..', '.env.local');
if (fs.existsSync(localEnv)) {
    require('dotenv').config({ path: localEnv, override: true });
}

/**
 * PostgreSQL 连接池
 * 目标实例：E:\jindieAI\sqlapp（PostgreSQL 12, localhost:5432）
 * 数据库：coal_mine_guard（建库脚本见项目 sjk/schema.sql）
 * 账号：coal_app（专用低权限账号，凭据仅存于 .env.local）
 */
const pool = new Pool({
    host: process.env.DB_HOST || 'localhost',
    port: parseInt(process.env.DB_PORT) || 5432,
    database: process.env.DB_DATABASE || 'coal_mine_guard',
    user: process.env.DB_USER || 'coal_app',
    password: process.env.DB_PASSWORD,
    max: 10,
    idleTimeoutMillis: 30000,
    connectionTimeoutMillis: 5000
});

/**
 * 建立数据库连接（校验连通性）
 */
async function connectToDatabase() {
    try {
        await pool.query('SELECT 1');
        console.log('Connected to PostgreSQL (coal_mine_guard) successfully');
        return pool;
    } catch (error) {
        console.error('Database connection failed:', error.message);
        throw error;
    }
}

/**
 * 执行查询并返回行数组
 * @param {string} text - SQL
 * @param {Array} params - 参数
 * @returns {Promise<Array>}
 */
async function query(text, params = []) {
    try {
        const result = await pool.query(text, params);
        return result.rows;
    } catch (error) {
        console.error('Query execution failed:', error.message);
        throw error;
    }
}

/**
 * 执行查询并返回单行（无则 null）
 */
async function queryOne(text, params = []) {
    const rows = await query(text, params);
    return rows[0] || null;
}

/**
 * 关闭连接池
 */
async function closeDatabaseConnection() {
    try {
        await pool.end();
        console.log('Database connection pool closed');
    } catch (error) {
        console.error('Error closing database connection:', error.message);
    }
}

module.exports = {
    pool,
    connectToDatabase,
    query,
    queryOne,
    closeDatabaseConnection
};
