import common from '@ohos.app.ability.common';
import { CanvasViewport, defaultViewport } from '../canvas/CanvasTypes';
import { ToolType } from '../models/Stroke';
import { NotePageRepository } from '../services/NotePageRepository';
import { StrokeRepository } from '../services/StrokeRepository';
import { Point, Stroke } from '../models/Stroke';

const DEFAULT_STROKE_COLOR = '#111827';
const DEFAULT_STROKE_WIDTH = 4;
const ERASER_COLOR = '#000000';
const MIN_VIEWPORT_SCALE = 0.5;
const MAX_VIEWPORT_SCALE = 3;

type InteractionMode = 'draw' | 'move';

interface CanvasSize {
  width: number;
  height: number;
}

interface CanvasLogicalBounds {
  left: number;
  top: number;
  right: number;
  bottom: number;
}

@Component
export struct CanvasEditor {
  @Prop notebookId: string = '';
  @Watch('handlePageChange') @Prop pageId: string = '';
  @Prop pageIndex: number = 0;
  @Watch('handlePageChange') @Prop pageUpdatedAt: number = 0;
  @StorageLink('page_thumbnail_refresh_signal') private pageThumbnailRefreshSignal: string = '';

  @State private strokes: Stroke[] = [];
  @State private saveStatus: string = 'Saved';
  @State private errorMessage: string = '';
  @State private currentTool: ToolType = 'pen';
  @State private currentColor: string = DEFAULT_STROKE_COLOR;
  @State private currentWidth: number = DEFAULT_STROKE_WIDTH;
  @State private interactionMode: InteractionMode = 'draw';
  @State private viewport: CanvasViewport = defaultViewport;

