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
  opacity: 1,
  outline: {
    lineStyle: 'none',
    color: '#111827',
    width: 2
  }
};

@Component
export struct ImageElementView {
  @Watch('onElementChanged')
  @Prop element: ImageCanvasElement = DEFAULT_IMAGE_ELEMENT;
  @Watch('onRenderVersionChanged')
  @Prop renderVersion: number = 0;

  @State private isOutlineCanvasReady: boolean = false;
  private readonly outlineRenderingSettings: RenderingContextSettings = new RenderingContextSettings(true);
  private readonly outlineContext: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.outlineRenderingSettings);

  build() {
    Stack() {
      Image(this.toImageSourceUri(this.element.uri))
        .width(this.element.width)
        .height(this.element.height)
        .objectFit(ImageFit.Fill)
        .opacity(this.element.opacity)
        .hitTestBehavior(HitTestMode.None)

      Canvas(this.outlineContext)
        .width(this.element.width)
        .height(this.element.height)
        .backgroundColor('#00000000')
        .hitTestBehavior(HitTestMode.None)
        .onReady(() => {
          this.isOutlineCanvasReady = true;
          this.redrawOutline();
        })
    }
      .width(this.element.width)
      .height(this.element.height)
      .position({
        x: this.element.x,
        y: this.element.y
      })
      .zIndex(this.element.zIndex)
      .hitTestBehavior(HitTestMode.None)
  }

  private onElementChanged(): void {
    this.redrawOutline();
  }

  private onRenderVersionChanged(): void {
    this.redrawOutline();
  }

  private redrawOutline(): void {
    if (!this.isOutlineCanvasReady) {
      return;
    }

    const width = Math.max(1, this.element.width);
    const height = Math.max(1, this.element.height);
    this.outlineContext.clearRect(0, 0, width, height);
    if (this.element.outline.lineStyle === 'none' || this.element.outline.width <= 0) {
      return;
    }

    const lineWidth = Math.max(1, this.element.outline.width);
    this.outlineContext.save();
    this.outlineContext.strokeStyle = this.element.outline.color;
    this.outlineContext.lineWidth = lineWidth;
    this.applyLineDash(lineWidth);
    this.outlineContext.strokeRect(
      lineWidth / 2,
      lineWidth / 2,
      Math.max(0, width - lineWidth),
      Math.max(0, height - lineWidth)
    );
    this.outlineContext.restore();
  }

  private applyLineDash(lineWidth: number): void {
    if (this.outlineContext.setLineDash === undefined) {
      return;
    }

    if (this.element.outline.lineStyle === 'dashed') {
      this.outlineContext.setLineDash([Math.max(4, lineWidth * 3), Math.max(3, lineWidth * 2)]);
    } else if (this.element.outline.lineStyle === 'dotted') {
      this.outlineContext.setLineDash([Math.max(1, lineWidth), Math.max(3, lineWidth * 2)]);
    } else {
      this.outlineContext.setLineDash([]);
    }
  }

  private toImageSourceUri(path: string): string {
    if (path.startsWith('file://')) {
      if (path.startsWith('file:///')) {
        return path;
      }
      const rawLocalPath: string = path.substring('file://'.length);
      return rawLocalPath.startsWith('/') ? `file://${rawLocalPath}` : `file:///${rawLocalPath}`;
    }

    if (path.startsWith('http://') || path.startsWith('https://')) {
      return path;
    }

    return `file://${path}`;
  }
}
