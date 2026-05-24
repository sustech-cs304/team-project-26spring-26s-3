import {
  buildNotebookExportFileName,
  NOTEBOOK_EXPORT_FORMAT_OPTIONS,
  NotebookExportFormatOption,
  normalizeNotebookExportFormat
} from '../models/NotebookExportOptions';

@Component
export struct NotebookExportDialog {
  @Link fileName: string;
  @Link outputPath: string;
  @Link selectedFormat: string;
  @Prop notebookTitle: string = '';
  @Prop isChoosingPath: boolean = false;
  onCancel: () => void = (): void => {};
  onChoosePath: () => void = (): void => {};
  onConfirm: () => void = (): void => {};

  build() {
    Column({ space: 16 }) {
      Column({ space: 6 }) {
        Text('导出为…')
          .fontSize($r('app.float.section_title_size'))
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.primary_text'))

        Text(this.notebookTitle.length > 0 ? `笔记本：${this.notebookTitle}` : '选择导出参数，实际导出逻辑后续接入。')
          .fontSize($r('app.float.caption_text_size'))
          .fontColor($r('app.color.secondary_text'))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

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
            .enabled(!this.isChoosingPath)
            .backgroundColor($r('app.color.primary_text'))
            .fontColor($r('app.color.inverse_text'))
            .borderRadius(14)
            .onClick(() => {
              if (!this.isChoosingPath) {
                this.onChoosePath();
              }
            })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      Text(`预览文件：${this.getPreviewFileName()}`)
        .width('100%')
        .fontSize($r('app.float.caption_text_size'))
        .fontColor($r('app.color.secondary_text'))

      Text('当前只保存导出参数与目标位置，PDF/图片写入逻辑后续接入。')
        .width('100%')
        .fontSize(12)
        .fontColor('#8A94A6')

      Row({ space: 12 }) {
        Button('取消')
          .layoutWeight(1)
          .height($r('app.float.button_height'))
          .enabled(!this.isChoosingPath)
          .backgroundColor($r('app.color.app_background'))
          .fontColor($r('app.color.primary_text'))
          .onClick(() => {
            if (!this.isChoosingPath) {
              this.onCancel();
            }
          })

        Button('确认')
          .layoutWeight(1)
          .height($r('app.float.button_height'))
          .enabled(!this.isChoosingPath)
          .backgroundColor($r('app.color.primary_text'))
          .fontColor($r('app.color.inverse_text'))
          .onClick(() => {
            if (!this.isChoosingPath) {
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
    .enabled(!this.isChoosingPath)
    .backgroundColor(this.isFormatSelected(option.format) ? $r('app.color.editor_accent') : $r('app.color.app_background'))
    .borderRadius(14)
    .border({
      width: 1,
      color: this.isFormatSelected(option.format) ? $r('app.color.editor_accent') : $r('app.color.card_border')
    })
    .onClick(() => {
      if (!this.isChoosingPath) {
        this.selectedFormat = option.format;
      }
    })
  }

  private isFormatSelected(format: string): boolean {
    return normalizeNotebookExportFormat(this.selectedFormat) === normalizeNotebookExportFormat(format);
  }

  private getPreviewFileName(): string {
    return buildNotebookExportFileName(this.fileName, this.selectedFormat);
  }
}
