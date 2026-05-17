import common from '@ohos.app.ability.common';

import {
  BoundingBox,
  clampBoundingBox,
  doBoundingBoxesIntersect,
  expandBoundingBox,
  getStrokeRenderBoundingBox
} from '../../../common/utils/GeometryUtil';
import { clampElementFrameToBounds } from '../../../common/utils/ElementBoundsUtil';
import { CanvasElement, ShapeType, TextCanvasElement } from '../../../domain/entities/CanvasElement';
import { NotebookPageTemplateType } from '../../../domain/entities/NotebookPage';
import { NotebookPageCanvasEntity } from '../../../domain/entities/NotebookPageCanvas';
import { Stroke, StrokePoint } from '../../../domain/entities/Stroke';
import { ToolSetting, ToolType } from '../../../domain/entities/ToolSetting';
import { PageTemplateRenderer } from '../controllers/PageTemplateRenderer';
import { InProgressStrokeRenderSession, StrokeRenderer } from '../controllers/StrokeRenderer';
import { SelectionDashRenderer } from '../controllers/SelectionDashRenderer';
import { ShapeRenderer } from '../controllers/ShapeRenderer';
import { IndexedStrokeRecord } from '../controllers/UndoRedoController';
import { StrokeSpatialHashIndex } from '../controllers/StrokeSpatialHashIndex';
import { SelectionController } from '../selection/SelectionController';
import {
  ResizeHandle,
  SelectionAction,
  SelectionContextMenuTarget,
  SelectionHitResult,
  SelectionTarget
} from '../selection/SelectionTypes';
import { EditorDebugSnapshot } from '../viewmodels/EditorDebugSnapshot';
import { DrawingEditorViewModel } from '../viewmodels/DrawingEditorViewModel';
import { EditorSessionRegistry } from '../viewmodels/EditorSessionRegistry';
import { RenderInvalidation } from '../viewmodels/RenderInvalidation';
import { EditorPerformanceTrace } from '../utils/EditorPerformanceTrace';
import { ElementLayer } from './ElementLayer';
import { SelectionTransformOverlay } from './SelectionTransformOverlay';
import { StrokeSelectionOverlay } from './StrokeSelectionOverlay';

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

type CanvasDrawContext = CanvasRenderingContext2D | OffscreenCanvasRenderingContext2D;

