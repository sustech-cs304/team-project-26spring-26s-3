import { AppRouter } from '../../../app/AppRouter';

@Entry
@Component
struct EditorPage {
  build() {
    Column({ space: 20 }) {
      Column({ space: 8 }) {
        Text($r('app.string.editor_page_title'))
          .fontSize($r('app.float.hero_title_size'))
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.primary_text'))

        Text($r('app.string.editor_page_desc'))
          .fontSize($r('app.float.body_text_size'))
          .fontColor($r('app.color.secondary_text'))
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      Column({ space: 12 }) {
        Text($r('app.string.editor_page_hint'))
          .fontSize($r('app.float.caption_text_size'))
          .fontColor($r('app.color.secondary_text'))

        Button($r('app.string.editor_back_home'))
          .width('100%')
          .height($r('app.float.button_height'))
          .onClick(() => {
            AppRouter.goHome();
          })
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
