import { BoundingBox } from '../../../common/utils/GeometryUtil';
import { SelectionController } from '../selection/SelectionController';
import { ResizeHandle, ResizeHandlePoint } from '../selection/SelectionTypes';

const TRANSFORM_COLOR = '#2563EB';
const HANDLE_SIZE = 10;
const HANDLE_OFFSET = -HANDLE_SIZE / 2;

@Component
export struct SelectionTransformOverlay {
  @Watch('onBoundsChanged')
  @Prop bounds: BoundingBox;
  @Watch('onBoundsChanged')
  @Prop handles: ResizeHandle[] = [
    'topLeft',
    'top',
    'topRight',
    'right',
    'bottomRight',
    'bottom',
    'bottomLeft',
    'left'
  ];
  @State private isCanvasReady: boolean = false;
  private readonly renderingSettings: RenderingContextSettings = new RenderingContextSettings(true);
  private readonly transformContext: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.renderingSettings);

  build() {
    Canvas(this.transformContext)
      .width('100%')
      .height('100%')
      .backgroundColor('#00000000')
      .onReady(() => {
        this.isCanvasReady = true;
        this.redrawTransform();
      })
      .zIndex(10000)
      .hitTestBehavior(HitTestMode.None)
  }

  private onBoundsChanged(): void {
    this.redrawTransform();
  }

  private redrawTransform(): void {
    if (!this.isCanvasReady) {
      return;
    }

    const width = this.transformContext.width;
    const height = this.transformContext.height;
    this.transformContext.clearRect(0, 0, width, height);
    this.transformContext.save();
    this.transformContext.strokeStyle = TRANSFORM_COLOR;
    this.transformContext.lineWidth = 2;
    this.transformContext.strokeRect(
      this.bounds.minX,
      this.bounds.minY,
      this.getBoxWidth(),
      this.getBoxHeight()
    );

    for (const handlePoint of SelectionController.getResizeHandlePoints(this.bounds)) {
      if (!this.handles.includes(handlePoint.handle)) {
        continue;
      }

      this.drawHandle(handlePoint);
    }
    this.transformContext.restore();
  }

  private drawHandle(handlePoint: ResizeHandlePoint): void {
    this.transformContext.fillStyle = '#FFFFFF';
    this.transformContext.strokeStyle = TRANSFORM_COLOR;
    this.transformContext.lineWidth = 2;
    this.transformContext.beginPath();
    this.transformContext.rect(
      handlePoint.x + HANDLE_OFFSET,
      handlePoint.y + HANDLE_OFFSET,
      HANDLE_SIZE,
      HANDLE_SIZE
    );
    this.transformContext.fill();
    this.transformContext.stroke();
  }

  private getBoxWidth(): number {
    return Math.max(1, this.bounds.maxX - this.bounds.minX);
  }

  private getBoxHeight(): number {
    return Math.max(1, this.bounds.maxY - this.bounds.minY);
  }
}
