/**
 * 单元测试：MQTT 桥接（mqtt-bridge）
 * 覆盖：三种载荷解析（纯数值/JSON value/JSON sensorId+value）、非法载荷、传感器存在/缺失的入库广播行为。
 * 依赖均 mock，不连真实 broker 与数据库。
 */
jest.mock('../services/sensor.service', () => ({
  updateSensorData: jest.fn(),
  getStats: jest.fn()
}));
jest.mock('../utils/wsHub', () => ({ emit: jest.fn() }));
jest.mock('../config/database', () => ({ query: jest.fn().mockResolvedValue([]) }));

const bridge = require('../services/mqtt-bridge');
const sensorService = require('../services/sensor.service');
const wsHub = require('../utils/wsHub');

describe('MQTT 桥接（mqtt-bridge）', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    sensorService.updateSensorData.mockResolvedValue({ id: 'sensor_x', value: 12.5, type: 'PRESSURE' });
    sensorService.getStats.mockResolvedValue({ total: 1, online: 1, warning: 0, offline: 0 });
  });

  describe('parsePayload（载荷解析）', () => {
    test('纯数值字符串 → 从主题取 sensorId', () => {
      expect(bridge.parsePayload('sensor/sensor_x/data', '12.5')).toEqual({ sensorId: 'sensor_x', value: 12.5 });
    });
    test('JSON 仅含 value → 主题 sensorId', () => {
      expect(bridge.parsePayload('sensor/sensor_x/data', '{"value":7}')).toEqual({ sensorId: 'sensor_x', value: 7 });
    });
    test('JSON 含 sensorId → 覆盖主题中的 id', () => {
      expect(bridge.parsePayload('sensor/sensor_x/data', '{"sensorId":"sensor_y","value":3.5}')).toEqual({ sensorId: 'sensor_y', value: 3.5 });
    });
    test('非法载荷 → null', () => {
      expect(bridge.parsePayload('sensor/sensor_x/data', 'abc')).toBeNull();
      expect(bridge.parsePayload('sensor/sensor_x/data', '{"value":"abc"}')).toBeNull();
      expect(bridge.parsePayload('sensor/sensor_x/data', '{"foo":1}')).toBeNull();
      expect(bridge.parsePayload('sensor/sensor_x/data', '')).toBeNull();
    });
    test('主题非 sensor/<id>/data 时纯数值无传感器 id', () => {
      expect(bridge.parsePayload('other/topic', '1.5')).toEqual({ sensorId: null, value: 1.5 });
    });
  });

  describe('ingest（入库 + 广播）', () => {
    test('传感器存在：返回 true 并广播 sensor_update / sensor_stats', async () => {
      sensorService.updateSensorData.mockResolvedValue({ id: 'sensor_x', value: 12.5, type: 'PRESSURE' });
      const ok = await bridge.ingest('sensor/sensor_x/data', '12.5');
      expect(ok).toBe(true);
      expect(sensorService.updateSensorData).toHaveBeenCalledWith('sensor_x', 12.5);
      expect(wsHub.emit).toHaveBeenCalledWith('sensor_update', expect.objectContaining({ id: 'sensor_x' }));
      expect(wsHub.emit).toHaveBeenCalledWith('sensor_stats', expect.any(Object));
    });

    test('传感器不存在：返回 false 且不广播', async () => {
      sensorService.updateSensorData.mockResolvedValue(null);
      const ok = await bridge.ingest('sensor/sensor_x/data', '12.5');
      expect(ok).toBe(false);
      expect(wsHub.emit).not.toHaveBeenCalled();
    });

    test('载荷无法解析：返回 false 且不调入库', async () => {
      const ok = await bridge.ingest('sensor/sensor_x/data', 'not-a-number');
      expect(ok).toBe(false);
      expect(sensorService.updateSensorData).not.toHaveBeenCalled();
      expect(wsHub.emit).not.toHaveBeenCalled();
    });
  });
});
