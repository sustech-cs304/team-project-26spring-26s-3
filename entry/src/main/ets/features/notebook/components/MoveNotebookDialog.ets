import { NotebookFolder } from '../../../domain/entities/NotebookFolder';

@Component
export struct MoveNotebookDialog {
  @Link selectedFolderId: string;
  @Prop notebookTitle: string = '';
  @Prop folderList: NotebookFolder[] = [];
  @Prop isSubmitting: boolean = false;
  onCancel: () => void = (): void => {};
  onConfirm: () => void = (): void => {};

  build() {
    Column({ space: 16 }) {
      Column({ space: 6 }) {
        Text($r('app.string.folder_move_dialog_title'))
          .fontSize($r('app.float.section_title_size'))
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.primary_text'))

        Text(this.getNotebookText())
          .fontSize($r('app.float.caption_text_size'))
          .fontColor($r('app.color.secondary_text'))
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      Column({ space: 8 }) {
        this.buildFolderOption('', '未归类')

        if (this.folderList.length === 0) {
          Text($r('app.string.folder_move_empty_desc'))
            .width('100%')
            .fontSize($r('app.float.caption_text_size'))
            .fontColor($r('app.color.secondary_text'))
        } else {
          ForEach(this.folderList, (folder: NotebookFolder) => {
            this.buildFolderOption(folder.id, folder.title)
          }, (folder: NotebookFolder): string => folder.id)
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

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

        Button(this.isSubmitting ? $r('app.string.folder_moving') : $r('app.string.folder_move_confirm'))
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

  @Builder
  private buildFolderOption(folderId: string, title: string): void {
    Button(title)
      .width('100%')
      .height($r('app.float.button_height'))
      .backgroundColor(this.selectedFolderId === folderId ? $r('app.color.primary_text') : $r('app.color.app_background'))
      .fontColor(this.selectedFolderId === folderId ? $r('app.color.inverse_text') : $r('app.color.primary_text'))
      .border({
        width: 1,
        color: this.selectedFolderId === folderId ? $r('app.color.primary_text') : $r('app.color.card_border')
      })
      .onClick(() => {
        if (!this.isSubmitting) {
          this.selectedFolderId = folderId;
        }
      })
  }

  private getNotebookText(): string {
    return `笔记本：${this.notebookTitle}`;
  }
}
