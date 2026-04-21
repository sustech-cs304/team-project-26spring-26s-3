import common from '@ohos.app.ability.common';

import { Stroke, StrokePoint } from '../../../domain/entities/Stroke';
import { ToolSetting } from '../../../domain/entities/ToolSetting';
import { StrokeRenderer } from '../controllers/StrokeRenderer';
import { EditorDebugSnapshot } from '../viewmodels/EditorDebugSnapshot';
import { DrawingEditorViewModel } from '../viewmodels/DrawingEditorViewModel';
import { EditorSessionRegistry } from '../viewmodels/EditorSessionRegistry';

interface CanvasSize {
  width: number;
  height: number;
}

interface ExtendedTouchObject extends TouchObject {
  pressure?: number;
  force?: number;
  timestamp?: number;
  eventTime?: number;
  t?: number;
}

const LIVE_PREVIEW_MIN_DISTANCE = 0.75;
const MATERIAL_REDRAW_DELAY_MS = 260;

@Component
export struct CanvasBoard {
  @Watch('onPageIdChanged')
  @Prop pageId: string = '';
  @Watch('onCanvasVersionChanged')
  @Prop canvasVersion: number = 0;
  @Link editorSnapshot: EditorDebugSnapshot;
  onContentChanged: (immediate: boolean) => void = (_immediate: boolean): void => {};
  onCanvasMetricsChanged: (width: number, height: number) => void = (_width: number, _height: number): void => {};
  private viewModel: DrawingEditorViewModel | null = null;

  private readonly committedRenderingSettings: RenderingContextSettings = new RenderingContextSettings(true);
  private readonly overlayRenderingSettings: RenderingContextSettings = new RenderingContextSettings(true);
  private readonly committedContext2D: CanvasRenderingContext2D =
    new CanvasRenderingContext2D(this.committedRenderingSettings);
  private readonly overlayContext2D: CanvasRenderingContext2D =
    new CanvasRenderingContext2D(this.overlayRenderingSettings);
  private lastLivePreviewPoint: StrokePoint | null = null;
  private materialRedrawTimerId: number = -1;

  @State private isCommittedLayerReady: boolean = false;
  @State private isOverlayLayerReady: boolean = false;

  aboutToAppear(): void {
    this.resolveViewModel();
  }

  aboutToDisappear(): void {
    this.clearScheduledMaterialRedraw();
  }

  build() {
    Stack() {
      Canvas(this.committedContext2D)
        .width('100%')
        .height('100%')
        .backgroundColor('#FFFFFF')
        .onReady(() => {
          this.isCommittedLayerReady = true;
          this.notifyCanvasMetricsChanged();
          this.redrawCommittedLayer();
        })

      Canvas(this.overlayContext2D)
        .width('100%')
        .height('100%')
        .backgroundColor('#00000000')
        .onReady(() => {
          this.isOverlayLayerReady = true;
          this.redrawOverlayLayer();
        })
        .onTouch((event: TouchEvent) => {
          this.handleTouch(event);
        })
    }
    .width('100%')
    .height('100%')
  }

  private onCanvasVersionChanged(): void {
    this.clearScheduledMaterialRedraw();
    const viewModel = this.getViewModel();
    if (viewModel) {
      viewModel.appendDebugEvent('CanvasBoard', `canvasRefresh version=${this.canvasVersion}`);
    }
    this.notifyCanvasMetricsChanged();
    this.redrawCommittedLayer();
    this.redrawOverlayLayer();
  }

  private handleTouch(event: TouchEvent): void {
    const viewModel = this.getViewModel();
    if (!viewModel) {
      return;
    }

    const toolSetting = viewModel.getToolSetting();
    const activeTool = toolSetting.tool;
    const touch = event.changedTouches.length > 0 ? event.changedTouches[0] : event.touches[0];
    if (!touch) {
      if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        viewModel.appendDebugEvent('CanvasBoard', `touchEndWithoutPoint type=${event.type} tool=${activeTool}`);
        void this.finishStrokeAndRedraw(activeTool);
      }
      return;
    }

    const point = this.buildPoint(touch);

    if (event.type === TouchType.Down) {
      this.clearScheduledMaterialRedraw();
      viewModel.appendDebugEvent(
        'CanvasBoard',
        `touchDown tool=${toolSetting.tool} color=${toolSetting.color} width=${toolSetting.width} opacity=${toolSetting.opacity.toFixed(2)}`
      );
      viewModel.beginStroke(point);
      this.syncEditorSnapshot();

      if (activeTool === 'eraser') {
        this.lastLivePreviewPoint = null;
        this.redrawOverlayLayer();
      } else {
        this.clearOverlayLayer();
        this.drawLivePreviewPoint(point, toolSetting);
        this.lastLivePreviewPoint = point;
      }
      return;
    }

