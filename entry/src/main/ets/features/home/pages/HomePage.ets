import common from '@ohos.app.ability.common';
import { StorageKeys } from '../../../common/constants/StorageKeys';
import { AppTheme, AppThemeColorOption } from '../../../common/theme/AppTheme';
import { PreferencesDataSource } from '../../../data/sources/local/PreferencesDataSource';
import { NotebookListPanel } from '../../notebook/components/NotebookListPanel';

const THEME_MENU_BUTTON_WIDTH = 34;
const THEME_MENU_BUTTON_GAP = 8;
const THEME_MENU_PADDING = 10;
const THEME_MENU_HEIGHT = 54;
const THEME_MENU_GAP = 8;

class ThemeMenuPosition {
  x: Length = 0;
  y: Length = 0;
}

class ThemeButtonAnchor {
  left: number = 0;
  top: number = 0;
  width: number = 0;
  height: number = 0;
}

@Entry
@Component
struct HomePage {
  @State private reloadNotebookSignal: number = 0;
  @State private notebookSearchText: string = '';
  @State private isNotebookSidebarCollapsed: boolean = false;
  @State private useLargeNotebookCards: boolean = true;
  @StorageLink('storage.app.theme.color') private themeColor: string = AppTheme.DEFAULT_COLOR;
  @State private isThemeMenuVisible: boolean = false;
  @State private themeButtonAnchor: ThemeButtonAnchor = new ThemeButtonAnchor();
  @State private pageAreaLeft: number = 0;
  @State private pageAreaTop: number = 0;
  @State private pageAreaWidth: number = 0;
  @State private pageAreaHeight: number = 0;
  private themePreferencesDataSource?: PreferencesDataSource;

  aboutToAppear(): void {
    void this.loadThemeColor();
  }

  onPageShow(): void {
    this.reloadNotebookSignal += 1;
  }

  private ensureThemePreferencesDataSource(): PreferencesDataSource {
    if (this.themePreferencesDataSource === undefined) {
      const hostContext: common.Context | undefined = this.getUIContext().getHostContext() as common.Context | undefined;
      if (hostContext === undefined) {
        throw new Error('Host context is unavailable.');
      }
      this.themePreferencesDataSource = new PreferencesDataSource(hostContext);
    }
    return this.themePreferencesDataSource as PreferencesDataSource;
  }

  private async loadThemeColor(): Promise<void> {
    const storedColor: string =
      await this.ensureThemePreferencesDataSource().getString(StorageKeys.THEME_COLOR, AppTheme.DEFAULT_COLOR);
    this.themeColor = AppTheme.normalizeThemeColor(storedColor);
  }

  private async selectThemeColor(color: string): Promise<void> {
    const nextColor: string = AppTheme.normalizeThemeColor(color);
    this.themeColor = nextColor;
    this.isThemeMenuVisible = false;
    await this.ensureThemePreferencesDataSource().putString(StorageKeys.THEME_COLOR, nextColor);
  }

  private getThemeColor(): string {
    return AppTheme.getAccentColor(this.themeColor);
  }

  private getSelectedThemeColor(): string {
    return AppTheme.normalizeThemeColor(this.themeColor);
  }

  private getThemeSoftColor(): string {
    return AppTheme.getSoftColor(this.themeColor);
  }

  private getThemeShellBackgroundColor(): string {
    return AppTheme.getShellBackgroundColor(this.themeColor);
  }

  private getThemeTopBarBackgroundColor(): string {
    return AppTheme.getTopBarBackgroundColor(this.themeColor);
  }

  private getThemePanelBackgroundColor(): string {
    return AppTheme.getPanelBackgroundColor(this.themeColor);
  }

  private getThemeTopBarTextColor(): string {
    return AppTheme.getTopBarTextColor(this.themeColor);
  }

  private getThemeBorderColor(): string {
    return AppTheme.getBorderColor(this.themeColor);
  }

  private getThemeMenuWidth(): number {
    const optionCount: number = AppTheme.getThemeOptions().length;
    return optionCount * THEME_MENU_BUTTON_WIDTH + Math.max(optionCount - 1, 0) * THEME_MENU_BUTTON_GAP +
      THEME_MENU_PADDING * 2;
  }

