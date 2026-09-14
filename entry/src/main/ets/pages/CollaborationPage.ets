/**
 * 三端协同可视化管控页 —— 企业/智库/监管 联动
 * 展示三端角色、协同数据、调度/派单动态，并支持监管端发起派单（apiCreateDispatch）。
 */
import { router } from '@kit.ArkUI';
import { promptAction } from '@kit.ArkUI';
import { DataStore } from '../services/DataStore';
import { DispatchRecord, apiCreateDispatch } from '../services/BackendApi';
import { Palette, ThemeMode, paletteFor, modeLabel, ensureThemeInit, switchThemeMode } from '../services/Theme';

const E_COLOR = '#FF8C2A';   // 企业端
const T_COLOR = '#3DDC84';   // 智库端
const S_COLOR = '#F5C542';   // 监管端

interface RoleCard {
  icon: string;
  name: string;
  desc: string;
  color: string;
}

@Entry
@Component
struct CollaborationPage {
  @State roles: RoleCard[] = [
    { icon: '⛏', name: '企业端', desc: '生产矿井 · 实时监测与预警处置', color: E_COLOR },
    { icon: '🧠', name: '智库端', desc: '科研机构 · 数据分析与模型指标', color: T_COLOR },
    { icon: '🏛️', name: '监管端', desc: '集团安监 · 监控调度与报告', color: S_COLOR }
  ];
  @State mkTitle: string = '';
  @State mkContent: string = '';
  @State mkLevel: string = 'ORANGE';
  @State mkTarget: string = '';
  @State creating: boolean = false;
  @State fresh: number = 0;
  @StorageProp('theme_mode') themeMode: number = ThemeMode.NIGHT;

