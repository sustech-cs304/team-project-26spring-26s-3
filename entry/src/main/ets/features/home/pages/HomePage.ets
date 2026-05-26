import { NotebookListPanel } from '../../notebook/components/NotebookListPanel';

@Entry
@Component
struct HomePage {
  @State private reloadNotebookSignal: number = 0;
  @State private notebookSearchText: string = '';
  @State private isNotebookSidebarCollapsed: boolean = false;

  onPageShow(): void {
    this.reloadNotebookSignal += 1;
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
            reloadNotebookSignal: this.reloadNotebookSignal,
            searchText: this.notebookSearchText,
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

    }
    .width('100%')
    .height('100%')
  }
}
