import { NotebookSortType } from '../../../domain/repositories/NotebookRepository';

@Component
export struct SortMenu {
  @Prop selectedSortType: NotebookSortType = NotebookSortType.UPDATED_DESC;
  onSortTypeChange: (sortType: NotebookSortType) => void = (_sortType: NotebookSortType): void => {};

  build() {
    Row({ space: 10 }) {
      Text($r('app.string.notebook_sort_title'))
        .fontSize($r('app.float.body_text_size'))
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.primary_text'))

      Row({ space: 8 }) {
        Button($r('app.string.notebook_sort_updated'))
          .height(32)
          .padding({ left: 12, right: 12 })
          .backgroundColor(this.selectedSortType === NotebookSortType.UPDATED_DESC ? $r('app.color.primary_text') : $r('app.color.app_background'))
          .fontColor(this.selectedSortType === NotebookSortType.UPDATED_DESC ? $r('app.color.inverse_text') : $r('app.color.primary_text'))
          .fontSize($r('app.float.caption_text_size'))
          .border({
            width: 1,
            color: this.selectedSortType === NotebookSortType.UPDATED_DESC ? $r('app.color.primary_text') : $r('app.color.card_border')
          })
          .onClick(() => {
            this.onSortTypeChange(NotebookSortType.UPDATED_DESC);
          })

        Button($r('app.string.notebook_sort_created'))
          .height(32)
          .padding({ left: 12, right: 12 })
          .backgroundColor(this.selectedSortType === NotebookSortType.CREATED_DESC ? $r('app.color.primary_text') : $r('app.color.app_background'))
          .fontColor(this.selectedSortType === NotebookSortType.CREATED_DESC ? $r('app.color.inverse_text') : $r('app.color.primary_text'))
          .fontSize($r('app.float.caption_text_size'))
          .border({
            width: 1,
            color: this.selectedSortType === NotebookSortType.CREATED_DESC ? $r('app.color.primary_text') : $r('app.color.card_border')
          })
          .onClick(() => {
            this.onSortTypeChange(NotebookSortType.CREATED_DESC);
          })

        Button($r('app.string.notebook_sort_title_asc'))
          .height(32)
          .padding({ left: 12, right: 12 })
          .backgroundColor(this.selectedSortType === NotebookSortType.TITLE_ASC ? $r('app.color.primary_text') : $r('app.color.app_background'))
          .fontColor(this.selectedSortType === NotebookSortType.TITLE_ASC ? $r('app.color.inverse_text') : $r('app.color.primary_text'))
          .fontSize($r('app.float.caption_text_size'))
          .border({
            width: 1,
            color: this.selectedSortType === NotebookSortType.TITLE_ASC ? $r('app.color.primary_text') : $r('app.color.card_border')
          })
          .onClick(() => {
            this.onSortTypeChange(NotebookSortType.TITLE_ASC);
          })
      }
      .layoutWeight(1)
      .justifyContent(FlexAlign.End)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({ left: 4, right: 4, top: 2, bottom: 2 })
  }
}