  private getThemeMenuPosition(): Position {
    const position: ThemeMenuPosition = new ThemeMenuPosition();
    const menuWidth: number = this.getThemeMenuWidth();
    const anchor: ThemeButtonAnchor = this.themeButtonAnchor;
    if (!this.isThemeMenuVisible || this.pageAreaWidth <= 0 || anchor.width <= 0) {
      position.x = Math.max(this.pageAreaWidth - menuWidth - 16, 0);
      position.y = 66;
      return position;
    }

    let menuLeft: number = anchor.left + anchor.width - menuWidth;
    if (menuLeft < 8) {
      menuLeft = 8;
    }
    if (menuLeft + menuWidth > this.pageAreaWidth - 8) {
      menuLeft = Math.max(this.pageAreaWidth - menuWidth - 8, 8);
    }

    let menuTop: number = anchor.top + anchor.height + THEME_MENU_GAP;
    if (this.pageAreaHeight > 0 && menuTop + THEME_MENU_HEIGHT > this.pageAreaHeight) {
      menuTop = Math.max(anchor.top - THEME_MENU_HEIGHT - THEME_MENU_GAP, 8);
    }

    position.x = menuLeft;
    position.y = menuTop;
    return position;
  }

  private updateThemeButtonAnchor(area: Area): void {
    const nextAnchor: ThemeButtonAnchor = new ThemeButtonAnchor();
    nextAnchor.left = this.resolveLengthValue(area.globalPosition.x) - this.pageAreaLeft;
    nextAnchor.top = this.resolveLengthValue(area.globalPosition.y) - this.pageAreaTop;
    nextAnchor.width = this.resolveLengthValue(area.width);
    nextAnchor.height = this.resolveLengthValue(area.height);
    this.themeButtonAnchor = nextAnchor;
  }

  private updatePageArea(area: Area): void {
    this.pageAreaLeft = this.resolveLengthValue(area.globalPosition.x);
    this.pageAreaTop = this.resolveLengthValue(area.globalPosition.y);
    this.pageAreaWidth = this.resolveLengthValue(area.width);
    this.pageAreaHeight = this.resolveLengthValue(area.height);
  }

  private resolveLengthValue(value: Length | undefined): number {
    if (typeof value === 'number') {
      return Number.isFinite(value) ? value : 0;
    }

    if (typeof value === 'string') {
      const parsedValue: number = parseFloat(value);
      return Number.isFinite(parsedValue) ? parsedValue : 0;
    }

    return 0;
  }

