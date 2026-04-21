import common from '@ohos.app.ability.common';

import {
  BoundingBox,
  clampBoundingBox,
  doBoundingBoxesIntersect
} from '../../../common/utils/GeometryUtil';
import { Stroke, StrokePoint } from '../../../domain/entities/Stroke';
import { ToolSetting } from '../../../domain/entities/ToolSetting';
import { StrokeRenderer } from '../controllers/StrokeRenderer';
import { IndexedStrokeRecord } from '../controllers/UndoRedoController';
import { StrokeSpatialHashIndex } from '../controllers/StrokeSpatialHashIndex';
import { EditorDebugSnapshot } from '../viewmodels/EditorDebugSnapshot';
import { DrawingEditorViewModel } from '../viewmodels/DrawingEditorViewModel';
import { EditorSessionRegistry } from '../viewmodels/EditorSessionRegistry';
import { RenderInvalidation } from '../viewmodels/RenderInvalidation';

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
  private readonly renderedStrokesById: Map<string, Stroke> = new Map<string, Stroke>();
  private renderedStrokeOrder: string[] = [];
  private readonly renderedStrokeIndexById: Map<string, number> = new Map<string, number>();
  private readonly strokeSpatialIndex: StrokeSpatialHashIndex = new StrokeSpatialHashIndex();
  private lastAppliedRenderInvalidationSequence: number = 0;

  @State private isCommittedLayerReady: boolean = false;
  @State private isOverlayLayerReady: boolean = false;

  aboutToAppear(): void {
    this.resolveViewModel();
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
    const viewModel = this.getViewModel();
    if (viewModel) {
      viewModel.appendDebugEvent('CanvasBoard', `canvasRefresh version=${this.canvasVersion}`);
    }
    this.notifyCanvasMetricsChanged();
    if (!this.tryApplyLatestRenderInvalidation()) {
      this.redrawCommittedLayer();
    }
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
      viewModel.appendDebugEvent(
        'CanvasBoard',
        `touchDown tool=${toolSetting.tool} color=${toolSetting.color} width=${toolSetting.width} opacity=${toolSetting.opacity.toFixed(2)}`
      );
      viewModel.beginStroke(point);
      this.syncEditorSnapshot();

      if (activeTool === 'eraser') {
        this.redrawOverlayLayer();
      } else {
        this.redrawOverlayLayer();
      }
      return;
    }

    if (event.type === TouchType.Move) {
      const activeStroke = viewModel.appendPoint(point);

      if (activeTool === 'eraser') {
        this.redrawOverlayLayer();
      } else if (activeStroke !== null) {
        this.redrawOverlayLayer();
      }
      return;
    }

    if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      viewModel.appendDebugEvent('CanvasBoard', `touchEnd type=${event.type} tool=${activeTool}`);
      viewModel.appendPoint(point);
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
    if (activeTool === 'eraser') {
      if (!this.tryApplyLatestRenderInvalidation()) {
        this.redrawCommittedLayer();
      }
    } else if (completedStroke !== null && this.isCommittedLayerReady) {
      this.drawStroke(this.committedContext2D, completedStroke);
      this.appendRenderedStroke(completedStroke);
    }
    this.clearOverlayLayer();
    this.onContentChanged(true);
    viewModel.appendDebugEvent('CanvasBoard', 'finishStroke done');
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

    this.clearRenderedStrokeState();
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
      this.appendRenderedStroke(stroke);
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
    StrokeRenderer.drawStroke(context, stroke);
  }

  private tryApplyLatestRenderInvalidation(): boolean {
    if (!this.isCommittedLayerReady) {
      return false;
    }

    const viewModel = this.getViewModel();
    if (!viewModel) {
      return false;
    }

    const invalidation = viewModel.getRenderInvalidation();
    if (invalidation === null) {
      return false;
    }

    if (invalidation.sequence <= this.lastAppliedRenderInvalidationSequence) {
      return true;
    }

    this.lastAppliedRenderInvalidationSequence = invalidation.sequence;
    if (invalidation.mode === 'full') {
      this.redrawCommittedLayer();
      return true;
    }

    return this.applyPartialRenderInvalidation(invalidation);
  }

  private applyPartialRenderInvalidation(invalidation: RenderInvalidation): boolean {
    this.applyRenderedStrokeMutation(invalidation);
    const dirtyRect = this.clipDirtyRectToCanvas(invalidation.dirtyRect);
    if (dirtyRect === null) {
      return true;
    }

    this.clearCommittedRegion(dirtyRect);

    const candidateStrokeIds = this.strokeSpatialIndex.queryStrokeIds(dirtyRect)
      .sort((left: string, right: string) => this.getRenderedStrokeIndex(left) - this.getRenderedStrokeIndex(right));

    for (const strokeId of candidateStrokeIds) {
      const stroke = this.renderedStrokesById.get(strokeId);
      if (stroke === undefined) {
        continue;
      }

      const strokeBounds = this.strokeSpatialIndex.getBounds(strokeId);
      if (strokeBounds !== null && doBoundingBoxesIntersect(strokeBounds, dirtyRect)) {
        this.drawStroke(this.committedContext2D, stroke);
      }
    }

    return true;
  }

  private applyRenderedStrokeMutation(invalidation: RenderInvalidation): void {
    const removedIdSet = new Set<string>(invalidation.removedStrokeIds);
    for (const strokeId of invalidation.removedStrokeIds) {
      this.renderedStrokesById.delete(strokeId);
      this.strokeSpatialIndex.removeStrokeById(strokeId);
    }

    if (removedIdSet.size > 0) {
      this.renderedStrokeOrder = this.renderedStrokeOrder.filter((strokeId: string) => !removedIdSet.has(strokeId));
      this.rebuildRenderedStrokeIndexMap();
    }

    const sortedAddedRecords = invalidation.addedRecords
      .map((record: IndexedStrokeRecord): IndexedStrokeRecord => ({
        index: record.index,
        stroke: record.stroke
      }))
      .sort((left: IndexedStrokeRecord, right: IndexedStrokeRecord) => left.index - right.index);

    for (const record of sortedAddedRecords) {
      this.cacheRenderedStrokeState(record.stroke);
      const insertionIndex = Math.max(0, Math.min(record.index, this.renderedStrokeOrder.length));
      this.renderedStrokeOrder.splice(insertionIndex, 0, record.stroke.id);
    }

    if (sortedAddedRecords.length > 0) {
      this.rebuildRenderedStrokeIndexMap();
    }
  }

  private appendRenderedStroke(stroke: Stroke): void {
    this.cacheRenderedStrokeState(stroke);
    this.renderedStrokeOrder.push(stroke.id);
    this.renderedStrokeIndexById.set(stroke.id, this.renderedStrokeOrder.length - 1);
  }

  private cacheRenderedStrokeState(stroke: Stroke): void {
    this.renderedStrokesById.set(stroke.id, stroke);
    this.strokeSpatialIndex.upsertStroke(stroke);
  }

  private clearRenderedStrokeState(): void {
    this.renderedStrokesById.clear();
    this.renderedStrokeOrder = [];
    this.renderedStrokeIndexById.clear();
    this.strokeSpatialIndex.clear();
  }

  private rebuildRenderedStrokeIndexMap(): void {
    this.renderedStrokeIndexById.clear();
    for (let index = 0; index < this.renderedStrokeOrder.length; index += 1) {
      this.renderedStrokeIndexById.set(this.renderedStrokeOrder[index], index);
    }
  }

  private getRenderedStrokeIndex(strokeId: string): number {
    const index = this.renderedStrokeIndexById.get(strokeId);
    return index === undefined ? Number.MAX_SAFE_INTEGER : index;
  }

  private clipDirtyRectToCanvas(dirtyRect: BoundingBox | null): BoundingBox | null {
    if (dirtyRect === null) {
      return null;
    }

    const size = this.getCanvasSize(this.committedContext2D);
    return clampBoundingBox(dirtyRect, size.width, size.height);
  }

  private clearCommittedRegion(region: BoundingBox): void {
    const width = region.maxX - region.minX;
    const height = region.maxY - region.minY;
    if (width <= 0 || height <= 0) {
      return;
    }

    this.committedContext2D.clearRect(region.minX, region.minY, width, height);
    this.committedContext2D.fillStyle = '#FFFFFF';
    this.committedContext2D.fillRect(region.minX, region.minY, width, height);
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
    this.clearRenderedStrokeState();
    this.lastAppliedRenderInvalidationSequence = 0;
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
      this.clearRenderedStrokeState();
      this.lastAppliedRenderInvalidationSequence = 0;
      return;
    }

    this.viewModel = EditorSessionRegistry.getOrCreate(
      this.pageId,
      this.getUIContext().getHostContext() as common.Context
    );
  }
}
