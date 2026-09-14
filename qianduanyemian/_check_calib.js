/* 校验模拟器新写入数据量纲：对比传感器当前值 + 最近历史与模型标定
 * 预期：film≈12、water≈0.5、vibration≈0.12、strain≈0.025、ultrasonic≈2.6
 */
const { pool } = require('D:/devecostudio-windows-6.0.2.660/devecostudio-windows-6.0.2.660/prj/backend/config/database');

(async () => {
    const s = await pool.query("SELECT id, value, threshold FROM sensors WHERE type NOT IN ('LORA_MODULE','OLED_DISPLAY') ORDER BY id");
    console.log('当前传感器值:');
    s.rows.forEach(r => console.log('  ' + r.id + ' = ' + r.value + ' (阈值 ' + r.threshold + ')'));

    const h = await pool.query(`
        SELECT sensor_id, COUNT(*) c, ROUND(MIN(value)::numeric,3) mn, ROUND(MAX(value)::numeric,3) mx, ROUND(AVG(value)::numeric,3) avg
        FROM sensor_history GROUP BY sensor_id ORDER BY sensor_id`);
    console.log('\n新历史(量纲校验):');
    h.rows.forEach(r => console.log('  ' + r.sensor_id + ': n=' + r.c + ' min=' + r.mn + ' max=' + r.mx + ' avg=' + r.avg));
    await pool.end();
})().catch(e => { console.error(e.message); process.exit(1); });
