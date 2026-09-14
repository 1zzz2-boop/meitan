/**
 * VR场景可视化页面
 * 采用工业控制室风格的分栏布局：
 * 左侧为主场景视图，右侧为传感器面板，底部为工具栏
 */

import { router } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { promptAction } from '@kit.ArkUI';
import {
  VRInterfaceService,
  VRSceneState,
  VRRenderMode,
  VRInteractionEvent
} from '../services/VRInterfaceService';
import {
  IoTDeviceService,
  SensorData,
  SensorType,
  DeviceStatus
} from '../services/IoTDeviceService';

const DOMAIN = 0x0000;
const TAG = 'VRScenePage';

const PANEL_BG = '#14181F';
const CARD_BG = '#1E242E';
const ACCENT = '#2B63C6';
const ACCENT_LIGHT = '#3D7BE0';

@Entry
@Component
struct VRScenePage {
  @State vrService: VRInterfaceService = VRInterfaceService.getInstance();
  @State iotService: IoTDeviceService = IoTDeviceService.getInstance();

  @State sceneState: VRSceneState = VRSceneState.IDLE;
  @State isVRMode: boolean = false;
  @State panelVisible: boolean = true;
  @State sensors: SensorData[] = [];
  @State selectedSensor: SensorData | null = null;
  @State cameraName: string = '默认视角';
  @State effectLevel: number = 0;

  // 渲染模式
  private renderModes: VRRenderMode[] = [
    VRRenderMode.NORMAL,
    VRRenderMode.STEREO,
    VRRenderMode.PANORAMA,
    VRRenderMode.AR_OVERLAY
  ];
  @State renderModeIndex: number = 0;

  aboutToAppear() {
    this.initializeVRScene();
    hilog.info(DOMAIN, TAG, 'VR场景页面加载完成');
  }

  aboutToDisappear() {
    this.vrService.stopRendering();
    hilog.info(DOMAIN, TAG, 'VR场景页面卸载');
  }

  private async initializeVRScene() {
    this.sceneState = this.vrService.getSceneState();
    this.isVRMode = this.vrService.isVRMode();
    this.sensors = this.iotService.getAllSensors();
    this.vrService.setInteractionCallback((event: VRInteractionEvent) => {
      const sensor = this.sensors.find(s => s.id === event.targetId);
      this.selectedSensor = sensor ?? null;
    });

    if (this.sceneState === VRSceneState.IDLE) {
      const currentScene = this.vrService.getCurrentScene();
      if (currentScene) {
        const success = await this.vrService.loadScene(currentScene);
        if (success) {
          this.sceneState = this.vrService.getSceneState();
          this.startRendering();
        }
      }
    } else if (this.sceneState === VRSceneState.READY) {
      this.startRendering();
    }
  }

  private startRendering() {
    const success = this.vrService.startRendering();
    if (success) {
      this.sceneState = VRSceneState.RENDERING;
    }
  }

  build() {
    Column() {
      // 顶部导航栏
      this.TopBar()

      // 主内容：左侧场景 + 右侧面板
      Row() {
        Stack() {
          // 3D 场景主视图
          this.SceneView()

          // 相机控制（左下）
          this.CameraControls()
        }
        .layoutWeight(1)

        // 右侧传感器面板
        if (this.panelVisible) {
          this.SensorSidebar()
        }
      }
      .layoutWeight(1)

      // 底部工具栏
      this.BottomBar()
    }
    .width('100%')
    .height('100%')
    .backgroundColor(PANEL_BG)
  }

