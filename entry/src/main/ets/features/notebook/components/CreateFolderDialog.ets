@Component
export struct CreateFolderDialog {
  @Link title: string;
  @Link selectedColor: string;
  @Prop colorPalette: string[] = [];
  @State private colorR: number = 124;
  @State private colorG: number = 155;
  @State private colorB: number = 255;
  @Prop isSubmitting: boolean = false;
  onCancel: () => void = (): void => {};
  onConfirm: () => void = (): void => {};

  aboutToAppear(): void {
    this.syncRgbFromColor(this.selectedColor);
  }

  private clampColorValue(value: number): number {
    if (!Number.isFinite(value)) {
      return 0;
    }
    if (value < 0) {
      return 0;
    }
    if (value > 255) {
      return 255;
    }
    return Math.round(value);
  }

  private padHex(value: number): string {
    const hex: string = this.clampColorValue(value).toString(16).toUpperCase();
    return hex.length === 1 ? `0${hex}` : hex;
  }

  private composeHexColor(r: number, g: number, b: number): string {
    return `#${this.padHex(r)}${this.padHex(g)}${this.padHex(b)}`;
  }

  private syncRgbFromColor(color: string): void {
    if (typeof color !== 'string' || !/^#[0-9A-Fa-f]{6}$/.test(color)) {
      this.colorR = 124;
      this.colorG = 155;
      this.colorB = 255;
      this.selectedColor = this.composeHexColor(this.colorR, this.colorG, this.colorB);
      return;
    }

    this.colorR = parseInt(color.slice(1, 3), 16);
    this.colorG = parseInt(color.slice(3, 5), 16);
    this.colorB = parseInt(color.slice(5, 7), 16);
    this.selectedColor = this.composeHexColor(this.colorR, this.colorG, this.colorB);
  }

  private applyRgbToColor(): void {
    this.selectedColor = this.composeHexColor(this.colorR, this.colorG, this.colorB);
  }

  @Builder
  private buildRgbSliderRow(label: string, value: number, trackColor: string, onChange: (value: number) => void): void {
    Column({ space: 6 }) {
      Row() {
        Text(label)
          .fontSize(12)
          .fontColor('#475467')
          .layoutWeight(1)
        Text(this.clampColorValue(value).toString())
          .fontSize(12)
          .fontColor('#667085')
      }
      .width('100%')

      Slider({
        value: value,
        min: 0,
        max: 255,
        step: 1,
        style: SliderStyle.OutSet
      })
        .showTips(false)
        .trackColor(trackColor)
        .onChange((nextValue: number) => {
          onChange(this.clampColorValue(nextValue));
        })
    }
    .width('100%')
  }

  build() {
    Column({ space: 16 }) {
      Column({ space: 6 }) {
        Text($r('app.string.folder_create_dialog_title'))
          .fontSize($r('app.float.section_title_size'))
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.primary_text'))

        Text($r('app.string.folder_create_dialog_desc'))
          .fontSize($r('app.float.caption_text_size'))
          .fontColor($r('app.color.secondary_text'))
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      TextInput({
        placeholder: $r('app.string.folder_create_placeholder'),
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

      Text($r('app.string.folder_create_tip'))
        .width('100%')
        .fontSize($r('app.float.caption_text_size'))
        .fontColor($r('app.color.secondary_text'))

      Column({ space: 10 }) {
        Text('文件夹颜色 (RGB)')
          .fontSize($r('app.float.caption_text_size'))
          .fontColor($r('app.color.secondary_text'))

        Row({ space: 10 }) {
          Column() {}
            .width(42)
            .height(42)
            .borderRadius(8)
            .backgroundColor(this.selectedColor)
            .border({ width: 1, color: '#D0D5DD' })

          Text(this.selectedColor)
            .fontSize(12)
            .fontColor('#667085')
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        this.buildRgbSliderRow('R', this.colorR, '#EF4444', (value: number): void => {
          this.colorR = value;
          this.applyRgbToColor();
        })
        this.buildRgbSliderRow('G', this.colorG, '#22C55E', (value: number): void => {
          this.colorG = value;
          this.applyRgbToColor();
        })
        this.buildRgbSliderRow('B', this.colorB, '#3B82F6', (value: number): void => {
          this.colorB = value;
          this.applyRgbToColor();
        })
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

        Button(this.isSubmitting ? $r('app.string.folder_creating') : $r('app.string.folder_create_confirm'))
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
