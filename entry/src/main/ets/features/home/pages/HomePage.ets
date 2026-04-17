import { QuickActionPanel } from '../components/QuickActionPanel';

@Entry
@Component
struct HomePage {
  build() {
    Scroll() {
      Column({ space: 24 }) {
        Column({ space: 8 }) {
          Text($r('app.string.home_title'))
            .fontSize($r('app.float.hero_title_size'))
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.primary_text'))

          Text($r('app.string.home_subtitle'))
            .fontSize($r('app.float.body_text_size'))
            .fontColor($r('app.color.secondary_text'))
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)

        QuickActionPanel()

        Column({ space: 10 }) {
          Text($r('app.string.home_overview_title'))
            .fontSize($r('app.float.section_title_size'))
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.primary_text'))

          Text($r('app.string.home_overview_desc'))
            .fontSize($r('app.float.body_text_size'))
            .fontColor($r('app.color.secondary_text'))
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
      .alignItems(HorizontalAlign.Start)
      .padding({
        left: $r('app.float.page_padding_horizontal'),
        right: $r('app.float.page_padding_horizontal'),
        top: $r('app.float.page_padding_vertical'),
        bottom: $r('app.float.page_padding_vertical')
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.app_background'))
  }
}
