# 基于数字孪生的煤矿顶板灾变智能预警与可视化决策系统
## MQTT 互联实施方案（STM32 ⇄ PC ⇄ VR）

> 题目编号：CS-202612 · 攻关方向：深地透明感知 + 智能预警模型（两者结合）
> 依据：手绘架构图（STM32 ⇄ PC 经 MQTT 推流、IP:端口 配置；VR 接 PC 展示）
> 配套演示：综合态势大屏（bigscreen.html）＋ PC 三端（企业端/监管端/智库端）＋ 鸿蒙移动端

---

## 一、为什么要用 MQTT

现有系统由后端**模拟器**造数（`backend/utils/simulator.js`），经 WebSocket 8080 广播到三端与鸿蒙端，适合演示但接不了真机。要接入 STM32 采集的真实传感器数据，MQTT 是最合适的工业物联网协议：

| 特性 | 说明 |
|---|---|
| 发布/订阅解耦 | 设备只发布到主题，后端/VR 各自订阅，互不依赖 |
| 断线重连 | broker 与客户端内置重连机制，适合井下弱网 |
| QoS 分级 | 传感器数据可用 QoS1，控制指令用 QoS1/2 |
| 轻量 | 报头开销极小，STM32 级别资源即可运行 |

**核心价值**：STM32 只认识 `IP:端口 + 主题`，不需要知道系统内部结构；PC 后端只需订阅一个通配主题，即可把真机数据"桥接"进现有数据库与 WebSocket 广播，三端/大屏/鸿蒙/VR 一行不改就能实时看到。

---

## 二、总体架构

```
┌─────────────┐   MQTT 推流    ┌──────────────────────────── PC（上位机） ────────────────────────────┐
│   STM32     │ ─────────────► │  MQTT Broker（1883）                                               │
│ 传感器/网关  │   sensor/x/data│        │ 订阅                                                        │
│  边缘节点    │ ◄───────────── │        ▼                                                          │
│   (WiFi)    │   cmd/x/exec   │  mqtt-bridge（backend/services/mqtt-bridge.js）                     │
└─────────────┘  下行控制      │  写入 DB（sensor / sensor_history）                                   │
                                │  广播 WS 8080（sensor_update / sensor_stats / alert_update）        │
                                └──────────────┬────────────────────────────────────────────────────┘
                                               │ WebSocket / MQTT
                          ┌────────────────────┼───────────────────────────┐
                          ▼                    ▼                           ▼
                   PC 三端 / 大屏         鸿蒙移动端                      VR 端
                  (enterprise/supervision/  (10.0.2.2 或局域网 IP)   (WS 8080 或直连 MQTT)
                   thinktank/bigscreen)
```

| 组件 | 角色 | 协议与地址 | 方向 |
|---|---|---|---|
| STM32 | 数据源（传感器采集 / 边缘计算） | MQTT → `PC_IP:1883` | 上行发布 |
| MQTT Broker | 消息中转（EMQX / Mosquitto） | TCP 1883（TLS 8883） | 双向 |
| PC 后端 | 桥接入库 + 实时广播 | `services/mqtt-bridge.js` | 订阅→转发 |
| PC 三端/大屏 | 展示 | WebSocket `PC_IP:8080` | 收广播 |
| VR 端 | 沉浸展示 / 控制 | WS 8080 或 MQTT.js | 收广播/发指令 |

---

## 三、MQTT 主题与载荷规范

### 3.1 上行主题（与现有 `mqtt-bridge.js` 完全一致）

| 主题 | 载荷 | 说明 |
|---|---|---|
| `sensor/<sensorId>/data` | 纯数值字符串 `12.5` | 最简单 |
| `sensor/<sensorId>/data` | JSON `{"value":12.5}` | 推荐 |
| `sensor/<sensorId>/data` | JSON `{"sensorId":"sensor_x","value":12.5}` | 多路复用同一主题时 |

> `sensorId` 必须是数据库 `sensors` 表里已存在的 id（如 `sensor_film_pressure`），否则桥接会跳过。通配订阅为 `sensor/+/data`。

### 3.2 下行主题（建议扩展，用于 VR/上位机 → STM32 控制）

| 主题 | 载荷 | 说明 |
|---|---|---|
| `sensor/<sensorId>/cmd` | `{"action":"stop"}` 或 `{"action":"start"}` | 远程启停/急停 |
| `sensor/<sensorId>/thr` | `{"threshold":80}` | 阈值下发（与系统阈值配置联动） |
| `sensor/<sensorId>/status` | `{"status":"online"}` / `{"status":"offline"}` | 设备在线状态（配合 Last Will） |

### 3.3 QoS 与保留消息

- 传感器数据：**QoS1**（至少一次，可容忍少量重复）。
- 控制指令：**QoS1/2**（需要幂等处理，建议指令带 `seq` 序号）。
- 设备状态：建议 **retain**（保留最新状态，新订阅者立刻收到）。
- 断线告警：使用 **Last Will**，遗嘱主题 `sensor/<sensorId>/status`，载荷 `{"status":"offline"}`。

