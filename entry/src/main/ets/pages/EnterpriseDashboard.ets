/**
 * 企业端 · 生产矿井 —— 独立功能主页
 * 模块：综合总览 / 实时监测 / 预警管理 / 数据分析
 * 数据：统一来自 DataStore（真实后端优先，离线模拟兜底）
 */
import { router } from '@kit.ArkUI';
import { promptAction } from '@kit.ArkUI';
import dataPreferences from '@ohos.data.preferences';
import { DataStore } from '../services/DataStore';
import { BackendSensor, BackendAlert, TrendPoint, ThreatItem, ThresholdSetting, apiGetThresholds, apiSetThreshold, clearAuthToken } from '../services/BackendApi';
import { Palette, ThemeMode, paletteFor, modeLabel, ensureThemeInit, switchThemeMode } from '../services/Theme';
import { MineIcon } from '../components/MineIcon';
import { AccountPanel } from '../components/AccountPanel';
import { RiskGauge } from '../components/RiskGauge';
import { ClosedLoop } from '../components/ClosedLoop';
import { FusedTrend } from '../components/FusedTrend';
import { SensorHistoryPanel } from '../components/SensorHistoryPanel';

const ACCENT = '#FF8C2A';

interface TabItem {
  label: string;
  icon: string;
}

@Entry
@Component
struct EnterpriseDashboard {
  @State tabs: TabItem[] = [
    { label: '综合总览', icon: 'dashboard' },
    { label: '实时监测', icon: 'antenna' },
    { label: '预警管理', icon: 'siren' },
    { label: '数据分析', icon: 'trend' },
    { label: '用户管理', icon: 'user' },
    { label: '系统管理', icon: 'settings' }
  ];
  @State current: number = 0;
  @State fresh: number = 0;
  @State userName: string = '企业监控员';
  @State history: BackendSensor | null = null;
  @State thresholds: ThresholdSetting[] = [];
  @State thrInputs: string[] = [];
  @StorageProp('theme_mode') themeMode: number = ThemeMode.NIGHT;

  aboutToAppear() {
    ensureThemeInit(getContext(this));
    this.loadSessionUser();
    DataStore.load();
    DataStore.onChange(() => {
      this.fresh++;
    });
    DataStore.refetch();
    this.loadThresholds();
  }

  private pal(): Palette {
    return paletteFor(this.themeMode as ThemeMode);
  }

  private toggleTheme() {
    switchThemeMode(getContext(this));
  }

  private async loadSessionUser() {
    try {
      const ctx = getContext(this);
      const prefs = await dataPreferences.getPreferences(ctx, 'user_session');
      this.userName = await prefs.get('displayName', '企业监管员') as string;
    } catch (e) {
      this.userName = '企业监管员';
    }
  }

  // 拉取预警阈值配置（多参数可编辑）
  private async loadThresholds() {
    try {
      const list = await apiGetThresholds();
      this.thresholds = list;
      this.thrInputs = list.map((t: ThresholdSetting) => t.value + '');
    } catch (e) {
      console.log('加载阈值配置失败: ' + JSON.stringify(e));
    }
  }

  // 保存单个阈值参数
  private async saveThreshold(index: number) {
    const t = this.thresholds[index];
    if (!t) {
      return;
    }
    const value = Number(this.thrInputs[index]);
    if (isNaN(value) || value <= 0) {
      promptAction.showToast({ message: '请输入有效的阈值数值', duration: 1500 });
      return;
    }
    try {
      await apiSetThreshold(t.key_name, value);
      const updated: ThresholdSetting = {
        id: t.id,
        key_name: t.key_name,
        name: t.name,
        value: value,
        unit: t.unit,
        description: t.description
      };
      this.thresholds[index] = updated;
      this.thresholds = this.thresholds.slice();
      promptAction.showToast({ message: `${t.name} 阈值已更新为 ${value}`, duration: 1500 });
    } catch (e) {
      promptAction.showToast({ message: '阈值保存失败：' + JSON.stringify(e), duration: 2000 });
    }
  }

