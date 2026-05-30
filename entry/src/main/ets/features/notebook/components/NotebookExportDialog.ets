import {
  buildNotebookExportFileName,
  NOTEBOOK_EXPORT_FORMAT_OPTIONS,
  NOTEBOOK_EXPORT_SCOPE_OPTIONS,
  NotebookExportFormatOption,
  NotebookExportScopeOption,
  normalizeNotebookExportFormat,
  normalizeNotebookExportScope
} from '../models/NotebookExportOptions';
import { AppTheme } from '../../../common/theme/AppTheme';

@Component
export struct NotebookExportDialog {
  @Link fileName: string;
  @Link outputPath: string;
  @Link selectedFormat: string;
  @Link selectedScope: string;
  @Link pageRange: string;
  @Prop notebookTitle: string = '';
  @Prop isChoosingPath: boolean = false;
  @Prop isExporting: boolean = false;
  @Prop showScopeOptions: boolean = true;
  @Prop isBatchMode: boolean = false;
  @Prop batchItemCount: number = 0;
  @StorageLink('storage.app.theme.color') private themeColor: string = AppTheme.DEFAULT_COLOR;
  onCancel: () => void = (): void => {};
  onChoosePath: () => void = (): void => {};
  onConfirm: () => void = (): void => {};
  onFormatChange: (format: string) => void = (_format: string): void => {};
  onScopeChange: (scope: string) => void = (_scope: string): void => {};
  onPageRangeChange: (range: string) => void = (_range: string): void => {};

