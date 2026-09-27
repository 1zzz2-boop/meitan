/**
 * 统一载荷解析工具
 * 兼容三种格式（MQTT 与 UDP 桥接共用）：
 *   - 纯数值字符串          例："12.5"
 *   - JSON 含 value         例：{"value":12.5}
 *   - JSON 含 sensorId+value 例：{"sensorId":"sensor_x","value":12.5}
 *
 * @param {string} str 原始载荷字符串
 * @param {string|null} fallbackSensorId 有上下文（如 MQTT topic）时的兜底 sensorId，无则传 null
 * @returns {{sensorId: string|null, value: number}|null}
 */
function parsePayload(str, fallbackSensorId = null) {
  const body = String(str).trim();
  // 纯数值
  if (/^[-+]?(\d+\.?\d*|\.\d+)$/.test(body)) {
    return { sensorId: fallbackSensorId, value: parseFloat(body) };
  }
  // JSON
  try {
    const o = JSON.parse(body);
    const value = parseFloat(o.value);
    if (Number.isNaN(value)) return null;
    return { sensorId: (o.sensorId || o.sensor_id || fallbackSensorId), value };
  } catch (e) {
    return null;
  }
}

module.exports = { parsePayload };