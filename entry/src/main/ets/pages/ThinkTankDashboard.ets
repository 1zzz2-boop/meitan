/**
 * 智库端 · 科研机构 —— 独立功能主页
 * 模块：数据集 / 分析研究 / 模型指标 / 报告导出
 */
import { router } from '@kit.ArkUI';
import { promptAction } from '@kit.ArkUI';
import dataPreferences from '@ohos.data.preferences';
import { DataStore } from '../services/DataStore';
import { BackendSensor, ThreatItem, AnalysisReport, ModelMetrics, TrendPoint, clearAuthToken, apiGetReportTemplates, apiGenerateReport, ReportTemplate, ReportMineChoice, GeneratedReport } from '../services/BackendApi';
import { Palette, ThemeMode, paletteFor, modeLabel, ensureThemeInit, switchThemeMode } from '../services/Theme';
import { AccountPanel } from '../components/AccountPanel';
import { SensorHistoryPanel } from '../components/SensorHistoryPanel';

const ACCENT = '#3DDC84';

interface TabItem {
  label: string;
  icon: string;
}

@Entry
@Component
struct ThinkTankDashboard {
  @State tabs: TabItem[] = [
    { label: '数据集', icon: '🗂️' },
    { label: '分析研究', icon: '📈' },
    { label: '模型指标', icon: '🧠' },
    { label: '报告导出', icon: '📄' },
    { label: '用户管理', icon: '👤' },
    { label: '系统管理', icon: '⚙️' }
  ];
  @State current: number = 0;
  @State fresh: number = 0;
  @State userName: string = '智库分析师';
  @State showCreate: boolean = false;
  @State reportTitle: string = '';
  @State reportContent: string = '';
  @State history: BackendSensor | null = null;
  @State tplList: ReportTemplate[] = [];
  @State mineList: ReportMineChoice[] = [];
  @State selTpl: string = '';
  @State selMine: number = 0; // 0=全部矿井
  @State genBusy: boolean = false;
  @State genReport: GeneratedReport | null = null;
  @StorageProp('theme_mode') themeMode: number = ThemeMode.NIGHT;

  aboutToAppear() {
    ensureThemeInit(getContext(this));
    this.loadSessionUser();
    DataStore.load();
    DataStore.onChange(() => {
      this.fresh++;
    });
    DataStore.refetch();
    this.loadTemplates();
  }

  private async loadTemplates() {
    try {
      const res = await apiGetReportTemplates();
      this.tplList = res.templates || [];
      this.mineList = res.mines || [];
      if (this.tplList.length > 0 && this.selTpl.length === 0) {
        this.selTpl = this.tplList[0].key;
      }
    } catch (e) {
      this.tplList = [];
      this.mineList = [];
    }
  }

