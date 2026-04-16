import { AppInitializer } from '../app/AppInitializer';
import { AppRouter } from '../app/AppRouter';

@Entry
@Component
struct Index {
  private hasRedirected: boolean = false;

  aboutToAppear(): void {
    if (this.hasRedirected) {
      return;
    }

    this.hasRedirected = true;
    AppInitializer.initialize();
    AppRouter.replace(AppRouter.getDefaultStartRoute());
  }

  build() {
    Column() {
      Text($r('app.string.boot_loading'))
        .fontSize($r('app.float.section_title_size'))
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.primary_text'))
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor($r('app.color.app_background'))
    .padding({
      left: $r('app.float.page_padding_horizontal'),
      right: $r('app.float.page_padding_horizontal')
    })
  }
}
