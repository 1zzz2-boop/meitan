/* 验证脚本：登录智库端 → 触发模型重训 → 拉取模型指标
 * 用法：node _verify_model.js
 */
const BASE = 'http://localhost:3000/api';

async function j(res) {
    const t = await res.text();
    try { return JSON.parse(t); } catch { return { raw: t }; }
}

(async () => {
    // 1. 获取验证码（服务端明文返回 code）
    const cap = await j(await fetch(`${BASE}/auth/captcha`));
    if (!cap.captchaId) { console.error('❌ 验证码获取失败:', cap); process.exit(1); }

    // 2. 智库端登录
    const login = await j(await fetch(`${BASE}/auth/login`, {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ username: 't_admin', password: '123456', captchaId: cap.captchaId, captchaCode: cap.code })
    }));
    if (!login.token) { console.error('❌ 登录失败:', login); process.exit(1); }
    const H = { 'Content-Type': 'application/json', Authorization: 'Bearer ' + login.token };
    console.log('✅ 登录成功:', login.user && (login.user.display_name || login.user.username));

    // 3. 触发重训
    console.log('⏳ 触发重训...');
    const t0 = Date.now();
    const m = await j(await fetch(`${BASE}/analysis/retrain`, { method: 'POST', headers: H }));
    console.log('⏱️ 重训耗时 ' + ((Date.now() - t0) / 1000).toFixed(1) + 's');
    if (m.error) { console.error('❌ 重训失败:', m); process.exit(1); }

    // 4. 输出指标
    console.log('\n=== MCFLR 模型指标 ===');
    console.log('版本        :', m.modelVersion);
    console.log('准确率      :', m.accuracy + '%');
    console.log('召回率      :', m.recall + '%   (安全优先 ≥88%)');
    console.log('误报率      :', m.falseRate + '%');
    console.log('工作阈值    :', m.operatingThreshold);
    console.log('训练样本    :', m.sampleSize, '· 测试样本:', m.testSampleSize);
    console.log('数据来源    :', JSON.stringify(m.dataSource));
    const cm = m.confusionMatrix || {};
    console.log('混淆矩阵    : TP=' + cm.tp, 'FN=' + cm.fn, 'FP=' + cm.fp, 'TN=' + cm.tn,
        '· 精确率=' + cm.precision + '%', '· F1=' + cm.f1 + '%');
    if (Array.isArray(cm.perGrade)) {
        console.log('分级指标    :');
        cm.perGrade.forEach(g => console.log('   ' + g.grade, '精确率=' + g.precision + '%', '召回率=' + g.recall + '%'));
    }
    const curve = m.thresholdCurve || [];
    if (curve.length) {
        console.log('阈值曲线(部分):');
        curve.forEach(c => console.log('   阈值=' + c.threshold.toFixed(2), '准确率=' + c.accuracy + '%', '误报率=' + c.falseRate + '%'));
    }

    // 5. GET 接口一致性（前端 thinktank 实际调用）
    const g = await j(await fetch(`${BASE}/analysis/model-metrics`, { headers: H }));
    console.log('\n=== GET /model-metrics（前端实际接口） ===');
    console.log('准确率:', g.accuracy + '%', '· 召回率:', g.recall + '%', '· 误报率:', g.falseRate + '%',
        '· 阈值:', g.operatingThreshold, '· 样本:', g.sampleSize + '/' + g.testSampleSize,
        '· 数据来源 real:', g.dataSource && g.dataSource.real, '条');
    console.log('GET 与重训结果一致:', g.accuracy === m.accuracy && g.recall === m.recall ? '✅' : '⚠️ 不一致');
})().catch(e => { console.error('❌ 脚本异常:', e.message); process.exit(1); });
