import {
  ShapeCanvasElement,
  TRANSPARENT_ELEMENT_BACKGROUND_COLOR
} from '../../../domain/entities/CanvasElement';
import { ShapeRenderer } from '../controllers/ShapeRenderer';

const DEFAULT_SHAPE_ELEMENT: ShapeCanvasElement = {
  id: '',
  pageId: '',
  type: 'shape',
  x: 0,
  y: 0,
  width: 1,
  height: 1,
  rotation: 0,
  zIndex: 0,
  createdAt: 0,
  updatedAt: 0,
  shapeType: 'rectangle',
  geometry: {
    kind: 'rect',
    points: [
      { x: 0, y: 0 },
      { x: 1, y: 1 }
    ]
  },
  strokeColor: '#111827',
  fillColor: TRANSPARENT_ELEMENT_BACKGROUND_COLOR,
  strokeWidth: 2,
  opacity: 1
};

@Component
export struct ShapeElementView {
  @Watch('onElementChanged')
  @Prop element: ShapeCanvasElement = DEFAULT_SHAPE_ELEMENT;

  @State private isCanvasReady: boolean = false;
  private readonly renderingSettings: RenderingContextSettings = new RenderingContextSettings(true);
  private readonly shapeContext: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.renderingSettings);

  build() {
    Canvas(this.shapeContext)
      .width(this.getRenderWidth())
      .height(this.getRenderHeight())
      .position({
        x: this.getRenderX(),
        y: this.getRenderY()
      })
      .backgroundColor('#00000000')
      .zIndex(this.element.zIndex)
      .hitTestBehavior(HitTestMode.None)
      .onReady(() => {
        this.isCanvasReady = true;
        this.redrawShape();
      })
  }

  private onElementChanged(): void {
    this.redrawShape();
  }

  private redrawShape(): void {
    if (!this.isCanvasReady) {
      return;
    }

    const width = this.getRenderWidth();
    const height = this.getRenderHeight();
    this.shapeContext.clearRect(0, 0, width, height);
    ShapeRenderer.drawShape(this.shapeContext, this.element, this.getRenderX(), this.getRenderY());
  }

  private getRenderX(): number {
    return this.element.x - this.getRenderPadding();
  }

  private getRenderY(): number {
    return this.element.y - this.getRenderPadding();
  }

  private getRenderWidth(): number {
    return Math.max(1, this.element.width + this.getRenderPadding() * 2);
  }

  private getRenderHeight(): number {
    return Math.max(1, this.element.height + this.getRenderPadding() * 2);
  }

  private getRenderPadding(): number {
    return Math.max(1, this.element.strokeWidth) / 2 + 2;
  }
}