  private async doGenerate() {
    if (!this.selTpl || this.genBusy) return;
    this.genBusy = true;
    try {
      this.genReport = await apiGenerateReport(this.selTpl, this.selMine === 0 ? null : this.selMine);
      promptAction.showToast({ message: '报表已生成', duration: 1200 });
    } catch (e) {
      promptAction.showToast({ message: '报表生成失败', duration: 1500 });
    } finally {
      this.genBusy = false;
    }
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
      this.userName = await prefs.get('displayName', '智库分析师') as string;
    } catch (e) {
      this.userName = '智库分析师';
    }
  }

  build() {
    Stack() {
      Column() {
        Row() {
          Text('‹')
            .fontSize(26)
            .fontColor(this.pal().textMain)
            .onClick(() => router.back())
          Text('智库端 · 科研机构')
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

        Column() {
          if (this.current === 0) {
            this.Dataset()
          } else if (this.current === 1) {
            this.Research()
          } else if (this.current === 2) {
            this.ModelMetrics()
          } else if (this.current === 3) {
          this.Reports()
        } else if (this.current === 4 || this.current === 5) {
          AccountPanel({
            mode: this.current === 4 ? 1 : 2,
            defaultName: '智库分析师',
            roleText: '智库端',
            accent: ACCENT,
            onProfileSaved: (name: string) => {
              this.userName = name;
            }
          })
        }
      }
      .layoutWeight(1)

        Row() {
          ForEach(this.tabs, (item: TabItem, index: number) => {
            Column() {
              Text(item.icon)
                .fontSize(18)
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

      // 新建报告弹层
      if (this.showCreate) {
        this.CreateOverlay()
      }

      // 历史趋势面板浮层（P0）
      if (this.history) {
        this.HistoryOverlay()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.pal().bgApp)
  }

  // ---------------- 历史趋势面板浮层（P0) ----------------
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

  // ---------------- 三端协同快捷入口 ----------------
  @Builder
  CollabCard() {
    Row() {
      Text('🔀')
        .fontSize(24)
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

  // ---------------- 数据集 ----------------
  @Builder
  Dataset() {
    Scroll() {
      Column() {
        Row() {
          this.Kpi('📋', '样本记录', this.sampleCount() + '', '条')
          this.Kpi('🎯', '模型准确率', (DataStore.getMetrics() ? DataStore.getMetrics()!.accuracy : 92.4) + '', '%')
        }
        .width('100%')

        this.CollabCard()

        this.panelTitle('采集数据快照', '实时采样')
        Column() {
          ForEach(DataStore.getSensors(), (s: BackendSensor) => {
            Row() {
              Text(this.iconOf(s.type))
                .fontSize(18)
                .width(32)
              Text(s.name)
                .fontSize(13)
                .fontColor(this.pal().textMain)
                .layoutWeight(1)
              Text(this.valueText(s))
                .fontSize(13)
                .fontColor(this.dataColor(s))
              Text('趋势')
                .fontSize(11)
                .fontColor(ACCENT)
                .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                .borderRadius(10)
                .backgroundColor(this.pal().field)
                .margin({ left: 8 })
                .onClick(() => this.history = s)
            }
            .width('100%')
            .padding({ top: 9, bottom: 9, left: 12, right: 12 })
            .borderRadius(10)
            .margin({ bottom: 7 })
          })
        }
        .width('100%')
        .padding(12)
        .backgroundColor(this.pal().card)
        .borderRadius(14)
        .margin({ top: 8 })
      }
      .width('100%')
      .padding(12)
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
  }

  // ---------------- 分析研究 ----------------
  @Builder
  Research() {
    Scroll() {
      Column() {
        Row() {
          this.Kpi('📊', '当前压力', DataStore.getAnalysis().currentPressure + '', 'kN')
          this.Kpi('⚠️', '风险指数', DataStore.getAnalysis().riskIndex + '%', '')
          this.Kpi('🚨', '未处理', DataStore.getAnalysis().unhandled + '', '条')
        }
        .width('100%')

        this.panelTitle('顶板压力趋势研究', '24H')
        this.TrendChart(DataStore.getTrend())

        this.panelTitle('威胁度关联分析', 'THREAT')
        Column() {
          ForEach(DataStore.getThreat(), (t: ThreatItem) => {
            Row() {
              Text(t.name)
                .fontSize(12)
                .fontColor(this.pal().textMain)
                .width(96)
              Blank()
              Text(t.pct + '%')
                .fontSize(12)
                .fontColor(this.threatColor(t.color))
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
            .margin({ bottom: 8 })
          })
        }
        .width('100%')
        .padding(14)
        .backgroundColor(this.pal().card)
        .borderRadius(14)
        .margin({ top: 10 })

        this.panelTitle('结论建议', 'AI')
        Text('基于压力 / 位移 / 震动多源关联分析，当前风险可控；建议对' + DataStore.getAnalysis().riskIndex + '%风险指数对应的预警点位加密采样，并复核传感器定标。')
          .fontSize(13)
          .fontColor(this.pal().textSub)
          .lineHeight(20)
          .width('100%')
          .padding(14)
          .backgroundColor(this.pal().card)
          .borderRadius(14)
          .margin({ top: 6 })
      }
      .width('100%')
      .padding(12)
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
  }

  // ---------------- 模型指标 ----------------
  @Builder
  ModelMetrics() {
    Scroll() {
      Column() {
        Row() {
          this.Kpi('🎯', '准确率', (DataStore.getMetrics() ? DataStore.getMetrics()!.accuracy : 92.4) + '', '%')
          this.Kpi('⚠️', '误报率', (DataStore.getMetrics() ? DataStore.getMetrics()!.falseRate : 7.6) + '', '%')
          this.Kpi('🧮', '训练样本', (DataStore.getMetrics() ? DataStore.getMetrics()!.sampleSize : 1840) + '', '条')
        }
        .width('100%')

        this.panelTitle('达标量化指标', 'TARGET')
        Column() {
          this.MetricBar('准确率', DataStore.getMetrics() ? DataStore.getMetrics()!.accuracy : 92.4, '%', 85, true)
          this.MetricBar('误报率', DataStore.getMetrics() ? DataStore.getMetrics()!.falseRate : 7.6, '%', 15, false)
        }
        .width('100%')
        .padding(14)
        .backgroundColor(this.pal().card)
        .borderRadius(14)
        .margin({ top: 10 })

        this.panelTitle('模型信息', DataStore.getMetrics() ? DataStore.getMetrics()!.modelVersion : '--')

        Column() {
          this.InfoRow('算法', DataStore.getMetrics() ? DataStore.getMetrics()!.algorithm : '数字孪生AI模型')
          this.InfoRow('版本', DataStore.getMetrics() ? DataStore.getMetrics()!.modelVersion : 'v2.3.1')
          this.InfoRow('样本量', (DataStore.getMetrics() ? DataStore.getMetrics()!.sampleSize : 1840) + '')
          this.InfoRow('准确率', (DataStore.getMetrics() ? DataStore.getMetrics()!.accuracy : 92.4) + '%')
          this.InfoRow('误报率', (DataStore.getMetrics() ? DataStore.getMetrics()!.falseRate : 7.6) + '%')
        }
        .width('100%')
        .padding(14)
        .backgroundColor(this.pal().card)
        .borderRadius(14)
        .margin({ top: 8 })

        this.panelTitle('模型评估', 'RADAR')
        Text('数字孪生 AI 预警模型准确率 92.4%（≥85% 达标），误报率 7.6%（≤15% 达标）。融合压力 / 位移 / 震动多源数据，训练样本 1840 条，模型持续迭代优化。')
          .fontSize(13)
          .fontColor(this.pal().textSub)
          .lineHeight(20)
          .width('100%')
          .padding(14)
          .backgroundColor(this.pal().card)
          .borderRadius(14)
          .margin({ top: 6 })
      }
      .width('100%')
      .padding(12)
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
  }

  // ---------------- 报告导出 ----------------
  @Builder
  Reports() {
    Scroll() {
      Column() {
        // 报表模板引擎（P2-3.6）
        Column() {
          Text('📑 报表模板引擎')
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.pal().textMain)
        Row() {
          Text('模板类型')
            .fontSize(12)
            .fontColor(this.pal().textDim)
        }
        .width('100%')
        .margin({ top: 8 })
        .padding({ left: 2 })

        Column() {
          ForEach(this.tplList, (t: ReportTemplate) => {
            Row() {
              Text(this.selTpl === t.key ? '●' : '○')
                .fontSize(13)
                .fontColor(this.selTpl === t.key ? ACCENT : this.pal().textDim)
                .margin({ right: 8 })
              Column() {
                Text(t.name)
                  .fontSize(13)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.pal().textMain)
                Text(t.desc)
                  .fontSize(10)
                  .fontColor(this.pal().textDim)
                  .margin({ top: 2 })
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
            }
            .width('100%')
            .padding({ top: 8, bottom: 8 })
            .borderRadius(10)
            .onClick(() => this.selTpl = t.key)
          })
        }
        .width('100%')
        .padding(12)
        .backgroundColor(this.pal().card)
        .borderRadius(12)
        .margin({ top: 6 })

        Row() {
          Text('矿井范围')
            .fontSize(12)
            .fontColor(this.pal().textDim)
        }
        .width('100%')
        .margin({ top: 10 })
        .padding({ left: 2 })

        Row() {
          Row() {
            Text(this.selMine === 0 ? '●' : '○')
              .fontSize(12)
              .fontColor(this.selMine === 0 ? ACCENT : this.pal().textDim)
            Text('全部矿井')
              .fontSize(12)
              .fontColor(this.pal().textMain)
              .margin({ left: 5 })
          }
          .padding({ left: 12, right: 12, top: 8, bottom: 8 })
          .borderRadius(18)
          .backgroundColor(this.selMine === 0 ? this.pal().accentSoft : this.pal().field)
          .onClick(() => this.selMine = 0)
          ForEach(this.mineList, (m: ReportMineChoice) => {
            Row() {
              Text(this.selMine === m.id ? '●' : '○')
                .fontSize(12)
                .fontColor(this.selMine === m.id ? ACCENT : this.pal().textDim)
              Text(this.shortMine(m.name))
                .fontSize(12)
                .fontColor(this.pal().textMain)
                .margin({ left: 5 })
            }
            .padding({ left: 12, right: 12, top: 8, bottom: 8 })
            .borderRadius(18)
            .backgroundColor(this.selMine === m.id ? this.pal().accentSoft : this.pal().field)
            .margin({ left: 6 })
            .onClick(() => this.selMine = m.id)
          })
        }
        .width('100%')
        .margin({ top: 6 })

        Button(this.genBusy ? '生成中...' : '生成报表')
          .width('100%')
          .height(44)
          .backgroundColor(ACCENT)
          .fontColor(this.pal().textMain)
          .fontWeight(FontWeight.Medium)
          .borderRadius(22)
          .margin({ top: 14 })
          .enabled(this.selTpl.length > 0 && !this.genBusy)
          .onClick(() => this.doGenerate())

        if (this.genReport) {
          this.GenReportCard(this.genReport)
        }

        Row() {
          Text('新建研究报告')
            .fontSize(13)
            .fontColor(this.pal().textMain)
            .fontWeight(FontWeight.Medium)
            .padding({ left: 16, right: 16, top: 8, bottom: 8 })
            .backgroundColor(ACCENT)
            .borderRadius(16)
            .onClick(() => {
              this.reportTitle = '';
              this.reportContent = '';
              this.showCreate = true;
            })
        }
        .width('100%')
        .justifyContent(FlexAlign.End)
        .margin({ top: 16 })

        Column() {
          ForEach(DataStore.getReports(), (r: AnalysisReport) => {
            this.ReportCard(r)
          })
        }
        .width('100%')
        .margin({ top: 10 })
      }
      .width('100%')
      .padding(12)
    }
    .width('100%')
    .height('100%')
  }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
  }

  @Builder
  GenReportCard(r: GeneratedReport) {
    Column() {
      Row() {
        Text('✅ 已生成：' + r.title)
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor(ACCENT)
      }
      .width('100%')
      .margin({ bottom: 8 })

      Row() {
        Text('传感器 ' + r.overview.sensorCount + '｜在线 ' + r.overview.online)
          .fontSize(12)
          .fontColor(this.pal().textMain)
        Blank()
        Text('预警 ' + r.alertSummary.total + '｜未处置 ' + r.alertSummary.unhandled)
          .fontSize(12)
          .fontColor(this.pal().textMain)
      }
      .width('100%')

      Row() {
        Text('黄 ' + r.alertSummary.byLevel.YELLOW)
          .fontSize(11)
          .fontColor(this.pal().textDim)
        Text('橙 ' + r.alertSummary.byLevel.ORANGE)
          .fontSize(11)
          .fontColor(this.pal().textDim)
          .margin({ left: 14 })
        Text('红 ' + r.alertSummary.byLevel.RED)
          .fontSize(11)
          .fontColor('#E5484D')
          .margin({ left: 14 })
        Blank()
        Text(this.fmtTime(r.createdAt))
          .fontSize(11)
          .fontColor(this.pal().textDim)
      }
      .width('100%')
      .margin({ top: 6 })
    }
    .width('100%')
    .padding(14)
    .backgroundColor(this.pal().card)
    .borderRadius(14)
    .margin({ top: 12 })
  }

  @Builder
  ReportCard(r: AnalysisReport) {
    Column() {
      Row() {
        Text('📄')
          .fontSize(18)
          .margin({ right: 8 })
        Text(r.title)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.pal().textMain)
          .layoutWeight(1)
      }
      .width('100%')
      Text(r.content)
        .fontSize(12)
        .fontColor(this.pal().textDim)
        .lineHeight(18)
        .margin({ top: 8 })
      Row() {
        Text('作者：' + r.author)
          .fontSize(11)
          .fontColor(this.pal().textDim)
        Blank()
        Text(this.fmtTime(r.created_at))
          .fontSize(11)
          .fontColor(this.pal().textDim)
      }
      .width('100%')
      .margin({ top: 10 })
    }
    .width('100%')
    .padding(14)
    .backgroundColor(this.pal().card)
    .borderRadius(14)
    .margin({ bottom: 10 })
  }

  // ---------------- 新建报告弹层 ----------------
  @Builder
  CreateOverlay() {
    Column() {
      Column() {
        Text('新建研究报告')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.pal().textMain)
        TextInput({ placeholder: '请输入报告标题', text: this.reportTitle })
          .width('100%')
          .margin({ top: 16 })
          .backgroundColor(this.pal().field)
          .borderRadius(10)
          .fontColor(this.pal().textMain)
          .placeholderColor(this.pal().placeholder)
          .onChange((v: string) => this.reportTitle = v)
        TextArea({ placeholder: '请输入报告内容', text: this.reportContent })
          .width('100%')
          .height(120)
          .margin({ top: 12 })
          .backgroundColor(this.pal().field)
          .borderRadius(10)
          .fontColor(this.pal().textMain)
          .placeholderColor(this.pal().placeholder)
          .onChange((v: string) => this.reportContent = v)
        Row() {
          Button('取消')
            .layoutWeight(1)
            .height(42)
            .backgroundColor(this.pal().accentSoft)
            .fontColor(this.pal().textMain)
            .borderRadius(21)
            .onClick(() => this.showCreate = false)
          Button('保存并生成')
            .layoutWeight(1)
            .height(42)
            .backgroundColor(ACCENT)
            .fontColor(this.pal().textMain)
            .borderRadius(21)
            .margin({ left: 12 })
            .enabled(this.reportTitle.length > 0 && this.reportContent.length > 0)
            .onClick(() => this.saveReport())
        }
        .width('100%')
        .margin({ top: 18 })
      }
      .width('86%')
      .padding(20)
      .backgroundColor(this.pal().card)
      .borderRadius(18)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor('rgba(0,0,0,0.6)')
  }

  private async saveReport() {
    await DataStore.createReport(this.reportTitle, this.reportContent);
    this.showCreate = false;
    promptAction.showToast({ message: '研究报告已生成', duration: 1500 });
  }

  // ---------------- 复用 ----------------
  // 达标量化指标进度条：good=true 表示越高越好（达标≥target），否则越低越好（达标≤target）
  private metricOk(value: number, target: number, good: boolean): boolean {
    return good ? value >= target : value <= target;
  }

  private metricColor(value: number, target: number, good: boolean): string {
    return this.metricOk(value, target, good) ? '#3DDC84' : '#E5484D';
  }

  @Builder
  MetricBar(label: string, value: number, unit: string, target: number, good: boolean) {
    Column() {
      Row() {
        Text(label)
          .fontSize(12)
          .fontColor(this.pal().textMain)
          .fontWeight(FontWeight.Medium)
        Blank()
        Text(value + unit)
          .fontSize(12)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.metricColor(value, target, good))
      }
      .width('100%')

      Row() {
        Text(good ? ('达标线 ≥' + target) : ('上限 ≤' + target))
          .fontSize(10)
          .fontColor(this.pal().textDim)
      }
      .width('100%')
      .margin({ top: 4 })

      Stack() {
        Row()
          .width('100%')
          .height(9)
          .borderRadius(5)
          .backgroundColor(this.pal().field)
        Row()
          .width((Math.max(0, Math.min(100, value))) + '%')
          .height(9)
          .borderRadius(5)
          .backgroundColor(this.metricColor(value, target, good))
      }
      .width('100%')
      .alignContent(Alignment.Start)
      .margin({ top: 6 })

      Text(this.metricOk(value, target, good) ? '✅ 达标' : '⚠️ 未达标')
        .fontSize(10)
        .fontColor(this.metricColor(value, target, good))
        .width('100%')
        .margin({ top: 4 })
    }
    .width('100%')
    .margin({ bottom: 12 })
  }

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
    .borderRadius(12)
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
  InfoRow(label: string, value: string) {
    Row() {
      Text(label)
        .fontSize(13)
        .fontColor(this.pal().textDim)
      Blank()
      Text(value)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.pal().textMain)
    }
    .width('100%')
    .padding({ top: 8, bottom: 8 })
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
          .borderRadius(12)
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
    const h = Math.max(6, Math.min(100, (v / 100) * 100));
    return h.toString() + '%';
  }

  private pctWidth(pct: number): string {
    return Math.max(4, Math.min(100, pct)).toString() + '%';
  }

  private sampleCount(): number {
    return DataStore.getSensors().length * 24;
  }

  private fmtTime(ts: string): string {
    if (!ts) return '--';
    return ts.replace('T', ' ').split('.')[0];
  }

  private shortMine(name: string): string {
    if (name.indexOf('青岛') >= 0) return '青岛矿井';
    if (name.indexOf('朔州') >= 0) return '朔州矿井';
    if (name.indexOf('鄂尔多斯') >= 0) return '鄂尔多斯矿';
    return name.length > 6 ? name.slice(0, 6) + '…' : name;
  }

  private iconOf(type: string): string {
    if (type === 'FILM_PRESSURE') return '🔴';
    if (type === 'WATER_PRESSURE') return '💧';
    if (type === 'VIBRATION') return '📳';
    if (type === 'LORA_MODULE') return '📡';
    return '📊';
  }

  private valueText(s: BackendSensor): string {
    if (s.type === 'LORA_MODULE' || s.type === 'OLED_DISPLAY') return s.status === 'ONLINE' ? '在线' : '离线';
    return s.value + (s.unit || '');
  }

  private dataColor(s: BackendSensor): string {
    return DataStore.isOver(s) ? '#E5484D' : '#3DDC84';
  }

  private threatColor(c: string): string {
    if (c === 'red') return '#E5484D';
    if (c === 'orange') return '#FF8C2A';
    if (c === 'amber') return '#F5C542';
    return '#3DDC84';
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
      console.log('ThinkTankDashboard 清除会话失败: ' + JSON.stringify(e));
    }
  }

  }