  @Builder
  private buildNotebookCardViewIcon(): void {
    if (this.useLargeNotebookCards) {
      Row({ space: 3 }) {
        Column() {}
          .width(7)
          .height(14)
          .borderRadius(2)
          .border({ width: 2, color: '#667085' })
        Column() {}
          .width(7)
          .height(14)
          .borderRadius(2)
          .border({ width: 2, color: '#667085' })
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
    } else {
      Column({ space: 4 }) {
        Row({ space: 4 }) {
          Column() {}
            .width(5)
            .height(5)
            .borderRadius(1)
            .backgroundColor('#667085')
          Column() {}
            .width(15)
            .height(2)
            .borderRadius(1)
            .backgroundColor('#667085')
        }
        .alignItems(VerticalAlign.Center)

        Row({ space: 4 }) {
          Column() {}
            .width(5)
            .height(5)
            .borderRadius(1)
            .backgroundColor('#667085')
          Column() {}
            .width(15)
            .height(2)
            .borderRadius(1)
            .backgroundColor('#667085')
        }
        .alignItems(VerticalAlign.Center)
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
    }
  }

  @Builder
  private buildNotebookCardViewButton(): void {
    Button() {
      this.buildNotebookCardViewIcon()
    }
    .width(42)
    .height(42)
    .padding(0)
    .backgroundColor($r('app.color.surface_background'))
    .borderRadius(12)
    .border({
      width: 1,
      color: $r('app.color.card_border')
    })
    .onClick(() => {
      this.useLargeNotebookCards = !this.useLargeNotebookCards;
    })
  }

  @Builder
  private buildThemeButton(): void {
    Button() {
      Image($rawfile('icons/app_palette_black.svg'))
        .width(20)
        .height(20)
        .objectFit(ImageFit.Contain)
    }
    .width(42)
    .height(42)
    .padding(0)
    .backgroundColor(this.isThemeMenuVisible ? this.getThemeSoftColor() : $r('app.color.surface_background'))
    .borderRadius(12)
    .border({
      width: 1,
      color: this.isThemeMenuVisible ? this.getThemeColor() : $r('app.color.card_border')
    })
    .onAreaChange((_oldValue: Area, newValue: Area) => {
      this.updateThemeButtonAnchor(newValue);
    })
    .onTouch((event?: TouchEvent) => {
      if (event !== undefined && event.type === TouchType.Down) {
        this.updateThemeButtonAnchor(event.target.area);
      }
    })
    .onClick(() => {
      this.isThemeMenuVisible = !this.isThemeMenuVisible;
    })
  }

  @Builder
  private buildThemeMenu(): void {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        ForEach(AppTheme.getThemeOptions(), (option: AppThemeColorOption) => {
          Button() {
            Column() {}
              .width(22)
              .height(22)
              .backgroundColor(option.color)
              .borderRadius(999)
              .border({
                width: this.getSelectedThemeColor() === option.color ? 3 : 1,
                color: this.getSelectedThemeColor() === option.color ? '#111827' : '#CBD5E1'
              })
          }
          .width(34)
          .height(34)
          .padding(0)
          .backgroundColor(this.getSelectedThemeColor() === option.color ? option.softColor : '#FFFFFF')
          .borderRadius(10)
          .onClick(() => {
            void this.selectThemeColor(option.color);
          })
        }, (option: AppThemeColorOption): string => option.id)
      }
      .alignItems(VerticalAlign.Center)
    }
    .padding(10)
    .backgroundColor(this.getThemePanelBackgroundColor())
    .borderRadius(14)
    .border({ width: 1, color: this.getThemeBorderColor() })
    .shadow({
      radius: 14,
      color: '#22000000',
      offsetX: 0,
      offsetY: 6
    })
    .position(this.getThemeMenuPosition())
    .zIndex(20)
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        Row({ space: 16 }) {
          Button() {
            Row({ space: 10 }) {
              Row() {
                Text('H')
                  .fontSize(18)
                  .fontWeight(FontWeight.Bold)
                  .fontColor($r('app.color.inverse_text'))
              }
              .width(36)
              .height(36)
              .justifyContent(FlexAlign.Center)
              .alignItems(VerticalAlign.Center)
              .backgroundColor(this.getThemeColor())
              .borderRadius(10)

              Text('HOSN')
                .fontSize(24)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.getThemeTopBarTextColor())
            }
          }
          .height(44)
          .padding({ left: 2, right: 8, top: 2, bottom: 2 })
          .backgroundColor('#00000000')
          .borderRadius(12)
          .onClick(() => {
            this.isNotebookSidebarCollapsed = !this.isNotebookSidebarCollapsed;
          })

          Row({ space: 8 }) {
            TextInput({
              placeholder: '搜索笔记、标签或内容...',
              text: this.notebookSearchText
            })
              .layoutWeight(1)
              .height(40)
              .fontSize($r('app.float.caption_text_size'))
              .fontColor('#344054')
              .placeholderColor('#98A2B3')
              .backgroundColor('#00000000')
              .padding({ left: 0, right: 0 })
              .onChange((value: string) => {
                this.notebookSearchText = value;
              })

            if (this.notebookSearchText.trim().length > 0) {
              Button('清除')
                .height(28)
                .padding({ left: 10, right: 10 })
                .fontSize(12)
                .fontColor('#667085')
                .backgroundColor('#F2F4F7')
                .onClick(() => {
                  this.notebookSearchText = '';
                })
            }
          }
          .layoutWeight(1)
          .height(42)
          .padding({ left: 14, right: 12 })
          .backgroundColor($r('app.color.surface_background'))
          .borderRadius(12)
          .border({
            width: 1,
            color: $r('app.color.card_border')
          })

          Row({ space: 8 }) {
            this.buildNotebookCardViewButton()
            this.buildThemeButton()
          }
          .alignItems(VerticalAlign.Center)
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 12, bottom: 12 })
        .backgroundColor(this.getThemeTopBarBackgroundColor())
        .border({
          width: {
            bottom: 1
          },
          color: this.getThemeBorderColor()
        })

        Column() {
          NotebookListPanel({
            reloadNotebookSignal: this.reloadNotebookSignal,
            searchText: this.notebookSearchText,
            isSidebarCollapsed: this.isNotebookSidebarCollapsed,
            useLargeNotebookCards: $useLargeNotebookCards
          })
        }
        .width('100%')
        .layoutWeight(1)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.getThemeShellBackgroundColor())
      .zIndex(0)

      if (this.isThemeMenuVisible) {
        this.buildThemeMenu()
      }
    }
    .width('100%')
    .height('100%')
    .onAreaChange((_oldValue: Area, newValue: Area) => {
      this.updatePageArea(newValue);
    })
  }
}