  aboutToAppear() {
    ensureThemeInit(getContext(this));
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

  private lvColor(lv: string): string {
    if (lv === 'RED') {
      return '#E5484D';
    }
    if (lv === 'ORANGE') {
      return '#F5C542';
    }
    return '#FFD76A';
  }

  private lvText(lv: string): string {
    if (lv === 'RED') {
      return '红';
    }
    if (lv === 'ORANGE') {
      return '橙';
    }
    return '黄';
  }

  private statusText(s: string): string {
    if (s === 'IN_PROGRESS') {
      return '进行中';
    }
    if (s === 'PENDING') {
      return '待处理';
    }
    if (s === 'COMPLETED') {
      return '已完成';
    }
    return s;
  }

  private async loadTarget() {
    const mines = DataStore.getMines();
    this.mkTarget = mines.length > 0 ? mines[0].name : '中建筑港青岛西海岸示范矿井';
  }

  private async createDispatch() {
    if (this.creating) {
      return;
    }
    if (this.mkTitle.trim().length === 0 || this.mkContent.trim().length === 0) {
      promptAction.showToast({ message: '请输入调度标题与内容', duration: 1500 });
      return;
    }
    this.creating = true;
    try {
      await apiCreateDispatch(this.mkTitle.trim(), this.mkLevel, this.mkContent.trim(), this.mkTarget);
      this.mkTitle = '';
      this.mkContent = '';
      promptAction.showToast({ message: '调度指令已下达至企业端', duration: 1500 });
      DataStore.refetch();
    } catch (e) {
      promptAction.showToast({ message: '派单失败：' + JSON.stringify(e), duration: 2000 });
    }
    this.creating = false;
  }

  build() {
    Stack() {
      Column() {
        // 顶部栏
        Row() {
          Text('‹')
            .fontSize(26)
            .fontColor(this.pal().textMain)
            .onClick(() => router.back())
          Text('三端协同可视化管控')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.pal().textMain)
            .margin({ left: 12 })
          Blank()
          Text(modeLabel())
            .fontSize(12)
            .fontColor(S_COLOR)
            .onClick(() => this.toggleTheme())
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 14, bottom: 14 })
        .backgroundColor(this.pal().headerBg)

        Scroll() {
          Column() {
            // 三端角色定位
            ForEach(this.roles, (r: RoleCard) => {
              Row() {
                Text(r.icon)
                  .fontSize(22)
                  .width(44)
                  .height(44)
                  .textAlign(TextAlign.Center)
                Column() {
                  Text(r.name)
                    .fontSize(14)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(this.pal().textMain)
                  Text(r.desc)
                    .fontSize(11)
                    .fontColor(this.pal().textDim)
                    .margin({ top: 3 })
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)
                .margin({ left: 10 })
              }
              .width('100%')
              .padding(12)
              .backgroundColor(this.pal().card)
              .borderRadius(12)
              .border({ width: 2, color: r.color })
              .margin({ bottom: 8 })
            })

            // 协同数据摘要
            this.panelTitle('协同数据', 'REALTIME')
            Row() {
              this.Brief('🏭', '下辖矿井', (DataStore.getOverview() ? DataStore.getOverview()!.mineCount : 0) + '', '座')
              this.Brief('🚨', '未处理预警', (DataStore.getOverview() ? DataStore.getOverview()!.unhandledAlert : 0) + '', '条')
              this.Brief('🚑', '在途调度', (DataStore.getOverview() ? DataStore.getOverview()!.activeDispatch : 0) + '', '个')
            }
            .width('100%')

            // 派单动态
            this.panelTitle('调度 / 派单动态', DataStore.getDispatches().length + ' 条')
            Column() {
              ForEach(DataStore.getDispatches(), (d: DispatchRecord) => {
                this.DispatchCard(d)
              })
            }
            .width('100%')

            // 监管发起派单
            this.panelTitle('监管端发起派单', 'DISPATCH')
            Column() {
              TextInput({ placeholder: '调度标题', text: this.mkTitle })
                .backgroundColor(this.pal().field)
                .fontColor(this.pal().textMain)
                .placeholderColor(this.pal().placeholder)
                .margin({ bottom: 8 })
                .onChange((v: string) => this.mkTitle = v)
              TextInput({ placeholder: '调度内容与要求', text: this.mkContent })
                .backgroundColor(this.pal().field)
                .fontColor(this.pal().textMain)
                .placeholderColor(this.pal().placeholder)
                .margin({ bottom: 8 })
                .onChange((v: string) => this.mkContent = v)
              TextInput({ placeholder: '目标矿井', text: this.mkTarget })
                .backgroundColor(this.pal().field)
                .fontColor(this.pal().textMain)
                .placeholderColor(this.pal().placeholder)
                .margin({ bottom: 8 })
                .onChange((v: string) => this.mkTarget = v)
              Row({ space: 8 }) {
                this.LevelChip('黄色', 'YELLOW')
                this.LevelChip('橙色', 'ORANGE')
                this.LevelChip('红色', 'RED')
                Blank()
              }
              .width('100%')
              .margin({ top: 4, bottom: 10 })

              Button(this.creating ? '下达中...' : '下达调度指令')
                .width('100%')
                .height(42)
                .fontSize(15)
                .backgroundColor(S_COLOR)
                .onClick(() => this.createDispatch())
            }
            .width('100%')
            .padding(14)
            .backgroundColor(this.pal().card)
            .borderRadius(14)
            .margin({ top: 6 })
            .onAppear(() => this.loadTarget())
          }
          .width('100%')
          .padding(12)
        }
        .width('100%')
        .height('100%')
        .scrollBar(BarState.Off)
        .layoutWeight(1)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.pal().bgApp)
    }
  }

  @Builder
  panelTitle(title: string, tag: string) {
    Row() {
      Row()
        .width(3)
        .height(13)
        .borderRadius(2)
        .backgroundColor(S_COLOR)
      Text(title)
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.pal().textMain)
        .margin({ left: 8 })
      Blank()
      Text(tag)
        .fontSize(10)
        .fontColor(this.pal().textDim)
    }
    .width('100%')
    .margin({ top: 12, bottom: 8 })
  }

  @Builder
  Brief(icon: string, label: string, value: string, unit: string) {
    Column() {
      Text(icon + ' ' + label)
        .fontSize(11)
        .fontColor(this.pal().textDim)
      Text(value)
        .fontSize(20)
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
  LevelChip(label: string, level: string) {
    Text(label)
      .fontSize(12)
      .fontColor(this.mkLevel === level ? Color.White : this.pal().textDim)
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .backgroundColor(this.mkLevel === level ? this.lvColor(level) : this.pal().field)
      .borderRadius(14)
      .onClick(() => this.mkLevel = level)
  }

  @Builder
  DispatchCard(d: DispatchRecord) {
    Column() {
      Row() {
        Text(d.title)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.pal().textMain)
          .layoutWeight(1)
        Text(this.lvText(d.level))
          .fontSize(10)
          .fontColor(Color.White)
          .padding({ left: 8, right: 8, top: 2, bottom: 2 })
          .backgroundColor(this.lvColor(d.level))
          .borderRadius(8)
        Text(this.statusText(d.status))
          .fontSize(10)
          .fontColor(this.pal().textMain)
          .padding({ left: 8, right: 8, top: 2, bottom: 2 })
          .backgroundColor(this.pal().accentSoft)
          .borderRadius(8)
          .margin({ left: 6 })
      }
      .width('100%')

      Text(d.content)
        .fontSize(12)
        .fontColor(this.pal().textSub)
        .width('100%')
        .margin({ top: 6 })

      Text('目标：' + d.target_mine + ' ｜ 发起：' + d.creator)
        .fontSize(10)
        .fontColor(this.pal().textDim)
        .width('100%')
        .margin({ top: 6 })
    }
    .width('100%')
    .padding(12)
    .backgroundColor(this.pal().card)
    .borderRadius(12)
    .margin({ bottom: 8 })
  }
}