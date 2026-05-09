import common from '@ohos.app.ability.common';

import {
  BoundingBox,
  clampBoundingBox,
  doBoundingBoxesIntersect
} from '../../../common/utils/GeometryUtil';
import { NotebookPageTemplateType } from '../../../domain/entities/NotebookPage';
import { Stroke, StrokePoint } from '../../../domain/entities/Stroke';
import { ToolSetting } from '../../../domain/entities/ToolSetting';
import { PageTemplateRenderer } from '../controllers/PageTemplateRenderer';
import { IncrementalPreviewSession, StrokeRenderer } from '../controllers/StrokeRenderer';
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

const COMMITTED_TILE_SIZE = 256;

@Component
export struct CanvasBoard {
  @Watch('onPageIdChanged')
  @Prop pageId: string = '';
  @Watch('onCanvasVersionChanged')
  @Prop canvasVersion: number = 0;
  @Watch('onCanvasStyleChanged')
  @Prop templateType: NotebookPageTemplateType = NotebookPageTemplateType.BLANK;
  @Watch('onCanvasStyleChanged')
  @Prop paperBackgroundColor: string = '#FFFFFF';
  @Link editorSnapshot: EditorDebugSnapshot;
  onContentChanged: (immediate: boolean) => void = (_immediate: boolean): void => {};
  onCanvasMetricsChanged: (width: number, height: number) => void = (_width: number, _height: number): void => {};
  private viewModel: DrawingEditorViewModel | null = null;

  private readonly committedRenderingSettings: RenderingContextSettings = new RenderingContextSettings(true);
  private readonly stablePreviewRenderingSettings: RenderingContextSettings = new RenderingContextSettings(true);
  private readonly overlayRenderingSettings: RenderingContextSettings = new RenderingContextSettings(true);
  private readonly committedContext2D: CanvasRenderingContext2D =
    new CanvasRenderingContext2D(this.committedRenderingSettings);
  private readonly stablePreviewContext2D: CanvasRenderingContext2D =
    new CanvasRenderingContext2D(this.stablePreviewRenderingSettings);
  private readonly overlayContext2D: CanvasRenderingContext2D =
    new CanvasRenderingContext2D(this.overlayRenderingSettings);
  private readonly renderedStrokesById: Map<string, Stroke> = new Map<string, Stroke>();
  private renderedStrokeOrder: string[] = [];
  private readonly renderedStrokeIndexById: Map<string, number> = new Map<string, number>();
  private readonly strokeSpatialIndex: StrokeSpatialHashIndex = new StrokeSpatialHashIndex();
  private lastAppliedRenderInvalidationSequence: number = 0;
  private activePreviewSession: IncrementalPreviewSession | null = null;

  @State private isCommittedLayerReady: boolean = false;
  @State private isStablePreviewLayerReady: boolean = false;
  @State private isOverlayLayerReady: boolean = false;

  aboutToAppear(): void {
    this.resolveViewModel();
  }