  build() {
    Column({ space: 16 }) {
      Column({ space: 6 }) {
        Text('导出为…')
          .fontSize($r('app.float.section_title_size'))
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.primary_text'))

        Text(this.isBatchMode ? `将分别导出 ${this.batchItemCount} 个笔记本` :
          (this.notebookTitle.length > 0 ? `笔记本：${this.notebookTitle}` : '选择导出参数。'))
          .fontSize($r('app.float.caption_text_size'))
          .fontColor($r('app.color.secondary_text'))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      if (!this.isBatchMode) {
        Column({ space: 8 }) {
          Text('文件名')
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.primary_text'))

          TextInput({
            placeholder: '输入导出文件名',
            text: this.fileName
          })
            .width('100%')
            .height($r('app.float.button_height'))
            .fontSize($r('app.float.body_text_size'))
            .backgroundColor($r('app.color.app_background'))
            .borderRadius(14)
            .padding({ left: 16, right: 16 })
            .onChange((value: string) => {
              this.fileName = value;
            })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }

      Column({ space: 8 }) {
        Text('导出格式')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.primary_text'))

        Row({ space: 8 }) {
          ForEach(NOTEBOOK_EXPORT_FORMAT_OPTIONS, (option: NotebookExportFormatOption) => {
            this.buildFormatOption(option)
          }, (option: NotebookExportFormatOption): string => option.format)
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      if (this.showScopeOptions) {
        Column({ space: 8 }) {
          Text('导出范围')
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.primary_text'))

          Row({ space: 8 }) {
            ForEach(NOTEBOOK_EXPORT_SCOPE_OPTIONS, (option: NotebookExportScopeOption) => {
              this.buildScopeOption(option)
            }, (option: NotebookExportScopeOption): string => option.scope)
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)

          if (this.isRangeScopeSelected()) {
            TextInput({
              placeholder: '例如 1-3, 5, 8',
              text: this.pageRange
            })
              .width('100%')
              .height($r('app.float.button_height'))
              .fontSize(13)
              .backgroundColor($r('app.color.app_background'))
              .borderRadius(14)
              .padding({ left: 14, right: 14 })
              .onChange((value: string) => {
                this.pageRange = value;
                this.onPageRangeChange(value);
              })
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }

      Column({ space: 8 }) {
        Text('保存位置')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.primary_text'))

        Row({ space: 10 }) {
          TextInput({
            placeholder: '选择或输入保存路径',
            text: this.outputPath
          })
            .layoutWeight(1)
            .height($r('app.float.button_height'))
            .fontSize(13)
            .backgroundColor($r('app.color.app_background'))
            .borderRadius(14)
            .padding({ left: 14, right: 14 })
            .onChange((value: string) => {
              this.outputPath = value;
            })

          Button(this.isChoosingPath ? '选择中...' : '选择路径')
            .height($r('app.float.button_height'))
            .padding({ left: 14, right: 14 })
            .fontSize(13)
            .enabled(!this.isDialogBusy())
            .backgroundColor(this.getThemeColor())
            .fontColor($r('app.color.inverse_text'))
            .borderRadius(14)
            .onClick(() => {
              if (!this.isDialogBusy()) {
                this.onChoosePath();
              }
            })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      if (this.isBatchMode) {
        Text('将使用每个笔记本名称分别生成导出文件。')
          .width('100%')
          .fontSize($r('app.float.caption_text_size'))
          .fontColor($r('app.color.secondary_text'))
      } else {
        Text(`预览文件：${this.getPreviewFileName()}`)
          .width('100%')
          .fontSize($r('app.float.caption_text_size'))
          .fontColor($r('app.color.secondary_text'))
      }

      Text('PDF 会导出为单个文件，图片格式会按页面导出。')
        .width('100%')
        .fontSize(12)
        .fontColor('#8A94A6')

      Row({ space: 12 }) {
        Button('取消')
          .layoutWeight(1)
          .height($r('app.float.button_height'))
          .enabled(!this.isDialogBusy())
          .backgroundColor($r('app.color.app_background'))
          .fontColor($r('app.color.primary_text'))
          .onClick(() => {
            if (!this.isDialogBusy()) {
              this.onCancel();
            }
          })

        Button(this.isExporting ? '导出中...' : '确认')
          .layoutWeight(1)
          .height($r('app.float.button_height'))
          .enabled(!this.isDialogBusy())
          .backgroundColor(this.getThemeColor())
          .fontColor($r('app.color.inverse_text'))
          .onClick(() => {
            if (!this.isDialogBusy()) {
              this.onConfirm();
            }
          })
      }
      .width('100%')
    }
    .width('100%')
    .constraintSize({ maxWidth: 620 })
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
  private buildFormatOption(option: NotebookExportFormatOption): void {
    Button() {
      Column({ space: 4 }) {
        Text(option.label)
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.isFormatSelected(option.format) ? $r('app.color.inverse_text') : $r('app.color.primary_text'))

        Text(option.caption)
          .fontSize(11)
          .fontColor(this.isFormatSelected(option.format) ? '#DCE7FF' : $r('app.color.secondary_text'))
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
    }
    .layoutWeight(1)
    .height(62)
    .padding(0)
    .enabled(!this.isDialogBusy())
    .backgroundColor(this.isFormatSelected(option.format) ? this.getThemeColor() : $r('app.color.app_background'))
    .borderRadius(14)
    .border({
      width: 1,
      color: this.isFormatSelected(option.format) ? this.getThemeColor() : $r('app.color.card_border')
    })
    .onClick(() => {
      if (!this.isDialogBusy()) {
        const nextFormat: string = normalizeNotebookExportFormat(option.format);
        if (!this.isFormatSelected(nextFormat)) {
          this.selectedFormat = nextFormat;
          this.onFormatChange(nextFormat);
        }
      }
    })
  }

  @Builder
  private buildScopeOption(option: NotebookExportScopeOption): void {
    Button() {
      Column({ space: 4 }) {
        Text(option.label)
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.isScopeSelected(option.scope) ? $r('app.color.inverse_text') : $r('app.color.primary_text'))

        Text(option.caption)
          .fontSize(11)
          .fontColor(this.isScopeSelected(option.scope) ? '#DCE7FF' : $r('app.color.secondary_text'))
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
    }
    .layoutWeight(1)
    .height(62)
    .padding(0)
    .enabled(!this.isDialogBusy())
    .backgroundColor(this.isScopeSelected(option.scope) ? this.getThemeColor() : $r('app.color.app_background'))
    .borderRadius(14)
    .border({
      width: 1,
      color: this.isScopeSelected(option.scope) ? this.getThemeColor() : $r('app.color.card_border')
    })
    .onClick(() => {
      if (!this.isDialogBusy()) {
        const nextScope: string = normalizeNotebookExportScope(option.scope);
        if (!this.isScopeSelected(nextScope)) {
          this.selectedScope = nextScope;
          this.onScopeChange(nextScope);
        }
      }
    })
  }

  private isFormatSelected(format: string): boolean {
    return normalizeNotebookExportFormat(this.selectedFormat) === normalizeNotebookExportFormat(format);
  }

  private isScopeSelected(scope: string): boolean {
    return normalizeNotebookExportScope(this.selectedScope) === normalizeNotebookExportScope(scope);
  }

  private isRangeScopeSelected(): boolean {
    return normalizeNotebookExportScope(this.selectedScope) === 'range';
  }

  private isDialogBusy(): boolean {
    return this.isChoosingPath || this.isExporting;
  }

  private getThemeColor(): string {
    return AppTheme.getAccentColor(this.themeColor);
  }

  private getPreviewFileName(): string {
    return buildNotebookExportFileName(this.fileName, this.selectedFormat);
  }
}
