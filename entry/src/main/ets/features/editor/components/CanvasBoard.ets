import common from '@ohos.app.ability.common';

import {
  BoundingBox,
  clampBoundingBox,
  doBoundingBoxesIntersect,
  getStrokeRenderBoundingBox
} from '../../../common/utils/GeometryUtil';
import { ShapeType } from '../../../domain/entities/CanvasElement';
import { NotebookPageTemplateType } from '../../../domain/entities/NotebookPage';
import { NotebookPageCanvasEntity } from '../../../domain/entities/NotebookPageCanvas';
import { Stroke, StrokePoint } from '../../../domain/entities/Stroke';
import { ToolSetting } from '../../../domain/entities/ToolSetting';
import { PageTemplateRenderer } from '../controllers/PageTemplateRenderer';
import { ShapeRenderer } from '../controllers/ShapeRenderer';
import { StrokeRenderer } from '../controllers/StrokeRenderer';
import { IndexedStrokeRecord } from '../controllers/UndoRedoController';
import { StrokeSpatialHashIndex } from '../controllers/StrokeSpatialHashIndex';
import { EditorDebugSnapshot } from '../viewmodels/EditorDebugSnapshot';
import { DrawingEditorViewModel } from '../viewmodels/DrawingEditorViewModel';
import { EditorSessionRegistry } from '../viewmodels/EditorSessionRegistry';
import { RenderInvalidation } from '../viewmodels/RenderInvalidation';
import { ElementLayer } from './ElementLayer';

interface CanvasSize {
  width: number;
  height: number;
}

interface PageViewportTransform {
  pageWidth: number;
  pageHeight: number;
  viewportWidth: number;
  viewportHeight: number;
  scale: number;
  offsetX: number;
  offsetY: number;
}

interface TouchPairMetrics {
  centerX: number;
  centerY: number;
  distance: number;
}

interface PageRenderRegion {
  x: number;
  y: number;
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

const VIEWPORT_PAGE_MARGIN = 36;
const VIEWPORT_EDGE_MARGIN = 42;
const MIN_ZOOM_SCALE = 1;
const MAX_ZOOM_SCALE = 4;
const DEFAULT_VIEWPORT_WIDTH = 1600;
const DEFAULT_VIEWPORT_HEIGHT = 900;
const PAGE_BORDER_COLOR = '#C4D2E6';
const VIEWPORT_REDRAW_INTERVAL_MS = 16;
export type CanvasBoardContentChangeKind = 'stroke' | 'element';

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
  @Watch('onPageGeometryChanged')
  @Prop pageWidth: number = NotebookPageCanvasEntity.DEFAULT_WIDTH;
  @Watch('onPageGeometryChanged')
  @Prop pageHeight: number = NotebookPageCanvasEntity.DEFAULT_HEIGHT;
  @Watch('onInteractionModeChanged')
  @Prop isPanModeEnabled: boolean = false;
  @Prop elementVersion: number = 0;
  @Prop selectedShapeType: ShapeType = 'rectangle';
  @Link editorSnapshot: EditorDebugSnapshot;
  onContentChanged: (immediate: boolean, kind: CanvasBoardContentChangeKind) => void =
    (_immediate: boolean, _kind: CanvasBoardContentChangeKind): void => {};
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
  private viewportZoomScale: number = MIN_ZOOM_SCALE;
  private viewportOffsetX: number = 0;
  private viewportOffsetY: number = 0;
  private lastViewportWidth: number = 0;
  private lastViewportHeight: number = 0;
  private lastPageWidth: number = 0;
  private lastPageHeight: number = 0;
  private isViewportTransformReady: boolean = false;
  private isDrawingGestureActive: boolean = false;
  private isWorkspacePanActive: boolean = false;
  private isViewportGestureActive: boolean = false;
  private lastWorkspacePanX: number = 0;
  private lastWorkspacePanY: number = 0;
  private viewportGestureStartDistance: number = 1;
  private viewportGestureStartZoomScale: number = MIN_ZOOM_SCALE;
  private viewportGestureStartPageX: number = 0;
  private viewportGestureStartPageY: number = 0;
  private lastViewportRedrawTime: number = 0;

