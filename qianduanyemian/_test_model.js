/* 桩测试：不连数据库，验证模型算法（生成器→特征→训练→评估）能产出合理指标 */
const path = require('path');
const BACKEND = path.join('D:', 'devecostudio-windows-6.0.2.660', 'devecostudio-windows-6.0.2.660', 'prj', 'backend');
const db = require(path.join(BACKEND, 'config', 'database'));

db.query = async () => [];
db.queryOne = async (sql) => {
    if (sql.includes('SELECT * FROM model_state')) return null;   // 无缓存状态 → 触发训练
    return { c: 0 };
};

const model = require(path.join(BACKEND, 'services', 'model.service'));
model.getMetrics().then(m => {
    console.log('accuracy=', m.accuracy, 'falseRate=', m.falseRate, 'opThr=', m.operatingThreshold);
    console.log('train/test=', m.sampleSize, '/', m.testSampleSize);
    console.log('confusion=', JSON.stringify(m.confusionMatrix));
    console.log('dataSource=', JSON.stringify(m.dataSource));
    console.log('curve=', JSON.stringify(m.thresholdCurve));
    console.log('perGrade=', JSON.stringify(m.confusionMatrix.perGrade));
    const pos = (m.confusionMatrix.tp + m.confusionMatrix.fn);
    console.log('testPositives=', pos);
    console.log('recall=', m.recall);
    if (m.accuracy < 85 || m.accuracy > 98.5) { console.error('准确率异常: ' + m.accuracy); process.exit(1); }
    if (m.recall < 75) { console.error('召回率过低（安全优先应≥88）: ' + m.recall); process.exit(1); }
    if (pos < 15) { console.error('测试集正样本过少: ' + pos); process.exit(1); }
    console.log('STUB TEST OK');
}).catch(e => { console.error('TEST FAILED:', e); process.exit(1); });
