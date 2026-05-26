import { NotebookListPanel } from '../../notebook/components/NotebookListPanel';
import { NotebookSortType } from '../../../domain/repositories/NotebookRepository';

class TopSortMenuAnchor {
  left: number = 0;
  top: number = 0;
  width: number = 0;
  height: number = 0;
}

class TopSortMenuPosition {
  x: number = 0;
  y: number = 0;
}

@Entry
@Component
struct HomePage {
  @State private createNotebookSignal: number = 0;
  @State private refreshNotebookSignal: number = 0;
  @State private selectedTopSortType: NotebookSortType = NotebookSortType.UPDATED_DESC;
  @State private isTopSortDropdownVisible: boolean = false;
  @State private isNotebookSidebarCollapsed: boolean = false;
  @State private topSortMenuAnchor: TopSortMenuAnchor = new TopSortMenuAnchor();
  @State private rootGlobalLeft: number = 0;
  @State private rootGlobalTop: number = 0;

  private getTopSortLabel(sortType: NotebookSortType): string {
    if (sortType === NotebookSortType.TITLE_ASC) {
      return '首字母';
    }
    if (sortType === NotebookSortType.CREATED_DESC) {
      return '最近创建';
    }
    return '最新更新';
  }

  @Builder
  private buildTopSortOption(label: string, sortType: NotebookSortType) {
    Button(label)
      .width('100%')
      .height(34)
      .fontSize(13)
      .fontColor(this.selectedTopSortType === sortType ? '#3D63FF' : '#344054')
      .backgroundColor(this.selectedTopSortType === sortType ? '#EAF0FF' : '#FFFFFF')
      .borderRadius(8)
      .onClick(() => {
        this.selectedTopSortType = sortType;
        this.isTopSortDropdownVisible = false;
      })
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

  private getTopSortMenuPosition(): TopSortMenuPosition {
    const position: TopSortMenuPosition = new TopSortMenuPosition();
    position.x = Math.max(this.topSortMenuAnchor.left - this.rootGlobalLeft + this.topSortMenuAnchor.width - 130, 16);
    position.y = this.topSortMenuAnchor.top - this.rootGlobalTop + this.topSortMenuAnchor.height + 2;
    return position;
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
              .backgroundColor('#3D63FF')
              .borderRadius(10)

              Text('HOSN')
                .fontSize(24)
                .fontWeight(FontWeight.Bold)
                .fontColor('#0F172A')
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
            Text('Search notes, tags or content...')
              .layoutWeight(1)
              .fontSize($r('app.float.caption_text_size'))
              .fontColor('#98A2B3')

            Text('Ctrl K')
              .fontSize(12)
              .fontColor('#98A2B3')
              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
              .backgroundColor('#F2F4F7')
              .borderRadius(6)
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

          Row({ space: 10 }) {
            Button('+新建')
              .height(40)
              .backgroundColor('#3D63FF')
              .fontColor($r('app.color.inverse_text'))
              .onClick(() => {
                this.createNotebookSignal += 1;
              })

            Button('导入')
              .height(40)
              .backgroundColor($r('app.color.surface_background'))
              .fontColor($r('app.color.primary_text'))
              .border({
                width: 1,
                color: $r('app.color.card_border')
              })
              .onClick(() => {
                this.refreshNotebookSignal += 1;
              })

            Button(this.getTopSortLabel(this.selectedTopSortType))
              .width(130)
              .height(40)
              .backgroundColor($r('app.color.surface_background'))
              .fontColor($r('app.color.primary_text'))
              .border({
                width: 1,
                color: $r('app.color.card_border')
              })
              .onAreaChange((_oldValue: Area, newValue: Area) => {
                this.topSortMenuAnchor.left = this.resolveLengthValue(newValue.globalPosition.x);
                this.topSortMenuAnchor.top = this.resolveLengthValue(newValue.globalPosition.y);
                this.topSortMenuAnchor.width = this.resolveLengthValue(newValue.width);
                this.topSortMenuAnchor.height = this.resolveLengthValue(newValue.height);
              })
              .onClick(() => {
                this.isTopSortDropdownVisible = !this.isTopSortDropdownVisible;
              })
          }
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 12, bottom: 12 })
        .backgroundColor('#FAFBFF')
        .border({
          width: {
            bottom: 1
          },
          color: $r('app.color.card_border')
        })

        Column() {
          NotebookListPanel({
            createNotebookSignal: this.createNotebookSignal,
            refreshNotebookSignal: this.refreshNotebookSignal,
            topSortType: this.selectedTopSortType,
            isSidebarCollapsed: this.isNotebookSidebarCollapsed
          })
        }
        .width('100%')
        .layoutWeight(1)
      }
      .width('100%')
      .height('100%')
      .backgroundColor('#F3F5FA')
      .zIndex(0)

      if (this.isTopSortDropdownVisible) {
        Column({ space: 4 }) {
          this.buildTopSortOption('首字母', NotebookSortType.TITLE_ASC)
          this.buildTopSortOption('最新更新', NotebookSortType.UPDATED_DESC)
          this.buildTopSortOption('最近创建', NotebookSortType.CREATED_DESC)
        }
        .width(130)
        .padding(6)
        .backgroundColor('#FFFFFF')
        .borderRadius(10)
        .border({ width: 1, color: '#D8DEE9' })
        .shadow({
          radius: 12,
          color: '#22000000',
          offsetX: 0,
          offsetY: 6
        })
        .position(this.getTopSortMenuPosition())
        .zIndex(100)
        .onTouch((event?: TouchEvent) => {
          if (event !== undefined) {
            event.stopPropagation();
          }
        })
      }
    }
    .width('100%')
    .height('100%')
    .onAreaChange((_oldValue: Area, newValue: Area) => {
      this.rootGlobalLeft = this.resolveLengthValue(newValue.globalPosition.x);
      this.rootGlobalTop = this.resolveLengthValue(newValue.globalPosition.y);
    })
    .onTouch((event?: TouchEvent) => {
      if (event === undefined || event.type !== TouchType.Down || !this.isTopSortDropdownVisible) {
        return;
      }
      this.isTopSortDropdownVisible = false;
    })
  }
}
