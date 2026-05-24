@Entry
@Component
struct Index {
  @State message: string = 'Hosn device test ready';

  build() {
    Row() {
      Column() {
        Text(this.message)
          .fontSize(28)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.Black)
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
    }
    .height('100%')
    .backgroundColor(Color.White)
  }
}
