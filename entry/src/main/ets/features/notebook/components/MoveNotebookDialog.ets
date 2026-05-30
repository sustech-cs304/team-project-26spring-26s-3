import { NotebookFolder } from '../../../domain/entities/NotebookFolder';
import { AppTheme } from '../../../common/theme/AppTheme';

@Component
export struct MoveNotebookDialog {
  @Link selectedFolderId: string;
  @Prop notebookTitle: string = '';
  @Prop folderList: NotebookFolder[] = [];
  @Prop isSubmitting: boolean = false;
  @StorageLink('storage.app.theme.color') private themeColor: string = AppTheme.DEFAULT_COLOR;
  @State private searchText: string = '';
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

      TextInput({
        placeholder: '搜索文件夹',
        text: this.searchText
      })
        .width('100%')
        .height($r('app.float.button_height'))
        .fontSize($r('app.float.body_text_size'))
        .backgroundColor($r('app.color.app_background'))
        .borderRadius(12)
        .border({ width: 1, color: this.getThemeBorderColor() })
        .padding({ left: 14, right: 14 })
        .enabled(!this.isSubmitting)
        .onChange((value: string) => {
          this.searchText = value;
        })

      Column({ space: 8 }) {
        if (this.shouldShowUngroupedOption()) {
          this.buildFolderOption('', '未归类')
        }

        if (this.getFilteredFolderList().length === 0 && !this.shouldShowUngroupedOption()) {
          Text($r('app.string.folder_move_empty_desc'))
            .width('100%')
            .fontSize($r('app.float.caption_text_size'))
            .fontColor($r('app.color.secondary_text'))
        } else {
          ForEach(this.getFilteredFolderList(), (folder: NotebookFolder) => {
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
          .backgroundColor(this.getThemeColor())
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
      .backgroundColor(this.selectedFolderId === folderId ? this.getThemeColor() : $r('app.color.app_background'))
      .fontColor(this.selectedFolderId === folderId ? $r('app.color.inverse_text') : $r('app.color.primary_text'))
      .border({
        width: 1,
        color: this.selectedFolderId === folderId ? this.getThemeColor() : $r('app.color.card_border')
      })
      .onClick(() => {
        if (!this.isSubmitting) {
          this.selectedFolderId = folderId;
        }
      })
  }

  private getThemeColor(): string {
    return AppTheme.getAccentColor(this.themeColor);
  }

  private getThemeBorderColor(): string {
    return AppTheme.getBorderColor(this.themeColor);
  }

  private normalizeSearchQuery(value: string): string {
    return value.trim().replace(/\s+/g, ' ').toLowerCase();
  }

  private shouldShowUngroupedOption(): boolean {
    const query: string = this.normalizeSearchQuery(this.searchText);
    return query.length === 0 || '未归类'.toLowerCase().includes(query);
  }

  private getFilteredFolderList(): NotebookFolder[] {
    const query: string = this.normalizeSearchQuery(this.searchText);
    if (query.length === 0) {
      return this.folderList;
    }

    const result: NotebookFolder[] = [];
    for (const folder of this.folderList) {
      if (folder.title.toLowerCase().includes(query)) {
        result.push(folder);
      }
    }
    return result;
  }

  private getNotebookText(): string {
    return `笔记本：${this.notebookTitle}`;
  }
}
