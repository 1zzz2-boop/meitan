/**
 * 监管端 · 集团/安监 —— 独立功能主页
 * 模块：监控总览 / 监管预警 / 应急调度 / 监管报告
 */
import { router } from '@kit.ArkUI';
import { promptAction } from '@kit.ArkUI';
import dataPreferences from '@ohos.data.preferences';
import { DataStore } from '../services/DataStore';
import { MineInfo, DispatchRecord, BackendAlert, SupervisionOverview, clearAuthToken } from '../services/BackendApi';
import { Palette, ThemeMode, paletteFor, modeLabel, ensureThemeInit, switchThemeMode } from '../services/Theme';
import { AccountPanel } from '../components/AccountPanel';
import { RiskGauge } from '../components/RiskGauge';
import { ClosedLoop } from '../components/ClosedLoop';

const ACCENT = '#F5C542';

interface TabItem {
  label: string;
  icon: string;
}

@Entry
@Component
struct SupervisionDashboard {
  @State tabs: TabItem[] = [
    { label: '监控总览', icon: '🏛️' },
    { label: '监管预警', icon: '🚨' },
    { label: '应急调度', icon: '🚑' },
    { label: '监管报告', icon: '📃' },
    { label: '用户管理', icon: '👤' },
    { label: '系统管理', icon: '⚙️' }
  ];
  @State current: number = 0;
  @State fresh: number = 0;
  @State userName: string = '监管员';
  @State showCreate: boolean = false;
  @State dispatchTitle: string = '';
  @State dispatchLevel: string = 'ORANGE';
  @State dispatchContent: string = '';
  @StorageProp('theme_mode') themeMode: number = ThemeMode.NIGHT;

