import { NotebookSortType } from '../../../domain/repositories/NotebookRepository';

@Component
export struct SortMenu {
  selectedSortType: NotebookSortType = NotebookSortType.UPDATED_DESC;
  onSortSelected: (sortType: NotebookSortType) => void = (_sortType: NotebookSortType): void => {};

  build() {
    Column({ space: 12 }) {
      Column({ space: 4 }) {
        Text($r('app.string.notebook_sort_title'))
          .fontSize($r('app.float.section_title_size'))
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.primary_text'))

        Text($r('app.string.notebook_sort_desc'))
          .fontSize($r('app.float.caption_text_size'))
          .fontColor($r('app.color.secondary_text'))
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      Row({ space: 8 }) {
        Button($r('app.string.notebook_sort_updated'))
          .layoutWeight(1)
          .height($r('app.float.button_height'))
          .backgroundColor(this.selectedSortType === NotebookSortType.UPDATED_DESC ? $r('app.color.primary_text') : $r('app.color.app_background'))
          .fontColor(this.selectedSortType === NotebookSortType.UPDATED_DESC ? $r('app.color.inverse_text') : $r('app.color.primary_text'))
          .border({
            width: 1,
            color: this.selectedSortType === NotebookSortType.UPDATED_DESC ? $r('app.color.primary_text') : $r('app.color.card_border')
          })
          .onClick(() => {
            this.onSortSelected(NotebookSortType.UPDATED_DESC);
          })

        Button($r('app.string.notebook_sort_created'))
          .layoutWeight(1)
          .height($r('app.float.button_height'))
          .backgroundColor(this.selectedSortType === NotebookSortType.CREATED_DESC ? $r('app.color.primary_text') : $r('app.color.app_background'))
          .fontColor(this.selectedSortType === NotebookSortType.CREATED_DESC ? $r('app.color.inverse_text') : $r('app.color.primary_text'))
          .border({
            width: 1,
            color: this.selectedSortType === NotebookSortType.CREATED_DESC ? $r('app.color.primary_text') : $r('app.color.card_border')
          })
          .onClick(() => {
            this.onSortSelected(NotebookSortType.CREATED_DESC);
          })

        Button($r('app.string.notebook_sort_title_asc'))
          .layoutWeight(1)
          .height($r('app.float.button_height'))
          .backgroundColor(this.selectedSortType === NotebookSortType.TITLE_ASC ? $r('app.color.primary_text') : $r('app.color.app_background'))
          .fontColor(this.selectedSortType === NotebookSortType.TITLE_ASC ? $r('app.color.inverse_text') : $r('app.color.primary_text'))
          .border({
            width: 1,
            color: this.selectedSortType === NotebookSortType.TITLE_ASC ? $r('app.color.primary_text') : $r('app.color.card_border')
          })
          .onClick(() => {
            this.onSortSelected(NotebookSortType.TITLE_ASC);
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
}
