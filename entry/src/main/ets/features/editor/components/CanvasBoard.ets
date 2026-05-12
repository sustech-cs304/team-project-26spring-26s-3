import common from '@ohos.app.ability.common';

import {
  BoundingBox,
  clampBoundingBox,
  doBoundingBoxesIntersect,
  getStrokeRenderBoundingBox
} from '../../../common/utils/GeometryUtil';
import { clampElementFrameToBounds } from '../../../common/utils/ElementBoundsUtil';
import { CanvasElement, ShapeType, TextCanvasElement } from '../../../domain/entities/CanvasElement';
import { NotebookPageTemplateType } from '../../../domain/entities/NotebookPage';
import { NotebookPageCanvasEntity } from '../../../domain/entities/NotebookPageCanvas';
import { Stroke, StrokePoint } from '../../../domain/entities/Stroke';
import { ToolSetting, ToolType } from '../../../domain/entities/ToolSetting';
import { PageTemplateRenderer } from '../controllers/PageTemplateRenderer';
import { IncrementalPreviewSession, StrokeRenderer } from '../controllers/StrokeRenderer';
import { ShapeRenderer } from '../controllers/ShapeRenderer';
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

const COMMITTED_TILE_SIZE = 256;
const VIEWPORT_PAGE_MARGIN = 36;
const VIEWPORT_EDGE_MARGIN = 42;
const MIN_ZOOM_SCALE = 1;
const MAX_ZOOM_SCALE = 4;
const DEFAULT_VIEWPORT_WIDTH = 1600;
const DEFAULT_VIEWPORT_HEIGHT = 900;
const PAGE_BORDER_COLOR = '#C4D2E6';
const VIEWPORT_REDRAW_INTERVAL_MS = 16;
const TEXT_EDIT_DOUBLE_TAP_MS = 360;
const TEXT_EDIT_DOUBLE_TAP_DISTANCE = 18;
const INLINE_TEXT_LINE_HEIGHT_FACTOR = 1.35;
const INLINE_TEXT_MAX_LINES = 1000;
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
  @Watch('onActiveToolChanged')
  @Prop activeTool: ToolType = 'pen';
  @Prop elementVersion: number = 0;
  @Prop selectedShapeType: ShapeType = 'rectangle';
  @Link editorSnapshot: EditorDebugSnapshot;
  onContentChanged: (immediate: boolean, kind: CanvasBoardContentChangeKind) => void =
    (_immediate: boolean, _kind: CanvasBoardContentChangeKind): void => {};
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
  private lastEditTapTime: number = 0;
  private lastEditTapElementId: string = '';
  private lastEditTapX: number = 0;
  private lastEditTapY: number = 0;

  @State private isCommittedLayerReady: boolean = false;
  @State private isStablePreviewLayerReady: boolean = false;
  @State private isOverlayLayerReady: boolean = false;
  @State private elementLayerPageWidth: number = NotebookPageCanvasEntity.DEFAULT_WIDTH;
  @State private elementLayerPageHeight: number = NotebookPageCanvasEntity.DEFAULT_HEIGHT;
  @State private elementLayerScale: number = 1;
  @State private elementLayerOffsetX: number = 0;
  @State private elementLayerOffsetY: number = 0;
  @State private inlineTextEditElement: TextCanvasElement | null = null;
  @State private inlineTextEditContent: string = '';
  @State private inlineTextEditX: number = 0;
  @State private inlineTextEditY: number = 0;
  @State private inlineTextEditWidth: number = 1;
  @State private inlineTextEditHeight: number = 1;

  aboutToAppear(): void {
    this.resolveViewModel();
  }

  aboutToDisappear(): void {
    this.commitInlineTextEdit(true);
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

      Canvas(this.stablePreviewContext2D)
        .width('100%')
        .height('100%')
        .backgroundColor('#00000000')
        .onReady(() => {
          this.isStablePreviewLayerReady = true;
          this.redrawOverlayLayer();
        })

      Stack() {
        ElementLayer({
          pageId: this.pageId,
          refreshVersion: this.elementVersion,
          editingElementId: this.getInlineTextEditElementId()
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

      if (this.inlineTextEditElement !== null) {
        this.buildInlineTextSizeProbe(this.inlineTextEditElement)
        this.buildInlineTextEditor(this.inlineTextEditElement)
      }

    }
    .width('100%')
    .height('100%')
    .clip(true)
  }

  @Builder
  private buildInlineTextEditor(element: TextCanvasElement): void {
    Stack({ alignContent: Alignment.TopStart }) {
      this.buildInlineTextDisplay(element)
      this.buildInlineTextInputProxy(element)
    }
      .width(this.getScaledInlineTextWidth())
      .height(this.getScaledInlineTextHeight())
      .position({
        x: this.elementLayerOffsetX + this.inlineTextEditX * this.elementLayerScale,
        y: this.elementLayerOffsetY + this.inlineTextEditY * this.elementLayerScale
      })
      .backgroundColor('#FFFFFF')
      .border({
        width: 2,
        color: '#2563EB'
      })
      .borderRadius(2)
      .zIndex(element.zIndex + 20000)
  }

  @Builder
  private buildInlineTextSizeProbe(element: TextCanvasElement): void {
    TextArea({
      placeholder: 'Text',
      text: this.inlineTextEditContent
    })
      .width(this.getScaledInlineTextWidth())
      .padding({
        left: this.getScaledInlineTextHorizontalPadding(),
        right: this.getScaledInlineTextHorizontalPadding(),
        top: this.getScaledInlineTextVerticalPadding(),
        bottom: this.getScaledInlineTextVerticalPadding()
      })
      .fontSize(this.getScaledInlineTextFontSize(element))
      .lineHeight(this.getInlineTextLineHeight(element))
      .fontFamily('monospace')
      .fontColor(element.color)
      .wordBreak(WordBreak.BREAK_ALL)
      .maxLines(INLINE_TEXT_MAX_LINES)
      .barState(BarState.Off)
      .backgroundColor(Color.Transparent)
      .opacity(0)
      .hitTestBehavior(HitTestMode.None)
      .position({
        x: this.elementLayerOffsetX + this.inlineTextEditX * this.elementLayerScale,
        y: this.elementLayerOffsetY + this.inlineTextEditY * this.elementLayerScale
      })
      .zIndex(element.zIndex + 19999)
      .onAreaChange((_oldValue: Area, newValue: Area) => {
        this.handleInlineTextSizeProbeAreaChange(newValue);
      })
  }

  @Builder
  private buildInlineTextDisplay(element: TextCanvasElement): void {
    TextArea({
      text: this.getInlineTextDisplayContent()
    })
      .width(this.getScaledInlineTextWidth())
      .height(this.getScaledInlineTextHeight())
      .padding({
        left: this.getScaledInlineTextHorizontalPadding(),
        right: this.getScaledInlineTextHorizontalPadding(),
        top: this.getScaledInlineTextVerticalPadding(),
        bottom: this.getScaledInlineTextVerticalPadding()
      })
      .fontSize(this.getScaledInlineTextFontSize(element))
      .lineHeight(this.getInlineTextLineHeight(element))
      .fontFamily('monospace')
      .fontColor(element.color)
      .wordBreak(WordBreak.BREAK_ALL)
      .maxLines(INLINE_TEXT_MAX_LINES)
      .barState(BarState.Off)
      .backgroundColor(Color.Transparent)
      .hitTestBehavior(HitTestMode.None)
  }

  @Builder
  private buildInlineTextInputProxy(element: TextCanvasElement): void {
    TextArea({
      placeholder: 'Text',
      text: this.inlineTextEditContent
    })
      .width(this.getScaledInlineTextWidth())
      .height(this.getScaledInlineTextHeight())
      .position({
        x: 0,
        y: 0
      })
      .padding({
        left: this.getScaledInlineTextHorizontalPadding(),
        right: this.getScaledInlineTextHorizontalPadding(),
        top: this.getScaledInlineTextVerticalPadding(),
        bottom: this.getScaledInlineTextVerticalPadding()
      })
      .fontSize(this.getScaledInlineTextFontSize(element))
      .lineHeight(this.getInlineTextLineHeight(element))
      .fontFamily('monospace')
      .fontColor(Color.Transparent)
      .caretColor('#2563EB')
      .wordBreak(WordBreak.BREAK_ALL)
      .maxLines(INLINE_TEXT_MAX_LINES)
      .barState(BarState.Off)
      .backgroundColor(Color.Transparent)
      .onChange((value: string) => {
        this.inlineTextEditContent = value;
      })
      .onBlur(() => {
        this.commitInlineTextEdit(true);
      })
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
          this.commitInlineTextEdit(true);
          viewModel.clearElementSelection();
        } else {
          if (this.inlineTextEditElement !== null && !this.isPointInsideTextElement(point, this.inlineTextEditElement)) {
            this.commitInlineTextEdit(true);
          }

          if (viewModel.isSelectedElementDeleteHit(point, hitTolerance)) {
            this.commitInlineTextEdit(false);
            viewModel.deleteSelectedElement();
            this.syncEditorSnapshot();
            this.onContentChanged(true, 'element');
            return;
          }

          const selectedElement = viewModel.getSelectedElement();
          if (this.shouldBeginInlineTextEdit(point, selectedElement, hitTolerance)) {
            this.beginInlineTextEdit(selectedElement as TextCanvasElement);
            this.syncEditorSnapshot();
            this.onContentChanged(false, 'element');
            return;
          }

          viewModel.beginElementEditGesture(point, pageBounds, hitTolerance);
          this.recordEditTap(point, viewModel.getSelectedElement());
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

    if (this.inlineTextEditElement !== null) {
      this.commitInlineTextEdit(true);
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
        this.renderActiveStrokePreview(activeStroke);
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
    this.clearPreviewLayers();
    this.resetActivePreviewSession();
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
      const size = this.getCanvasSize(this.overlayContext2D);
      const transform = this.getPageViewportTransform(size);
      this.syncElementLayerTransform(transform);
      this.overlayContext2D.save();
      this.applyPageTransformAndClip(this.overlayContext2D, transform);
      this.drawErasePreview(this.overlayContext2D, viewModel.getActiveErasePath(), viewModel.getErasePreviewWidth());
      this.overlayContext2D.restore();
      return;
    }

    const activeStroke = viewModel.getActiveStrokeForRendering();
    if (activeStroke) {
      const size = this.getCanvasSize(this.overlayContext2D);
      const transform = this.getPageViewportTransform(size);
      this.syncElementLayerTransform(transform);
      this.rebuildActivePreviewLayers(activeStroke);
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
    this.clearPageRegionFromContext(this.stablePreviewContext2D, region);
  }

  private clearOverlayRegion(region: BoundingBox): void {
    this.clearPageRegionFromContext(this.overlayContext2D, region);
  }

  private syncEditorSnapshot(): void {
    const viewModel = this.getViewModel();
    if (!viewModel) {
      return;
    }

    this.editorSnapshot = viewModel.getDebugSnapshot();
  }

  private beginInlineTextEdit(element: TextCanvasElement): void {
    this.inlineTextEditElement = this.cloneTextElement(element);
    this.inlineTextEditX = element.x;
    this.inlineTextEditY = element.y;
    this.inlineTextEditWidth = element.width;
    this.inlineTextEditHeight = element.height;
    this.inlineTextEditContent = element.content;
    this.clampInlineTextEditFrameToBounds();
    this.clearLastEditTap();
  }

  private commitInlineTextEdit(refreshThumbnail: boolean): void {
    if (this.inlineTextEditElement === null) {
      return;
    }

    const editingElementId = this.inlineTextEditElement.id;
    const nextContent = this.inlineTextEditContent;
    const nextFrame = clampElementFrameToBounds({
      x: this.inlineTextEditX,
      y: this.inlineTextEditY,
      width: this.inlineTextEditWidth,
      height: this.inlineTextEditHeight
    }, this.getPageBounds());
    this.inlineTextEditElement = null;
    this.inlineTextEditContent = '';
    this.resetInlineTextEditFrame();
    this.clearLastEditTap();

    const viewModel = this.getViewModel();
    if (viewModel === null) {
      return;
    }

    const updatedElement = viewModel.updateTextElementContentWithFrame(editingElementId, nextContent, nextFrame);
    this.syncEditorSnapshot();
    this.onContentChanged(updatedElement !== null && refreshThumbnail, 'element');
  }

  private clampInlineTextEditFrameToBounds(): void {
    const frame = clampElementFrameToBounds({
      x: this.inlineTextEditX,
      y: this.inlineTextEditY,
      width: this.inlineTextEditWidth,
      height: this.inlineTextEditHeight
    }, this.getPageBounds());
    this.inlineTextEditX = frame.x;
    this.inlineTextEditY = frame.y;
    this.inlineTextEditWidth = frame.width;
    this.inlineTextEditHeight = frame.height;
  }

  private handleInlineTextSizeProbeAreaChange(newValue: Area): void {
    if (this.inlineTextEditElement === null) {
      return;
    }

    const measuredHeight = this.getLengthNumber(newValue.height);
    if (measuredHeight <= 0) {
      return;
    }

    const scale = Math.max(0.01, this.elementLayerScale);
    const pageHeight = measuredHeight / scale;
    const maximumHeight = Math.max(1, this.getPageHeight() - this.inlineTextEditY);
    const nextHeight = Math.ceil(this.clampNumber(pageHeight, 1, maximumHeight));
    if (Math.abs(nextHeight - this.inlineTextEditHeight) >= 1) {
      this.inlineTextEditHeight = nextHeight;
    }
  }

  private getInlineTextLineHeight(element: TextCanvasElement): number {
    return this.getScaledInlineTextFontSize(element) * INLINE_TEXT_LINE_HEIGHT_FACTOR;
  }

  private getScaledInlineTextWidth(): number {
    return Math.max(36, this.inlineTextEditWidth * this.elementLayerScale);
  }

  private getScaledInlineTextHeight(): number {
    return Math.max(32, this.inlineTextEditHeight * this.elementLayerScale);
  }

  private getScaledInlineTextFontSize(element: TextCanvasElement): number {
    return Math.max(8, element.fontSize * this.elementLayerScale);
  }

  private getScaledInlineTextHorizontalPadding(): number {
    return Math.max(4, 8 * this.elementLayerScale);
  }

  private getScaledInlineTextVerticalPadding(): number {
    return Math.max(3, 6 * this.elementLayerScale);
  }

  private getInlineTextDisplayContent(): string {
    return this.inlineTextEditContent.length === 0 ? 'Text' : this.inlineTextEditContent;
  }

  private cloneTextElement(element: TextCanvasElement): TextCanvasElement {
    return {
      id: element.id,
      pageId: element.pageId,
      type: 'text',
      x: element.x,
      y: element.y,
      width: element.width,
      height: element.height,
      rotation: element.rotation,
      zIndex: element.zIndex,
      createdAt: element.createdAt,
      updatedAt: element.updatedAt,
      content: element.content,
      color: element.color,
      fontSize: element.fontSize,
      backgroundColor: element.backgroundColor
    };
  }

  private getLengthNumber(value: Length): number {
    const numericValue = Number(value);
    if (Number.isFinite(numericValue)) {
      return numericValue;
    }

    const parsedValue = Number.parseFloat(`${value}`);
    return Number.isFinite(parsedValue) ? parsedValue : 0;
  }

  private clampNumber(value: number, minimumValue: number, maximumValue: number): number {
    if (!Number.isFinite(value)) {
      return minimumValue;
    }

    return Math.min(Math.max(value, minimumValue), maximumValue);
  }

  private resetInlineTextEditFrame(): void {
    this.inlineTextEditX = 0;
    this.inlineTextEditY = 0;
    this.inlineTextEditWidth = 1;
    this.inlineTextEditHeight = 1;
  }

  private getInlineTextEditElementId(): string {
    return this.inlineTextEditElement === null ? '' : this.inlineTextEditElement.id;
  }

  private shouldBeginInlineTextEdit(
    point: StrokePoint,
    selectedElement: CanvasElement | null,
    hitTolerance: number
  ): boolean {
    if (selectedElement === null || selectedElement.type !== 'text') {
      return false;
    }

    if (!this.isPointInsideTextElementContent(point, selectedElement, hitTolerance)) {
      return false;
    }

    if (this.lastEditTapElementId !== selectedElement.id) {
      return false;
    }

    const elapsedTime = Date.now() - this.lastEditTapTime;
    const deltaX = point.x - this.lastEditTapX;
    const deltaY = point.y - this.lastEditTapY;
    const distance = Math.sqrt(deltaX * deltaX + deltaY * deltaY);
    return elapsedTime >= 0 && elapsedTime <= TEXT_EDIT_DOUBLE_TAP_MS &&
      distance <= Math.max(hitTolerance * 2, TEXT_EDIT_DOUBLE_TAP_DISTANCE);
  }

  private recordEditTap(point: StrokePoint, element: CanvasElement | null): void {
    if (element === null || element.type !== 'text') {
      this.clearLastEditTap();
      return;
    }

    this.lastEditTapTime = Date.now();
    this.lastEditTapElementId = element.id;
    this.lastEditTapX = point.x;
    this.lastEditTapY = point.y;
  }

  private clearLastEditTap(): void {
    this.lastEditTapTime = 0;
    this.lastEditTapElementId = '';
    this.lastEditTapX = 0;
    this.lastEditTapY = 0;
  }

  private isPointInsideTextElement(point: StrokePoint, element: TextCanvasElement): boolean {
    return point.x >= element.x && point.x <= element.x + element.width &&
      point.y >= element.y && point.y <= element.y + element.height;
  }

  private isPointInsideTextElementContent(point: StrokePoint, element: TextCanvasElement, hitTolerance: number): boolean {
    const margin = Math.min(Math.max(4, hitTolerance), Math.max(0, Math.min(element.width, element.height) / 3));
    return point.x >= element.x + margin && point.x <= element.x + element.width - margin &&
      point.y >= element.y + margin && point.y <= element.y + element.height - margin;
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

    const size = this.getCanvasSize(context);
    const transform = this.getPageViewportTransform(size);
    const viewportClipRect = this.toViewportBoundingBox(clipRect, transform);
    if (viewportClipRect === null) {
      return;
    }

    context.save();
    this.applyPageTransformAndClip(context, transform);
    context.beginPath();
    context.rect(clipRect.minX, clipRect.minY, width, height);
    context.clip();
    this.drawPreviewStroke(context, stroke);
    context.restore();
  }

  private drawPreviewStrokeOnViewport(context: CanvasRenderingContext2D, stroke: Stroke): void {
    const size = this.getCanvasSize(context);
    const transform = this.getPageViewportTransform(size);
    const visibleRegion = this.getVisiblePageRegion(transform);
    if (visibleRegion === null || !this.isStrokeVisible(stroke, visibleRegion)) {
      return;
    }

    context.save();
    this.applyPageTransformAndClip(context, transform);
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
      this.drawPreviewStrokeOnViewport(this.stablePreviewContext2D, stableStroke);
    }

    const renderUpdate = StrokeRenderer.buildIncrementalPreviewUpdate(stroke, null);
    this.drawPreviewStrokeOnViewport(this.overlayContext2D, renderUpdate.renderStroke);
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
    const dirtyRects = this.clipDirtyRectsToPage(invalidation.dirtyRects);
    if (dirtyRects.length === 0) {
      return true;
    }

    const size = this.getCanvasSize(this.committedContext2D);
    const transform = this.getPageViewportTransform(size);
    const visibleRegion = this.getVisiblePageRegion(transform);
    if (visibleRegion === null) {
      return true;
    }

    const visibleBounds = this.toBoundingBox(visibleRegion);
    let hasRedrawnTile = false;
    for (const tileBounds of this.buildCommittedTileBoundsForDirtyRects(dirtyRects)) {
      if (this.redrawCommittedTile(tileBounds, transform, visibleBounds)) {
        hasRedrawnTile = true;
      }
    }

    if (hasRedrawnTile) {
      this.drawPageBorder(this.committedContext2D, transform);
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

  private clipDirtyRectsToPage(dirtyRects: BoundingBox[]): BoundingBox[] {
    const pageWidth = this.getPageWidth();
    const pageHeight = this.getPageHeight();
    const clippedDirtyRects: BoundingBox[] = [];

    for (const dirtyRect of dirtyRects) {
      const clippedDirtyRect = clampBoundingBox(dirtyRect, pageWidth, pageHeight);
      if (clippedDirtyRect !== null) {
        clippedDirtyRects.push(clippedDirtyRect);
      }
    }

    return clippedDirtyRects;
  }

  private clearCommittedRegion(region: BoundingBox, transform: PageViewportTransform): void {
    const viewportRegion = this.toViewportBoundingBox(region, transform);
    if (viewportRegion === null) {
      return;
    }

    this.committedContext2D.clearRect(
      viewportRegion.minX,
      viewportRegion.minY,
      viewportRegion.maxX - viewportRegion.minX,
      viewportRegion.maxY - viewportRegion.minY
    );
  }

  private redrawCommittedTile(
    tileBounds: BoundingBox,
    transform: PageViewportTransform,
    visibleBounds: BoundingBox
  ): boolean {
    const tileRegion = this.intersectBoundingBoxes(tileBounds, visibleBounds);
    if (tileRegion === null) {
      return false;
    }

    this.clearCommittedRegion(tileRegion, transform);

    const candidateStrokeIds = this.strokeSpatialIndex.queryStrokeIds(tileBounds)
      .sort((left: string, right: string) => this.getRenderedStrokeIndex(left) - this.getRenderedStrokeIndex(right));

    this.committedContext2D.save();
    this.applyPageTransformAndClip(this.committedContext2D, transform);
    this.committedContext2D.beginPath();
    this.committedContext2D.rect(
      tileRegion.minX,
      tileRegion.minY,
      tileRegion.maxX - tileRegion.minX,
      tileRegion.maxY - tileRegion.minY
    );
    this.committedContext2D.clip();
    PageTemplateRenderer.drawTemplateBackground(
      this.committedContext2D,
      this.templateType,
      transform.pageWidth,
      transform.pageHeight,
      this.paperBackgroundColor,
      {
        x: tileRegion.minX,
        y: tileRegion.minY,
        width: tileRegion.maxX - tileRegion.minX,
        height: tileRegion.maxY - tileRegion.minY
      }
    );

    for (const strokeId of candidateStrokeIds) {
      const stroke = this.renderedStrokesById.get(strokeId);
      if (stroke === undefined) {
        continue;
      }

      const strokeBounds = this.strokeSpatialIndex.getBounds(strokeId);
      if (strokeBounds !== null && doBoundingBoxesIntersect(strokeBounds, tileRegion)) {
        this.drawStroke(this.committedContext2D, stroke);
      }
    }

    this.committedContext2D.restore();
    return true;
  }

  private buildCommittedTileBoundsForDirtyRects(dirtyRects: BoundingBox[]): BoundingBox[] {
    const tileBoundsList: BoundingBox[] = [];
    const tileKeySet = new Set<string>();
    const pageWidth = this.getPageWidth();
    const pageHeight = this.getPageHeight();

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
          }, pageWidth, pageHeight);

          if (tileBounds !== null) {
            tileKeySet.add(tileKey);
            tileBoundsList.push(tileBounds);
          }
        }
      }
    }

    return tileBoundsList;
  }

  private clearPageRegionFromContext(context: CanvasRenderingContext2D, region: BoundingBox): void {
    const size = this.getCanvasSize(context);
    const transform = this.getPageViewportTransform(size);
    const viewportRegion = this.toViewportBoundingBox(region, transform);
    if (viewportRegion === null) {
      return;
    }

    context.clearRect(
      viewportRegion.minX,
      viewportRegion.minY,
      viewportRegion.maxX - viewportRegion.minX,
      viewportRegion.maxY - viewportRegion.minY
    );
  }

  private toViewportBoundingBox(bounds: BoundingBox, transform: PageViewportTransform): BoundingBox | null {
    return clampBoundingBox({
      minX: bounds.minX * transform.scale + transform.offsetX,
      minY: bounds.minY * transform.scale + transform.offsetY,
      maxX: bounds.maxX * transform.scale + transform.offsetX,
      maxY: bounds.maxY * transform.scale + transform.offsetY
    }, transform.viewportWidth, transform.viewportHeight);
  }

  private intersectBoundingBoxes(left: BoundingBox, right: BoundingBox): BoundingBox | null {
    const minX = Math.max(left.minX, right.minX);
    const minY = Math.max(left.minY, right.minY);
    const maxX = Math.min(left.maxX, right.maxX);
    const maxY = Math.min(left.maxY, right.maxY);

    if (maxX <= minX || maxY <= minY) {
      return null;
    }

    return {
      minX,
      minY,
      maxX,
      maxY
    };
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
    this.inlineTextEditElement = null;
    this.inlineTextEditContent = '';
    this.resetInlineTextEditFrame();
    this.clearLastEditTap();
    this.resetViewportTransform();
    this.clearRenderedStrokeState();
    this.lastAppliedRenderInvalidationSequence = 0;
    this.clearPreviewLayers();
    this.resetActivePreviewSession();
    this.resolveViewModel();
  }

  private onActiveToolChanged(): void {
    if (this.activeTool !== 'edit') {
      this.commitInlineTextEdit(true);
    }
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
