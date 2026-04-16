import { AppRouter, RouterParams } from '../../../app/AppRouter';

@Entry
@Component
struct NotebookListPage {
  build() {
    Column({ space: 20 }) {
      Column({ space: 8 }) {
        Text($r('app.string.notebook_page_title'))
          .fontSize($r('app.float.hero_title_size'))
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.primary_text'))

        Text($r('app.string.notebook_page_desc'))
          .fontSize($r('app.float.body_text_size'))
          .fontColor($r('app.color.secondary_text'))
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      Column({ space: 12 }) {
        Text($r('app.string.notebook_demo_card_title'))
          .fontSize($r('app.float.section_title_size'))
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.primary_text'))

        Text($r('app.string.notebook_demo_card_desc'))
          .fontSize($r('app.float.caption_text_size'))
          .fontColor($r('app.color.secondary_text'))

        Row({ space: 12 }) {
          Button($r('app.string.notebook_open_demo'))
            .layoutWeight(1)
            .height($r('app.float.button_height'))
            .onClick(() => {
              const params: RouterParams = {
                notebookId: 'demo-notebook'
              };
              AppRouter.openEditor(params);
            })

          Button($r('app.string.notebook_back_home'))
            .layoutWeight(1)
            .height($r('app.float.button_height'))
            .onClick(() => {
              AppRouter.goHome();
            })
        }
        .width('100%')
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding(20)
      .backgroundColor($r('app.color.surface_background'))
      .borderRadius($r('app.float.card_radius'))
      .border({
        width: 1,
        color: $r('app.color.card_border')
      })
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({
      left: $r('app.float.page_padding_horizontal'),
      right: $r('app.float.page_padding_horizontal'),
      top: $r('app.float.page_padding_vertical'),
      bottom: $r('app.float.page_padding_vertical')
    })
    .backgroundColor($r('app.color.app_background'))
  }
}
