/* 数据质量排查：alerts 与 sensor_history 的关系 */
const { pool } = require('D:/devecostudio-windows-6.0.2.660/devecostudio-windows-6.0.2.660/prj/backend/config/database');
(async () => {
    const alerts = await pool.query('SELECT sensor_id, COUNT(*) c FROM alerts GROUP BY sensor_id ORDER BY c DESC');
    console.log('alerts by sensor:', JSON.stringify(alerts.rows));
    const hist = await pool.query("SELECT sensor_id, COUNT(*) c FROM sensor_history WHERE created_at > now() - interval '90 days' GROUP BY sensor_id ORDER BY c DESC");
    console.log('history(90d) by sensor:', JSON.stringify(hist.rows));
    const a = await pool.query("SELECT sensor_id, created_at, level, value, threshold FROM alerts ORDER BY created_at DESC LIMIT 6");
    console.log('recent alerts:', JSON.stringify(a.rows));
    const s = await pool.query("SELECT value, created_at FROM sensor_history WHERE sensor_id='sensor_film_pressure' ORDER BY created_at DESC LIMIT 5");
    console.log('recent film_pressure:', JSON.stringify(s.rows));
    const w = await pool.query("SELECT sensor_id, value, created_at FROM sensor_history WHERE sensor_id IN ('sensor_film_pressure','sensor_water_pressure','sensor_ultrasonic','sensor_vibration','sensor_strain') AND created_at > (SELECT MAX(created_at) - interval '30 min' FROM alerts) ORDER BY created_at LIMIT 12");
    console.log('history during recent alert window:', JSON.stringify(w.rows));
    await pool.end();
})().catch(e => { console.error(e.message); process.exit(1); });
