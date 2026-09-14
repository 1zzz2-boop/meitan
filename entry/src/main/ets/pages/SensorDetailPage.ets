/**
 * 传感器详情页面
 * 显示单个传感器的详细信息和历史数据
 */

import { router } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { promptAction } from '@kit.ArkUI';
import { 
  IoTDeviceService, 
  SensorData,
  SensorType,
  DeviceStatus,
  AlertInfo,
  AlertLevel
} from '../services/IoTDeviceService';
import { 
  VRInterfaceService,
  Vector3D
} from '../services/VRInterfaceService';
import {
  IoTControlService,
  SensorCommand,
  WorkMode,
  ControlRecord
} from '../services/IoTControlService';
import { CommandResponse } from '../services/IoTConnectionInterface';

const DOMAIN = 0x0000;
const TAG = 'SensorDetailPage';

// 导出数据接口
interface SensorExportData {
  sensor: SensorData | null;
  alerts: AlertInfo[];
  exportTime: string;
}

@Entry
@Component
struct SensorDetailPage {
  @State sensorId: string = '';
  @State sensor: SensorData | null = null;
  @State alerts: AlertInfo[] = [];
  @State isLoading: boolean = true;
  
  // 控制相关状态
  @State controlHistory: ControlRecord[] = [];
  @State newThreshold: number = 0;
  @State newInterval: number = 10000;
  @State selectedWorkMode: WorkMode = WorkMode.NORMAL;
  
  private iotService: IoTDeviceService = IoTDeviceService.getInstance();
  private vrService: VRInterfaceService = VRInterfaceService.getInstance();
  private controlService: IoTControlService = IoTControlService.getInstance();
  
  aboutToAppear() {
    // 从路由参数获取传感器ID
    const params = router.getParams() as Record<string, string>;
    if (params && params['sensorId']) {
      this.sensorId = params['sensorId'];
      this.loadSensorData();
    } else {
      promptAction.showToast({
        message: '传感器ID无效',
        duration: 2000
      });
      setTimeout(() => {
        router.back();
      }, 1500);
    }
  }
  
  // 加载传感器数据
  private loadSensorData() {
    this.isLoading = true;
    
    // 获取传感器数据
    const sensorData = this.iotService.getSensorById(this.sensorId);
    this.sensor = sensorData ?? null;
    
    if (!this.sensor) {
      promptAction.showToast({
        message: '传感器不存在',
        duration: 2000
      });
      setTimeout(() => {
        router.back();
      }, 1500);
      return;
    }
    
    // 获取相关预警
    this.alerts = this.iotService.getAllAlerts()
      .filter(alert => alert.sensorId === this.sensorId);
    
    this.isLoading = false;
    hilog.info(DOMAIN, TAG, '传感器数据加载完成: %{public}s', this.sensorId);
  }
  
  build() {
    Column() {
      // 顶部导航栏
      this.TopNavigationBar()
      
      if (this.isLoading) {
        // 加载中状态
        this.LoadingView()
      } else if (this.sensor) {
        // 传感器详情
        Scroll() {
          Column() {
            // 传感器基本信息
            this.SensorInfoCard()
            
            // 实时数据卡片
            this.RealTimeDataCard()
            
            // 历史数据图表
            this.HistoryDataChart()
            
            // 预警记录
            this.AlertHistoryCard()
            
            // 操作按钮
            this.ActionButtons()
            
            // 设备控制面板
            this.ControlPanelView()
          }
          .width('100%')
          .padding(16)
        }
        .layoutWeight(1)
      } else {
        // 错误状态
        this.ErrorView()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F4F6FB')
  }
  
  // 顶部导航栏
  @Builder
  TopNavigationBar() {
    Row() {
      Button('‹')
        .width(36)
        .height(36)
        .fontSize(22)
        .fontColor(Color.White)
        .backgroundColor('#33FFFFFF')
        .borderRadius(18)
        .onClick(() => router.back())

      Blank()

      Column() {
        Text('传感器详情')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.White)
        Text(this.sensor ? this.sensor.name : '')
          .fontSize(11)
          .fontColor('#CCFFFFFF')
          .margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.Center)

      Blank()

      Button('VR查看')
        .fontSize(13)
        .fontColor(Color.White)
        .backgroundColor('#33FFFFFF')
        .borderRadius(16)
        .height(34)
        .onClick(() => this.viewInVR())
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 48, bottom: 16 })
    .linearGradient({
      angle: 180,
      colors: [
        ['#1B3B6F', 0.0],
        ['#2B63C6', 0.6],
        ['#147BDB', 1.0]
      ]
    })
  }
  
