# API 接口文档
## 深地智控 · 煤矿顶板灾变智能预警与可视化决策系统 · 后端

| 项 | 内容 |
|---|---|
| 版本 | v2.0.0（与根接口返回一致） |
| Base URL | `http://<host>:3000`（HTTPS 可选 :8443） |
| 数据格式 | JSON |
| 日期 | 2026-09-14 |

## 1. 通用约定

- **鉴权**：除标注「公开」的接口外，均需请求头 `Authorization: Bearer <token>`（token 由登录返回，服务端会话校验）。
- **角色**：`enterprise` / `supervision` / `thinktank`。
- **错误格式**：`{ "error": "类型", "message": "中文提示" }`。
- **状态码**：200 成功；201 创建；400 参数错误；401 未登录/凭证失效；403 无权限；404 资源不存在；409 冲突；429 限流；500 服务器错误。

## 2. 公开接口

### 2.1 验证码 `GET /api/auth/captcha`
- 限频：同 IP 30 次/分钟（超限 429）。
- 响应：`{ id, image }`（image 为 base64 图片）。

### 2.2 登录 `POST /api/auth/login`
- Body：`{ username, password, captchaId, captchaCode }`
- 限频：账号 5 次/分钟 + IP 20 次/分钟，超限 429。
- 成功：`{ ok: true, token, user: { id, username, role, endName, ... } }`
- 失败：401，message 区分「验证码错误/用户名或密码错误」，调用方需重新获取验证码。

### 2.3 注册 `POST /api/auth/register`
- Body：`{ username, password, role, display_name }`
- 成功 201：`{ ok: true, user }`；失败 409。

### 2.4 修改密码 `POST /api/auth/change-password`
- Body：`{ username, oldPassword, newPassword }`
- 响应：`{ success, message }`（200，便于鸿蒙端直接展示提示）。

### 2.5 系统信息 `GET /api/system/info`
- 响应：系统名称、版本、环境信息。

## 3. 健康检查（公开）

| 方法 | 路径 | 说明 |
|---|---|---|
| GET | `/api/health` | 基础健康，`{ status: 'ok' }` 等 |
| GET | `/api/health/detailed` | 数据库/Redis/模拟器/MQTT 桥接等细项状态 |

## 4. 传感器（需登录）

| 方法 | 路径 | 角色 | 说明 |
|---|---|---|---|
| GET | `/api/sensor/all` | 任意登录 | 全部传感器列表（含阈值、单位） |
| GET | `/api/sensor/stats` | 任意登录 | 汇总统计（总数/在线/预警/离线） |
| GET | `/api/sensor/thresholds` | 任意登录 | 阈值配置列表 |
| GET | `/api/sensor/type/:type` | 任意登录 | 按类型筛选 |
| GET | `/api/sensor/:id` | 任意登录 | 单个传感器，不存在 404 |
| POST | `/api/sensor/update` | 任意登录 | Body `{ sensorId, value }`；立即广播 sensor_update；不存在 404 |
| POST | `/api/sensor/thresholds` | enterprise/supervision | Body `{ keyName, value }`；写审计日志 |

**传感器字段示例**：`{ id, name, type, unit, value, threshold, mine, location, status, update_time, ... }`

**阈值方向规则**：`ULTRASONIC_DISTANCE` 为 `value < threshold` 预警；其余类型为 `value > threshold` 预警（前端以 `thresholdDir()` 展示）。

## 5. 预警（需登录）

| 方法 | 路径 | 角色 | 说明 |
|---|---|---|---|
| GET | `/api/alert/all` | 任意登录 | 全部预警 |
| GET | `/api/alert/unhandled` | 任意登录 | 未处置预警 |
| GET | `/api/alert/unhandled/count` | 任意登录 | `{ count }` |
| POST | `/api/alert/handle` | enterprise/supervision | Body `{ alertId, handledBy }`；写审计 |
| POST | `/api/alert/clear` | enterprise/supervision | 清空全部预警；写审计 |

## 6. 分析（需登录）

| 方法 | 路径 | 角色 | 说明 |
|---|---|---|---|
| GET | `/api/analysis/trend` | 任意登录 | 趋势数据 |
| GET | `/api/analysis/threat` | 任意登录 | 威胁评估 |
| GET | `/api/analysis/stats` | 任意登录 | 分析统计 |
| GET | `/api/analysis/model-metrics` | 任意登录 | 模型精度指标 |
| GET | `/api/analysis/reports` | 任意登录 | 报告列表 |
| POST | `/api/analysis/retrain` | thinktank | 触发模型重训 |
| POST | `/api/analysis/reports` | thinktank | 生成报告 |

## 7. 监管（需登录）

| 方法 | 路径 | 角色 | 说明 |
|---|---|---|---|
| GET | `/api/supervision/mines` | 任意登录 | 矿井列表 |
| GET | `/api/supervision/overview` | 任意登录 | 监管概览 |
| GET | `/api/supervision/dispatches` | 任意登录 | 派单列表 |
| POST | `/api/supervision/dispatches` | **仅 supervision** | Body `{ title, target_mine, ... }`；201；写审计 |
| POST | `/api/supervision/dispatches/status` | **仅 supervision** | Body `{ id, status }`；写审计 |

## 8. 用户管理（需登录）

| 方法 | 路径 | 角色 | 说明 |
|---|---|---|---|
| GET | `/api/users` | 仅 supervision | 用户列表 |
| GET | `/api/users/:id` | 仅 supervision | 用户详情 |
| POST | `/api/users` | 仅 supervision | 创建用户 |
| PUT | `/api/users/:id` | 登录（本人/管理） | 更新用户 |
| DELETE | `/api/users/:id` | 仅 supervision | 删除用户 |

## 9. 审计（需登录）

| 方法 | 路径 | 角色 | 说明 |
|---|---|---|---|
| GET | `/api/audit` | 仅 supervision | 审计日志列表 |
| GET | `/api/audit/me` | 任意登录 | 当前用户相关日志 |

## 10. WebSocket 实时通道（:8080）

连接：`ws://<host>:8080?clientId=<id>`（clientId 可选）。

服务端主动推送（JSON `{ type, payload }`）：
| type | payload | 触发时机 |
|---|---|---|
| `connection_status` | `{ connected, clientId, message }` | 连接建立 |
| `sensor_update` | 传感器数组 | 传感器数据更新/手动干预/MQTT 入库 |
| `sensor_stats` | `{ total, online, warning, offline, ... }` | 统计变化 |
| `alert_update` | 预警对象/列表 | 预警产生或处置 |
| `pong` | `{ t }` | 客户端发 `{ "type": "ping" }` 的应答 |

## 11. 常见调用序列

1. `GET /api/auth/captcha` → 2. `POST /api/auth/login`（得到 token）→ 3. 携带 `Authorization: Bearer <token>` 调业务接口；前端另开 `ws://host:8080` 收实时数据。
