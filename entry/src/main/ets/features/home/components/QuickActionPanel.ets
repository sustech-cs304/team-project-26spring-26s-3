import { AppRouter } from '../../../app/AppRouter';

@Component
export struct QuickActionPanel {
  build() {
    Column({ space: 12 }) {
      Text($r('app.string.quick_action_title'))
        .fontSize($r('app.float.section_title_size'))
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.primary_text'))

      Text($r('app.string.quick_action_subtitle'))
        .fontSize($r('app.float.caption_text_size'))
        .fontColor($r('app.color.secondary_text'))

      Column({ space: 10 }) {
        Text($r('app.string.quick_action_notebooks_title'))
          .fontSize($r('app.float.body_text_size'))
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.primary_text'))

        Text($r('app.string.quick_action_notebooks_desc'))
          .fontSize($r('app.float.caption_text_size'))
          .fontColor($r('app.color.secondary_text'))
          .maxLines(3)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .justifyContent(FlexAlign.SpaceBetween)
      .padding(20)
      .constraintSize({ minHeight: 156 })
      .backgroundColor($r('app.color.surface_background'))
      .borderRadius($r('app.float.card_radius'))
      .border({
        width: 1,
        color: $r('app.color.card_border')
      })
      .onClick(() => {
        AppRouter.openNotebookList();
      })
    }
    .width('100%')
  }
}
