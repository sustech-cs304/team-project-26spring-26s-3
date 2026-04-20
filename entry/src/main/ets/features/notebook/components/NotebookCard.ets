@Component
export struct NotebookCard {
  @Prop title: string = '';
  @Prop updatedAtText: string = '';

  build() {
    Column({ space: 8 }) {
      Text(this.title)
        .fontSize($r('app.float.section_title_size'))
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.primary_text'))
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Text(this.updatedAtText)
        .fontSize($r('app.float.caption_text_size'))
        .fontColor($r('app.color.secondary_text'))
        .maxLines(1)
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