  // ---------------- 三维孪生 / VR 入口 ----------------
  @Builder
  VrEntryCard() {
    Row() {
      Text('🌐')
        .fontSize(26)
      Column() {
        Text('三维孪生场景 · VR')
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.pal().textMain)
        Text('点击进入顶板三维可视化与 VR 沉浸漫游')
          .fontSize(11)
          .fontColor(this.pal().textDim)
          .margin({ top: 3 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ left: 12 })

      Text('进入 ›')
        .fontSize(12)
        .fontColor(ACCENT)
    }
    .width('100%')
    .padding(14)
    .backgroundColor(this.pal().card)
    .borderRadius(14)
    .border({ width: 1, color: '#22FF8C2A' })
    .margin({ top: 10 })
    .onClick(() => {
      router.pushUrl({ url: 'pages/VRScenePage' });
    })
  }

  // ---------------- 三端协同快捷入口 ----------------
  @Builder
  CollabCard() {
    Row() {
      MineIcon({ name: 'link', iconSize: 20, color: ACCENT })
      Column() {
        Text('三端协同')
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.pal().textMain)
        Text('企业 · 智库 · 监管 联动调度与协同决策')
          .fontSize(11)
          .fontColor(this.pal().textDim)
          .margin({ top: 3 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ left: 12 })

      Text('进入 ›')
        .fontSize(12)
        .fontColor(ACCENT)
    }
    .width('100%')
    .padding(14)
    .backgroundColor(this.pal().card)
    .borderRadius(14)
    .border({ width: 1, color: '#1AFF3B47' })
    .margin({ top: 10 })
    .onClick(() => {
      router.pushUrl({ url: 'pages/CollaborationPage' });
    })
  }

