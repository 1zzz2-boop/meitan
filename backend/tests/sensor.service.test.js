/**
 * 单元测试：传感器阈值判定（sensor.service）
 * 覆盖：超声波测距（值<阈值预警）与其他传感器（值>阈值预警）的方向差异、未设置阈值、预警等级分级。
 */
const sensorService = require('../services/sensor.service');
const { isOverThreshold, alertLevelOf } = sensorService;

describe('传感器阈值判定（sensor.service）', () => {
  describe('isOverThreshold（方向判定）', () => {
    test('超声波测距：值小于阈值 → 预警', () => {
      expect(isOverThreshold({ type: 'ULTRASONIC_DISTANCE', value: 2.0, threshold: 2.5 })).toBe(true);
    });
    test('超声波测距：值大于阈值 → 不预警', () => {
      expect(isOverThreshold({ type: 'ULTRASONIC_DISTANCE', value: 3.0, threshold: 2.5 })).toBe(false);
    });
    test('超声波测距：值等于阈值 → 不预警（严格小于）', () => {
      expect(isOverThreshold({ type: 'ULTRASONIC_DISTANCE', value: 2.5, threshold: 2.5 })).toBe(false);
    });
    test('普通传感器：值大于阈值 → 预警', () => {
      expect(isOverThreshold({ type: 'PRESSURE', value: 12.5, threshold: 12.0 })).toBe(true);
    });
    test('普通传感器：值小于阈值 → 不预警', () => {
      expect(isOverThreshold({ type: 'PRESSURE', value: 11.0, threshold: 12.0 })).toBe(false);
    });
    test('未设置阈值 → 永不预警', () => {
      expect(isOverThreshold({ type: 'PRESSURE', value: 999 })).toBe(false);
      expect(isOverThreshold({ type: 'PRESSURE', value: 999, threshold: null })).toBe(false);
      expect(isOverThreshold({ type: 'PRESSURE', value: 999, threshold: undefined })).toBe(false);
    });
  });

  describe('alertLevelOf（等级分级）', () => {
    test('超阈值比例 > 0.5 → RED', () => {
      expect(alertLevelOf({ type: 'PRESSURE', value: 20, threshold: 12 })).toBe('RED'); // 8/12≈0.67
    });
    test('0.3 < 比例 ≤ 0.5 → ORANGE', () => {
      expect(alertLevelOf({ type: 'PRESSURE', value: 16.5, threshold: 12 })).toBe('ORANGE'); // 4.5/12=0.375
    });
    test('比例 ≤ 0.3 → YELLOW', () => {
      expect(alertLevelOf({ type: 'PRESSURE', value: 13.2, threshold: 12 })).toBe('YELLOW'); // 1.2/12=0.1
    });
    test('超声波方向：偏离越多等级越高', () => {
      expect(alertLevelOf({ type: 'ULTRASONIC_DISTANCE', value: 0.8, threshold: 2.5 })).toBe('RED'); // 1.7/2.5=0.68
      expect(alertLevelOf({ type: 'ULTRASONIC_DISTANCE', value: 2.2, threshold: 2.5 })).toBe('YELLOW'); // 0.3/2.5=0.12
    });
  });
});
