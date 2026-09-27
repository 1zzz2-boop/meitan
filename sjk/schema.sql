-- ============================================================
-- 煤矿顶板灾变智能预警与可视化决策系统 · 数据库脚本
-- 目标数据库：PostgreSQL 12  (E:\jindieAI\sqlapp 实例, localhost:5432)
-- 数据库名称：coal_mine_guard
--
-- 执行方式（在 PowerShell 中）：
--   $env:PGPASSWORD='123456'
--   1) 建库（如未创建）：
--      & "E:\jindieAI\sqlapp\bin\createdb.exe" -U postgres -h localhost coal_mine_guard
--   2) 执行本脚本：
--      & "E:\jindieAI\sqlapp\bin\psql.exe" -U postgres -h localhost -d coal_mine_guard -f sjk\schema.sql
-- ============================================================

SET client_encoding TO 'UTF8';

-- ---------- 矿井 ----------
DROP TABLE IF EXISTS dispatch_records;
DROP TABLE IF EXISTS analysis_reports;
DROP TABLE IF EXISTS threshold_config;
DROP TABLE IF EXISTS alerts;
DROP TABLE IF EXISTS sensor_history;
DROP TABLE IF EXISTS sensors;
DROP TABLE IF EXISTS users;
DROP TABLE IF EXISTS mine;

CREATE TABLE mine (
    id          SERIAL PRIMARY KEY,
    name        VARCHAR(128) NOT NULL,
    location    VARCHAR(128),
    owner       VARCHAR(128),
    status      VARCHAR(32)  DEFAULT 'RUNNING'
);

-- ---------- 用户（含三端角色） ----------
CREATE TABLE users (
    id          SERIAL PRIMARY KEY,
    username    VARCHAR(64) UNIQUE NOT NULL,
    password    VARCHAR(255) NOT NULL,
    role        VARCHAR(32) NOT NULL CHECK (role IN ('enterprise','thinktank','supervision')),
    display_name VARCHAR(64),
    end_name    VARCHAR(64),
    mine_id     INTEGER REFERENCES mine(id),
    created_at  TIMESTAMP DEFAULT now()
);
-- 密码列放宽以容纳加盐哈希（scrypt$salt$hash，约 168 字符）；已部署库需执行此行
ALTER TABLE users ALTER COLUMN password TYPE VARCHAR(255);