  private readonly renderingSettings: RenderingContextSettings = new RenderingContextSettings(true);
  private readonly guideContext2D: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.renderingSettings);
  private readonly strokeContext2D: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.renderingSettings);
  private readonly colorPresets: string[] = ['#111827', '#1D4ED8', '#059669', '#DC2626', '#7C3AED'];
  private readonly widthPresets: number[] = [3, 6, 10, 18];
  private activeStroke: Stroke | null = null;
  private isGuideCanvasReady: boolean = false;
  private isStrokeCanvasReady: boolean = false;
  private panReferencePoint: Point | null = null;
  private strokeRepository?: StrokeRepository;
  private pageRepository?: NotePageRepository;

  async aboutToAppear(): Promise<void> {
    await this.loadCurrentPage();
  }

  build() {
    Column({ space: 14 }) {
      this.buildToolbar()

      if (this.strokes.length === 0 && !this.activeStroke) {
        Text(`Mode: ${this.interactionMode === 'draw' ? 'Draw' : 'Move'}. Current tool: ${this.currentTool === 'pen' ? 'Pen' : 'Eraser'}.`)
          .width('100%')
          .fontSize(12)
          .fontColor('#64748B')
          .textAlign(TextAlign.Start)
      }

      if (this.errorMessage.length > 0) {
        Text(this.errorMessage)
          .width('100%')
          .fontSize(12)
          .fontColor('#B91C1C')
          .textAlign(TextAlign.Start)
      }

      Stack({ alignContent: Alignment.TopStart }) {
        Canvas(this.guideContext2D)
          .width('100%')
          .height('100%')
          .backgroundColor('#FFFDF7')
          .borderRadius(20)
          .onReady(() => {
            this.isGuideCanvasReady = true;
            this.redrawGuideLayer();
          })

        Canvas(this.strokeContext2D)
          .width('100%')
          .height('100%')
          .backgroundColor(Color.Transparent)
          .borderRadius(20)
          .onReady(() => {
            this.isStrokeCanvasReady = true;
            this.redrawStrokeLayer();
          })
          .onTouch((event: TouchEvent) => {
            this.handleTouch(event);
          })
      }
      .layoutWeight(1)
      .width('100%')
      .backgroundColor('#F8FAFC')
      .borderRadius(24)
      .border({
        width: 1,
        color: '#E2E8F0'
      })
      .clip(true)
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private buildToolbar(): void {
    Column({ space: 12 }) {
      Row({ space: 12 }) {
        Column({ space: 4 }) {
          Text(`Canvas Page ${this.pageIndex + 1}`)
            .fontSize(20)
            .fontWeight(FontWeight.Medium)
            .fontColor('#0F172A')
            .width('100%')
            .textAlign(TextAlign.Start)

          Text(`${this.strokes.length} stroke(s) | ${this.saveStatus}`)
            .fontSize(12)
            .fontColor('#64748B')
            .width('100%')
            .textAlign(TextAlign.Start)
        }
        .layoutWeight(1)

        Button('Undo')
          .backgroundColor('#E2E8F0')
          .fontColor('#334155')
          .borderRadius(12)
          .enabled(this.strokes.length > 0)
          .onClick(() => {
            void this.undoLastStroke();
          })

        Button('Clear')
          .backgroundColor('#FEE2E2')
          .fontColor('#B91C1C')
          .borderRadius(12)
          .enabled(this.strokes.length > 0)
          .onClick(() => {
            void this.clearCanvas();
          })
      }
      .width('100%')

      Row({ space: 12 }) {
        Text('Mode')
          .fontSize(13)
          .fontColor('#475569')

        Button('Draw')
          .backgroundColor(this.interactionMode === 'draw' ? '#1D4ED8' : '#E2E8F0')
          .fontColor(this.interactionMode === 'draw' ? '#FFFFFF' : '#334155')
          .borderRadius(12)
          .onClick(() => {
            this.interactionMode = 'draw';
            this.panReferencePoint = null;
          })

        Button('Move')
          .backgroundColor(this.interactionMode === 'move' ? '#0F172A' : '#E2E8F0')
          .fontColor(this.interactionMode === 'move' ? '#FFFFFF' : '#334155')
          .borderRadius(12)
          .onClick(() => {
            this.interactionMode = 'move';
            this.panReferencePoint = null;
          })

        Text('Zoom')
          .fontSize(13)
          .fontColor('#475569')
          .margin({ left: 8 })

        Button('-')
          .backgroundColor('#E2E8F0')
          .fontColor('#334155')
          .borderRadius(12)
          .onClick(() => {
            this.zoomBy(0.85);
          })

        Button(`${Math.round(this.viewport.scale * 100)}%`)
          .backgroundColor('#E0F2FE')
          .fontColor('#0F172A')
          .borderRadius(12)
          .onClick(() => {
            this.resetViewport();
          })

        Button('+')
          .backgroundColor('#E2E8F0')
          .fontColor('#334155')
          .borderRadius(12)
          .onClick(() => {
            this.zoomBy(1.15);
          })
      }
      .width('100%')

      Row({ space: 12 }) {
        Text('Tool')
          .fontSize(13)
          .fontColor('#475569')

        Button('Pen')
          .backgroundColor(this.currentTool === 'pen' ? '#1D4ED8' : '#E2E8F0')
          .fontColor(this.currentTool === 'pen' ? '#FFFFFF' : '#334155')
          .borderRadius(12)
          .onClick(() => {
            this.currentTool = 'pen';
          })

        Button('Eraser')
          .backgroundColor(this.currentTool === 'eraser' ? '#0F172A' : '#E2E8F0')
          .fontColor(this.currentTool === 'eraser' ? '#FFFFFF' : '#334155')
          .borderRadius(12)
          .onClick(() => {
            this.currentTool = 'eraser';
          })

        Text('Width')
          .fontSize(13)
          .fontColor('#475569')
          .margin({ left: 8 })

        ForEach(this.widthPresets, (width: number) => {
          Button(`${width}`)
            .backgroundColor(this.currentWidth === width ? '#0F172A' : '#E2E8F0')
            .fontColor(this.currentWidth === width ? '#FFFFFF' : '#334155')
            .borderRadius(12)
            .onClick(() => {
              this.currentWidth = width;
            })
        }, (width: number) => `${width}`)
      }
      .width('100%')

      Row({ space: 10 }) {
        Text('Color')
          .fontSize(13)
          .fontColor('#475569')

        ForEach(this.colorPresets, (color: string) => {
          Button('')
            .width(28)
            .height(28)
            .backgroundColor(color)
            .borderRadius(14)
            .border({
              width: this.currentColor === color ? 3 : 1,
              color: this.currentColor === color ? '#0F172A' : '#CBD5E1'
            })
            .enabled(this.currentTool === 'pen')
            .opacity(this.currentTool === 'pen' ? 1 : 0.45)
            .onClick(() => {
              this.currentColor = color;
            })
        }, (color: string) => color)
      }
      .width('100%')
    }
    .width('100%')
  }

  private handlePageChange(): void {
    void this.loadCurrentPage();
  }

  private async loadCurrentPage(): Promise<void> {
    this.activeStroke = null;
    this.panReferencePoint = null;
    this.errorMessage = '';
    this.saveStatus = 'Loading...';

    if (this.pageId.length === 0) {
      this.strokes = [];
      this.saveStatus = 'Idle';
      this.redraw();
      return;
    }

    try {
      this.strokes = await this.getStrokeRepository().listByPage(this.pageId);
      this.saveStatus = 'Saved';
      this.redraw();
    } catch (error) {
      this.strokes = [];
      this.saveStatus = 'Save failed';
      this.errorMessage = `Failed to load strokes: ${this.stringifyError(error)}`;
      this.redraw();
    }
  }

  private handleTouch(event: TouchEvent): void {
    if (!this.isStrokeCanvasReady || this.pageId.length === 0) {
      return;
    }

    const touch = this.pickTouchPoint(event);
    if (!touch) {
      if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        if (this.interactionMode === 'move') {
          this.panReferencePoint = null;
        } else {
          void this.finishStroke();
        }
      }
      return;
    }

    if (this.interactionMode === 'move') {
      this.handlePanTouch(event, touch);
      return;
    }

    const canvasPoint = this.toCanvasPoint(touch);
    if (event.type === TouchType.Down) {
      this.beginStroke(canvasPoint);
      return;
    }

    if (event.type === TouchType.Move) {
      this.appendPoint(canvasPoint);
      return;
    }

    if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      this.appendPoint(canvasPoint);
      void this.finishStroke();
    }
  }

  private handlePanTouch(event: TouchEvent, touch: Point): void {
    if (event.type === TouchType.Down) {
      this.panReferencePoint = touch;
      return;
    }

    if ((event.type === TouchType.Move || event.type === TouchType.Up) && this.panReferencePoint) {
      const deltaX = touch.x - this.panReferencePoint.x;
      const deltaY = touch.y - this.panReferencePoint.y;
      this.viewport = this.createViewport(
        this.viewport.offsetX + deltaX,
        this.viewport.offsetY + deltaY,
        this.viewport.scale
      );
      this.panReferencePoint = touch;
      this.redraw();
    }

    if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      this.panReferencePoint = null;
    }
  }

  private beginStroke(point: Point): void {
    this.errorMessage = '';
    this.saveStatus = 'Editing...';
    const strokeColor = this.currentTool === 'eraser' ? ERASER_COLOR : this.currentColor;
    this.activeStroke = {
      id: this.generateStrokeId(),
      pageId: this.pageId,
      tool: this.currentTool,
      color: strokeColor,
      width: this.currentWidth,
      points: [point],
      createdAt: Date.now()
    };
    this.drawStrokeSegment(this.activeStroke, point, point, 1);
  }

  private appendPoint(point: Point): void {
    if (!this.activeStroke) {
      return;
    }

    const lastPoint = this.activeStroke.points[this.activeStroke.points.length - 1];
    if (lastPoint && this.isSamePoint(lastPoint, point)) {
      return;
    }

    this.activeStroke.points = [...this.activeStroke.points, point];
    if (lastPoint) {
      this.drawStrokeSegment(this.activeStroke, lastPoint, point, 1);
    }
  }

  private async finishStroke(): Promise<void> {
    if (!this.activeStroke) {
      return;
    }

    const nextStroke: Stroke = {
      id: this.activeStroke.id,
      pageId: this.activeStroke.pageId,
      tool: this.activeStroke.tool,
      color: this.activeStroke.color,
      width: this.activeStroke.width,
      points: this.normalizePoints(this.activeStroke.points),
      createdAt: this.activeStroke.createdAt
    };
    this.activeStroke = null;

    if (nextStroke.points.length < 1) {
      this.redraw();
      return;
    }

    if (nextStroke.points.length === 1) {
      const point = nextStroke.points[0];
      const tailPoint: Point = {
        x: point.x + 0.1,
        y: point.y + 0.1,
        t: point.t
      };
      nextStroke.points = [
        point,
        tailPoint
      ];
    }

    this.strokes = [...this.strokes, nextStroke];
    this.redrawStrokeLayer();
    await this.persistStrokes();
  }

  private async undoLastStroke(): Promise<void> {
    if (this.strokes.length === 0) {
      return;
    }

    this.strokes = this.strokes.slice(0, this.strokes.length - 1);
    this.redraw();
    await this.persistStrokes();
  }

  private async clearCanvas(): Promise<void> {
    this.activeStroke = null;
    this.strokes = [];
    this.redraw();
    await this.persistStrokes();
  }

  private async persistStrokes(): Promise<void> {
    if (this.pageId.length === 0) {
      return;
    }

    this.saveStatus = 'Saving...';
    this.errorMessage = '';
    try {
      const strokeIds = this.strokes.map((item: Stroke) => item.id);
      await this.getStrokeRepository().saveAll(this.pageId, this.strokes);
      await this.getPageRepository().updateStrokeIds(this.notebookId, this.pageId, strokeIds);
      this.pageThumbnailRefreshSignal = `${this.pageId}|${Date.now()}|${strokeIds.length}`;
      this.saveStatus = 'Saved';
    } catch (error) {
      this.saveStatus = 'Save failed';
      this.errorMessage = `Failed to save strokes: ${this.stringifyError(error)}`;
    }
  }

  private redraw(): void {
    this.redrawGuideLayer();
    this.redrawStrokeLayer();
  }

  private redrawGuideLayer(): void {
    if (!this.isGuideCanvasReady) {
      return;
    }

    const width = this.guideContext2D.width > 0 ? this.guideContext2D.width : 1600;
    const height = this.guideContext2D.height > 0 ? this.guideContext2D.height : 900;
    this.guideContext2D.clearRect(0, 0, width, height);
    this.guideContext2D.fillStyle = '#FFFDF7';
    this.guideContext2D.fillRect(0, 0, width, height);
    this.drawGuides(width, height);
  }

  private redrawStrokeLayer(): void {
    if (!this.isStrokeCanvasReady) {
      return;
    }

    const width = this.strokeContext2D.width > 0 ? this.strokeContext2D.width : 1600;
    const height = this.strokeContext2D.height > 0 ? this.strokeContext2D.height : 900;
    this.strokeContext2D.clearRect(0, 0, width, height);

    this.strokes.forEach((item: Stroke) => {
      this.drawStroke(item, 1);
    });

    if (this.activeStroke) {
      this.drawStroke(this.activeStroke, 1);
    }
  }

  private drawGuides(width: number, height: number): void {
    this.guideContext2D.beginPath();
    this.guideContext2D.lineWidth = Math.max(1, this.viewport.scale);
    this.guideContext2D.strokeStyle = '#E2E8F0';

    const bounds = this.getVisibleLogicalBounds(width, height);
    const startY = this.getGuideStartY(bounds.top);
    const startX = bounds.left - 64;
    const endX = bounds.right + 64;

    let y = startY;
    while (y <= bounds.bottom + 64) {
      const startPoint = this.toViewportPoint(this.createPoint(startX, y));
      const endPoint = this.toViewportPoint(this.createPoint(endX, y));
      this.guideContext2D.moveTo(startPoint.x, startPoint.y);
      this.guideContext2D.lineTo(endPoint.x, endPoint.y);
      y += 64;
    }

    this.guideContext2D.stroke();
  }

  private drawStroke(stroke: Stroke, alpha: number): void {
    if (stroke.points.length === 0) {
      return;
    }

    if (stroke.points.length === 1) {
      const point = stroke.points[0];
      this.drawStrokeSegment(stroke, point, point, alpha);
      return;
    }

    let previousPoint = stroke.points[0];
    stroke.points.slice(1).forEach((point: Point) => {
      this.drawStrokeSegment(stroke, previousPoint, point, alpha);
      previousPoint = point;
    });
  }

  private drawStrokeSegment(stroke: Stroke, startPoint: Point, endPoint: Point, alpha: number): void {
    if (!this.isStrokeCanvasReady) {
      return;
    }

    const color = alpha >= 1 ? stroke.color : this.withAlpha(stroke.color, alpha);
    const isSinglePoint = this.isSamePoint(startPoint, endPoint);
    const logicalTargetPoint = isSinglePoint
      ? this.createOffsetPoint(endPoint)
      : endPoint;
    const viewStartPoint = this.toViewportPoint(startPoint);
    const viewTargetPoint = this.toViewportPoint(logicalTargetPoint);

    this.strokeContext2D.beginPath();
    this.strokeContext2D.globalCompositeOperation = stroke.tool === 'eraser' ? 'destination-out' : 'source-over';
    this.strokeContext2D.lineWidth = Math.max(1, stroke.width * this.viewport.scale);
    this.strokeContext2D.lineCap = 'round';
    this.strokeContext2D.lineJoin = 'round';
    this.strokeContext2D.strokeStyle = color;
    this.strokeContext2D.moveTo(viewStartPoint.x, viewStartPoint.y);
    this.strokeContext2D.lineTo(viewTargetPoint.x, viewTargetPoint.y);
    this.strokeContext2D.stroke();
    this.strokeContext2D.globalCompositeOperation = 'source-over';
  }

  private pickTouchPoint(event: TouchEvent): Point | null {
    const source = event.changedTouches.length > 0 ? event.changedTouches[0] : event.touches[0];
    if (!source) {
      return null;
    }

    return {
      x: source.x,
      y: source.y,
      t: Date.now()
    };
  }

  private normalizePoints(points: Point[]): Point[] {
    return points.filter((item: Point, index: number) => {
      if (index === 0) {
        return true;
      }
      const previous = points[index - 1];
      return !this.isSamePoint(previous, item);
    });
  }

  private isSamePoint(left: Point, right: Point): boolean {
    return Math.abs(left.x - right.x) < 0.5 && Math.abs(left.y - right.y) < 0.5;
  }

  private createOffsetPoint(point: Point): Point {
    return {
      x: point.x + 0.1,
      y: point.y + 0.1,
      t: point.t
    };
  }

  private createPoint(x: number, y: number): Point {
    return {
      x,
      y,
      t: Date.now()
    };
  }

  private toViewportPoint(point: Point): Point {
    return this.createPoint(
      point.x * this.viewport.scale + this.viewport.offsetX,
      point.y * this.viewport.scale + this.viewport.offsetY
    );
  }

  private toCanvasPoint(point: Point): Point {
    const scale = this.viewport.scale <= 0 ? 1 : this.viewport.scale;
    return this.createPoint(
      (point.x - this.viewport.offsetX) / scale,
      (point.y - this.viewport.offsetY) / scale
    );
  }

  private zoomBy(factor: number): void {
    const currentSize = this.getCanvasSize();
    const centerX = currentSize.width / 2;
    const centerY = currentSize.height / 2;
    const nextScale = this.clampScale(this.viewport.scale * factor);
    const centerCanvasX = (centerX - this.viewport.offsetX) / this.viewport.scale;
    const centerCanvasY = (centerY - this.viewport.offsetY) / this.viewport.scale;
    this.viewport = this.createViewport(
      centerX - centerCanvasX * nextScale,
      centerY - centerCanvasY * nextScale,
      nextScale
    );
    this.redraw();
  }

  private resetViewport(): void {
    this.viewport = this.createViewport(defaultViewport.offsetX, defaultViewport.offsetY, defaultViewport.scale);
    this.panReferencePoint = null;
    this.redraw();
  }

  private clampScale(scale: number): number {
    return Math.max(MIN_VIEWPORT_SCALE, Math.min(MAX_VIEWPORT_SCALE, scale));
  }

  private createViewport(offsetX: number, offsetY: number, scale: number): CanvasViewport {
    return {
      offsetX,
      offsetY,
      scale
    };
  }

  private getCanvasSize(): CanvasSize {
    const width = this.strokeContext2D.width > 0 ? this.strokeContext2D.width : 1600;
    const height = this.strokeContext2D.height > 0 ? this.strokeContext2D.height : 900;
    return {
      width,
      height
    };
  }

  private getVisibleLogicalBounds(width: number, height: number): CanvasLogicalBounds {
    const scale = this.viewport.scale <= 0 ? 1 : this.viewport.scale;
    return {
      left: (0 - this.viewport.offsetX) / scale,
      top: (0 - this.viewport.offsetY) / scale,
      right: (width - this.viewport.offsetX) / scale,
      bottom: (height - this.viewport.offsetY) / scale
    };
  }

  private getGuideStartY(top: number): number {
    if (top <= 72) {
      return 72;
    }

    const offset = top - 72;
    return 72 + Math.floor(offset / 64) * 64;
  }

  private withAlpha(color: string, alpha: number): string {
    const normalized = color.startsWith('#') ? color.slice(1) : color;
    if (normalized.length !== 6) {
      return color;
    }

    const opacity = Math.max(0, Math.min(255, Math.round(alpha * 255)));
    return `#${normalized}${opacity.toString(16).padStart(2, '0')}`;
  }

  private getStrokeRepository(): StrokeRepository {
    if (!this.strokeRepository) {
      this.strokeRepository = new StrokeRepository(this.getHostContext());
    }
    return this.strokeRepository;
  }

  private getPageRepository(): NotePageRepository {
    if (!this.pageRepository) {
      this.pageRepository = new NotePageRepository(this.getHostContext());
    }
    return this.pageRepository;
  }

  private getHostContext(): common.Context {
    const hostContext = this.getUIContext().getHostContext();
    if (!hostContext) {
      throw new Error('UI host context is unavailable.');
    }
    return hostContext as common.Context;
  }

  private generateStrokeId(): string {
    return `stroke_${Date.now()}_${Math.floor(Math.random() * 100000)}`;
  }

  private stringifyError(error: Object): string {
    return JSON.stringify(error);
  }
}