  // 顶部导航栏
  @Builder
  TopBar() {
    Row() {
      Button('← 返回')
        .fontSize(14)
        .fontColor(Color.White)
        .backgroundColor(Color.Transparent)
        .onClick(() => router.back())

      Blank()

      Column() {
        Text('VR数字孪生场景')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.White)
        Text(`${this.getSceneStateText()} · ${this.getRenderModeText()}`)
          .fontSize(11)
          .fontColor('#8A94A6')
          .margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.Center)

      Blank()

      Button(this.isVRMode ? '退出VR' : '进入VR')
        .fontSize(14)
        .fontColor(Color.White)
        .backgroundColor(this.isVRMode ? '#3DDC84' : ACCENT)
        .borderRadius(18)
        .onClick(() => this.toggleVRMode())
    }
    .width('100%')
    .height(60)
    .padding({ left: 12, right: 12 })
    .backgroundColor('rgba(0, 0, 0, 0.55)')
  }

  // 3D 场景主视图
  @Builder
  SceneView() {
    Stack() {
      // 场景背景（模拟矿井隧道）
      Column() {
        // 顶部光源
        Row() {
          Text('☀️')
            .fontSize(16)
            .opacity(0.7)
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .margin({ top: 8 })

        Blank()

        // 井道示意
        Column() {
          Text('⛏️')
            .fontSize(96)
            .opacity(0.95)
          Text('煤矿顶板数字孪生场景')
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.White)
            .margin({ top: 14 })
          Text('选中传感器即查看实时数据与位置')
            .fontSize(12)
            .fontColor('#8A94A6')
            .margin({ top: 6 })
        }

        Blank()

        // 底部地面网格
        Row() {
          ForEach([1, 2, 3, 4, 5, 6], (i: number) => {
            Row()
              .width(2)
              .layoutWeight(1)
              .margin({ left: 4, right: 4 })
              .height(2)
              .backgroundColor('#3A4454')
              .opacity(0.4)
          })
        }
        .width('100%')
        .padding({ left: 12, right: 12, bottom: 10 })
      }
      .width('100%')
      .height('100%')
      .linearGradient({
        angle: 180,
        colors: [['#1B2740', 0], ['#0E1420', 1]]
      })

      // 顶部状态数据 HUD
      Row() {
        this.HudItem('传感器', `${this.sensors.length}`)
        this.HudItem('在线', `${this.countOnline()}`)
        this.HudItem('状态', this.getSceneStateText())
      }
      .position({ x: 12, y: 10 })
      .padding(8)
      .backgroundColor('rgba(0,0,0,0.45)')
      .borderRadius(10)

      // 选中传感器信息
      if (this.selectedSensor) {
        Column() {
          Row() {
            Text(this.getSensorIcon(this.selectedSensor!.type))
              .fontSize(18)
              .margin({ right: 6 })
            Text(this.selectedSensor!.name)
              .fontSize(14)
              .fontWeight(FontWeight.Bold)
              .fontColor(Color.White)
            Blank()
            Text('›')
              .fontSize(18)
              .fontColor('#8A94A6')
          }
          .width('100%')

          Text(`${this.selectedSensor!.value.toFixed(2)} ${this.selectedSensor!.unit}`)
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.selectedSensor!.isWarning ? '#E5484D' : ACCENT_LIGHT)
            .alignSelf(ItemAlign.Start)
            .margin({ top: 8 })
        }
        .width('78%')
        .padding(12)
        .backgroundColor(CARD_BG)
        .borderRadius(12)
        .margin({ bottom: 70 })
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  HudItem(label: string, value: string) {
    Column() {
      Text(label)
        .fontSize(9)
        .fontColor('#8A94A6')
      Text(value)
        .fontSize(13)
        .fontWeight(FontWeight.Bold)
        .fontColor(Color.White)
        .margin({ top: 2 })
    }
    .padding({ left: 8, right: 8 })
  }

  // 相机控制（左下角悬浮）
  @Builder
  CameraControls() {
    Column() {
      Row() {
        this.CamBtn('重置', ACCENT, (): void => this.resetCamera())
        this.CamBtn('俯视图', '#0EA5E9', (): void => this.setTopView())
        this.CamBtn('侧视图', '#10B981', (): void => this.setSideView())
        this.CamBtn('特效', '#F59E0B', (): void => this.cycleEffect())
      }
      .width('100%')

      Text(`当前视角: ${this.cameraName}${this.effectLevel > 0 ? ' · 粒子特效x' + this.effectLevel : ''}`)
        .fontSize(10)
        .fontColor('#8A94A6')
        .alignSelf(ItemAlign.Start)
        .margin({ top: 6 })
    }
    .padding(10)
    .backgroundColor('rgba(0,0,0,0.5)')
    .borderRadius(12)
    .position({ x: 0, y: '100%' })
    .translate({ y: -110, x: 0 })
    .margin({ left: 12 })
  }

  @Builder
  CamBtn(label: string, color: string, onClick: () => void) {
    Button(label)
      .fontSize(11)
      .height(30)
      .fontColor(Color.White)
      .backgroundColor(color)
      .borderRadius(15)
      .layoutWeight(1)
      .margin({ right: 6 })
      .onClick(onClick)
  }

  // 右侧传感器面板
  @Builder
  SensorSidebar() {
    Column() {
      Row() {
        Text('传感器')
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.White)
        Blank()
        Text(this.panelVisible ? '收起' : '展开')
          .fontSize(11)
          .fontColor('#8A94A6')
          .onClick(() => this.panelVisible = false)
      }
      .width('100%')
      .padding({ left: 4, top: 8, bottom: 8 })

      Divider()
        .color('#2A3444')
        .margin({ bottom: 6 })

      List() {
        ForEach(this.sensors, (sensor: SensorData) => {
          ListItem() {
            this.SensorItem(sensor)
          }
        })
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Auto)
    }
    .width(228)
    .height('100%')
    .padding({ left: 10, right: 10, bottom: 10 })
    .backgroundColor('#151A23')
  }

  @Builder
  SensorItem(sensor: SensorData) {
    Column() {
      Row() {
        Text(this.getSensorIcon(sensor.type))
          .fontSize(18)
          .margin({ right: 8 })
        Column() {
          Text(sensor.name)
            .fontSize(12)
            .fontColor(Color.White)
          Text(`${sensor.value.toFixed(2)} ${sensor.unit}`)
            .fontSize(10)
            .fontColor(sensor.isWarning ? '#E5484D' : '#8A94A6')
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        // 在线 / 离线
        Circle()
          .width(8)
          .height(8)
          .fill(sensor.status === DeviceStatus.ONLINE ? '#3DDC84' : '#E5484D')
      }
      .width('100%')

      Divider()
        .color('#242E3B')
        .margin({ top: 8 })
    }
    .width('100%')
    .padding(8)
    .onClick(() => {
      this.selectedSensor = sensor;
      promptAction.showToast({ message: `查看: ${sensor.name}`, duration: 1500 });
    })
  }

  // 底部工具栏
  @Builder
  BottomBar() {
    Column() {
      // 渲染模式选择
      Row() {
        ForEach(this.renderModes, (mode: VRRenderMode, index: number) => {
          Text(this.getRenderModeShort(mode))
            .fontSize(12)
            .fontColor(this.renderModeIndex === index ? ACCENT_LIGHT : '#8A94A6')
            .backgroundColor(this.renderModeIndex === index ? 'rgba(43, 99, 198, 0.25)' : 'transparent')
            .padding({ left: 10, right: 10, top: 5, bottom: 5 })
            .borderRadius(12)
            .onClick(() => this.selectRenderMode(index))
        })
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceEvenly)
      .padding({ top: 8, bottom: 6 })

      Row() {
        Button('📷 截图')
          .layoutWeight(1)
          .height(40)
          .fontSize(13)
          .fontColor(Color.White)
          .backgroundColor(ACCENT)
          .margin({ right: 6 })
          .onClick(() => this.takeSnapshot())

        Button('导出配置')
          .layoutWeight(1)
          .height(40)
          .fontSize(13)
          .fontColor(Color.White)
          .backgroundColor('#10B981')
          .margin({ left: 6, right: 6 })
          .onClick(() => this.exportSceneConfig())

        Button(this.panelVisible ? '隐藏面板' : '显示面板')
          .layoutWeight(1)
          .height(40)
          .fontSize(13)
          .fontColor(Color.White)
          .backgroundColor('#475569')
          .margin({ left: 6 })
          .onClick(() => this.panelVisible = !this.panelVisible)
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 6, bottom: 12 })
    }
    .width('100%')
    .backgroundColor('#12161E')
  }

  private selectRenderMode(index: number) {
    this.renderModeIndex = index;
    const mode = this.renderModes[index];
    this.vrService.setVRMode(mode !== VRRenderMode.NORMAL);
    promptAction.showToast({
      message: `已切换为: ${this.getRenderModeTextFor(mode)}`,
      duration: 1500
    });
  }

  private cycleEffect() {
    this.effectLevel = (this.effectLevel + 1) % 4;
    promptAction.showToast({
      message: this.effectLevel === 0 ? '关闭粒子特效' : `粒子特效已开启，强度 ${this.effectLevel}`,
      duration: 1200
    });
  }

  private toggleVRMode() {
    this.isVRMode = !this.isVRMode;
    this.vrService.setVRMode(this.isVRMode);
    promptAction.showToast({
      message: this.isVRMode ? 'VR模式已开启' : 'VR模式已关闭',
      duration: 1500
    });
  }

  private resetCamera() {
    this.vrService.resetCamera();
    this.cameraName = '默认视角';
    promptAction.showToast({ message: '相机已重置', duration: 1200 });
  }

  private setTopView() {
    this.vrService.setCameraPosition({ x: 0, y: 10, z: 0 });
    this.vrService.setCameraTarget({ x: 0, y: 0, z: 0 });
    this.cameraName = '俯视图';
    promptAction.showToast({ message: '已切换到俯视图', duration: 1200 });
  }

  private setSideView() {
    this.vrService.setCameraPosition({ x: 10, y: 2, z: 0 });
    this.vrService.setCameraTarget({ x: 0, y: 2, z: 0 });
    this.cameraName = '侧视图';
    promptAction.showToast({ message: '已切换到侧视图', duration: 1200 });
  }

  private async takeSnapshot() {
    const path = await this.vrService.exportSnapshot();
    promptAction.showToast({
      message: path ? `截图已保存: ${path}` : '截图失败',
      duration: 2000
    });
  }

  private exportSceneConfig() {
    const config = this.vrService.exportSceneConfig();
    promptAction.showToast({ message: '场景配置已导出', duration: 1500 });
    hilog.info(DOMAIN, TAG, '场景配置: %{public}s', config);
  }

  private countOnline(): number {
    return this.sensors.filter(s => s.status === DeviceStatus.ONLINE).length;
  }

  private getSceneStateText(): string {
    switch (this.sceneState) {
      case VRSceneState.IDLE: return '空闲';
      case VRSceneState.LOADING: return '加载中';
      case VRSceneState.READY: return '就绪';
      case VRSceneState.RENDERING: return '渲染中';
      case VRSceneState.ERROR: return '错误';
      default: return '未知';
    }
  }

  private getRenderMode(): VRRenderMode {
    return this.renderModes[this.renderModeIndex];
  }

  private getRenderModeText(): string {
    return this.getRenderModeTextFor(this.getRenderMode());
  }

  private getRenderModeTextFor(mode: VRRenderMode): string {
    switch (mode) {
      case VRRenderMode.NORMAL: return '普通模式';
      case VRRenderMode.STEREO: return '立体模式';
      case VRRenderMode.PANORAMA: return '全景模式';
      case VRRenderMode.AR_OVERLAY: return 'AR叠加模式';
      default: return '未知';
    }
  }

  private getRenderModeShort(mode: VRRenderMode): string {
    switch (mode) {
      case VRRenderMode.NORMAL: return '标准';
      case VRRenderMode.STEREO: return '立体';
      case VRRenderMode.PANORAMA: return '全景';
      case VRRenderMode.AR_OVERLAY: return 'AR';
      default: return '?';
    }
  }

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
}