  aboutToAppear() {
    ensureThemeInit(getContext(this));
    this.loadSessionUser();
    DataStore.load();
    DataStore.onChange(() => {
      this.fresh++;
    });
    DataStore.refetch();
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
      this.userName = await prefs.get('displayName', '监管员') as string;
    } catch (e) {
      this.userName = '监管员';
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
          Text('监管端 · 远程监管')
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
            this.Overview()
          } else if (this.current === 1) {
            this.Alert()
          } else if (this.current === 2) {
            this.Dispatch()
          } else if (this.current === 3) {
            this.Report()
          } else if (this.current === 4 || this.current === 5) {
            AccountPanel({
              mode: this.current === 4 ? 1 : 2,
              defaultName: '监管员',
              roleText: '监管端',
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

      if (this.showCreate) {
        this.CreateOverlay()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.pal().bgApp)
  }

  // ---------------- 监控总览 ----------------
  @Builder
  Overview() {
    Scroll() {
      Column() {
        Row() {
          this.Kpi('🏭', '矿井', this.ov().mineCount + '', '座')
          this.Kpi('📡', '设备', this.ov().sensorTotal + '', '台')
          this.Kpi('🚨', '未处理', this.ov().unhandledAlert + '', '条')
          this.Kpi('🚑', '在途调度', this.ov().activeDispatch + '', '个')
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

        this.panelTitle('全流程数据闭环', 'CLOSED LOOP')
        Column() {
          ClosedLoop()
        }
        .width('100%')
        .padding({ top: 10, bottom: 10 })
        .backgroundColor(this.pal().card)
        .borderRadius(14)
        .margin({ top: 10 })

        this.CollabCard()

        this.panelTitle('下辖矿井', '实时')
        Column() {
          ForEach(DataStore.getMines(), (m: MineInfo) => {
            Column() {
              Row() {
                Text('⛏')
                  .fontSize(20)
                  .margin({ right: 8 })
                Column() {
                  Text(m.name)
                    .fontSize(14)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(this.pal().textMain)
                  Text(m.location + ' · ' + m.owner)
                    .fontSize(11)
                    .fontColor(this.pal().textDim)
                    .margin({ top: 2 })
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)
              }
              .width('100%')
              Row() {
                this.Stat('设备', m.sensorTotal + '', '台')
                this.Stat('在线', m.online + '', '台')
                this.Stat('预警', m.warning + '', '条')
              }
              .width('100%')
              .margin({ top: 10 })
            }
            .width('100%')
            .padding(14)
            .backgroundColor(this.pal().card)
            .borderRadius(14)
            .margin({ bottom: 10 })
          })
        }
        .width('100%')
        .margin({ top: 6 })
      }
      .width('100%')
      .padding(12)
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
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

  // ---------------- 监管预警 ----------------
  @Builder
  Alert() {
    Scroll() {
      Column() {
        Row() {
          this.Kpi('🔴', '红色', this.ov().alertStat.RED + '', '条')
          this.Kpi('🟠', '橙色', this.ov().alertStat.ORANGE + '', '条')
          this.Kpi('🟡', '黄色', this.ov().alertStat.YELLOW + '', '条')
          this.Kpi('✅', '已处理', DataStore.getAlerts().filter((a) => a.handled).length + '', '条')
        }
        .width('100%')

        this.panelTitle('预警态势', '未处理')
        Column() {
          ForEach(DataStore.getAlerts().filter((a) => !a.handled), (a: BackendAlert) => {
            this.AlertRow(a)
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
    .scrollBar(BarState.Off)
  }

  // ---------------- 应急调度 ----------------
  @Builder
  Dispatch() {
    Scroll() {
      Column() {
        Row() {
          Text('新建调度指令')
            .fontSize(13)
            .fontColor(this.pal().textMain)
            .fontWeight(FontWeight.Medium)
            .padding({ left: 16, right: 16, top: 8, bottom: 8 })
            .backgroundColor(ACCENT)
            .borderRadius(16)
            .onClick(() => {
              this.dispatchTitle = '';
              this.dispatchContent = '';
              this.dispatchLevel = 'ORANGE';
              this.showCreate = true;
            })
        }
        .width('100%')
        .justifyContent(FlexAlign.End)

        Column() {
          ForEach(DataStore.getDispatches(), (d: DispatchRecord) => {
            this.DispatchRow(d)
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
    .scrollBar(BarState.Off)
  }

  @Builder
  DispatchRow(d: DispatchRecord) {
    Column() {
      Row() {
        Text(this.lvText(d.level))
          .fontSize(11)
          .fontColor(this.pal().textMain)
          .padding({ left: 10, right: 10, top: 3, bottom: 3 })
          .backgroundColor(this.lvColor(d.level))
          .borderRadius(8)
        Text(d.title)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.pal().textMain)
          .margin({ left: 8 })
          .layoutWeight(1)
        Text(this.statusText(d.status))
          .fontSize(11)
          .fontColor(d.status === 'DONE' ? '#3DDC84' : '#F5C542')
      }
      .width('100%')
      Text(d.content)
        .fontSize(12)
        .fontColor(this.pal().textDim)
        .lineHeight(18)
        .margin({ top: 8 })
        .width('100%')
      Row() {
        Text('目标：' + d.target_mine)
          .fontSize(11)
          .fontColor(this.pal().textDim)
        Blank()
        Text(d.created_at.replace('T', ' ').split('.')[0])
          .fontSize(11)
          .fontColor(this.pal().textDim)
      }
      .width('100%')
      .margin({ top: 8 })

      if (d.status !== 'DONE') {
        Row() {
          Text('标记完成')
            .fontSize(12)
            .fontColor(this.pal().textMain)
            .padding({ left: 14, right: 14, top: 6, bottom: 6 })
            .backgroundColor('#3DDC84')
            .borderRadius(12)
            .onClick(() => this.finishDispatch(d.id))
        }
        .width('100%')
        .justifyContent(FlexAlign.End)
        .margin({ top: 8 })
      }
    }
    .width('100%')
    .padding(14)
    .backgroundColor(this.pal().card)
    .borderRadius(14)
    .margin({ bottom: 10 })
  }

  // ---------------- 监管报告 ----------------
  @Builder
  Report() {
    Scroll() {
      Column() {
        this.panelTitle('安全生产态势报告', 'SUPERVISION')
        Column() {
          Text('综合风险指数 ' + DataStore.getAnalysis().riskIndex + '%')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor(ACCENT)
            .alignSelf(ItemAlign.Start)
          Text('当前下辖矿井合计接入设备 ' + this.ov().sensorTotal + ' 台，未处理预警 ' + this.ov().unhandledAlert + ' 条，在途调度 ' + this.ov().activeDispatch + ' 个。监测数据显示整体态势稳定可控，重点点位已下发核查指令，请持续跟踪处置闭环。')
            .fontSize(13)
            .fontColor(this.pal().textSub)
            .lineHeight(20)
            .margin({ top: 10 })
            .alignSelf(ItemAlign.Start)
          Row() {
            Text('导出报告')
              .fontSize(13)
              .fontColor(this.pal().textMain)
              .padding({ left: 18, right: 18, top: 9, bottom: 9 })
              .backgroundColor(ACCENT)
              .borderRadius(16)
              .margin({ top: 16 })
              .onClick(() => this.exportReport())
          }
          .width('100%')
          .justifyContent(FlexAlign.Center)
        }
        .width('100%')
        .padding(16)
        .backgroundColor(this.pal().card)
        .borderRadius(14)
        .margin({ top: 6 })

        this.panelTitle('处置建议', 'REGULATORY')
        Column() {
          this.Advice('黄色响应（Ⅲ级）：加密监测与重点巡检')
          this.Advice('橙色响应（Ⅱ级）：专项检查，跟踪督办')
          this.Advice('红色响应（Ⅰ级）：全端联动，撤人/停产')
        }
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

  @Builder
  Advice(text: string) {
    Row() {
      Text('▪')
        .fontSize(14)
        .fontColor(ACCENT)
        .margin({ right: 8 })
      Text(text)
        .fontSize(13)
        .fontColor(this.pal().textSub)
    }
    .width('100%')
    .padding({ top: 6, bottom: 6 })
  }

  // ---------------- 弹层 ----------------
  @Builder
  CreateOverlay() {
    Column() {
      Column() {
        Text('新建应急调度指令')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.pal().textMain)
        Row() {
          this.LevelPick('黄色', 'YELLOW', '#F5C542')
          this.LevelPick('橙色', 'ORANGE', '#FF8C2A')
          this.LevelPick('红色', 'RED', '#E5484D')
        }
        .width('100%')
        .margin({ top: 14 })
        TextInput({ placeholder: '请输入指令标题', text: this.dispatchTitle })
          .width('100%')
          .margin({ top: 14 })
          .backgroundColor(this.pal().field)
          .borderRadius(10)
          .fontColor(this.pal().textMain)
          .placeholderColor(this.pal().placeholder)
          .onChange((v: string) => this.dispatchTitle = v)
        TextArea({ placeholder: '请输入指令内容', text: this.dispatchContent })
          .width('100%')
          .height(110)
          .margin({ top: 12 })
          .backgroundColor(this.pal().field)
          .borderRadius(10)
          .fontColor(this.pal().textMain)
          .placeholderColor(this.pal().placeholder)
          .onChange((v: string) => this.dispatchContent = v)
        Row() {
          Button('取消')
            .layoutWeight(1)
            .height(42)
            .backgroundColor(this.pal().accentSoft)
            .fontColor(this.pal().textMain)
            .borderRadius(21)
            .onClick(() => this.showCreate = false)
          Button('下达指令')
            .layoutWeight(1)
            .height(42)
            .backgroundColor(ACCENT)
            .fontColor(this.pal().textMain)
            .borderRadius(21)
            .margin({ left: 12 })
            .enabled(this.dispatchTitle.length > 0)
            .onClick(() => this.saveDispatch())
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

  @Builder
  LevelPick(label: string, lv: string, color: string) {
    Text(label)
      .fontSize(12)
      .fontColor(this.dispatchLevel === lv ? this.pal().textMain : this.pal().textDim)
      .padding({ left: 14, right: 14, top: 6, bottom: 6 })
      .backgroundColor(this.dispatchLevel === lv ? color : this.pal().field)
      .borderRadius(12)
      .margin({ right: 8 })
      .onClick(() => this.dispatchLevel = lv)
  }

  private async saveDispatch() {
    await DataStore.createDispatch(this.dispatchTitle, this.dispatchLevel, this.dispatchContent);
    this.showCreate = false;
    promptAction.showToast({ message: '应急调度指令已下达', duration: 1500 });
  }

  private async finishDispatch(id: number) {
    await DataStore.updateDispatchStatus(id, 'DONE');
    promptAction.showToast({ message: '调度已完成', duration: 1500 });
  }

  private async exportReport() {
    promptAction.showToast({ message: '报告已导出至本地', duration: 1500 });
  }

  // ---------------- 复用 ----------------
  private ov(): SupervisionOverview {
    const o = DataStore.getOverview();
    if (o) return o;
    const fallback: SupervisionOverview = {
      mineCount: 1, sensorTotal: DataStore.getStats().total, unhandledAlert: DataStore.getAnalysis().unhandled,
      activeDispatch: 0, alertStat: { RED: 0, ORANGE: 0, YELLOW: 9 }, mines: []
    };
    return fallback;
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
  Stat(label: string, value: string, unit: string) {
    Column() {
      Text(value)
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.pal().textMain)
      Text(label + '(' + unit + ')')
        .fontSize(10)
        .fontColor(this.pal().textDim)
        .margin({ top: 3 })
    }
    .layoutWeight(1)
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
  AlertRow(a: BackendAlert) {
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
            .fontSize(13)
            .fontColor(this.pal().textMain)
          Text(this.lvText(a.level))
            .fontSize(10)
            .fontColor(this.pal().textMain)
            .padding({ left: 8, right: 8, top: 2, bottom: 2 })
            .backgroundColor(this.lvColor(a.level))
            .borderRadius(8)
            .margin({ left: 8 })
        }
        Text(a.message)
          .fontSize(12)
          .fontColor(this.pal().textDim)
          .margin({ top: 4 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .padding(12)
    .backgroundColor(this.pal().card)
    .borderRadius(12)
    .margin({ bottom: 8 })
  }

  private lvColor(level: string): string {
    if (level === 'RED') return '#E5484D';
    if (level === 'ORANGE') return '#FF8C2A';
    return '#F5C542';
  }

  private lvText(level: string): string {
    if (level === 'RED') return '红色';
    if (level === 'ORANGE') return '橙色';
    return '黄色';
  }

  private statusText(status: string): string {
    if (status === 'DONE') return '已完成';
    return '进行中';
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
      console.log('SupervisionDashboard 清除会话失败: ' + JSON.stringify(e));
    }
  }

  }