const COMMITTED_TILE_SIZE = 256;
const PARTIAL_REDRAW_OVERDRAW_VIEWPORT_PX = 2;
const RECENT_COMMITTED_STROKE_LIMIT = 6;
type StrokeResizeUiMode = 'none' | 'ready' | 'resizing' | 'moving';
const VIEWPORT_PAGE_MARGIN = 36;
const VIEWPORT_EDGE_MARGIN = 42;
const MIN_ZOOM_SCALE = 1;
const MAX_ZOOM_SCALE = 4;
const DEFAULT_VIEWPORT_WIDTH = 1600;
const DEFAULT_VIEWPORT_HEIGHT = 900;
const PAGE_BORDER_COLOR = '#C4D2E6';
const VIEWPORT_REDRAW_INTERVAL_MS = 24;
const TEXT_EDIT_DOUBLE_TAP_MS = 360;
const TEXT_EDIT_DOUBLE_TAP_DISTANCE = 18;
const INLINE_TEXT_LINE_HEIGHT_FACTOR = 1.35;
const INLINE_TEXT_MAX_LINES = 1000;
const EDIT_HANDLE_HIT_TOLERANCE_SCREEN_PX = 12;
const LASSO_HIT_TOLERANCE_SCREEN_PX = 10;
const MIN_LASSO_HIT_TOLERANCE_PAGE = 4;
const MAX_LASSO_HIT_TOLERANCE_PAGE = 12;
const LASSO_OVERLAY_REDRAW_INTERVAL_MS = 24;
const SELECTION_OVERLAY_RESUME_DELAY_MS = 220;
const SELECTION_MOVE_HIT_TOLERANCE_SCREEN_PX = 6;
const MIN_SELECTION_MOVE_HIT_TOLERANCE_PAGE = 2;
const MAX_SELECTION_MOVE_HIT_TOLERANCE_PAGE = 8;
const SELECTION_MOVE_START_THRESHOLD_SCREEN_PX = 4;
const SELECTION_MOVE_REDRAW_INTERVAL_MS = 24;
const SELECTION_CONTEXT_MENU_WIDTH = 128;
const SELECTION_CONTEXT_MENU_ITEM_HEIGHT = 38;
const SELECTION_CONTEXT_MENU_OFFSET = 8;
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
  @Watch('onInteractionModeChanged')
  @Prop isDocumentViewportMode: boolean = false;
  @Watch('onActiveToolChanged')
  @Prop activeTool: ToolType = 'pen';
  @Prop elementVersion: number = 0;
  @Prop selectedShapeType: ShapeType = 'rectangle';
  @Link editorSnapshot: EditorDebugSnapshot;
  onContentChanged: (immediate: boolean, kind: CanvasBoardContentChangeKind) => void =
    (_immediate: boolean, _kind: CanvasBoardContentChangeKind): void => {};
  onCanvasMetricsChanged: (width: number, height: number) => void = (_width: number, _height: number): void => {};
  onDocumentViewportGestureStart: () => void = (): void => {};
  onDocumentViewportGestureUpdate: (scaleRatio: number, deltaX: number, deltaY: number) => void =
    (_scaleRatio: number, _deltaX: number, _deltaY: number): void => {};
  onDocumentViewportGestureEnd: () => void = (): void => {};
  private viewModel: DrawingEditorViewModel | null = null;

  private readonly committedRenderingSettings: RenderingContextSettings = new RenderingContextSettings(true);
  private readonly recentCommittedRenderingSettings: RenderingContextSettings = new RenderingContextSettings(true);
  private readonly stablePreviewRenderingSettings: RenderingContextSettings = new RenderingContextSettings(true);
  private readonly overlayRenderingSettings: RenderingContextSettings = new RenderingContextSettings(true);
  private readonly committedContext2D: CanvasRenderingContext2D =
    new CanvasRenderingContext2D(this.committedRenderingSettings);
  private readonly recentCommittedContext2D: CanvasRenderingContext2D =
    new CanvasRenderingContext2D(this.recentCommittedRenderingSettings);
  private readonly stablePreviewContext2D: CanvasRenderingContext2D =
    new CanvasRenderingContext2D(this.stablePreviewRenderingSettings);
  private readonly overlayContext2D: CanvasRenderingContext2D =
    new CanvasRenderingContext2D(this.overlayRenderingSettings);
  private readonly renderedStrokesById: Map<string, Stroke> = new Map<string, Stroke>();
  private renderedStrokeOrder: string[] = [];
  private readonly renderedStrokeIndexById: Map<string, number> = new Map<string, number>();
  private readonly strokeSpatialIndex: StrokeSpatialHashIndex = new StrokeSpatialHashIndex();
  private readonly hiddenStrokeIdsDuringSelectionMove: Set<string> = new Set<string>();
  private lastAppliedRenderInvalidationSequence: number = 0;
  private forceFullCommittedRedrawOnNextCanvasRefresh: boolean = false;
  private flattenedCommittedStrokeCount: number = 0;
  private activePreviewSession: InProgressStrokeRenderSession | null = null;
  private viewportZoomScale: number = MIN_ZOOM_SCALE;
  private viewportOffsetX: number = 0;
  private viewportOffsetY: number = 0;
  private lastViewportWidth: number = 0;
  private lastViewportHeight: number = 0;
  private lastPageWidth: number = 0;
  private lastPageHeight: number = 0;
  private isViewportTransformReady: boolean = false;
  private isDrawingGestureActive: boolean = false;
  private isLassoGestureActive: boolean = false;
  private isSelectionMovePending: boolean = false;
  private isSelectionMoveGestureActive: boolean = false;
  private pendingSelectionHitResult: SelectionHitResult | null = null;
  private isWorkspacePanActive: boolean = false;
  private isViewportGestureActive: boolean = false;
  private selectionMoveStartScreenX: number = 0;
  private selectionMoveStartScreenY: number = 0;
  private selectionMoveStartPageX: number = 0;
  private selectionMoveStartPageY: number = 0;
  private lassoStartScreenX: number = 0;
  private lassoStartScreenY: number = 0;
  private shouldClearSelectionOnLassoTap: boolean = false;
  private lastWorkspacePanX: number = 0;
  private lastWorkspacePanY: number = 0;
  private viewportGestureStartDistance: number = 1;
  private viewportGestureStartZoomScale: number = MIN_ZOOM_SCALE;
  private viewportGestureStartPageX: number = 0;
  private viewportGestureStartPageY: number = 0;
  private viewportGestureLastCenterX: number = 0;
  private viewportGestureLastCenterY: number = 0;
  private lastViewportRedrawTime: number = 0;
  private lastEditTapTime: number = 0;
  private lastEditTapElementId: string = '';
  private lastEditTapX: number = 0;
  private lastEditTapY: number = 0;
  private lastSelectionVersion: number = -1;
  private lastLassoOverlayRedrawTime: number = 0;
  private lastSelectionMoveRedrawTime: number = 0;
  private selectionOverlayResumeTimerId: number = -1;

  @State private isCommittedLayerReady: boolean = false;
  @State private isRecentCommittedLayerReady: boolean = false;
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
  @State private selectedStrokeTargets: SelectionTarget[] = [];
  @State private strokeResizeUiMode: StrokeResizeUiMode = 'none';
  @State private strokeResizeBounds: BoundingBox | null = null;
  @State private selectionOverlayRefreshVersion: number = 0;
  @State private isSelectionOverlayPaused: boolean = false;
  @State private isSelectionContextMenuVisible: boolean = false;
  @State private selectionContextMenuTarget: SelectionContextMenuTarget = 'strokeGroup';
  @State private selectionContextMenuX: number = 0;
  @State private selectionContextMenuY: number = 0;

  aboutToAppear(): void {
    this.resolveViewModel();
  }

  aboutToDisappear(): void {
    this.flattenRecentCommittedLayer();
    this.clearSelectionOverlayResumeTimer();
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

      Canvas(this.recentCommittedContext2D)
        .width('100%')
        .height('100%')
        .backgroundColor('#00000000')
        .onReady(() => {
          this.isRecentCommittedLayerReady = true;
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

        StrokeSelectionOverlay({
          targets: this.isStrokeResizeModeVisible() ? [] : this.selectedStrokeTargets,
          refreshVersion: this.selectionOverlayRefreshVersion,
          paused: this.isSelectionOverlayPaused
        })
          .width('100%')
          .height('100%')

        if (this.isStrokeResizeModeVisible() && this.strokeResizeBounds !== null) {
          SelectionTransformOverlay({
            bounds: this.strokeResizeBounds
          })
            .width('100%')
            .height('100%')
        }
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

      if (this.isSelectionContextMenuVisible) {
        this.buildSelectionContextMenu()
      }

    }
    .width('100%')
    .height('100%')
    .clip(true)
    .onAreaChange((_oldValue: Area, _newValue: Area) => {
      this.notifyCanvasMetricsChanged();
      this.redrawViewportLayers(this.isViewportGestureActive);
    })
  }

  @Builder
  private buildSelectionContextMenu(): void {
    Column() {
      if (this.selectionContextMenuTarget === 'strokeGroup') {
        Button('拷贝')
          .width('100%')
          .height(SELECTION_CONTEXT_MENU_ITEM_HEIGHT)
          .fontSize(14)
          .fontColor('#111827')
          .backgroundColor('#00000000')
          .onClick(() => {
            this.handleSelectionContextMenuAction('copy');
          })

        Button('调整大小')
          .width('100%')
          .height(SELECTION_CONTEXT_MENU_ITEM_HEIGHT)
          .fontSize(14)
          .fontColor('#111827')
          .backgroundColor('#00000000')
          .onClick(() => {
            this.handleSelectionContextMenuAction('resize');
          })

        Button('删除')
          .width('100%')
          .height(SELECTION_CONTEXT_MENU_ITEM_HEIGHT)
          .fontSize(14)
          .fontColor('#DC2626')
          .backgroundColor('#00000000')
          .onClick(() => {
            this.handleSelectionContextMenuAction('delete');
          })
      }
    }
      .width(SELECTION_CONTEXT_MENU_WIDTH)
      .padding(4)
      .backgroundColor('#FFFFFF')
      .border({
        width: 1,
        color: '#CBD5E1'
      })
      .borderRadius(8)
      .position({
        x: this.selectionContextMenuX,
        y: this.selectionContextMenuY
      })
      .zIndex(20)
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
    if (this.forceFullCommittedRedrawOnNextCanvasRefresh) {
      this.redrawCommittedLayer();
      this.consumeLatestRenderInvalidationSequence();
      this.forceFullCommittedRedrawOnNextCanvasRefresh = false;
    } else if (!this.tryApplyLatestRenderInvalidation()) {
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
      if (activeTool === 'lasso') {
        this.finishLassoGestureWithoutPoint(viewModel, event.type);
        return;
      }

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

    if (this.isStrokeResizeModeVisible() && this.handleStrokeResizeTouch(event, touch, viewModel)) {
      return;
    }

    if (event.type === TouchType.Down && activeTool !== 'lasso') {
      this.hideSelectionContextMenu();
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

    if (activeTool === 'lasso') {
      this.handleLassoTouch(event, touch, viewModel);
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
    if (this.isDocumentViewportMode) {
      return false;
    }

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

  private handleLassoTouch(event: TouchEvent, touch: TouchObject, viewModel: DrawingEditorViewModel): void {
    if (event.type === TouchType.Down) {
      this.hideSelectionContextMenu();
      const point = this.buildPoint(touch, false);
      if (point === null) {
        this.beginWorkspacePan(touch);
        return;
      }

      const hitResult = viewModel.hitTestSelection(point, this.getSelectionMoveHitToleranceInPage());
      if (hitResult.canMove && hitResult.target !== null) {
        this.isSelectionMovePending = true;
        this.isSelectionMoveGestureActive = false;
        this.pendingSelectionHitResult = hitResult;
        this.selectionMoveStartScreenX = touch.x;
        this.selectionMoveStartScreenY = touch.y;
        this.selectionMoveStartPageX = point.x;
        this.selectionMoveStartPageY = point.y;
        this.pauseSelectionOverlay();
        this.syncEditorSnapshot();
        return;
      }

      this.pendingSelectionHitResult = null;
      this.lassoStartScreenX = touch.x;
      this.lassoStartScreenY = touch.y;
      this.shouldClearSelectionOnLassoTap = viewModel.getSelectionTargets().length > 0;
      this.isLassoGestureActive = true;
      this.pauseSelectionOverlay();
      viewModel.beginLassoSelection(point);
      this.syncEditorSnapshot();
      this.requestLassoOverlayRedraw(true);
      this.onContentChanged(false, 'element');
      return;
    }

    if (event.type === TouchType.Move) {
      if (this.isWorkspacePanActive) {
        this.updateWorkspacePan(touch);
        return;
      }

      if (this.isSelectionMovePending || this.isSelectionMoveGestureActive) {
        this.updateSelectionMoveGesture(touch, viewModel);
        return;
      }

      if (!this.isLassoGestureActive) {
        return;
      }

      if (this.hasLassoTapExceededStartThreshold(touch)) {
        this.shouldClearSelectionOnLassoTap = false;
      }

      const point = this.buildPoint(touch, true);
      if (point === null) {
        return;
      }

      viewModel.updateLassoSelection(point);
      this.requestLassoOverlayRedraw(false);
      return;
    }

    if (event.type === TouchType.Up) {
      if (this.isWorkspacePanActive) {
        this.endWorkspacePan(true);
        return;
      }

      if (this.isSelectionMovePending || this.isSelectionMoveGestureActive) {
        this.finishSelectionMoveGesture(touch, viewModel);
        return;
      }

      if (!this.isLassoGestureActive) {
        return;
      }

      if (this.shouldClearSelectionOnLassoTap && !this.hasLassoTapExceededStartThreshold(touch)) {
        this.shouldClearSelectionOnLassoTap = false;
        this.isLassoGestureActive = false;
        viewModel.cancelLassoSelection();
        viewModel.clearSelection();
        this.scheduleSelectionOverlayResume();
        this.syncEditorSnapshot();
        this.redrawOverlayLayer();
        this.onContentChanged(false, 'element');
        return;
      }

      const point = this.buildPoint(touch, true);
      if (point !== null) {
        viewModel.updateLassoSelection(point);
      }
      this.isLassoGestureActive = false;
      this.shouldClearSelectionOnLassoTap = false;
      viewModel.finishLassoSelection(this.getLassoHitToleranceInPage());
      this.scheduleSelectionOverlayResume();
      this.syncEditorSnapshot();
      this.redrawOverlayLayer();
      this.onContentChanged(false, 'element');
      return;
    }

    if (event.type === TouchType.Cancel) {
      if (this.isWorkspacePanActive) {
        this.endWorkspacePan(true);
        return;
      }

      if (this.isSelectionMovePending || this.isSelectionMoveGestureActive) {
        this.cancelSelectionMoveGesture(viewModel);
        return;
      }

      this.cancelLassoGesture(viewModel);
      this.shouldClearSelectionOnLassoTap = false;
    }
  }

  private handleViewportTouch(event: TouchEvent, viewModel: DrawingEditorViewModel): boolean {
    const activeTouches: TouchObject[] = this.getActiveTouches(event);
    if (activeTouches.length >= 2) {
      this.cancelDrawingGesture(viewModel);
      this.cancelLassoGesture(viewModel);
      this.cancelSelectionMoveGesture(viewModel);
      this.cancelActiveStrokeResizeGesture(viewModel);
      this.endWorkspacePan(false);
      const pairMetrics: TouchPairMetrics = this.getTouchPairMetrics(activeTouches[0], activeTouches[1]);
      if (!this.isViewportGestureActive || event.type === TouchType.Down) {
        if (this.isDocumentCanvasGestureEnabled()) {
          this.beginDocumentViewportGesture(pairMetrics);
        } else {
          this.beginViewportGesture(pairMetrics);
        }
      } else {
        if (this.isDocumentCanvasGestureEnabled()) {
          this.updateDocumentViewportGesture(pairMetrics);
        } else {
          this.updateViewportGesture(pairMetrics);
        }
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

  private handleStrokeResizeTouch(event: TouchEvent, touch: TouchObject, viewModel: DrawingEditorViewModel): boolean {
    const point = this.buildPoint(touch, event.type !== TouchType.Down);
    if (event.type === TouchType.Down) {
      if (point === null) {
        return false;
      }

      const resizeBounds = viewModel.getSelectedStrokeResizeBounds();
      if (resizeBounds === null) {
        this.exitStrokeResizeMode(viewModel);
        return true;
      }

      const hitTolerance = this.getEditHitToleranceInPage();
      const handle = SelectionController.hitTestResizeHandle(resizeBounds, point, hitTolerance);
      if (handle === null) {
        if (!SelectionController.isPointInTargetBounds(resizeBounds, point, this.getSelectionMoveHitToleranceInPage())) {
          this.clearSelectionAndExitStrokeResizeMode(viewModel);
          this.onContentChanged(false, 'element');
          return true;
        }

        if (!viewModel.beginSelectionMove(point)) {
          return true;
        }

        this.hideSelectionContextMenu();
        this.strokeResizeUiMode = 'moving';
        this.beginSelectionMovePreview();
        this.syncEditorSnapshot();
        this.redrawOverlayLayer();
        return true;
      }

      this.hideSelectionContextMenu();
      if (!viewModel.beginStrokeResize(handle)) {
        this.exitStrokeResizeMode(viewModel);
        return true;
      }

      this.strokeResizeUiMode = 'resizing';
      this.beginSelectionMovePreview();
      this.syncEditorSnapshot();
      this.redrawOverlayLayer();
      return true;
    }

    if (event.type === TouchType.Move) {
      if (!this.isStrokeResizeDragging() || point === null) {
        return true;
      }

      const didUpdate = this.strokeResizeUiMode === 'moving' ?
        viewModel.updateSelectionMove(point, this.getPageBounds()) :
        viewModel.updateStrokeResize(point, this.getPageBounds());
      if (didUpdate) {
        this.syncEditorSnapshot();
        if (this.requestSelectionMoveRedraw(false) && viewModel.getSelectedElementIds().length > 0) {
          this.onContentChanged(false, 'element');
        }
      }
      return true;
    }

    if (event.type === TouchType.Up) {
      if (!this.isStrokeResizeDragging()) {
        return true;
      }

      if (point !== null) {
        if (this.strokeResizeUiMode === 'moving') {
          viewModel.updateSelectionMove(point, this.getPageBounds());
        } else {
          viewModel.updateStrokeResize(point, this.getPageBounds());
        }
      }
      this.syncEditorSnapshot();
      this.redrawOverlayLayer();
      const didChange = this.strokeResizeUiMode === 'moving' ?
        viewModel.finishSelectionMove() :
        viewModel.finishStrokeResize();
      const contentChangeKind: CanvasBoardContentChangeKind =
        this.strokeResizeUiMode === 'moving' && viewModel.getSelectedElementIds().length > 0 ? 'element' : 'stroke';
      this.strokeResizeUiMode = 'ready';
      this.syncEditorSnapshot();
      this.finishSelectionMovePreview(didChange);
      this.onContentChanged(didChange, contentChangeKind);
      return true;
    }

    if (event.type === TouchType.Cancel) {
      this.cancelActiveStrokeResizeGesture(viewModel);
      return true;
    }

    return true;
  }

  private cancelActiveStrokeResizeGesture(viewModel: DrawingEditorViewModel): void {
    if (!this.isStrokeResizeDragging()) {
      return;
    }

    if (this.strokeResizeUiMode === 'moving') {
      viewModel.cancelSelectionMove();
    } else {
      viewModel.cancelStrokeResize();
    }
    this.strokeResizeUiMode = 'ready';
    this.hiddenStrokeIdsDuringSelectionMove.clear();
    this.redrawCommittedLayer(false);
    this.syncEditorSnapshot();
    this.redrawOverlayLayer();
  }

  private updateSelectionMoveGesture(touch: TouchObject, viewModel: DrawingEditorViewModel): void {
    const point = this.buildPoint(touch, true);
    if (point === null) {
      return;
    }

    let forceRedraw = false;
    if (this.isSelectionMovePending) {
      if (!this.hasSelectionMoveExceededStartThreshold(touch)) {
        return;
      }

      const didBeginMove = viewModel.beginSelectionMove(
        {
          x: this.selectionMoveStartPageX,
          y: this.selectionMoveStartPageY,
          t: point.t,
          pressure: point.pressure
        }
      );
      if (!didBeginMove) {
        this.isSelectionMovePending = false;
        this.pendingSelectionHitResult = null;
        this.scheduleSelectionOverlayResume();
        return;
      }

      this.isSelectionMovePending = false;
      this.pendingSelectionHitResult = null;
      this.isSelectionMoveGestureActive = true;
      this.beginSelectionMovePreview();
      forceRedraw = true;
    }

    if (viewModel.updateSelectionMove(point, this.getPageBounds())) {
      this.syncEditorSnapshot();
      if (this.requestSelectionMoveRedraw(forceRedraw) && viewModel.getSelectedElementIds().length > 0) {
        this.onContentChanged(false, 'element');
      }
    }
  }

  private finishSelectionMoveGesture(touch: TouchObject, viewModel: DrawingEditorViewModel): void {
    if (this.isSelectionMoveGestureActive) {
      const point = this.buildPoint(touch, true);
      if (point !== null) {
        viewModel.updateSelectionMove(point, this.getPageBounds());
      }
      const didMove = viewModel.finishSelectionMove();
      this.isSelectionMoveGestureActive = false;
      this.isSelectionMovePending = false;
      this.scheduleSelectionOverlayResume();
      this.syncEditorSnapshot();
      this.finishSelectionMovePreview(didMove);
      this.onContentChanged(didMove, 'element');
      return;
    }

    const pendingHitResult = this.pendingSelectionHitResult;
    this.isSelectionMovePending = false;
    this.pendingSelectionHitResult = null;
    this.scheduleSelectionOverlayResume();
    this.syncEditorSnapshot();
    this.redrawOverlayLayer();
    this.showSelectionContextMenu(pendingHitResult);
    this.onContentChanged(false, 'element');
  }

  private cancelSelectionMoveGesture(viewModel: DrawingEditorViewModel): void {
    const hadSelectionMove = this.isSelectionMovePending || this.isSelectionMoveGestureActive;
    this.hideSelectionContextMenu();
    this.isSelectionMovePending = false;
    this.isSelectionMoveGestureActive = false;
    this.pendingSelectionHitResult = null;
    viewModel.cancelSelectionMove();
    if (hadSelectionMove) {
      this.scheduleSelectionOverlayResume();
      this.syncEditorSnapshot();
      this.cancelSelectionMovePreview();
      this.onContentChanged(false, 'element');
    }
  }

  private hasSelectionMoveExceededStartThreshold(touch: TouchObject): boolean {
    const deltaX = touch.x - this.selectionMoveStartScreenX;
    const deltaY = touch.y - this.selectionMoveStartScreenY;
    return Math.sqrt(deltaX * deltaX + deltaY * deltaY) >= SELECTION_MOVE_START_THRESHOLD_SCREEN_PX;
  }

  private hasLassoTapExceededStartThreshold(touch: TouchObject): boolean {
    const deltaX = touch.x - this.lassoStartScreenX;
    const deltaY = touch.y - this.lassoStartScreenY;
    return Math.sqrt(deltaX * deltaX + deltaY * deltaY) >= SELECTION_MOVE_START_THRESHOLD_SCREEN_PX;
  }

  private beginSelectionMovePreview(): void {
    this.hiddenStrokeIdsDuringSelectionMove.clear();
    for (const target of this.selectedStrokeTargets) {
      if (target.kind !== 'strokeGroup') {
        continue;
      }

      for (const strokeId of target.strokeIds) {
        this.hiddenStrokeIdsDuringSelectionMove.add(strokeId);
      }
    }

    if (this.hiddenStrokeIdsDuringSelectionMove.size > 0) {
      this.repaintSelectedStrokeTargetRegions();
    }
  }

  private finishSelectionMovePreview(didMove: boolean): void {
    this.hiddenStrokeIdsDuringSelectionMove.clear();
    if (didMove) {
      if (!this.tryApplyLatestRenderInvalidation()) {
        this.redrawCommittedLayer(false);
      }
    } else {
      this.redrawCommittedLayer(false);
    }

    this.redrawOverlayLayer();
  }

  private cancelSelectionMovePreview(): void {
    this.hiddenStrokeIdsDuringSelectionMove.clear();
    this.repaintSelectedStrokeTargetRegions();
    this.redrawOverlayLayer();
  }

  private finishLassoGestureWithoutPoint(viewModel: DrawingEditorViewModel, touchType: TouchType): void {
    if (this.isSelectionMovePending || this.isSelectionMoveGestureActive) {
      this.cancelSelectionMoveGesture(viewModel);
      return;
    }

    if (!this.isLassoGestureActive) {
      return;
    }

    if (touchType === TouchType.Up) {
      viewModel.finishLassoSelection(this.getLassoHitToleranceInPage());
    } else {
      viewModel.cancelLassoSelection();
    }
    this.isLassoGestureActive = false;
    this.shouldClearSelectionOnLassoTap = false;
    this.scheduleSelectionOverlayResume();
    this.syncEditorSnapshot();
    this.redrawOverlayLayer();
    this.onContentChanged(false, 'element');
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

  private cancelLassoGesture(viewModel: DrawingEditorViewModel): void {
    if (!this.isLassoGestureActive) {
      return;
    }

    viewModel.cancelLassoSelection();
    this.isLassoGestureActive = false;
    this.shouldClearSelectionOnLassoTap = false;
    this.scheduleSelectionOverlayResume();
    this.redrawOverlayLayer();
    this.syncEditorSnapshot();
    this.onContentChanged(false, 'element');
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
    } else if (completedStroke !== null && this.areCommittedLayersReady()) {
      this.appendRenderedStroke(completedStroke);
      if (this.canAppendToRecentCommittedLayer()) {
        this.drawStrokeOnViewport(this.recentCommittedContext2D, completedStroke, false);
      } else if (this.trimRecentCommittedLayerIntoBase()) {
        this.redrawRecentCommittedLayer(false);
      } else {
        this.redrawCommittedLayer();
      }
    }
    this.clearPreviewLayers();
    this.resetActivePreviewSession();
    this.onContentChanged(false, 'stroke');
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

  private redrawCommittedLayer(useFastRendering: boolean = false, preserveRecentSplit: boolean = false): void {
    if (!this.areCommittedLayersReady()) {
      return;
    }

    const redrawStartedAt = Date.now();
    const viewModel = this.getViewModel();
    const strokes = viewModel ? viewModel.getStrokesForRendering() : [];
    let flattenedStrokeCount = preserveRecentSplit
      ? Math.max(0, Math.min(this.flattenedCommittedStrokeCount, strokes.length))
      : strokes.length;
    if (strokes.length - flattenedStrokeCount > RECENT_COMMITTED_STROKE_LIMIT) {
      flattenedStrokeCount = strokes.length;
    }
    this.flattenedCommittedStrokeCount = flattenedStrokeCount;
    this.rebuildRenderedStrokeCache(strokes);

    const size = this.getCanvasSize(this.committedContext2D);
    const transform = this.getPageViewportTransform(size);
    this.syncElementLayerTransform(transform);
    const visibleRegion = this.getVisiblePageRegion(transform);

    if (this.redrawCommittedBaseLayerWithBuffer(size, transform, visibleRegion, strokes, flattenedStrokeCount,
      useFastRendering)) {
      this.redrawRecentCommittedStrokes(strokes, flattenedStrokeCount, visibleRegion, transform, useFastRendering);
    } else {
      this.redrawCommittedLayerDirect(size, transform, visibleRegion, strokes, flattenedStrokeCount, useFastRendering);
    }

    EditorPerformanceTrace.record(
      'committed.fullRedraw',
      Date.now() - redrawStartedAt,
      `fast=${useFastRendering} visible=${visibleRegion === null ? 'false' : 'true'} flattened=${flattenedStrokeCount} recent=${Math.max(0, strokes.length - flattenedStrokeCount)} strokes=${strokes.length}`,
      useFastRendering ? 10 : 14
    );
  }

  private redrawOverlayLayer(): void {
    if (!this.isOverlayLayerReady) {
      return;
    }

    this.clearPreviewLayers();
    this.resetActivePreviewSession();

    const viewModel = this.getViewModel();
    if (!viewModel) {
      return;
    }
    this.syncSelectionOverlayState(viewModel);

    if (this.isSelectionMoveGestureActive || this.isStrokeResizeDragging()) {
      this.drawSelectionMovePreview(viewModel);
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

    const lassoDraftPath = viewModel.getLassoDraftPath();
    if (lassoDraftPath.length > 0) {
      const size = this.getCanvasSize(this.overlayContext2D);
      const transform = this.getPageViewportTransform(size);
      this.syncElementLayerTransform(transform);
      this.overlayContext2D.save();
      this.applyPageTransformAndClip(this.overlayContext2D, transform);
      this.drawLassoDraft(this.overlayContext2D, lassoDraftPath);
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

  private clearRecentCommittedLayer(): void {
    if (!this.isRecentCommittedLayerReady) {
      return;
    }

    const size = this.getCanvasSize(this.recentCommittedContext2D);
    this.recentCommittedContext2D.clearRect(0, 0, size.width, size.height);
  }

  private clearCommittedLayer(): void {
    if (!this.isCommittedLayerReady) {
      return;
    }

    const size = this.getCanvasSize(this.committedContext2D);
    this.committedContext2D.clearRect(0, 0, size.width, size.height);
    this.clearRecentCommittedLayer();
    this.flattenedCommittedStrokeCount = 0;
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
    this.syncSelectionOverlayState(viewModel);
  }

  private syncSelectionOverlayState(viewModel: DrawingEditorViewModel): void {
    const selectionVersion = viewModel.getSelectionVersion();
    if (selectionVersion !== this.lastSelectionVersion) {
      this.lastSelectionVersion = selectionVersion;
      this.selectedStrokeTargets = viewModel.getSelectedStrokeTargets();
      this.selectionOverlayRefreshVersion += 1;
    }

    this.strokeResizeBounds = this.isStrokeResizeModeVisible() ? viewModel.getSelectedStrokeResizeBounds() : null;
  }

  private showSelectionContextMenu(hitResult: SelectionHitResult | null): void {
    if (hitResult === null || hitResult.target === null || !hitResult.canShowMenu) {
      return;
    }

    this.selectionContextMenuTarget = SelectionController.getContextMenuTarget(hitResult.target);
    const menuHeight = this.getSelectionContextMenuHeight();
    const size = this.getCanvasSize(this.overlayContext2D);
    const transform = this.getPageViewportTransform(size);
    const screenX = transform.offsetX + this.selectionMoveStartPageX * transform.scale;
    const screenY = transform.offsetY + this.selectionMoveStartPageY * transform.scale;
    this.selectionContextMenuX = this.clamp(
      screenX + SELECTION_CONTEXT_MENU_OFFSET,
      4,
      Math.max(4, size.width - SELECTION_CONTEXT_MENU_WIDTH - 4)
    );
    this.selectionContextMenuY = this.clamp(
      screenY - menuHeight - SELECTION_CONTEXT_MENU_OFFSET,
      4,
      Math.max(4, size.height - menuHeight - 4)
    );
    this.isSelectionContextMenuVisible = true;
  }

  private hideSelectionContextMenu(): void {
    if (!this.isSelectionContextMenuVisible) {
      return;
    }

    this.isSelectionContextMenuVisible = false;
  }

  private getSelectionContextMenuHeight(): number {
    if (this.selectionContextMenuTarget === 'strokeGroup') {
      return SELECTION_CONTEXT_MENU_ITEM_HEIGHT * 3 + 8;
    }

    return SELECTION_CONTEXT_MENU_ITEM_HEIGHT + 8;
  }

  private handleSelectionContextMenuAction(action: SelectionAction): void {
    const viewModel = this.getViewModel();
    if (viewModel === null) {
      this.hideSelectionContextMenu();
      return;
    }

    const target = this.selectionContextMenuTarget;
    this.hideSelectionContextMenu();
    if (action === 'resize' && target === 'strokeGroup') {
      this.beginStrokeResizeMode(viewModel);
      return;
    }

    const result = viewModel.applySelectionAction(action, target);
    if (!result.changed) {
      this.syncEditorSnapshot();
      this.redrawOverlayLayer();
      return;
    }

    this.syncEditorSnapshot();
    if (!this.tryApplyLatestRenderInvalidation()) {
      this.redrawCommittedLayer(false);
    }
    this.redrawOverlayLayer();
    this.onContentChanged(true, result.changedElements || result.elementSelectionChanged ? 'element' : 'stroke');
  }

  private beginStrokeResizeMode(viewModel: DrawingEditorViewModel): void {
    const resizeBounds = viewModel.beginStrokeResizeMode();
    if (resizeBounds === null) {
      this.strokeResizeUiMode = 'none';
      this.strokeResizeBounds = null;
      this.syncEditorSnapshot();
      this.redrawOverlayLayer();
      return;
    }

    this.strokeResizeUiMode = 'ready';
    this.strokeResizeBounds = resizeBounds;
    this.selectionOverlayRefreshVersion += 1;
    this.syncEditorSnapshot();
    this.redrawOverlayLayer();
    this.onContentChanged(false, 'element');
  }

  private exitStrokeResizeMode(viewModel: DrawingEditorViewModel): void {
    if (!this.isStrokeResizeModeVisible()) {
      return;
    }

    if (this.isStrokeResizeDragging()) {
      if (this.strokeResizeUiMode === 'moving') {
        viewModel.cancelSelectionMove();
      } else {
        viewModel.cancelStrokeResize();
      }
      this.hiddenStrokeIdsDuringSelectionMove.clear();
      this.redrawCommittedLayer(false);
    }

    this.strokeResizeUiMode = 'none';
    this.strokeResizeBounds = null;
    this.selectionOverlayRefreshVersion += 1;
    this.syncEditorSnapshot();
    this.redrawOverlayLayer();
  }

  private clearSelectionAndExitStrokeResizeMode(viewModel: DrawingEditorViewModel): void {
    if (this.isStrokeResizeDragging()) {
      if (this.strokeResizeUiMode === 'moving') {
        viewModel.cancelSelectionMove();
      } else {
        viewModel.cancelStrokeResize();
      }
      this.hiddenStrokeIdsDuringSelectionMove.clear();
      this.redrawCommittedLayer(false);
    }

    this.strokeResizeUiMode = 'none';
    this.strokeResizeBounds = null;
    viewModel.clearSelection();
    this.selectionOverlayRefreshVersion += 1;
    this.syncEditorSnapshot();
    this.redrawOverlayLayer();
  }

  private isStrokeResizeModeVisible(): boolean {
    return this.strokeResizeUiMode !== 'none';
  }

  private isStrokeResizeDragging(): boolean {
    return this.strokeResizeUiMode === 'resizing' || this.strokeResizeUiMode === 'moving';
  }

  private pauseSelectionOverlay(): void {
    this.clearSelectionOverlayResumeTimer();
    if (!this.isSelectionOverlayPaused) {
      this.isSelectionOverlayPaused = true;
    }
  }

  private scheduleSelectionOverlayResume(): void {
    if (!this.isSelectionOverlayPaused && this.selectionOverlayResumeTimerId < 0) {
      return;
    }

    this.clearSelectionOverlayResumeTimer();
    this.selectionOverlayResumeTimerId = setTimeout(() => {
      this.selectionOverlayResumeTimerId = -1;
      if (this.hasSelectionOverlayPauseSource()) {
        this.scheduleSelectionOverlayResume();
        return;
      }

      if (this.isSelectionOverlayPaused) {
        this.isSelectionOverlayPaused = false;
      }
    }, SELECTION_OVERLAY_RESUME_DELAY_MS);
  }

  private resumeSelectionOverlayImmediately(): void {
    this.clearSelectionOverlayResumeTimer();
    if (this.isSelectionOverlayPaused) {
      this.isSelectionOverlayPaused = false;
    }
  }

  private hasSelectionOverlayPauseSource(): boolean {
    return this.isLassoGestureActive || this.isSelectionMovePending || this.isSelectionMoveGestureActive ||
      this.isWorkspacePanActive || this.isViewportGestureActive;
  }

  private clearSelectionOverlayResumeTimer(): void {
    if (this.selectionOverlayResumeTimerId < 0) {
      return;
    }

    clearTimeout(this.selectionOverlayResumeTimerId);
    this.selectionOverlayResumeTimerId = -1;
  }

  private requestLassoOverlayRedraw(force: boolean): void {
    const now = Date.now();
    if (!force && now - this.lastLassoOverlayRedrawTime < LASSO_OVERLAY_REDRAW_INTERVAL_MS) {
      return;
    }

    this.lastLassoOverlayRedrawTime = now;
    this.redrawOverlayLayer();
  }

  private requestSelectionMoveRedraw(force: boolean): boolean {
    const now = Date.now();
    if (!force && now - this.lastSelectionMoveRedrawTime < SELECTION_MOVE_REDRAW_INTERVAL_MS) {
      return false;
    }

    this.lastSelectionMoveRedrawTime = now;
    this.redrawOverlayLayer();
    return true;
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
    return Math.max(3, EDIT_HANDLE_HIT_TOLERANCE_SCREEN_PX / Math.max(0.01, transform.scale));
  }

  private getLassoHitToleranceInPage(): number {
    const size = this.getCanvasSize(this.overlayContext2D);
    const transform = this.getPageViewportTransform(size);
    const scaledTolerance = LASSO_HIT_TOLERANCE_SCREEN_PX / Math.max(0.01, transform.scale);
    return this.clamp(scaledTolerance, MIN_LASSO_HIT_TOLERANCE_PAGE, MAX_LASSO_HIT_TOLERANCE_PAGE);
  }

  private getSelectionMoveHitToleranceInPage(): number {
    const size = this.getCanvasSize(this.overlayContext2D);
    const transform = this.getPageViewportTransform(size);
    const scaledTolerance = SELECTION_MOVE_HIT_TOLERANCE_SCREEN_PX / Math.max(0.01, transform.scale);
    return this.clamp(
      scaledTolerance,
      MIN_SELECTION_MOVE_HIT_TOLERANCE_PAGE,
      MAX_SELECTION_MOVE_HIT_TOLERANCE_PAGE
    );
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

  private drawStroke(context: CanvasDrawContext, stroke: Stroke, useFastRendering: boolean = false): void {
    if (useFastRendering) {
      StrokeRenderer.drawStrokeFast(context, stroke);
      return;
    }

    StrokeRenderer.drawStroke(context, stroke);
  }

  private drawStrokeOnViewport(
    context: CanvasRenderingContext2D,
    stroke: Stroke,
    drawBorder: boolean = true
  ): void {
    const size = this.getCanvasSize(context);
    const transform = this.getPageViewportTransform(size);
    const visibleRegion = this.getVisiblePageRegion(transform);
    if (visibleRegion !== null && this.isStrokeVisible(stroke, visibleRegion)) {
      context.save();
      this.applyPageTransformAndClip(context, transform);
      this.drawStroke(context, stroke);
      context.restore();
    }
    if (drawBorder) {
      this.drawPageBorder(context, transform);
    }
  }

  private drawSelectionMovePreview(viewModel: DrawingEditorViewModel): void {
    if (this.hiddenStrokeIdsDuringSelectionMove.size === 0) {
      return;
    }

    const size = this.getCanvasSize(this.overlayContext2D);
    const transform = this.getPageViewportTransform(size);
    const visibleRegion = this.getVisiblePageRegion(transform);
    if (visibleRegion === null) {
      return;
    }

    const visibleBounds = this.toBoundingBox(visibleRegion);
    this.syncElementLayerTransform(transform);
    this.overlayContext2D.save();
    this.applyPageTransformAndClip(this.overlayContext2D, transform);
    for (const stroke of viewModel.getStrokesForRendering()) {
      if (!this.hiddenStrokeIdsDuringSelectionMove.has(stroke.id)) {
        continue;
      }

      if (this.isStrokeBoundsVisible(stroke, visibleBounds)) {
        this.drawStroke(this.overlayContext2D, stroke, true);
      }
    }
    this.overlayContext2D.restore();
  }

  private repaintSelectedStrokeTargetRegions(): void {
    const dirtyRect = this.getSelectedStrokeTargetDirtyBounds();
    if (dirtyRect === null) {
      return;
    }

    if (!this.repaintCommittedRegion(dirtyRect)) {
      this.redrawCommittedLayer(false);
      return;
    }
  }

  private flattenRecentCommittedLayer(): void {
    if (!this.hasActiveRecentCommittedLayer()) {
      return;
    }

    this.redrawCommittedLayer(false, false);
  }

  private getSelectedStrokeTargetDirtyBounds(): BoundingBox | null {
    const dirtyBounds: BoundingBox[] = [];
    for (const strokeId of this.hiddenStrokeIdsDuringSelectionMove) {
      const stroke = this.renderedStrokesById.get(strokeId);
      if (stroke === undefined) {
        continue;
      }

      const strokeBounds = getStrokeRenderBoundingBox(stroke);
      if (strokeBounds !== null) {
        dirtyBounds.push(strokeBounds);
      }
    }

    if (dirtyBounds.length === 0) {
      for (const target of this.selectedStrokeTargets) {
        if (target.kind === 'strokeGroup') {
          dirtyBounds.push(target.bounds);
        }
      }
    }

    return this.mergeBoundingBoxes(dirtyBounds);
  }

  private repaintCommittedRegion(region: BoundingBox): boolean {
    if (!this.areCommittedLayersReady()) {
      return false;
    }

    const pageRegion = clampBoundingBox(region, this.getPageWidth(), this.getPageHeight());
    if (pageRegion === null) {
      return true;
    }

    const size = this.getCanvasSize(this.committedContext2D);
    const transform = this.getPageViewportTransform(size);
    this.syncElementLayerTransform(transform);
    const visibleRegion = this.getVisiblePageRegion(transform);
    if (visibleRegion === null) {
      return true;
    }

    const visibleBounds = this.toBoundingBox(visibleRegion);
    if (this.redrawCommittedRegion(pageRegion, transform, visibleBounds)) {
      this.drawPageBorder(this.committedContext2D, transform);
    }

    return true;
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
        if (this.hiddenStrokeIdsDuringSelectionMove.has(stroke.id)) {
          continue;
        }

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
        if (this.hiddenStrokeIdsDuringSelectionMove.has(strokeId)) {
          continue;
        }

        const stroke = this.renderedStrokesById.get(strokeId);
        if (stroke !== undefined) {
          this.drawStroke(context, stroke, useFastRendering);
        }
      }
      return;
    }

    for (const stroke of strokes) {
      if (this.hiddenStrokeIdsDuringSelectionMove.has(stroke.id)) {
        continue;
      }

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
    StrokeRenderer.drawPreviewStroke(context, stroke);
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
    this.hiddenStrokeIdsDuringSelectionMove.clear();
    this.viewportZoomScale = MIN_ZOOM_SCALE;
    this.viewportOffsetX = 0;
    this.viewportOffsetY = 0;
    this.isViewportTransformReady = false;
    this.endViewportGesture(false);
    this.endWorkspacePan(false);
    this.isDrawingGestureActive = false;
    this.isLassoGestureActive = false;
    this.shouldClearSelectionOnLassoTap = false;
    this.isSelectionMovePending = false;
    this.pendingSelectionHitResult = null;
    this.isSelectionMoveGestureActive = false;
    this.strokeResizeUiMode = 'none';
    this.strokeResizeBounds = null;
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

  private applyPageTransformAndClip(context: CanvasDrawContext, transform: PageViewportTransform): void {
    context.translate(transform.offsetX, transform.offsetY);
    context.scale(transform.scale, transform.scale);
    context.beginPath();
    context.rect(0, 0, transform.pageWidth, transform.pageHeight);
    context.clip();
  }

  private drawPageBorder(context: CanvasDrawContext, transform: PageViewportTransform): void {
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
    this.pauseSelectionOverlay();
    this.flattenRecentCommittedLayer();
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
    if (wasPanning) {
      this.scheduleSelectionOverlayResume();
    }
    if (redrawFinal && wasPanning) {
      this.redrawViewportLayers(false);
    }
  }

  private beginViewportGesture(pairMetrics: TouchPairMetrics): void {
    const size = this.getCanvasSize(this.overlayContext2D);
    const transform = this.getPageViewportTransform(size);

    this.isViewportGestureActive = true;
    this.pauseSelectionOverlay();
    this.flattenRecentCommittedLayer();
    this.viewportGestureStartDistance = Math.max(1, pairMetrics.distance);
    this.viewportGestureStartZoomScale = this.viewportZoomScale;
    this.viewportGestureStartPageX = (pairMetrics.centerX - transform.offsetX) / transform.scale;
    this.viewportGestureStartPageY = (pairMetrics.centerY - transform.offsetY) / transform.scale;
    this.viewportGestureLastCenterX = pairMetrics.centerX;
    this.viewportGestureLastCenterY = pairMetrics.centerY;
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
    if (wasGesturing) {
      this.scheduleSelectionOverlayResume();
    }
    if (wasGesturing && this.isDocumentCanvasGestureEnabled()) {
      this.onDocumentViewportGestureEnd();
      return;
    }
    if (redrawFinal && wasGesturing) {
      this.redrawViewportLayers(false);
    }
  }

  private beginDocumentViewportGesture(pairMetrics: TouchPairMetrics): void {
    this.isViewportGestureActive = true;
    this.viewportGestureStartDistance = Math.max(1, pairMetrics.distance);
    this.viewportGestureLastCenterX = pairMetrics.centerX;
    this.viewportGestureLastCenterY = pairMetrics.centerY;
    this.onDocumentViewportGestureStart();
  }

  private updateDocumentViewportGesture(pairMetrics: TouchPairMetrics): void {
    if (!this.isViewportGestureActive) {
      return;
    }

    const distanceRatio = Math.max(0.1, pairMetrics.distance / Math.max(1, this.viewportGestureStartDistance));
    const deltaX = pairMetrics.centerX - this.viewportGestureLastCenterX;
    const deltaY = pairMetrics.centerY - this.viewportGestureLastCenterY;
    this.viewportGestureLastCenterX = pairMetrics.centerX;
    this.viewportGestureLastCenterY = pairMetrics.centerY;
    this.onDocumentViewportGestureUpdate(distanceRatio, deltaX, deltaY);
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

    this.redrawCommittedLayer(useFastRendering, false);
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
    context.save();
    this.applyPageTransformAndClip(context, transform);
    this.drawPreviewStroke(context, stroke);
    context.restore();
  }

  private appendPreviewStrokeOnViewport(
    context: CanvasRenderingContext2D,
    stroke: Stroke,
    previousSession: InProgressStrokeRenderSession | null
  ): InProgressStrokeRenderSession {
    const size = this.getCanvasSize(context);
    const transform = this.getPageViewportTransform(size);
    context.save();
    this.applyPageTransformAndClip(context, transform);
    const nextSession = StrokeRenderer.appendInProgressStroke(context, stroke, previousSession);
    context.restore();
    return nextSession;
  }

  private renderActiveStrokePreview(stroke: Stroke): void {
    if (!this.isOverlayLayerReady) {
      return;
    }

    if (this.shouldUseWholeStrokePreviewRebuild(stroke)) {
      this.rebuildActivePreviewLayers(stroke);
      return;
    }

    const renderStartedAt = Date.now();
    const previousSession = this.activePreviewSession;
    if (previousSession === null || !this.canContinueActivePreviewSession(stroke)) {
      this.rebuildActivePreviewLayers(stroke);
      EditorPerformanceTrace.record(
        'preview.render',
        Date.now() - renderStartedAt,
        `mode=full points=${stroke.points.length}`,
        6
      );
      return;
    }

    const previousPointCount = previousSession.processedPointCount;
    this.activePreviewSession = this.appendPreviewStrokeOnViewport(this.overlayContext2D, stroke, previousSession);
    EditorPerformanceTrace.record(
      'preview.render',
      Date.now() - renderStartedAt,
      `mode=append points=${stroke.points.length} added=${Math.max(0, stroke.points.length - previousPointCount)}`,
      6
    );
  }

  private rebuildActivePreviewLayers(stroke: Stroke): void {
    const rebuildStartedAt = Date.now();
    this.clearPreviewLayers();
    if (this.shouldUseWholeStrokePreviewRebuild(stroke)) {
      this.drawPreviewStrokeOnViewport(this.overlayContext2D, stroke);
      this.activePreviewSession = null;
    } else {
      this.activePreviewSession = this.appendPreviewStrokeOnViewport(this.overlayContext2D, stroke, null);
    }
    EditorPerformanceTrace.record(
      'preview.rebuild',
      Date.now() - rebuildStartedAt,
      `points=${stroke.points.length}`,
      6
    );
  }

  private resetActivePreviewSession(): void {
    this.activePreviewSession = null;
  }

  private shouldUseWholeStrokePreviewRebuild(stroke: Stroke): boolean {
    return stroke.style.tool === 'highlighter' || stroke.style.tool === 'pencil';
  }

  private consumeLatestRenderInvalidationSequence(): void {
    const viewModel = this.getViewModel();
    if (viewModel === null) {
      return;
    }

    const invalidation = viewModel.getRenderInvalidation();
    if (invalidation !== null) {
      this.lastAppliedRenderInvalidationSequence = invalidation.sequence;
    }
  }

  private canContinueActivePreviewSession(stroke: Stroke): boolean {
    if (this.activePreviewSession === null) {
      return false;
    }

    return this.activePreviewSession.strokeId === stroke.id &&
      this.activePreviewSession.processedPointCount <= stroke.points.length;
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
    const redrawStartedAt = Date.now();
    const previousRecentStrokeIds = this.getRecentCommittedStrokeIdSet();
    this.applyRenderedStrokeMutation(invalidation);
    if (this.canUseRecentCommittedFastPath(invalidation, previousRecentStrokeIds)) {
      this.redrawRecentCommittedLayer(false);
      EditorPerformanceTrace.record(
        'committed.partialRedraw',
        Date.now() - redrawStartedAt,
        `reason=${invalidation.reason} dirtyRects=0 tiles=0 mode=recent removed=${invalidation.removedStrokeIds.length} added=${invalidation.addedRecords.length}`,
        8
      );
      return true;
    }

    if (this.requiresFullCommittedRedrawWithRecentLayer(invalidation, previousRecentStrokeIds)) {
      this.redrawCommittedLayer(false, true);
      EditorPerformanceTrace.record(
        'committed.partialRedraw',
        Date.now() - redrawStartedAt,
        `reason=${invalidation.reason} dirtyRects=0 tiles=0 mode=fullRecent removed=${invalidation.removedStrokeIds.length} added=${invalidation.addedRecords.length}`,
        8
      );
      return true;
    }

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
    if (this.shouldUseUnifiedCommittedRedraw(invalidation, dirtyRects)) {
      const mergedDirtyRegion = this.mergeBoundingBoxes(dirtyRects);
      if (mergedDirtyRegion !== null) {
        const hasRedrawnRegion = this.redrawCommittedRegion(mergedDirtyRegion, transform, visibleBounds);
        if (hasRedrawnRegion) {
          this.drawPageBorder(this.committedContext2D, transform);
        }

        EditorPerformanceTrace.record(
          'committed.partialRedraw',
          Date.now() - redrawStartedAt,
          `reason=${invalidation.reason} dirtyRects=${dirtyRects.length} tiles=0 mode=region removed=${invalidation.removedStrokeIds.length} added=${invalidation.addedRecords.length}`,
          8
        );
        return true;
      }
    }

    let hasRedrawnTile = false;
    const tileBoundsList = this.buildCommittedTileBoundsForDirtyRects(dirtyRects);
    for (const tileBounds of tileBoundsList) {
      if (this.redrawCommittedTile(tileBounds, transform, visibleBounds)) {
        hasRedrawnTile = true;
      }
    }

    if (hasRedrawnTile) {
      this.drawPageBorder(this.committedContext2D, transform);
    }

    EditorPerformanceTrace.record(
      'committed.partialRedraw',
      Date.now() - redrawStartedAt,
      `reason=${invalidation.reason} dirtyRects=${dirtyRects.length} tiles=${tileBoundsList.length} removed=${invalidation.removedStrokeIds.length} added=${invalidation.addedRecords.length}`,
      8
    );

    return true;
  }

  private shouldUseUnifiedCommittedRedraw(
    invalidation: RenderInvalidation,
    dirtyRects: BoundingBox[]
  ): boolean {
    if (dirtyRects.length === 0) {
      return false;
    }

    switch (invalidation.reason) {
      case 'undo':
      case 'redo':
      case 'clear':
        return true;
      default:
        return dirtyRects.length === 1;
    }
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

  private rebuildRenderedStrokeCache(strokes: Stroke[]): void {
    this.clearRenderedStrokeState();
    for (const stroke of strokes) {
      this.appendRenderedStroke(stroke);
    }
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
    const redrawStartedAt = Date.now();
    const tileRegion = this.intersectBoundingBoxes(tileBounds, visibleBounds);
    if (tileRegion === null) {
      return false;
    }

    const redrawRegion = this.expandCommittedTileRegion(tileRegion, transform);
    const candidateStrokeIds = this.redrawCommittedRegionCore(redrawRegion, transform);
    EditorPerformanceTrace.record(
      'committed.tile',
      Date.now() - redrawStartedAt,
      `candidateStrokes=${candidateStrokeIds.length} region=${this.describeBoundingBox(redrawRegion)}`,
      4
    );
    return true;
  }

  private redrawCommittedRegion(
    region: BoundingBox,
    transform: PageViewportTransform,
    visibleBounds: BoundingBox
  ): boolean {
    const clippedRegion = this.intersectBoundingBoxes(region, visibleBounds);
    if (clippedRegion === null) {
      return false;
    }

    const redrawStartedAt = Date.now();
    const redrawRegion = this.expandCommittedTileRegion(clippedRegion, transform);
    const candidateStrokeIds = this.redrawCommittedRegionCore(redrawRegion, transform);
    EditorPerformanceTrace.record(
      'committed.region',
      Date.now() - redrawStartedAt,
      `candidateStrokes=${candidateStrokeIds.length} region=${this.describeBoundingBox(redrawRegion)}`,
      4
    );
    return true;
  }

  private redrawRecentCommittedLayer(useFastRendering: boolean): void {
    if (!this.areCommittedLayersReady()) {
      return;
    }

    const redrawStartedAt = Date.now();
    const viewModel = this.getViewModel();
    const strokes = viewModel ? viewModel.getStrokesForRendering() : [];
    this.clearRecentCommittedLayer();
    if (this.flattenedCommittedStrokeCount >= strokes.length) {
      EditorPerformanceTrace.record('committed.recentRedraw', Date.now() - redrawStartedAt, 'strokes=0', 4);
      return;
    }

    const size = this.getCanvasSize(this.recentCommittedContext2D);
    const transform = this.getPageViewportTransform(size);
    const visibleRegion = this.getVisiblePageRegion(transform);
    if (visibleRegion === null) {
      EditorPerformanceTrace.record('committed.recentRedraw', Date.now() - redrawStartedAt, 'visible=false', 4);
      return;
    }

    const visibleBounds = this.toBoundingBox(visibleRegion);
    this.recentCommittedContext2D.save();
    this.applyPageTransformAndClip(this.recentCommittedContext2D, transform);
    this.drawStrokeRange(
      this.recentCommittedContext2D,
      strokes,
      this.flattenedCommittedStrokeCount,
      strokes.length,
      visibleBounds,
      useFastRendering
    );
    this.recentCommittedContext2D.restore();
    EditorPerformanceTrace.record(
      'committed.recentRedraw',
      Date.now() - redrawStartedAt,
      `strokes=${Math.max(0, strokes.length - this.flattenedCommittedStrokeCount)}`,
      4
    );
  }

  private trimRecentCommittedLayerIntoBase(): boolean {
    if (!this.areCommittedLayersReady()) {
      return false;
    }

    const trimStartedAt = Date.now();
    let bakedStrokeCount = 0;
    while (this.getRecentCommittedStrokeCount() > RECENT_COMMITTED_STROKE_LIMIT) {
      const strokeId = this.renderedStrokeOrder[this.flattenedCommittedStrokeCount];
      if (strokeId === undefined) {
        return false;
      }

      const stroke = this.renderedStrokesById.get(strokeId);
      if (stroke === undefined) {
        return false;
      }

      this.drawStrokeOnViewport(this.committedContext2D, stroke, false);
      this.flattenedCommittedStrokeCount += 1;
      bakedStrokeCount += 1;
    }

    if (bakedStrokeCount === 0) {
      return false;
    }

    EditorPerformanceTrace.record(
      'committed.recentBake',
      Date.now() - trimStartedAt,
      `baked=${bakedStrokeCount} flattened=${this.flattenedCommittedStrokeCount} recent=${this.getRecentCommittedStrokeCount()}`,
      4
    );
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

  private redrawCommittedRegionCore(
    redrawRegion: BoundingBox,
    transform: PageViewportTransform
  ): string[] {
    const candidateStrokeIds = this.strokeSpatialIndex.queryStrokeIds(redrawRegion)
      .sort((left: string, right: string) => this.getRenderedStrokeIndex(left) - this.getRenderedStrokeIndex(right));

    if (!this.repaintCommittedBaseRegionWithBuffer(redrawRegion, transform, candidateStrokeIds)) {
      this.clearCommittedRegion(redrawRegion, transform);
    }
    this.repaintRecentCommittedRegionWithBuffer(redrawRegion, transform, candidateStrokeIds);
    return candidateStrokeIds;
  }

  private repaintCommittedBaseRegionWithBuffer(
    redrawRegion: BoundingBox,
    transform: PageViewportTransform,
    candidateStrokeIds: string[]
  ): boolean {
    const viewportRegion = this.toPixelAlignedViewportRegion(redrawRegion, transform);
    if (viewportRegion === null) {
      return true;
    }

    const width = viewportRegion.maxX - viewportRegion.minX;
    const height = viewportRegion.maxY - viewportRegion.minY;
    if (width <= 0 || height <= 0) {
      return true;
    }

    const offscreenCanvas = new OffscreenCanvas(width, height);
    const offscreenContext = offscreenCanvas.getContext('2d', this.committedRenderingSettings);
    offscreenContext.clearRect(0, 0, width, height);
    offscreenContext.save();
    offscreenContext.translate(-viewportRegion.minX, -viewportRegion.minY);
    this.applyPageTransformAndClip(offscreenContext, transform);
    offscreenContext.beginPath();
    offscreenContext.rect(
      redrawRegion.minX,
      redrawRegion.minY,
      redrawRegion.maxX - redrawRegion.minX,
      redrawRegion.maxY - redrawRegion.minY
    );
    offscreenContext.clip();
    PageTemplateRenderer.drawTemplateBackground(
      offscreenContext,
      this.templateType,
      transform.pageWidth,
      transform.pageHeight,
      this.paperBackgroundColor,
      {
        x: redrawRegion.minX,
        y: redrawRegion.minY,
        width: redrawRegion.maxX - redrawRegion.minX,
        height: redrawRegion.maxY - redrawRegion.minY
      }
    );

    for (const strokeId of candidateStrokeIds) {
      if (this.hiddenStrokeIdsDuringSelectionMove.has(strokeId)) {
        continue;
      }

      const stroke = this.renderedStrokesById.get(strokeId);
      if (stroke === undefined) {
        continue;
      }

      if (this.shouldSkipRecentCommittedStrokeInBaseLayer(strokeId)) {
        continue;
      }

      const strokeBounds = this.strokeSpatialIndex.getBounds(strokeId);
      if (strokeBounds !== null && doBoundingBoxesIntersect(strokeBounds, redrawRegion)) {
        this.drawStroke(offscreenContext, stroke);
      }
    }

    offscreenContext.restore();
    const bitmap = offscreenCanvas.transferToImageBitmap();
    this.committedContext2D.drawImage(bitmap, viewportRegion.minX, viewportRegion.minY, width, height);
    bitmap.close();
    return true;
  }

  private repaintRecentCommittedRegionWithBuffer(
    redrawRegion: BoundingBox,
    transform: PageViewportTransform,
    candidateStrokeIds: string[]
  ): boolean {
    if (!this.hasActiveRecentCommittedLayer()) {
      return true;
    }

    const viewportRegion = this.toPixelAlignedViewportRegion(redrawRegion, transform);
    if (viewportRegion === null) {
      return true;
    }

    const width = viewportRegion.maxX - viewportRegion.minX;
    const height = viewportRegion.maxY - viewportRegion.minY;
    if (width <= 0 || height <= 0) {
      return true;
    }

    const offscreenCanvas = new OffscreenCanvas(width, height);
    const offscreenContext = offscreenCanvas.getContext('2d', this.recentCommittedRenderingSettings);
    offscreenContext.clearRect(0, 0, width, height);
    offscreenContext.save();
    offscreenContext.translate(-viewportRegion.minX, -viewportRegion.minY);
    this.applyPageTransformAndClip(offscreenContext, transform);
    offscreenContext.beginPath();
    offscreenContext.rect(
      redrawRegion.minX,
      redrawRegion.minY,
      redrawRegion.maxX - redrawRegion.minX,
      redrawRegion.maxY - redrawRegion.minY
    );
    offscreenContext.clip();

    for (const strokeId of candidateStrokeIds) {
      if (this.hiddenStrokeIdsDuringSelectionMove.has(strokeId)) {
        continue;
      }

      if (!this.shouldSkipRecentCommittedStrokeInBaseLayer(strokeId)) {
        continue;
      }

      const stroke = this.renderedStrokesById.get(strokeId);
      if (stroke === undefined) {
        continue;
      }

      const strokeBounds = this.strokeSpatialIndex.getBounds(strokeId);
      if (strokeBounds !== null && doBoundingBoxesIntersect(strokeBounds, redrawRegion)) {
        this.drawStroke(offscreenContext, stroke);
      }
    }

    offscreenContext.restore();
    const bitmap = offscreenCanvas.transferToImageBitmap();
    this.recentCommittedContext2D.clearRect(
      viewportRegion.minX,
      viewportRegion.minY,
      width,
      height
    );
    this.recentCommittedContext2D.drawImage(bitmap, viewportRegion.minX, viewportRegion.minY, width, height);
    bitmap.close();
    return true;
  }

  private drawStrokeRange(
    context: CanvasDrawContext,
    strokes: Stroke[],
    startIndex: number,
    endIndex: number,
    visibleBounds: BoundingBox,
    useFastRendering: boolean
  ): void {
    for (let index = startIndex; index < endIndex; index += 1) {
      const stroke = strokes[index];
      if (this.hiddenStrokeIdsDuringSelectionMove.has(stroke.id)) {
        continue;
      }

      if (this.isStrokeBoundsVisible(stroke, visibleBounds)) {
        this.drawStroke(context, stroke, useFastRendering);
      }
    }
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

  private redrawCommittedBaseLayerWithBuffer(
    size: CanvasSize,
    transform: PageViewportTransform,
    visibleRegion: PageRenderRegion | null,
    strokes: Stroke[],
    flattenedStrokeCount: number,
    useFastRendering: boolean
  ): boolean {
    const width = Math.ceil(size.width);
    const height = Math.ceil(size.height);
    if (width <= 0 || height <= 0) {
      return true;
    }

    try {
      const offscreenCanvas = new OffscreenCanvas(width, height);
      const offscreenContext = offscreenCanvas.getContext('2d', this.committedRenderingSettings);
      offscreenContext.clearRect(0, 0, width, height);
      this.drawCommittedBaseLayerContent(
        offscreenContext,
        transform,
        visibleRegion,
        strokes,
        flattenedStrokeCount,
        useFastRendering
      );
      this.drawPageBorder(offscreenContext, transform);

      const bitmap = offscreenCanvas.transferToImageBitmap();
      this.committedContext2D.clearRect(0, 0, size.width, size.height);
      this.committedContext2D.drawImage(bitmap, 0, 0, width, height);
      bitmap.close();
      return true;
    } catch (_error) {
      return false;
    }
  }

  private redrawCommittedLayerDirect(
    size: CanvasSize,
    transform: PageViewportTransform,
    visibleRegion: PageRenderRegion | null,
    strokes: Stroke[],
    flattenedStrokeCount: number,
    useFastRendering: boolean
  ): void {
    this.committedContext2D.clearRect(0, 0, size.width, size.height);
    this.drawCommittedBaseLayerContent(
      this.committedContext2D,
      transform,
      visibleRegion,
      strokes,
      flattenedStrokeCount,
      useFastRendering
    );
    this.drawPageBorder(this.committedContext2D, transform);
    this.redrawRecentCommittedStrokes(strokes, flattenedStrokeCount, visibleRegion, transform, useFastRendering);
  }

  private drawCommittedBaseLayerContent(
    context: CanvasDrawContext,
    transform: PageViewportTransform,
    visibleRegion: PageRenderRegion | null,
    strokes: Stroke[],
    flattenedStrokeCount: number,
    useFastRendering: boolean
  ): void {
    if (visibleRegion === null) {
      return;
    }

    const visibleBounds = this.toBoundingBox(visibleRegion);
    context.save();
    this.applyPageTransformAndClip(context, transform);
    PageTemplateRenderer.drawTemplateBackground(
      context,
      this.templateType,
      transform.pageWidth,
      transform.pageHeight,
      this.paperBackgroundColor,
      visibleRegion
    );
    this.drawStrokeRange(context, strokes, 0, flattenedStrokeCount, visibleBounds, useFastRendering);
    context.restore();
  }

  private redrawRecentCommittedStrokes(
    strokes: Stroke[],
    flattenedStrokeCount: number,
    visibleRegion: PageRenderRegion | null,
    transform: PageViewportTransform,
    useFastRendering: boolean
  ): void {
    this.clearRecentCommittedLayer();
    if (visibleRegion === null || flattenedStrokeCount >= strokes.length) {
      return;
    }

    const visibleBounds = this.toBoundingBox(visibleRegion);
    this.recentCommittedContext2D.save();
    this.applyPageTransformAndClip(this.recentCommittedContext2D, transform);
    this.drawStrokeRange(
      this.recentCommittedContext2D,
      strokes,
      flattenedStrokeCount,
      strokes.length,
      visibleBounds,
      useFastRendering
    );
    this.recentCommittedContext2D.restore();
  }

  private toPixelAlignedViewportRegion(region: BoundingBox, transform: PageViewportTransform): BoundingBox | null {
    const viewportRegion = this.toViewportBoundingBox(region, transform);
    if (viewportRegion === null) {
      return null;
    }

    const pixelRegion: BoundingBox = {
      minX: Math.floor(viewportRegion.minX),
      minY: Math.floor(viewportRegion.minY),
      maxX: Math.ceil(viewportRegion.maxX),
      maxY: Math.ceil(viewportRegion.maxY)
    };

    return clampBoundingBox(pixelRegion, transform.viewportWidth, transform.viewportHeight);
  }

  private expandCommittedTileRegion(region: BoundingBox, transform: PageViewportTransform): BoundingBox {
    const pagePadding = Math.max(1, PARTIAL_REDRAW_OVERDRAW_VIEWPORT_PX / Math.max(0.01, transform.scale));
    const expandedRegion = expandBoundingBox(region, pagePadding);
    return clampBoundingBox(expandedRegion, transform.pageWidth, transform.pageHeight) ?? region;
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

  private mergeBoundingBoxes(boundsList: BoundingBox[]): BoundingBox | null {
    if (boundsList.length === 0) {
      return null;
    }

    let mergedBounds: BoundingBox = {
      minX: boundsList[0].minX,
      minY: boundsList[0].minY,
      maxX: boundsList[0].maxX,
      maxY: boundsList[0].maxY
    };

    for (let index = 1; index < boundsList.length; index += 1) {
      const nextBounds = boundsList[index];
      mergedBounds = {
        minX: Math.min(mergedBounds.minX, nextBounds.minX),
        minY: Math.min(mergedBounds.minY, nextBounds.minY),
        maxX: Math.max(mergedBounds.maxX, nextBounds.maxX),
        maxY: Math.max(mergedBounds.maxY, nextBounds.maxY)
      };
    }

    return mergedBounds;
  }

  private getRecentCommittedStrokeIdSet(): Set<string> {
    const recentStrokeIds = new Set<string>();
    for (let index = this.flattenedCommittedStrokeCount; index < this.renderedStrokeOrder.length; index += 1) {
      recentStrokeIds.add(this.renderedStrokeOrder[index]);
    }

    return recentStrokeIds;
  }

  private canUseRecentCommittedFastPath(
    invalidation: RenderInvalidation,
    previousRecentStrokeIds: Set<string>
  ): boolean {
    if (invalidation.reason !== 'undo' && invalidation.reason !== 'redo') {
      return false;
    }

    const viewModel = this.getViewModel();
    if (viewModel === null) {
      return false;
    }

    const strokes = viewModel.getStrokesForRendering();
    if (this.flattenedCommittedStrokeCount > strokes.length) {
      return false;
    }

    if (strokes.length - this.flattenedCommittedStrokeCount > RECENT_COMMITTED_STROKE_LIMIT) {
      return false;
    }

    for (const strokeId of invalidation.removedStrokeIds) {
      if (!previousRecentStrokeIds.has(strokeId)) {
        return false;
      }
    }

    for (const record of invalidation.addedRecords) {
      if (record.index < this.flattenedCommittedStrokeCount) {
        return false;
      }
    }

    return true;
  }

  private requiresFullCommittedRedrawWithRecentLayer(
    invalidation: RenderInvalidation,
    previousRecentStrokeIds: Set<string>
  ): boolean {
    if (!this.hasActiveRecentCommittedLayer()) {
      return false;
    }

    if (invalidation.reason === 'clear') {
      return true;
    }

    if (invalidation.reason === 'move' || invalidation.reason === 'resize') {
      return false;
    }

    for (const strokeId of invalidation.removedStrokeIds) {
      if (previousRecentStrokeIds.has(strokeId)) {
        return true;
      }
    }

    for (const record of invalidation.addedRecords) {
      if (record.index >= this.flattenedCommittedStrokeCount) {
        return true;
      }
    }

    return false;
  }

  private canAppendToRecentCommittedLayer(): boolean {
    const viewModel = this.getViewModel();
    if (viewModel === null) {
      return false;
    }

    return viewModel.getStrokesForRendering().length - this.flattenedCommittedStrokeCount <= RECENT_COMMITTED_STROKE_LIMIT;
  }

  private getRecentCommittedStrokeCount(): number {
    return Math.max(0, this.renderedStrokeOrder.length - this.flattenedCommittedStrokeCount);
  }

  private hasActiveRecentCommittedLayer(): boolean {
    return this.flattenedCommittedStrokeCount < this.renderedStrokeOrder.length;
  }

  private shouldSkipRecentCommittedStrokeInBaseLayer(strokeId: string): boolean {
    if (!this.hasActiveRecentCommittedLayer()) {
      return false;
    }

    const strokeIndex = this.getRenderedStrokeIndex(strokeId);
    return strokeIndex >= this.flattenedCommittedStrokeCount;
  }

  private areCommittedLayersReady(): boolean {
    return this.isCommittedLayerReady && this.isRecentCommittedLayerReady;
  }

  private describeBoundingBox(bounds: BoundingBox | null): string {
    if (bounds === null) {
      return 'none';
    }

    return `${Math.round(bounds.minX)},${Math.round(bounds.minY)}-${Math.round(bounds.maxX)},${Math.round(bounds.maxY)}`;
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

  private drawLassoDraft(context: CanvasRenderingContext2D, path: StrokePoint[]): void {
    if (path.length === 0) {
      return;
    }

    context.save();
    SelectionDashRenderer.drawPath(context, path, false, 0);
    context.restore();
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
    this.hideSelectionContextMenu();
    this.selectedStrokeTargets = [];
    this.strokeResizeBounds = null;
    this.strokeResizeUiMode = 'none';
    this.lastSelectionVersion = -1;
    this.selectionOverlayRefreshVersion += 1;
    this.resumeSelectionOverlayImmediately();
    this.resetViewportTransform();
    this.clearCommittedLayer();
    this.clearRenderedStrokeState();
    this.lastAppliedRenderInvalidationSequence = 0;
    this.forceFullCommittedRedrawOnNextCanvasRefresh = true;
    this.clearPreviewLayers();
    this.resetActivePreviewSession();
    this.resolveViewModel();
  }

  private onActiveToolChanged(): void {
    if (this.activeTool !== 'edit') {
      this.commitInlineTextEdit(true);
    }
    const viewModel = this.getViewModel();
    if (viewModel !== null && this.activeTool !== 'lasso') {
      this.exitStrokeResizeMode(viewModel);
    }
    if (viewModel !== null && this.activeTool !== 'lasso') {
      this.cancelSelectionMoveGesture(viewModel);
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
      this.cancelSelectionMoveGesture(viewModel);
    }
    this.endWorkspacePan(false);
    this.endViewportGesture(false);
    if (this.isDocumentViewportMode && this.isPanModeEnabled) {
      this.resetViewportTransform();
      this.redrawViewportLayers(false);
    }
  }

  private isDocumentCanvasGestureEnabled(): boolean {
    return this.isDocumentViewportMode && !this.isPanModeEnabled;
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
      this.clearCommittedLayer();
      this.hiddenStrokeIdsDuringSelectionMove.clear();
      this.strokeResizeBounds = null;
      this.strokeResizeUiMode = 'none';
      this.clearRenderedStrokeState();
      this.lastAppliedRenderInvalidationSequence = 0;
      this.forceFullCommittedRedrawOnNextCanvasRefresh = true;
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
