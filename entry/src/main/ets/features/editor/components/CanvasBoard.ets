import common from '@ohos.app.ability.common';
import abilityAccessCtrl, { Permissions } from '@ohos.abilityAccessCtrl';
import photoAccessHelper from '@ohos.file.photoAccessHelper';
import image from '@ohos.multimedia.image';

import {
  BoundingBox,
  clampBoundingBox,
  doBoundingBoxesIntersect,
  expandBoundingBox,
  getStrokeRenderBoundingBox
} from '../../../common/utils/GeometryUtil';
import { clampElementFrameToBounds } from '../../../common/utils/ElementBoundsUtil';
import {
  CanvasElement,
  ElementOutlineLineStyle,
  ImageCanvasElement,
  ShapeType,
  TextCanvasElement
} from '../../../domain/entities/CanvasElement';
import { NotebookPageTemplateType } from '../../../domain/entities/NotebookPage';
import { NotebookPageCanvasEntity } from '../../../domain/entities/NotebookPageCanvas';
import { Stroke, StrokePoint } from '../../../domain/entities/Stroke';
import { ToolSetting } from '../../../domain/entities/ToolSetting';
import { PageTemplateRenderer } from '../controllers/PageTemplateRenderer';
import { CanvasElementRenderer } from '../controllers/CanvasElementRenderer';
import { InProgressStrokeRenderSession, StrokeRenderer } from '../controllers/StrokeRenderer';
import { SelectionDashRenderer } from '../controllers/SelectionDashRenderer';
import { ShapeRenderer } from '../controllers/ShapeRenderer';
import { IndexedStrokeRecord } from '../controllers/UndoRedoController';
import { StrokeSpatialHashIndex } from '../controllers/StrokeSpatialHashIndex';
import { SelectionController } from '../selection/SelectionController';
import {
  LayerActionAvailability,
  LayerOrderAction,
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
import { XFYUN_FORMULA_CONFIG } from '../services/XfyunFormulaConfig';
import { XfyunFormulaService } from '../services/XfyunFormulaService';
import { XFYUN_OCR_CONFIG } from '../services/XfyunOcrConfig';
import { XfyunOcrService } from '../services/XfyunOcrService';
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

interface PageRenderRegion {
  x: number;
  y: number;
  width: number;
  height: number;
}

interface RecognitionInsertFrame {
  x: number;
  y: number;
  width: number;
  height: number;
}

interface RecognitionSelectionImagePayload {
  base64Image: string;
  pngBytes: Uint8Array;
  frame: RecognitionInsertFrame;
  width: number;
  height: number;
  contentWidth: number;
  contentHeight: number;
  scale: number;
  strokeCount: number;
  elementCount: number;
}

interface SelectionBoundsFrame {
  width: number;
  height: number;
}

interface RecognitionEncodedPng {
  base64Image: string;
  bytes: Uint8Array;
}

interface ExtendedTouchObject extends TouchObject {
  pressure?: number;
  force?: number;
  timestamp?: number;
  eventTime?: number;
  t?: number;
}

type CanvasDrawContext = CanvasRenderingContext2D | OffscreenCanvasRenderingContext2D;
type RecognitionExportMode = 'ocr' | 'formula';

const COMMITTED_TILE_SIZE = 256;
const PARTIAL_REDRAW_OVERDRAW_VIEWPORT_PX = 2;
const RECENT_COMMITTED_STROKE_LIMIT = 6;
const RECENT_COMMITTED_IDLE_FLUSH_DELAY_MS = 420;
type StrokeResizeUiMode = 'none' | 'ready' | 'resizing' | 'moving';
type ElementStylePanelMode = 'none' | 'fill' | 'outline' | 'layer';
const DEFAULT_VIEWPORT_WIDTH = 1600;
const DEFAULT_VIEWPORT_HEIGHT = 900;
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
const SELECTION_CONTEXT_MENU_WIDTH = 144;
const SELECTION_CONTEXT_MENU_ITEM_HEIGHT = 38;
const ELEMENT_LAYER_Z_INDEX_MIN = -1000000000;
const ELEMENT_LAYER_Z_INDEX_MAX = 1000000000;
const SELECTION_CONTEXT_MENU_OFFSET = 8;
const ELEMENT_STYLE_PANEL_WIDTH = 220;
const ELEMENT_STYLE_PANEL_COLOR_OPTIONS: string[] = [
  '#00FFFFFF',
  '#111827',
  '#FFFFFF',
  '#EF4444',
  '#F59E0B',
  '#22C55E',
  '#3B82F6',
  '#8B5CF6'
];
const ELEMENT_OUTLINE_COLOR_OPTIONS: string[] = ['#111827', '#FFFFFF', '#EF4444', '#F59E0B', '#22C55E', '#3B82F6', '#8B5CF6'];
const ELEMENT_OUTLINE_WIDTH_OPTIONS: number[] = [1, 2, 4, 6, 8];
const ELEMENT_OUTLINE_WIDTH_MIN = 1;
const ELEMENT_OUTLINE_WIDTH_MAX = 16;
const ELEMENT_OUTLINE_WIDTH_STEP = 1;
const ELEMENT_OUTLINE_LINE_STYLE_OPTIONS: ElementOutlineLineStyle[] = ['none', 'solid', 'dashed', 'dotted'];
const FORMULA_EXPORT_PADDING = 36;
const FORMULA_EXPORT_MIN_EDGE = 320;
const FORMULA_EXPORT_SCALE = 3;
const FORMULA_EXPORT_MIN_STROKE_WIDTH = 4;
const FORMULA_EXPORT_STROKE_WIDTH_FACTOR = 1.25;
const OCR_EXPORT_PADDING = 36;
const OCR_EXPORT_SCALE = 3;
const OCR_EXPORT_MIN_EDGE = 320;
const OCR_EXPORT_MIN_STROKE_WIDTH = 10;
const OCR_EXPORT_STROKE_WIDTH_FACTOR = 1.7;
const VIEWPORT_INACTIVE_FAST_REDRAW_BASE_DELAY_MS = 32;
const VIEWPORT_INACTIVE_FAST_REDRAW_STAGGER_MS = 96;
const VIEWPORT_ACTIVE_QUALITY_REDRAW_DELAY_MS = 360;
const VIEWPORT_INACTIVE_QUALITY_REDRAW_BASE_DELAY_MS = 720;
const VIEWPORT_INACTIVE_QUALITY_REDRAW_STAGGER_MS = 260;
const VIEWPORT_QUALITY_REDRAW_RETRY_DELAY_MS = 240;
const VIEWPORT_QUALITY_REDRAW_STROKE_LIMIT = 180;
export type CanvasBoardContentChangeKind = 'stroke' | 'element';
export type CanvasInputMode = 'stylus' | 'touch';

const DEFAULT_CANVAS_TOOL_SETTING: ToolSetting = {
  tool: 'pen',
  color: '#111827',
  width: 4,
  opacity: 1
};

@Component
export struct CanvasBoard {
  @Watch('onPageIdChanged')
  @Prop pageId: string = '';
  @Watch('onCanvasVersionChanged')
  @Prop canvasVersion: number = 0;
  @Watch('onViewportRefreshVersionChanged')
  @Prop viewportRefreshVersion: number = 0;
  @Watch('onCanvasStyleChanged')
  @Prop templateType: NotebookPageTemplateType = NotebookPageTemplateType.BLANK;
  @Watch('onCanvasStyleChanged')
  @Prop paperBackgroundColor: string = '#FFFFFF';
  @Watch('onPageGeometryChanged')
  @Prop pageWidth: number = NotebookPageCanvasEntity.DEFAULT_WIDTH;
  @Watch('onPageGeometryChanged')
  @Prop pageHeight: number = NotebookPageCanvasEntity.DEFAULT_HEIGHT;
  @Watch('onToolSettingChanged')
  @Prop toolSetting: ToolSetting = DEFAULT_CANVAS_TOOL_SETTING;
  @Watch('onInputModeChanged')
  @Prop inputMode: CanvasInputMode = 'stylus';
  @Watch('onActivePageChanged')
  @Prop isActivePage: boolean = false;
  @Watch('onCanvasStyleChanged')
  @Prop backgroundImageUri: string = '';
  @Watch('onAutoLoadSessionChanged')
  @Prop autoLoadSession: boolean = true;
  @Prop elementVersion: number = 0;
  @Prop selectedShapeType: ShapeType = 'rectangle';
  @Link editorSnapshot: EditorDebugSnapshot;
  onContentChanged: (immediate: boolean, kind: CanvasBoardContentChangeKind) => void =
    (_immediate: boolean, _kind: CanvasBoardContentChangeKind): void => {};
  onCanvasMetricsChanged: (width: number, height: number) => void = (_width: number, _height: number): void => {};
  onPageInteractionStart: (pageId: string) => void = (_pageId: string): void => {};
  onDocumentTouch: (event: TouchEvent) => void = (_event: TouchEvent): void => {};
  private viewModel: DrawingEditorViewModel | null = null;

  private readonly committedRenderingSettings: RenderingContextSettings = new RenderingContextSettings(true);
  private readonly backgroundRenderingSettings: RenderingContextSettings = new RenderingContextSettings(true);
  private readonly recentCommittedRenderingSettings: RenderingContextSettings = new RenderingContextSettings(true);
  private readonly stablePreviewRenderingSettings: RenderingContextSettings = new RenderingContextSettings(true);
  private readonly overlayRenderingSettings: RenderingContextSettings = new RenderingContextSettings(true);
  private readonly committedContext2D: CanvasRenderingContext2D =
    new CanvasRenderingContext2D(this.committedRenderingSettings);
  private readonly backgroundContext2D: CanvasRenderingContext2D =
    new CanvasRenderingContext2D(this.backgroundRenderingSettings);
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
  private hasRecognitionGalleryWritePermission: boolean = false;
  private isDrawingGestureActive: boolean = false;
  private isForwardingDocumentTouchGesture: boolean = false;
  private isLassoGestureActive: boolean = false;
  private isSelectionMovePending: boolean = false;
  private isSelectionMoveGestureActive: boolean = false;
  private pendingSelectionHitResult: SelectionHitResult | null = null;
  private selectionMoveStartScreenX: number = 0;
  private selectionMoveStartScreenY: number = 0;
  private selectionMoveStartPageX: number = 0;
  private selectionMoveStartPageY: number = 0;
  private lassoStartScreenX: number = 0;
  private lassoStartScreenY: number = 0;
  private shouldClearSelectionOnLassoTap: boolean = false;
  private lastEditTapTime: number = 0;
  private lastEditTapElementId: string = '';
  private lastEditTapX: number = 0;
  private lastEditTapY: number = 0;
  private lastSelectionVersion: number = -1;
  private lastLassoOverlayRedrawTime: number = 0;
  private lastSelectionMoveRedrawTime: number = 0;
  private selectionOverlayResumeTimerId: number = -1;
  private backgroundPixelMap: image.PixelMap | null = null;
  private backgroundPixelMapUri: string = '';
  private backgroundPixelMapLoadingUri: string = '';
  private backgroundPixelMapFailedUri: string = '';
  private viewportFastRedrawTimerId: number = -1;
  private viewportQualityRedrawTimerId: number = -1;
  private recentCommittedFlushTimerId: number = -1;
  private lastHighQualityViewportRenderKey: string = '';

  @State private isCommittedLayerReady: boolean = false;
  @State private isBackgroundLayerReady: boolean = false;
  @State private isRecentCommittedLayerReady: boolean = false;
  @State private isStablePreviewLayerReady: boolean = false;
  @State private isOverlayLayerReady: boolean = false;
  @State private elementLayerPageWidth: number = NotebookPageCanvasEntity.DEFAULT_WIDTH;
  @State private elementLayerPageHeight: number = NotebookPageCanvasEntity.DEFAULT_HEIGHT;
  @State private elementLayerScale: number = 1;
  @State private elementLayerOffsetX: number = 0;
  @State private elementLayerOffsetY: number = 0;
  @State private elementLayerLocalRefreshVersion: number = 0;
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
  @State private selectionContextMenuElementId: string = '';
  @State private elementStylePanelMode: ElementStylePanelMode = 'none';
  @State private selectionContextFillColor: string = '#00FFFFFF';
  @State private selectionContextOutlineLineStyle: ElementOutlineLineStyle = 'solid';
  @State private selectionContextOutlineColor: string = '#111827';
  @State private selectionContextOutlineWidth: number = 2;
  @State private canLayerMoveUp: boolean = false;
  @State private canLayerMoveDown: boolean = false;
  @State private canLayerMoveTop: boolean = false;
  @State private canLayerMoveBottom: boolean = false;
  @State private selectionContextMenuX: number = 0;
  @State private selectionContextMenuY: number = 0;
  @State private isOcrRecognizing: boolean = false;
  @State private isFormulaRecognizing: boolean = false;
  private isSelectionContextOutlineWidthDragging: boolean = false;

  aboutToAppear(): void {
    this.attachExistingViewModelIfAvailable();
    if (this.shouldAutoLoadCurrentSession()) {
      this.resolveViewModel();
      void this.ensurePageSessionLoaded();
    } else {
      this.requestViewportRedraw();
    }
  }

  aboutToDisappear(): void {
    this.clearViewportRedrawTimers();
    this.clearRecentCommittedIdleFlushTimer();
    this.clearSelectionOverlayResumeTimer();
    this.commitInlineTextEdit(true);
    this.releaseBackgroundPixelMap();
  }

  build() {
    Stack() {
      Stack() {
        this.buildPageBackgroundImage()
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

      Canvas(this.backgroundContext2D)
        .width('100%')
        .height('100%')
        .backgroundColor('#00000000')
        .hitTestBehavior(HitTestMode.None)
        .onReady(() => {
          this.isBackgroundLayerReady = true;
          this.redrawBackgroundLayer();
          this.redrawCommittedLayerAfterReadiness();
        })

      ElementLayer({
        pageId: this.pageId,
        refreshVersion: this.getElementLayerRefreshVersion(),
        autoCreateSession: this.shouldAutoLoadCurrentSession(),
        editingElementId: this.getInlineTextEditElementId(),
        renderContent: true,
        renderSelection: false,
        minZIndex: ELEMENT_LAYER_Z_INDEX_MIN,
        maxZIndex: this.getStrokeLayerZIndexForRendering()
      })
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

      Canvas(this.committedContext2D)
        .width('100%')
        .height('100%')
        .backgroundColor('#00000000')
        .onReady(() => {
          this.isCommittedLayerReady = true;
          this.notifyCanvasMetricsChanged();
          this.redrawCommittedLayerAfterReadiness();
        })

      Canvas(this.recentCommittedContext2D)
        .width('100%')
        .height('100%')
        .backgroundColor('#00000000')
        .onReady(() => {
          this.isRecentCommittedLayerReady = true;
          this.notifyCanvasMetricsChanged();
          this.redrawCommittedLayerAfterReadiness();
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
          refreshVersion: this.getElementLayerRefreshVersion(),
          autoCreateSession: this.shouldAutoLoadCurrentSession(),
          editingElementId: this.getInlineTextEditElementId(),
          renderContent: true,
          renderSelection: false,
          minZIndex: this.getStrokeLayerZIndexForRendering(),
          maxZIndex: ELEMENT_LAYER_Z_INDEX_MAX
        })
          .width('100%')
          .height('100%')

        ElementLayer({
          pageId: this.pageId,
          refreshVersion: this.getElementLayerRefreshVersion(),
          autoCreateSession: this.shouldAutoLoadCurrentSession(),
          editingElementId: this.getInlineTextEditElementId(),
          renderContent: false,
          renderSelection: true,
          minZIndex: ELEMENT_LAYER_Z_INDEX_MIN,
          maxZIndex: ELEMENT_LAYER_Z_INDEX_MAX
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
      this.requestViewportRedraw();
    })
  }

  private getStrokeLayerZIndexForRendering(): number {
    const viewModel = this.getViewModel();
    return viewModel === null ? 0 : viewModel.getStrokeLayerZIndex();
  }

  private resolvePageBackgroundImageUri(): string {
    if (typeof this.backgroundImageUri !== 'string') {
      return '';
    }
    const backgroundImageUri = this.backgroundImageUri.trim();
    if (backgroundImageUri.length === 0) {
      return '';
    }
    if (backgroundImageUri.startsWith('file://')) {
      if (backgroundImageUri.startsWith('file:///')) {
        return backgroundImageUri;
      }
      const rawLocalPath: string = backgroundImageUri.substring('file://'.length);
      return rawLocalPath.startsWith('/') ? `file://${rawLocalPath}` : `file:///${rawLocalPath}`;
    }
    if (backgroundImageUri.startsWith('http://') || backgroundImageUri.startsWith('https://')) {
      return backgroundImageUri;
    }
    return `file://${backgroundImageUri}`;
  }

  @Builder
  private buildPageBackgroundImage(): void {
    if (this.resolvePageBackgroundImageUri().length > 0) {
      Image(this.resolvePageBackgroundImageUri())
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Fill)
        .hitTestBehavior(HitTestMode.None)
    }
  }

  private drawPageBackgroundImageOnContext(
    context: CanvasDrawContext,
    pageWidth: number,
    pageHeight: number
  ): boolean {
    const backgroundImageUri: string = this.resolvePageBackgroundImageUri();
    if (backgroundImageUri.length === 0 || pageWidth <= 0 || pageHeight <= 0) {
      this.releaseBackgroundPixelMap();
      return false;
    }

    if ((this.backgroundPixelMapUri !== backgroundImageUri || this.backgroundPixelMap === null) &&
      this.backgroundPixelMapFailedUri !== backgroundImageUri) {
      void this.ensureBackgroundPixelMapLoaded(backgroundImageUri);
    }

    const pixelMap: image.PixelMap | null = this.backgroundPixelMap;
    if (pixelMap !== null && this.backgroundPixelMapUri === backgroundImageUri) {
      try {
        context.drawImage(pixelMap, 0, 0, pageWidth, pageHeight);
        return true;
      } catch (_drawError) {
      }
    }

    return this.drawBackgroundImageBitmapOnContext(context, backgroundImageUri, pageWidth, pageHeight);
  }

  private drawBackgroundImageBitmapOnContext(
    context: CanvasDrawContext,
    backgroundImageUri: string,
    pageWidth: number,
    pageHeight: number
  ): boolean {
    const candidates: string[] = this.buildImageSourceCandidates(backgroundImageUri);
    for (const candidate of candidates) {
      let imageBitmap: ImageBitmap | undefined = undefined;
      try {
        imageBitmap = new ImageBitmap(candidate);
        context.drawImage(imageBitmap, 0, 0, pageWidth, pageHeight);
        return true;
      } catch (_error) {
      } finally {
        if (imageBitmap !== undefined) {
          try {
            imageBitmap.close();
          } catch (_closeError) {
          }
        }
      }
    }

    return false;
  }

  private async ensureBackgroundPixelMapLoaded(uri: string): Promise<void> {
    if (uri.length === 0 || this.backgroundPixelMapLoadingUri === uri) {
      return;
    }

    this.backgroundPixelMapLoadingUri = uri;
    const pixelMap: image.PixelMap | null = await this.createPixelMapFromPath(uri);
    if (this.resolvePageBackgroundImageUri() !== uri) {
      if (pixelMap !== null) {
        this.releasePixelMap(pixelMap);
      }
      if (this.backgroundPixelMapLoadingUri === uri) {
        this.backgroundPixelMapLoadingUri = '';
      }
      return;
    }

    if (pixelMap === null) {
      if (this.backgroundPixelMapLoadingUri === uri) {
        this.backgroundPixelMapLoadingUri = '';
      }
      this.backgroundPixelMapFailedUri = uri;
      return;
    }

    if (this.backgroundPixelMap !== null && this.backgroundPixelMapUri !== uri) {
      this.releasePixelMap(this.backgroundPixelMap);
    }
    this.backgroundPixelMap = pixelMap;
    this.backgroundPixelMapUri = uri;
    this.backgroundPixelMapFailedUri = '';
    if (this.backgroundPixelMapLoadingUri === uri) {
      this.backgroundPixelMapLoadingUri = '';
    }
    this.redrawBackgroundLayer();
    this.redrawCommittedLayer();
    this.redrawOverlayLayer();
  }

  private async createPixelMapFromPath(path: string): Promise<image.PixelMap | null> {
    const candidates: string[] = this.buildImageSourceCandidates(path);
    for (const candidate of candidates) {
      let imageSource: image.ImageSource | undefined = undefined;
      try {
        imageSource = image.createImageSource(candidate);
        return await imageSource.createPixelMap();
      } catch (_error) {
      } finally {
        if (imageSource !== undefined) {
          try {
            await imageSource.release();
          } catch (_releaseError) {
          }
        }
      }
    }
    return null;
  }

  private releaseBackgroundPixelMap(): void {
    if (this.backgroundPixelMap !== null) {
      this.releasePixelMap(this.backgroundPixelMap);
    }
    this.backgroundPixelMap = null;
    this.backgroundPixelMapUri = '';
    this.backgroundPixelMapLoadingUri = '';
    this.backgroundPixelMapFailedUri = '';
  }

  private releasePixelMap(pixelMap: image.PixelMap): void {
    try {
      void pixelMap.release();
    } catch (_releaseError) {
    }
  }

  private buildImageSourceCandidates(path: string): string[] {
    const candidates: string[] = [];
    this.appendImageSourceCandidate(candidates, path);
    const decodedPath: string = this.decodeUriSegment(path);
    if (decodedPath !== path) {
      this.appendImageSourceCandidate(candidates, decodedPath);
    }

    if (path.startsWith('file://')) {
      const rawLocalPath: string = path.substring('file://'.length);
      this.appendImageSourceCandidate(candidates, rawLocalPath);
      if (!rawLocalPath.startsWith('/')) {
        this.appendImageSourceCandidate(candidates, `/${rawLocalPath}`);
      }
      const decodedLocalPath: string = this.decodeUriSegment(rawLocalPath);
      if (decodedLocalPath !== rawLocalPath) {
        this.appendImageSourceCandidate(candidates, decodedLocalPath);
        if (!decodedLocalPath.startsWith('/')) {
          this.appendImageSourceCandidate(candidates, `/${decodedLocalPath}`);
        }
      }
    } else if (!path.startsWith('http://') && !path.startsWith('https://')) {
      this.appendImageSourceCandidate(candidates, `file://${path}`);
    }

    if (decodedPath.startsWith('file://')) {
      const decodedSchemePath: string = decodedPath.substring('file://'.length);
      this.appendImageSourceCandidate(candidates, decodedSchemePath);
      if (!decodedSchemePath.startsWith('/')) {
        this.appendImageSourceCandidate(candidates, `/${decodedSchemePath}`);
      }
    }

    return candidates;
  }

  private appendImageSourceCandidate(candidates: string[], candidate: string): void {
    if (candidate.length === 0) {
      return;
    }
    if (!candidates.includes(candidate)) {
      candidates.push(candidate);
    }
  }

  private decodeUriSegment(text: string): string {
    try {
      return decodeURIComponent(text);
    } catch (_error) {
      return text;
    }
  }

  @Builder
  private buildSelectionContextMenu(): void {
    Column() {
      if (this.elementStylePanelMode === 'fill') {
        this.buildFillStylePanel()
      } else if (this.elementStylePanelMode === 'outline') {
        this.buildOutlineStylePanel()
      } else if (this.elementStylePanelMode === 'layer') {
        this.buildLayerOrderPanel()
      } else if (this.selectionContextMenuTarget === 'strokeGroup') {
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

        Button(this.isOcrRecognizing ? '转换中...' : '转换为文本')
          .width('100%')
          .height(SELECTION_CONTEXT_MENU_ITEM_HEIGHT)
          .fontSize(14)
          .fontColor('#111827')
          .backgroundColor('#00000000')
          .enabled(!this.isOcrRecognizing && !this.isFormulaRecognizing)
          .onClick(() => {
            this.handleSelectionContextMenuAction('ocr');
          })

        Button(this.isFormulaRecognizing ? '识别中...' : '公式识别')
          .width('100%')
          .height(SELECTION_CONTEXT_MENU_ITEM_HEIGHT)
          .fontSize(14)
          .fontColor('#111827')
          .backgroundColor('#00000000')
          .enabled(!this.isOcrRecognizing && !this.isFormulaRecognizing)
          .onClick(() => {
            this.handleSelectionContextMenuAction('formula');
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
      } else {
        if (this.isSelectionContextElementShape()) {
          this.buildSelectionMenuButton('填充', 'fill')
        }
        if (this.isSelectionContextElementOutlineEditable()) {
          this.buildSelectionMenuButton('轮廓', 'outline')
        }
        this.buildSelectionMenuButton('改变图层', 'layer')
        this.buildSelectionMenuButton('删除', 'delete', '#DC2626')
      }
    }
      .width(this.getSelectionContextMenuWidth())
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
  private buildSelectionMenuButton(
    label: string,
    action: SelectionAction,
    color: string = '#111827',
    enabled: boolean = true
  ): void {
    Button(label)
      .width('100%')
      .height(SELECTION_CONTEXT_MENU_ITEM_HEIGHT)
      .fontSize(14)
      .fontColor(color)
      .backgroundColor('#00000000')
      .enabled(enabled)
      .onClick(() => {
        if (!enabled) {
          return;
        }
        this.handleSelectionContextMenuAction(action);
      })
  }

  @Builder
  private buildFillStylePanel(): void {
    Column({ space: 8 }) {
      Text('填充')
        .fontSize(12)
        .fontColor('#475569')
        .width('100%')

      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(ELEMENT_STYLE_PANEL_COLOR_OPTIONS, (color: string) => {
          this.buildFillColorSwatch(color)
        }, (color: string): string => color)
      }
        .width('100%')
    }
      .width('100%')
      .padding(4)
  }

  @Builder
  private buildOutlineStylePanel(): void {
    Column({ space: 10 }) {
      Text('轮廓')
        .fontSize(12)
        .fontColor('#475569')
        .width('100%')

      Row({ space: 4 }) {
        ForEach(ELEMENT_OUTLINE_LINE_STYLE_OPTIONS, (lineStyle: ElementOutlineLineStyle) => {
          Button() {
            this.buildOutlineLineStyleGlyph(lineStyle)
          }
            .layoutWeight(1)
            .height(28)
            .backgroundColor(this.isSelectedOutlineLineStyle(lineStyle) ? '#0F172A' : '#FFFFFF')
            .border({
              width: 1,
              color: '#CBD5E1'
            })
            .borderRadius(8)
            .accessibilityText(this.getOutlineLineStyleLabel(lineStyle))
            .onClick(() => {
              this.updateSelectionContextElementOutline(lineStyle, null, null);
            })
        }, (lineStyle: ElementOutlineLineStyle): string => lineStyle)
      }
        .width('100%')

      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(ELEMENT_OUTLINE_COLOR_OPTIONS, (color: string) => {
          this.buildOutlineColorSwatch(color)
        }, (color: string): string => color)
      }
        .width('100%')

      Column({ space: 6 }) {
        Text(`粗细 ${this.getSelectionContextOutlineWidth()}px`)
          .fontSize(12)
          .fontColor('#475569')
          .width('100%')

        Row({ space: 5 }) {
          ForEach(ELEMENT_OUTLINE_WIDTH_OPTIONS, (width: number) => {
            Button() {
              this.buildOutlineWidthGlyph(width)
            }
              .layoutWeight(1)
              .height(28)
              .backgroundColor(this.getSelectionContextOutlineWidth() === width ? '#0F172A' : '#FFFFFF')
              .border({
                width: 1,
                color: '#CBD5E1'
              })
              .borderRadius(8)
              .onClick(() => {
                this.updateSelectionContextElementOutline(null, null, width);
              })
          }, (width: number): string => `${width}`)
        }
          .width('100%')

        Slider({
          value: this.getSelectionContextOutlineWidth(),
          min: ELEMENT_OUTLINE_WIDTH_MIN,
          max: ELEMENT_OUTLINE_WIDTH_MAX,
          step: ELEMENT_OUTLINE_WIDTH_STEP,
          style: SliderStyle.OutSet
        })
          .showTips(false)
          .onChange((value: number, mode: SliderChangeMode) => {
            this.updateSelectionContextOutlineWidthFromSlider(Math.round(value), mode);
          })
      }
        .width('100%')
    }
      .width('100%')
      .padding(4)
  }

  @Builder
  private buildLayerOrderPanel(): void {
    Column({ space: 4 }) {
      Text('改变图层')
        .fontSize(12)
        .fontColor('#475569')
        .width('100%')

      this.buildLayerOrderButton('上移一层', 'layerUp')
      this.buildLayerOrderButton('下移一层', 'layerDown')
      this.buildLayerOrderButton('置于顶层', 'layerTop')
      this.buildLayerOrderButton('置于底层', 'layerBottom')
    }
      .width('100%')
      .padding(4)
  }

  @Builder
  private buildLayerOrderButton(label: string, action: LayerOrderAction): void {
    Button(label)
      .width('100%')
      .height(SELECTION_CONTEXT_MENU_ITEM_HEIGHT)
      .fontSize(14)
      .fontColor(this.isLayerOrderActionEnabled(action) ? '#111827' : '#94A3B8')
      .backgroundColor('#00000000')
      .enabled(this.isLayerOrderActionEnabled(action))
      .onClick(() => {
        if (!this.isLayerOrderActionEnabled(action)) {
          return;
        }
        this.handleSelectionContextMenuAction(action);
      })
  }

  @Builder
  private buildFillColorSwatch(color: string): void {
    Stack({ alignContent: Alignment.Center }) {
      if (color === '#00FFFFFF') {
        Text('/')
          .fontSize(16)
          .fontColor('#DC2626')
      }
    }
      .width(24)
      .height(24)
      .margin({ right: 6, bottom: 6 })
      .backgroundColor(color === '#00FFFFFF' ? '#FFFFFF' : color)
      .borderRadius(12)
      .border({
        width: this.getSelectionContextFillColor() === color ? 3 : 1,
        color: this.getSelectionContextFillColor() === color ? '#111827' : '#CBD5E1'
      })
      .onClick(() => {
        this.updateSelectionContextElementFill(color);
      })
  }

  @Builder
  private buildOutlineColorSwatch(color: string): void {
    Stack() {}
      .width(24)
      .height(24)
      .margin({ right: 6, bottom: 6 })
      .backgroundColor(color)
      .borderRadius(12)
      .border({
        width: this.getSelectionContextOutlineColor() === color ? 3 : 1,
        color: this.getSelectionContextOutlineColor() === color ? '#111827' : '#CBD5E1'
      })
      .onClick(() => {
        this.updateSelectionContextElementOutline(null, color, null);
      })
  }

  @Builder
  private buildOutlineWidthGlyph(width: number): void {
    Column() {}
      .width(16)
      .height(Math.max(2, Math.min(14, width)))
      .backgroundColor(this.getSelectionContextOutlineWidth() === width ? '#FFFFFF' : '#111827')
      .borderRadius(7)
  }

  @Builder
  private buildOutlineLineStyleGlyph(lineStyle: ElementOutlineLineStyle): void {
    Stack({ alignContent: Alignment.Center }) {
      if (lineStyle === 'none') {
        Column() {}
          .width(22)
          .height(2)
          .backgroundColor(this.getOutlineLineStyleGlyphColor(lineStyle))
          .rotate({ angle: -35 })
      } else if (lineStyle === 'dashed') {
        Row({ space: 3 }) {
          ForEach([0, 1, 2], (dashIndex: number) => {
            Column() {}
              .width(6)
              .height(2)
              .backgroundColor(this.getOutlineLineStyleGlyphColor(lineStyle))
              .borderRadius(1)
          }, (dashIndex: number): string => `${dashIndex}`)
        }
      } else if (lineStyle === 'dotted') {
        Row({ space: 4 }) {
          ForEach([0, 1, 2, 3], (dotIndex: number) => {
            Column() {}
              .width(3)
              .height(3)
              .backgroundColor(this.getOutlineLineStyleGlyphColor(lineStyle))
              .borderRadius(2)
          }, (dotIndex: number): string => `${dotIndex}`)
        }
      } else {
        Column() {}
          .width(24)
          .height(2)
          .backgroundColor(this.getOutlineLineStyleGlyphColor(lineStyle))
          .borderRadius(1)
      }
    }
    .width('100%')
    .height('100%')
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
    this.clearViewportRedrawTimers();
    const viewModel = this.getRenderingViewModel();
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

  private redrawCommittedLayerAfterReadiness(): void {
    if (!this.areCommittedLayersReady()) {
      return;
    }

    this.requestViewportRedraw();
  }

  private onViewportRefreshVersionChanged(): void {
    this.requestViewportRedraw();
  }

  private handleTouch(event: TouchEvent): void {
    if (this.shouldRouteTouchToDocument(event)) {
      this.isForwardingDocumentTouchGesture = true;
      this.onDocumentTouch(event);
      this.cancelActiveCanvasGestures(this.peekViewModel());
      this.updateDocumentTouchForwardingState(event);
      return;
    }

    if (this.isForwardingDocumentTouchGesture) {
      this.onDocumentTouch(event);
      this.cancelActiveCanvasGestures(this.peekViewModel());
      this.updateDocumentTouchForwardingState(event);
      return;
    }

    if (!this.shouldHandleCanvasTouch(event)) {
      this.cancelActiveCanvasGestures(this.peekViewModel());
      return;
    }

    const viewModel = this.getRenderingViewModel();
    if (!viewModel) {
      return;
    }

    this.syncViewModelToolSetting(viewModel);
    const toolSetting = this.getEffectiveToolSetting();
    const activeTool = toolSetting.tool;
    if (this.shouldNotifyPageInteractionStart(event, activeTool)) {
      this.onPageInteractionStart(this.pageId);
    }

    if (!viewModel.isLoadedForPage(this.pageId)) {
      void this.ensurePageSessionLoaded();
      return;
    }

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

    if (event.type === TouchType.Down && this.isStrokeInputTool(activeTool) && !this.shouldAcceptStrokeInput(event)) {
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

          const selectedElement = viewModel.getSelectedElement();
          if (this.shouldBeginInlineTextEdit(point, selectedElement, hitTolerance)) {
            const textElement = selectedElement as TextCanvasElement;
            if (textElement.recognition?.source === 'formula' && (textElement.recognition.latex?.trim().length ?? 0) > 0) {
              this.clearLastEditTap();
            } else {
              this.beginInlineTextEdit(textElement);
              this.syncEditorSnapshot();
              this.onContentChanged(false, 'element');
              return;
            }
          }

          const contextMenuCandidate = viewModel.getElementContextMenuCandidate(point, hitTolerance);
          viewModel.beginElementEditGesture(point, pageBounds, hitTolerance);
          if (contextMenuCandidate !== null) {
            this.showElementContextMenu(contextMenuCandidate);
          }
          this.recordEditTap(point, viewModel.getSelectedElement());
        }

        this.syncEditorSnapshot();
        this.onContentChanged(false, 'element');
        return;
      }

      if (event.type === TouchType.Move) {
        if (point !== null && viewModel.updateElementEditGesture(point, pageBounds)) {
          this.hideSelectionContextMenu();
          this.syncEditorSnapshot();
          this.elementLayerLocalRefreshVersion += 1;
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
        this.elementLayerLocalRefreshVersion += 1;
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
        return;
      }

      viewModel.appendDebugEvent(
        'CanvasBoard',
        `touchDown tool=${toolSetting.tool} color=${toolSetting.color} width=${toolSetting.width} opacity=${toolSetting.opacity.toFixed(2)}`
      );
      if (activeTool === 'eraser') {
        this.stabilizeCommittedLayersForEdit('eraserStart');
      }
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

  private handleLassoTouch(event: TouchEvent, touch: TouchObject, viewModel: DrawingEditorViewModel): void {
    if (event.type === TouchType.Down) {
      this.hideSelectionContextMenu();
      this.stabilizeCommittedLayersForEdit('lassoStart');
      const point = this.buildPoint(touch, false);
      if (point === null) {
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
      if (this.isSelectionMovePending || this.isSelectionMoveGestureActive) {
        this.cancelSelectionMoveGesture(viewModel);
        return;
      }

      this.cancelLassoGesture(viewModel);
      this.shouldClearSelectionOnLassoTap = false;
    }
  }

  private isStrokeInputTool(activeTool: string): boolean {
    return activeTool === 'pen' || activeTool === 'pencil' || activeTool === 'highlighter' || activeTool === 'eraser';
  }

  private shouldAcceptStrokeInput(event: TouchEvent): boolean {
    return this.shouldHandleCanvasTouch(event);
  }

  private shouldNotifyPageInteractionStart(event: TouchEvent, activeTool: string): boolean {
    if (event.type === TouchType.Down) {
      return !this.shouldDeferTouchStrokeActivation(event, activeTool);
    }

    if (event.type === TouchType.Move || event.type === TouchType.Up) {
      return this.shouldDeferTouchStrokeActivation(event, activeTool);
    }

    return false;
  }

  private shouldDeferTouchStrokeActivation(event: TouchEvent, activeTool: string): boolean {
    return this.inputMode === 'touch' &&
      !this.isActivePage &&
      !this.isStylusEvent(event) &&
      this.isStrokeInputTool(activeTool);
  }

  private isStylusEvent(event: TouchEvent): boolean {
    return event.sourceTool === SourceTool.Pen;
  }

  private shouldRouteTouchToDocument(event: TouchEvent): boolean {
    if (this.inputMode === 'stylus') {
      return !this.isStylusEvent(event);
    }

    return !this.isStylusEvent(event) && this.hasMultipleActiveTouches(event);
  }

  private shouldHandleCanvasTouch(event: TouchEvent): boolean {
    if (this.inputMode === 'touch') {
      return !this.isStylusEvent(event) && !this.hasMultipleActiveTouches(event);
    }

    return this.isStylusEvent(event);
  }

  private hasMultipleActiveTouches(event: TouchEvent): boolean {
    return this.getActiveTouches(event).length >= 2;
  }

  private updateDocumentTouchForwardingState(event: TouchEvent): void {
    if (event.type === TouchType.Cancel) {
      this.isForwardingDocumentTouchGesture = false;
      return;
    }

    if (event.type === TouchType.Up && this.getActiveTouches(event).length < 2) {
      this.isForwardingDocumentTouchGesture = false;
    }
  }

  private getActiveTouches(event: TouchEvent): TouchObject[] {
    if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      return event.touches;
    }

    if (event.touches.length > 0) {
      return event.touches;
    }

    return event.changedTouches;
  }

  private cancelActiveCanvasGestures(viewModel: DrawingEditorViewModel | null): void {
    if (viewModel === null) {
      return;
    }

    this.cancelDrawingGesture(viewModel);
    this.cancelLassoGesture(viewModel);
    this.cancelSelectionMoveGesture(viewModel);
    this.cancelActiveStrokeResizeGesture(viewModel);
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
    this.stabilizeCommittedLayersForEdit('selectionMoveStart');
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
    const viewModel = this.getRenderingViewModel();
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
        this.drawStrokeOnViewport(this.recentCommittedContext2D, completedStroke);
        this.scheduleRecentCommittedIdleFlush();
      } else if (this.trimRecentCommittedLayerIntoBase()) {
        this.redrawRecentCommittedLayer(false);
        this.scheduleRecentCommittedIdleFlush();
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

  private redrawBackgroundLayer(
    providedSize: CanvasSize | null = null,
    providedTransform: PageViewportTransform | null = null,
    providedVisibleRegion: PageRenderRegion | null = null
  ): void {
    if (!this.isBackgroundLayerReady) {
      return;
    }

    const size = providedSize ?? this.getCanvasSize(this.backgroundContext2D);
    const transform = providedTransform ?? this.getPageViewportTransform(size);
    const visibleRegion = providedVisibleRegion ?? this.getVisiblePageRegion(transform);
    this.backgroundContext2D.clearRect(0, 0, size.width, size.height);
    if (visibleRegion === null) {
      return;
    }

    this.backgroundContext2D.save();
    this.applyPageTransformAndClip(this.backgroundContext2D, transform);
    const backgroundImageUri: string = this.resolvePageBackgroundImageUri();
    this.drawPageBackgroundImageOnContext(
      this.backgroundContext2D,
      transform.pageWidth,
      transform.pageHeight
    );
    PageTemplateRenderer.drawTemplateBackground(
      this.backgroundContext2D,
      this.templateType,
      transform.pageWidth,
      transform.pageHeight,
      this.paperBackgroundColor,
      visibleRegion,
      backgroundImageUri.length === 0
    );
    this.backgroundContext2D.restore();
  }

  private redrawCommittedLayer(
    useFastRendering: boolean = false,
    preserveRecentSplit: boolean = false,
    useBufferedRendering: boolean = true,
    shouldRebuildRenderCache: boolean = true
  ): void {
    if (!this.areCommittedLayersReady()) {
      return;
    }
    if (!useFastRendering) {
      this.clearViewportRedrawTimers();
    }

    const redrawStartedAt = Date.now();
    const size = this.getCanvasSize(this.committedContext2D);
    const transform = this.getPageViewportTransform(size);
    this.syncElementLayerTransform(transform);
    const visibleRegion = this.getVisiblePageRegion(transform);
    this.redrawBackgroundLayer(size, transform, visibleRegion);

    const viewModel = this.getRenderingViewModel();
    if (viewModel === null && !this.shouldAutoLoadCurrentSession()) {
      EditorPerformanceTrace.record(
        'committed.fullRedraw',
        Date.now() - redrawStartedAt,
        'deferredSession=true preserveLayer=true',
        4
      );
      return;
    }
    const strokes = viewModel ? viewModel.getStrokesForRendering() : [];
    let flattenedStrokeCount = preserveRecentSplit
      ? Math.max(0, Math.min(this.flattenedCommittedStrokeCount, strokes.length))
      : strokes.length;
    if (strokes.length - flattenedStrokeCount > RECENT_COMMITTED_STROKE_LIMIT) {
      flattenedStrokeCount = strokes.length;
    }
    this.flattenedCommittedStrokeCount = flattenedStrokeCount;
    if (shouldRebuildRenderCache || !this.isRenderedStrokeCacheReusable(strokes)) {
      this.rebuildRenderedStrokeCache(strokes);
    }

    if (useBufferedRendering &&
      this.redrawCommittedBaseLayerWithBuffer(size, transform, visibleRegion, strokes, flattenedStrokeCount,
      useFastRendering)) {
      this.redrawRecentCommittedStrokes(strokes, flattenedStrokeCount, visibleRegion, transform, useFastRendering);
    } else {
      this.redrawCommittedLayerDirect(size, transform, visibleRegion, strokes, flattenedStrokeCount, useFastRendering);
    }
    this.markCommittedViewportRendered(!useFastRendering);

    EditorPerformanceTrace.record(
      'committed.fullRedraw',
      Date.now() - redrawStartedAt,
      `fast=${useFastRendering} buffered=${useBufferedRendering} rebuildCache=${shouldRebuildRenderCache} visible=${visibleRegion === null ? 'false' : 'true'} flattened=${flattenedStrokeCount} recent=${Math.max(0, strokes.length - flattenedStrokeCount)} strokes=${strokes.length}`,
      useFastRendering ? 10 : 14
    );
  }

  private redrawOverlayLayer(): void {
    if (!this.isOverlayLayerReady) {
      return;
    }

    this.clearPreviewLayers();
    this.resetActivePreviewSession();

    const viewModel = this.getRenderingViewModel();
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

  private flushRecentCommittedLayerIntoBase(reason: string = 'manual'): boolean {
    this.clearRecentCommittedIdleFlushTimer();
    if (!this.areCommittedLayersReady()) {
      return false;
    }

    if (!this.hasActiveRecentCommittedLayer()) {
      this.clearRecentCommittedLayer();
      this.flattenedCommittedStrokeCount = Math.min(
        this.flattenedCommittedStrokeCount,
        this.renderedStrokeOrder.length
      );
      return true;
    }

    const flushStartedAt = Date.now();
    let flushedStrokeCount = 0;
    const startIndex = Math.max(0, Math.min(this.flattenedCommittedStrokeCount, this.renderedStrokeOrder.length));
    for (let index = startIndex; index < this.renderedStrokeOrder.length; index += 1) {
      const strokeId = this.renderedStrokeOrder[index];
      const stroke = this.renderedStrokesById.get(strokeId);
      if (stroke === undefined) {
        continue;
      }

      this.drawStrokeOnViewport(this.committedContext2D, stroke);
      flushedStrokeCount += 1;
    }

    this.clearRecentCommittedLayer();
    this.flattenedCommittedStrokeCount = this.renderedStrokeOrder.length;
    EditorPerformanceTrace.record(
      'committed.recentFlush',
      Date.now() - flushStartedAt,
      `reason=${reason} strokes=${flushedStrokeCount} flattened=${this.flattenedCommittedStrokeCount}`,
      4
    );
    return true;
  }

  private stabilizeCommittedLayersForEdit(reason: string): void {
    this.clearViewportRedrawTimers();
    if (!this.flushRecentCommittedLayerIntoBase(reason)) {
      this.redrawCommittedLayer(false);
    }
  }

  private scheduleRecentCommittedIdleFlush(): void {
    if (!this.hasActiveRecentCommittedLayer()) {
      return;
    }

    this.clearRecentCommittedIdleFlushTimer();
    this.recentCommittedFlushTimerId = setTimeout(() => {
      this.recentCommittedFlushTimerId = -1;
      if (this.shouldDeferRecentCommittedIdleFlush()) {
        this.scheduleRecentCommittedIdleFlush();
        return;
      }

      this.flushRecentCommittedLayerIntoBase('idle');
    }, RECENT_COMMITTED_IDLE_FLUSH_DELAY_MS);
  }

  private shouldDeferRecentCommittedIdleFlush(): boolean {
    return this.hasActiveCanvasGesture();
  }

  private clearRecentCommittedIdleFlushTimer(): void {
    if (this.recentCommittedFlushTimerId < 0) {
      return;
    }

    clearTimeout(this.recentCommittedFlushTimerId);
    this.recentCommittedFlushTimerId = -1;
  }

  private clearCommittedLayer(): void {
    this.clearRecentCommittedIdleFlushTimer();
    if (!this.isCommittedLayerReady) {
      return;
    }

    const size = this.getCanvasSize(this.committedContext2D);
    this.committedContext2D.clearRect(0, 0, size.width, size.height);
    if (this.isBackgroundLayerReady) {
      const backgroundSize = this.getCanvasSize(this.backgroundContext2D);
      this.backgroundContext2D.clearRect(0, 0, backgroundSize.width, backgroundSize.height);
    }
    this.clearRecentCommittedLayer();
    this.flattenedCommittedStrokeCount = 0;
    this.lastHighQualityViewportRenderKey = '';
  }

  private clearStablePreviewRegion(region: BoundingBox): void {
    this.clearPageRegionFromContext(this.stablePreviewContext2D, region);
  }

  private clearOverlayRegion(region: BoundingBox): void {
    this.clearPageRegionFromContext(this.overlayContext2D, region);
  }

  private syncEditorSnapshot(): void {
    const viewModel = this.getRenderingViewModel();
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
    this.selectionContextMenuElementId = '';
    this.elementStylePanelMode = 'none';
    this.resetLayerActionAvailability();
    const menuHeight = this.getSelectionContextMenuHeight();
    const size = this.getCanvasSize(this.overlayContext2D);
    const transform = this.getPageViewportTransform(size);
    const screenX = transform.offsetX + this.selectionMoveStartPageX * transform.scale;
    const screenY = transform.offsetY + this.selectionMoveStartPageY * transform.scale;
    this.selectionContextMenuX = this.clamp(
      screenX + SELECTION_CONTEXT_MENU_OFFSET,
      4,
      Math.max(4, size.width - this.getSelectionContextMenuWidth() - 4)
    );
    this.selectionContextMenuY = this.clamp(
      screenY - menuHeight - SELECTION_CONTEXT_MENU_OFFSET,
      4,
      Math.max(4, size.height - menuHeight - 4)
    );
    this.isSelectionContextMenuVisible = true;
  }

  private showElementContextMenu(element: CanvasElement): void {
    this.finishSelectionContextOutlineWidthDrag();
    const size = this.getCanvasSize(this.overlayContext2D);
    const transform = this.getPageViewportTransform(size);
    this.selectionContextMenuTarget = 'element';
    this.selectionContextMenuElementId = element.id;
    this.elementStylePanelMode = 'none';
    this.syncSelectionContextElementStyleState(element);
    this.syncLayerActionAvailability();
    const menuHeight = this.getSelectionContextMenuHeight();
    const menuWidth = this.getSelectionContextMenuWidth();
    const screenX = transform.offsetX + (element.x + element.width) * transform.scale;
    const screenY = transform.offsetY + element.y * transform.scale;
    this.selectionContextMenuX = this.clamp(
      screenX + SELECTION_CONTEXT_MENU_OFFSET,
      4,
      Math.max(4, size.width - menuWidth - 4)
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

    this.finishSelectionContextOutlineWidthDrag();
    this.isSelectionContextMenuVisible = false;
    this.elementStylePanelMode = 'none';
    this.selectionContextMenuElementId = '';
    this.selectionContextFillColor = '#00FFFFFF';
    this.selectionContextOutlineLineStyle = 'solid';
    this.selectionContextOutlineColor = '#111827';
    this.selectionContextOutlineWidth = 2;
    this.resetLayerActionAvailability();
  }

  private getSelectionContextMenuHeight(): number {
    if (this.elementStylePanelMode === 'fill') {
      return 96;
    }

    if (this.elementStylePanelMode === 'outline') {
      return 230;
    }

    if (this.elementStylePanelMode === 'layer') {
      return SELECTION_CONTEXT_MENU_ITEM_HEIGHT * 4 + 34;
    }

    if (this.selectionContextMenuTarget === 'strokeGroup') {
      return SELECTION_CONTEXT_MENU_ITEM_HEIGHT * 5 + 8;
    }

    let itemCount = 1;
    if (this.isSelectionContextElementShape()) {
      itemCount += 1;
    }
    if (this.isSelectionContextElementOutlineEditable()) {
      itemCount += 1;
    }
    itemCount += 1;
    return SELECTION_CONTEXT_MENU_ITEM_HEIGHT * itemCount + 8;
  }

  private getSelectionContextMenuWidth(): number {
    return this.elementStylePanelMode === 'none' ? SELECTION_CONTEXT_MENU_WIDTH : ELEMENT_STYLE_PANEL_WIDTH;
  }

  private handleSelectionContextMenuAction(action: SelectionAction): void {
    if (action === 'ocr') {
      void this.handleOcrRecognitionAction();
      return;
    }

    if (action === 'formula') {
      void this.handleFormulaRecognitionAction();
      return;
    }

    const viewModel = this.getViewModel();
    if (viewModel === null) {
      this.hideSelectionContextMenu();
      return;
    }

    const target = this.selectionContextMenuTarget;
    if (target === 'element') {
      this.handleElementContextMenuAction(viewModel, action);
      return;
    }

    this.hideSelectionContextMenu();
    if (action === 'resize' && target === 'strokeGroup') {
      this.beginStrokeResizeMode(viewModel);
      return;
    }

    if (target === 'strokeGroup') {
      this.stabilizeCommittedLayersForEdit(`selectionAction:${action}`);
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

  private handleElementContextMenuAction(viewModel: DrawingEditorViewModel, action: SelectionAction): void {
    if (action === 'fill') {
      if (this.isSelectionContextElementShape()) {
        this.elementStylePanelMode = 'fill';
        this.clampSelectionContextMenuToCanvas();
      }
      return;
    }

    if (action === 'outline') {
      if (this.isSelectionContextElementOutlineEditable()) {
        this.elementStylePanelMode = 'outline';
        this.clampSelectionContextMenuToCanvas();
      }
      return;
    }

    if (action === 'layer') {
      this.syncLayerActionAvailability(viewModel);
      this.elementStylePanelMode = 'layer';
      this.clampSelectionContextMenuToCanvas();
      return;
    }

    const layerOrderAction = this.toLayerOrderAction(action);
    if (layerOrderAction !== null) {
      if (this.selectionContextMenuElementId.length === 0) {
        return;
      }

      const availability = viewModel.getElementLayerActionAvailability(this.selectionContextMenuElementId);
      if (!this.isLayerOrderActionEnabled(layerOrderAction, availability)) {
        this.syncLayerActionAvailability(viewModel);
        return;
      }

      const result = viewModel.changeElementLayerById(this.selectionContextMenuElementId, layerOrderAction);
      this.syncEditorSnapshot();
      this.elementLayerLocalRefreshVersion += 1;
      this.redrawOverlayLayer();
      this.syncLayerActionAvailability(viewModel);
      this.clampSelectionContextMenuToCanvas();
      if (result.changed) {
        this.onContentChanged(true, 'element');
      }
      return;
    }

    if (action !== 'delete' || this.selectionContextMenuElementId.length === 0) {
      this.hideSelectionContextMenu();
      return;
    }

    const result = viewModel.deleteElementById(this.selectionContextMenuElementId);
    this.hideSelectionContextMenu();
    this.syncEditorSnapshot();
    this.redrawOverlayLayer();
    if (result.changed) {
      this.onContentChanged(true, 'element');
    }
  }

  private toLayerOrderAction(action: SelectionAction): LayerOrderAction | null {
    if (action === 'layerUp' || action === 'layerDown' || action === 'layerTop' || action === 'layerBottom') {
      return action;
    }

    return null;
  }

  private isLayerOrderActionEnabled(
    action: LayerOrderAction,
    availability: LayerActionAvailability | null = null
  ): boolean {
    const resolvedAvailability = availability ?? this.getCurrentLayerActionAvailability();
    switch (action) {
      case 'layerUp':
        return resolvedAvailability.canMoveUp;
      case 'layerDown':
        return resolvedAvailability.canMoveDown;
      case 'layerTop':
        return resolvedAvailability.canMoveTop;
      case 'layerBottom':
        return resolvedAvailability.canMoveBottom;
      default:
        return false;
    }
  }

  private getCurrentLayerActionAvailability(): LayerActionAvailability {
    return {
      canMoveUp: this.canLayerMoveUp,
      canMoveDown: this.canLayerMoveDown,
      canMoveTop: this.canLayerMoveTop,
      canMoveBottom: this.canLayerMoveBottom
    };
  }

  private syncLayerActionAvailability(viewModel: DrawingEditorViewModel | null = null): void {
    const resolvedViewModel = viewModel ?? this.getViewModel();
    if (resolvedViewModel === null || this.selectionContextMenuElementId.length === 0) {
      this.resetLayerActionAvailability();
      return;
    }

    const availability: LayerActionAvailability =
      resolvedViewModel.getElementLayerActionAvailability(this.selectionContextMenuElementId);
    this.canLayerMoveUp = availability.canMoveUp;
    this.canLayerMoveDown = availability.canMoveDown;
    this.canLayerMoveTop = availability.canMoveTop;
    this.canLayerMoveBottom = availability.canMoveBottom;
  }

  private resetLayerActionAvailability(): void {
    this.canLayerMoveUp = false;
    this.canLayerMoveDown = false;
    this.canLayerMoveTop = false;
    this.canLayerMoveBottom = false;
  }

  private updateSelectionContextElementFill(color: string): void {
    const viewModel = this.getViewModel();
    if (viewModel === null || this.selectionContextMenuElementId.length === 0) {
      return;
    }

    this.selectionContextFillColor = color;
    const result = viewModel.updateShapeFillColorById(this.selectionContextMenuElementId, color);
    this.syncEditorSnapshot();
    this.redrawOverlayLayer();
    if (result.changed) {
      this.onContentChanged(true, 'element');
    }
  }

  private updateSelectionContextOutlineWidthFromSlider(width: number, mode: SliderChangeMode): void {
    if (mode === SliderChangeMode.Begin) {
      this.beginSelectionContextOutlineWidthDrag();
      this.updateSelectionContextElementOutline(null, null, width, false);
      return;
    }

    if (mode === SliderChangeMode.Moving) {
      if (!this.isSelectionContextOutlineWidthDragging) {
        this.beginSelectionContextOutlineWidthDrag();
      }
      this.updateSelectionContextElementOutline(null, null, width, false);
      return;
    }

    if (mode === SliderChangeMode.End) {
      if (!this.isSelectionContextOutlineWidthDragging) {
        this.updateSelectionContextElementOutline(null, null, width);
        return;
      }
      this.updateSelectionContextElementOutline(null, null, width, false);
      this.finishSelectionContextOutlineWidthDrag();
      return;
    }

    this.finishSelectionContextOutlineWidthDrag();
    this.updateSelectionContextElementOutline(null, null, width);
  }

  private beginSelectionContextOutlineWidthDrag(): void {
    const viewModel = this.getViewModel();
    if (viewModel === null || this.selectionContextMenuElementId.length === 0) {
      this.isSelectionContextOutlineWidthDragging = false;
      return;
    }

    this.isSelectionContextOutlineWidthDragging =
      viewModel.beginElementOutlineEdit(this.selectionContextMenuElementId);
  }

  private finishSelectionContextOutlineWidthDrag(): void {
    if (!this.isSelectionContextOutlineWidthDragging) {
      return;
    }

    this.isSelectionContextOutlineWidthDragging = false;
    const viewModel = this.getViewModel();
    if (viewModel === null || this.selectionContextMenuElementId.length === 0) {
      return;
    }

    const result = viewModel.finishElementOutlineEdit(this.selectionContextMenuElementId);
    this.syncEditorSnapshot();
    this.redrawOverlayLayer();
    if (result.changed) {
      this.onContentChanged(true, 'element');
    }
  }

  private updateSelectionContextElementOutline(
    lineStyle: ElementOutlineLineStyle | null,
    color: string | null,
    width: number | null,
    recordHistory: boolean = true
  ): void {
    const viewModel = this.getViewModel();
    if (viewModel === null || this.selectionContextMenuElementId.length === 0) {
      return;
    }

    const currentElement = this.getSelectionContextElement();
    const nextLineStyle = lineStyle ?? (
      currentElement !== null && currentElement.type !== 'text' && currentElement.outline.lineStyle === 'none' &&
        (color !== null || width !== null) ? 'solid' : null
    );
    this.selectionContextOutlineLineStyle = nextLineStyle ?? this.selectionContextOutlineLineStyle;
    this.selectionContextOutlineColor = color ?? this.selectionContextOutlineColor;
    this.selectionContextOutlineWidth = width ?? this.selectionContextOutlineWidth;
    const result = viewModel.updateElementOutlineById(this.selectionContextMenuElementId, {
      lineStyle: nextLineStyle ?? undefined,
      color: color ?? undefined,
      width: width ?? undefined
    }, recordHistory);
    this.syncEditorSnapshot();
    this.redrawOverlayLayer();
    if (result.changed) {
      if (recordHistory) {
        this.onContentChanged(true, 'element');
      } else {
        this.elementLayerLocalRefreshVersion += 1;
        this.onContentChanged(false, 'element');
      }
    }
  }

  private getElementLayerRefreshVersion(): number {
    return this.elementVersion + this.elementLayerLocalRefreshVersion;
  }

  private getSelectionContextElement(): CanvasElement | null {
    const viewModel = this.getViewModel();
    if (viewModel === null || this.selectionContextMenuElementId.length === 0) {
      return null;
    }

    return viewModel.getElementForRendering(this.selectionContextMenuElementId);
  }

  private isSelectionContextElementShape(): boolean {
    return this.getSelectionContextElement()?.type === 'shape';
  }

  private isSelectionContextElementOutlineEditable(): boolean {
    const element = this.getSelectionContextElement();
    return element !== null && (element.type === 'shape' || element.type === 'image');
  }

  private getSelectionContextFillColor(): string {
    return this.selectionContextFillColor;
  }

  private getSelectionContextOutlineColor(): string {
    return this.selectionContextOutlineColor;
  }

  private getSelectionContextOutlineWidth(): number {
    return Math.max(0, Math.round(this.selectionContextOutlineWidth));
  }

  private isSelectedOutlineLineStyle(lineStyle: ElementOutlineLineStyle): boolean {
    return this.selectionContextOutlineLineStyle === lineStyle;
  }

  private getOutlineLineStyleGlyphColor(lineStyle: ElementOutlineLineStyle): string {
    return this.isSelectedOutlineLineStyle(lineStyle) ? '#FFFFFF' : '#111827';
  }

  private syncSelectionContextElementStyleState(element: CanvasElement): void {
    this.selectionContextFillColor = element.type === 'shape' ? element.fillColor : '#00FFFFFF';
    if (element.type === 'text') {
      this.selectionContextOutlineLineStyle = 'solid';
      this.selectionContextOutlineColor = '#111827';
      this.selectionContextOutlineWidth = 2;
      return;
    }

    this.selectionContextOutlineLineStyle = element.outline.lineStyle;
    this.selectionContextOutlineColor = element.outline.color;
    this.selectionContextOutlineWidth = element.outline.width;
  }

  private getOutlineLineStyleLabel(lineStyle: ElementOutlineLineStyle): string {
    switch (lineStyle) {
      case 'none':
        return '无';
      case 'dashed':
        return '虚线';
      case 'dotted':
        return '点线';
      case 'solid':
      default:
        return '实线';
    }
  }

  private clampSelectionContextMenuToCanvas(): void {
    const size = this.getCanvasSize(this.overlayContext2D);
    this.selectionContextMenuX = this.clamp(
      this.selectionContextMenuX,
      4,
      Math.max(4, size.width - this.getSelectionContextMenuWidth() - 4)
    );
    this.selectionContextMenuY = this.clamp(
      this.selectionContextMenuY,
      4,
      Math.max(4, size.height - this.getSelectionContextMenuHeight() - 4)
    );
  }

  private async handleOcrRecognitionAction(): Promise<void> {
    const viewModel = this.getViewModel();
    if (viewModel === null) {
      this.hideSelectionContextMenu();
      return;
    }

    if (this.isOcrRecognizing || this.isFormulaRecognizing) {
      return;
    }

    this.hideSelectionContextMenu();
    this.isOcrRecognizing = true;
    try {
      viewModel.appendDebugEvent('ocrRecognition', 'start');
      this.editorSnapshot = viewModel.getDebugSnapshot();
      const exportPayload = await this.exportRecognitionSelectionImage(viewModel, 'ocr');
      if (exportPayload === null) {
        throw new Error('No selectable lasso content was available for OCR recognition.');
      }
      viewModel.appendDebugEvent('ocrRecognition', `exported base64Length=${exportPayload.base64Image.length}`);
      viewModel.appendDebugEvent(
        'ocrRecognition',
        `exportMeta size=${exportPayload.width}x${exportPayload.height} content=${exportPayload.contentWidth}x${exportPayload.contentHeight} scale=${exportPayload.scale} strokes=${exportPayload.strokeCount} elements=${exportPayload.elementCount}`
      );
      this.editorSnapshot = viewModel.getDebugSnapshot();
      await this.persistRecognitionUploadImageForDebug(viewModel, 'ocr', exportPayload);

      const ocrService = new XfyunOcrService(XFYUN_OCR_CONFIG);
      const ocrResult = await ocrService.recognize(exportPayload.base64Image);
      viewModel.appendDebugEvent('ocrRecognition', `requestSuccess sid=${ocrResult.sid} textLength=${ocrResult.text.length}`);
      this.editorSnapshot = viewModel.getDebugSnapshot();
      const insertedElement = viewModel.insertRecognizedTextElement(
        ocrResult.text,
        exportPayload.frame,
        {
          width: this.pageWidth,
          height: this.pageHeight
        },
        {
          recognition: {
            source: 'ocr',
            sid: ocrResult.sid,
            recognizedAt: Date.now(),
            rawText: ocrResult.text
          }
        }
      );
      if (insertedElement === null) {
        throw new Error(viewModel.getErrorMessage() || 'Failed to insert OCR recognition result.');
      }

      this.syncEditorSnapshot();
      if (!this.tryApplyLatestRenderInvalidation()) {
        this.redrawCommittedLayer(false);
      }
      this.redrawOverlayLayer();
      this.onContentChanged(true, 'element');
    } catch (error) {
      viewModel.appendDebugEvent('ocrRecognition', `failed error=${this.stringifyError(error)}`);
      this.editorSnapshot = viewModel.getDebugSnapshot();
      this.updateSnapshotErrorMessage(this.stringifyError(error));
      this.redrawOverlayLayer();
    } finally {
      this.isOcrRecognizing = false;
    }
  }

  private async handleFormulaRecognitionAction(): Promise<void> {
    const viewModel = this.getViewModel();
    if (viewModel === null) {
      this.hideSelectionContextMenu();
      return;
    }

    if (this.isOcrRecognizing || this.isFormulaRecognizing) {
      return;
    }

    this.hideSelectionContextMenu();
    this.isFormulaRecognizing = true;
    try {
      viewModel.appendDebugEvent('formulaRecognition', 'start');
      this.editorSnapshot = viewModel.getDebugSnapshot();
      const exportPayload = await this.exportRecognitionSelectionImage(viewModel, 'formula');
      if (exportPayload === null) {
        throw new Error('No selectable lasso content was available for formula recognition.');
      }
      viewModel.appendDebugEvent('formulaRecognition', `exported base64Length=${exportPayload.base64Image.length}`);
      viewModel.appendDebugEvent(
        'formulaRecognition',
        `exportMeta size=${exportPayload.width}x${exportPayload.height} content=${exportPayload.contentWidth}x${exportPayload.contentHeight} scale=${exportPayload.scale} strokes=${exportPayload.strokeCount} elements=${exportPayload.elementCount}`
      );
      this.editorSnapshot = viewModel.getDebugSnapshot();
      await this.persistRecognitionUploadImageForDebug(viewModel, 'formula', exportPayload);

      const formulaService = new XfyunFormulaService(XFYUN_FORMULA_CONFIG);
      const formulaResult = await formulaService.recognize(exportPayload.base64Image);
      viewModel.appendDebugEvent(
        'formulaRecognition',
        `requestSuccess sid=${formulaResult.sid} textLength=${formulaResult.text.length} latexLength=${formulaResult.latex.length}`
      );
      this.editorSnapshot = viewModel.getDebugSnapshot();
      const insertedElement = viewModel.insertRecognizedTextElement(
        formulaResult.latex.length > 0 ? formulaResult.latex : formulaResult.text,
        exportPayload.frame,
        {
          width: this.pageWidth,
          height: this.pageHeight
        },
        {
          recognition: {
            source: 'formula',
            sid: formulaResult.sid,
            recognizedAt: Date.now(),
            rawText: formulaResult.text,
            latex: formulaResult.latex.length > 0 ? formulaResult.latex : undefined
          }
        }
      );
      if (insertedElement === null) {
        throw new Error(viewModel.getErrorMessage() || 'Failed to insert formula recognition result.');
      }

      this.syncEditorSnapshot();
      if (!this.tryApplyLatestRenderInvalidation()) {
        this.redrawCommittedLayer(false);
      }
      this.redrawOverlayLayer();
      this.onContentChanged(true, 'element');
    } catch (error) {
      if (viewModel !== null) {
        viewModel.appendDebugEvent('formulaRecognition', `failed error=${this.stringifyError(error)}`);
        this.editorSnapshot = viewModel.getDebugSnapshot();
      }
      this.updateSnapshotErrorMessage(this.stringifyError(error));
      this.redrawOverlayLayer();
    } finally {
      this.isFormulaRecognizing = false;
    }
  }

  private beginStrokeResizeMode(viewModel: DrawingEditorViewModel): void {
    this.stabilizeCommittedLayersForEdit('strokeResizeMode');
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
    return this.isLassoGestureActive || this.isSelectionMovePending || this.isSelectionMoveGestureActive;
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

    const viewModel = this.getRenderingViewModel();
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
      backgroundColor: element.backgroundColor,
      recognition: element.recognition ? {
        source: element.recognition.source,
        sid: element.recognition.sid,
        recognizedAt: element.recognition.recognizedAt,
        rawText: element.recognition.rawText,
        latex: element.recognition.latex
      } : undefined
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
    this.redrawCommittedRegion(pageRegion, transform, visibleBounds);

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
    const pageWidth = this.getPageWidth();
    const pageHeight = this.getPageHeight();
    const scale = this.getViewportTotalScale(size);
    return {
      pageWidth,
      pageHeight,
      viewportWidth: size.width,
      viewportHeight: size.height,
      scale,
      offsetX: (size.width - pageWidth * scale) / 2,
      offsetY: (size.height - pageHeight * scale) / 2
    };
  }

  private resetViewportTransform(): void {
    this.hiddenStrokeIdsDuringSelectionMove.clear();
    this.isDrawingGestureActive = false;
    this.isForwardingDocumentTouchGesture = false;
    this.isLassoGestureActive = false;
    this.shouldClearSelectionOnLassoTap = false;
    this.isSelectionMovePending = false;
    this.pendingSelectionHitResult = null;
    this.isSelectionMoveGestureActive = false;
    this.strokeResizeUiMode = 'none';
    this.strokeResizeBounds = null;
  }

  private getViewportTotalScale(size: CanvasSize): number {
    return this.getFitScale(size, this.getPageWidth(), this.getPageHeight());
  }

  private getFitScale(size: CanvasSize, pageWidth: number, pageHeight: number): number {
    return Math.max(0.01, Math.min(
      Math.max(1, size.width) / pageWidth,
      Math.max(1, size.height) / pageHeight
    ));
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

  private redrawViewportLayers(useFastRendering: boolean = false, useBufferedRendering: boolean = true): void {
    this.redrawCommittedLayer(useFastRendering, false, useBufferedRendering, false);
    this.redrawOverlayLayer();
  }

  private requestViewportRedraw(): void {
    this.clearViewportRedrawTimers();
    const fastDelay = this.getViewportFastRedrawDelay();
    this.viewportFastRedrawTimerId = setTimeout(() => {
      this.viewportFastRedrawTimerId = -1;
      if (this.buildViewportRenderKey() === this.lastHighQualityViewportRenderKey) {
        return;
      }
      this.redrawViewportLayers(true, false);
    }, fastDelay);
    if (!this.shouldScheduleViewportQualityRedraw()) {
      return;
    }
    this.scheduleViewportQualityRedraw(Math.max(fastDelay + 1, this.getViewportQualityRedrawDelay()));
  }

  private shouldScheduleViewportQualityRedraw(): boolean {
    const viewModel = this.getRenderingViewModel();
    if (viewModel === null) {
      return false;
    }

    return viewModel.getStrokesForRendering().length <= VIEWPORT_QUALITY_REDRAW_STROKE_LIMIT;
  }

  private scheduleViewportQualityRedraw(delayMs: number): void {
    this.clearViewportQualityRedrawTimer();
    this.viewportQualityRedrawTimerId = setTimeout(() => {
      this.viewportQualityRedrawTimerId = -1;
      this.redrawViewportLayersWhenIdle();
    }, delayMs);
  }

  private redrawViewportLayersWhenIdle(): void {
    if (this.shouldDeferViewportQualityRedraw()) {
      this.scheduleViewportQualityRedraw(VIEWPORT_QUALITY_REDRAW_RETRY_DELAY_MS);
      return;
    }

    if (this.buildViewportRenderKey() === this.lastHighQualityViewportRenderKey) {
      return;
    }

    this.redrawViewportLayers(false, false);
  }

  private shouldDeferViewportQualityRedraw(): boolean {
    return this.hasActiveCanvasGesture();
  }

  private hasActiveCanvasGesture(): boolean {
    return this.isDrawingGestureActive ||
      this.isForwardingDocumentTouchGesture ||
      this.isLassoGestureActive ||
      this.isSelectionMovePending ||
      this.isSelectionMoveGestureActive ||
      this.isStrokeResizeDragging();
  }

  private clearViewportRedrawTimers(): void {
    this.clearViewportFastRedrawTimer();
    this.clearViewportQualityRedrawTimer();
  }

  private clearViewportFastRedrawTimer(): void {
    if (this.viewportFastRedrawTimerId < 0) {
      return;
    }

    clearTimeout(this.viewportFastRedrawTimerId);
    this.viewportFastRedrawTimerId = -1;
  }

  private clearViewportQualityRedrawTimer(): void {
    if (this.viewportQualityRedrawTimerId < 0) {
      return;
    }

    clearTimeout(this.viewportQualityRedrawTimerId);
    this.viewportQualityRedrawTimerId = -1;
  }

  private getViewportFastRedrawDelay(): number {
    if (this.isActivePage) {
      return 0;
    }

    return VIEWPORT_INACTIVE_FAST_REDRAW_BASE_DELAY_MS +
      this.getPageScopedDelay(VIEWPORT_INACTIVE_FAST_REDRAW_STAGGER_MS);
  }

  private getViewportQualityRedrawDelay(): number {
    if (this.isActivePage) {
      return VIEWPORT_ACTIVE_QUALITY_REDRAW_DELAY_MS;
    }

    return VIEWPORT_INACTIVE_QUALITY_REDRAW_BASE_DELAY_MS +
      this.getPageScopedDelay(VIEWPORT_INACTIVE_QUALITY_REDRAW_STAGGER_MS);
  }

  private getPageScopedDelay(maxDelayMs: number): number {
    const normalizedMaxDelay = Math.max(1, Math.round(maxDelayMs));
    let hash = 0;
    for (let index = 0; index < this.pageId.length; index += 1) {
      hash = (hash * 31 + this.pageId.charCodeAt(index)) % normalizedMaxDelay;
    }

    return hash;
  }

  private markCommittedViewportRendered(isHighQuality: boolean): void {
    if (isHighQuality) {
      this.lastHighQualityViewportRenderKey = this.buildViewportRenderKey();
    }
  }

  private buildViewportRenderKey(): string {
    const size = this.getCanvasSize(this.committedContext2D);
    const transform = this.getPageViewportTransform(size);
    const lastStrokeId = this.renderedStrokeOrder.length === 0
      ? ''
      : this.renderedStrokeOrder[this.renderedStrokeOrder.length - 1];
    return [
      this.pageId,
      `${this.canvasVersion}`,
      `${this.lastAppliedRenderInvalidationSequence}`,
      `${this.renderedStrokeOrder.length}`,
      lastStrokeId,
      `${this.flattenedCommittedStrokeCount}`,
      `${this.templateType}`,
      this.paperBackgroundColor,
      this.resolvePageBackgroundImageUri(),
      this.backgroundPixelMapUri,
      this.backgroundPixelMapLoadingUri,
      this.backgroundPixelMapFailedUri,
      `${Math.round(transform.pageWidth * 100)}`,
      `${Math.round(transform.pageHeight * 100)}`,
      `${Math.round(transform.viewportWidth)}`,
      `${Math.round(transform.viewportHeight)}`,
      `${Math.round(transform.scale * 10000)}`,
      `${Math.round(transform.offsetX * 100)}`,
      `${Math.round(transform.offsetY * 100)}`
    ].join('|');
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
    const viewModel = this.getRenderingViewModel();
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

    const viewModel = this.getRenderingViewModel();
    if (!viewModel) {
      return false;
    }

    const invalidation = viewModel.getRenderInvalidation();
    if (invalidation === null) {
      return this.isRenderedStrokeCacheReusable(viewModel.getStrokesForRendering());
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
    const shouldKeepStableCommittedLayer = this.shouldStabilizeBeforeRenderInvalidation(invalidation);
    if (shouldKeepStableCommittedLayer && !this.flushRecentCommittedLayerIntoBase(`invalidation:${invalidation.reason}`)) {
      return false;
    }

    const previousRecentStrokeIds = this.getRecentCommittedStrokeIdSet();
    this.applyRenderedStrokeMutation(invalidation);
    if (shouldKeepStableCommittedLayer) {
      this.clearRecentCommittedLayer();
      this.flattenedCommittedStrokeCount = this.renderedStrokeOrder.length;
    }

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
        this.redrawCommittedRegion(mergedDirtyRegion, transform, visibleBounds);

        EditorPerformanceTrace.record(
          'committed.partialRedraw',
          Date.now() - redrawStartedAt,
          `reason=${invalidation.reason} dirtyRects=${dirtyRects.length} tiles=0 mode=region removed=${invalidation.removedStrokeIds.length} added=${invalidation.addedRecords.length}`,
          8
        );
        return true;
      }
    }

    const tileBoundsList = this.buildCommittedTileBoundsForDirtyRects(dirtyRects);
    for (const tileBounds of tileBoundsList) {
      this.redrawCommittedTile(tileBounds, transform, visibleBounds);
    }

    EditorPerformanceTrace.record(
      'committed.partialRedraw',
      Date.now() - redrawStartedAt,
      `reason=${invalidation.reason} dirtyRects=${dirtyRects.length} tiles=${tileBoundsList.length} removed=${invalidation.removedStrokeIds.length} added=${invalidation.addedRecords.length}`,
      8
    );

    return true;
  }

  private shouldStabilizeBeforeRenderInvalidation(invalidation: RenderInvalidation): boolean {
    switch (invalidation.reason) {
      case 'delete':
      case 'copy':
      case 'undo':
      case 'redo':
      case 'clear':
      case 'move':
      case 'resize':
      case 'erase':
        return true;
      default:
        return false;
    }
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

  private isRenderedStrokeCacheReusable(strokes: Stroke[]): boolean {
    if (this.renderedStrokeOrder.length !== strokes.length) {
      return false;
    }

    for (let index = 0; index < strokes.length; index += 1) {
      if (this.renderedStrokeOrder[index] !== strokes[index].id) {
        return false;
      }
    }

    return true;
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
    const viewModel = this.getRenderingViewModel();
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

      this.drawStrokeOnViewport(this.committedContext2D, stroke);
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
    const viewportRegion = this.toPixelAlignedViewportRegion(redrawRegion, transform);
    if (viewportRegion === null) {
      return true;
    }

    const width = viewportRegion.maxX - viewportRegion.minX;
    const height = viewportRegion.maxY - viewportRegion.minY;
    if (width <= 0 || height <= 0) {
      return true;
    }

    this.recentCommittedContext2D.clearRect(
      viewportRegion.minX,
      viewportRegion.minY,
      width,
      height
    );
    if (!this.hasActiveRecentCommittedLayer()) {
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
    const normalizedStartIndex = Math.max(0, startIndex);
    const normalizedEndIndex = Math.min(strokes.length, endIndex);
    if (normalizedStartIndex >= normalizedEndIndex) {
      return;
    }

    if (normalizedStartIndex === 0 &&
      normalizedEndIndex === strokes.length &&
      this.renderedStrokeOrder.length === strokes.length) {
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

    for (let index = normalizedStartIndex; index < normalizedEndIndex; index += 1) {
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

  private async exportRecognitionSelectionImage(
    viewModel: DrawingEditorViewModel,
    mode: RecognitionExportMode
  ): Promise<RecognitionSelectionImagePayload | null> {
    const selectionBounds = viewModel.getSelectionBoundingBox();
    if (selectionBounds === null) {
      return null;
    }

    const selectedStrokeIds = new Set<string>();
    for (const target of viewModel.getSelectedStrokeTargets()) {
      for (const strokeId of target.strokeIds) {
        selectedStrokeIds.add(strokeId);
      }
    }

    const selectedElementIds = new Set<string>(viewModel.getSelectedElementIds());
    const strokes = viewModel.getStrokesForRendering().filter((stroke: Stroke): boolean => selectedStrokeIds.has(stroke.id));
    const elements = viewModel.getElementsForRendering().filter((element: CanvasElement): boolean => selectedElementIds.has(element.id));
    if (strokes.length === 0 && elements.length === 0) {
      return null;
    }

    const contentBounds = this.resolveRecognitionContentBounds(selectionBounds, strokes, elements);
    const padding = mode === 'ocr' ? OCR_EXPORT_PADDING : FORMULA_EXPORT_PADDING;
    const scale = mode === 'ocr' ? OCR_EXPORT_SCALE : FORMULA_EXPORT_SCALE;
    const minOutputEdge = mode === 'ocr' ? OCR_EXPORT_MIN_EDGE : FORMULA_EXPORT_MIN_EDGE;
    const minLogicalEdge = Math.max(1, Math.ceil(minOutputEdge / scale));
    const paddedBounds = clampBoundingBox(
      {
        minX: contentBounds.minX - padding,
        minY: contentBounds.minY - padding,
        maxX: contentBounds.maxX + padding,
        maxY: contentBounds.maxY + padding
      },
      this.pageWidth,
      this.pageHeight
    );
    if (paddedBounds === null) {
      return null;
    }

    const logicalContentWidth = Math.max(1, Math.ceil(contentBounds.maxX - contentBounds.minX));
    const logicalContentHeight = Math.max(1, Math.ceil(contentBounds.maxY - contentBounds.minY));
    const logicalWidth = Math.max(minLogicalEdge, Math.ceil(paddedBounds.maxX - paddedBounds.minX));
    const logicalHeight = Math.max(minLogicalEdge, Math.ceil(paddedBounds.maxY - paddedBounds.minY));
    const width = Math.max(1, Math.ceil(logicalWidth * scale));
    const height = Math.max(1, Math.ceil(logicalHeight * scale));
    const contentOffsetX = Math.max(0, (logicalWidth - (paddedBounds.maxX - paddedBounds.minX)) / 2);
    const contentOffsetY = Math.max(0, (logicalHeight - (paddedBounds.maxY - paddedBounds.minY)) / 2);

    try {
      const offscreenCanvas = new OffscreenCanvas(width, height);
      const offscreenContext = offscreenCanvas.getContext('2d', this.committedRenderingSettings);
      offscreenContext.clearRect(0, 0, width, height);
      offscreenContext.fillStyle = '#FFFFFF';
      offscreenContext.globalAlpha = 1;
      offscreenContext.fillRect(0, 0, width, height);
      offscreenContext.save();
      offscreenContext.scale(scale, scale);
      offscreenContext.translate(contentOffsetX - paddedBounds.minX, contentOffsetY - paddedBounds.minY);
      const strokeLayerZIndex = viewModel.getStrokeLayerZIndex();
      CanvasElementRenderer.drawElements(
        offscreenContext,
        elements.filter((element: CanvasElement): boolean => element.zIndex < strokeLayerZIndex)
      );
      if (mode === 'ocr') {
        this.drawOcrRecognitionStrokes(offscreenContext, strokes);
      } else {
        this.drawFormulaRecognitionStrokes(offscreenContext, strokes);
      }
      CanvasElementRenderer.drawElements(
        offscreenContext,
        elements.filter((element: CanvasElement): boolean => element.zIndex >= strokeLayerZIndex)
      );
      offscreenContext.restore();

      const encodedPng = await this.encodeOffscreenCanvasAsPng(offscreenContext, width, height);

      const frameBounds: SelectionBoundsFrame = {
        width: this.pageWidth,
        height: this.pageHeight
      };
      const clampedFrame = clampElementFrameToBounds({
        x: paddedBounds.minX,
        y: paddedBounds.minY,
        width: paddedBounds.maxX - paddedBounds.minX,
        height: paddedBounds.maxY - paddedBounds.minY
      }, frameBounds);
      const recognitionFrame: RecognitionInsertFrame = {
        x: clampedFrame.x,
        y: clampedFrame.y,
        width: clampedFrame.width,
        height: clampedFrame.height
      };
      const payload: RecognitionSelectionImagePayload = {
        base64Image: encodedPng.base64Image,
        pngBytes: encodedPng.bytes,
        frame: recognitionFrame,
        width,
        height,
        contentWidth: logicalContentWidth,
        contentHeight: logicalContentHeight,
        scale,
        strokeCount: strokes.length,
        elementCount: elements.length
      };
      return payload;
    } catch (error) {
      throw new Error(`Selection image export failed: ${this.stringifyError(error)}`);
    }
  }

  private resolveRecognitionContentBounds(
    selectionBounds: BoundingBox,
    strokes: Stroke[],
    elements: CanvasElement[]
  ): BoundingBox {
    const boundsList: BoundingBox[] = [];
    for (const stroke of strokes) {
      const strokeBounds = getStrokeRenderBoundingBox(stroke);
      if (strokeBounds !== null) {
        boundsList.push(strokeBounds);
      }
    }

    for (const element of elements) {
      boundsList.push({
        minX: element.x,
        minY: element.y,
        maxX: element.x + element.width,
        maxY: element.y + element.height
      });
    }

    return this.mergeBoundingBoxes(boundsList) ?? selectionBounds;
  }

  private drawOcrRecognitionStrokes(context: CanvasDrawContext, strokes: Stroke[]): void {
    for (const stroke of strokes) {
      this.drawHighContrastRecognitionStroke(
        context,
        stroke,
        OCR_EXPORT_MIN_STROKE_WIDTH,
        OCR_EXPORT_STROKE_WIDTH_FACTOR
      );
    }
  }

  private drawFormulaRecognitionStrokes(context: CanvasDrawContext, strokes: Stroke[]): void {
    for (const stroke of strokes) {
      this.drawHighContrastRecognitionStroke(
        context,
        stroke,
        FORMULA_EXPORT_MIN_STROKE_WIDTH,
        FORMULA_EXPORT_STROKE_WIDTH_FACTOR
      );
    }
  }

  private drawHighContrastRecognitionStroke(
    context: CanvasDrawContext,
    stroke: Stroke,
    minimumStrokeWidth: number,
    strokeWidthFactor: number
  ): void {
    if (stroke.points.length === 0) {
      return;
    }

    const points = stroke.points;
    context.save();
    try {
      context.strokeStyle = '#000000';
      context.fillStyle = '#000000';
      context.globalAlpha = 1;
      context.lineCap = 'round';
      context.lineJoin = 'round';
      context.lineWidth = Math.max(minimumStrokeWidth, stroke.style.width * strokeWidthFactor);

      const firstPoint = points[0];
      if (points.length === 1) {
        context.beginPath();
        context.arc(firstPoint.x, firstPoint.y, context.lineWidth / 2, 0, Math.PI * 2);
        context.fill();
        return;
      }

      context.beginPath();
      context.moveTo(firstPoint.x, firstPoint.y);
      if (points.length === 2) {
        const lastPoint = points[1];
        context.lineTo(lastPoint.x, lastPoint.y);
      } else {
        for (let index = 1; index < points.length - 1; index += 1) {
          const currentPoint = points[index];
          const nextPoint = points[index + 1];
          const midpointX = (currentPoint.x + nextPoint.x) / 2;
          const midpointY = (currentPoint.y + nextPoint.y) / 2;
          context.quadraticCurveTo(currentPoint.x, currentPoint.y, midpointX, midpointY);
        }

        const tailPoint = points[points.length - 1];
        context.lineTo(tailPoint.x, tailPoint.y);
      }
      context.stroke();
    } finally {
      context.restore();
    }
  }

  private async persistRecognitionUploadImageForDebug(
    viewModel: DrawingEditorViewModel,
    mode: RecognitionExportMode,
    payload: RecognitionSelectionImagePayload
  ): Promise<void> {
    const debugSource = mode === 'ocr' ? 'ocrRecognition' : 'formulaRecognition';
    try {
      const title = await this.saveRecognitionUploadImageToGallery(mode, payload);
      viewModel.appendDebugEvent(debugSource, `savedUploadImage title=${title}.png`);
    } catch (error) {
      viewModel.appendDebugEvent(debugSource, `saveUploadImageFailed error=${this.stringifyError(error)}`);
    }
    this.editorSnapshot = viewModel.getDebugSnapshot();
  }

  private async saveRecognitionUploadImageToGallery(
    mode: RecognitionExportMode,
    payload: RecognitionSelectionImagePayload
  ): Promise<string> {
    const hostContext: common.Context | undefined = this.getUIContext().getHostContext() as common.Context | undefined;
    if (hostContext === undefined) {
      throw new Error('Host context is unavailable.');
    }

    await this.ensureRecognitionGalleryWritePermission(hostContext);
    const title = this.buildRecognitionUploadImageTitle(mode, payload);
    const photoHelper = photoAccessHelper.getPhotoAccessHelper(hostContext);
    try {
      const request = photoAccessHelper.MediaAssetChangeRequest.createAssetRequest(
        hostContext,
        photoAccessHelper.PhotoType.IMAGE,
        'png',
        { title }
      );
      request.addResource(photoAccessHelper.ResourceType.IMAGE_RESOURCE, this.copyBytesToArrayBuffer(payload.pngBytes));
      await photoHelper.applyChanges(request);
      return title;
    } finally {
      try {
        await photoHelper.release();
      } catch (_releaseError) {
      }
    }
  }

  private async ensureRecognitionGalleryWritePermission(hostContext: common.Context): Promise<void> {
    if (this.hasRecognitionGalleryWritePermission) {
      return;
    }

    const permissions: Array<Permissions> = ['ohos.permission.WRITE_IMAGEVIDEO'];
    const atManager = abilityAccessCtrl.createAtManager();
    const result = await atManager.requestPermissionsFromUser(hostContext, permissions);
    for (const authResult of result.authResults) {
      if (authResult !== 0) {
        throw new Error(`Gallery write permission denied authResults=${result.authResults.join(',')}`);
      }
    }
    this.hasRecognitionGalleryWritePermission = true;
  }

  private buildRecognitionUploadImageTitle(
    mode: RecognitionExportMode,
    payload: RecognitionSelectionImagePayload
  ): string {
    return `hosn_${mode}_upload_${Date.now()}_${payload.width}x${payload.height}`;
  }

  private copyBytesToArrayBuffer(bytes: Uint8Array): ArrayBuffer {
    const buffer = new ArrayBuffer(bytes.length);
    const target = new Uint8Array(buffer);
    for (let index = 0; index < bytes.length; index += 1) {
      target[index] = bytes[index];
    }
    return buffer;
  }

  private async encodeOffscreenCanvasAsPng(
    context: OffscreenCanvasRenderingContext2D,
    width: number,
    height: number
  ): Promise<RecognitionEncodedPng> {
    let pixelMap: image.PixelMap | null = null;
    const packer: image.ImagePacker = image.createImagePacker();
    try {
      pixelMap = context.getPixelMap(0, 0, width, height);
      const packingOption: image.PackingOption = {
        format: 'image/png',
        quality: 100
      };
      const packedData = await packer.packing(pixelMap, packingOption);
      const bytes = new Uint8Array(packedData);
      return {
        base64Image: this.encodeBase64Bytes(bytes),
        bytes
      };
    } finally {
      if (pixelMap !== null) {
        try {
          await pixelMap.release();
        } catch (_releasePixelMapError) {
        }
      }

      try {
        await packer.release();
      } catch (_releasePackerError) {
      }
    }
  }

  private encodeBase64Bytes(bytes: Uint8Array): string {
    const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
    let output = '';
    for (let index = 0; index < bytes.length; index += 3) {
      const byte1 = bytes[index];
      const byte2 = index + 1 < bytes.length ? bytes[index + 1] : 0;
      const byte3 = index + 2 < bytes.length ? bytes[index + 2] : 0;
      const triplet = (byte1 << 16) | (byte2 << 8) | byte3;
      output += this.getBase64Char(alphabet, (triplet >>> 18) & 0x3f);
      output += this.getBase64Char(alphabet, (triplet >>> 12) & 0x3f);
      output += index + 1 < bytes.length ? this.getBase64Char(alphabet, (triplet >>> 6) & 0x3f) : '=';
      output += index + 2 < bytes.length ? this.getBase64Char(alphabet, triplet & 0x3f) : '=';
    }
    return output;
  }

  private getBase64Char(alphabet: string, index: number): string {
    return alphabet.substring(index, index + 1);
  }

  private stringifyError(error: Object): string {
    if (error instanceof Error) {
      return error.message.length > 0 ? error.message : error.name;
    }

    if (typeof error === 'string') {
      return error;
    }

    try {
      return JSON.stringify(error);
    } catch (_stringifyError) {
      return 'Unknown error';
    }
  }

  private updateSnapshotErrorMessage(message: string): void {
    this.editorSnapshot = {
      instanceId: this.editorSnapshot.instanceId,
      pageId: this.editorSnapshot.pageId,
      toolSetting: this.editorSnapshot.toolSetting,
      strokeCount: this.editorSnapshot.strokeCount,
      elementCount: this.editorSnapshot.elementCount,
      selectedElementId: this.editorSnapshot.selectedElementId,
      activeStrokeStyle: this.editorSnapshot.activeStrokeStyle,
      undoDepth: this.editorSnapshot.undoDepth,
      redoDepth: this.editorSnapshot.redoDepth,
      recentEvents: this.editorSnapshot.recentEvents,
      errorMessage: message,
      persistenceStatus: this.editorSnapshot.persistenceStatus
    };
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

  private shouldFillTemplateBackground(didDrawBackgroundImage: boolean): boolean {
    return this.resolvePageBackgroundImageUri().length === 0 || !didDrawBackgroundImage;
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

    const viewModel = this.getRenderingViewModel();
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
    const viewModel = this.getRenderingViewModel();
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
    return this.isBackgroundLayerReady && this.isCommittedLayerReady && this.isRecentCommittedLayerReady;
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
    this.clearViewportRedrawTimers();
    this.lastHighQualityViewportRenderKey = '';
    this.inlineTextEditElement = null;
    this.inlineTextEditContent = '';
    this.resetInlineTextEditFrame();
    this.clearLastEditTap();
    this.hideSelectionContextMenu();
    this.selectedStrokeTargets = [];
    this.strokeResizeBounds = null;
    this.strokeResizeUiMode = 'none';
    this.isForwardingDocumentTouchGesture = false;
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
    this.attachExistingViewModelIfAvailable();
    if (this.shouldAutoLoadCurrentSession()) {
      this.resolveViewModel();
      void this.ensurePageSessionLoaded();
    } else {
      this.requestViewportRedraw();
    }
  }

  private onToolSettingChanged(): void {
    const activeTool = this.getEffectiveToolSetting().tool;
    if (!this.isRecentCommittedWritingTool(activeTool)) {
      this.stabilizeCommittedLayersForEdit(`tool:${activeTool}`);
    }
    if (activeTool !== 'edit') {
      this.commitInlineTextEdit(true);
    }
    const viewModel = this.peekViewModel();
    if (viewModel !== null) {
      this.syncViewModelToolSetting(viewModel);
    }
    if (viewModel !== null && activeTool !== 'lasso') {
      this.exitStrokeResizeMode(viewModel);
    }
    if (viewModel !== null && activeTool !== 'lasso') {
      this.cancelSelectionMoveGesture(viewModel);
    }
  }

  private onInputModeChanged(): void {
    const hadCanvasGesture = this.hasActiveCanvasGesture();
    this.isForwardingDocumentTouchGesture = false;
    if (!this.isActivePage && !hadCanvasGesture) {
      return;
    }

    const viewModel = this.peekViewModel();
    if (viewModel !== null && hadCanvasGesture) {
      this.cancelDrawingGesture(viewModel);
      this.cancelLassoGesture(viewModel);
      this.cancelSelectionMoveGesture(viewModel);
      this.cancelActiveStrokeResizeGesture(viewModel);
    }

    if (this.isActivePage) {
      this.hideSelectionContextMenu();
    }
  }

  private isRecentCommittedWritingTool(tool: string): boolean {
    return tool === 'pen' || tool === 'pencil' || tool === 'highlighter';
  }

  private onAutoLoadSessionChanged(): void {
    if (!this.shouldAutoLoadCurrentSession()) {
      return;
    }

    this.resolveViewModel();
    const viewModel = this.getViewModel();
    if (viewModel === null || !viewModel.isLoadedForPage(this.pageId)) {
      void this.ensurePageSessionLoaded();
      return;
    }

    this.requestViewportRedraw();
  }

  private onActivePageChanged(): void {
    if (!this.isActivePage) {
      this.hideSelectionContextMenu();
      return;
    }

    if (!this.shouldAutoLoadCurrentSession()) {
      this.attachExistingViewModelIfAvailable();
      const existingViewModel = this.peekViewModel();
      if (existingViewModel !== null && existingViewModel.isLoadedForPage(this.pageId)) {
        this.syncViewModelToolSetting(existingViewModel);
        this.syncEditorSnapshot();
      }
      return;
    }

    const viewModel = this.getViewModel();
    if (viewModel !== null) {
      this.syncViewModelToolSetting(viewModel);
      this.syncEditorSnapshot();
      if (!viewModel.isLoadedForPage(this.pageId)) {
        void this.ensurePageSessionLoaded();
      }
    }
  }

  private onCanvasStyleChanged(): void {
    this.clearViewportRedrawTimers();
    if (this.backgroundPixelMapUri !== this.resolvePageBackgroundImageUri()) {
      this.releaseBackgroundPixelMap();
    }
    this.lastHighQualityViewportRenderKey = '';
    this.redrawBackgroundLayer();
    this.redrawCommittedLayer();
    this.redrawOverlayLayer();
  }

  private onPageGeometryChanged(): void {
    this.clearViewportRedrawTimers();
    this.resetViewportTransform();
    this.notifyCanvasMetricsChanged();
    this.redrawCommittedLayer();
    this.redrawOverlayLayer();
  }

  private async ensurePageSessionLoaded(): Promise<void> {
    if (this.pageId.length === 0) {
      return;
    }

    const hostContext = this.getUIContext().getHostContext() as common.Context;
    const viewModel = await EditorSessionRegistry.ensureLoaded(
      this.pageId,
      hostContext,
      this.getEffectiveToolSetting()
    );
    if (this.pageId !== viewModel.getDebugSnapshot().pageId) {
      return;
    }

    this.viewModel = viewModel;
    this.forceFullCommittedRedrawOnNextCanvasRefresh = false;
    this.consumeLatestRenderInvalidationSequence();
    this.requestViewportRedraw();
    this.redrawOverlayLayer();
    if (this.isActivePage) {
      this.syncEditorSnapshot();
    }
  }

  private syncViewModelToolSetting(viewModel: DrawingEditorViewModel): void {
    const nextSetting = this.getEffectiveToolSetting();
    const currentSetting = viewModel.getToolSetting();
    if (currentSetting.tool === nextSetting.tool &&
      currentSetting.color === nextSetting.color &&
      currentSetting.width === nextSetting.width &&
      currentSetting.opacity === nextSetting.opacity) {
      return;
    }

    viewModel.updateToolSetting(nextSetting);
  }

  private getEffectiveToolSetting(): ToolSetting {
    return {
      tool: this.toolSetting.tool,
      color: this.toolSetting.color,
      width: this.toolSetting.width,
      opacity: this.toolSetting.opacity
    };
  }

  private getViewModel(): DrawingEditorViewModel | null {
    if (!this.viewModel) {
      this.resolveViewModel();
    }

    return this.viewModel;
  }

  private getRenderingViewModel(): DrawingEditorViewModel | null {
    if (this.viewModel !== null) {
      return this.shouldUseViewModelForRendering(this.viewModel) ? this.viewModel : null;
    }

    this.attachExistingViewModelIfAvailable();
    if (this.viewModel !== null) {
      return this.shouldUseViewModelForRendering(this.viewModel) ? this.viewModel : null;
    }

    if (!this.shouldAutoLoadCurrentSession()) {
      return null;
    }

    this.resolveViewModel();
    return this.viewModel;
  }

  private shouldUseViewModelForRendering(viewModel: DrawingEditorViewModel): boolean {
    return this.shouldAutoLoadCurrentSession() || viewModel.isLoadedForPage(this.pageId);
  }

  private peekViewModel(): DrawingEditorViewModel | null {
    if (this.viewModel !== null) {
      return this.viewModel;
    }

    return EditorSessionRegistry.get(this.pageId);
  }

  private attachExistingViewModelIfAvailable(): void {
    if (this.pageId.length === 0 || this.viewModel !== null) {
      return;
    }

    const existingSession = EditorSessionRegistry.get(this.pageId);
    if (existingSession === null) {
      return;
    }

    this.viewModel = existingSession;
    this.syncViewModelToolSetting(existingSession);
  }

  private shouldAutoLoadCurrentSession(): boolean {
    return this.autoLoadSession;
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
    this.syncViewModelToolSetting(this.viewModel);
  }
}
