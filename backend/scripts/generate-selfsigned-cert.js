#!/usr/bin/env node
/**
 * 生成自签 TLS 证书（本地/内网 HTTPS 验证用）
 * 生产环境的正式域名务必用权威 CA（如 Let's Encrypt 或企业 CA）签发的证书替换。
 *
 * 用法：
 *   node scripts/generate-selfsigned-cert.js
 * 在 backend/certs 下生成 cert.pem / key.pem。
 *
 * 依赖：系统 PATH 或 Git 自带 openssl。
 */
const { execFileSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const CERTS_DIR = path.join(__dirname, '..', 'certs');
const CERT_FILE = path.join(CERTS_DIR, 'cert.pem');
const KEY_FILE = path.join(CERTS_DIR, 'key.pem');
const CONFIG_FILE = path.join(CERTS_DIR, 'openssl.cnf');

const commonName = process.env.CERT_CN || 'localhost';
const days = process.env.CERT_DAYS || '825';

function findOpenssl() {
    const candidates = ['openssl', 'C:\\Program Files\\Git\\usr\\bin\\openssl.exe'];
    for (const c of candidates) {
        try { execFileSync(c, ['version'], { stdio: 'ignore' }); return c; }
        catch (e) { /* try next */ }
    }
    throw new Error('未找到 openssl，请安装或在 PATH 中提供');
}

function main() {
    fs.mkdirSync(CERTS_DIR, { recursive: true });
    const openssl = findOpenssl();

    // SAN 配置，保证 modern 客户端可用（CN 已不单独校验）
    const cnfg = [
        '[req]',
        'distinguished_name=dn',
        'x509_extensions=v3',
        'prompt=no',
        '[dn]',
        `CN=${commonName}`,
        '[v3]',
        `subjectAltName=DNS:${commonName},DNS:localhost,IP:127.0.0.1`,
        'basicConstraints=CA:FALSE',
        'extendedKeyUsage=serverAuth'
    ].join('\n');
    fs.writeFileSync(CONFIG_FILE, cnfg, 'utf8');

    execFileSync(openssl, [
        'req', '-x509', '-newkey', 'rsa:2048', '-nodes',
        '-keyout', KEY_FILE, '-out', CERT_FILE,
        '-days', days, '-config', CONFIG_FILE,
        '-subj', `/CN=${commonName}`
    ], { stdio: 'inherit' });

    console.log('\n自签证书已生成：');
    console.log('  证书: ' + CERT_FILE);
    console.log('  密钥: ' + KEY_FILE);
    console.log('\n启用 HTTPS：在 .env 设 HTTPS_ENABLED=true（可再加 HTTPS_PORT / REDIRECT_HTTPS）');
    console.log('注意：自签证书仅用于本地/内网验证，正式上线请替换为权威 CA 签发的证书。');
}

main();