  @State private isCommittedLayerReady: boolean = false;
  @State private isOverlayLayerReady: boolean = false;
  @State private elementLayerPageWidth: number = NotebookPageCanvasEntity.DEFAULT_WIDTH;
  @State private elementLayerPageHeight: number = NotebookPageCanvasEntity.DEFAULT_HEIGHT;
  @State private elementLayerScale: number = 1;
  @State private elementLayerOffsetX: number = 0;
  @State private elementLayerOffsetY: number = 0;

  aboutToAppear(): void {
    this.resolveViewModel();
  }

  build() {
    Stack() {
      Canvas(this.committedContext2D)
        .width('100%')
        .height('100%')
        .backgroundColor('#00000000')
        .onReady(() => {
          this.isCommittedLayerReady = true;
          this.notifyCanvasMetricsChanged();
          this.redrawCommittedLayer();
        })

      Stack() {
        ElementLayer({
          pageId: this.pageId,
          refreshVersion: this.elementVersion
        })
          .width('100%')
          .height('100%')
      }
        .width(this.elementLayerPageWidth)
        .height(this.elementLayerPageHeight)
        .position({
          x: this.elementLayerOffsetX,
          y: this.elementLayerOffsetY
        })
        .scale({
          x: this.elementLayerScale,
          y: this.elementLayerScale,
          centerX: 0,
          centerY: 0
        })
        .clip(true)
        .hitTestBehavior(HitTestMode.None)

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
    .clip(true)
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

    if (this.handleViewportTouch(event, viewModel)) {
      return;
    }

    const toolSetting = viewModel.getToolSetting();
    const activeTool = toolSetting.tool;
    const touch = event.changedTouches.length > 0 ? event.changedTouches[0] : event.touches[0];
    if (!touch) {
      if (activeTool === 'shape') {
        viewModel.cancelShapeDraft();
        this.syncEditorSnapshot();
        this.redrawOverlayLayer();
        return;
      }

      if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.finishDrawingGestureWithoutPoint(viewModel, activeTool, event.type);
      }
      return;
    }

    if (this.handlePanModeTouch(event, touch)) {
      return;
    }

    if (activeTool === 'edit') {
      const point = this.buildPoint(touch, event.type !== TouchType.Down);
      const pageBounds = this.getPageBounds();
      const hitTolerance = this.getEditHitToleranceInPage();

      if (event.type === TouchType.Down) {
        if (point === null) {
          viewModel.clearElementSelection();
        } else {
          if (viewModel.isSelectedElementDeleteHit(point, hitTolerance)) {
            viewModel.deleteSelectedElement();
            this.syncEditorSnapshot();
            this.onContentChanged(true, 'element');
            return;
          }

          viewModel.beginElementEditGesture(point, pageBounds, hitTolerance);
        }

        this.syncEditorSnapshot();
        this.onContentChanged(false, 'element');
        return;
      }

      if (event.type === TouchType.Move) {
        if (point !== null && viewModel.updateElementEditGesture(point, pageBounds)) {
          this.syncEditorSnapshot();
          this.onContentChanged(false, 'element');
        }
        return;
      }

      if (event.type === TouchType.Up) {
        if (point !== null) {
          viewModel.updateElementEditGesture(point, pageBounds);
        }
        const editedElement = viewModel.finishElementEditGesture(pageBounds);
        this.syncEditorSnapshot();
        this.onContentChanged(editedElement !== null, 'element');
        return;
      }

      if (event.type === TouchType.Cancel) {
        viewModel.cancelElementEditGesture();
        this.syncEditorSnapshot();
        this.onContentChanged(false, 'element');
      }
      return;
    }

    if (activeTool === 'text') {
      if (event.type === TouchType.Down) {
        const point = this.buildPoint(touch, false);
        if (point === null) {
          this.beginWorkspacePan(touch);
          return;
        }

        viewModel.appendDebugEvent('CanvasBoard', `insertText x=${Math.round(point.x)} y=${Math.round(point.y)}`);
        viewModel.insertTextElement(point, {
          width: this.getPageWidth(),
          height: this.getPageHeight()
        });
        this.syncEditorSnapshot();
        this.onContentChanged(true, 'element');
      }
      return;
    }

    if (activeTool === 'shape') {
      const point = this.buildPoint(touch, event.type === TouchType.Down ? false : true);

      if (event.type === TouchType.Down) {
        if (point === null) {
          this.beginWorkspacePan(touch);
          return;
        }

        viewModel.appendDebugEvent(
          'CanvasBoard',
          `beginShape shape=${this.selectedShapeType} x=${Math.round(point.x)} y=${Math.round(point.y)}`
        );
        viewModel.beginShapeDraft(point, {
          width: this.getPageWidth(),
          height: this.getPageHeight()
        }, this.selectedShapeType);
        this.syncEditorSnapshot();
        this.redrawOverlayLayer();
        return;
      }

      if (event.type === TouchType.Move) {
        if (point === null) {
          return;
        }

        viewModel.updateShapeDraft(point, {
          width: this.getPageWidth(),
          height: this.getPageHeight()
        });
        this.redrawOverlayLayer();
        return;
      }

      if (event.type === TouchType.Up) {
        if (point !== null) {
          viewModel.updateShapeDraft(point, {
            width: this.getPageWidth(),
            height: this.getPageHeight()
          });
        }

        const createdElement = viewModel.commitShapeDraft({
          width: this.getPageWidth(),
          height: this.getPageHeight()
        });
        this.syncEditorSnapshot();
        this.redrawOverlayLayer();
        if (createdElement !== null) {
          this.onContentChanged(true, 'element');
        }
        return;
      }

      if (event.type === TouchType.Cancel) {
        viewModel.cancelShapeDraft();
        this.syncEditorSnapshot();
        this.redrawOverlayLayer();
      }
      return;
    }

    if (event.type === TouchType.Down) {
      const point = this.buildPoint(touch, false);
      if (point === null) {
        this.beginWorkspacePan(touch);
        return;
      }

      viewModel.appendDebugEvent(
        'CanvasBoard',
        `touchDown tool=${toolSetting.tool} color=${toolSetting.color} width=${toolSetting.width} opacity=${toolSetting.opacity.toFixed(2)}`
      );
      this.isDrawingGestureActive = true;
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
      if (this.isWorkspacePanActive) {
        this.updateWorkspacePan(touch);
        return;
      }

      if (!this.isDrawingGestureActive) {
        return;
      }

      const point = this.buildPoint(touch, true);
      if (point === null) {
        return;
      }

      const activeStroke = viewModel.appendPoint(point);

      if (activeTool === 'eraser') {
        this.redrawOverlayLayer();
      } else if (activeStroke !== null) {
        this.redrawOverlayLayer();
      }
      return;
    }

    if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      if (this.isWorkspacePanActive) {
        this.endWorkspacePan(true);
        return;
      }

      if (!this.isDrawingGestureActive) {
        return;
      }

      const point = this.buildPoint(touch, true);
      viewModel.appendDebugEvent('CanvasBoard', `touchEnd type=${event.type} tool=${activeTool}`);
      if (point !== null) {
        viewModel.appendPoint(point);
      }
      void this.finishStrokeAndRedraw(activeTool);
      return;
    }
  }

  private handlePanModeTouch(event: TouchEvent, touch: TouchObject): boolean {
    if (!this.isPanModeEnabled) {
      return false;
    }

    if (event.type === TouchType.Down) {
      this.beginWorkspacePan(touch);
      return true;
    }

    if (event.type === TouchType.Move) {
      this.updateWorkspacePan(touch);
      return true;
    }

    if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      this.endWorkspacePan(true);
      return true;
    }

    return true;
  }

  private handleViewportTouch(event: TouchEvent, viewModel: DrawingEditorViewModel): boolean {
    const activeTouches: TouchObject[] = this.getActiveTouches(event);
    if (activeTouches.length >= 2) {
      this.cancelDrawingGesture(viewModel);
      this.endWorkspacePan(false);
      const pairMetrics: TouchPairMetrics = this.getTouchPairMetrics(activeTouches[0], activeTouches[1]);
      if (!this.isViewportGestureActive || event.type === TouchType.Down) {
        this.beginViewportGesture(pairMetrics);
      } else {
        this.updateViewportGesture(pairMetrics);
      }
      return true;
    }

    if (this.isViewportGestureActive) {
      if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.endViewportGesture(true);
      }
      return true;
    }

    return false;
  }

  private getActiveTouches(event: TouchEvent): TouchObject[] {
    if (event.touches.length > 0) {
      return event.touches;
    }

    return event.changedTouches;
  }

  private finishDrawingGestureWithoutPoint(
    viewModel: DrawingEditorViewModel,
    activeTool: string,
    touchType: TouchType
  ): void {
    if (!this.isDrawingGestureActive) {
      return;
    }

    viewModel.appendDebugEvent('CanvasBoard', `touchEndWithoutPoint type=${touchType} tool=${activeTool}`);
    void this.finishStrokeAndRedraw(activeTool);
  }

  private cancelDrawingGesture(viewModel: DrawingEditorViewModel): void {
    if (!this.isDrawingGestureActive) {
      return;
    }

    viewModel.cancelStroke();
    this.isDrawingGestureActive = false;
    this.redrawOverlayLayer();
    this.syncEditorSnapshot();
  }

  private async finishStrokeAndRedraw(activeTool: string): Promise<void> {
    const viewModel = this.getViewModel();
    if (!viewModel) {
      return;
    }

    this.isDrawingGestureActive = false;
    viewModel.appendDebugEvent('CanvasBoard', `finishStroke start tool=${activeTool}`);
    const completedStroke = await viewModel.finishStroke();
    this.syncEditorSnapshot();
    if (activeTool === 'eraser') {
      if (!this.tryApplyLatestRenderInvalidation()) {
        this.redrawCommittedLayer();
      }
    } else if (completedStroke !== null && this.isCommittedLayerReady) {
      this.drawStrokeOnViewport(this.committedContext2D, completedStroke);
      this.appendRenderedStroke(completedStroke);
    }
    this.clearOverlayLayer();
    this.onContentChanged(true, 'stroke');
    viewModel.appendDebugEvent('CanvasBoard', 'finishStroke done');
  }

  private buildPoint(touch: TouchObject, clampToPage: boolean): StrokePoint | null {
    const touchRecord = touch as ExtendedTouchObject;
    const pagePoint: StrokePoint | null = this.toPagePoint(touch.x, touch.y, clampToPage);
    if (pagePoint === null) {
      return null;
    }

    return {
      x: pagePoint.x,
      y: pagePoint.y,
      t: this.resolveTouchTimestamp(touchRecord),
      pressure: this.resolveTouchPressure(touchRecord)
    };
  }

  private redrawCommittedLayer(useFastRendering: boolean = false): void {
    if (!this.isCommittedLayerReady) {
      return;
    }

    const shouldRebuildRenderCache = !useFastRendering;
    if (shouldRebuildRenderCache) {
      this.clearRenderedStrokeState();
    }

    const size = this.getCanvasSize(this.committedContext2D);
    const transform = this.getPageViewportTransform(size);
    this.syncElementLayerTransform(transform);
    const visibleRegion = this.getVisiblePageRegion(transform);
    this.committedContext2D.clearRect(0, 0, size.width, size.height);

    if (visibleRegion !== null) {
      this.committedContext2D.save();
      this.applyPageTransformAndClip(this.committedContext2D, transform);
      PageTemplateRenderer.drawTemplateBackground(
        this.committedContext2D,
        this.templateType,
        transform.pageWidth,
        transform.pageHeight,
        this.paperBackgroundColor,
        visibleRegion
      );

      const viewModel = this.getViewModel();
      if (viewModel) {
        this.drawVisibleStrokes(
          this.committedContext2D,
          viewModel.getStrokesForRendering(),
          visibleRegion,
          useFastRendering,
          shouldRebuildRenderCache
        );
      }

      this.committedContext2D.restore();
    }

    this.drawPageBorder(this.committedContext2D, transform);
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
      const size = this.getCanvasSize(this.overlayContext2D);
      const transform = this.getPageViewportTransform(size);
      this.syncElementLayerTransform(transform);
      this.overlayContext2D.save();
      this.applyPageTransformAndClip(this.overlayContext2D, transform);
      this.drawErasePreview(this.overlayContext2D, viewModel.getActiveErasePath(), viewModel.getErasePreviewWidth());
      this.overlayContext2D.restore();
      return;
    }

    const activeStroke = viewModel.getActiveStroke();
    if (activeStroke) {
      const size = this.getCanvasSize(this.overlayContext2D);
      const transform = this.getPageViewportTransform(size);
      this.syncElementLayerTransform(transform);
      this.overlayContext2D.save();
      this.applyPageTransformAndClip(this.overlayContext2D, transform);
      this.drawPreviewStroke(this.overlayContext2D, activeStroke);
      this.overlayContext2D.restore();
      return;
    }

    const shapeDraft = viewModel.getShapeDraftForRendering();
    if (shapeDraft !== null) {
      const size = this.getCanvasSize(this.overlayContext2D);
      const transform = this.getPageViewportTransform(size);
      this.syncElementLayerTransform(transform);
      this.overlayContext2D.save();
      this.applyPageTransformAndClip(this.overlayContext2D, transform);
      ShapeRenderer.drawShape(this.overlayContext2D, shapeDraft);
      this.overlayContext2D.restore();
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
    this.onCanvasMetricsChanged(this.getPageWidth(), this.getPageHeight());
  }

  private getPageBounds(): CanvasSize {
    return {
      width: this.getPageWidth(),
      height: this.getPageHeight()
    };
  }

  private getEditHitToleranceInPage(): number {
    const size = this.getCanvasSize(this.overlayContext2D);
    const transform = this.getPageViewportTransform(size);
    return Math.max(3, 10 / Math.max(0.01, transform.scale));
  }

  private syncElementLayerTransform(transform: PageViewportTransform): void {
    if (this.elementLayerPageWidth !== transform.pageWidth) {
      this.elementLayerPageWidth = transform.pageWidth;
    }

    if (this.elementLayerPageHeight !== transform.pageHeight) {
      this.elementLayerPageHeight = transform.pageHeight;
    }

    if (this.elementLayerScale !== transform.scale) {
      this.elementLayerScale = transform.scale;
    }

    if (this.elementLayerOffsetX !== transform.offsetX) {
      this.elementLayerOffsetX = transform.offsetX;
    }

    if (this.elementLayerOffsetY !== transform.offsetY) {
      this.elementLayerOffsetY = transform.offsetY;
    }
  }

  private getCanvasSize(context: CanvasRenderingContext2D): CanvasSize {
    return {
      width: context.width > 0 ? context.width : DEFAULT_VIEWPORT_WIDTH,
      height: context.height > 0 ? context.height : DEFAULT_VIEWPORT_HEIGHT
    };
  }

  private drawStroke(context: CanvasRenderingContext2D, stroke: Stroke, useFastRendering: boolean = false): void {
    if (useFastRendering) {
      StrokeRenderer.drawStrokeFast(context, stroke);
      return;
    }

    StrokeRenderer.drawStroke(context, stroke);
  }

  private drawStrokeOnViewport(context: CanvasRenderingContext2D, stroke: Stroke): void {
    const size = this.getCanvasSize(context);
    const transform = this.getPageViewportTransform(size);
    const visibleRegion = this.getVisiblePageRegion(transform);
    if (visibleRegion !== null && this.isStrokeVisible(stroke, visibleRegion)) {
      context.save();
      this.applyPageTransformAndClip(context, transform);
      this.drawStroke(context, stroke);
      context.restore();
    }
    this.drawPageBorder(context, transform);
  }

  private drawVisibleStrokes(
    context: CanvasRenderingContext2D,
    strokes: Stroke[],
    visibleRegion: PageRenderRegion,
    useFastRendering: boolean,
    shouldRebuildRenderCache: boolean
  ): void {
    const visibleBounds = this.toBoundingBox(visibleRegion);
    if (shouldRebuildRenderCache) {
      for (const stroke of strokes) {
        this.appendRenderedStroke(stroke);
        if (this.isStrokeBoundsVisible(stroke, visibleBounds)) {
          this.drawStroke(context, stroke, useFastRendering);
        }
      }
      return;
    }

    if (this.renderedStrokeOrder.length > 0) {
      const visibleStrokeIds = this.getCachedVisibleStrokeIds(visibleBounds);
      for (const strokeId of visibleStrokeIds) {
        const stroke = this.renderedStrokesById.get(strokeId);
        if (stroke !== undefined) {
          this.drawStroke(context, stroke, useFastRendering);
        }
      }
      return;
    }

    for (const stroke of strokes) {
      if (this.isStrokeBoundsVisible(stroke, visibleBounds)) {
        this.drawStroke(context, stroke, useFastRendering);
      }
    }
  }

  private getCachedVisibleStrokeIds(visibleBounds: BoundingBox): string[] {
    if (this.renderedStrokeOrder.length === 0) {
      return [];
    }

    return this.strokeSpatialIndex.queryStrokeIds(visibleBounds)
      .sort((left: string, right: string) => this.getRenderedStrokeIndex(left) - this.getRenderedStrokeIndex(right));
  }

  private isStrokeVisible(stroke: Stroke, visibleRegion: PageRenderRegion): boolean {
    return this.isStrokeBoundsVisible(stroke, this.toBoundingBox(visibleRegion));
  }

  private isStrokeBoundsVisible(stroke: Stroke, visibleBounds: BoundingBox): boolean {
    const strokeBounds = getStrokeRenderBoundingBox(stroke);
    if (strokeBounds === null) {
      return false;
    }

    return doBoundingBoxesIntersect(strokeBounds, visibleBounds);
  }

  private getVisiblePageRegion(transform: PageViewportTransform): PageRenderRegion | null {
    if (transform.scale <= 0 || transform.pageWidth <= 0 || transform.pageHeight <= 0) {
      return null;
    }

    const padding = Math.max(2, 2 / Math.max(0.01, transform.scale));
    const minX = this.clamp((0 - transform.offsetX) / transform.scale - padding, 0, transform.pageWidth);
    const minY = this.clamp((0 - transform.offsetY) / transform.scale - padding, 0, transform.pageHeight);
    const maxX = this.clamp(
      (transform.viewportWidth - transform.offsetX) / transform.scale + padding,
      0,
      transform.pageWidth
    );
    const maxY = this.clamp(
      (transform.viewportHeight - transform.offsetY) / transform.scale + padding,
      0,
      transform.pageHeight
    );

    if (maxX <= minX || maxY <= minY) {
      return null;
    }

    return {
      x: minX,
      y: minY,
      width: maxX - minX,
      height: maxY - minY
    };
  }

  private toBoundingBox(region: PageRenderRegion): BoundingBox {
    return {
      minX: region.x,
      minY: region.y,
      maxX: region.x + region.width,
      maxY: region.y + region.height
    };
  }

  private drawPreviewStroke(context: CanvasRenderingContext2D, stroke: Stroke): void {
    StrokeRenderer.drawPreviewStrokeFast(context, stroke);
  }

  private getPageViewportTransform(size: CanvasSize): PageViewportTransform {
    this.ensureViewportTransform(size);
    return {
      pageWidth: this.getPageWidth(),
      pageHeight: this.getPageHeight(),
      viewportWidth: size.width,
      viewportHeight: size.height,
      scale: this.getViewportTotalScale(size),
      offsetX: this.viewportOffsetX,
      offsetY: this.viewportOffsetY
    };
  }

  private ensureViewportTransform(size: CanvasSize): void {
    const pageWidth = this.getPageWidth();
    const pageHeight = this.getPageHeight();
    const hasGeometryChanged = size.width !== this.lastViewportWidth ||
      size.height !== this.lastViewportHeight ||
      pageWidth !== this.lastPageWidth ||
      pageHeight !== this.lastPageHeight;

    if (!this.isViewportTransformReady || hasGeometryChanged) {
      this.viewportZoomScale = MIN_ZOOM_SCALE;
      const fitScale = this.getFitScale(size, pageWidth, pageHeight);
      this.viewportOffsetX = (size.width - pageWidth * fitScale) / 2;
      this.viewportOffsetY = (size.height - pageHeight * fitScale) / 2;
      this.isViewportTransformReady = true;
      this.lastViewportWidth = size.width;
      this.lastViewportHeight = size.height;
      this.lastPageWidth = pageWidth;
      this.lastPageHeight = pageHeight;
      return;
    }

    this.clampViewportOffset(size);
  }

  private resetViewportTransform(): void {
    this.viewportZoomScale = MIN_ZOOM_SCALE;
    this.viewportOffsetX = 0;
    this.viewportOffsetY = 0;
    this.isViewportTransformReady = false;
    this.endViewportGesture(false);
    this.endWorkspacePan(false);
    this.isDrawingGestureActive = false;
  }

  private getViewportTotalScale(size: CanvasSize): number {
    return this.getFitScale(size, this.getPageWidth(), this.getPageHeight()) * this.viewportZoomScale;
  }

  private getFitScale(size: CanvasSize, pageWidth: number, pageHeight: number): number {
    const availableWidth = Math.max(1, size.width - VIEWPORT_PAGE_MARGIN * 2);
    const availableHeight = Math.max(1, size.height - VIEWPORT_PAGE_MARGIN * 2);
    return Math.max(0.01, Math.min(availableWidth / pageWidth, availableHeight / pageHeight));
  }

  private getPageWidth(): number {
    const normalizedWidth = Number(this.pageWidth);
    if (Number.isFinite(normalizedWidth) && normalizedWidth > 0) {
      return normalizedWidth;
    }

    return NotebookPageCanvasEntity.DEFAULT_WIDTH;
  }

  private getPageHeight(): number {
    const normalizedHeight = Number(this.pageHeight);
    if (Number.isFinite(normalizedHeight) && normalizedHeight > 0) {
      return normalizedHeight;
    }

    return NotebookPageCanvasEntity.DEFAULT_HEIGHT;
  }

  private applyPageTransformAndClip(context: CanvasRenderingContext2D, transform: PageViewportTransform): void {
    context.translate(transform.offsetX, transform.offsetY);
    context.scale(transform.scale, transform.scale);
    context.beginPath();
    context.rect(0, 0, transform.pageWidth, transform.pageHeight);
    context.clip();
  }

  private drawPageBorder(context: CanvasRenderingContext2D, transform: PageViewportTransform): void {
    const left = Math.round(transform.offsetX) + 0.5;
    const top = Math.round(transform.offsetY) + 0.5;
    const width = transform.pageWidth * transform.scale;
    const height = transform.pageHeight * transform.scale;

    context.save();
    context.strokeStyle = PAGE_BORDER_COLOR;
    context.lineWidth = 1;
    context.globalAlpha = 0.92;
    context.beginPath();
    context.moveTo(left, top);
    context.lineTo(left + width, top);
    context.lineTo(left + width, top + height);
    context.lineTo(left, top + height);
    context.closePath();
    context.stroke();
    context.globalAlpha = 1;
    context.restore();
  }

  private toPagePoint(screenX: number, screenY: number, clampToPage: boolean): StrokePoint | null {
    const size = this.getCanvasSize(this.overlayContext2D);
    const transform = this.getPageViewportTransform(size);
    const pageX = (screenX - transform.offsetX) / transform.scale;
    const pageY = (screenY - transform.offsetY) / transform.scale;

    if (!clampToPage && !this.isPagePointWithinBounds(pageX, pageY, transform)) {
      return null;
    }

    return {
      x: this.clamp(pageX, 0, transform.pageWidth),
      y: this.clamp(pageY, 0, transform.pageHeight),
      t: Date.now()
    };
  }

  private isPagePointWithinBounds(pageX: number, pageY: number, transform: PageViewportTransform): boolean {
    return pageX >= 0 && pageX <= transform.pageWidth && pageY >= 0 && pageY <= transform.pageHeight;
  }

  private beginWorkspacePan(touch: TouchObject): void {
    this.isWorkspacePanActive = true;
    this.lastWorkspacePanX = touch.x;
    this.lastWorkspacePanY = touch.y;
  }

  private updateWorkspacePan(touch: TouchObject): void {
    if (!this.isWorkspacePanActive) {
      return;
    }

    const deltaX = touch.x - this.lastWorkspacePanX;
    const deltaY = touch.y - this.lastWorkspacePanY;
    this.lastWorkspacePanX = touch.x;
    this.lastWorkspacePanY = touch.y;
    this.panViewportBy(deltaX, deltaY);
  }

  private endWorkspacePan(redrawFinal: boolean = false): void {
    const wasPanning = this.isWorkspacePanActive;
    this.isWorkspacePanActive = false;
    if (redrawFinal && wasPanning) {
      this.redrawViewportLayers(false);
    }
  }

  private beginViewportGesture(pairMetrics: TouchPairMetrics): void {
    const size = this.getCanvasSize(this.overlayContext2D);
    const transform = this.getPageViewportTransform(size);

    this.isViewportGestureActive = true;
    this.viewportGestureStartDistance = Math.max(1, pairMetrics.distance);
    this.viewportGestureStartZoomScale = this.viewportZoomScale;
    this.viewportGestureStartPageX = (pairMetrics.centerX - transform.offsetX) / transform.scale;
    this.viewportGestureStartPageY = (pairMetrics.centerY - transform.offsetY) / transform.scale;
  }

  private updateViewportGesture(pairMetrics: TouchPairMetrics): void {
    if (!this.isViewportGestureActive) {
      return;
    }

    const size = this.getCanvasSize(this.overlayContext2D);
    const distanceRatio = Math.max(0.1, pairMetrics.distance / Math.max(1, this.viewportGestureStartDistance));
    this.viewportZoomScale = this.clamp(
      this.viewportGestureStartZoomScale * distanceRatio,
      MIN_ZOOM_SCALE,
      MAX_ZOOM_SCALE
    );
    const totalScale = this.getViewportTotalScale(size);
    this.viewportOffsetX = pairMetrics.centerX - this.viewportGestureStartPageX * totalScale;
    this.viewportOffsetY = pairMetrics.centerY - this.viewportGestureStartPageY * totalScale;
    this.clampViewportOffset(size);
    this.redrawViewportLayers(true);
  }

  private endViewportGesture(redrawFinal: boolean = false): void {
    const wasGesturing = this.isViewportGestureActive;
    this.isViewportGestureActive = false;
    if (redrawFinal && wasGesturing) {
      this.redrawViewportLayers(false);
    }
  }

  private panViewportBy(deltaX: number, deltaY: number): void {
    const size = this.getCanvasSize(this.overlayContext2D);
    this.viewportOffsetX += deltaX;
    this.viewportOffsetY += deltaY;
    this.clampViewportOffset(size);
    this.redrawViewportLayers(true);
  }

  private clampViewportOffset(size: CanvasSize): void {
    const scale = this.getViewportTotalScale(size);
    const pageWidth = this.getPageWidth() * scale;
    const pageHeight = this.getPageHeight() * scale;
    this.viewportOffsetX = this.clampAxisOffset(this.viewportOffsetX, size.width, pageWidth);
    this.viewportOffsetY = this.clampAxisOffset(this.viewportOffsetY, size.height, pageHeight);
  }

  private clampAxisOffset(offset: number, viewportLength: number, pageLength: number): number {
    if (pageLength <= viewportLength - VIEWPORT_PAGE_MARGIN * 2) {
      return (viewportLength - pageLength) / 2;
    }

    const minOffset = viewportLength - pageLength - VIEWPORT_EDGE_MARGIN;
    const maxOffset = VIEWPORT_EDGE_MARGIN;
    return this.clamp(offset, minOffset, maxOffset);
  }

  private getTouchPairMetrics(firstTouch: TouchObject, secondTouch: TouchObject): TouchPairMetrics {
    const deltaX = secondTouch.x - firstTouch.x;
    const deltaY = secondTouch.y - firstTouch.y;

    return {
      centerX: (firstTouch.x + secondTouch.x) / 2,
      centerY: (firstTouch.y + secondTouch.y) / 2,
      distance: Math.sqrt(deltaX * deltaX + deltaY * deltaY)
    };
  }

  private redrawViewportLayers(useFastRendering: boolean = false): void {
    if (useFastRendering && !this.shouldRedrawViewportFrame()) {
      return;
    }

    this.redrawCommittedLayer(useFastRendering);
    this.redrawOverlayLayer();
  }

  private shouldRedrawViewportFrame(): boolean {
    const now = Date.now();
    if (now - this.lastViewportRedrawTime < VIEWPORT_REDRAW_INTERVAL_MS) {
      return false;
    }

    this.lastViewportRedrawTime = now;
    return true;
  }

  private clamp(value: number, minValue: number, maxValue: number): number {
    return Math.max(minValue, Math.min(maxValue, value));
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

    this.redrawCommittedLayer();
    return true;
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
    this.resetViewportTransform();
    this.clearRenderedStrokeState();
    this.lastAppliedRenderInvalidationSequence = 0;
    this.resolveViewModel();
  }

  private onCanvasStyleChanged(): void {
    this.redrawCommittedLayer();
    this.redrawOverlayLayer();
  }

  private onPageGeometryChanged(): void {
    this.resetViewportTransform();
    this.notifyCanvasMetricsChanged();
    this.redrawCommittedLayer();
    this.redrawOverlayLayer();
  }

  private onInteractionModeChanged(): void {
    const viewModel = this.getViewModel();
    if (viewModel !== null) {
      this.cancelDrawingGesture(viewModel);
    }
    this.endWorkspacePan(false);
    this.endViewportGesture(false);
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