---

## 四、PC 端（上位机）要做的操作

### 4.1 安装并启动 MQTT Broker

**方案 A：EMQX（推荐，带 Web 控制台，运维友好）**

```bash
# Windows（已提供安装包/或官网下载）
# 安装后默认监听 1883，控制台 http://localhost:18083 （admin/public 默认账号）

# Deepin / Linux
docker run -d --name emqx -p 1883:1883 -p 18083:18083 emqx/emqx:latest
```

**方案 B：Mosquitto（轻量，适合演示）**

```bash
# Windows：官网下载安装包，安装后默认服务自动启动
netstat -ano | findstr 1883        # 确认 1883 已监听

# Deepin / Linux
sudo apt install -y mosquitto mosquitto-clients
sudo systemctl enable --now mosquitto
```

### 4.2 把 MQTT 桥接接入后端（接线代码）

`backend/services/mqtt-bridge.js` 已实现完整订阅→入库→广播逻辑，但尚未挂到 `server.js`。在 `backend/server.js` 加入两处：

```javascript
// 顶部（第 10 行附近，与其它 require 并列）
const mqttBridge = require('./services/mqtt-bridge');

// startServer() 内部、simulator.start() 旁边
mqttBridge.start();
```

> 桥接服务自带自动重连，broker 未启动时**不会阻塞**后端启动；broker 恢复后自动恢复订阅。

### 4.3 配置环境变量（backend/.env）

```ini
# MQTT 桥接配置（默认即可本地演示）
MQTT_URL=tcp://localhost:1883      # 指向 broker 地址
MQTT_TOPIC=sensor/+/data           # 订阅通配主题
MQTT_USER=                         # 需要鉴权的 broker 填用户名
MQTT_PASS=                         # 需要鉴权的 broker 填密码
```

### 4.4 验证 broker 连通

```bash
# 订阅一个临时主题，能收到即代表 broker 正常
mosquitto_sub -h localhost -p 1883 -t 'test/#' -v
mosquitto_pub -h localhost -p 1883 -t 'test/1' -m 'hello'
```

---

## 五、STM32 设备端要做的操作

### 5.1 硬件与软件栈

| 硬件方案 | 推荐库 | 说明 |
|---|---|---|
| ESP32 / ESP8266 | `PubSubClient`（Arduino） | 自带 WiFi，最省事 |
| STM32 + ESP-01S（AT 指令） | 串口透传 + `AT+CIPSTART` + 自实现 MQTT 报文 | 需要自己拼 MQTT 包，工作量较大 |
| STM32 + W5500（以太网） | 官方 lwIP + MQTT 客户端 | 适合井下有线部署 |

### 5.2 三步让 STM32 连上 PC（对应"开热点 + IP:端口拷入"）

1. **PC 开热点**（Windows）：
   - 设置 → 网络和 Internet → 移动热点 → 开启。
   - `ipconfig` 查看"无线局域网适配器"下的 IPv4，通常为 `192.168.137.1`。
   - 若用路由器/手机热点，则用 `ipconfig`（PC 有线网卡）或手机热点详情里的 IP。
2. **STM32 连同一网络**：把热点的 SSID 与密码写入固件（或设备配置），保证设备与 PC 处于同一网段。
3. **配置 broker 地址**：设备配置里写入 `192.168.137.1:1883`（即"拷入 IP 和端口"）。若用手机热点，则填 PC 在那张网卡上的 IP（同一网络 `ipconfig` 查询，或 `ping PC主机名` 反查）。

> **排障要点**：① Windows 防火墙需放行 1883 入站；② 设备与 PC 必须在**同一网段**（热点场景下 PC 是 `192.168.137.1`，设备通常为 `192.168.137.x`）；③ 热点不要开启"AP 隔离"。

### 5.3 连接与上报代码骨架（ESP32 + PubSubClient）

```cpp
#include <WiFi.h>
#include <PubSubClient.h>

const char* WIFI_SSID = "PC-Hotspot";        // PC 热点 / 路由器 SSID
const char* WIFI_PASS = "12345678";
const char* MQTT_HOST = "192.168.137.1";     // PC（broker）IP —— "拷入的 IP"
const int   MQTT_PORT = 1883;                // 端口

WiFiClient net;
PubSubClient mqtt(net);

void reconnect() {
  while (!mqtt.connected()) {
    if (mqtt.connect("sensor_film_pressure")) {   // clientId = 传感器 ID
      Serial.println("[mqtt] connected");
      // 订阅下行控制主题（VR/上位机 → STM32）
      mqtt.subscribe("sensor/sensor_film_pressure/cmd");
      mqtt.subscribe("sensor/sensor_film_pressure/thr");
    } else {
      delay(2000);   // 2s 后重试（MQTT 内置重连周期可配置）
    }
  }
}

void setup() {
  WiFi.begin(WIFI_SSID, WIFI_PASS);
  mqtt.setServer(MQTT_HOST, MQTT_PORT);
  mqtt.setCallback(onCmd);
}

void loop() {
  if (!mqtt.connected()) reconnect();
  mqtt.loop();

  // 推流：每 2s 发布一次传感器值（JSON 格式，与后端桥接解析一致）
  static unsigned long t = 0;
  if (millis() - t > 2000) {
    t = millis();
    float v = readSensor();   // 读取传感器
    mqtt.publish("sensor/sensor_film_pressure/data",
                 String("{\"value\":") + v + "}", true);   // QoS1 + retain
  }
}

void onCmd(char* topic, byte* payload, unsigned int len) {
  // 解析下行指令：{"action":"stop"} → 执行急停/停采
}
```