  build() {
    Stack() {
      Canvas(this.committedContext2D)
        .width('100%')
        .height('100%')
        .backgroundColor(this.paperBackgroundColor)
        .onReady(() => {
          this.isCommittedLayerReady = true;
          this.notifyCanvasMetricsChanged();
          this.redrawCommittedLayer();
        })

      Canvas(this.stablePreviewContext2D)
        .width('100%')
        .height('100%')
        .backgroundColor('#00000000')
        .onReady(() => {
          this.isStablePreviewLayerReady = true;
          this.redrawOverlayLayer();
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
      const activeStroke = viewModel.beginStroke(point);
      this.syncEditorSnapshot();

      if (activeTool === 'eraser') {
        this.redrawOverlayLayer();
      } else if (activeStroke !== null) {
        this.resetActivePreviewSession();
        this.renderActiveStrokePreview(activeStroke);
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
        this.renderActiveStrokePreview(activeStroke);
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
    this.clearPreviewLayers();
    this.resetActivePreviewSession();
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
    PageTemplateRenderer.drawTemplateBackground(
      this.committedContext2D,
      this.templateType,
      size.width,
      size.height,
      this.paperBackgroundColor
    );

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
    if (!this.isOverlayLayerReady || !this.isStablePreviewLayerReady) {
      return;
    }

    this.clearPreviewLayers();
    this.resetActivePreviewSession();

    const viewModel = this.getViewModel();
    if (!viewModel) {
      return;
    }

    if (viewModel.hasActiveEraseGesture()) {
      this.drawErasePreview(this.overlayContext2D, viewModel.getActiveErasePath(), viewModel.getErasePreviewWidth());
      return;
    }

    const activeStroke = viewModel.getActiveStrokeForRendering();
    if (activeStroke) {
      this.rebuildActivePreviewLayers(activeStroke);
    }
  }

  private clearOverlayLayer(): void {
    if (!this.isOverlayLayerReady) {
      return;
    }

    const size = this.getCanvasSize(this.overlayContext2D);
    this.overlayContext2D.clearRect(0, 0, size.width, size.height);
  }

  private clearStablePreviewLayer(): void {
    if (!this.isStablePreviewLayerReady) {
      return;
    }

    const size = this.getCanvasSize(this.stablePreviewContext2D);
    this.stablePreviewContext2D.clearRect(0, 0, size.width, size.height);
  }

  private clearPreviewLayers(): void {
    this.clearStablePreviewLayer();
    this.clearOverlayLayer();
  }

  private clearStablePreviewRegion(region: BoundingBox): void {
    const width = region.maxX - region.minX;
    const height = region.maxY - region.minY;
    if (width <= 0 || height <= 0) {
      return;
    }

    this.stablePreviewContext2D.clearRect(region.minX, region.minY, width, height);
  }

  private clearOverlayRegion(region: BoundingBox): void {
    const width = region.maxX - region.minX;
    const height = region.maxY - region.minY;
    if (width <= 0 || height <= 0) {
      return;
    }

    this.overlayContext2D.clearRect(region.minX, region.minY, width, height);
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

  private drawClippedPreviewStroke(
    context: CanvasRenderingContext2D,
    clipRect: BoundingBox,
    stroke: Stroke
  ): void {
    const width = clipRect.maxX - clipRect.minX;
    const height = clipRect.maxY - clipRect.minY;
    if (width <= 0 || height <= 0) {
      return;
    }

    context.save();
    context.beginPath();
    context.rect(clipRect.minX, clipRect.minY, width, height);
    context.clip();
    this.drawPreviewStroke(context, stroke);
    context.restore();
  }

  private renderActiveStrokePreview(stroke: Stroke): void {
    if (!this.isOverlayLayerReady || !this.isStablePreviewLayerReady) {
      return;
    }

    const update = StrokeRenderer.buildIncrementalPreviewUpdate(stroke, this.activePreviewSession);
    if (!update.shouldDraw) {
      return;
    }

    if (update.requiresFullRedraw || update.dirtyRect === null) {
      this.rebuildActivePreviewLayers(stroke);
      return;
    }

    if (update.promoteStroke !== null && update.promoteDirtyRect !== null) {
      this.clearStablePreviewRegion(update.promoteDirtyRect);
      this.drawClippedPreviewStroke(this.stablePreviewContext2D, update.promoteDirtyRect, update.promoteStroke);
    }

    this.clearOverlayRegion(update.dirtyRect);
    this.drawClippedPreviewStroke(this.overlayContext2D, update.dirtyRect, update.renderStroke);
    this.activePreviewSession = update.nextSession;
  }

  private rebuildActivePreviewLayers(stroke: Stroke): void {
    this.clearPreviewLayers();

    const stableStroke = StrokeRenderer.buildStablePreviewStroke(stroke);
    if (stableStroke !== null && stableStroke.points.length > 0) {
      this.drawPreviewStroke(this.stablePreviewContext2D, stableStroke);
    }

    const renderUpdate = StrokeRenderer.buildIncrementalPreviewUpdate(stroke, null);
    this.drawPreviewStroke(this.overlayContext2D, renderUpdate.renderStroke);
    this.activePreviewSession = renderUpdate.nextSession;
  }

  private resetActivePreviewSession(): void {
    this.activePreviewSession = null;
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
    const dirtyRects = this.clipDirtyRectsToCanvas(invalidation.dirtyRects);
    if (dirtyRects.length === 0) {
      return true;
    }

    for (const tileBounds of this.buildCommittedTileBoundsForDirtyRects(dirtyRects)) {
      this.redrawCommittedTile(tileBounds);
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

  private clipDirtyRectsToCanvas(dirtyRects: BoundingBox[]): BoundingBox[] {
    const size = this.getCanvasSize(this.committedContext2D);
    const clippedDirtyRects: BoundingBox[] = [];

    for (const dirtyRect of dirtyRects) {
      const clippedDirtyRect = clampBoundingBox(dirtyRect, size.width, size.height);
      if (clippedDirtyRect !== null) {
        clippedDirtyRects.push(clippedDirtyRect);
      }
    }

    return clippedDirtyRects;
  }

  private clearCommittedRegion(region: BoundingBox): void {
    const width = region.maxX - region.minX;
    const height = region.maxY - region.minY;
    if (width <= 0 || height <= 0) {
      return;
    }

    this.committedContext2D.clearRect(region.minX, region.minY, width, height);
    const size = this.getCanvasSize(this.committedContext2D);
    PageTemplateRenderer.drawTemplateBackground(
      this.committedContext2D,
      this.templateType,
      size.width,
      size.height,
      this.paperBackgroundColor,
      {
        x: region.minX,
        y: region.minY,
        width: width,
        height: height
      }
    );
  }

  private redrawCommittedTile(tileBounds: BoundingBox): void {
    this.clearCommittedRegion(tileBounds);

    const candidateStrokeIds = this.strokeSpatialIndex.queryStrokeIds(tileBounds)
      .sort((left: string, right: string) => this.getRenderedStrokeIndex(left) - this.getRenderedStrokeIndex(right));

    this.committedContext2D.save();
    this.committedContext2D.beginPath();
    this.committedContext2D.rect(
      tileBounds.minX,
      tileBounds.minY,
      tileBounds.maxX - tileBounds.minX,
      tileBounds.maxY - tileBounds.minY
    );
    this.committedContext2D.clip();

    for (const strokeId of candidateStrokeIds) {
      const stroke = this.renderedStrokesById.get(strokeId);
      if (stroke === undefined) {
        continue;
      }

      const strokeBounds = this.strokeSpatialIndex.getBounds(strokeId);
      if (strokeBounds !== null && doBoundingBoxesIntersect(strokeBounds, tileBounds)) {
        this.drawStroke(this.committedContext2D, stroke);
      }
    }

    this.committedContext2D.restore();
  }

  private buildCommittedTileBoundsForDirtyRects(dirtyRects: BoundingBox[]): BoundingBox[] {
    const tileBoundsList: BoundingBox[] = [];
    const tileKeySet = new Set<string>();
    const canvasSize = this.getCanvasSize(this.committedContext2D);

    for (const dirtyRect of dirtyRects) {
      const safeMaxX = Math.max(dirtyRect.minX, dirtyRect.maxX - 0.001);
      const safeMaxY = Math.max(dirtyRect.minY, dirtyRect.maxY - 0.001);
      const startTileX = Math.floor(dirtyRect.minX / COMMITTED_TILE_SIZE);
      const endTileX = Math.floor(safeMaxX / COMMITTED_TILE_SIZE);
      const startTileY = Math.floor(dirtyRect.minY / COMMITTED_TILE_SIZE);
      const endTileY = Math.floor(safeMaxY / COMMITTED_TILE_SIZE);

      for (let tileX = startTileX; tileX <= endTileX; tileX += 1) {
        for (let tileY = startTileY; tileY <= endTileY; tileY += 1) {
          const tileKey = `${tileX}:${tileY}`;
          if (tileKeySet.has(tileKey)) {
            continue;
          }

          const tileBounds = clampBoundingBox({
            minX: tileX * COMMITTED_TILE_SIZE,
            minY: tileY * COMMITTED_TILE_SIZE,
            maxX: (tileX + 1) * COMMITTED_TILE_SIZE,
            maxY: (tileY + 1) * COMMITTED_TILE_SIZE
          }, canvasSize.width, canvasSize.height);

          if (tileBounds !== null) {
            tileKeySet.add(tileKey);
            tileBoundsList.push(tileBounds);
          }
        }
      }
    }

    return tileBoundsList;
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
    this.clearPreviewLayers();
    this.resetActivePreviewSession();
    this.resolveViewModel();
  }

  private onCanvasStyleChanged(): void {
    this.redrawCommittedLayer();
    this.redrawOverlayLayer();
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
      this.clearPreviewLayers();
      this.resetActivePreviewSession();
      return;
    }

    this.viewModel = EditorSessionRegistry.getOrCreate(
      this.pageId,
      this.getUIContext().getHostContext() as common.Context
    );
  }
}
