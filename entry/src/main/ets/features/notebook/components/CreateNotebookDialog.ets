@Component
export struct CreateNotebookDialog {
  @Link title: string;
  isRenameMode: boolean = false;
  isSubmitting: boolean = false;
  onCancel: () => void = (): void => {};
  onConfirm: () => void = (): void => {};

  build() {
    Column({ space: 16 }) {
      Column({ space: 6 }) {
        Text(this.isRenameMode ? $r('app.string.notebook_rename_dialog_title') : $r('app.string.notebook_create_dialog_title'))
          .fontSize($r('app.float.section_title_size'))
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.primary_text'))

        Text(this.isRenameMode ? $r('app.string.notebook_rename_dialog_desc') : $r('app.string.notebook_create_dialog_desc'))
          .fontSize($r('app.float.caption_text_size'))
          .fontColor($r('app.color.secondary_text'))
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      TextInput({
        placeholder: this.isRenameMode ? $r('app.string.notebook_rename_placeholder') : $r('app.string.notebook_create_placeholder'),
        text: this.title
      })
        .width('100%')
        .height($r('app.float.button_height'))
        .fontSize($r('app.float.body_text_size'))
        .backgroundColor($r('app.color.app_background'))
        .borderRadius($r('app.float.card_radius'))
        .padding({
          left: 16,
          right: 16
        })
        .onChange((value: string) => {
          this.title = value;
        })

      Text(this.isRenameMode ? $r('app.string.notebook_rename_tip') : $r('app.string.notebook_create_tip'))
        .width('100%')
        .fontSize($r('app.float.caption_text_size'))
        .fontColor($r('app.color.secondary_text'))

      Row({ space: 12 }) {
        Button($r('app.string.dialog_cancel'))
          .layoutWeight(1)
          .height($r('app.float.button_height'))
          .backgroundColor($r('app.color.app_background'))
          .fontColor($r('app.color.primary_text'))
          .onClick(() => {
            if (!this.isSubmitting) {
              this.onCancel();
            }
          })

        Button(
          this.isSubmitting
            ? (this.isRenameMode ? $r('app.string.notebook_renaming') : $r('app.string.notebook_creating'))
            : (this.isRenameMode ? $r('app.string.notebook_rename_confirm') : $r('app.string.notebook_create_confirm'))
        )
          .layoutWeight(1)
          .height($r('app.float.button_height'))
          .backgroundColor($r('app.color.primary_text'))
          .fontColor($r('app.color.inverse_text'))
          .onClick(() => {
            if (!this.isSubmitting) {
              this.onConfirm();
            }
          })
      }
      .width('100%')
    }
    .width('100%')
    .constraintSize({ maxWidth: 560 })
    .alignItems(HorizontalAlign.Start)
    .padding(24)
    .backgroundColor($r('app.color.surface_background'))
    .borderRadius($r('app.float.card_radius'))
    .border({
      width: 1,
      color: $r('app.color.card_border')
    })
  }
}