  // ---------------- 预警阈值配置面板 ----------------
  @Builder
  ThresholdPanel() {
    Column() {
      Row() {
        Text('预警阈值配置')
          .fontSize(13)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.pal().textMain)
        Blank()
        Text('多参数')
          .fontSize(10)
          .fontColor(ACCENT)
          .padding({ left: 8, right: 8, top: 2, bottom: 2 })
          .backgroundColor('#22FF8C2A')
          .borderRadius(8)
      }
      .width('100%')
      .margin({ bottom: 8 })

      if (this.thresholds.length === 0) {
        Text('暂无阈值配置')
          .fontSize(12)
          .fontColor(this.pal().textDim)
          .padding(16)
      } else {
        ForEach(this.thresholds, (t: ThresholdSetting, index: number) => {
          this.ThresholdRow(t, index)
        })
        Text('修改后点击「保存」即生效并同步至后端')
          .fontSize(10)
          .fontColor(this.pal().textDim)
          .width('100%')
          .margin({ top: 6 })
      }
    }
    .width('100%')
    .padding(14)
    .backgroundColor(this.pal().card)
    .borderRadius(14)
    .margin({ bottom: 10 })
  }

  @Builder
  ThresholdRow(t: ThresholdSetting, index: number) {
    Row() {
      Column() {
        Text(t.name)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.pal().textMain)
        Text(t.description)
          .fontSize(10)
          .fontColor(this.pal().textDim)
          .margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      TextInput({ text: this.thrInputs[index] || '' })
        .width(86)
        .height(34)
        .type(InputType.Number)
        .backgroundColor(this.pal().field)
        .fontColor(this.pal().textMain)
        .textAlign(TextAlign.Center)
        .onChange((v: string) => {
          this.thrInputs[index] = v;
        })

      Text(t.unit)
        .fontSize(11)
        .fontColor(this.pal().textDim)
        .margin({ left: 6 })

      Text('保存')
        .fontSize(11)
        .fontColor(Color.White)
        .padding({ left: 10, right: 10, top: 5, bottom: 5 })
        .backgroundColor(ACCENT)
        .borderRadius(8)
        .margin({ left: 8 })
        .onClick(() => this.saveThreshold(index))
    }
    .width('100%')
    .padding({ top: 6, bottom: 6 })
  }

  build() {
    Stack() {
      Column() {
      // 顶部状态栏
      Row() {
        Text('‹')
          .fontSize(26)
          .fontColor(this.pal().textMain)
          .onClick(() => router.back())
        Text('企业端 · 生产矿井')
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.pal().textMain)
          .margin({ left: 12 })
        Blank()
        Text(this.userName)
          .fontSize(12)
          .fontColor(this.pal().textDim)
        Text(modeLabel())
          .fontSize(12)
          .fontColor(ACCENT)
          .margin({ left: 14 })
          .onClick(() => this.toggleTheme())
        Text('退出')
          .fontSize(12)
          .fontColor(ACCENT)
          .margin({ left: 14 })
          .onClick(() => this.doLogout())
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 14, bottom: 14 })
      .backgroundColor(this.pal().headerBg)

      // Tab 内容
      Column() {
        if (this.current === 0) {
          this.Overview()
        } else if (this.current === 1) {
          this.Monitor()
        } else if (this.current === 2) {
          this.Alert()
        } else if (this.current === 3) {
          this.Analysis()
        } else if (this.current === 4 || this.current === 5) {
          AccountPanel({
            mode: this.current === 4 ? 1 : 2,
            defaultName: '企业监管员',
            roleText: '企业端',
            accent: ACCENT,
            onProfileSaved: (name: string) => {
              this.userName = name;
            }
          })
        }
      }
      .layoutWeight(1)

      // 底部 Tab 栏
      Row() {
        ForEach(this.tabs, (item: TabItem, index: number) => {
          Column() {
            MineIcon({ name: item.icon, iconSize: 17, color: this.current === index ? ACCENT : this.pal().textDim })
            Text(item.label)
              .fontSize(11)
              .fontColor(this.current === index ? ACCENT : this.pal().textDim)
              .margin({ top: 3 })
            Row()
              .width(20)
              .height(2)
              .borderRadius(1)
              .backgroundColor(this.current === index ? ACCENT : Color.Transparent)
              .margin({ top: 3 })
          }
          .layoutWeight(1)
          .onClick(() => {
            this.current = index;
            if (index === 2) {
              this.loadThresholds();
            }
          })
        })
      }
      .width('100%')
      .padding({ top: 8, bottom: 10 })
      .backgroundColor(this.pal().headerBg)
    }
      .width('100%')
      .height('100%')
      .backgroundColor(this.pal().bgApp)

      if (this.history) {
        this.HistoryOverlay()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.pal().bgApp)
  }

  // ---------------- 历史趋势面板浮层 ----------------
  @Builder
  HistoryOverlay() {
    if (this.history) {
      Stack() {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('#99000000')
        Column() {
          SensorHistoryPanel({
            sensorId: this.history.id,
            sensorName: this.history.name,
            onClose: () => this.history = null
          })
        }
        .width('92%')
        .padding(12)
        .backgroundColor(this.pal().bgApp)
        .borderRadius(16)
      }
      .width('100%')
      .height('100%')
      .onClick(() => this.history = null)
    }
  }

  private doLogout() {
    this.clearSession();
    router.clear();
    router.replaceUrl({ url: 'pages/LoginPage' });
  }

  private async clearSession() {
    try {
      clearAuthToken();
      const ctx = getContext(this);
      const prefs = await dataPreferences.getPreferences(ctx, 'user_session');
      await prefs.clear();
      await prefs.flush();
    } catch (e) {
      console.log('EnterpriseDashboard 清除会话失败: ' + JSON.stringify(e));
    }
  }

  // ---------------- 综合总览 ----------------
  @Builder
  Overview() {
    Scroll() {
      Column() {
        Row() {
          this.Kpi('📡', '接入设备', DataStore.getStats().total + '', '台')
          this.Kpi('🟢', '在线设备', DataStore.getStats().online + '', '台')
          this.Kpi('🚨', '未处理预警', DataStore.getAnalysis().unhandled + '', '条')
          this.Kpi('⚠️', '风险指数', DataStore.getAnalysis().riskIndex + '%', '')
        }
        .width('100%')

        this.panelTitle('综合风险等级', '实时')
          Column() {
            RiskGauge({ risk: DataStore.getAnalysis().riskIndex })
          }
          .width('100%')
          .padding({ top: 6, bottom: 6 })
          .backgroundColor(this.pal().card)
          .borderRadius(14)
          .margin({ top: 10 })

          this.panelTitle('顶板压力趋势（24h）', '实时曲线')
          this.TrendChart(DataStore.getTrend())

        this.panelTitle('最近预警', '实时')
        Column() {
          if (DataStore.getAlerts().filter((a) => !a.handled).length === 0) {
            Text('当前无未处理预警')
              .fontSize(13)
              .fontColor(this.pal().textDim)
              .padding(24)
          } else {
            ForEach(DataStore.getAlerts().filter((a) => !a.handled).slice(0, 5), (a: BackendAlert) => {
              this.AlertItem(a)
            })
          }
        }
        .width('100%')
        .backgroundColor(this.pal().card)
        .borderRadius(14)

        this.panelTitle('全流程数据闭环', 'CLOSED LOOP')
        Column() {
          ClosedLoop()
        }
        .width('100%')
        .padding({ top: 10, bottom: 10 })
        .backgroundColor(this.pal().card)
        .borderRadius(14)
        .margin({ top: 10 })

        this.VrEntryCard()

        this.CollabCard()
      }
      .width('100%')
      .padding(12)
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
  }

  // ---------------- 实时监测 ----------------
  @Builder
  Monitor() {
    Scroll() {
      Column() {
        this.panelTitle('传感器实时监测', DataStore.getStats().online + '/' + DataStore.getStats().total + ' 在线')
        Column() {
          ForEach(DataStore.getSensors(), (s: BackendSensor) => {
            Row() {
              MineIcon({ name: this.iconOf(s.type), iconSize: 18, color: this.pal().textDim })
                .width(36)
              Column() {
                Text(s.name)
                  .fontSize(14)
                  .fontColor(this.pal().textMain)
                  .fontWeight(FontWeight.Medium)
                Text(s.description)
                  .fontSize(11)
                  .fontColor(this.pal().textDim)
                  .margin({ top: 2 })
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              Text(this.valueText(s))
                .fontSize(16)
                .fontWeight(FontWeight.Bold)
                .fontColor(DataStore.isOver(s) ? '#E5484D' : '#3DDC84')
              Text('趋势')
                .fontSize(11)
                .fontColor(ACCENT)
                .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                .borderRadius(10)
                .backgroundColor(this.pal().field)
                .margin({ left: 8 })
                .onClick(() => this.history = s)
              Column()
                .width(8)
                .height(8)
                .borderRadius(4)
                .backgroundColor(DataStore.isOver(s) ? '#E5484D' : '#3DDC84')
                .margin({ left: 8 })
            }
            .width('100%')
            .padding(12)
            .backgroundColor(this.pal().card)
            .borderRadius(8)
            .margin({ bottom: 10 })
          })
        }
        .width('100%')
      }
      .width('100%')
      .padding(12)
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
  }

  // ---------------- 预警管理 ----------------
  @Builder
  Alert() {
    Scroll() {
      Column() {
        Row() {
          this.Kpi('🔴', '红色', this.countBy('RED') + '', '条')
          this.Kpi('🟠', '橙色', this.countBy('ORANGE') + '', '条')
          this.Kpi('🟡', '黄色', this.countBy('YELLOW') + '', '条')
          this.Kpi('✅', '已处理', this.handledCount() + '', '条')
        }
        .width('100%')

        this.ThresholdPanel()

        Row() {
          Text('全部确认')
            .fontSize(12)
            .fontColor(this.pal().textMain)
            .padding({ left: 14, right: 14, top: 7, bottom: 7 })
            .backgroundColor('#E5484D')
            .borderRadius(14)
            .onClick(() => this.confirmAll())
        }
        .width('100%')
        .justifyContent(FlexAlign.End)
        .margin({ top: 8 })

        Column() {
          if (DataStore.getAlerts().length === 0) {
            Text('暂无预警记录')
              .fontSize(13)
              .fontColor(this.pal().textDim)
              .padding(24)
          } else {
            ForEach(DataStore.getAlerts(), (a: BackendAlert) => {
              this.AlertRow(a)
            })
          }
        }
        .width('100%')
        .margin({ top: 10 })
      }
      .width('100%')
      .padding(12)
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
  }

  // ---------------- 数据分析 ----------------
  @Builder
  Analysis() {
    Scroll() {
      Column() {
        Row() {
          this.Kpi('gauge', '当前压力', DataStore.getAnalysis().currentPressure + '', 'kN')
          this.Kpi('trend', '今日峰值', DataStore.getAnalysis().peakPressure + '', 'kN')
          this.Kpi('siren', '累计预警', DataStore.getAnalysis().alertTotal + '', '次')
        }
        .width('100%')

        this.panelTitle('顶板压力趋势分析', '24H')
        this.TrendChart(DataStore.getTrend())

        this.panelTitle('多源监测融合曲线', '力 · 位移 · 震动')
        Column() {
          FusedTrend({ trend: DataStore.getTrend() })
        }
        .width('100%')
        .padding({ top: 10, bottom: 12, left: 8, right: 8 })
        .backgroundColor(this.pal().card)
        .borderRadius(14)
        .margin({ top: 10 })

        this.panelTitle('传感器威胁度', 'THREAT')
        Column() {
          ForEach(DataStore.getThreat(), (t: ThreatItem) => {
            Row() {
              Text(t.name)
                .fontSize(12)
                .fontColor(this.pal().textMain)
                .width(100)
              Blank()
              Text(t.value + t.unit)
                .fontSize(12)
                .fontColor(this.pal().textDim)
            }
            .width('100%')
            .margin({ bottom: 4 })
            Stack() {
              Row()
                .width('100%')
                .height(9)
                .borderRadius(5)
                .backgroundColor(this.pal().field)
              Row()
                .width(this.pctWidth(t.pct))
                .height(9)
                .borderRadius(5)
                .backgroundColor(this.threatColor(t.color))
            }
            .width('100%')
            .alignContent(Alignment.Center)
            .margin({ bottom: 8 })
          })
        }
        .width('100%')
        .padding(14)
        .backgroundColor(this.pal().card)
        .borderRadius(14)
        .margin({ top: 10 })
      }
      .width('100%')
      .padding(12)
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
  }

  // ---------------- 预警条目 ----------------
  @Builder
  AlertItem(a: BackendAlert) {
    Row() {
      Column()
        .width(8)
        .height(8)
        .borderRadius(4)
        .backgroundColor(this.lvColor(a.level))
        .margin({ right: 10 })
      Column() {
        Row() {
          Text(a.sensor_name)
            .fontSize(14)
            .fontColor(this.pal().textMain)
            .fontWeight(FontWeight.Medium)
          Text(this.lvText(a.level))
            .fontSize(10)
            .fontColor(this.pal().textMain)
            .padding({ left: 8, right: 8, top: 2, bottom: 2 })
            .backgroundColor(this.lvColor(a.level))
            .borderRadius(8)
            .margin({ left: 8 })
          if (a.raised_count > 0) {
            Text('已升级×' + a.raised_count)
              .fontSize(10)
              .fontColor(this.pal().textMain)
              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
              .backgroundColor(this.lvColor(a.level))
              .borderRadius(8)
              .margin({ left: 6 })
          }
        }
        Text(a.message)
          .fontSize(12)
          .fontColor(this.pal().textDim)
          .margin({ top: 4 })
        Text(a.value + ' / 阈值 ' + a.threshold)
          .fontSize(11)
          .fontColor(this.lvColor(a.level))
          .margin({ top: 4 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .padding(12)
    .backgroundColor(this.pal().card)
    .borderRadius(8)
    .margin({ bottom: 8 })
  }

  @Builder
  AlertRow(a: BackendAlert) {
    Row() {
      Column() {
        Text(this.lvText(a.level))
          .fontSize(11)
          .fontColor(this.pal().textMain)
          .padding({ left: 10, right: 10, top: 3, bottom: 3 })
          .backgroundColor(this.lvColor(a.level))
          .borderRadius(8)
        if (a.raised_count > 0) {
          Text('已升级×' + a.raised_count)
            .fontSize(10)
            .fontColor(this.pal().textMain)
            .padding({ left: 8, right: 8, top: 2, bottom: 2 })
            .backgroundColor(this.lvColor(a.level))
            .borderRadius(8)
            .margin({ top: 4 })
        }
      }
      Column() {
        Text(a.sensor_name)
          .fontSize(14)
          .fontColor(this.pal().textMain)
          .fontWeight(FontWeight.Medium)
        Text(a.message)
          .fontSize(11)
          .fontColor(this.pal().textDim)
          .margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ left: 10 })

      if (!a.handled) {
        Text('确认')
          .fontSize(12)
          .fontColor(this.pal().textMain)
          .padding({ left: 12, right: 12, top: 5, bottom: 5 })
          .backgroundColor(ACCENT)
          .borderRadius(8)
          .onClick(() => this.handleOne(a.id))
      }
    }
    .width('100%')
    .padding({ top: 10, bottom: 10, left: 12, right: 12 })
    .backgroundColor(this.pal().card)
    .borderRadius(8)
    .margin({ bottom: 8 })
  }

  // ---------------- 复用组件 ----------------
  @Builder
  Kpi(icon: string, label: string, value: string, unit: string) {
    Column() {
      Text(icon + ' ' + label)
        .fontSize(11)
        .fontColor(this.pal().textDim)
      Text(value)
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.pal().textMain)
        .margin({ top: 6 })
      Text(unit)
        .fontSize(10)
        .fontColor(this.pal().textDim)
        .margin({ top: 2 })
    }
    .layoutWeight(1)
    .padding({ top: 12, bottom: 12 })
    .backgroundColor(this.pal().card)
    .borderRadius(8)
    .margin({ left: 4, right: 4 })
  }

  @Builder
  panelTitle(title: string, tag: string) {
    Row() {
      Text(title)
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.pal().textMain)
      Blank()
      Text(tag)
        .fontSize(10)
        .fontColor(ACCENT)
    }
    .width('100%')
    .margin({ top: 12, bottom: 8, left: 4, right: 4 })
  }

  @Builder
  TrendChart(trend: TrendPoint[]) {
    if (trend.length === 0) {
      Text('暂无趋势数据')
        .fontSize(13)
        .fontColor(this.pal().textDim)
        .padding(24)
    } else {
      Stack() {
        Row()
          .width('100%')
          .height(150)
          .backgroundColor(this.pal().card)
          .borderRadius(8)
        Row() {
          ForEach(trend, (t: TrendPoint) => {
            Column() {
              Blank()
              Column()
                .width('55%')
                .height(this.barHeight(t.value))
                .borderRadius({ topLeft: 4, topRight: 4 })
                .backgroundColor(t.value >= 80 ? '#E5484D' : ACCENT)
                .margin({ left: 3, right: 3 })
            }
            .width('4.2%')
            .height(150)
            .justifyContent(FlexAlign.End)
          })
        }
        .width('100%')
        .height(150)
        .padding({ left: 8, right: 8, top: 14, bottom: 14 })
      }
      .width('100%')
      .height(150)
    }
  }

  private barHeight(v: number): string {
    const h = (v / 100) * 100;
    const clamped = Math.max(6, Math.min(100, h));
    return clamped.toString() + '%';
  }

  private pctWidth(pct: number): string {
    const w = Math.max(4, Math.min(100, pct));
    return w.toString() + '%';
  }

  private iconOf(type: string): string {
    if (type === 'WATER_PRESSURE') return '💧';
    if (type === 'FILM_PRESSURE') return '🔴';
    if (type === 'TEMPERATURE') return '🌡️';
    if (type === 'HUMIDITY') return '💧';
    if (type === 'CO2_LEVEL' || type === 'SO2_LEVEL') return '💨';
    if (type === 'ULTRASONIC_DISTANCE') return '📏';
    if (type === 'STRAIN_GAUGE') return '🔧';
    if (type === 'VIBRATION') return '📳';
    if (type === 'LORA_MODULE') return '📡';
    if (type === 'OLED_DISPLAY') return '📺';
    return '📊';
  }

  private valueText(s: BackendSensor): string {
    if (s.type === 'LORA_MODULE' || s.type === 'OLED_DISPLAY') {
      return s.status === 'ONLINE' ? '在线' : '离线';
    }
    return s.value + (s.unit || '');
  }

  private countBy(level: string): number {
    return DataStore.getAlerts().filter((a) => a.level === level).length;
  }

  private handledCount(): number {
    return DataStore.getAlerts().filter((a) => a.handled).length;
  }

  private lvColor(level: string): string {
    if (level === 'RED') return '#E5484D';
    if (level === 'ORANGE') return '#FF8C2A';
    return '#F5C542';
  }

  private lvText(level: string): string {
    if (level === 'RED') return '红色预警';
    if (level === 'ORANGE') return '橙色预警';
    return '黄色预警';
  }

  private threatColor(c: string): string {
    if (c === 'red') return '#E5484D';
    if (c === 'orange') return '#FF8C2A';
    if (c === 'amber') return '#F5C542';
    return '#3DDC84';
  }

  private async handleOne(id: string) {
    await DataStore.handleAlert(id);
    promptAction.showToast({ message: '预警已确认处理', duration: 1500 });
  }

  private async confirmAll() {
    await DataStore.clearAlerts();
    promptAction.showToast({ message: '已确认全部预警', duration: 1500 });
  }
}