### 5.4 断线重连与在线状态

- `PubSubClient` 的 `setKeepAlive` / 自动重连即可满足弱网场景。
- 遗嘱：连接时声明 `will`（`sensor/<id>/status` = `{"status":"offline"}`），设备异常断电时 broker 自动广播离线，后端/大屏据此显示"离线"。

---

## 六、VR 端要做的操作

| 方案 | 实现 | 适用 |
|---|---|---|
| **A. WebSocket（推荐）** | VR 应用（如 WebXR 页面）连 `ws://PC_IP:8080`，复用现有 `sensor_update` / `alert_update` 广播，驱动 3D 场景点位刷新 | 与三端/大屏完全一致的数据语义，改动最小 |
| B. 直连 MQTT | 使用 `MQTT.js`（`mqtt.connect('ws://PC_IP:8083/mqtt')`，需 broker 开启 WebSocket 端口，如 EMQX 默认 8083）订阅 `sensor/+/data` | 需要 VR 直接收发指令、绕开后端时 |

**下行控制**：VR 端通过方案 B 发布到 `sensor/<sensorId>/cmd`（如 `{"action":"stop"}`），STM32 收到后执行急停/调参，形成"沉浸场景 → 设备"闭环。

---

## 七、完整验证流程（把这些操作一步步跑通）

| 步骤 | 操作 | 预期结果 | 失败排查 |
|---|---|---|---|
| 1 | 启动 broker（EMQX/Mosquitto） | `netstat` 看到 1883 监听 | 安装服务未启动，`systemctl start` / 服务管理器 |
| 2 | 按 4.2 接线后启动后端（start-backend.bat） | 日志出现 `[mqtt] broker 已连接`、`已订阅 sensor/+/data` | broker 地址错误、防火墙拦截 |
| 3 | 手动上报验证：`node scripts/mqtt-publisher.js once sensor_film_pressure 12.5` | 日志出现 `[publisher] 发布 ...`，后端收到并入库 | 传感器 id 不存在 → 桥接跳过 |
| 4 | 打开企业端/大屏 | 顶板压力卡显示 12.50，趋势曲线出现该点 | WS 未连（8080）；刷新缓存 `?v=` |
| 5 | 持续推流：`node scripts/mqtt-publisher.js` | 每 2s 数值刷新，多传感器同步上报 | 主题前缀 `sensor/` 拼写 |
| 6 | STM32 固件烧录并连接热点 | 设备上线，大屏出现真机实时值 | 见 5.2 排障要点 |
| 7 | VR 端订阅 WS / MQTT | 3D 场景点位数值与 PC 同步 | CORS/端口、broker WS 端口未开 |
| 8 | 下发控制（可选）：发布 `sensor/x/cmd` | 设备执行急停/阈值变更 | STM32 未订阅 cmd 主题 |

---

## 八、安全与可靠性建议

- **传输加密**：broker 开启 TLS，端口 8883，`MQTT_URL=tls://...`；证书见 `backend/certs/`。
- **鉴权与 ACL**：broker 开启用户名密码，并按设备隔离主题权限（设备只能发布自己的 `sensor/<id>/#`）。
- **消息质量**：上报 QoS1 + 载荷带时间戳；控制指令带 `seq` 序号防重放；设备状态 retain + 遗嘱。
- **降级兼容**：broker 未接入时，现有 `simulator.js` 继续兜底造数，系统不依赖 MQTT 也能完整演示。

---

## 九、与现有代码的对应关系

| 文件 | 作用 |
|---|---|
| `backend/services/mqtt-bridge.js` | 订阅 `sensor/+/data` → 入库 + WS 广播（已就绪，需按 4.2 接线） |
| `backend/scripts/mqtt-publisher.js` | 模拟网关推流 / `once` 手动验证 |
| `backend/server.js` | 后端主入口（需新增两行启动桥接） |
| `backend/utils/simulator.js` | 模拟器造数（与 MQTT 并存，互为兜底） |
| `qianduanyemian/docs/01-总体技术方案报告.md` | 总体架构背景 |
