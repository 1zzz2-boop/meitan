/**
 * 单元测试：模拟器平滑游走（simulator.nextValue）
 * 覆盖：物理量程软边界、边界反弹、无标定传感器小幅扰动、小数位数。
 */
const simulator = require('../utils/simulator');
const { nextValue, MODEL_CAL } = simulator;

describe('模拟器平滑游走（simulator.nextValue）', () => {
  test('有标定传感器：数值始终在物理量程内且有限', () => {
    const { normal, spread } = MODEL_CAL.sensor_film_pressure;
    const lo = Math.max(0, normal - 3.2 * spread);
    const hi = normal + 3.2 * spread;
    const s = { id: 'sensor_film_pressure', value: normal };
    for (let i = 0; i < 1000; i++) {
      s.value = nextValue(s);
      expect(Number.isFinite(s.value)).toBe(true);
      expect(s.value).toBeGreaterThanOrEqual(lo - 1e-9);
      expect(s.value).toBeLessThanOrEqual(hi + 1e-9);
    }
  });

  test('从物理上限起步：触边后不再越界', () => {
    const { normal, spread } = MODEL_CAL.sensor_vibration;
    const hi = normal + 3.2 * spread;
    const s = { id: 'sensor_vibration', value: hi };
    for (let i = 0; i < 500; i++) {
      s.value = nextValue(s);
      expect(s.value).toBeLessThanOrEqual(hi + 1e-9);
    }
  });

  test('无标定传感器：保持非负且单步扰动小于 1%', () => {
    const s = { id: 'sensor_x', value: 10 };
    let prev = 10;
    for (let i = 0; i < 300; i++) {
      s.value = nextValue(s);
      expect(Number.isFinite(s.value)).toBe(true);
      expect(s.value).toBeGreaterThanOrEqual(0);
      expect(Math.abs(s.value - prev) / prev).toBeLessThan(0.01);
      prev = s.value;
    }
  });

  test('输出保留最多 4 位小数（toFixed(4)）', () => {
    const s = { id: 'sensor_vibration', value: MODEL_CAL.sensor_vibration.normal };
    for (let i = 0; i < 50; i++) {
      s.value = nextValue(s);
      const parts = String(s.value).split('.');
      expect(parts[1] ? parts[1].length : 0).toBeLessThanOrEqual(4);
    }
  });
});
