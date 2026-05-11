import {
  ImageCanvasElement
} from '../../../domain/entities/CanvasElement';

const DEFAULT_IMAGE_ELEMENT: ImageCanvasElement = {
  id: '',
  pageId: '',
  type: 'image',
  x: 0,
  y: 0,
  width: 1,
  height: 1,
  rotation: 0,
  zIndex: 0,
  createdAt: 0,
  updatedAt: 0,
  uri: '',
  originalWidth: 1,
  originalHeight: 1,
  opacity: 1
};

@Component
export struct ImageElementView {
  @Prop element: ImageCanvasElement = DEFAULT_IMAGE_ELEMENT;

  build() {
    Image(this.toImageSourceUri(this.element.uri))
      .width(this.element.width)
      .height(this.element.height)
      .position({
        x: this.element.x,
        y: this.element.y
      })
      .objectFit(ImageFit.Contain)
      .opacity(this.element.opacity)
      .zIndex(this.element.zIndex)
      .hitTestBehavior(HitTestMode.None)
  }

  private toImageSourceUri(path: string): string {
    if (path.startsWith('file://') || path.startsWith('http://') || path.startsWith('https://')) {
      return path;
    }

    return `file://${path}`;
  }
}
