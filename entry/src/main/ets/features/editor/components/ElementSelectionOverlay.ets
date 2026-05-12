import { CanvasElement, ShapeCanvasElement, ShapeGeometryPoint } from '../../../domain/entities/CanvasElement';

const SELECTION_COLOR = '#2563EB';
const HANDLE_SIZE = 8;
const HANDLE_OFFSET = -4;
const DELETE_BUTTON_SIZE = 24;
const LINE_SELECTION_PADDING = 10;

@Component
export struct ElementSelectionOverlay {
  @Watch('onElementChanged')
  @Prop element: CanvasElement;

  @State private isLineCanvasReady: boolean = false;
  private readonly lineRenderingSettings: RenderingContextSettings = new RenderingContextSettings(true);
  private readonly lineContext: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.lineRenderingSettings);

  build() {
    if (this.isLineElement()) {
      this.buildLineSelection()
    } else {
      this.buildBoxSelection()
    }
  }

  @Builder
  private buildBoxSelection(): void {
    Stack() {
      Column() {}
        .width(this.element.width)
        .height(this.element.height)
        .border({
          width: 2,
          color: SELECTION_COLOR
        })

      this.buildHandle(HANDLE_OFFSET, HANDLE_OFFSET)
      this.buildHandle(this.element.width - HANDLE_SIZE - HANDLE_OFFSET, HANDLE_OFFSET)
      this.buildHandle(HANDLE_OFFSET, this.element.height - HANDLE_SIZE - HANDLE_OFFSET)
      this.buildHandle(
        this.element.width - HANDLE_SIZE - HANDLE_OFFSET,
        this.element.height - HANDLE_SIZE - HANDLE_OFFSET
      )
      if (this.element.type === 'text') {
        this.buildHandle(HANDLE_OFFSET, this.getBoxMiddleHandleY())
        this.buildHandle(this.element.width - HANDLE_SIZE - HANDLE_OFFSET, this.getBoxMiddleHandleY())
      }
      this.buildDeleteButton(this.getBoxDeleteButtonX(), 6)
    }
    .width(this.element.width)
    .height(this.element.height)
    .position({
      x: this.element.x,
      y: this.element.y
    })
    .zIndex(this.element.zIndex + 10000)
    .hitTestBehavior(HitTestMode.None)
  }

  @Builder
  private buildLineSelection(): void {
    Stack() {
      Canvas(this.lineContext)
        .width(this.getLineOverlayWidth())
        .height(this.getLineOverlayHeight())
        .backgroundColor('#00000000')
        .onReady(() => {
          this.isLineCanvasReady = true;
          this.redrawLineSelection();
        })

      this.buildHandle(
        this.getLineStartPoint().x - this.getLineOverlayX() - HANDLE_SIZE / 2,
        this.getLineStartPoint().y - this.getLineOverlayY() - HANDLE_SIZE / 2
      )
      this.buildHandle(
        this.getLineEndPoint().x - this.getLineOverlayX() - HANDLE_SIZE / 2,
        this.getLineEndPoint().y - this.getLineOverlayY() - HANDLE_SIZE / 2
      )
      this.buildDeleteButton(this.getLineDeleteButtonX(), 6)
    }
    .width(this.getLineOverlayWidth())
    .height(this.getLineOverlayHeight())
    .position({
      x: this.getLineOverlayX(),
      y: this.getLineOverlayY()
    })
    .zIndex(this.element.zIndex + 10000)
    .hitTestBehavior(HitTestMode.None)
  }

  @Builder
  private buildHandle(x: number, y: number): void {
    Column() {}
      .width(HANDLE_SIZE)
      .height(HANDLE_SIZE)
      .position({
        x,
        y
      })
      .backgroundColor('#FFFFFF')
      .border({
        width: 2,
        color: SELECTION_COLOR
      })
      .borderRadius(2)
  }

  @Builder
  private buildDeleteButton(x: number, y: number): void {
    Stack({ alignContent: Alignment.Center }) {
      Text('X')
        .fontSize(12)
        .fontWeight(FontWeight.Bold)
        .fontColor('#FFFFFF')
    }
    .width(DELETE_BUTTON_SIZE)
    .height(DELETE_BUTTON_SIZE)
    .position({
      x,
      y
    })
    .backgroundColor('#DC2626')
    .borderRadius(12)
    .border({
      width: 2,
      color: '#FFFFFF'
    })
    .hitTestBehavior(HitTestMode.None)
  }

  private onElementChanged(): void {
    this.redrawLineSelection();
  }

  private redrawLineSelection(): void {
    if (!this.isLineCanvasReady || !this.isLineElement()) {
      return;
    }

    const width = this.getLineOverlayWidth();
    const height = this.getLineOverlayHeight();
    const startPoint = this.getLineStartPoint();
    const endPoint = this.getLineEndPoint();
    const overlayX = this.getLineOverlayX();
    const overlayY = this.getLineOverlayY();
    this.lineContext.clearRect(0, 0, width, height);
    this.lineContext.strokeStyle = SELECTION_COLOR;
    this.lineContext.lineWidth = 2;
    this.lineContext.lineCap = 'round';
    this.lineContext.beginPath();
    this.lineContext.moveTo(startPoint.x - overlayX, startPoint.y - overlayY);
    this.lineContext.lineTo(endPoint.x - overlayX, endPoint.y - overlayY);
    this.lineContext.stroke();
  }

  private isLineElement(): boolean {
    return this.element.type === 'shape' && this.element.shapeType === 'line' &&
      this.element.geometry.points.length >= 2;
  }

  private getLineElement(): ShapeCanvasElement {
    return this.element as ShapeCanvasElement;
  }

  private getLineStartPoint(): ShapeGeometryPoint {
    if (!this.isLineElement()) {
      return {
        x: this.element.x,
        y: this.element.y
      };
    }

    return this.getLineElement().geometry.points[0];
  }

  private getLineEndPoint(): ShapeGeometryPoint {
    if (!this.isLineElement()) {
      return {
        x: this.element.x + this.element.width,
        y: this.element.y + this.element.height
      };
    }

    return this.getLineElement().geometry.points[1];
  }

  private getLineOverlayX(): number {
    return Math.min(this.getLineStartPoint().x, this.getLineEndPoint().x) - LINE_SELECTION_PADDING;
  }

  private getLineOverlayY(): number {
    return Math.min(this.getLineStartPoint().y, this.getLineEndPoint().y) - LINE_SELECTION_PADDING;
  }

  private getLineOverlayWidth(): number {
    return Math.max(1, Math.abs(this.getLineEndPoint().x - this.getLineStartPoint().x) + LINE_SELECTION_PADDING * 2);
  }

  private getLineOverlayHeight(): number {
    return Math.max(1, Math.abs(this.getLineEndPoint().y - this.getLineStartPoint().y) + LINE_SELECTION_PADDING * 2);
  }

  private getBoxDeleteButtonX(): number {
    return Math.max(0, this.element.width - DELETE_BUTTON_SIZE - 6);
  }

  private getBoxMiddleHandleY(): number {
    return this.element.height / 2 - HANDLE_SIZE / 2;
  }

  private getLineDeleteButtonX(): number {
    return Math.max(0, this.getLineOverlayWidth() - DELETE_BUTTON_SIZE - 6);
  }
}
