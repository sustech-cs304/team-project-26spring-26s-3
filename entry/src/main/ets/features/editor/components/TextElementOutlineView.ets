import { ElementOutlineStyle, TextCanvasElement } from '../../../domain/entities/CanvasElement';

const DEFAULT_TEXT_ELEMENT: TextCanvasElement = {
  id: '',
  pageId: '',
  type: 'text',
  x: 0,
  y: 0,
  width: 1,
  height: 1,
  rotation: 0,
  zIndex: 0,
  createdAt: 0,
  updatedAt: 0,
  content: '',
  color: '#111827',
  fontSize: 18,
  backgroundColor: '#00FFFFFF',
  outline: {
    lineStyle: 'none',
    color: '#111827',
    width: 2
  }
};

@Component
export struct TextElementOutlineView {
  @Watch('onElementChanged')
  @Prop element: TextCanvasElement = DEFAULT_TEXT_ELEMENT;
  @Prop useElementPosition: boolean = true;

  @State private isCanvasReady: boolean = false;
  private readonly renderingSettings: RenderingContextSettings = new RenderingContextSettings(true);
  private readonly outlineContext: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.renderingSettings);

  build() {
    Canvas(this.outlineContext)
      .width(this.element.width)
      .height(this.element.height)
      .position({
        x: this.useElementPosition ? this.element.x : 0,
        y: this.useElementPosition ? this.element.y : 0
      })
      .backgroundColor('#00000000')
      .zIndex(this.element.zIndex + 1)
      .hitTestBehavior(HitTestMode.None)
      .onReady(() => {
        this.isCanvasReady = true;
        this.redrawOutline();
      })
  }

  private onElementChanged(): void {
    this.redrawOutline();
  }

  private redrawOutline(): void {
    if (!this.isCanvasReady) {
      return;
    }

    const width = Math.max(1, this.element.width);
    const height = Math.max(1, this.element.height);
    this.outlineContext.clearRect(0, 0, width, height);
    const outlineWidth = this.getVisibleOutlineWidth(this.element.outline);
    if (outlineWidth <= 0) {
      return;
    }

    this.outlineContext.save();
    this.outlineContext.globalAlpha = 1;
    this.outlineContext.strokeStyle = this.element.outline.color;
    this.outlineContext.lineWidth = outlineWidth;
    this.applyLineDash(this.element.outline, outlineWidth);
    this.outlineContext.strokeRect(
      outlineWidth / 2,
      outlineWidth / 2,
      Math.max(0, width - outlineWidth),
      Math.max(0, height - outlineWidth)
    );
    this.outlineContext.restore();
  }

  private getVisibleOutlineWidth(outline: ElementOutlineStyle): number {
    if (outline.lineStyle === 'none' || outline.width <= 0) {
      return 0;
    }

    return Math.max(1, outline.width);
  }

  private applyLineDash(outline: ElementOutlineStyle, lineWidth: number): void {
    if (this.outlineContext.setLineDash === undefined) {
      return;
    }

    if (outline.lineStyle === 'dashed') {
      this.outlineContext.setLineDash([Math.max(4, lineWidth * 3), Math.max(3, lineWidth * 2)]);
    } else if (outline.lineStyle === 'dotted') {
      this.outlineContext.setLineDash([Math.max(1, lineWidth), Math.max(3, lineWidth * 2)]);
    } else {
      this.outlineContext.setLineDash([]);
    }
  }
}
