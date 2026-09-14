const request = require('supertest');
const app = require('../src/app');

describe('Sensor API', () => {
  test('GET /api/sensor/all returns 200 with sensor list', async () => {
    const res = await request(app).get('/api/sensor/all');
    expect(res.status).toBe(200);
    expect(Array.isArray(res.body)).toBe(true);
  });
});

describe('Alert API', () => {
  test('GET /api/alert/all returns 200 with alert list', async () => {
    const res = await request(app).get('/api/alert/all');
    expect(res.status).toBe(200);
    expect(Array.isArray(res.body)).toBe(true);
  });
});