  // 加载中视图
  @Builder
  LoadingView() {
    Column() {
      Text('加载中...')
        .fontSize(16)
        .fontColor('#666666')
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }
  
  // 错误视图
  @Builder
  ErrorView() {
    Column() {
      Text('⚠️')
        .fontSize(48)
        .margin({ bottom: 16 })
      
      Text('传感器数据加载失败')
        .fontSize(16)
        .fontColor('#FF4D4F')
        .margin({ bottom: 16 })
      
      Button('返回')
        .onClick(() => {
          router.back();
        })
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }
  
  // 传感器基本信息卡片
  @Builder
  SensorInfoCard() {
    Column() {
      Row() {
        Text(this.getSensorIcon(this.sensor!.type))
          .fontSize(48)
          .margin({ right: 16 })
        
        Column() {
          Text(this.sensor!.name)
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor('#333333')
            .margin({ bottom: 8 })
          
          Text(this.sensor!.description || '暂无描述')
            .fontSize(14)
            .fontColor('#666666')
            .margin({ bottom: 8 })
          
          Row() {
            Text('状态:')
              .fontSize(12)
              .fontColor('#666666')
            
            Text(this.getDeviceStatusText(this.sensor!.status))
              .fontSize(12)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.sensor!.status === DeviceStatus.ONLINE ? '#07C160' : '#FF4D4F')
              .margin({ left: 4 })
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
    }
    .width('100%')
    .padding(16)
    .backgroundColor(Color.White)
    .borderRadius(12)
    .margin({ bottom: 16 })
  }
  
  // 实时数据卡片
  @Builder
  RealTimeDataCard() {
    Column() {
      Text('实时数据')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor('#333333')
        .margin({ bottom: 16 })
      
      Row() {
        Column() {
          Text(`${this.sensor!.value.toFixed(2)}`)
            .fontSize(36)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.sensor!.isWarning ? '#FF4D4F' : '#07C160')
          
          Text(this.sensor!.unit)
            .fontSize(16)
            .fontColor('#666666')
            .margin({ top: 4 })
        }
        .layoutWeight(1)
        
        if (this.sensor!.threshold) {
          Divider()
            .vertical(true)
            .height(60)
            .color('#E8E8E8')
            .margin({ left: 16, right: 16 })
          
          Column() {
            Text('预警阈值')
              .fontSize(12)
              .fontColor('#666666')
            
            Text(`${this.sensor!.threshold.toFixed(2)} ${this.sensor!.unit}`)
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor('#FAAD14')
              .margin({ top: 4 })
          }
          .layoutWeight(1)
        }
      }
      .width('100%')
      
      // 预警状态
      if (this.sensor!.isWarning) {
        Row() {
          Text('⚠️')
            .fontSize(20)
            .margin({ right: 8 })
          
          Text('当前值超过预警阈值')
            .fontSize(14)
            .fontColor('#FF4D4F')
        }
        .width('100%')
        .padding(12)
        .backgroundColor('#FFF1F0')
        .borderRadius(8)
        .margin({ top: 16 })
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor(Color.White)
    .borderRadius(12)
    .margin({ bottom: 16 })
  }
  
  // 历史数据图表
  @Builder
  HistoryDataChart() {
    Column() {
      Text('历史数据趋势')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor('#333333')
        .margin({ bottom: 16 })
      
      // 模拟历史数据图表
      Column() {
        Row() {
          ForEach([0.8, 0.85, 0.9, 0.88, 0.92, 0.87, 0.84, 0.86], (value: number) => {
            Column()
              .width(30)
              .height(value * 150)
              .backgroundColor(this.sensor!.isWarning ? '#FF4D4F' : '#007DFF')
              .borderRadius(4)
          })
        }
        .width('100%')
        .justifyContent(FlexAlign.SpaceBetween)
        .padding({ left: 16, right: 16 })
      }
      .width('100%')
      .height(200)
      .justifyContent(FlexAlign.End)
      .padding(16)
      .backgroundColor('#F5F5F5')
      .borderRadius(8)
      
      // 时间轴标签
      Row() {
        Text('8小时前')
          .fontSize(10)
          .fontColor('#999999')
        
        Blank()
        
        Text('现在')
          .fontSize(10)
          .fontColor('#999999')
      }
      .width('100%')
      .margin({ top: 8 })
    }
    .width('100%')
    .padding(16)
    .backgroundColor(Color.White)
    .borderRadius(12)
    .margin({ bottom: 16 })
  }
  
  // 预警历史卡片
  @Builder
  AlertHistoryCard() {
    Column() {
      Text('预警记录')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor('#333333')
        .margin({ bottom: 16 })
      
      if (this.alerts.length === 0) {
        Column() {
          Text('✅')
            .fontSize(32)
            .margin({ bottom: 8 })
          
          Text('暂无预警记录')
            .fontSize(14)
            .fontColor('#666666')
        }
        .width('100%')
        .padding(32)
      } else {
        List() {
          ForEach(this.alerts, (alert: AlertInfo) => {
            ListItem() {
              this.AlertItem(alert)
            }
          })
        }
        .width('100%')
        .height(Math.min(this.alerts.length * 80, 240))
        .scrollBar(BarState.Auto)
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor(Color.White)
    .borderRadius(12)
    .margin({ bottom: 16 })
  }
  
  // 预警项
  @Builder
  AlertItem(alert: AlertInfo) {
    Row() {
      Column() {
        Text(alert.level)
          .fontSize(12)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.getAlertLevelColor(alert.level))
        
        Text(this.formatTimestamp(alert.timestamp))
          .fontSize(10)
          .fontColor('#999999')
          .margin({ top: 4 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      
      Column() {
        Text(`值: ${alert.value.toFixed(2)}`)
          .fontSize(12)
          .fontColor('#333333')
        
        Text(`阈值: ${alert.threshold.toFixed(2)}`)
          .fontSize(10)
          .fontColor('#666666')
          .margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.End)
      
      if (!alert.isHandled) {
        Button('处理')
          .fontSize(10)
          .height(24)
          .backgroundColor('#007DFF')
          .margin({ left: 8 })
          .onClick(() => {
            this.handleAlert(alert.id);
          })
      } else {
        Text('已处理')
          .fontSize(10)
          .fontColor('#07C160')
          .margin({ left: 8 })
      }
    }
    .width('100%')
    .padding(12)
    .backgroundColor('#F5F5F5')
    .borderRadius(8)
    .margin({ bottom: 8 })
  }
  
  // 操作按钮
  @Builder
  ActionButtons() {
    Column() {
      Row() {
        Button('在VR中查看')
          .layoutWeight(1)
          .height(44)
          .backgroundColor('#007DFF')
          .onClick(() => {
            this.viewInVR();
          })
          .margin({ right: 8 })
        
        Button('导出数据')
          .layoutWeight(1)
          .height(44)
          .backgroundColor('#07C160')
          .onClick(() => {
            this.exportData();
          })
          .margin({ left: 8 })
      }
      .width('100%')
      .margin({ bottom: 12 })
      
      Button('刷新数据')
        .width('100%')
        .height(44)
        .backgroundColor('#FAAD14')
        .onClick(() => {
          this.refreshData();
        })
    }
    .width('100%')
  }
  
  // 在VR中查看
  private viewInVR() {
    const success = this.vrService.focusOnSensor(this.sensorId);
    if (success) {
      router.pushUrl({
        url: 'pages/VRScenePage'
      });
    } else {
      promptAction.showToast({
        message: '传感器VR配置不存在',
        duration: 2000
      });
    }
  }
  
  // 导出数据
  private exportData() {
    const exportDataObj: SensorExportData = {
      sensor: this.sensor,
      alerts: this.alerts,
      exportTime: new Date().toISOString()
    };
    
    promptAction.showToast({
      message: '数据已导出',
      duration: 2000
    });
    
    hilog.info(DOMAIN, TAG, '传感器数据导出: %{public}s', JSON.stringify(exportDataObj));
  }
  
  // 刷新数据
  private refreshData() {
    this.loadSensorData();
    promptAction.showToast({
      message: '数据已刷新',
      duration: 2000
    });
  }
  
  // 处理预警
  private handleAlert(alertId: string) {
    const success = this.iotService.handleAlert(alertId);
    if (success) {
      this.alerts = this.iotService.getAllAlerts()
        .filter(alert => alert.sensorId === this.sensorId);
      promptAction.showToast({
        message: '预警已处理',
        duration: 2000
      });
    }
  }
  
  // 获取传感器图标
  private getSensorIcon(type: SensorType): string {
    const iconMap: Map<SensorType, string> = new Map([
      [SensorType.WATER_PRESSURE, '💧'],
      [SensorType.FILM_PRESSURE, '🔴'],
      [SensorType.TEMPERATURE, '🌡️'],
      [SensorType.HUMIDITY, '💧'],
      [SensorType.CO2_LEVEL, '💨'],
      [SensorType.SO2_LEVEL, '💨'],
      [SensorType.ULTRASONIC_DISTANCE, '📏'],
      [SensorType.STRAIN_GAUGE, '🔧'],
      [SensorType.VIBRATION, '📳'],
      [SensorType.LORA_MODULE, '📡'],
      [SensorType.OLED_DISPLAY, '📺']
    ]);
    
    return iconMap.get(type) || '📊';
  }
  
  // 获取设备状态文本
  private getDeviceStatusText(status: DeviceStatus): string {
    switch (status) {
      case DeviceStatus.ONLINE:
        return '在线';
      case DeviceStatus.OFFLINE:
        return '离线';
      case DeviceStatus.WARNING:
        return '预警';
      case DeviceStatus.ERROR:
        return '故障';
      default:
        return '未知';
    }
  }
  
  // 获取预警等级颜色
  private getAlertLevelColor(level: AlertLevel): string {
    switch (level) {
      case AlertLevel.RED:
        return '#FF4D4F';
      case AlertLevel.ORANGE:
        return '#FF7A45';
      case AlertLevel.YELLOW:
        return '#FAAD14';
      case AlertLevel.NORMAL:
      default:
        return '#07C160';
    }
  }
  
  // 格式化时间戳
  private formatTimestamp(timestamp: number): string {
    const date = new Date(timestamp);
    return `${date.getMonth() + 1}/${date.getDate()} ${date.getHours()}:${String(date.getMinutes()).padStart(2, '0')}`;
  }
  
  // ========================================
  // 设备控制功能
  // ========================================
  
  // 控制面板
  @Builder
  ControlPanelView() {
    Column() {
      Text('🎛️ 设备控制')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor('#333333')
        .margin({ bottom: 16 })
      
      // 基础控制按钮
      Row() {
        Button('开启')
          .width('22%')
          .backgroundColor('#07C160')
          .onClick(() => this.executeControl(SensorCommand.TURN_ON))
        
        Button('关闭')
          .width('22%')
          .backgroundColor('#FF4D4F')
          .onClick(() => this.executeControl(SensorCommand.TURN_OFF))
        
        Button('重置')
          .width('22%')
          .backgroundColor('#007DFF')
          .onClick(() => this.executeControl(SensorCommand.RESET))
        
        Button('校准')
          .width('22%')
          .backgroundColor('#FF9500')
          .onClick(() => this.executeControl(SensorCommand.CALIBRATE))
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)
      .margin({ bottom: 16 })
      
      // 预警控制
      Row() {
        Button('启用预警')
          .layoutWeight(1)
          .backgroundColor('#FF9500')
          .onClick(() => this.executeControl(SensorCommand.ENABLE_ALERT))
        
        Button('禁用预警')
          .layoutWeight(1)
          .backgroundColor('#8E8E93')
          .margin({ left: 8 })
          .onClick(() => this.executeControl(SensorCommand.DISABLE_ALERT))
        
        Button('测试预警')
          .layoutWeight(1)
          .backgroundColor('#FF3B30')
          .margin({ left: 8 })
          .onClick(() => this.executeControl(SensorCommand.TEST_ALERT))
      }
      .width('100%')
    }
    .width('100%')
    .padding(16)
    .backgroundColor(Color.White)
    .borderRadius(12)
    .margin({ top: 16 })
  }
  
  // 执行控制命令
  private async executeControl(command: string) {
    if (!this.sensor) {
      promptAction.showToast({
        message: '传感器不存在',
        duration: 2000
      });
      return;
    }
    
    promptAction.showToast({
      message: `正在执行: ${command}`,
      duration: 1500
    });
    
    try {
      let response: CommandResponse;
      switch (command) {
        case SensorCommand.TURN_ON:
          response = await this.controlService.turnOn(this.sensor.id);
          break;
        case SensorCommand.TURN_OFF:
          response = await this.controlService.turnOff(this.sensor.id);
          break;
        case SensorCommand.RESET:
          response = await this.controlService.reset(this.sensor.id);
          break;
        case SensorCommand.CALIBRATE:
          response = await this.controlService.calibrate(this.sensor.id);
          break;
        case SensorCommand.ENABLE_ALERT:
          response = await this.controlService.enableAlert(this.sensor.id);
          break;
        case SensorCommand.DISABLE_ALERT:
          response = await this.controlService.disableAlert(this.sensor.id);
          break;
        case SensorCommand.TEST_ALERT:
          response = await this.controlService.testAlert(this.sensor.id);
          break;
        default:
          response = {
            commandId: 'unknown',
            deviceId: this.sensor.id,
            success: false,
            error: '未知命令',
            timestamp: Date.now()
          };
      }
      
      if (response.success) {
        promptAction.showToast({
          message: `${command} 执行成功`,
          duration: 2000
        });
      } else {
        promptAction.showToast({
          message: `${command} 执行失败`,
          duration: 2000
        });
      }
      
      hilog.info(DOMAIN, TAG, '控制命令执行: %{public}s, 结果: %{public}s', 
        command, response.success ? '成功' : '失败');
    } catch (error) {
      const errorMsg = error instanceof Error ? error.message : '未知错误';
      promptAction.showToast({
        message: `执行失败: ${errorMsg}`,
        duration: 2000
      });
    }
  }
}