    if (event.type === TouchType.Move) {
      viewModel.appendPoint(point);

      if (activeTool === 'eraser') {
        this.lastLivePreviewPoint = null;
        this.redrawOverlayLayer();
      } else if (this.shouldDrawLivePreviewSegment(this.lastLivePreviewPoint, point)) {
        this.drawLivePreviewSegment(this.lastLivePreviewPoint, point, toolSetting);
        this.lastLivePreviewPoint = point;
      }
      return;
    }

    if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      viewModel.appendDebugEvent('CanvasBoard', `touchEnd type=${event.type} tool=${activeTool}`);
      viewModel.appendPoint(point);
      if (activeTool !== 'eraser') {
        this.drawLivePreviewSegment(this.lastLivePreviewPoint, point, toolSetting);
      }
      this.lastLivePreviewPoint = null;
      void this.finishStrokeAndRedraw(activeTool);
      return;
    }
  }

  private async finishStrokeAndRedraw(activeTool: string): Promise<void> {
    const viewModel = this.getViewModel();
    if (!viewModel) {
      return;
    }

    viewModel.appendDebugEvent('CanvasBoard', `finishStroke start tool=${activeTool}`);
    const completedStroke = await viewModel.finishStroke();
    this.syncEditorSnapshot();
    if (activeTool === 'eraser' || completedStroke === null) {
      this.redrawCommittedLayer();
    } else if (this.isCommittedLayerReady) {
      StrokeRenderer.drawStrokeFast(this.committedContext2D, completedStroke);
      this.scheduleMaterialRedraw();
    }
    this.clearOverlayLayer();
    this.onContentChanged(true);
    viewModel.appendDebugEvent('CanvasBoard', 'finishStroke done');
  }

  private drawLivePreviewPoint(point: StrokePoint, toolSetting: ToolSetting): void {
    const previewEndPoint: StrokePoint = {
      x: point.x + 0.01,
      y: point.y + 0.01,
      t: point.t,
      pressure: point.pressure
    };
    this.drawLivePreviewSegment(point, previewEndPoint, toolSetting);
  }

  private drawLivePreviewSegment(
    startPoint: StrokePoint | null,
    endPoint: StrokePoint,
    toolSetting: ToolSetting
  ): void {
    if (!this.isOverlayLayerReady || startPoint === null) {
      return;
    }

    this.overlayContext2D.strokeStyle = toolSetting.color;
    this.overlayContext2D.lineCap = toolSetting.tool === 'highlighter' ? 'butt' : 'round';
    this.overlayContext2D.lineJoin = 'round';
    this.overlayContext2D.lineWidth = Math.max(1, toolSetting.width);
    this.overlayContext2D.globalAlpha = this.getLivePreviewOpacity(toolSetting);
    this.overlayContext2D.beginPath();
    this.overlayContext2D.moveTo(startPoint.x, startPoint.y);
    this.overlayContext2D.lineTo(endPoint.x, endPoint.y);
    this.overlayContext2D.stroke();
    this.overlayContext2D.globalAlpha = 1;
  }

  private getLivePreviewOpacity(toolSetting: ToolSetting): number {
    if (toolSetting.tool === 'highlighter') {
      return Math.min(1, Math.max(0.08, toolSetting.opacity * 0.42));
    }

    if (toolSetting.tool === 'pencil') {
      return Math.min(1, Math.max(0.12, toolSetting.opacity * 0.72));
    }

    return Math.min(1, Math.max(0.12, toolSetting.opacity));
  }

  private shouldDrawLivePreviewSegment(startPoint: StrokePoint | null, endPoint: StrokePoint): boolean {
    if (startPoint === null) {
      return false;
    }

    const deltaX = startPoint.x - endPoint.x;
    const deltaY = startPoint.y - endPoint.y;
    return deltaX * deltaX + deltaY * deltaY >= LIVE_PREVIEW_MIN_DISTANCE * LIVE_PREVIEW_MIN_DISTANCE;
  }

  private buildPoint(touch: TouchObject): StrokePoint {
    const touchRecord = touch as ExtendedTouchObject;

    return {
      x: touch.x,
      y: touch.y,
      t: this.resolveTouchTimestamp(touchRecord),
      pressure: this.resolveTouchPressure(touchRecord)
    };
  }

  private redrawCommittedLayer(): void {
    if (!this.isCommittedLayerReady) {
      return;
    }

    const size = this.getCanvasSize(this.committedContext2D);
    this.committedContext2D.clearRect(0, 0, size.width, size.height);
    this.committedContext2D.fillStyle = '#FFFFFF';
    this.committedContext2D.fillRect(0, 0, size.width, size.height);

    const viewModel = this.getViewModel();
    if (!viewModel) {
      return;
    }

    const strokes = viewModel.getStrokesForRendering();
    for (const stroke of strokes) {
      this.drawStroke(this.committedContext2D, stroke);
    }
  }

  private redrawOverlayLayer(): void {
    if (!this.isOverlayLayerReady) {
      return;
    }

    this.clearOverlayLayer();

    const viewModel = this.getViewModel();
    if (!viewModel) {
      return;
    }

    if (viewModel.hasActiveEraseGesture()) {
      this.drawErasePreview(this.overlayContext2D, viewModel.getActiveErasePath(), viewModel.getErasePreviewWidth());
      return;
    }

    const activeStroke = viewModel.getActiveStroke();
    if (activeStroke) {
      this.drawPreviewStroke(this.overlayContext2D, activeStroke);
    }
  }

  private clearOverlayLayer(): void {
    if (!this.isOverlayLayerReady) {
      return;
    }

    const size = this.getCanvasSize(this.overlayContext2D);
    this.overlayContext2D.clearRect(0, 0, size.width, size.height);
  }

  private syncEditorSnapshot(): void {
    const viewModel = this.getViewModel();
    if (!viewModel) {
      return;
    }

    this.editorSnapshot = viewModel.getDebugSnapshot();
  }

  private notifyCanvasMetricsChanged(): void {
    const size = this.getCanvasSize(this.committedContext2D);
    this.onCanvasMetricsChanged(size.width, size.height);
  }

  private getCanvasSize(context: CanvasRenderingContext2D): CanvasSize {
    return {
      width: context.width > 0 ? context.width : 1600,
      height: context.height > 0 ? context.height : 900
    };
  }

  private drawStroke(context: CanvasRenderingContext2D, stroke: Stroke): void {
    StrokeRenderer.drawStroke(context, stroke);
  }

  private drawPreviewStroke(context: CanvasRenderingContext2D, stroke: Stroke): void {
    StrokeRenderer.drawPreviewStroke(context, stroke);
  }

  private scheduleMaterialRedraw(): void {
    if (this.materialRedrawTimerId >= 0) {
      clearTimeout(this.materialRedrawTimerId);
    }

    this.materialRedrawTimerId = setTimeout(() => {
      this.materialRedrawTimerId = -1;
      this.redrawCommittedLayer();
    }, MATERIAL_REDRAW_DELAY_MS);
  }

  private clearScheduledMaterialRedraw(): void {
    if (this.materialRedrawTimerId < 0) {
      return;
    }

    clearTimeout(this.materialRedrawTimerId);
    this.materialRedrawTimerId = -1;
  }

  private drawErasePreview(context: CanvasRenderingContext2D, path: StrokePoint[], width: number): void {
    if (path.length === 0) {
      return;
    }

    const previewWidth = Math.max(8, width);
    context.strokeStyle = '#64748B';
    context.lineCap = 'round';
    context.lineJoin = 'round';
    context.lineWidth = previewWidth;
    context.globalAlpha = 0.16;
    context.beginPath();
    context.moveTo(path[0].x, path[0].y);
    for (let index = 1; index < path.length; index += 1) {
      context.lineTo(path[index].x, path[index].y);
    }
    if (path.length === 1) {
      context.lineTo(path[0].x + 0.01, path[0].y + 0.01);
    }
    context.stroke();

    const cursor = path[path.length - 1];
    context.globalAlpha = 0.9;
    context.lineWidth = 2;
    context.beginPath();
    context.arc(cursor.x, cursor.y, previewWidth / 2, 0, Math.PI * 2);
    context.stroke();
    context.globalAlpha = 1;
  }

  private resolveTouchTimestamp(touch: ExtendedTouchObject): number {
    const candidate = this.getNumericValue(touch.timestamp, touch.eventTime, touch.t);
    if (candidate === undefined) {
      return Date.now();
    }

    if (candidate > 1000000000000000) {
      return candidate / 1000000;
    }

    if (candidate > 1000000000) {
      return candidate;
    }

    return Date.now();
  }

  private resolveTouchPressure(touch: ExtendedTouchObject): number | undefined {
    const candidate = this.getNumericValue(touch.pressure, touch.force);
    if (candidate === undefined || !Number.isFinite(candidate)) {
      return undefined;
    }

    return Math.max(0.12, Math.min(1, candidate));
  }

  private getNumericValue(...values: Array<number | undefined>): number | undefined {
    for (const value of values) {
      const numericValue = Number(value);
      if (Number.isFinite(numericValue) && numericValue > 0) {
        return numericValue;
      }
    }

    return undefined;
  }

  private onPageIdChanged(): void {
    this.clearScheduledMaterialRedraw();
    this.resolveViewModel();
  }

  private getViewModel(): DrawingEditorViewModel | null {
    if (!this.viewModel) {
      this.resolveViewModel();
    }

    return this.viewModel;
  }

  private resolveViewModel(): void {
    if (this.pageId.length === 0) {
      this.viewModel = null;
      return;
    }

    this.viewModel = EditorSessionRegistry.getOrCreate(
      this.pageId,
      this.getUIContext().getHostContext() as common.Context
    );
  }
}