-- ---------- 审计日志（操作留痕） ----------
CREATE TABLE IF NOT EXISTS audit_logs (
    id          SERIAL PRIMARY KEY,
    action      VARCHAR(64) NOT NULL,
    username    VARCHAR(64),
    role        VARCHAR(32),
    ip          VARCHAR(64),
    detail      TEXT,
    created_at  TIMESTAMP DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_audit_created ON audit_logs(created_at);

-- ---------- 传感器 ----------
CREATE TABLE sensors (
    id          VARCHAR(64) PRIMARY KEY,
    type        VARCHAR(64) NOT NULL,
    name        VARCHAR(64) NOT NULL,
    unit        VARCHAR(16),
    threshold   FLOAT,
    value       FLOAT,
    status      VARCHAR(16) DEFAULT 'ONLINE',
    description VARCHAR(255),
    mine_id     INTEGER REFERENCES mine(id),
    updated_at  TIMESTAMP DEFAULT now()
);

-- ---------- 传感器历史数据 ----------
CREATE TABLE sensor_history (
    id          BIGSERIAL PRIMARY KEY,
    sensor_id   VARCHAR(64) NOT NULL,
    value       FLOAT NOT NULL,
    source      VARCHAR(32),
    source_addr VARCHAR(128),
    created_at  TIMESTAMP DEFAULT now()
);
CREATE INDEX idx_history_source ON sensor_history(source);
CREATE INDEX idx_history_sensor ON sensor_history(sensor_id, created_at DESC);

-- ---------- 历史数据归档（P2-3.7，超过 ARCHIVE_DAYS 的明细按聚合迁入） ----------
CREATE TABLE IF NOT EXISTS sensor_history_archive (
    dim         VARCHAR(16) NOT NULL CHECK (dim IN ('hour', 'day')),
    sensor_id   VARCHAR(64) NOT NULL,
    bucket_start TIMESTAMP NOT NULL,
    avg         FLOAT,
    min         FLOAT,
    max         FLOAT,
    samples     BIGINT DEFAULT 0,
    updated_at  TIMESTAMP DEFAULT now(),
    PRIMARY KEY (dim, sensor_id, bucket_start)
);
CREATE INDEX IF NOT EXISTS idx_archive_sensor ON sensor_history_archive(sensor_id, bucket_start);

-- ---------- 预警 ----------
CREATE TABLE alerts (
    id          VARCHAR(64) PRIMARY KEY,
    sensor_id   VARCHAR(64),
    sensor_name VARCHAR(64),
    level       VARCHAR(16) CHECK (level IN ('RED','ORANGE','YELLOW')),
    message     VARCHAR(255),
    value       FLOAT,
    threshold   FLOAT,
    handled     BOOLEAN DEFAULT FALSE,
    handler     VARCHAR(64),
    handled_at  TIMESTAMP,
    mine_id     INTEGER REFERENCES mine(id),
    -- 预警升级状态机
    raised_count INT DEFAULT 0,          -- 已升级次数
    escalated_at TIMESTAMP,              -- 当前级别起始时间（用于判定是否触发升级）
    escalation_note VARCHAR(255),        -- 升级说明（如「已上报监管端」）
    created_at  TIMESTAMP DEFAULT now()
);
CREATE INDEX idx_alerts_created ON alerts(created_at DESC);

-- ---------- 预警阈值配置 ----------
CREATE TABLE threshold_config (
    key_name    VARCHAR(64) PRIMARY KEY,
    name        VARCHAR(64) NOT NULL,
    value       FLOAT NOT NULL,
    unit        VARCHAR(16),
    description VARCHAR(255)
);

-- ---------- 智库端分析报告 ----------
CREATE TABLE analysis_reports (
    id          SERIAL PRIMARY KEY,
    title       VARCHAR(200) NOT NULL,
    author      VARCHAR(64),
    content     TEXT,
    created_at  TIMESTAMP DEFAULT now()
);

-- ---------- 监管端应急调度记录 ----------
CREATE TABLE dispatch_records (
    id          SERIAL PRIMARY KEY,
    title       VARCHAR(200) NOT NULL,
    level       VARCHAR(16),
    content     TEXT,
    target_mine VARCHAR(128),
    status      VARCHAR(32) DEFAULT 'PENDING',
    creator     VARCHAR(64),
    created_at  TIMESTAMP DEFAULT now()
);

-- ============================================================
-- 种子数据
-- ============================================================

INSERT INTO mine (name, location, owner) VALUES
('中建筑港青岛西海岸示范矿井', '山东·青岛·西海岸新区', '中建筑港集团青岛西海岸新区分公司');

INSERT INTO users (username, password, role, display_name, end_name, mine_id) VALUES
('admin',     '123456', 'enterprise', '系统管理员', '企业端 · 生产矿井', 1),
('mine_super','123456', 'enterprise', '矿井值班员', '企业端 · 生产矿井', 1),
('t_admin',   '123456', 'thinktank',  '智库研究员', '智库端 · 高校科研机构', NULL),
('s_admin',   '123456', 'supervision','监管调度员', '监管端 · 集团/安监部门', NULL);

INSERT INTO sensors (id, type, name, unit, threshold, value, status, description, mine_id) VALUES
('sensor_water_pressure',  'WATER_PRESSURE',       '水压传感器',   'MPa', 1.0,   0.85,  'ONLINE', '检测矿洞渗水情况', 1),
('sensor_film_pressure',   'FILM_PRESSURE',        '薄膜传感器',   'kN',  15.0,  12.5,  'ONLINE', '顶板压力检测', 1),
('sensor_temperature',     'TEMPERATURE',          'DHT11温度',    '℃',  35.0,  25.3,  'ONLINE', '环境温度监测', 1),
('sensor_humidity',        'HUMIDITY',             'DHT11湿度',    '%',  85.0,  68.2,  'ONLINE', '环境湿度监测', 1),
('sensor_co2',             'CO2_LEVEL',            'CO2浓度',      '%',  0.05,  0.04,  'ONLINE', '空气质量监测', 1),
('sensor_so2',             'SO2_LEVEL',            'SO2浓度',      '%',  0.002, 0.001, 'ONLINE', '有害气体监测', 1),
('sensor_ultrasonic',      'ULTRASONIC_DISTANCE',  '超声波测距',   'm',  2.5,   2.85,  'ONLINE', '顶板下沉监测', 1),
('sensor_strain',          'STRAIN_GAUGE',         '锚杆弯折',     'mm', 0.05,  0.02,  'ONLINE', '锚杆应力监测', 1),
('sensor_vibration',       'VIBRATION',            '震动传感器',   'g',  0.5,   0.15,  'ONLINE', '冲击地压监测', 1),
('module_lora',            'LORA_MODULE',          'LoRa通讯模块', '',   NULL,  1,     'ONLINE', '数据传输模块', 1),
('display_oled',           'OLED_DISPLAY',         'OLED显示屏',   '',   NULL,  1,     'ONLINE', '数据显示模块', 1);

INSERT INTO threshold_config (key_name, name, value, unit, description) VALUES
('water_pressure', '水压阈值',   1.0, 'MPa', '矿洞渗水压力超过该阈值触发预警，默认 1.0 MPa'),
('roof_sink',      '顶板下沉阈值', 2.5, 'm',   '顶板下沉量超过该阈值即预警，默认 2.5 m'),
('vibration',      '震动阈值',   0.5, 'g',   '震动强度超过该阈值即预警，默认 0.5 g');

-- 顶板压力 24 小时历史曲线（模拟传感器历史数据）
INSERT INTO sensor_history (sensor_id, value, created_at) VALUES
('sensor_film_pressure', 46, now() - interval '24 hours'),
('sensor_film_pressure', 58, now() - interval '22 hours'),
('sensor_film_pressure', 50, now() - interval '20 hours'),
('sensor_film_pressure', 62, now() - interval '18 hours'),
('sensor_film_pressure', 54, now() - interval '16 hours'),
('sensor_film_pressure', 71, now() - interval '14 hours'),
('sensor_film_pressure', 66, now() - interval '12 hours'),
('sensor_film_pressure', 78, now() - interval '10 hours'),
('sensor_film_pressure', 69, now() - interval '8 hours'),
('sensor_film_pressure', 84, now() - interval '6 hours'),
('sensor_film_pressure', 90, now() - interval '4 hours'),
('sensor_film_pressure', 76, now() - interval '2 hours');

-- 初始分析报告
INSERT INTO analysis_reports (title, author, content) VALUES
('顶板压力周期性规律分析（第 24 期）', '智库端·矿压研究组',
 '近 24 小时顶板压力平均 70 kN，峰值出现于回采作业时段（18-22 时）。压力与采动影响呈正相关，当前处于安全区间。建议对 80-90 kN 区间加密采样，进一步校验数字孪生 AI 模型预警阈值。');

-- 初始应急调度记录
INSERT INTO dispatch_records (title, level, content, target_mine, status, creator) VALUES
('回采工作面冲击地压风险专项检查', 'ORANGE',
 '针对回采工作面震动传感器频次升高，要求企业端立即开展专项检查并提交处置反馈。',
 '中建筑港青岛西海岸示范矿井', 'IN_PROGRESS', '监管调度员');
