import common from '@ohos.app.ability.common';

import {
  BoundingBox,
  doBoundingBoxesIntersect,
  ErasedStrokeSegment,
  eraseStrokePointsWithPath,
  expandBoundingBox,
  getBoundingBox,
  getPointToSegmentDistance,
  getStrokeRenderBoundingBox,
  mergeBoundingBoxes,
  sampleStrokePoints,
  isSamePoint
} from '../../../common/utils/GeometryUtil';
import {
  clampElementFrameToBounds,
  ElementBounds,
  ElementFrame
} from '../../../common/utils/ElementBoundsUtil';
import { createId } from '../../../common/utils/IdUtil';
import { now } from '../../../common/utils/TimeUtil';
import { EditorRepositoryImpl } from '../../../data/repositories/EditorRepositoryImpl';
import {
  CanvasElement,
  DEFAULT_STROKE_LAYER_Z_INDEX,
  ElementOutlineStyle,
  ImageCanvasElement,
  PAGE_CANVAS_CONTENT_VERSION,
  PageCanvasContent,
  ShapeCanvasElement,
  ShapeGeometry,
  ShapeGeometryPoint,
  ShapeType,
  TextCanvasElement,
  TextRecognitionMetadata,
  TRANSPARENT_ELEMENT_BACKGROUND_COLOR
} from '../../../domain/entities/CanvasElement';
import { Stroke, StrokePoint, StrokeStyle } from '../../../domain/entities/Stroke';
import { DrawableToolType, ToolSetting } from '../../../domain/entities/ToolSetting';
import { StrokeController } from '../controllers/StrokeController';
import { StrokeSpatialHashIndex } from '../controllers/StrokeSpatialHashIndex';
import {
  EditorDeltaLabel,
  EditorOperation,
  EditorSelectionSnapshot,
  IndexedElementRecord,
  IndexedStrokeRecord,
  UndoRedoApplyResult,
  UndoRedoController,
  UndoRedoDebugState,
  UndoRedoSnapshot
} from '../controllers/UndoRedoController';
import { SelectionController } from '../selection/SelectionController';
import {
  LayerActionAvailability,
  LayerOrderAction,
  ResizeHandle,
  SelectionAction,
  SelectionActionResult,
  SelectionContextMenuTarget,
  SelectionHitResult,
  SelectionTarget,
  SelectionTargetKind
} from '../selection/SelectionTypes';
import { EditorDebugSnapshot } from './EditorDebugSnapshot';
import { EditorPerformanceTrace } from '../utils/EditorPerformanceTrace';
import { RenderInvalidation, RenderInvalidationReason } from './RenderInvalidation';

const DEFAULT_TOOL_SETTING: ToolSetting = {
  tool: 'pen',
  color: '#111827',
  width: 4,
  opacity: 1
};

interface EraseResult {
  strokes: Stroke[];
  changed: boolean;
  removed: IndexedStrokeRecord[];
  added: IndexedStrokeRecord[];
}

interface ShapeDraft {
  shapeType: ShapeType;
  startPoint: StrokePoint;
  currentPoint: StrokePoint;
}

interface BoundaryEdge {
  startColumn: number;
  startRow: number;
  endColumn: number;
  endRow: number;
}

interface BoundaryStartEdge {
  edge: BoundaryEdge | null;
  startKeyIndex: number;
}

interface InsertRecognizedTextOptions {
  recognition?: TextRecognitionMetadata;
}

type ElementEditGestureKind =
  'move' |
  'resizeTopLeft' |
  'resizeTop' |
  'resizeTopRight' |
  'resizeRight' |
  'resizeBottomLeft' |
  'resizeBottom' |
  'resizeBottomRight' |
  'resizeLeft' |
  'resizeTextLeft' |
  'resizeTextRight' |
  'lineStart' |
  'lineEnd';

interface ElementEditGesture {
  elementId: string;
  kind: ElementEditGestureKind;
  startPoint: StrokePoint;
  originalElement: CanvasElement;
}

interface ElementStyleEditGesture {
  elementId: string;
  originalElement: CanvasElement;
}

interface SelectionMoveGesture {
  startPoint: StrokePoint;
  currentOffsetX: number;
  currentOffsetY: number;
  originalStrokeRecords: IndexedStrokeRecord[];
  originalElementRecords: IndexedElementRecord[];
  originalTargets: SelectionTarget[];
  selectionBounds: BoundingBox;
}

export interface PageContentResizeSnapshot {
  strokes: Stroke[];
  elements: CanvasElement[];
  strokeLayerZIndex: number;
  undoRedoSnapshot: UndoRedoSnapshot;
  changeSequence: number;
  lastPersistedChangeSequence: number;
  persistenceStatus: string;
}

interface StrokeResizeGesture {
  handle: ResizeHandle;
  currentBounds: BoundingBox;
  originalBounds: BoundingBox;
  originalStrokeRecords: IndexedStrokeRecord[];
  originalTargets: SelectionTarget[];
}

export interface ImageInsertAsset {
  uri: string;
  originalWidth: number;
  originalHeight: number;
}

type LayerStackItemKind = 'strokeLayer' | 'element';

interface LayerStackItem {
  kind: LayerStackItemKind;
  id: string;
  zIndex: number;
  createdAt: number;
  orderIndex: number;
}

interface LayerReorderResult {
  changed: boolean;
  strokeLayerZIndex: number;
  elements: CanvasElement[];
}

export interface ElementLayerChangePreview {
  changed: boolean;
  beforeElement: CanvasElement | null;
  afterElement: CanvasElement | null;
  beforeStrokeLayerZIndex: number;
  afterStrokeLayerZIndex: number;
}

interface ElementLayerOrderRecord {
  element: CanvasElement;
  orderIndex: number;
}

export interface ImageElementEditDraft {
  elementId: string;
  originalFrame: ElementFrame;
  currentFrame: ElementFrame;
}

const MAX_DEBUG_EVENTS = 20;
const SAVE_DEBOUNCE_MS = 900;
const INTERACTION_SAVE_DEBOUNCE_MS = 180;
const EDITOR_BUILD_MARKER = 'editor-build-2026-04-20-state-link-sync-v1';
const DEFAULT_TEXT_ELEMENT_TOP_OFFSET = 24;
const DEFAULT_SHAPE_OUTLINE: ElementOutlineStyle = {
  lineStyle: 'solid',
  color: '#111827',
  width: 2
};
const DEFAULT_TEXT_OUTLINE: ElementOutlineStyle = {
  lineStyle: 'none',
  color: '#111827',
  width: 2
};
const DEFAULT_IMAGE_OUTLINE: ElementOutlineStyle = {
  lineStyle: 'none',
  color: '#111827',
  width: 2
};
const MIN_SHAPE_DRAG_DISTANCE = 8;
const ELEMENT_LINE_HIT_TOLERANCE = 8;
const MIN_TEXT_FONT_SIZE = 8;
const MAX_TEXT_FONT_SIZE = 96;
const DEFAULT_TEXT_ELEMENT_WIDTH = 64;
const MIN_TEXT_ELEMENT_WIDTH = 40;
const TEXT_ELEMENT_HORIZONTAL_PADDING = 16;
const TEXT_ELEMENT_VERTICAL_PADDING = 12;
const TEXT_ELEMENT_WIDTH_FACTOR = 0.58;
const TEXT_ELEMENT_LINE_HEIGHT_FACTOR = 1.35;
const MIN_IMAGE_ELEMENT_SIZE = 24;
const STROKE_COPY_OFFSET = 32;
const EMPTY_SELECTION_ACTION_RESULT: SelectionActionResult = {
  changed: false,
  changedStrokes: false,
  changedElements: false,
  elementSelectionChanged: false
};
const MIN_SHAPE_ELEMENT_SIZE = 8;
const MAX_IMAGE_INSERT_WIDTH = 420;
const MAX_IMAGE_INSERT_HEIGHT = 320;
const IMAGE_CANVAS_FILL_RATIO = 0.6;
const MIN_LASSO_POINT_DISTANCE = 2;
const MIN_LASSO_POINT_COUNT = 3;
const STROKE_SELECTION_MASK_CELL_SIZE = 4;
const STROKE_SELECTION_OUTLINE_PADDING = 24;
const STROKE_SELECTION_OUTLINE_SIMPLIFY_DISTANCE = 8;
const STROKE_SELECTION_MAX_MASK_CELLS = 180000;
const STROKE_SELECTION_MAX_EDGE_COUNT = 16000;
const LASSO_STROKE_MIN_INSIDE_RATIO = 0.2;
const LASSO_STROKE_MIN_INSIDE_COUNT = 2;
const LASSO_STROKE_SHORT_SAMPLE_COUNT = 3;
const MIN_STROKE_RESIZE_BOUNDS_SIZE = 8;
const MIN_STROKE_RESIZE_WIDTH = 0.5;
let nextEditorViewModelInstanceId = 1;

export class DrawingEditorViewModel {
  private readonly strokeController: StrokeController = new StrokeController();
  private readonly undoRedoController: UndoRedoController = new UndoRedoController();
  private readonly strokeSpatialIndex: StrokeSpatialHashIndex = new StrokeSpatialHashIndex();

  private pageId: string = '';
  private strokes: Stroke[] = [];
  private elements: CanvasElement[] = [];
  private strokeLayerZIndex: number = DEFAULT_STROKE_LAYER_Z_INDEX;
  private toolSetting: ToolSetting = {
    tool: DEFAULT_TOOL_SETTING.tool,
    color: DEFAULT_TOOL_SETTING.color,
    width: DEFAULT_TOOL_SETTING.width,
    opacity: DEFAULT_TOOL_SETTING.opacity
  };
  private isLoading: boolean = false;
  private errorMessage: string = '';
  private activeErasePath: StrokePoint[] = [];
  private eraseSourceStrokes: Stroke[] | null = null;
  private debugEvents: string[] = [];
  private debugSequence: number = 0;
  private persistenceStatus: string = 'idle';
  private saveTimerId: number = -1;
  private isPersisting: boolean = false;
  private hasQueuedPersistence: boolean = false;
  private queuedPersistenceReason: string = 'update';
  private changeSequence: number = 0;
  private lastPersistedChangeSequence: number = 0;
  private renderInvalidationSequence: number = 0;
  private lastRenderInvalidation: RenderInvalidation | null = null;
  private hasLoadedPageSnapshot: boolean = false;
  private selectionVersion: number = 0;
  private shapeDraft: ShapeDraft | null = null;
  private selectedElementId: string = '';
  private selectedElementIds: string[] = [];
  private selectedStrokeTargets: SelectionTarget[] = [];
  private lassoDraftPath: StrokePoint[] = [];
  private elementEditGesture: ElementEditGesture | null = null;
  private elementStyleEditGesture: ElementStyleEditGesture | null = null;
  private imageElementEditDraft: ImageElementEditDraft | null = null;
  private selectionMoveGesture: SelectionMoveGesture | null = null;
  private strokeResizeGesture: StrokeResizeGesture | null = null;
  private readonly instanceId: number = nextEditorViewModelInstanceId++;

  constructor(private readonly contextProvider: () => common.Context) {}

  async loadPage(pageId: string): Promise<void> {
    this.isLoading = true;
    this.errorMessage = '';
    this.pageId = pageId;
    this.hasLoadedPageSnapshot = false;
    this.debugEvents = [];
    this.debugSequence = 0;
    this.persistenceStatus = 'loading';
    this.appendDebugEvent('build', `${EDITOR_BUILD_MARKER} vm=${this.instanceId}`);
    this.appendDebugEvent('loadPage', `start pageId=${pageId}`);

    try {
      const pageContent: PageCanvasContent = await this.createRepository().getPageContent(pageId);
      this.strokes = pageContent.strokes;
      this.elements = pageContent.elements;
      this.strokeLayerZIndex = pageContent.strokeLayerZIndex;
      this.rebuildStrokeSpatialIndex();
      this.resetTransientState();
      this.undoRedoController.seedLoadedStrokes(this.strokes);
      this.markFullRenderInvalidation('load');
      this.changeSequence = 0;
      this.lastPersistedChangeSequence = 0;
      this.hasLoadedPageSnapshot = true;
      this.persistenceStatus = `loaded strokes=${this.strokes.length} elements=${this.elements.length}`;
      this.appendDebugEvent('loadPage', `loaded strokes=${this.strokes.length} elements=${this.elements.length}`);
    } catch (error) {
      this.errorMessage = this.stringifyError(error);
      this.strokes = [];
      this.elements = [];
      this.strokeLayerZIndex = DEFAULT_STROKE_LAYER_Z_INDEX;
      this.strokeSpatialIndex.clear();
      this.resetTransientState();
      this.markFullRenderInvalidation('load');
      this.changeSequence = 0;
      this.lastPersistedChangeSequence = 0;
      this.hasLoadedPageSnapshot = false;
      this.persistenceStatus = `loadFailed error=${this.errorMessage}`;
      this.appendDebugEvent('loadPage', `failed error=${this.errorMessage}`);
    } finally {
      this.isLoading = false;
    }
  }

  createPageContentResizeSnapshot(): PageContentResizeSnapshot {
    return {
      strokes: this.cloneStrokes(this.strokes),
      elements: this.cloneElements(this.elements),
      strokeLayerZIndex: this.strokeLayerZIndex,
      undoRedoSnapshot: this.undoRedoController.createSnapshot(),
      changeSequence: this.changeSequence,
      lastPersistedChangeSequence: this.lastPersistedChangeSequence,
      persistenceStatus: this.persistenceStatus
    };
  }

  restorePageContentResizeSnapshot(snapshot: PageContentResizeSnapshot): void {
    this.clearScheduledSave();
    this.strokes = this.cloneStrokes(snapshot.strokes);
    this.elements = this.cloneElements(snapshot.elements);
    this.strokeLayerZIndex = snapshot.strokeLayerZIndex;
    this.undoRedoController.restoreSnapshot(snapshot.undoRedoSnapshot);
    this.rebuildStrokeSpatialIndex();
    this.resetTransientState();
    this.changeSequence = snapshot.changeSequence;
    this.lastPersistedChangeSequence = snapshot.lastPersistedChangeSequence;
    this.persistenceStatus = snapshot.persistenceStatus;
    this.errorMessage = '';
    this.markFullRenderInvalidation('resize');
    this.appendDebugEvent('canvasResize', 'restored rollback snapshot');
  }

  resizePageContentForCanvasSize(sourceSize: ElementBounds, targetSize: ElementBounds): boolean {
    const sourceWidth = Math.max(1, Number(sourceSize.width));
    const sourceHeight = Math.max(1, Number(sourceSize.height));
    const targetWidth = Math.max(1, Number(targetSize.width));
    const targetHeight = Math.max(1, Number(targetSize.height));
    if (!Number.isFinite(sourceWidth) || !Number.isFinite(sourceHeight) ||
      !Number.isFinite(targetWidth) || !Number.isFinite(targetHeight)) {
      return false;
    }

    if (sourceWidth === targetWidth && sourceHeight === targetHeight) {
      return false;
    }

    const hasCurrentContent = this.strokes.length > 0 || this.elements.length > 0;
    const historyState: UndoRedoDebugState = this.undoRedoController.getDebugState();
    const hasUndoRedoContent = historyState.undoDepth > 0 || historyState.redoDepth > 0;
    if (this.pageId.length === 0 || (!hasCurrentContent && !hasUndoRedoContent)) {
      return false;
    }

    const sourceBounds: BoundingBox = {
      minX: 0,
      minY: 0,
      maxX: sourceWidth,
      maxY: sourceHeight
    };
    const targetBounds: BoundingBox = {
      minX: 0,
      minY: 0,
      maxX: targetWidth,
      maxY: targetHeight
    };
    const updatedAt = now();

    this.strokes = this.strokes.map((stroke: Stroke): Stroke =>
      this.scaleStrokeForCanvasResize(stroke, sourceBounds, targetBounds, updatedAt));
    this.elements = this.elements.map((element: CanvasElement): CanvasElement =>
      this.scaleElementForCanvasResize(element, sourceBounds, targetBounds, updatedAt));
    this.undoRedoController.restoreSnapshot(
      this.scaleUndoRedoSnapshotForCanvasResize(
        this.undoRedoController.createSnapshot(),
        sourceBounds,
        targetBounds
      )
    );
    this.rebuildStrokeSpatialIndex();
    this.resetTransientState();
    if (hasCurrentContent) {
      this.changeSequence += 1;
      this.persistenceStatus = 'pending canvas resize save';
    }
    this.markFullRenderInvalidation('resize');
    this.appendDebugEvent(
      'canvasResize',
      `${Math.round(sourceWidth)}x${Math.round(sourceHeight)} -> ${Math.round(targetWidth)}x${Math.round(targetHeight)}`
    );
    return true;
  }

  beginStroke(point: StrokePoint): Stroke | null {
    if (this.pageId.length === 0) {
      this.errorMessage = 'Page is not loaded.';
      return null;
    }

    this.clearScheduledSave();
    this.errorMessage = '';
    this.appendDebugEvent(
      'beginStroke',
      `tool=${this.describeToolSetting(this.toolSetting)} point=(${Math.round(point.x)},${Math.round(point.y)})`
    );

    if (this.toolSetting.tool === 'eraser') {
      this.beginErase(point);
      return null;
    }

    const activeStroke = this.strokeController.beginStroke(this.pageId, point, this.buildDrawableStrokeStyle());
    this.appendDebugEvent('beginStroke', `active=${this.describeStroke(activeStroke)}`);
    return activeStroke;
  }

  appendPoint(point: StrokePoint): Stroke | null {
    if (this.isEraseGestureActive()) {
      this.appendErasePoint(point);
      return null;
    }

    return this.strokeController.appendPoint(point);
  }

  async finishStroke(): Promise<Stroke | null> {
    if (this.isEraseGestureActive()) {
      return this.finishErase();
    }

    const completedStroke = this.strokeController.finishStroke();
    if (!completedStroke) {
      return null;
    }

    const applyStartedAt = Date.now();
    const nextStrokes = this.strokes.slice();
    nextStrokes.push(completedStroke);
    this.strokes = nextStrokes;
    this.clearStrokeSelection();
    this.lassoDraftPath = [];
    this.strokeSpatialIndex.upsertStroke(completedStroke);
    this.undoRedoController.recordAppendStroke(completedStroke, nextStrokes.length - 1);
    this.changeSequence += 1;
    this.persistenceStatus = 'pending stroke save';
    this.appendDebugEvent('finishStroke', `queuedSave count=${nextStrokes.length} stroke=${this.describeStroke(completedStroke)}`);
    this.schedulePersistCurrentStrokes('stroke');
    EditorPerformanceTrace.record(
      'stroke.commit',
      Date.now() - applyStartedAt,
      `strokes=${nextStrokes.length} strokePoints=${completedStroke.points.length}`,
      4
    );

    return completedStroke;
  }

  cancelStroke(): void {
    if (this.isEraseGestureActive()) {
      this.cancelErase();
      return;
    }

    this.strokeController.cancelStroke();
  }

  async undo(): Promise<void> {
    if (this.pageId.length === 0) {
      this.errorMessage = 'Page is not loaded.';
      return;
    }

    this.cancelStroke();
    this.cancelSelectionMove();
    this.cancelStrokeResize();
    const operationStartedAt = Date.now();
    const beforeStrokeCount = this.strokes.length;
    const beforePointCount = this.countStrokePoints(this.strokes);
    this.appendDebugEvent('undo', `requested count=${this.strokes.length} history=${this.describeHistoryState()}`);
    const undoResult: UndoRedoApplyResult = EditorPerformanceTrace.measureSync(
      'undo.controller',
      () => this.undoRedoController.undo(this.strokes, this.elements),
      `beforeStrokes=${beforeStrokeCount} beforePoints=${beforePointCount}`,
      6
    );
    if (!this.hasUndoRedoChanges(undoResult)) {
      this.appendDebugEvent('undo', 'skipped noChange');
      return;
    }

    const applyStartedAt = Date.now();
    this.strokes = undoResult.strokes;
    this.elements = undoResult.elements;
    if (undoResult.strokeLayerZIndex !== null) {
      this.strokeLayerZIndex = undoResult.strokeLayerZIndex;
    }
    this.restoreSelectionSnapshot(undoResult.selection);
    this.lassoDraftPath = [];
    this.applyStrokeSpatialIndexMutation(undoResult.removed, undoResult.added);
    this.markPartialRenderInvalidation('undo', undoResult.removed, undoResult.added);
    this.changeSequence += 1;
    this.persistenceStatus = 'pending undo save';
    this.schedulePersistCurrentStrokes('undo', INTERACTION_SAVE_DEBOUNCE_MS);
    this.errorMessage = '';
    this.appendDebugEvent('undo', `applied queuedSave count=${this.strokes.length} history=${this.describeHistoryState()}`);
    const afterPointCount = this.countStrokePoints(this.strokes);
    EditorPerformanceTrace.record(
      'undo.apply',
      Date.now() - applyStartedAt,
      `afterStrokes=${this.strokes.length} afterPoints=${afterPointCount} removed=${undoResult.removed.length} added=${undoResult.added.length}`,
      6
    );
    EditorPerformanceTrace.record(
      'undo.total',
      Date.now() - operationStartedAt,
      `beforeStrokes=${beforeStrokeCount} afterStrokes=${this.strokes.length} beforePoints=${beforePointCount} afterPoints=${afterPointCount} persistDelay=${INTERACTION_SAVE_DEBOUNCE_MS}`,
      8
    );
  }

  async redo(): Promise<void> {
    if (this.pageId.length === 0) {
      this.errorMessage = 'Page is not loaded.';
      return;
    }

    this.cancelStroke();
    this.cancelSelectionMove();
    this.cancelStrokeResize();
    const operationStartedAt = Date.now();
    const beforeStrokeCount = this.strokes.length;
    const beforePointCount = this.countStrokePoints(this.strokes);
    this.appendDebugEvent('redo', `requested count=${this.strokes.length} history=${this.describeHistoryState()}`);
    const redoResult: UndoRedoApplyResult = EditorPerformanceTrace.measureSync(
      'redo.controller',
      () => this.undoRedoController.redo(this.strokes, this.elements),
      `beforeStrokes=${beforeStrokeCount} beforePoints=${beforePointCount}`,
      6
    );
    if (!this.hasUndoRedoChanges(redoResult)) {
      this.appendDebugEvent('redo', 'skipped noChange');
      return;
    }

    const applyStartedAt = Date.now();
    this.strokes = redoResult.strokes;
    this.elements = redoResult.elements;
    if (redoResult.strokeLayerZIndex !== null) {
      this.strokeLayerZIndex = redoResult.strokeLayerZIndex;
    }
    this.restoreSelectionSnapshot(redoResult.selection);
    this.lassoDraftPath = [];
    this.applyStrokeSpatialIndexMutation(redoResult.removed, redoResult.added);
    this.markPartialRenderInvalidation('redo', redoResult.removed, redoResult.added);
    this.changeSequence += 1;
    this.persistenceStatus = 'pending redo save';
    this.schedulePersistCurrentStrokes('redo', INTERACTION_SAVE_DEBOUNCE_MS);
    this.errorMessage = '';
    this.appendDebugEvent('redo', `applied queuedSave count=${this.strokes.length} history=${this.describeHistoryState()}`);
    const afterPointCount = this.countStrokePoints(this.strokes);
    EditorPerformanceTrace.record(
      'redo.apply',
      Date.now() - applyStartedAt,
      `afterStrokes=${this.strokes.length} afterPoints=${afterPointCount} removed=${redoResult.removed.length} added=${redoResult.added.length}`,
      6
    );
    EditorPerformanceTrace.record(
      'redo.total',
      Date.now() - operationStartedAt,
      `beforeStrokes=${beforeStrokeCount} afterStrokes=${this.strokes.length} beforePoints=${beforePointCount} afterPoints=${afterPointCount} persistDelay=${INTERACTION_SAVE_DEBOUNCE_MS}`,
      8
    );
  }

  async clear(): Promise<void> {
    if (this.pageId.length === 0) {
      this.errorMessage = 'Page is not loaded.';
      return;
    }

    this.cancelStroke();
    this.cancelShapeDraft();
    this.clearEraseState();
    const sourceSnapshot = this.cloneStrokes(this.strokes);
    const sourceElementSnapshot = this.elements.map((element: CanvasElement, index: number): IndexedElementRecord => ({
      index,
      element: this.cloneElement(element)
    }));
    if (sourceSnapshot.length === 0 && sourceElementSnapshot.length === 0) {
      this.appendDebugEvent('clear', 'skipped empty');
      return;
    }

    this.appendDebugEvent(
      'clear',
      `requested strokes=${sourceSnapshot.length} elements=${sourceElementSnapshot.length} history=${this.describeHistoryState()}`
    );
    const applyStartedAt = Date.now();
    const beforeSelection = this.getCurrentSelectionSnapshot();
    this.strokes = [];
    this.elements = [];
    this.clearSelectionState();
    this.lassoDraftPath = [];
    this.strokeSpatialIndex.clear();
    this.undoRedoController.recordDelta(
      sourceSnapshot.map((stroke: Stroke, index: number): IndexedStrokeRecord => ({
        index,
        stroke: this.cloneStroke(stroke)
      })),
      [],
      'clear',
      sourceElementSnapshot,
      [],
      beforeSelection,
      this.getCurrentSelectionSnapshot()
    );
    this.markFullRenderInvalidation('clear');
    this.changeSequence += 1;
    this.persistenceStatus = 'pending clear save';
    this.schedulePersistCurrentStrokes('clear', INTERACTION_SAVE_DEBOUNCE_MS);
    this.errorMessage = '';
    this.appendDebugEvent('clear', `queuedSave history=${this.describeHistoryState()}`);
    EditorPerformanceTrace.record(
      'clear.total',
      Date.now() - applyStartedAt,
      `removedStrokes=${sourceSnapshot.length} removedElements=${sourceElementSnapshot.length} removedPoints=${this.countStrokePoints(sourceSnapshot)} persistDelay=${INTERACTION_SAVE_DEBOUNCE_MS}`,
      8
    );
  }

  updateToolSetting(nextSetting: ToolSetting): void {
    if (this.toolSetting.tool === nextSetting.tool &&
      this.toolSetting.color === nextSetting.color &&
      this.toolSetting.width === nextSetting.width &&
      this.toolSetting.opacity === nextSetting.opacity) {
      return;
    }

    if (this.isEraseGestureActive() || this.strokeController.hasActiveStroke()) {
      this.cancelStroke();
    }
    this.cancelShapeDraft();
    this.cancelLassoSelection();
    this.cancelSelectionMove();
    this.cancelStrokeResize();
    if (this.toolSetting.tool === 'lasso' && nextSetting.tool !== 'lasso') {
      this.clearSelection();
    }

    this.toolSetting = {
      tool: nextSetting.tool,
      color: nextSetting.color,
      width: nextSetting.width,
      opacity: nextSetting.opacity
    };
    this.appendDebugEvent('toolSetting', this.describeToolSetting(this.toolSetting));
  }

  getToolSetting(): ToolSetting {
    return {
      tool: this.toolSetting.tool,
      color: this.toolSetting.color,
      width: this.toolSetting.width,
      opacity: this.toolSetting.opacity
    };
  }

  getStrokes(): Stroke[] {
    return this.cloneStrokes(this.strokes);
  }

  getStrokesForRendering(): Stroke[] {
    return this.strokes;
  }

  getElements(): CanvasElement[] {
    return this.cloneElements(this.elements);
  }

  getElementsForRendering(): CanvasElement[] {
    return this.cloneElements(this.getElementsInLayerOrderAscending(this.elements));
  }

  getStrokeLayerZIndex(): number {
    return this.strokeLayerZIndex;
  }

  getImageElementEditDraft(): ImageElementEditDraft | null {
    if (this.imageElementEditDraft === null) {
      return null;
    }

    return this.cloneImageElementEditDraft(this.imageElementEditDraft);
  }

  getSelectedElementId(): string {
    return this.selectedElementId;
  }

  getSelectedElementIds(): string[] {
    return [...this.selectedElementIds];
  }

  getSelectedStrokeTargets(): SelectionTarget[] {
    return this.cloneSelectionTargets(this.selectedStrokeTargets);
  }

  getSelectedStrokeResizeBounds(): BoundingBox | null {
    return this.getSelectionBoundsFromTargets(this.selectedStrokeTargets);
  }

  getSelectionBoundingBox(): BoundingBox | null {
    return this.getSelectionBoundsFromTargets(this.buildSelectionTargets());
  }

  getSelectionTargets(): SelectionTarget[] {
    return this.buildSelectionTargets();
  }

  hitTestSelection(point: StrokePoint, hitTolerance: number): SelectionHitResult {
    return SelectionController.hitTestTargets(this.buildSelectionTargets(), point, hitTolerance);
  }

  clearSelection(): void {
    this.clearSelectionState();
    this.lassoDraftPath = [];
    this.appendDebugEvent('selection', 'clear');
  }

  getSelectionVersion(): number {
    return this.selectionVersion;
  }

  getLassoDraftPath(): StrokePoint[] {
    return this.lassoDraftPath.map((point: StrokePoint): StrokePoint => this.clonePoint(point));
  }

  getSelectedElement(): CanvasElement | null {
    const selectedElement = this.elements.find((element: CanvasElement): boolean => element.id === this.selectedElementId);
    return selectedElement === undefined ? null : this.cloneElement(selectedElement);
  }

  getElementForRendering(elementId: string): CanvasElement | null {
    const element = this.getElementById(elementId);
    return element === null ? null : this.cloneElement(element);
  }

  getElementContextMenuCandidate(point: StrokePoint, hitTolerance: number): CanvasElement | null {
    for (const selectedElement of this.getSelectedElementsInZOrderDescending()) {
      if (this.hitTestElementEditHandle(point, selectedElement, hitTolerance) !== null) {
        return null;
      }
    }

    const hitElement = this.hitTestElement(point);
    return hitElement === null ? null : this.cloneElement(hitElement);
  }

  getSelectedElementEditCandidate(point: StrokePoint, hitTolerance: number): CanvasElement | null {
    for (const selectedElement of this.getSelectedElementsInZOrderDescending()) {
      if (this.hitTestElementEditHandle(point, selectedElement, hitTolerance) !== null) {
        return this.cloneElement(selectedElement);
      }
    }

    const hitElement = this.hitTestElement(point);
    if (hitElement !== null && this.selectedElementIds.includes(hitElement.id)) {
      return this.cloneElement(hitElement);
    }

    return null;
  }

  selectElement(elementId: string): CanvasElement | null {
    if (elementId.length === 0) {
      this.clearElementSelection();
      return null;
    }

    const selectedElement = this.elements.find((element: CanvasElement): boolean => element.id === elementId);
    if (selectedElement === undefined) {
      this.clearElementSelection();
      return null;
    }

    this.selectedElementId = selectedElement.id;
    this.selectedElementIds = [selectedElement.id];
    this.selectedStrokeTargets = [];
    this.selectionVersion += 1;
    this.appendDebugEvent('selectElement', `element=${selectedElement.id} type=${selectedElement.type}`);
    return this.cloneElement(selectedElement);
  }

  selectElementAt(point: StrokePoint): CanvasElement | null {
    const selectedElement = this.hitTestElement(point);
    if (selectedElement === null) {
      this.clearElementSelection();
      this.appendDebugEvent('selectElementAt', `empty x=${Math.round(point.x)} y=${Math.round(point.y)}`);
      return null;
    }

    this.selectedElementId = selectedElement.id;
    this.selectedElementIds = [selectedElement.id];
    this.selectedStrokeTargets = [];
    this.selectionVersion += 1;
    this.appendDebugEvent(
      'selectElementAt',
      `element=${selectedElement.id} type=${selectedElement.type} x=${Math.round(point.x)} y=${Math.round(point.y)}`
    );
    return this.cloneElement(selectedElement);
  }

  clearElementSelection(): void {
    if (this.selectedElementId.length > 0) {
      this.appendDebugEvent('clearElementSelection', `element=${this.selectedElementId}`);
    }
    this.elementEditGesture = null;
    this.elementStyleEditGesture = null;
    this.imageElementEditDraft = null;
    this.selectionMoveGesture = null;
    this.strokeResizeGesture = null;
    this.selectedElementId = '';
    this.selectedElementIds = [];
    this.selectedStrokeTargets = [];
    this.selectionVersion += 1;
  }

  hasSelectedElement(): boolean {
    return this.selectedElementIds.length > 0 &&
      this.elements.some((element: CanvasElement): boolean => this.selectedElementIds.includes(element.id));
  }

  deleteElementById(elementId: string): SelectionActionResult {
    const beforeSelection = this.getCurrentSelectionSnapshot();
    const selectedElement = this.getElementById(elementId);
    if (selectedElement === null) {
      return { ...EMPTY_SELECTION_ACTION_RESULT };
    }

    const selectedElementIndex = this.getElementIndexById(selectedElement.id);
    this.elements = this.elements.filter((element: CanvasElement): boolean => element.id !== selectedElement.id);
    this.selectedElementIds = this.selectedElementIds.filter((elementId: string): boolean => elementId !== selectedElement.id);
    this.selectedElementId = this.selectedElementIds.length > 0 ? this.selectedElementIds[0] : '';
    this.elementEditGesture = null;
    this.elementStyleEditGesture = null;
    this.imageElementEditDraft = null;
    this.selectionVersion += 1;
    this.recordElementDelta('elementDelete', [{
      index: selectedElementIndex,
      element: this.cloneElement(selectedElement)
    }], [], beforeSelection, this.getCurrentSelectionSnapshot());
    this.changeSequence += 1;
    this.persistenceStatus = 'pending element delete save';
    this.schedulePersistCurrentStrokes('elementDelete', 0);
    this.errorMessage = '';
    this.appendDebugEvent('deleteElement', `element=${selectedElement.id} type=${selectedElement.type}`);
    return {
      changed: true,
      changedStrokes: false,
      changedElements: true,
      elementSelectionChanged: true
    };
  }

  updateShapeFillColorById(elementId: string, fillColor: string): SelectionActionResult {
    const element = this.getElementById(elementId);
    if (element === null || element.type !== 'shape' || element.fillColor === fillColor) {
      return { ...EMPTY_SELECTION_ACTION_RESULT };
    }

    const nextElement: ShapeCanvasElement = {
      ...this.cloneShapeElement(element),
      fillColor,
      updatedAt: now()
    };
    return this.replaceElementWithDelta('elementStyle', element, nextElement, 'elementStyle');
  }

  updateTextBackgroundColorById(elementId: string, backgroundColor: string): SelectionActionResult {
    const element = this.getElementById(elementId);
    if (element === null || element.type !== 'text' || element.backgroundColor === backgroundColor) {
      return { ...EMPTY_SELECTION_ACTION_RESULT };
    }

    const nextElement: TextCanvasElement = {
      ...this.cloneTextElement(element),
      backgroundColor,
      updatedAt: now()
    };
    return this.replaceElementWithDelta('elementStyle', element, nextElement, 'elementStyle');
  }

  updateTextColorById(elementId: string, color: string): SelectionActionResult {
    const element = this.getElementById(elementId);
    if (element === null || element.type !== 'text' || element.color === color) {
      return { ...EMPTY_SELECTION_ACTION_RESULT };
    }

    const nextElement: TextCanvasElement = {
      ...this.cloneTextElement(element),
      color,
      updatedAt: now()
    };
    return this.replaceElementWithDelta('elementStyle', element, nextElement, 'elementStyle');
  }

  updateTextFontSizeById(
    elementId: string,
    fontSize: number,
    bounds: ElementBounds,
    recordHistory: boolean = true
  ): SelectionActionResult {
    const element = this.getElementById(elementId);
    if (element === null || element.type !== 'text') {
      return { ...EMPTY_SELECTION_ACTION_RESULT };
    }
    if (recordHistory) {
      this.elementStyleEditGesture = null;
    }

    const nextFontSize = this.clampNumber(Math.round(fontSize), MIN_TEXT_FONT_SIZE, MAX_TEXT_FONT_SIZE);
    const nextHeight = this.calculatePredictedTextHeight(element.content, element.width, nextFontSize);
    const nextFrame = clampElementFrameToBounds({
      x: element.x,
      y: element.y,
      width: element.width,
      height: nextHeight
    }, bounds);
    if (
      element.fontSize === nextFontSize &&
        element.x === nextFrame.x &&
        element.y === nextFrame.y &&
        element.width === nextFrame.width &&
        element.height === nextFrame.height
    ) {
      return { ...EMPTY_SELECTION_ACTION_RESULT };
    }

    const nextElement: TextCanvasElement = {
      ...this.cloneTextElement(element),
      x: nextFrame.x,
      y: nextFrame.y,
      width: nextFrame.width,
      height: nextFrame.height,
      fontSize: nextFontSize,
      updatedAt: recordHistory ? now() : element.updatedAt
    };
    if (!recordHistory) {
      this.replaceElementInMemory(nextElement);
      return {
        changed: true,
        changedStrokes: false,
        changedElements: true,
        elementSelectionChanged: false
      };
    }

    return this.replaceElementWithDelta('elementStyle', element, nextElement, 'elementStyle');
  }

  beginElementStyleEdit(elementId: string): boolean {
    const element = this.getElementById(elementId);
    if (element === null) {
      this.elementStyleEditGesture = null;
      return false;
    }

    this.elementStyleEditGesture = {
      elementId,
      originalElement: this.cloneElement(element)
    };
    return true;
  }

  finishElementStyleEdit(elementId: string): SelectionActionResult {
    const gesture = this.elementStyleEditGesture;
    this.elementStyleEditGesture = null;
    if (gesture === null || gesture.elementId !== elementId) {
      return { ...EMPTY_SELECTION_ACTION_RESULT };
    }

    const currentElement = this.getElementById(elementId);
    if (currentElement === null || this.areElementsEquivalent(gesture.originalElement, currentElement)) {
      return { ...EMPTY_SELECTION_ACTION_RESULT };
    }

    const finalElement = this.cloneElementWithUpdatedAt(currentElement);
    return this.replaceElementWithDelta('elementStyle', gesture.originalElement, finalElement, 'elementStyle');
  }

  beginElementOutlineEdit(elementId: string): boolean {
    return this.beginElementStyleEdit(elementId);
  }

  finishElementOutlineEdit(elementId: string): SelectionActionResult {
    return this.finishElementStyleEdit(elementId);
  }

  updateElementOutlineById(
    elementId: string,
    patch: Partial<ElementOutlineStyle>,
    recordHistory: boolean = true
  ): SelectionActionResult {
    const element = this.getElementById(elementId);
    if (element === null) {
      return { ...EMPTY_SELECTION_ACTION_RESULT };
    }
    if (recordHistory) {
      this.elementStyleEditGesture = null;
    }

    const nextOutline: ElementOutlineStyle = {
      lineStyle: patch.lineStyle ?? element.outline.lineStyle,
      color: patch.color ?? element.outline.color,
      width: Math.max(0, patch.width ?? element.outline.width)
    };
    if (JSON.stringify(nextOutline) === JSON.stringify(element.outline)) {
      return { ...EMPTY_SELECTION_ACTION_RESULT };
    }

    const nextElement = this.cloneElementWithOutline(element, nextOutline, recordHistory ? now() : element.updatedAt);
    if (!recordHistory) {
      this.replaceElementInMemory(nextElement);
      return {
        changed: true,
        changedStrokes: false,
        changedElements: true,
        elementSelectionChanged: false
      };
    }

    return this.replaceElementWithDelta('elementStyle', element, nextElement, 'elementStyle');
  }

  getElementLayerActionAvailability(elementId: string): LayerActionAvailability {
    const stack = this.buildLayerStack();
    const itemIndex = stack.findIndex((item: LayerStackItem): boolean => item.id === `element:${elementId}`);
    if (itemIndex < 0) {
      return {
        canMoveUp: false,
        canMoveDown: false,
        canMoveTop: false,
        canMoveBottom: false
      };
    }

    const stackLength = stack.length;
    return {
      canMoveUp: itemIndex < stackLength - 1,
      canMoveDown: itemIndex > 0,
      canMoveTop: itemIndex < stackLength - 1,
      canMoveBottom: itemIndex > 0
    };
  }

  previewElementLayerChangeById(elementId: string, action: LayerOrderAction): ElementLayerChangePreview {
    const beforeElement = this.getElementById(elementId);
    if (beforeElement === null) {
      return {
        changed: false,
        beforeElement: null,
        afterElement: null,
        beforeStrokeLayerZIndex: this.strokeLayerZIndex,
        afterStrokeLayerZIndex: this.strokeLayerZIndex
      };
    }

    const reorderResult = this.reorderLayerStack(`element:${elementId}`, action);
    const afterElement = this.getElementByIdFromList(reorderResult.elements, elementId);
    return {
      changed: reorderResult.changed,
      beforeElement: this.cloneElement(beforeElement),
      afterElement: afterElement === null ? null : this.cloneElement(afterElement),
      beforeStrokeLayerZIndex: this.strokeLayerZIndex,
      afterStrokeLayerZIndex: reorderResult.strokeLayerZIndex
    };
  }

  changeElementLayerById(elementId: string, action: LayerOrderAction): SelectionActionResult {
    const element = this.getElementById(elementId);
    if (element === null) {
      return { ...EMPTY_SELECTION_ACTION_RESULT };
    }

    const beforeSelection = this.getCurrentSelectionSnapshot();
    const beforeStrokeLayerZIndex = this.strokeLayerZIndex;
    const beforeElements = this.cloneElements(this.elements);
    const reorderResult = this.reorderLayerStack(`element:${elementId}`, action);
    if (!reorderResult.changed) {
      return { ...EMPTY_SELECTION_ACTION_RESULT };
    }

    this.elements = reorderResult.elements;
    this.strokeLayerZIndex = reorderResult.strokeLayerZIndex;
    const removedElements: IndexedElementRecord[] = [];
    const addedElements: IndexedElementRecord[] = [];
    for (let index = 0; index < beforeElements.length; index += 1) {
      const beforeElement = beforeElements[index];
      const afterElement = this.getElementByIdFromList(reorderResult.elements, beforeElement.id);
      if (afterElement !== null &&
        (beforeElement.zIndex !== afterElement.zIndex || !this.areElementsEquivalent(beforeElement, afterElement))) {
        removedElements.push({
          index,
          element: this.cloneElement(beforeElement)
        });
        addedElements.push({
          index,
          element: this.cloneElement(afterElement)
        });
      }
    }

    this.undoRedoController.recordDelta(
      [],
      [],
      'layer',
      removedElements,
      addedElements,
      beforeSelection,
      this.getCurrentSelectionSnapshot(),
      beforeStrokeLayerZIndex,
      this.strokeLayerZIndex
    );
    this.changeSequence += 1;
    this.persistenceStatus = 'pending layer save';
    this.schedulePersistCurrentStrokes('layer', 0);
    this.errorMessage = '';
    this.appendDebugEvent('layer', `element=${elementId} action=${action}`);
    return {
      changed: true,
      changedStrokes: beforeStrokeLayerZIndex !== this.strokeLayerZIndex,
      changedElements: removedElements.length > 0 || addedElements.length > 0,
      elementSelectionChanged: false
    };
  }

  beginLassoSelection(point: StrokePoint): void {
    if (this.pageId.length === 0) {
      return;
    }

    this.cancelStroke();
    this.cancelShapeDraft();
    this.clearEraseState();
    this.elementEditGesture = null;
    this.elementStyleEditGesture = null;
    this.imageElementEditDraft = null;
    this.selectionMoveGesture = null;
    this.strokeResizeGesture = null;
    this.lassoDraftPath = [this.clonePoint(point)];
    this.appendDebugEvent('lasso', `start x=${Math.round(point.x)} y=${Math.round(point.y)}`);
  }

  updateLassoSelection(point: StrokePoint): void {
    if (this.lassoDraftPath.length === 0) {
      return;
    }

    const lastPoint = this.lassoDraftPath[this.lassoDraftPath.length - 1];
    if (this.getPointDistance(lastPoint, point) < MIN_LASSO_POINT_DISTANCE) {
      return;
    }

    this.lassoDraftPath.push(this.clonePoint(point));
  }

  finishLassoSelection(hitTolerance: number = 0): boolean {
    if (this.lassoDraftPath.length < MIN_LASSO_POINT_COUNT) {
      this.cancelLassoSelection();
      return false;
    }

    const lassoPath = this.lassoDraftPath.map((point: StrokePoint): StrokePoint => this.clonePoint(point));
    this.lassoDraftPath = [];
    const selectedStrokes = this.getStrokesInsideLasso(lassoPath, hitTolerance);
    this.selectedStrokeTargets = this.buildStrokeSelectionTargets(selectedStrokes);
    this.selectedElementIds = this.getElementIdsInsideLasso(lassoPath);
    this.selectedElementId = this.selectedElementIds.length > 0 ? this.selectedElementIds[0] : '';
    this.elementEditGesture = null;
    this.elementStyleEditGesture = null;
    this.imageElementEditDraft = null;
    this.selectionVersion += 1;
    this.appendDebugEvent(
      'lasso',
      `finish strokes=${selectedStrokes.length} groups=${this.selectedStrokeTargets.length} elements=${this.selectedElementIds.length}`
    );
    return this.selectedStrokeTargets.length > 0 || this.selectedElementIds.length > 0;
  }

  cancelLassoSelection(): void {
    if (this.lassoDraftPath.length > 0) {
      this.appendDebugEvent('lasso', 'cancelled');
    }
    this.lassoDraftPath = [];
  }

  beginSelectionMove(point: StrokePoint): boolean {
    const originalStrokeRecords = this.getSelectedStrokeRecords();
    const originalElementRecords = this.getSelectedElementRecords();
    if (originalStrokeRecords.length === 0 && originalElementRecords.length === 0) {
      return false;
    }

    const selectionBounds = this.getSelectionBoundsFromRecords(originalStrokeRecords, originalElementRecords);
    if (selectionBounds === null) {
      return false;
    }

    this.cancelStroke();
    this.cancelShapeDraft();
    this.clearEraseState();
    this.lassoDraftPath = [];
    this.elementEditGesture = null;
    this.elementStyleEditGesture = null;
    this.imageElementEditDraft = null;
    this.selectionMoveGesture = {
      startPoint: this.clonePoint(point),
      currentOffsetX: 0,
      currentOffsetY: 0,
      originalStrokeRecords: originalStrokeRecords.map((record: IndexedStrokeRecord): IndexedStrokeRecord =>
        this.cloneIndexedStrokeRecord(record)),
      originalElementRecords: originalElementRecords.map((record: IndexedElementRecord): IndexedElementRecord =>
        this.cloneIndexedElementRecord(record)),
      originalTargets: this.cloneSelectionTargets(this.buildSelectionTargets()),
      selectionBounds
    };
    this.appendDebugEvent(
      'selectionMove',
      `start strokes=${originalStrokeRecords.length} elements=${originalElementRecords.length}`
    );
    return true;
  }

  applySelectionAction(action: SelectionAction, target: SelectionContextMenuTarget): SelectionActionResult {
    if (action === 'delete' && target === 'strokeGroup') {
      return this.deleteSelectedStrokeTargets();
    }

    if (action === 'copy' && target === 'strokeGroup') {
      return this.copySelectedStrokeTargets();
    }

    return { ...EMPTY_SELECTION_ACTION_RESULT };
  }

  updateSelectionMove(point: StrokePoint, bounds: ElementBounds): boolean {
    if (this.selectionMoveGesture === null) {
      return false;
    }

    const rawOffsetX = point.x - this.selectionMoveGesture.startPoint.x;
    const rawOffsetY = point.y - this.selectionMoveGesture.startPoint.y;
    const offsetX = this.clampSelectionMoveOffset(
      rawOffsetX,
      -this.selectionMoveGesture.selectionBounds.minX,
      bounds.width - this.selectionMoveGesture.selectionBounds.maxX
    );
    const offsetY = this.clampSelectionMoveOffset(
      rawOffsetY,
      -this.selectionMoveGesture.selectionBounds.minY,
      bounds.height - this.selectionMoveGesture.selectionBounds.maxY
    );

    if (offsetX === this.selectionMoveGesture.currentOffsetX && offsetY === this.selectionMoveGesture.currentOffsetY) {
      return false;
    }

    this.applySelectionMoveOffset(offsetX, offsetY);
    return true;
  }

  finishSelectionMove(): boolean {
    if (this.selectionMoveGesture === null) {
      return false;
    }

    const gesture = this.selectionMoveGesture;
    this.selectionMoveGesture = null;
    if (gesture.currentOffsetX === 0 && gesture.currentOffsetY === 0) {
      this.appendDebugEvent('selectionMove', 'finish noChange');
      return false;
    }

    const movedStrokeRecords = this.translateStrokeRecords(
      gesture.originalStrokeRecords,
      gesture.currentOffsetX,
      gesture.currentOffsetY
    );
    const movedElementRecords = this.translateElementRecords(
      gesture.originalElementRecords,
      gesture.currentOffsetX,
      gesture.currentOffsetY
    );
    this.undoRedoController.recordDelta(
      gesture.originalStrokeRecords,
      movedStrokeRecords,
      'move',
      gesture.originalElementRecords,
      movedElementRecords,
      this.getSelectionSnapshotFromTargets(gesture.originalTargets),
      this.getCurrentSelectionSnapshot()
    );
    this.markPartialRenderInvalidation('move', gesture.originalStrokeRecords, movedStrokeRecords);
    this.changeSequence += 1;
    this.persistenceStatus = 'pending selection move save';
    this.schedulePersistCurrentStrokes('selectionMove', 0);
    this.errorMessage = '';
    this.appendDebugEvent(
      'selectionMove',
      `finish dx=${Math.round(gesture.currentOffsetX)} dy=${Math.round(gesture.currentOffsetY)}`
    );
    return true;
  }

  cancelSelectionMove(): void {
    if (this.selectionMoveGesture === null) {
      return;
    }

    const gesture = this.selectionMoveGesture;
    this.selectionMoveGesture = null;
    this.replaceStrokeRecordsInMemory(gesture.originalStrokeRecords);
    this.replaceElementRecordsInMemory(gesture.originalElementRecords);
    this.applyMovedStrokeRecordsToSpatialIndex(gesture.originalStrokeRecords);
    this.selectedStrokeTargets = this.getStrokeTargetsFromTargets(gesture.originalTargets);
    this.selectedElementIds = this.getElementIdsFromTargets(gesture.originalTargets);
    this.selectedElementId = this.selectedElementIds.length > 0 ? this.selectedElementIds[0] : '';
    this.selectionVersion += 1;
    this.appendDebugEvent('selectionMove', 'cancelled');
  }

  beginStrokeResizeMode(): BoundingBox | null {
    const resizeBounds = this.getSelectedStrokeResizeBounds();
    if (resizeBounds === null) {
      return null;
    }

    const hadElementSelection = this.selectedElementIds.length > 0;
    this.cancelStroke();
    this.cancelShapeDraft();
    this.clearEraseState();
    this.cancelSelectionMove();
    this.cancelElementEditGesture();
    this.selectedElementId = '';
    this.selectedElementIds = [];
    this.lassoDraftPath = [];
    this.elementEditGesture = null;
    this.elementStyleEditGesture = null;
    this.imageElementEditDraft = null;
    if (hadElementSelection) {
      this.selectionVersion += 1;
    }
    this.appendDebugEvent('strokeResize', 'mode start');
    return resizeBounds;
  }

  beginStrokeResize(handle: ResizeHandle): boolean {
    const originalStrokeRecords = this.getSelectedStrokeRecords();
    if (originalStrokeRecords.length === 0) {
      return false;
    }

    const originalBounds = this.getSelectionBoundsFromTargets(this.selectedStrokeTargets);
    if (originalBounds === null ||
      originalBounds.maxX - originalBounds.minX <= 0 ||
      originalBounds.maxY - originalBounds.minY <= 0) {
      return false;
    }

    this.cancelStroke();
    this.cancelShapeDraft();
    this.clearEraseState();
    this.lassoDraftPath = [];
    this.elementEditGesture = null;
    this.elementStyleEditGesture = null;
    this.imageElementEditDraft = null;
    this.selectionMoveGesture = null;
    this.strokeResizeGesture = {
      handle,
      currentBounds: this.cloneBoundingBox(originalBounds),
      originalBounds: this.cloneBoundingBox(originalBounds),
      originalStrokeRecords: originalStrokeRecords.map((record: IndexedStrokeRecord): IndexedStrokeRecord =>
        this.cloneIndexedStrokeRecord(record)),
      originalTargets: this.cloneSelectionTargets(this.selectedStrokeTargets)
    };
    this.appendDebugEvent('strokeResize', `start handle=${handle} strokes=${originalStrokeRecords.length}`);
    return true;
  }

  updateStrokeResize(point: StrokePoint, bounds: ElementBounds): boolean {
    if (this.strokeResizeGesture === null) {
      return false;
    }

    const nextBounds = this.buildStrokeResizeBounds(
      this.strokeResizeGesture.originalBounds,
      this.strokeResizeGesture.handle,
      point,
      bounds
    );
    if (this.areBoundingBoxesEquivalent(nextBounds, this.strokeResizeGesture.currentBounds)) {
      return false;
    }

    this.applyStrokeResizeBounds(nextBounds);
    return true;
  }

  finishStrokeResize(): boolean {
    if (this.strokeResizeGesture === null) {
      return false;
    }

    const gesture = this.strokeResizeGesture;
    this.strokeResizeGesture = null;
    if (this.areBoundingBoxesEquivalent(gesture.originalBounds, gesture.currentBounds)) {
      this.replaceStrokeRecordsInMemory(gesture.originalStrokeRecords);
      this.applyMovedStrokeRecordsToSpatialIndex(gesture.originalStrokeRecords);
      this.selectedStrokeTargets = this.cloneSelectionTargets(gesture.originalTargets);
      this.selectionVersion += 1;
      this.appendDebugEvent('strokeResize', 'finish noChange');
      return false;
    }

    const resizedStrokeRecords = this.scaleStrokeRecords(
      gesture.originalStrokeRecords,
      gesture.originalBounds,
      gesture.currentBounds
    );
    this.undoRedoController.recordDelta(
      gesture.originalStrokeRecords,
      resizedStrokeRecords,
      'resize',
      [],
      [],
      this.getSelectionSnapshotFromTargets(gesture.originalTargets),
      this.getCurrentSelectionSnapshot()
    );
    this.markPartialRenderInvalidation('resize', gesture.originalStrokeRecords, resizedStrokeRecords);
    this.changeSequence += 1;
    this.persistenceStatus = 'pending stroke resize save';
    this.schedulePersistCurrentStrokes('strokeResize', 0);
    this.errorMessage = '';
    this.appendDebugEvent('strokeResize', 'finish');
    return true;
  }

  cancelStrokeResize(): void {
    if (this.strokeResizeGesture === null) {
      return;
    }

    const gesture = this.strokeResizeGesture;
    this.strokeResizeGesture = null;
    this.replaceStrokeRecordsInMemory(gesture.originalStrokeRecords);
    this.applyMovedStrokeRecordsToSpatialIndex(gesture.originalStrokeRecords);
    this.selectedStrokeTargets = this.cloneSelectionTargets(gesture.originalTargets);
    this.selectionVersion += 1;
    this.appendDebugEvent('strokeResize', 'cancelled');
  }

  beginElementEditGesture(point: StrokePoint, bounds: ElementBounds, hitTolerance: number): boolean {
    if (this.pageId.length === 0) {
      return false;
    }

    this.cancelStroke();
    this.cancelShapeDraft();
    this.cancelSelectionMove();
    this.imageElementEditDraft = null;

    const selectedElements = this.getSelectedElementsInZOrderDescending();
    for (const selectedElement of selectedElements) {
      const handleKind = this.hitTestElementEditHandle(point, selectedElement, hitTolerance);
      if (handleKind !== null) {
        this.selectedElementId = selectedElement.id;
        this.elementEditGesture = {
          elementId: selectedElement.id,
          kind: handleKind,
          startPoint: this.clonePoint(point),
          originalElement: this.cloneElement(selectedElement)
        };
        this.beginImageElementEditDraft(selectedElement);
        this.appendDebugEvent('beginElementEdit', `element=${selectedElement.id} kind=${handleKind}`);
        return true;
      }
    }

    const hitElement = this.hitTestElement(point);
    if (hitElement === null) {
      this.clearElementSelection();
      this.appendDebugEvent('beginElementEdit', `empty x=${Math.round(point.x)} y=${Math.round(point.y)}`);
      return false;
    }

    this.activateHitElementSelection(hitElement);
    this.elementEditGesture = {
      elementId: hitElement.id,
      kind: 'move',
      startPoint: this.clonePoint(point),
      originalElement: this.cloneElement(hitElement)
    };
    this.beginImageElementEditDraft(hitElement);
    this.appendDebugEvent('beginElementEdit', `element=${hitElement.id} kind=move`);
    return true;
  }

  private activateHitElementSelection(hitElement: CanvasElement): void {
    const wasAlreadySelected = this.selectedElementIds.includes(hitElement.id);
    this.selectedElementId = hitElement.id;
    if (wasAlreadySelected) {
      return;
    }

    this.selectedElementIds = [hitElement.id];
    this.selectedStrokeTargets = [];
    this.selectionVersion += 1;
  }

  updateElementEditGesture(point: StrokePoint, bounds: ElementBounds): boolean {
    if (this.elementEditGesture === null) {
      return false;
    }

    const nextElement = this.buildElementFromEditGesture(this.elementEditGesture, point, bounds);
    if (nextElement === null) {
      return false;
    }

    if (this.elementEditGesture.originalElement.type === 'image' && nextElement.type === 'image') {
      const nextFrame = this.getElementFrame(nextElement);
      if (this.imageElementEditDraft !== null &&
        this.areElementFramesEquivalent(this.imageElementEditDraft.currentFrame, nextFrame)) {
        return false;
      }
      this.imageElementEditDraft = {
        elementId: nextElement.id,
        originalFrame: this.imageElementEditDraft === null ?
          this.getElementFrame(this.elementEditGesture.originalElement) :
          this.cloneElementFrame(this.imageElementEditDraft.originalFrame),
        currentFrame: nextFrame
      };
      return true;
    }

    this.replaceElementInMemory(nextElement);
    return true;
  }

  finishElementEditGesture(bounds: ElementBounds): CanvasElement | null {
    if (this.elementEditGesture === null) {
      return null;
    }

    const gesture = this.elementEditGesture;
    this.elementEditGesture = null;
    if (gesture.originalElement.type === 'image') {
      const draft = this.imageElementEditDraft;
      this.imageElementEditDraft = null;
      if (draft === null || draft.elementId !== gesture.elementId ||
        this.areElementFramesEquivalent(draft.originalFrame, draft.currentFrame)) {
        return null;
      }

      const finalElement = this.cloneElementWithFrame(gesture.originalElement, draft.currentFrame);
      this.replaceElementInMemory(finalElement);
      this.selectedElementId = finalElement.id;
      const elementIndex = this.getElementIndexById(finalElement.id);
      this.recordElementDelta('elementEdit', [{
        index: elementIndex,
        element: this.cloneElement(gesture.originalElement)
      }], [{
        index: elementIndex,
        element: this.cloneElement(finalElement)
      }]);
      this.changeSequence += 1;
      this.persistenceStatus = 'pending element edit save';
      this.schedulePersistCurrentStrokes('elementEdit', 0);
      this.errorMessage = '';
      this.appendDebugEvent('finishElementEdit', `element=${finalElement.id} kind=${gesture.kind}`);
      return this.cloneElement(finalElement);
    }

    const editedElement = this.getElementById(gesture.elementId);
    if (editedElement === null || this.areElementsEquivalent(gesture.originalElement, editedElement)) {
      return null;
    }

    this.selectedElementId = editedElement.id;
    const elementIndex = this.getElementIndexById(editedElement.id);
    this.recordElementDelta('elementEdit', [{
      index: elementIndex,
      element: this.cloneElement(gesture.originalElement)
    }], [{
      index: elementIndex,
      element: this.cloneElement(editedElement)
    }]);
    this.changeSequence += 1;
    this.persistenceStatus = 'pending element edit save';
    this.schedulePersistCurrentStrokes('elementEdit', 0);
    this.errorMessage = '';
    this.appendDebugEvent('finishElementEdit', `element=${editedElement.id} kind=${gesture.kind}`);
    return this.cloneElement(editedElement);
  }

  cancelElementEditGesture(): void {
    if (this.elementEditGesture === null) {
      return;
    }

    const originalElement = this.cloneElement(this.elementEditGesture.originalElement);
    this.replaceElementInMemory(originalElement);
    this.selectedElementId = originalElement.id;
    this.appendDebugEvent('cancelElementEdit', `element=${originalElement.id}`);
    this.elementEditGesture = null;
    this.elementStyleEditGesture = null;
    this.imageElementEditDraft = null;
  }

  insertTextElement(point: StrokePoint, bounds: ElementBounds): TextCanvasElement | null {
    if (this.pageId.length === 0) {
      this.errorMessage = 'Page is not loaded.';
      return null;
    }

    this.cancelStroke();
    const timestamp = now();
    const fontSize = 18;
    const textSize = this.buildDefaultTextElementSize(fontSize);
    const frame: ElementFrame = clampElementFrameToBounds({
      x: point.x - textSize.width / 2,
      y: point.y - DEFAULT_TEXT_ELEMENT_TOP_OFFSET,
      width: textSize.width,
      height: textSize.height
    }, bounds);
    const nextElement: TextCanvasElement = {
      id: createId('text'),
      pageId: this.pageId,
      type: 'text',
      x: frame.x,
      y: frame.y,
      width: frame.width,
      height: frame.height,
      rotation: 0,
      zIndex: this.getNextElementZIndex(),
      createdAt: timestamp,
      updatedAt: timestamp,
      content: 'Text',
      color: this.toolSetting.color,
      fontSize,
      backgroundColor: TRANSPARENT_ELEMENT_BACKGROUND_COLOR,
      outline: { ...DEFAULT_TEXT_OUTLINE }
    };

    const insertionIndex = this.elements.length;
    this.elements = [...this.elements, nextElement];
    this.recordElementDelta('elementInsert', [], [{
      index: insertionIndex,
      element: this.cloneElement(nextElement)
    }]);
    this.changeSequence += 1;
    this.persistenceStatus = 'pending text save';
    this.schedulePersistCurrentStrokes('text', 0);
    this.errorMessage = '';
    this.appendDebugEvent('insertText', `element=${nextElement.id} x=${Math.round(nextElement.x)} y=${Math.round(nextElement.y)}`);
    return this.cloneTextElement(nextElement);
  }

  insertImageElement(asset: ImageInsertAsset, bounds: ElementBounds): ImageCanvasElement | null {
    if (this.pageId.length === 0) {
      this.errorMessage = 'Page is not loaded.';
      return null;
    }

    if (asset.uri.length === 0 || asset.originalWidth <= 0 || asset.originalHeight <= 0) {
      this.errorMessage = 'Image asset is invalid.';
      return null;
    }

    this.cancelStroke();
    this.cancelShapeDraft();
    const timestamp = now();
    const displaySize = this.calculateInitialImageDisplaySize(asset, bounds);
    const frame: ElementFrame = clampElementFrameToBounds({
      x: (Math.max(1, bounds.width) - displaySize.width) / 2,
      y: (Math.max(1, bounds.height) - displaySize.height) / 2,
      width: displaySize.width,
      height: displaySize.height
    }, bounds);
    const nextElement: ImageCanvasElement = {
      id: createId('image'),
      pageId: this.pageId,
      type: 'image',
      x: frame.x,
      y: frame.y,
      width: frame.width,
      height: frame.height,
      rotation: 0,
      zIndex: this.getNextElementZIndex(),
      createdAt: timestamp,
      updatedAt: timestamp,
      uri: asset.uri,
      originalWidth: asset.originalWidth,
      originalHeight: asset.originalHeight,
      opacity: 1,
      outline: { ...DEFAULT_IMAGE_OUTLINE }
    };

    const insertionIndex = this.elements.length;
    this.elements = [...this.elements, nextElement];
    this.recordElementDelta('elementInsert', [], [{
      index: insertionIndex,
      element: this.cloneElement(nextElement)
    }]);
    this.changeSequence += 1;
    this.persistenceStatus = 'pending image save';
    this.schedulePersistCurrentStrokes('image', 0);
    this.errorMessage = '';
    this.appendDebugEvent(
      'insertImage',
      `element=${nextElement.id} x=${Math.round(nextElement.x)} y=${Math.round(nextElement.y)}`
    );
    return this.cloneImageElement(nextElement);
  }

  beginShapeDraft(point: StrokePoint, bounds: ElementBounds, shapeType: ShapeType): void {
    if (this.pageId.length === 0) {
      this.errorMessage = 'Page is not loaded.';
      return;
    }

    this.cancelStroke();
    const clampedPoint = this.clampPointToBounds(point, bounds);
    this.shapeDraft = {
      shapeType,
      startPoint: clampedPoint,
      currentPoint: clampedPoint
    };
    this.errorMessage = '';
    this.appendDebugEvent(
      'beginShapeDraft',
      `shape=${shapeType} x=${Math.round(clampedPoint.x)} y=${Math.round(clampedPoint.y)}`
    );
  }

  updateShapeDraft(point: StrokePoint, bounds: ElementBounds): void {
    if (this.shapeDraft === null) {
      return;
    }

    this.shapeDraft = {
      shapeType: this.shapeDraft.shapeType,
      startPoint: this.clonePoint(this.shapeDraft.startPoint),
      currentPoint: this.clampPointToBounds(point, bounds)
    };
  }

  commitShapeDraft(bounds: ElementBounds): ShapeCanvasElement | null {
    if (this.pageId.length === 0) {
      this.errorMessage = 'Page is not loaded.';
      this.shapeDraft = null;
      return null;
    }

    if (this.shapeDraft === null) {
      return null;
    }

    const draft = this.shapeDraft;
    this.shapeDraft = null;

    const nextElement = this.buildShapeElementFromDraft(draft, bounds, 1, true);
    if (nextElement === null) {
      this.appendDebugEvent('commitShapeDraft', `cancelled shape=${draft.shapeType} reason=tooSmall`);
      return null;
    }

    const insertionIndex = this.elements.length;
    this.elements = [...this.elements, nextElement];
    this.recordElementDelta('elementInsert', [], [{
      index: insertionIndex,
      element: this.cloneElement(nextElement)
    }]);
    this.changeSequence += 1;
    this.persistenceStatus = 'pending shape save';
    this.schedulePersistCurrentStrokes('shape', 0);
    this.errorMessage = '';
    this.appendDebugEvent(
      'commitShapeDraft',
      `element=${nextElement.id} shape=${draft.shapeType} x=${Math.round(nextElement.x)} y=${Math.round(nextElement.y)}`
    );
    return this.cloneShapeElement(nextElement);
  }

  cancelShapeDraft(): void {
    if (this.shapeDraft !== null) {
      this.appendDebugEvent('cancelShapeDraft', `shape=${this.shapeDraft.shapeType}`);
    }
    this.shapeDraft = null;
  }

  getShapeDraftForRendering(): ShapeCanvasElement | null {
    if (this.shapeDraft === null) {
      return null;
    }

    return this.buildShapeElementFromDraft(this.shapeDraft, {
      width: Number.MAX_SAFE_INTEGER,
      height: Number.MAX_SAFE_INTEGER
    }, 0.65, false);
  }

  private buildShapeElementFromDraft(
    draft: ShapeDraft,
    bounds: ElementBounds,
    opacity: number,
    enforceMinimumSize: boolean
  ): ShapeCanvasElement | null {
    const startPoint = this.clampPointToBounds(draft.startPoint, bounds);
    const currentPoint = this.clampPointToBounds(draft.currentPoint, bounds);
    const frame = this.buildShapeFrameFromPoints(draft.shapeType, startPoint, currentPoint);
    if (enforceMinimumSize && !this.isValidShapeFrame(draft.shapeType, frame, startPoint, currentPoint)) {
      return null;
    }

    if (!enforceMinimumSize && !this.hasVisibleShapeFrame(draft.shapeType, frame, startPoint, currentPoint)) {
      return null;
    }

    const timestamp = now();
    return {
      id: createId('shape'),
      pageId: this.pageId,
      type: 'shape',
      x: frame.x,
      y: frame.y,
      width: frame.width,
      height: frame.height,
      rotation: 0,
      zIndex: this.getNextElementZIndex(),
      createdAt: timestamp,
      updatedAt: timestamp,
      shapeType: draft.shapeType,
      geometry: this.buildShapeGeometry(draft.shapeType, startPoint, currentPoint),
      fillColor: TRANSPARENT_ELEMENT_BACKGROUND_COLOR,
      outline: { ...DEFAULT_SHAPE_OUTLINE },
      opacity
    };
  }

  updateTextElementContentWithFrame(
    elementId: string,
    content: string,
    frame: ElementFrame
  ): TextCanvasElement | null {
    if (this.pageId.length === 0 || elementId.length === 0) {
      return null;
    }

    let changed = false;
    let originalTextElement: TextCanvasElement | null = null;
    let updatedTextElement: TextCanvasElement | null = null;
    const timestamp = now();
    this.elements = this.elements.map((element: CanvasElement): CanvasElement => {
      if (element.id !== elementId || element.type !== 'text') {
        return element;
      }

      const frameChanged = element.x !== frame.x || element.y !== frame.y ||
        element.width !== frame.width || element.height !== frame.height;
      if (element.content === content && !frameChanged) {
        updatedTextElement = this.cloneTextElement(element);
        return element;
      }

      changed = true;
      originalTextElement = this.cloneTextElement(element);
      const nextElement: TextCanvasElement = {
        id: element.id,
        pageId: element.pageId,
        type: 'text',
        x: frame.x,
        y: frame.y,
        width: frame.width,
        height: frame.height,
        rotation: element.rotation,
        zIndex: element.zIndex,
        createdAt: element.createdAt,
        content,
        color: element.color,
        fontSize: element.fontSize,
        backgroundColor: element.backgroundColor,
        outline: this.cloneElementOutline(element.outline ?? DEFAULT_TEXT_OUTLINE),
        updatedAt: timestamp
      };
      updatedTextElement = this.cloneTextElement(nextElement);
      return nextElement;
    });

    if (!changed) {
      return null;
    }

    if (originalTextElement !== null && updatedTextElement !== null) {
      const elementIndex = this.getElementIndexById(elementId);
      this.recordElementDelta('textEdit', [{
        index: elementIndex,
        element: this.cloneElement(originalTextElement)
      }], [{
        index: elementIndex,
        element: this.cloneElement(updatedTextElement)
      }]);
    }
    this.changeSequence += 1;
    this.persistenceStatus = 'pending text edit save';
    this.schedulePersistCurrentStrokes('textEdit', 0);
    this.errorMessage = '';
    this.appendDebugEvent('textEdit', `element=${elementId} length=${content.length}`);
    return updatedTextElement;
  }

  insertRecognizedTextElement(
    content: string,
    frame: ElementFrame,
    bounds: ElementBounds,
    options: InsertRecognizedTextOptions = {}
  ): TextCanvasElement | null {
    if (this.pageId.length === 0) {
      this.errorMessage = 'Page is not loaded.';
      return null;
    }

    const normalizedContent = content.trim();
    if (normalizedContent.length === 0) {
      this.errorMessage = 'Recognition result is empty.';
      return null;
    }

    const timestamp = now();
    const clampedFrame = clampElementFrameToBounds(frame, bounds);
    const fontSize = Math.max(16, Math.min(28, Math.round(clampedFrame.height / 4)));
    const nextElement: TextCanvasElement = {
      id: createId('text'),
      pageId: this.pageId,
      type: 'text',
      x: clampedFrame.x,
      y: clampedFrame.y,
      width: clampedFrame.width,
      height: clampedFrame.height,
      rotation: 0,
      zIndex: this.getNextElementZIndex(),
      createdAt: timestamp,
      updatedAt: timestamp,
      content: normalizedContent,
      color: '#111827',
      fontSize,
      backgroundColor: TRANSPARENT_ELEMENT_BACKGROUND_COLOR,
      outline: { ...DEFAULT_TEXT_OUTLINE },
      recognition: options.recognition
    };

    const insertionIndex = this.elements.length;
    this.elements = [...this.elements, nextElement];
    this.selectedStrokeTargets = [];
    this.selectedElementIds = [nextElement.id];
    this.selectedElementId = nextElement.id;
    this.selectionVersion += 1;
    this.recordElementDelta('elementInsert', [], [{
      index: insertionIndex,
      element: this.cloneElement(nextElement)
    }]);
    this.changeSequence += 1;
    this.persistenceStatus = 'pending recognition text save';
    this.schedulePersistCurrentStrokes('recognitionText', 0);
    this.errorMessage = '';
    const recognitionEventSource = options.recognition?.source === 'ocr' ? 'ocrRecognition' : 'formulaRecognition';
    this.appendDebugEvent(
      recognitionEventSource,
      `element=${nextElement.id} length=${normalizedContent.length} x=${Math.round(nextElement.x)} y=${Math.round(nextElement.y)}`
    );
    return this.cloneTextElement(nextElement);
  }

  getActiveStroke(): Stroke | null {
    return this.strokeController.getActiveStroke();
  }

  getActiveStrokeForRendering(): Stroke | null {
    return this.strokeController.getActiveStrokeForRendering();
  }

  getActiveErasePath(): StrokePoint[] {
    return this.activeErasePath.map((point: StrokePoint) => this.clonePoint(point));
  }

  getErasePreviewWidth(): number {
    return this.toolSetting.width;
  }

  hasActiveEraseGesture(): boolean {
    return this.eraseSourceStrokes !== null;
  }

  canUndo(): boolean {
    return this.undoRedoController.canUndo();
  }

  canRedo(): boolean {
    return this.undoRedoController.canRedo();
  }

  getErrorMessage(): string {
    return this.errorMessage;
  }

  getDebugSnapshot(): EditorDebugSnapshot {
    const historyState = this.undoRedoController.getDebugState();
    const activeStroke = this.strokeController.getActiveStroke();

    return {
      instanceId: this.instanceId,
      pageId: this.pageId,
      toolSetting: this.getToolSetting(),
      strokeCount: this.strokes.length,
      elementCount: this.elements.length,
      selectedElementId: this.selectedElementId,
      activeStrokeStyle: activeStroke ? this.cloneStyle(activeStroke.style) : null,
      undoDepth: historyState.undoDepth,
      redoDepth: historyState.redoDepth,
      recentEvents: [...this.debugEvents],
      errorMessage: this.errorMessage,
      persistenceStatus: this.persistenceStatus
    };
  }

  appendDebugEvent(source: string, message: string): void {
    const entry = `${this.nextDebugSequence()} [vm=${this.instanceId}] [${source}] ${message}`;
    this.debugEvents = [...this.debugEvents.slice(-(MAX_DEBUG_EVENTS - 1)), entry];
    console.info(`[EditorDebug] ${entry}`);
  }

  isPageLoading(): boolean {
    return this.isLoading;
  }

  isLoadedForPage(pageId: string): boolean {
    return this.pageId === pageId && this.hasLoadedPageSnapshot;
  }

  getRenderInvalidation(): RenderInvalidation | null {
    if (this.lastRenderInvalidation === null) {
      return null;
    }

    return this.cloneRenderInvalidation(this.lastRenderInvalidation);
  }

  async flushPendingSave(): Promise<void> {
    const hadScheduledSave: boolean = this.saveTimerId >= 0;
    this.clearScheduledSave();
    if (!hadScheduledSave &&
      !this.isPersisting &&
      !this.hasQueuedPersistence &&
      this.changeSequence === this.lastPersistedChangeSequence) {
      return;
    }
    await this.persistCurrentStrokes('flush');
  }

  requestDeferredSave(reason: string = 'deferred'): void {
    if (this.pageId.length === 0) {
      return;
    }

    if (!this.isPersisting &&
      !this.hasQueuedPersistence &&
      this.saveTimerId < 0 &&
      this.changeSequence === this.lastPersistedChangeSequence) {
      return;
    }

    this.schedulePersistCurrentStrokes(reason, INTERACTION_SAVE_DEBOUNCE_MS);
  }

  private beginErase(point: StrokePoint): void {
    this.strokeController.cancelStroke();
    this.activeErasePath = [this.clonePoint(point)];
    this.eraseSourceStrokes = this.cloneStrokes(this.strokes);
    this.appendDebugEvent('erase', `start width=${this.toolSetting.width} sourceCount=${this.strokes.length}`);
  }

  private appendErasePoint(point: StrokePoint): void {
    if (!this.eraseSourceStrokes) {
      return;
    }

    const lastPoint = this.activeErasePath[this.activeErasePath.length - 1];
    if (lastPoint && isSamePoint(lastPoint, point)) {
      return;
    }

    this.activeErasePath.push(this.clonePoint(point));
  }

  private async finishErase(): Promise<Stroke | null> {
    if (!this.eraseSourceStrokes) {
      return null;
    }

    const sourceSnapshot = this.cloneStrokes(this.eraseSourceStrokes);
    const erasePath = this.activeErasePath.map((point: StrokePoint) => this.clonePoint(point));
    const eraseResult = EditorPerformanceTrace.measureSync(
      'erase.diff',
      () => this.eraseStrokes(sourceSnapshot, erasePath),
      `sourceStrokes=${sourceSnapshot.length} sourcePoints=${this.countStrokePoints(sourceSnapshot)} pathPoints=${erasePath.length}`,
      10
    );
    this.clearEraseState();

    if (!eraseResult.changed) {
      this.strokes = sourceSnapshot;
      this.appendDebugEvent('erase', 'finish noChange');
      return null;
    }

    const applyStartedAt = Date.now();
    const beforeSelection = this.getCurrentSelectionSnapshot();
    this.strokes = eraseResult.strokes;
    this.clearStrokeSelection();
    this.lassoDraftPath = [];
    this.applyStrokeSpatialIndexMutation(eraseResult.removed, eraseResult.added);
    this.undoRedoController.recordDelta(
      eraseResult.removed,
      eraseResult.added,
      'erase',
      [],
      [],
      beforeSelection,
      this.getCurrentSelectionSnapshot()
    );
    this.markPartialRenderInvalidation('erase', eraseResult.removed, eraseResult.added);
    this.changeSequence += 1;
    this.persistenceStatus = 'pending erase save';
    this.schedulePersistCurrentStrokes('erase');
    this.errorMessage = '';
    this.appendDebugEvent('erase', `queuedSave count=${this.strokes.length} history=${this.describeHistoryState()}`);
    EditorPerformanceTrace.record(
      'erase.apply',
      Date.now() - applyStartedAt,
      `afterStrokes=${this.strokes.length} afterPoints=${this.countStrokePoints(this.strokes)} removed=${eraseResult.removed.length} added=${eraseResult.added.length}`,
      8
    );

    return null;
  }

  private cancelErase(): void {
    this.clearEraseState();
    this.appendDebugEvent('erase', 'cancelled');
  }

  private clearEraseState(): void {
    this.activeErasePath = [];
    this.eraseSourceStrokes = null;
  }

  private resetTransientState(): void {
    this.strokeController.cancelStroke();
    this.clearEraseState();
    this.shapeDraft = null;
    this.selectionMoveGesture = null;
    this.clearSelectionState();
    this.lassoDraftPath = [];
  }

  private clearStrokeSelection(): void {
    this.selectedStrokeTargets = [];
    this.selectionVersion += 1;
  }

  private clearSelectionState(): void {
    this.elementEditGesture = null;
    this.elementStyleEditGesture = null;
    this.imageElementEditDraft = null;
    this.selectionMoveGesture = null;
    this.selectedElementId = '';
    this.selectedElementIds = [];
    this.selectedStrokeTargets = [];
    this.selectionVersion += 1;
  }

  private hasUndoRedoChanges(result: UndoRedoApplyResult): boolean {
    return result.removed.length > 0 || result.added.length > 0 ||
      result.removedElements.length > 0 || result.addedElements.length > 0 ||
      result.strokeLayerZIndex !== null;
  }

  private schedulePersistCurrentStrokes(reason: string, delayMs: number = SAVE_DEBOUNCE_MS): void {
    this.queuedPersistenceReason = reason;

    if (this.saveTimerId >= 0) {
      clearTimeout(this.saveTimerId);
    }

    this.saveTimerId = setTimeout(() => {
      this.saveTimerId = -1;
      void this.persistCurrentStrokes(this.queuedPersistenceReason);
    }, Math.max(0, delayMs));
  }

  private clearScheduledSave(): void {
    if (this.saveTimerId < 0) {
      return;
    }

    clearTimeout(this.saveTimerId);
    this.saveTimerId = -1;
  }

  private async persistCurrentStrokes(reason: string): Promise<void> {
    if (this.pageId.length === 0) {
      return;
    }

    if (this.isPersisting) {
      this.hasQueuedPersistence = true;
      this.queuedPersistenceReason = reason;
      return;
    }

    if (this.changeSequence === this.lastPersistedChangeSequence) {
      return;
    }

    this.isPersisting = true;
    const strokeSnapshot = this.cloneStrokes(this.strokes);
    const elementSnapshot = this.cloneElements(this.elements);
    const strokeLayerZIndexSnapshot = this.strokeLayerZIndex;
    const snapshotChangeSequence: number = this.changeSequence;
    this.persistenceStatus = `saving ${reason}`;
    const snapshotPointCount = this.countStrokePoints(strokeSnapshot);

    try {
      await EditorPerformanceTrace.measureAsync(
        'persist.pageContent',
        async () => {
          await this.createRepository().savePageContent(this.pageId, {
            version: PAGE_CANVAS_CONTENT_VERSION,
            strokes: strokeSnapshot,
            elements: elementSnapshot,
            strokeLayerZIndex: strokeLayerZIndexSnapshot
          });
        },
        `reason=${reason} strokes=${strokeSnapshot.length} points=${snapshotPointCount} elements=${elementSnapshot.length}`,
        20
      );
      this.lastPersistedChangeSequence = Math.max(this.lastPersistedChangeSequence, snapshotChangeSequence);
      this.errorMessage = '';
      this.persistenceStatus = `saved ${reason} strokes=${strokeSnapshot.length} elements=${elementSnapshot.length}`;
      this.appendDebugEvent(
        'persist',
        `saved reason=${reason} strokes=${strokeSnapshot.length} elements=${elementSnapshot.length}`
      );
    } catch (error) {
      this.errorMessage = this.stringifyError(error);
      this.persistenceStatus = `saveFailed reason=${reason} keepMemory count=${this.strokes.length}`;
      this.appendDebugEvent('persist', `failed reason=${reason} error=${this.errorMessage}`);
    } finally {
      this.isPersisting = false;
      if (this.hasQueuedPersistence) {
        const queuedReason = this.queuedPersistenceReason;
        this.hasQueuedPersistence = false;
        void this.persistCurrentStrokes(queuedReason);
      }
    }
  }

  private eraseStrokes(sourceStrokes: Stroke[], eraserPath: StrokePoint[]): EraseResult {
    const eraserBounds = getBoundingBox(eraserPath);
    if (!eraserBounds) {
      return {
        strokes: this.cloneStrokes(sourceStrokes),
        changed: false,
        removed: [],
        added: []
      };
    }

    const result: Stroke[] = [];
    let changed = false;
    const removed: IndexedStrokeRecord[] = [];
    const added: IndexedStrokeRecord[] = [];
    const expandedEraserBounds = expandBoundingBox(eraserBounds, this.toolSetting.width / 2);
    const candidateStrokeIds = new Set<string>(this.strokeSpatialIndex.queryStrokeIds(expandedEraserBounds));
    if (candidateStrokeIds.size === 0) {
      return {
        strokes: sourceStrokes,
        changed: false,
        removed: [],
        added: []
      };
    }

    const updateTime = now();

    for (let strokeIndex = 0; strokeIndex < sourceStrokes.length; strokeIndex += 1) {
      const stroke = sourceStrokes[strokeIndex];
      if (!candidateStrokeIds.has(stroke.id)) {
        result.push(stroke);
        continue;
      }

      const strokeBounds = getBoundingBox(stroke.points);
      if (!strokeBounds) {
        continue;
      }

      const expandedStrokeBounds = expandBoundingBox(strokeBounds, stroke.style.width / 2);
      if (!doBoundingBoxesIntersect(expandedEraserBounds, expandedStrokeBounds)) {
        result.push(stroke);
        continue;
      }

      const effectiveRadius = Math.max(1, this.toolSetting.width / 2 + stroke.style.width / 2);
      const samplingStep = Math.max(1, Math.min(this.toolSetting.width, stroke.style.width) / 2);
      const remainingSegments = eraseStrokePointsWithPath(stroke.points, eraserPath, effectiveRadius, samplingStep);

      if (remainingSegments.length === 1 && this.arePointListsEqual(remainingSegments[0].points, stroke.points)) {
        result.push(stroke);
        continue;
      }

      changed = true;
      removed.push({
        index: strokeIndex,
        stroke: this.cloneStroke(stroke)
      });

      const insertionStartIndex = result.length;
      for (let segmentIndex = 0; segmentIndex < remainingSegments.length; segmentIndex += 1) {
        const segment: ErasedStrokeSegment = remainingSegments[segmentIndex];
        const nextStroke: Stroke = {
          id: this.buildDerivedStrokeId(stroke.id, segmentIndex, updateTime),
          pageId: stroke.pageId,
          renderKey: stroke.renderKey ?? stroke.id,
          renderWarmupPoints: segment.renderWarmupPoints.map((point: StrokePoint) => this.clonePoint(point)),
          points: segment.points.map((point: StrokePoint) => this.clonePoint(point)),
          style: this.cloneStyle(stroke.style),
          createdAt: stroke.createdAt,
          updatedAt: updateTime
        };
        result.push(nextStroke);
        added.push({
          index: insertionStartIndex + segmentIndex,
          stroke: this.cloneStroke(nextStroke)
        });
      }
    }

    return {
      strokes: result,
      changed,
      removed,
      added
    };
  }

  private hitTestElement(point: StrokePoint): CanvasElement | null {
    const sortedElements = this.getElementsInLayerOrderDescending(this.elements);

    for (const element of sortedElements) {
      if (this.isPointInElement(point, element)) {
        return element;
      }
    }

    return null;
  }

  private isPointInElement(point: StrokePoint, element: CanvasElement): boolean {
    if (element.type === 'shape' && element.shapeType === 'line') {
      return this.isPointNearLineElement(point, element);
    }

    return this.isPointInElementBounds(point, element);
  }

  private isPointInElementBounds(point: StrokePoint, element: CanvasElement): boolean {
    return point.x >= element.x &&
      point.x <= element.x + element.width &&
      point.y >= element.y &&
      point.y <= element.y + element.height;
  }

  private isPointNearLineElement(point: StrokePoint, element: ShapeCanvasElement): boolean {
    if (element.geometry.points.length < 2) {
      return this.isPointInElementBounds(point, element);
    }

    const startPoint = element.geometry.points[0];
    const endPoint = element.geometry.points[1];
    return this.getPointToSegmentDistance(point, startPoint, endPoint) <= ELEMENT_LINE_HIT_TOLERANCE;
  }

  private getPointToSegmentDistance(
    point: StrokePoint,
    startPoint: ShapeGeometryPoint,
    endPoint: ShapeGeometryPoint
  ): number {
    const deltaX = endPoint.x - startPoint.x;
    const deltaY = endPoint.y - startPoint.y;
    const segmentLengthSquared = deltaX * deltaX + deltaY * deltaY;
    if (segmentLengthSquared <= 0) {
      const pointDeltaX = point.x - startPoint.x;
      const pointDeltaY = point.y - startPoint.y;
      return Math.sqrt(pointDeltaX * pointDeltaX + pointDeltaY * pointDeltaY);
    }

    const projectionRatio = Math.max(
      0,
      Math.min(1, ((point.x - startPoint.x) * deltaX + (point.y - startPoint.y) * deltaY) / segmentLengthSquared)
    );
    const closestX = startPoint.x + projectionRatio * deltaX;
    const closestY = startPoint.y + projectionRatio * deltaY;
    const distanceX = point.x - closestX;
    const distanceY = point.y - closestY;
    return Math.sqrt(distanceX * distanceX + distanceY * distanceY);
  }

  private hitTestElementEditHandle(
    point: StrokePoint,
    element: CanvasElement,
    hitTolerance: number
  ): ElementEditGestureKind | null {
    if (element.type === 'shape' && element.shapeType === 'line' && element.geometry.points.length >= 2) {
      if (this.isPointNearGeometryPoint(point, element.geometry.points[0], hitTolerance)) {
        return 'lineStart';
      }

      if (this.isPointNearGeometryPoint(point, element.geometry.points[1], hitTolerance)) {
        return 'lineEnd';
      }

      return null;
    }

    if (element.type === 'text') {
      return this.hitTestTextElementEditHandle(point, element, hitTolerance);
    }

    const handles: Array<{ kind: ElementEditGestureKind; point: ShapeGeometryPoint }> = [
      {
        kind: 'resizeTopLeft',
        point: { x: element.x, y: element.y }
      },
      {
        kind: 'resizeTopRight',
        point: { x: element.x + element.width, y: element.y }
      },
      {
        kind: 'resizeBottomLeft',
        point: { x: element.x, y: element.y + element.height }
      },
      {
        kind: 'resizeBottomRight',
        point: { x: element.x + element.width, y: element.y + element.height }
      }
    ];
    handles.push(
      {
        kind: 'resizeTop',
        point: { x: element.x + element.width / 2, y: element.y }
      },
      {
        kind: 'resizeRight',
        point: { x: element.x + element.width, y: element.y + element.height / 2 }
      },
      {
        kind: 'resizeBottom',
        point: { x: element.x + element.width / 2, y: element.y + element.height }
      },
      {
        kind: 'resizeLeft',
        point: { x: element.x, y: element.y + element.height / 2 }
      }
    );

    for (const handle of handles) {
      if (this.isPointNearGeometryPoint(point, handle.point, hitTolerance)) {
        return handle.kind;
      }
    }

    return null;
  }

  private hitTestTextElementEditHandle(
    point: StrokePoint,
    element: TextCanvasElement,
    hitTolerance: number
  ): ElementEditGestureKind | null {
    const verticalCenter = element.y + element.height / 2;
    const handles: Array<{ kind: ElementEditGestureKind; point: ShapeGeometryPoint }> = [
      {
        kind: 'resizeTopLeft',
        point: { x: element.x, y: element.y }
      },
      {
        kind: 'resizeTopRight',
        point: { x: element.x + element.width, y: element.y }
      },
      {
        kind: 'resizeBottomLeft',
        point: { x: element.x, y: element.y + element.height }
      },
      {
        kind: 'resizeBottomRight',
        point: { x: element.x + element.width, y: element.y + element.height }
      },
      {
        kind: 'resizeTextLeft',
        point: { x: element.x, y: verticalCenter }
      },
      {
        kind: 'resizeTextRight',
        point: { x: element.x + element.width, y: verticalCenter }
      }
    ];
    const tolerance = Math.max(1, hitTolerance);
    let bestKind: ElementEditGestureKind | null = null;
    let bestDistance = Number.POSITIVE_INFINITY;
    for (const handle of handles) {
      const distance = this.getPointToGeometryPointDistance(point, handle.point);
      if (distance <= tolerance && distance < bestDistance) {
        bestKind = handle.kind;
        bestDistance = distance;
      }
    }

    return bestKind;
  }

  private isPointNearGeometryPoint(point: StrokePoint, targetPoint: ShapeGeometryPoint, tolerance: number): boolean {
    return this.getPointToGeometryPointDistance(point, targetPoint) <= Math.max(1, tolerance);
  }

  private getPointToGeometryPointDistance(point: StrokePoint, targetPoint: ShapeGeometryPoint): number {
    const deltaX = point.x - targetPoint.x;
    const deltaY = point.y - targetPoint.y;
    return Math.sqrt(deltaX * deltaX + deltaY * deltaY);
  }

  private buildElementFromEditGesture(
    gesture: ElementEditGesture,
    point: StrokePoint,
    bounds: ElementBounds
  ): CanvasElement | null {
    switch (gesture.kind) {
      case 'move':
        return this.buildMovedElement(gesture.originalElement, point, gesture.startPoint, bounds);
      case 'lineStart':
      case 'lineEnd':
        return this.buildLineEndpointEditedElement(gesture, point, bounds);
      case 'resizeTopLeft':
      case 'resizeTop':
      case 'resizeTopRight':
      case 'resizeRight':
      case 'resizeBottomLeft':
      case 'resizeBottom':
      case 'resizeBottomRight':
      case 'resizeLeft':
      case 'resizeTextLeft':
      case 'resizeTextRight':
        return this.buildResizedElement(gesture, point, bounds);
      default:
        return null;
    }
  }

  private buildMovedElement(
    originalElement: CanvasElement,
    point: StrokePoint,
    startPoint: StrokePoint,
    bounds: ElementBounds
  ): CanvasElement {
    const deltaX = point.x - startPoint.x;
    const deltaY = point.y - startPoint.y;
    if (originalElement.type === 'shape' && originalElement.shapeType === 'line') {
      return this.buildMovedLineElement(originalElement, deltaX, deltaY, bounds);
    }

    const frame = clampElementFrameToBounds({
      x: originalElement.x + deltaX,
      y: originalElement.y + deltaY,
      width: originalElement.width,
      height: originalElement.height
    }, bounds);
    return this.cloneElementWithFrame(originalElement, frame);
  }

  private buildMovedLineElement(
    originalElement: ShapeCanvasElement,
    deltaX: number,
    deltaY: number,
    bounds: ElementBounds
  ): ShapeCanvasElement {
    if (originalElement.geometry.points.length < 2) {
      return this.cloneShapeElement(originalElement);
    }

    const startPoint = originalElement.geometry.points[0];
    const endPoint = originalElement.geometry.points[1];
    const minX = Math.min(startPoint.x, endPoint.x);
    const minY = Math.min(startPoint.y, endPoint.y);
    const maxX = Math.max(startPoint.x, endPoint.x);
    const maxY = Math.max(startPoint.y, endPoint.y);
    const safeDeltaX = this.clampNumber(deltaX, -minX, Math.max(0, bounds.width) - maxX);
    const safeDeltaY = this.clampNumber(deltaY, -minY, Math.max(0, bounds.height) - maxY);
    return this.buildLineElementFromPoints(
      originalElement,
      { x: startPoint.x + safeDeltaX, y: startPoint.y + safeDeltaY },
      { x: endPoint.x + safeDeltaX, y: endPoint.y + safeDeltaY }
    );
  }

  private buildLineEndpointEditedElement(
    gesture: ElementEditGesture,
    point: StrokePoint,
    bounds: ElementBounds
  ): ShapeCanvasElement | null {
    if (gesture.originalElement.type !== 'shape' ||
      gesture.originalElement.shapeType !== 'line' ||
      gesture.originalElement.geometry.points.length < 2) {
      return null;
    }

    const clampedPoint = this.clampPointToBounds(point, bounds);
    const startPoint = gesture.originalElement.geometry.points[0];
    const endPoint = gesture.originalElement.geometry.points[1];
    return this.buildLineElementFromPoints(
      gesture.originalElement,
      gesture.kind === 'lineStart' ? clampedPoint : startPoint,
      gesture.kind === 'lineEnd' ? clampedPoint : endPoint
    );
  }

  private buildLineElementFromPoints(
    originalElement: ShapeCanvasElement,
    startPoint: ShapeGeometryPoint,
    endPoint: ShapeGeometryPoint
  ): ShapeCanvasElement {
    const frame = this.buildShapeFrameFromPoints(originalElement.shapeType, {
      x: startPoint.x,
      y: startPoint.y,
      t: 0
    }, {
      x: endPoint.x,
      y: endPoint.y,
      t: 0
    });
    return {
      ...this.cloneShapeElement(originalElement),
      x: frame.x,
      y: frame.y,
      width: frame.width,
      height: frame.height,
      geometry: {
        kind: 'line',
        points: [
          { x: startPoint.x, y: startPoint.y },
          { x: endPoint.x, y: endPoint.y }
        ]
      },
      updatedAt: now()
    };
  }

  private buildResizedElement(
    gesture: ElementEditGesture,
    point: StrokePoint,
    bounds: ElementBounds
  ): CanvasElement | null {
    if (gesture.originalElement.type === 'shape' && gesture.originalElement.shapeType === 'line') {
      return null;
    }

    const targetFrame = this.buildResizeFrame(gesture.originalElement, gesture.kind, point, bounds);
    if (gesture.originalElement.type === 'text') {
      if (gesture.kind === 'resizeTextLeft' || gesture.kind === 'resizeTextRight') {
        return this.buildTextWidthResizedElement(gesture.originalElement, gesture.kind, point, bounds);
      }

      return this.buildResizedTextElement(gesture.originalElement, gesture.kind, targetFrame, bounds);
    }

    if (gesture.originalElement.type === 'image') {
      return this.buildAspectRatioResizedImageElement(gesture.originalElement, gesture.kind, targetFrame, bounds);
    }

    const frame = this.clampFrameWithMinimumSize(targetFrame, bounds, MIN_SHAPE_ELEMENT_SIZE, MIN_SHAPE_ELEMENT_SIZE);
    return this.cloneElementWithFrame(gesture.originalElement, frame);
  }

  private buildAspectRatioResizedImageElement(
    originalElement: ImageCanvasElement,
    kind: ElementEditGestureKind,
    targetFrame: ElementFrame,
    bounds: ElementBounds
  ): ImageCanvasElement {
    const aspectRatio = this.getImageAspectRatio(originalElement);
    let width = Math.max(MIN_IMAGE_ELEMENT_SIZE, targetFrame.width);
    let height = Math.max(MIN_IMAGE_ELEMENT_SIZE, targetFrame.height);

    if (kind === 'resizeLeft' || kind === 'resizeRight') {
      height = width / aspectRatio;
    } else if (kind === 'resizeTop' || kind === 'resizeBottom') {
      width = height * aspectRatio;
    } else if (width / Math.max(1, height) > aspectRatio) {
      width = height * aspectRatio;
    } else {
      height = width / aspectRatio;
    }

    const constrainedSize = this.constrainImageSizeToBounds(width, height, aspectRatio, bounds);
    width = constrainedSize.width;
    height = constrainedSize.height;

    const frame = clampElementFrameToBounds({
      x: this.resolveAspectResizeX(originalElement, kind, width),
      y: this.resolveAspectResizeY(originalElement, kind, height),
      width,
      height
    }, bounds);
    return this.cloneElementWithFrame(originalElement, frame) as ImageCanvasElement;
  }

  private getImageAspectRatio(element: ImageCanvasElement): number {
    if (element.originalWidth > 0 && element.originalHeight > 0) {
      return element.originalWidth / element.originalHeight;
    }

    return Math.max(1, element.width) / Math.max(1, element.height);
  }

  private constrainImageSizeToBounds(
    width: number,
    height: number,
    aspectRatio: number,
    bounds: ElementBounds
  ): ElementBounds {
    const maxWidth = Math.max(MIN_IMAGE_ELEMENT_SIZE, bounds.width);
    const maxHeight = Math.max(MIN_IMAGE_ELEMENT_SIZE, bounds.height);
    let nextWidth = Math.max(MIN_IMAGE_ELEMENT_SIZE, width);
    let nextHeight = Math.max(MIN_IMAGE_ELEMENT_SIZE, height);
    const scale = Math.min(1, maxWidth / nextWidth, maxHeight / nextHeight);
    nextWidth *= scale;
    nextHeight *= scale;

    if (nextWidth < MIN_IMAGE_ELEMENT_SIZE) {
      nextWidth = MIN_IMAGE_ELEMENT_SIZE;
      nextHeight = nextWidth / aspectRatio;
    }
    if (nextHeight < MIN_IMAGE_ELEMENT_SIZE) {
      nextHeight = MIN_IMAGE_ELEMENT_SIZE;
      nextWidth = nextHeight * aspectRatio;
    }

    return {
      width: Math.min(maxWidth, nextWidth),
      height: Math.min(maxHeight, nextHeight)
    };
  }

  private resolveAspectResizeX(
    originalElement: ImageCanvasElement,
    kind: ElementEditGestureKind,
    width: number
  ): number {
    if (kind === 'resizeTopLeft' || kind === 'resizeBottomLeft' || kind === 'resizeLeft') {
      return originalElement.x + originalElement.width - width;
    }
    if (kind === 'resizeTop' || kind === 'resizeBottom') {
      return originalElement.x + originalElement.width / 2 - width / 2;
    }

    return originalElement.x;
  }

  private resolveAspectResizeY(
    originalElement: ImageCanvasElement,
    kind: ElementEditGestureKind,
    height: number
  ): number {
    if (kind === 'resizeTopLeft' || kind === 'resizeTopRight' || kind === 'resizeTop') {
      return originalElement.y + originalElement.height - height;
    }
    if (kind === 'resizeLeft' || kind === 'resizeRight') {
      return originalElement.y + originalElement.height / 2 - height / 2;
    }

    return originalElement.y;
  }

  private buildResizeFrame(
    originalElement: CanvasElement,
    kind: ElementEditGestureKind,
    point: StrokePoint,
    bounds: ElementBounds
  ): ElementFrame {
    const minX = 0;
    const minY = 0;
    const maxX = Math.max(0, bounds.width);
    const maxY = Math.max(0, bounds.height);
    const clampedX = this.clampNumber(point.x, minX, maxX);
    const clampedY = this.clampNumber(point.y, minY, maxY);
    const left = originalElement.x;
    const top = originalElement.y;
    const right = originalElement.x + originalElement.width;
    const bottom = originalElement.y + originalElement.height;

    switch (kind) {
      case 'resizeTopLeft':
        return this.normalizeFrame(clampedX, clampedY, right, bottom);
      case 'resizeTop':
        return this.normalizeFrame(left, clampedY, right, bottom);
      case 'resizeTopRight':
        return this.normalizeFrame(left, clampedY, clampedX, bottom);
      case 'resizeRight':
        return this.normalizeFrame(left, top, clampedX, bottom);
      case 'resizeBottomLeft':
        return this.normalizeFrame(clampedX, top, right, clampedY);
      case 'resizeBottom':
        return this.normalizeFrame(left, top, right, clampedY);
      case 'resizeLeft':
        return this.normalizeFrame(clampedX, top, right, bottom);
      case 'resizeTextLeft':
      case 'resizeTextRight':
        return {
          x: left,
          y: top,
          width: originalElement.width,
          height: originalElement.height
        };
      case 'resizeBottomRight':
      default:
        return this.normalizeFrame(left, top, clampedX, clampedY);
    }
  }

  private buildResizedTextElement(
    originalElement: TextCanvasElement,
    kind: ElementEditGestureKind,
    targetFrame: ElementFrame,
    bounds: ElementBounds
  ): TextCanvasElement {
    const nextFontSize = this.calculateFontSizeForTextTarget(originalElement, targetFrame);
    const fontScale = nextFontSize / Math.max(1, originalElement.fontSize);
    const targetWidth = this.clampNumber(
      originalElement.width * fontScale,
      MIN_TEXT_ELEMENT_WIDTH,
      Math.max(MIN_TEXT_ELEMENT_WIDTH, bounds.width)
    );
    const fittedHeight = this.calculatePredictedTextHeight(originalElement.content, targetWidth, nextFontSize);
    const anchoredFrame = this.buildAnchoredTextFrame(
      originalElement,
      kind,
      this.clampFrameWithMinimumSize(
        {
          x: targetFrame.x,
          y: targetFrame.y,
          width: targetWidth,
          height: fittedHeight
        },
        bounds,
        MIN_TEXT_ELEMENT_WIDTH,
        this.calculateTextMinimumHeight(nextFontSize)
      ),
      bounds
    );
    return {
      ...this.cloneTextElement(originalElement),
      x: anchoredFrame.x,
      y: anchoredFrame.y,
      width: anchoredFrame.width,
      height: anchoredFrame.height,
      fontSize: nextFontSize,
      updatedAt: now()
    };
  }

  private buildTextWidthResizedElement(
    originalElement: TextCanvasElement,
    kind: ElementEditGestureKind,
    point: StrokePoint,
    bounds: ElementBounds
  ): TextCanvasElement {
    const right = originalElement.x + originalElement.width;
    const minWidth = MIN_TEXT_ELEMENT_WIDTH;
    const maxRightWidth = Math.max(minWidth, Math.max(1, bounds.width - originalElement.x));
    if (kind === 'resizeTextRight') {
      const targetWidth = this.clampNumber(point.x - originalElement.x, minWidth, maxRightWidth);
      const targetHeight = this.calculatePredictedTextHeight(originalElement.content, targetWidth, originalElement.fontSize);
      return this.cloneTextElementWithFrame(
        originalElement,
        clampElementFrameToBounds({
          x: originalElement.x,
          y: originalElement.y,
          width: targetWidth,
          height: targetHeight
        }, bounds)
      );
    }

    const maxLeftWidth = Math.max(minWidth, right);
    const targetWidth = this.clampNumber(right - point.x, minWidth, maxLeftWidth);
    const targetHeight = this.calculatePredictedTextHeight(originalElement.content, targetWidth, originalElement.fontSize);
    const frame = clampElementFrameToBounds({
      x: right - targetWidth,
      y: originalElement.y,
      width: targetWidth,
      height: targetHeight
    }, bounds);
    return this.cloneTextElementWithFrame(originalElement, frame);
  }

  private calculateFontSizeForTextTarget(originalElement: TextCanvasElement, targetFrame: ElementFrame): number {
    const widthRatio = Math.max(1, targetFrame.width) / Math.max(1, originalElement.width);
    const heightRatio = Math.max(1, targetFrame.height) / Math.max(1, originalElement.height);
    return this.clampNumber(
      originalElement.fontSize * Math.min(widthRatio, heightRatio),
      MIN_TEXT_FONT_SIZE,
      MAX_TEXT_FONT_SIZE
    );
  }

  private buildAnchoredTextFrame(
    originalElement: TextCanvasElement,
    kind: ElementEditGestureKind,
    frame: ElementFrame,
    bounds: ElementBounds
  ): ElementFrame {
    if (kind === 'resizeTopLeft' || kind === 'resizeBottomLeft') {
      frame.x = originalElement.x + originalElement.width - frame.width;
    }
    if (kind === 'resizeTopLeft' || kind === 'resizeTopRight') {
      frame.y = originalElement.y + originalElement.height - frame.height;
    }

    return clampElementFrameToBounds(frame, bounds);
  }

  private buildDefaultTextElementSize(fontSize: number): ElementBounds {
    return {
      width: DEFAULT_TEXT_ELEMENT_WIDTH,
      height: this.calculateTextMinimumHeight(fontSize)
    };
  }

  private calculateTextMinimumHeight(fontSize: number): number {
    return Math.max(1, Math.ceil(fontSize * TEXT_ELEMENT_LINE_HEIGHT_FACTOR + TEXT_ELEMENT_VERTICAL_PADDING));
  }

  private calculatePredictedTextHeight(content: string, width: number, fontSize: number): number {
    const lines = this.getTextLines(content);
    const contentWidth = Math.max(1, width - TEXT_ELEMENT_HORIZONTAL_PADDING);
    const estimatedCharacterWidth = Math.max(1, fontSize * TEXT_ELEMENT_WIDTH_FACTOR);
    const maxCharactersPerLine = Math.max(1, Math.floor(contentWidth / estimatedCharacterWidth));
    let visualLineCount = 0;

    for (const line of lines) {
      visualLineCount += Math.max(1, Math.ceil(line.length / maxCharactersPerLine));
    }

    return Math.max(
      this.calculateTextMinimumHeight(fontSize),
      Math.ceil(visualLineCount * fontSize * TEXT_ELEMENT_LINE_HEIGHT_FACTOR + TEXT_ELEMENT_VERTICAL_PADDING)
    );
  }

  private getTextLines(content: string): string[] {
    const normalizedContent = content.length === 0 ? 'Text' : content;
    const rawLines = normalizedContent.split('\n');
    const lines: string[] = [];

    for (const line of rawLines) {
      lines.push(line.length === 0 ? ' ' : line);
    }

    return lines.length === 0 ? ['Text'] : lines;
  }

  private cloneTextElementWithFrame(element: TextCanvasElement, frame: ElementFrame): TextCanvasElement {
    return {
      ...this.cloneTextElement(element),
      x: frame.x,
      y: frame.y,
      width: frame.width,
      height: frame.height,
      updatedAt: now()
    };
  }

  private normalizeFrame(left: number, top: number, right: number, bottom: number): ElementFrame {
    const x = Math.min(left, right);
    const y = Math.min(top, bottom);
    return {
      x,
      y,
      width: Math.abs(right - left),
      height: Math.abs(bottom - top)
    };
  }

  private clampFrameWithMinimumSize(
    frame: ElementFrame,
    bounds: ElementBounds,
    minWidth: number,
    minHeight: number
  ): ElementFrame {
    const width = Math.max(minWidth, frame.width);
    const height = Math.max(minHeight, frame.height);
    return clampElementFrameToBounds({
      x: frame.x,
      y: frame.y,
      width,
      height
    }, bounds);
  }

  private beginImageElementEditDraft(element: CanvasElement): void {
    if (element.type !== 'image') {
      this.imageElementEditDraft = null;
      return;
    }

    const frame = this.getElementFrame(element);
    this.imageElementEditDraft = {
      elementId: element.id,
      originalFrame: this.cloneElementFrame(frame),
      currentFrame: this.cloneElementFrame(frame)
    };
  }

  private getElementFrame(element: CanvasElement): ElementFrame {
    return {
      x: element.x,
      y: element.y,
      width: element.width,
      height: element.height
    };
  }

  private cloneImageElementEditDraft(draft: ImageElementEditDraft): ImageElementEditDraft {
    return {
      elementId: draft.elementId,
      originalFrame: this.cloneElementFrame(draft.originalFrame),
      currentFrame: this.cloneElementFrame(draft.currentFrame)
    };
  }

  private cloneElementFrame(frame: ElementFrame): ElementFrame {
    return {
      x: frame.x,
      y: frame.y,
      width: frame.width,
      height: frame.height
    };
  }

  private areElementFramesEquivalent(left: ElementFrame, right: ElementFrame): boolean {
    return Math.abs(left.x - right.x) < 0.01 &&
      Math.abs(left.y - right.y) < 0.01 &&
      Math.abs(left.width - right.width) < 0.01 &&
      Math.abs(left.height - right.height) < 0.01;
  }

  private cloneElementWithFrame(element: CanvasElement, frame: ElementFrame): CanvasElement {
    if (element.type === 'text') {
      return {
        ...this.cloneTextElement(element),
        x: frame.x,
        y: frame.y,
        width: frame.width,
        height: frame.height,
        updatedAt: now()
      };
    }

    if (element.type === 'image') {
      return {
        ...this.cloneImageElement(element),
        x: frame.x,
        y: frame.y,
        width: frame.width,
        height: frame.height,
        updatedAt: now()
      };
    }

    const nextElement = {
      ...this.cloneShapeElement(element),
      x: frame.x,
      y: frame.y,
      width: frame.width,
      height: frame.height,
      updatedAt: now()
    };
    if (nextElement.shapeType === 'rectangle' || nextElement.shapeType === 'circle') {
      nextElement.geometry = {
        kind: nextElement.shapeType === 'circle' ? 'ellipse' : 'rect',
        points: [
          { x: frame.x, y: frame.y },
          { x: frame.x + frame.width, y: frame.y + frame.height }
        ]
      };
    }

    return nextElement;
  }

  private cloneElementWithOutline(
    element: TextCanvasElement | ShapeCanvasElement | ImageCanvasElement,
    outline: ElementOutlineStyle,
    updatedAt: number
  ): CanvasElement {
    if (element.type === 'text') {
      return {
        ...this.cloneTextElement(element),
        outline: this.cloneElementOutline(outline),
        updatedAt
      };
    }

    if (element.type === 'shape') {
      return {
        ...this.cloneShapeElement(element),
        outline: this.cloneElementOutline(outline),
        updatedAt
      };
    }

    return {
      ...this.cloneImageElement(element),
      outline: this.cloneElementOutline(outline),
      updatedAt
    };
  }

  private cloneElementWithUpdatedAt(element: CanvasElement): CanvasElement {
    if (element.type === 'text') {
      return {
        ...this.cloneTextElement(element),
        updatedAt: now()
      };
    }

    if (element.type === 'shape') {
      return {
        ...this.cloneShapeElement(element),
        updatedAt: now()
      };
    }

    return {
      ...this.cloneImageElement(element),
      updatedAt: now()
    };
  }

  private replaceElementInMemory(nextElement: CanvasElement): void {
    this.elements = this.elements.map((element: CanvasElement): CanvasElement => {
      return element.id === nextElement.id ? this.cloneElement(nextElement) : element;
    });
  }

  private buildSelectionTargets(): SelectionTarget[] {
    const targets: SelectionTarget[] = [];
    for (const target of this.selectedStrokeTargets) {
      targets.push(this.cloneSelectionTarget(target));
    }

    for (const element of this.getSelectedElementsInZOrderDescending()) {
      const bounds = this.getElementBoundingBox(element);
      targets.push({
        id: element.id,
        kind: this.getSelectionTargetKindForElement(element),
        bounds,
        outline: this.buildBoundsOutline(bounds),
        strokeIds: [],
        elementId: element.id,
        canMove: true,
        canShowMenu: false
      });
    }

    return targets;
  }

  private cloneSelectionTargets(targets: SelectionTarget[]): SelectionTarget[] {
    return targets.map((target: SelectionTarget): SelectionTarget => this.cloneSelectionTarget(target));
  }

  private cloneSelectionTarget(target: SelectionTarget): SelectionTarget {
    return {
      id: target.id,
      kind: target.kind,
      bounds: { ...target.bounds },
      outline: target.outline.map((point: StrokePoint): StrokePoint => this.clonePoint(point)),
      strokeIds: [...target.strokeIds],
      elementId: target.elementId,
      canMove: target.canMove,
      canShowMenu: target.canShowMenu
    };
  }

  private getSelectionBoundsFromTargets(targets: SelectionTarget[]): BoundingBox | null {
    let bounds: BoundingBox | null = null;
    for (const target of targets) {
      bounds = mergeBoundingBoxes(bounds, target.bounds);
    }

    return bounds;
  }

  private getSelectionTargetKindForElement(element: CanvasElement): SelectionTargetKind {
    if (element.type === 'shape') {
      return 'shapeElement';
    }

    if (element.type === 'image') {
      return 'imageElement';
    }

    return 'textElement';
  }

  private getStrokeTargetsFromTargets(targets: SelectionTarget[]): SelectionTarget[] {
    return targets
      .filter((target: SelectionTarget): boolean => target.kind === 'strokeGroup')
      .map((target: SelectionTarget): SelectionTarget => this.cloneSelectionTarget(target));
  }

  private getElementIdsFromTargets(targets: SelectionTarget[]): string[] {
    return targets
      .filter((target: SelectionTarget): boolean => target.kind !== 'strokeGroup' && target.elementId.length > 0)
      .map((target: SelectionTarget): string => target.elementId);
  }

  private getCurrentSelectionSnapshot(): EditorSelectionSnapshot {
    return this.getSelectionSnapshotFromTargets(this.buildSelectionTargets());
  }

  private getSelectionSnapshotFromTargets(targets: SelectionTarget[]): EditorSelectionSnapshot {
    const strokeIds: string[] = [];
    const strokeIdSet = new Set<string>();
    const elementIds: string[] = [];
    const elementIdSet = new Set<string>();

    for (const target of targets) {
      if (target.kind === 'strokeGroup') {
        for (const strokeId of target.strokeIds) {
          if (!strokeIdSet.has(strokeId)) {
            strokeIdSet.add(strokeId);
            strokeIds.push(strokeId);
          }
        }
        continue;
      }

      if (target.elementId.length > 0 && !elementIdSet.has(target.elementId)) {
        elementIdSet.add(target.elementId);
        elementIds.push(target.elementId);
      }
    }

    return {
      strokeIds,
      strokeTargets: this.getStrokeTargetsFromTargets(targets),
      elementIds
    };
  }

  private restoreSelectionSnapshot(snapshot: EditorSelectionSnapshot | null): void {
    this.elementEditGesture = null;
    this.elementStyleEditGesture = null;
    this.imageElementEditDraft = null;
    this.selectionMoveGesture = null;
    if (snapshot === null) {
      this.selectedElementId = '';
      this.selectedElementIds = [];
      this.selectedStrokeTargets = [];
      this.selectionVersion += 1;
      return;
    }

    const existingStrokeIdSet = new Set<string>(this.strokes.map((stroke: Stroke): string => stroke.id));
    this.selectedStrokeTargets = snapshot.strokeTargets
      .filter((target: SelectionTarget): boolean => {
        return target.kind === 'strokeGroup' &&
          target.strokeIds.length > 0 &&
          target.strokeIds.every((strokeId: string): boolean => existingStrokeIdSet.has(strokeId));
      })
      .map((target: SelectionTarget): SelectionTarget => this.cloneSelectionTarget(target));
    this.selectedElementIds = [];
    for (const elementId of snapshot.elementIds) {
      if (this.elements.some((element: CanvasElement): boolean => element.id === elementId)) {
        this.selectedElementIds.push(elementId);
      }
    }
    this.selectedElementId = this.selectedElementIds.length > 0 ? this.selectedElementIds[0] : '';
    this.selectionVersion += 1;
  }

  private deleteSelectedStrokeTargets(): SelectionActionResult {
    const beforeSelection = this.getCurrentSelectionSnapshot();
    const hadElementSelection = this.selectedElementIds.length > 0;
    const removedStrokeRecords = this.getSelectedStrokeRecords();
    if (removedStrokeRecords.length === 0) {
      this.clearSelectionState();
      return {
        changed: false,
        changedStrokes: false,
        changedElements: false,
        elementSelectionChanged: hadElementSelection
      };
    }

    const removedStrokeIdSet = new Set<string>();
    for (const record of removedStrokeRecords) {
      removedStrokeIdSet.add(record.stroke.id);
    }

    this.strokes = this.strokes.filter((stroke: Stroke): boolean => !removedStrokeIdSet.has(stroke.id));
    this.applyStrokeSpatialIndexMutation(removedStrokeRecords, []);
    this.clearSelectionState();
    this.undoRedoController.recordDelta(
      removedStrokeRecords,
      [],
      'delete',
      [],
      [],
      beforeSelection,
      this.getCurrentSelectionSnapshot()
    );
    this.markPartialRenderInvalidation('delete', removedStrokeRecords, []);
    this.changeSequence += 1;
    this.persistenceStatus = 'pending selection delete save';
    this.schedulePersistCurrentStrokes('selectionDelete', 0);
    this.errorMessage = '';
    this.appendDebugEvent('selectionAction', `delete strokes=${removedStrokeRecords.length}`);
    return {
      changed: true,
      changedStrokes: true,
      changedElements: false,
      elementSelectionChanged: hadElementSelection
    };
  }

  private copySelectedStrokeTargets(): SelectionActionResult {
    const beforeSelection = this.getCurrentSelectionSnapshot();
    const hadElementSelection = this.selectedElementIds.length > 0;
    const sourceStrokeRecords = this.getSelectedStrokeRecords();
    if (sourceStrokeRecords.length === 0) {
      return { ...EMPTY_SELECTION_ACTION_RESULT };
    }

    const timestamp = now();
    const copiedStrokeIdBySourceId = new Map<string, string>();
    const copiedRecords: IndexedStrokeRecord[] = sourceStrokeRecords.map(
      (record: IndexedStrokeRecord, recordOffset: number): IndexedStrokeRecord => {
        const copiedStrokeId = createId('stroke');
        copiedStrokeIdBySourceId.set(record.stroke.id, copiedStrokeId);
        return {
          index: this.strokes.length + recordOffset,
          stroke: {
            ...this.translateStroke(record.stroke, STROKE_COPY_OFFSET, STROKE_COPY_OFFSET),
            id: copiedStrokeId,
            createdAt: timestamp,
            updatedAt: timestamp
          }
        };
      }
    );

    this.strokes = [
      ...this.strokes,
      ...copiedRecords.map((record: IndexedStrokeRecord): Stroke => this.cloneStroke(record.stroke))
    ];
    this.applyStrokeSpatialIndexMutation([], copiedRecords);
    this.selectedStrokeTargets = this.buildCopiedStrokeTargets(
      this.selectedStrokeTargets,
      copiedStrokeIdBySourceId,
      STROKE_COPY_OFFSET,
      STROKE_COPY_OFFSET
    );
    this.selectedElementId = '';
    this.selectedElementIds = [];
    this.elementEditGesture = null;
    this.elementStyleEditGesture = null;
    this.imageElementEditDraft = null;
    this.selectionMoveGesture = null;
    this.lassoDraftPath = [];
    this.selectionVersion += 1;
    this.undoRedoController.recordDelta(
      [],
      copiedRecords,
      'copy',
      [],
      [],
      beforeSelection,
      this.getCurrentSelectionSnapshot()
    );
    this.markPartialRenderInvalidation('copy', [], copiedRecords);
    this.changeSequence += 1;
    this.persistenceStatus = 'pending selection copy save';
    this.schedulePersistCurrentStrokes('selectionCopy', 0);
    this.errorMessage = '';
    this.appendDebugEvent('selectionAction', `copy strokes=${copiedRecords.length}`);
    return {
      changed: true,
      changedStrokes: true,
      changedElements: false,
      elementSelectionChanged: hadElementSelection
    };
  }

  private buildCopiedStrokeTargets(
    sourceTargets: SelectionTarget[],
    copiedStrokeIdBySourceId: Map<string, string>,
    offsetX: number,
    offsetY: number
  ): SelectionTarget[] {
    const copiedTargets: SelectionTarget[] = [];
    for (let targetIndex = 0; targetIndex < sourceTargets.length; targetIndex += 1) {
      const sourceTarget = sourceTargets[targetIndex];
      const copiedStrokeIds: string[] = [];
      for (const strokeId of sourceTarget.strokeIds) {
        const copiedStrokeId = copiedStrokeIdBySourceId.get(strokeId);
        if (copiedStrokeId !== undefined) {
          copiedStrokeIds.push(copiedStrokeId);
        }
      }

      if (copiedStrokeIds.length === 0) {
        continue;
      }

      copiedTargets.push({
        id: `stroke_group_copy_${targetIndex}_${copiedStrokeIds.join('_')}`,
        kind: 'strokeGroup',
        bounds: this.translateBoundingBox(sourceTarget.bounds, offsetX, offsetY),
        outline: sourceTarget.outline.map((point: StrokePoint): StrokePoint =>
          this.translatePoint(point, offsetX, offsetY)),
        strokeIds: copiedStrokeIds,
        elementId: '',
        canMove: sourceTarget.canMove,
        canShowMenu: sourceTarget.canShowMenu
      });
    }

    return copiedTargets;
  }

  private getSelectedStrokeRecords(): IndexedStrokeRecord[] {
    const selectedStrokeIds = this.getSelectedStrokeIdSet();
    if (selectedStrokeIds.size === 0) {
      return [];
    }

    const records: IndexedStrokeRecord[] = [];
    for (let index = 0; index < this.strokes.length; index += 1) {
      const stroke = this.strokes[index];
      if (selectedStrokeIds.has(stroke.id)) {
        records.push({
          index,
          stroke: this.cloneStroke(stroke)
        });
      }
    }

    return records;
  }

  private getSelectedElementRecords(): IndexedElementRecord[] {
    if (this.selectedElementIds.length === 0) {
      return [];
    }

    const selectedElementIds = new Set<string>(this.selectedElementIds);
    const records: IndexedElementRecord[] = [];
    for (let index = 0; index < this.elements.length; index += 1) {
      const element = this.elements[index];
      if (selectedElementIds.has(element.id)) {
        records.push({
          index,
          element: this.cloneElement(element)
        });
      }
    }

    return records;
  }

  private getSelectedStrokeIdSet(): Set<string> {
    const selectedStrokeIds = new Set<string>();
    for (const group of this.selectedStrokeTargets) {
      for (const strokeId of group.strokeIds) {
        selectedStrokeIds.add(strokeId);
      }
    }

    return selectedStrokeIds;
  }

  private getSelectionBoundsFromRecords(
    strokeRecords: IndexedStrokeRecord[],
    elementRecords: IndexedElementRecord[]
  ): BoundingBox | null {
    let bounds: BoundingBox | null = null;
    for (const record of strokeRecords) {
      bounds = mergeBoundingBoxes(bounds, getStrokeRenderBoundingBox(record.stroke));
    }

    for (const record of elementRecords) {
      bounds = mergeBoundingBoxes(bounds, this.getElementBoundingBox(record.element));
    }

    return bounds;
  }

  private applySelectionMoveOffset(offsetX: number, offsetY: number): void {
    if (this.selectionMoveGesture === null) {
      return;
    }

    this.selectionMoveGesture.currentOffsetX = offsetX;
    this.selectionMoveGesture.currentOffsetY = offsetY;
    const movedStrokeRecords = this.translateStrokeRecords(
      this.selectionMoveGesture.originalStrokeRecords,
      offsetX,
      offsetY
    );
    const movedElementRecords = this.translateElementRecords(
      this.selectionMoveGesture.originalElementRecords,
      offsetX,
      offsetY
    );
    this.replaceStrokeRecordsInMemory(movedStrokeRecords);
    this.replaceElementRecordsInMemory(movedElementRecords);
    this.applyMovedStrokeRecordsToSpatialIndex(movedStrokeRecords);
    const movedTargets = this.translateSelectionTargets(
      this.selectionMoveGesture.originalTargets,
      offsetX,
      offsetY
    );
    this.selectedStrokeTargets = this.getStrokeTargetsFromTargets(movedTargets);
    this.selectedElementIds = this.getElementIdsFromTargets(movedTargets);
    this.selectedElementId = this.selectedElementIds.length > 0 ? this.selectedElementIds[0] : '';
    this.selectionVersion += 1;
  }

  private translateStrokeRecords(records: IndexedStrokeRecord[], offsetX: number, offsetY: number): IndexedStrokeRecord[] {
    return records.map((record: IndexedStrokeRecord): IndexedStrokeRecord => {
      return {
        index: record.index,
        stroke: this.translateStroke(record.stroke, offsetX, offsetY)
      };
    });
  }

  private translateElementRecords(
    records: IndexedElementRecord[],
    offsetX: number,
    offsetY: number
  ): IndexedElementRecord[] {
    return records.map((record: IndexedElementRecord): IndexedElementRecord => {
      return {
        index: record.index,
        element: this.translateElement(record.element, offsetX, offsetY)
      };
    });
  }

  private replaceStrokeRecordsInMemory(records: IndexedStrokeRecord[]): void {
    if (records.length === 0) {
      return;
    }

    const strokeById = new Map<string, Stroke>();
    for (const record of records) {
      strokeById.set(record.stroke.id, this.cloneStroke(record.stroke));
    }

    this.strokes = this.strokes.map((stroke: Stroke): Stroke => {
      const movedStroke = strokeById.get(stroke.id);
      return movedStroke === undefined ? stroke : movedStroke;
    });
  }

  private replaceElementRecordsInMemory(records: IndexedElementRecord[]): void {
    if (records.length === 0) {
      return;
    }

    const elementById = new Map<string, CanvasElement>();
    for (const record of records) {
      elementById.set(record.element.id, this.cloneElement(record.element));
    }

    this.elements = this.elements.map((element: CanvasElement): CanvasElement => {
      const movedElement = elementById.get(element.id);
      return movedElement === undefined ? element : movedElement;
    });
  }

  private applyMovedStrokeRecordsToSpatialIndex(records: IndexedStrokeRecord[]): void {
    for (const record of records) {
      this.strokeSpatialIndex.removeStrokeById(record.stroke.id);
      this.strokeSpatialIndex.upsertStroke(record.stroke);
    }
  }

  private translateSelectionTargets(
    targets: SelectionTarget[],
    offsetX: number,
    offsetY: number
  ): SelectionTarget[] {
    return targets.map((target: SelectionTarget): SelectionTarget => {
      return {
        id: target.id,
        kind: target.kind,
        bounds: this.translateBoundingBox(target.bounds, offsetX, offsetY),
        outline: target.outline.map((point: StrokePoint): StrokePoint => this.translatePoint(point, offsetX, offsetY)),
        strokeIds: [...target.strokeIds],
        elementId: target.elementId,
        canMove: target.canMove,
        canShowMenu: target.canShowMenu
      };
    });
  }

  private translateStroke(stroke: Stroke, offsetX: number, offsetY: number): Stroke {
    return {
      ...this.cloneStroke(stroke),
      points: stroke.points.map((point: StrokePoint): StrokePoint => this.translatePoint(point, offsetX, offsetY)),
      updatedAt: now()
    };
  }

  private translateElement(element: CanvasElement, offsetX: number, offsetY: number): CanvasElement {
    if (element.type === 'shape') {
      return {
        ...this.cloneShapeElement(element),
        x: element.x + offsetX,
        y: element.y + offsetY,
        geometry: {
          kind: element.geometry.kind,
          points: element.geometry.points.map((point: ShapeGeometryPoint): ShapeGeometryPoint => {
            return {
              x: point.x + offsetX,
              y: point.y + offsetY
            };
          })
        },
        updatedAt: now()
      };
    }

    if (element.type === 'image') {
      return {
        ...this.cloneImageElement(element),
        x: element.x + offsetX,
        y: element.y + offsetY,
        updatedAt: now()
      };
    }

    return {
      ...this.cloneTextElement(element),
      x: element.x + offsetX,
      y: element.y + offsetY,
      updatedAt: now()
    };
  }

  private translatePoint(point: StrokePoint, offsetX: number, offsetY: number): StrokePoint {
    return {
      x: point.x + offsetX,
      y: point.y + offsetY,
      t: point.t,
      pressure: point.pressure
    };
  }

  private translateBoundingBox(bounds: BoundingBox, offsetX: number, offsetY: number): BoundingBox {
    return {
      minX: bounds.minX + offsetX,
      minY: bounds.minY + offsetY,
      maxX: bounds.maxX + offsetX,
      maxY: bounds.maxY + offsetY
    };
  }

  private buildStrokeResizeBounds(
    originalBounds: BoundingBox,
    handle: ResizeHandle,
    point: StrokePoint,
    bounds: ElementBounds
  ): BoundingBox {
    const clampedX = this.clampNumber(point.x, 0, Math.max(0, bounds.width));
    const clampedY = this.clampNumber(point.y, 0, Math.max(0, bounds.height));
    let minX = originalBounds.minX;
    let minY = originalBounds.minY;
    let maxX = originalBounds.maxX;
    let maxY = originalBounds.maxY;

    if (handle === 'topLeft' || handle === 'left' || handle === 'bottomLeft') {
      minX = Math.min(clampedX, originalBounds.maxX - MIN_STROKE_RESIZE_BOUNDS_SIZE);
    }
    if (handle === 'topRight' || handle === 'right' || handle === 'bottomRight') {
      maxX = Math.max(clampedX, originalBounds.minX + MIN_STROKE_RESIZE_BOUNDS_SIZE);
    }
    if (handle === 'topLeft' || handle === 'top' || handle === 'topRight') {
      minY = Math.min(clampedY, originalBounds.maxY - MIN_STROKE_RESIZE_BOUNDS_SIZE);
    }
    if (handle === 'bottomLeft' || handle === 'bottom' || handle === 'bottomRight') {
      maxY = Math.max(clampedY, originalBounds.minY + MIN_STROKE_RESIZE_BOUNDS_SIZE);
    }

    return {
      minX: this.clampNumber(minX, 0, Math.max(0, bounds.width - MIN_STROKE_RESIZE_BOUNDS_SIZE)),
      minY: this.clampNumber(minY, 0, Math.max(0, bounds.height - MIN_STROKE_RESIZE_BOUNDS_SIZE)),
      maxX: this.clampNumber(maxX, MIN_STROKE_RESIZE_BOUNDS_SIZE, Math.max(MIN_STROKE_RESIZE_BOUNDS_SIZE, bounds.width)),
      maxY: this.clampNumber(maxY, MIN_STROKE_RESIZE_BOUNDS_SIZE, Math.max(MIN_STROKE_RESIZE_BOUNDS_SIZE, bounds.height))
    };
  }

  private applyStrokeResizeBounds(nextBounds: BoundingBox): void {
    if (this.strokeResizeGesture === null) {
      return;
    }

    this.strokeResizeGesture.currentBounds = this.cloneBoundingBox(nextBounds);
    const resizedStrokeRecords = this.scaleStrokeRecords(
      this.strokeResizeGesture.originalStrokeRecords,
      this.strokeResizeGesture.originalBounds,
      nextBounds
    );
    this.replaceStrokeRecordsInMemory(resizedStrokeRecords);
    this.applyMovedStrokeRecordsToSpatialIndex(resizedStrokeRecords);
    this.selectedStrokeTargets = this.scaleSelectionTargets(
      this.strokeResizeGesture.originalTargets,
      this.strokeResizeGesture.originalBounds,
      nextBounds
    );
    this.selectionVersion += 1;
  }

  private scaleStrokeRecords(
    records: IndexedStrokeRecord[],
    sourceBounds: BoundingBox,
    targetBounds: BoundingBox
  ): IndexedStrokeRecord[] {
    return records.map((record: IndexedStrokeRecord): IndexedStrokeRecord => ({
      index: record.index,
      stroke: this.scaleStroke(record.stroke, sourceBounds, targetBounds)
    }));
  }

  private scaleStroke(stroke: Stroke, sourceBounds: BoundingBox, targetBounds: BoundingBox): Stroke {
    return this.scaleStrokeForCanvasResize(stroke, sourceBounds, targetBounds, now());
  }

  private scaleStrokeForCanvasResize(
    stroke: Stroke,
    sourceBounds: BoundingBox,
    targetBounds: BoundingBox,
    updatedAt: number
  ): Stroke {
    const scaleX = (targetBounds.maxX - targetBounds.minX) / Math.max(1, sourceBounds.maxX - sourceBounds.minX);
    const scaleY = (targetBounds.maxY - targetBounds.minY) / Math.max(1, sourceBounds.maxY - sourceBounds.minY);
    const widthScale = Math.sqrt(Math.max(0.01, Math.abs(scaleX * scaleY)));
    return {
      ...this.cloneStroke(stroke),
      renderWarmupPoints: stroke.renderWarmupPoints?.map((point: StrokePoint): StrokePoint =>
        this.scalePoint(point, sourceBounds, targetBounds, scaleX, scaleY)) ?? [],
      points: stroke.points.map((point: StrokePoint): StrokePoint =>
        this.scalePoint(point, sourceBounds, targetBounds, scaleX, scaleY)),
      style: {
        ...stroke.style,
        width: Math.max(MIN_STROKE_RESIZE_WIDTH, stroke.style.width * widthScale)
      },
      updatedAt: updatedAt
    };
  }

  private scaleSelectionTargets(
    targets: SelectionTarget[],
    sourceBounds: BoundingBox,
    targetBounds: BoundingBox
  ): SelectionTarget[] {
    const scaleX = (targetBounds.maxX - targetBounds.minX) / Math.max(1, sourceBounds.maxX - sourceBounds.minX);
    const scaleY = (targetBounds.maxY - targetBounds.minY) / Math.max(1, sourceBounds.maxY - sourceBounds.minY);
    return targets.map((target: SelectionTarget): SelectionTarget => ({
      id: target.id,
      kind: target.kind,
      bounds: this.scaleBoundingBox(target.bounds, sourceBounds, targetBounds, scaleX, scaleY),
      outline: target.outline.map((point: StrokePoint): StrokePoint =>
        this.scalePoint(point, sourceBounds, targetBounds, scaleX, scaleY)),
      strokeIds: [...target.strokeIds],
      elementId: target.elementId,
      canMove: target.canMove,
      canShowMenu: target.canShowMenu
    }));
  }

  private scalePoint(
    point: StrokePoint,
    sourceBounds: BoundingBox,
    targetBounds: BoundingBox,
    scaleX: number,
    scaleY: number
  ): StrokePoint {
    return {
      x: targetBounds.minX + (point.x - sourceBounds.minX) * scaleX,
      y: targetBounds.minY + (point.y - sourceBounds.minY) * scaleY,
      t: point.t,
      pressure: point.pressure
    };
  }

  private scaleBoundingBox(
    bounds: BoundingBox,
    sourceBounds: BoundingBox,
    targetBounds: BoundingBox,
    scaleX: number,
    scaleY: number
  ): BoundingBox {
    const topLeft = this.scalePoint({ x: bounds.minX, y: bounds.minY, t: 0 }, sourceBounds, targetBounds, scaleX, scaleY);
    const bottomRight = this.scalePoint({ x: bounds.maxX, y: bounds.maxY, t: 0 }, sourceBounds, targetBounds, scaleX, scaleY);
    return {
      minX: Math.min(topLeft.x, bottomRight.x),
      minY: Math.min(topLeft.y, bottomRight.y),
      maxX: Math.max(topLeft.x, bottomRight.x),
      maxY: Math.max(topLeft.y, bottomRight.y)
    };
  }

  private scaleUndoRedoSnapshotForCanvasResize(
    snapshot: UndoRedoSnapshot,
    sourceBounds: BoundingBox,
    targetBounds: BoundingBox
  ): UndoRedoSnapshot {
    return {
      undoStack: snapshot.undoStack.map((operation: EditorOperation): EditorOperation =>
        this.scaleUndoRedoOperationForCanvasResize(operation, sourceBounds, targetBounds)),
      redoStack: snapshot.redoStack.map((operation: EditorOperation): EditorOperation =>
        this.scaleUndoRedoOperationForCanvasResize(operation, sourceBounds, targetBounds))
    };
  }

  private scaleUndoRedoOperationForCanvasResize(
    operation: EditorOperation,
    sourceBounds: BoundingBox,
    targetBounds: BoundingBox
  ): EditorOperation {
    const updatedAt = now();
    if (operation.type === 'append_stroke') {
      return {
        type: 'append_stroke',
        index: operation.index,
        stroke: this.scaleStrokeForCanvasResize(operation.stroke, sourceBounds, targetBounds, updatedAt)
      };
    }

    return {
      type: 'replace_page_delta',
      removed: operation.removed.map((record: IndexedStrokeRecord): IndexedStrokeRecord => ({
        index: record.index,
        stroke: this.scaleStrokeForCanvasResize(record.stroke, sourceBounds, targetBounds, updatedAt)
      })),
      added: operation.added.map((record: IndexedStrokeRecord): IndexedStrokeRecord => ({
        index: record.index,
        stroke: this.scaleStrokeForCanvasResize(record.stroke, sourceBounds, targetBounds, updatedAt)
      })),
      removedElements: operation.removedElements.map((record: IndexedElementRecord): IndexedElementRecord => ({
        index: record.index,
        element: this.scaleElementForCanvasResize(record.element, sourceBounds, targetBounds, updatedAt)
      })),
      addedElements: operation.addedElements.map((record: IndexedElementRecord): IndexedElementRecord => ({
        index: record.index,
        element: this.scaleElementForCanvasResize(record.element, sourceBounds, targetBounds, updatedAt)
      })),
      beforeSelection: operation.beforeSelection === undefined
        ? undefined
        : this.scaleSelectionSnapshotForCanvasResize(operation.beforeSelection, sourceBounds, targetBounds),
      afterSelection: operation.afterSelection === undefined
        ? undefined
        : this.scaleSelectionSnapshotForCanvasResize(operation.afterSelection, sourceBounds, targetBounds),
      beforeStrokeLayerZIndex: operation.beforeStrokeLayerZIndex,
      afterStrokeLayerZIndex: operation.afterStrokeLayerZIndex,
      label: operation.label
    };
  }

  private scaleSelectionSnapshotForCanvasResize(
    snapshot: EditorSelectionSnapshot,
    sourceBounds: BoundingBox,
    targetBounds: BoundingBox
  ): EditorSelectionSnapshot {
    return {
      strokeIds: [...snapshot.strokeIds],
      strokeTargets: this.scaleSelectionTargets(snapshot.strokeTargets, sourceBounds, targetBounds),
      elementIds: [...snapshot.elementIds]
    };
  }

  private scaleElementForCanvasResize(
    element: CanvasElement,
    sourceBounds: BoundingBox,
    targetBounds: BoundingBox,
    updatedAt: number
  ): CanvasElement {
    switch (element.type) {
      case 'text':
        return this.scaleTextElementForCanvasResize(element, sourceBounds, targetBounds, updatedAt);
      case 'shape':
        return this.scaleShapeElementForCanvasResize(element, sourceBounds, targetBounds, updatedAt);
      case 'image':
        return this.scaleImageElementForCanvasResize(element, sourceBounds, targetBounds, updatedAt);
      default:
        return this.scaleTextElementForCanvasResize(element as TextCanvasElement, sourceBounds, targetBounds, updatedAt);
    }
  }

  private scaleTextElementForCanvasResize(
    element: TextCanvasElement,
    sourceBounds: BoundingBox,
    targetBounds: BoundingBox,
    updatedAt: number
  ): TextCanvasElement {
    const frame = this.scaleElementFrameForCanvasResize(element, sourceBounds, targetBounds);
    const sizeScale = this.getCanvasResizeStrokeWidthScale(sourceBounds, targetBounds);
    return {
      ...this.cloneTextElement(element),
      x: frame.x,
      y: frame.y,
      width: frame.width,
      height: frame.height,
      fontSize: Math.max(1, element.fontSize * sizeScale),
      outline: this.scaleElementOutlineForCanvasResize(element.outline ?? DEFAULT_TEXT_OUTLINE, sizeScale),
      updatedAt: updatedAt
    };
  }

  private scaleShapeElementForCanvasResize(
    element: ShapeCanvasElement,
    sourceBounds: BoundingBox,
    targetBounds: BoundingBox,
    updatedAt: number
  ): ShapeCanvasElement {
    const frame = this.scaleElementFrameForCanvasResize(element, sourceBounds, targetBounds);
    const sizeScale = this.getCanvasResizeStrokeWidthScale(sourceBounds, targetBounds);
    const scaleX = (targetBounds.maxX - targetBounds.minX) / Math.max(1, sourceBounds.maxX - sourceBounds.minX);
    const scaleY = (targetBounds.maxY - targetBounds.minY) / Math.max(1, sourceBounds.maxY - sourceBounds.minY);
    return {
      ...this.cloneShapeElement(element),
      x: frame.x,
      y: frame.y,
      width: frame.width,
      height: frame.height,
      geometry: {
        kind: element.geometry.kind,
        points: element.geometry.points.map((point: ShapeGeometryPoint): ShapeGeometryPoint => ({
          x: targetBounds.minX + (point.x - sourceBounds.minX) * scaleX,
          y: targetBounds.minY + (point.y - sourceBounds.minY) * scaleY
        }))
      },
      outline: this.scaleElementOutlineForCanvasResize(element.outline, sizeScale),
      updatedAt: updatedAt
    };
  }

  private scaleImageElementForCanvasResize(
    element: ImageCanvasElement,
    sourceBounds: BoundingBox,
    targetBounds: BoundingBox,
    updatedAt: number
  ): ImageCanvasElement {
    const frame = this.scaleElementFrameForCanvasResize(element, sourceBounds, targetBounds);
    const sizeScale = this.getCanvasResizeStrokeWidthScale(sourceBounds, targetBounds);
    return {
      ...this.cloneImageElement(element),
      x: frame.x,
      y: frame.y,
      width: frame.width,
      height: frame.height,
      outline: this.scaleElementOutlineForCanvasResize(element.outline, sizeScale),
      updatedAt: updatedAt
    };
  }

  private scaleElementFrameForCanvasResize(
    element: CanvasElement,
    sourceBounds: BoundingBox,
    targetBounds: BoundingBox
  ): ElementFrame {
    const scaleX = (targetBounds.maxX - targetBounds.minX) / Math.max(1, sourceBounds.maxX - sourceBounds.minX);
    const scaleY = (targetBounds.maxY - targetBounds.minY) / Math.max(1, sourceBounds.maxY - sourceBounds.minY);
    return {
      x: targetBounds.minX + (element.x - sourceBounds.minX) * scaleX,
      y: targetBounds.minY + (element.y - sourceBounds.minY) * scaleY,
      width: Math.max(1, element.width * scaleX),
      height: Math.max(1, element.height * scaleY)
    };
  }

  private scaleElementOutlineForCanvasResize(
    outline: ElementOutlineStyle,
    sizeScale: number
  ): ElementOutlineStyle {
    return {
      lineStyle: outline.lineStyle,
      color: outline.color,
      width: Math.max(0, outline.width * sizeScale)
    };
  }

  private getCanvasResizeStrokeWidthScale(sourceBounds: BoundingBox, targetBounds: BoundingBox): number {
    const scaleX = (targetBounds.maxX - targetBounds.minX) / Math.max(1, sourceBounds.maxX - sourceBounds.minX);
    const scaleY = (targetBounds.maxY - targetBounds.minY) / Math.max(1, sourceBounds.maxY - sourceBounds.minY);
    return Math.sqrt(Math.max(0.01, Math.abs(scaleX * scaleY)));
  }

  private cloneBoundingBox(bounds: BoundingBox): BoundingBox {
    return {
      minX: bounds.minX,
      minY: bounds.minY,
      maxX: bounds.maxX,
      maxY: bounds.maxY
    };
  }

  private areBoundingBoxesEquivalent(left: BoundingBox, right: BoundingBox): boolean {
    return Math.abs(left.minX - right.minX) < 0.01 &&
      Math.abs(left.minY - right.minY) < 0.01 &&
      Math.abs(left.maxX - right.maxX) < 0.01 &&
      Math.abs(left.maxY - right.maxY) < 0.01;
  }

  private clampSelectionMoveOffset(value: number, firstLimit: number, secondLimit: number): number {
    const minValue = Math.min(firstLimit, secondLimit);
    const maxValue = Math.max(firstLimit, secondLimit);
    return Math.max(minValue, Math.min(maxValue, value));
  }

  private buildLayerStack(): LayerStackItem[] {
    const stack: LayerStackItem[] = [];

    if (this.hasVisibleStrokeLayer()) {
      stack.push({
        kind: 'strokeLayer',
        id: 'strokeLayer',
        zIndex: this.strokeLayerZIndex,
        createdAt: 0,
        orderIndex: -1
      });
    }

    for (let index = 0; index < this.elements.length; index += 1) {
      const element = this.elements[index];
      stack.push({
        kind: 'element',
        id: `element:${element.id}`,
        zIndex: element.zIndex,
        createdAt: element.createdAt,
        orderIndex: index
      });
    }

    return stack.sort((left: LayerStackItem, right: LayerStackItem): number =>
      this.compareLayerStackItemAscending(left, right));
  }

  private hasVisibleStrokeLayer(): boolean {
    return this.strokes.length > 0;
  }

  private getElementsInLayerOrderAscending(elements: CanvasElement[]): CanvasElement[] {
    return elements
      .map((element: CanvasElement, orderIndex: number): ElementLayerOrderRecord => ({ element, orderIndex }))
      .sort((left: ElementLayerOrderRecord, right: ElementLayerOrderRecord): number =>
        this.compareElementLayerOrderAscending(left.element, left.orderIndex, right.element, right.orderIndex))
      .map((record: ElementLayerOrderRecord): CanvasElement => record.element);
  }

  private getElementsInLayerOrderDescending(elements: CanvasElement[]): CanvasElement[] {
    return elements
      .map((element: CanvasElement, orderIndex: number): ElementLayerOrderRecord => ({ element, orderIndex }))
      .sort((left: ElementLayerOrderRecord, right: ElementLayerOrderRecord): number =>
        this.compareElementLayerOrderAscending(right.element, right.orderIndex, left.element, left.orderIndex))
      .map((record: ElementLayerOrderRecord): CanvasElement => record.element);
  }

  private compareElementLayerOrderAscending(
    leftElement: CanvasElement,
    leftOrderIndex: number,
    rightElement: CanvasElement,
    rightOrderIndex: number
  ): number {
    if (leftElement.zIndex !== rightElement.zIndex) {
      return leftElement.zIndex - rightElement.zIndex;
    }
    if (leftOrderIndex !== rightOrderIndex) {
      return leftOrderIndex - rightOrderIndex;
    }
    if (leftElement.createdAt !== rightElement.createdAt) {
      return leftElement.createdAt - rightElement.createdAt;
    }
    return leftElement.id.localeCompare(rightElement.id);
  }

  private compareLayerStackItemAscending(left: LayerStackItem, right: LayerStackItem): number {
    if (left.zIndex !== right.zIndex) {
      return left.zIndex - right.zIndex;
    }
    if (left.orderIndex !== right.orderIndex) {
      return left.orderIndex - right.orderIndex;
    }
    if (left.createdAt !== right.createdAt) {
      return left.createdAt - right.createdAt;
    }
    return left.id.localeCompare(right.id);
  }

  private reorderLayerStack(itemId: string, action: LayerOrderAction): LayerReorderResult {
    const stack = this.buildLayerStack();
    const itemIndex = stack.findIndex((item: LayerStackItem): boolean => item.id === itemId);
    if (itemIndex < 0) {
      return {
        changed: false,
        strokeLayerZIndex: this.strokeLayerZIndex,
        elements: this.cloneElements(this.elements)
      };
    }

    const targetIndex = this.getLayerReorderTargetIndex(itemIndex, stack.length, action);
    if (targetIndex === itemIndex) {
      return {
        changed: false,
        strokeLayerZIndex: this.strokeLayerZIndex,
        elements: this.cloneElements(this.elements)
      };
    }

    const reorderedStack = stack.slice();
    const movedItems = reorderedStack.splice(itemIndex, 1);
    reorderedStack.splice(targetIndex, 0, movedItems[0]);
    return this.buildLayerReorderResult(reorderedStack);
  }

  private getLayerReorderTargetIndex(currentIndex: number, stackLength: number, action: LayerOrderAction): number {
    switch (action) {
      case 'layerUp':
        return Math.min(stackLength - 1, currentIndex + 1);
      case 'layerDown':
        return Math.max(0, currentIndex - 1);
      case 'layerTop':
        return stackLength - 1;
      case 'layerBottom':
        return 0;
      default:
        return currentIndex;
    }
  }

  private buildLayerReorderResult(stack: LayerStackItem[]): LayerReorderResult {
    let nextStrokeLayerZIndex = this.strokeLayerZIndex;
    const nextElementZIndexById = new Map<string, number>();
    for (let index = 0; index < stack.length; index += 1) {
      const item = stack[index];
      if (item.kind === 'strokeLayer') {
        nextStrokeLayerZIndex = index;
      } else {
        nextElementZIndexById.set(item.id.substring('element:'.length), index);
      }
    }

    const timestamp = now();
    let changed = nextStrokeLayerZIndex !== this.strokeLayerZIndex;
    const nextElements = this.elements.map((element: CanvasElement): CanvasElement => {
      const nextZIndex = nextElementZIndexById.get(element.id) ?? element.zIndex;
      if (nextZIndex === element.zIndex) {
        return this.cloneElement(element);
      }
      changed = true;
      return this.cloneElementWithZIndex(element, nextZIndex, timestamp);
    });

    return {
      changed,
      strokeLayerZIndex: nextStrokeLayerZIndex,
      elements: nextElements
    };
  }

  private getElementByIdFromList(elements: CanvasElement[], elementId: string): CanvasElement | null {
    for (const element of elements) {
      if (element.id === elementId) {
        return element;
      }
    }

    return null;
  }

  private cloneElementWithZIndex(element: CanvasElement, zIndex: number, updatedAt: number): CanvasElement {
    if (element.type === 'text') {
      return {
        ...this.cloneTextElement(element),
        zIndex,
        updatedAt
      };
    }

    if (element.type === 'shape') {
      return {
        ...this.cloneShapeElement(element),
        zIndex,
        updatedAt
      };
    }

    return {
      ...this.cloneImageElement(element),
      zIndex,
      updatedAt
    };
  }

  private recordElementDelta(
    label: EditorDeltaLabel,
    removedElements: IndexedElementRecord[],
    addedElements: IndexedElementRecord[],
    beforeSelection: EditorSelectionSnapshot | null = null,
    afterSelection: EditorSelectionSnapshot | null = null
  ): void {
    this.undoRedoController.recordDelta(
      [],
      [],
      label,
      removedElements,
      addedElements,
      beforeSelection ?? this.getCurrentSelectionSnapshot(),
      afterSelection ?? this.getCurrentSelectionSnapshot()
    );
  }

  private replaceElementWithDelta(
    label: EditorDeltaLabel,
    originalElement: CanvasElement,
    nextElement: CanvasElement,
    persistenceLabel: string
  ): SelectionActionResult {
    const beforeSelection = this.getCurrentSelectionSnapshot();
    const elementIndex = this.getElementIndexById(originalElement.id);
    this.replaceElementInMemory(nextElement);
    this.recordElementDelta(label, [{
      index: elementIndex,
      element: this.cloneElement(originalElement)
    }], [{
      index: elementIndex,
      element: this.cloneElement(nextElement)
    }], beforeSelection, this.getCurrentSelectionSnapshot());
    this.changeSequence += 1;
    this.persistenceStatus = `pending ${persistenceLabel} save`;
    this.schedulePersistCurrentStrokes(persistenceLabel, 0);
    this.errorMessage = '';
    this.appendDebugEvent(persistenceLabel, `element=${nextElement.id} type=${nextElement.type}`);
    return {
      changed: true,
      changedStrokes: false,
      changedElements: true,
      elementSelectionChanged: false
    };
  }

  private getElementIndexById(elementId: string): number {
    const elementIndex = this.elements.findIndex((element: CanvasElement): boolean => element.id === elementId);
    return elementIndex < 0 ? this.elements.length : elementIndex;
  }

  private getStrokesInsideLasso(lassoPath: StrokePoint[], hitTolerance: number): Stroke[] {
    const lassoBounds = getBoundingBox(lassoPath);
    if (lassoBounds === null) {
      return [];
    }

    const selectedStrokes: Stroke[] = [];
    for (const stroke of this.strokes) {
      const strokeBounds = this.getStrokeLassoCandidateBounds(stroke, hitTolerance);
      if (strokeBounds === null || !doBoundingBoxesIntersect(strokeBounds, lassoBounds)) {
        continue;
      }

      if (this.doesStrokeIntersectLasso(stroke, lassoPath, hitTolerance)) {
        selectedStrokes.push(this.cloneStroke(stroke));
      }
    }

    return selectedStrokes;
  }

  private doesStrokeIntersectLasso(stroke: Stroke, lassoPath: StrokePoint[], hitTolerance: number): boolean {
    const sampledPoints = sampleStrokePoints(stroke.points, Math.max(1, stroke.style.width / 2));
    let insideCount = 0;
    for (const point of sampledPoints) {
      if (this.isPointInsidePolygon(point, lassoPath)) {
        insideCount += 1;
      }
    }

    if (this.hasEnoughStrokeSamplesInsideLasso(insideCount, sampledPoints.length)) {
      return true;
    }

    const edgeTolerance = stroke.style.width / 2 + Math.max(0, hitTolerance);
    return this.doesStrokeEdgeIntersectLasso(stroke, lassoPath, edgeTolerance);
  }

  private hasEnoughStrokeSamplesInsideLasso(insideCount: number, totalCount: number): boolean {
    if (totalCount <= 0) {
      return false;
    }

    if (totalCount <= LASSO_STROKE_SHORT_SAMPLE_COUNT) {
      return insideCount >= 1;
    }

    return insideCount >= LASSO_STROKE_MIN_INSIDE_COUNT &&
      insideCount / totalCount >= LASSO_STROKE_MIN_INSIDE_RATIO;
  }

  private doesStrokeEdgeIntersectLasso(stroke: Stroke, lassoPath: StrokePoint[], edgeTolerance: number): boolean {
    for (let strokeIndex = 1; strokeIndex < stroke.points.length; strokeIndex += 1) {
      const strokeStart = stroke.points[strokeIndex - 1];
      const strokeEnd = stroke.points[strokeIndex];
      for (let lassoIndex = 0; lassoIndex < lassoPath.length; lassoIndex += 1) {
        const lassoStart = lassoPath[lassoIndex];
        const lassoEnd = lassoPath[(lassoIndex + 1) % lassoPath.length];
        if (this.doSegmentsIntersect(strokeStart, strokeEnd, lassoStart, lassoEnd) ||
          this.getSegmentToSegmentDistance(strokeStart, strokeEnd, lassoStart, lassoEnd) <= edgeTolerance) {
          return true;
        }
      }
    }

    return false;
  }

  private getStrokeLassoCandidateBounds(stroke: Stroke, hitTolerance: number): BoundingBox | null {
    const bounds = getBoundingBox(stroke.points);
    if (bounds === null) {
      return null;
    }

    const padding = stroke.style.width / 2 + Math.max(0, hitTolerance);
    return expandBoundingBox(bounds, padding);
  }

  private getElementIdsInsideLasso(lassoPath: StrokePoint[]): string[] {
    const selectedIds: string[] = [];
    const lassoBounds = getBoundingBox(lassoPath);
    if (lassoBounds === null) {
      return selectedIds;
    }

    for (const element of this.elements) {
      const elementBounds = this.getElementBoundingBox(element);
      if (!doBoundingBoxesIntersect(elementBounds, lassoBounds)) {
        continue;
      }

      if (this.doesElementIntersectLasso(element, lassoPath)) {
        selectedIds.push(element.id);
      }
    }

    return selectedIds;
  }

  private doesElementIntersectLasso(element: CanvasElement, lassoPath: StrokePoint[]): boolean {
    const bounds = this.getElementBoundingBox(element);
    const corners: StrokePoint[] = [
      { x: bounds.minX, y: bounds.minY, t: 0 },
      { x: bounds.maxX, y: bounds.minY, t: 0 },
      { x: bounds.maxX, y: bounds.maxY, t: 0 },
      { x: bounds.minX, y: bounds.maxY, t: 0 }
    ];
    const center: StrokePoint = {
      x: (bounds.minX + bounds.maxX) / 2,
      y: (bounds.minY + bounds.maxY) / 2,
      t: 0
    };

    if (this.isPointInsidePolygon(center, lassoPath)) {
      return true;
    }

    for (const corner of corners) {
      if (this.isPointInsidePolygon(corner, lassoPath)) {
        return true;
      }
    }

    for (const point of lassoPath) {
      if (this.isPointInsideBoundingBox(point, bounds)) {
        return true;
      }
    }

    for (let cornerIndex = 0; cornerIndex < corners.length; cornerIndex += 1) {
      const rectStart = corners[cornerIndex];
      const rectEnd = corners[(cornerIndex + 1) % corners.length];
      for (let lassoIndex = 0; lassoIndex < lassoPath.length; lassoIndex += 1) {
        const lassoStart = lassoPath[lassoIndex];
        const lassoEnd = lassoPath[(lassoIndex + 1) % lassoPath.length];
        if (this.doSegmentsIntersect(rectStart, rectEnd, lassoStart, lassoEnd)) {
          return true;
        }
      }
    }

    return false;
  }

  private buildStrokeSelectionTargets(strokes: Stroke[]): SelectionTarget[] {
    const bounds = this.getStrokeSelectionMaskBounds(strokes);
    if (bounds === null) {
      return [];
    }

    const strokeIds = strokes.map((stroke: Stroke): string => stroke.id);
    return this.buildStrokeSelectionOutlinePaths(strokes, bounds).map(
      (outline: StrokePoint[], index: number): SelectionTarget => {
        const outlineBounds = getBoundingBox(outline);
        return {
          id: `stroke_group_${index}_${strokeIds.join('_')}`,
          kind: 'strokeGroup',
          bounds: outlineBounds === null ? bounds : outlineBounds,
          outline,
          strokeIds: [...strokeIds],
          elementId: '',
          canMove: true,
          canShowMenu: true
        };
      }
    );
  }

  private getStrokeSelectionMaskBounds(strokes: Stroke[]): BoundingBox | null {
    let bounds: BoundingBox | null = null;
    for (const stroke of strokes) {
      const strokeBounds = getBoundingBox(stroke.points);
      if (strokeBounds === null) {
        continue;
      }

      const padding = stroke.style.width / 2 + STROKE_SELECTION_OUTLINE_PADDING + STROKE_SELECTION_MASK_CELL_SIZE;
      bounds = mergeBoundingBoxes(bounds, expandBoundingBox(strokeBounds, padding));
    }

    return bounds;
  }

  private buildStrokeSelectionOutlinePaths(strokes: Stroke[], bounds: BoundingBox): StrokePoint[][] {
    const cellSize = this.getStrokeSelectionMaskCellSize(bounds);
    const originX = bounds.minX;
    const originY = bounds.minY;
    const columnCount = Math.max(1, Math.ceil((bounds.maxX - bounds.minX) / cellSize) + 2);
    const rowCount = Math.max(1, Math.ceil((bounds.maxY - bounds.minY) / cellSize) + 2);
    const mask: boolean[] = new Array<boolean>(columnCount * rowCount).fill(false);

    for (const stroke of strokes) {
      const radius = Math.max(cellSize, stroke.style.width / 2 + STROKE_SELECTION_OUTLINE_PADDING);
      const sampledPoints = sampleStrokePoints(stroke.points, Math.max(1, cellSize / 2));
      for (const point of sampledPoints) {
        this.markMaskCircle(mask, columnCount, rowCount, originX, originY, cellSize, point, radius);
      }
    }

    const outlines = this.traceExteriorMaskBoundaryPaths(mask, columnCount, rowCount, originX, originY, cellSize);
    if (outlines.length === 0) {
      outlines.push(this.buildBoundsOutline(bounds));
    }

    return outlines;
  }

  private getStrokeSelectionMaskCellSize(bounds: BoundingBox): number {
    const width = Math.max(1, bounds.maxX - bounds.minX);
    const height = Math.max(1, bounds.maxY - bounds.minY);
    let cellSize = STROKE_SELECTION_MASK_CELL_SIZE;
    let columnCount = Math.max(1, Math.ceil(width / cellSize) + 2);
    let rowCount = Math.max(1, Math.ceil(height / cellSize) + 2);

    while (columnCount * rowCount > STROKE_SELECTION_MAX_MASK_CELLS) {
      cellSize *= 1.5;
      columnCount = Math.max(1, Math.ceil(width / cellSize) + 2);
      rowCount = Math.max(1, Math.ceil(height / cellSize) + 2);
    }

    return cellSize;
  }

  private markMaskCircle(
    mask: boolean[],
    columnCount: number,
    rowCount: number,
    originX: number,
    originY: number,
    cellSize: number,
    point: StrokePoint,
    radius: number
  ): void {
    const centerColumn = Math.floor((point.x - originX) / cellSize);
    const centerRow = Math.floor((point.y - originY) / cellSize);
    const cellRadius = Math.ceil(radius / cellSize);
    const radiusSquared = radius * radius;

    for (let row = centerRow - cellRadius; row <= centerRow + cellRadius; row += 1) {
      if (row < 0 || row >= rowCount) {
        continue;
      }

      for (let column = centerColumn - cellRadius; column <= centerColumn + cellRadius; column += 1) {
        if (column < 0 || column >= columnCount) {
          continue;
        }

        const cellCenterX = originX + (column + 0.5) * cellSize;
        const cellCenterY = originY + (row + 0.5) * cellSize;
        const deltaX = cellCenterX - point.x;
        const deltaY = cellCenterY - point.y;
        if (deltaX * deltaX + deltaY * deltaY <= radiusSquared) {
          mask[row * columnCount + column] = true;
        }
      }
    }
  }

  private traceExteriorMaskBoundaryPaths(
    mask: boolean[],
    columnCount: number,
    rowCount: number,
    originX: number,
    originY: number,
    cellSize: number
  ): StrokePoint[][] {
    const exteriorMask = this.buildExteriorEmptyMask(mask, columnCount, rowCount);
    const edges: BoundaryEdge[] = [];
    for (let row = 0; row < rowCount; row += 1) {
      for (let column = 0; column < columnCount; column += 1) {
        if (!this.isMaskFilled(mask, columnCount, rowCount, column, row)) {
          continue;
        }

        if (this.isExteriorEmptyCell(exteriorMask, columnCount, rowCount, column, row - 1)) {
          edges.push({ startColumn: column, startRow: row, endColumn: column + 1, endRow: row });
        }
        if (this.isExteriorEmptyCell(exteriorMask, columnCount, rowCount, column + 1, row)) {
          edges.push({ startColumn: column + 1, startRow: row, endColumn: column + 1, endRow: row + 1 });
        }
        if (this.isExteriorEmptyCell(exteriorMask, columnCount, rowCount, column, row + 1)) {
          edges.push({ startColumn: column + 1, startRow: row + 1, endColumn: column, endRow: row + 1 });
        }
        if (this.isExteriorEmptyCell(exteriorMask, columnCount, rowCount, column - 1, row)) {
          edges.push({ startColumn: column, startRow: row + 1, endColumn: column, endRow: row });
        }
      }
    }

    if (edges.length > STROKE_SELECTION_MAX_EDGE_COUNT) {
      return [];
    }

    return this.buildBoundaryPaths(edges).map((pathEdges: BoundaryEdge[]): StrokePoint[] => {
      return this.convertBoundaryPathToPoints(pathEdges, originX, originY, cellSize);
    });
  }

  private buildExteriorEmptyMask(mask: boolean[], columnCount: number, rowCount: number): boolean[] {
    const exteriorMask: boolean[] = new Array<boolean>(columnCount * rowCount).fill(false);
    const queue: number[] = [];

    for (let column = 0; column < columnCount; column += 1) {
      this.enqueueExteriorEmptyCell(mask, exteriorMask, queue, columnCount, rowCount, column, 0);
      this.enqueueExteriorEmptyCell(mask, exteriorMask, queue, columnCount, rowCount, column, rowCount - 1);
    }

    for (let row = 0; row < rowCount; row += 1) {
      this.enqueueExteriorEmptyCell(mask, exteriorMask, queue, columnCount, rowCount, 0, row);
      this.enqueueExteriorEmptyCell(mask, exteriorMask, queue, columnCount, rowCount, columnCount - 1, row);
    }

    let queueIndex = 0;
    while (queueIndex < queue.length) {
      const currentIndex = queue[queueIndex];
      queueIndex += 1;
      const column = currentIndex % columnCount;
      const row = Math.floor(currentIndex / columnCount);
      this.enqueueExteriorEmptyCell(mask, exteriorMask, queue, columnCount, rowCount, column + 1, row);
      this.enqueueExteriorEmptyCell(mask, exteriorMask, queue, columnCount, rowCount, column - 1, row);
      this.enqueueExteriorEmptyCell(mask, exteriorMask, queue, columnCount, rowCount, column, row + 1);
      this.enqueueExteriorEmptyCell(mask, exteriorMask, queue, columnCount, rowCount, column, row - 1);
    }

    return exteriorMask;
  }

  private enqueueExteriorEmptyCell(
    mask: boolean[],
    exteriorMask: boolean[],
    queue: number[],
    columnCount: number,
    rowCount: number,
    column: number,
    row: number
  ): void {
    if (column < 0 || column >= columnCount || row < 0 || row >= rowCount) {
      return;
    }

    const index = row * columnCount + column;
    if (mask[index] || exteriorMask[index]) {
      return;
    }

    exteriorMask[index] = true;
    queue.push(index);
  }

  private isExteriorEmptyCell(
    exteriorMask: boolean[],
    columnCount: number,
    rowCount: number,
    column: number,
    row: number
  ): boolean {
    if (column < 0 || column >= columnCount || row < 0 || row >= rowCount) {
      return true;
    }

    return exteriorMask[row * columnCount + column];
  }

  private buildBoundaryPaths(edges: BoundaryEdge[]): BoundaryEdge[][] {
    const edgeBuckets: Map<string, BoundaryEdge[]> = new Map<string, BoundaryEdge[]>();
    const startKeys: string[] = [];
    const paths: BoundaryEdge[][] = [];

    for (const edge of edges) {
      const key = this.getBoundaryPointKey(edge.startColumn, edge.startRow);
      let bucket = edgeBuckets.get(key);
      if (bucket === undefined) {
        bucket = [];
        edgeBuckets.set(key, bucket);
        startKeys.push(key);
      }
      bucket.push(edge);
    }

    let remainingEdgeCount = edges.length;
    let startKeyIndex = 0;
    while (remainingEdgeCount > 0) {
      const startEdge = this.takeNextBoundaryEdge(edgeBuckets, startKeys, startKeyIndex);
      if (startEdge.edge === null) {
        break;
      }

      startKeyIndex = startEdge.startKeyIndex;
      remainingEdgeCount -= 1;

      const path: BoundaryEdge[] = [startEdge.edge];
      while (path.length <= edges.length) {
        const tail = path[path.length - 1];
        const head = path[0];
        if (tail.endColumn === head.startColumn && tail.endRow === head.startRow) {
          break;
        }

        const bucket = edgeBuckets.get(this.getBoundaryPointKey(tail.endColumn, tail.endRow));
        if (bucket === undefined || bucket.length === 0) {
          break;
        }

        path.push(bucket.pop() as BoundaryEdge);
        remainingEdgeCount -= 1;
      }

      if (path.length > 0) {
        paths.push(path);
      }
    }

    return paths;
  }

  private takeNextBoundaryEdge(
    edgeBuckets: Map<string, BoundaryEdge[]>,
    startKeys: string[],
    startKeyIndex: number
  ): BoundaryStartEdge {
    for (let index = startKeyIndex; index < startKeys.length; index += 1) {
      const bucket = edgeBuckets.get(startKeys[index]);
      if (bucket !== undefined && bucket.length > 0) {
        return {
          edge: bucket.pop() as BoundaryEdge,
          startKeyIndex: index
        };
      }
    }

    return {
      edge: null,
      startKeyIndex: startKeys.length
    };
  }

  private getBoundaryPointKey(column: number, row: number): string {
    return `${column}:${row}`;
  }

  private convertBoundaryPathToPoints(
    pathEdges: BoundaryEdge[],
    originX: number,
    originY: number,
    cellSize: number
  ): StrokePoint[] {
    if (pathEdges.length === 0) {
      return [];
    }

    const points: StrokePoint[] = [{
      x: originX + pathEdges[0].startColumn * cellSize,
      y: originY + pathEdges[0].startRow * cellSize,
      t: 0
    }];

    for (const edge of pathEdges) {
      points.push({
        x: originX + edge.endColumn * cellSize,
        y: originY + edge.endRow * cellSize,
        t: 0
      });
    }

    return this.smoothClosedOutline(points);
  }

  private smoothClosedOutline(points: StrokePoint[]): StrokePoint[] {
    const outline = this.removeClosingDuplicatePoint(points);
    if (outline.length < 4) {
      return outline;
    }

    return this.simplifyClosedOutline(outline, STROKE_SELECTION_OUTLINE_SIMPLIFY_DISTANCE);
  }

  private removeClosingDuplicatePoint(points: StrokePoint[]): StrokePoint[] {
    if (points.length < 2) {
      return points;
    }

    const first = points[0];
    const last = points[points.length - 1];
    if (this.getPointDistance(first, last) < 0.001) {
      return points.slice(0, points.length - 1);
    }

    return points;
  }

  private simplifyClosedOutline(points: StrokePoint[], minDistance: number): StrokePoint[] {
    const simplified: StrokePoint[] = [points[0]];
    let lastKept = points[0];
    for (let index = 1; index < points.length; index += 1) {
      const point = points[index];
      if (this.getPointDistance(lastKept, point) >= minDistance) {
        simplified.push(point);
        lastKept = point;
      }
    }

    if (simplified.length >= 4 && this.getPointDistance(simplified[0], simplified[simplified.length - 1]) < minDistance) {
      simplified.pop();
    }

    return simplified.length >= 4 ? simplified : points;
  }

  private isMaskFilled(
    mask: boolean[],
    columnCount: number,
    rowCount: number,
    column: number,
    row: number
  ): boolean {
    if (column < 0 || column >= columnCount || row < 0 || row >= rowCount) {
      return false;
    }

    return mask[row * columnCount + column];
  }

  private buildBoundsOutline(bounds: BoundingBox): StrokePoint[] {
    return [
      { x: bounds.minX, y: bounds.minY, t: 0 },
      { x: bounds.maxX, y: bounds.minY, t: 0 },
      { x: bounds.maxX, y: bounds.maxY, t: 0 },
      { x: bounds.minX, y: bounds.maxY, t: 0 },
      { x: bounds.minX, y: bounds.minY, t: 0 }
    ];
  }

  private cloneIndexedStrokeRecord(record: IndexedStrokeRecord): IndexedStrokeRecord {
    return {
      index: record.index,
      stroke: this.cloneStroke(record.stroke)
    };
  }

  private cloneIndexedElementRecord(record: IndexedElementRecord): IndexedElementRecord {
    return {
      index: record.index,
      element: this.cloneElement(record.element)
    };
  }

  private getSelectedElementsInZOrderDescending(): CanvasElement[] {
    return this.getElementsInLayerOrderDescending(this.elements)
      .filter((element: CanvasElement): boolean => this.selectedElementIds.includes(element.id));
  }

  private getElementBoundingBox(element: CanvasElement): BoundingBox {
    if (element.type === 'shape' && element.shapeType === 'line' && element.geometry.points.length >= 2) {
      const startPoint = element.geometry.points[0];
      const endPoint = element.geometry.points[1];
      return expandBoundingBox({
        minX: Math.min(startPoint.x, endPoint.x),
        minY: Math.min(startPoint.y, endPoint.y),
        maxX: Math.max(startPoint.x, endPoint.x),
        maxY: Math.max(startPoint.y, endPoint.y)
      }, Math.max(ELEMENT_LINE_HIT_TOLERANCE, element.outline.width));
    }

    return {
      minX: element.x,
      minY: element.y,
      maxX: element.x + element.width,
      maxY: element.y + element.height
    };
  }

  private isPointInsideBoundingBox(point: StrokePoint, bounds: BoundingBox): boolean {
    return point.x >= bounds.minX && point.x <= bounds.maxX && point.y >= bounds.minY && point.y <= bounds.maxY;
  }

  private isPointInsidePolygon(point: StrokePoint, polygon: StrokePoint[]): boolean {
    if (polygon.length < 3) {
      return false;
    }

    let isInside = false;
    let previousIndex = polygon.length - 1;
    for (let currentIndex = 0; currentIndex < polygon.length; currentIndex += 1) {
      const current = polygon[currentIndex];
      const previous = polygon[previousIndex];
      const intersects = ((current.y > point.y) !== (previous.y > point.y)) &&
        (point.x < (previous.x - current.x) * (point.y - current.y) / (previous.y - current.y) + current.x);
      if (intersects) {
        isInside = !isInside;
      }
      previousIndex = currentIndex;
    }

    return isInside;
  }

  private doSegmentsIntersect(
    firstStart: StrokePoint,
    firstEnd: StrokePoint,
    secondStart: StrokePoint,
    secondEnd: StrokePoint
  ): boolean {
    const firstDirection = this.getSegmentOrientation(firstStart, firstEnd, secondStart);
    const secondDirection = this.getSegmentOrientation(firstStart, firstEnd, secondEnd);
    const thirdDirection = this.getSegmentOrientation(secondStart, secondEnd, firstStart);
    const fourthDirection = this.getSegmentOrientation(secondStart, secondEnd, firstEnd);

    if (firstDirection !== secondDirection && thirdDirection !== fourthDirection) {
      return true;
    }

    return (firstDirection === 0 && this.isPointOnSegment(secondStart, firstStart, firstEnd)) ||
      (secondDirection === 0 && this.isPointOnSegment(secondEnd, firstStart, firstEnd)) ||
      (thirdDirection === 0 && this.isPointOnSegment(firstStart, secondStart, secondEnd)) ||
      (fourthDirection === 0 && this.isPointOnSegment(firstEnd, secondStart, secondEnd));
  }

  private getSegmentToSegmentDistance(
    firstStart: StrokePoint,
    firstEnd: StrokePoint,
    secondStart: StrokePoint,
    secondEnd: StrokePoint
  ): number {
    if (this.doSegmentsIntersect(firstStart, firstEnd, secondStart, secondEnd)) {
      return 0;
    }

    return Math.min(
      getPointToSegmentDistance(firstStart, secondStart, secondEnd),
      getPointToSegmentDistance(firstEnd, secondStart, secondEnd),
      getPointToSegmentDistance(secondStart, firstStart, firstEnd),
      getPointToSegmentDistance(secondEnd, firstStart, firstEnd)
    );
  }

  private getSegmentOrientation(first: StrokePoint, second: StrokePoint, third: StrokePoint): number {
    const value = (second.y - first.y) * (third.x - second.x) - (second.x - first.x) * (third.y - second.y);
    if (Math.abs(value) < 0.0001) {
      return 0;
    }

    return value > 0 ? 1 : 2;
  }

  private isPointOnSegment(point: StrokePoint, segmentStart: StrokePoint, segmentEnd: StrokePoint): boolean {
    return point.x <= Math.max(segmentStart.x, segmentEnd.x) + 0.0001 &&
      point.x >= Math.min(segmentStart.x, segmentEnd.x) - 0.0001 &&
      point.y <= Math.max(segmentStart.y, segmentEnd.y) + 0.0001 &&
      point.y >= Math.min(segmentStart.y, segmentEnd.y) - 0.0001;
  }

  private getPointDistance(left: StrokePoint, right: StrokePoint): number {
    const deltaX = left.x - right.x;
    const deltaY = left.y - right.y;
    return Math.sqrt(deltaX * deltaX + deltaY * deltaY);
  }

  private getElementById(elementId: string): CanvasElement | null {
    const element = this.elements.find((candidate: CanvasElement): boolean => candidate.id === elementId);
    return element === undefined ? null : element;
  }

  private areElementsEquivalent(left: CanvasElement, right: CanvasElement): boolean {
    return JSON.stringify(left) === JSON.stringify(right);
  }

  private buildDrawableStrokeStyle(): StrokeStyle {
    return {
      tool: this.getDrawableTool(),
      color: this.toolSetting.color,
      width: this.toolSetting.width,
      opacity: this.toolSetting.opacity
    };
  }

  private getDrawableTool(): DrawableToolType {
    switch (this.toolSetting.tool) {
      case 'pen':
      case 'pencil':
      case 'highlighter':
        return this.toolSetting.tool;
      default:
        throw new Error('Eraser is not a drawable stroke tool.');
    }
  }

  private buildDerivedStrokeId(baseId: string, index: number, versionToken: number): string {
    return `${baseId}__split_${versionToken}_${index}`;
  }

  private arePointListsEqual(left: StrokePoint[], right: StrokePoint[]): boolean {
    if (left.length !== right.length) {
      return false;
    }

    for (let index = 0; index < left.length; index += 1) {
      if (!this.arePointsEqual(left[index], right[index])) {
        return false;
      }
    }

    return true;
  }

  private arePointsEqual(left: StrokePoint, right: StrokePoint): boolean {
    return (
      left.x === right.x &&
      left.y === right.y &&
      left.t === right.t &&
      left.pressure === right.pressure
    );
  }

  private cloneStrokes(strokes: Stroke[]): Stroke[] {
    return strokes.map((stroke: Stroke) => this.cloneStroke(stroke));
  }

  private countStrokePoints(strokes: Stroke[]): number {
    let pointCount = 0;
    for (const stroke of strokes) {
      pointCount += stroke.points.length;
    }
    return pointCount;
  }

  private cloneElements(elements: CanvasElement[]): CanvasElement[] {
    return elements.map((element: CanvasElement): CanvasElement => this.cloneElement(element));
  }

  private cloneElement(element: CanvasElement): CanvasElement {
    switch (element.type) {
      case 'text':
        return this.cloneTextElement(element);
      case 'shape':
        return this.cloneShapeElement(element);
      case 'image':
        return this.cloneImageElement(element);
      default:
        return this.cloneTextElement(element as TextCanvasElement);
    }
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
      outline: this.cloneElementOutline(element.outline ?? DEFAULT_TEXT_OUTLINE),
      recognition: element.recognition ? {
        source: element.recognition.source,
        sid: element.recognition.sid,
        recognizedAt: element.recognition.recognizedAt,
        rawText: element.recognition.rawText,
        latex: element.recognition.latex
      } : undefined
    };
  }

  private cloneShapeElement(element: ShapeCanvasElement): ShapeCanvasElement {
    return {
      id: element.id,
      pageId: element.pageId,
      type: 'shape',
      x: element.x,
      y: element.y,
      width: element.width,
      height: element.height,
      rotation: element.rotation,
      zIndex: element.zIndex,
      createdAt: element.createdAt,
      updatedAt: element.updatedAt,
      shapeType: element.shapeType,
      geometry: this.cloneShapeGeometry(element.geometry),
      fillColor: element.fillColor,
      outline: this.cloneElementOutline(element.outline),
      opacity: element.opacity
    };
  }

  private cloneElementOutline(outline: ElementOutlineStyle): ElementOutlineStyle {
    return {
      lineStyle: outline.lineStyle,
      color: outline.color,
      width: outline.width
    };
  }

  private cloneShapeGeometry(geometry: ShapeGeometry): ShapeGeometry {
    return {
      kind: geometry.kind,
      points: geometry.points.map((point: ShapeGeometryPoint): ShapeGeometryPoint => {
        return {
          x: point.x,
          y: point.y
        };
      })
    };
  }

  private cloneImageElement(element: ImageCanvasElement): ImageCanvasElement {
    return {
      id: element.id,
      pageId: element.pageId,
      type: 'image',
      x: element.x,
      y: element.y,
      width: element.width,
      height: element.height,
      rotation: element.rotation,
      zIndex: element.zIndex,
      createdAt: element.createdAt,
      updatedAt: element.updatedAt,
      uri: element.uri,
      originalWidth: element.originalWidth,
      originalHeight: element.originalHeight,
      opacity: element.opacity,
      outline: this.cloneElementOutline(element.outline),
      sourceFileUri: element.sourceFileUri,
      sourceFileType: element.sourceFileType
    };
  }

  private cloneStroke(stroke: Stroke): Stroke {
    return {
      id: stroke.id,
      pageId: stroke.pageId,
      renderKey: stroke.renderKey,
      renderWarmupPoints: stroke.renderWarmupPoints?.map((point: StrokePoint) => this.clonePoint(point)) ?? [],
      points: stroke.points.map((point: StrokePoint) => this.clonePoint(point)),
      style: this.cloneStyle(stroke.style),
      createdAt: stroke.createdAt,
      updatedAt: stroke.updatedAt
    };
  }

  private clonePoint(point: StrokePoint): StrokePoint {
    return {
      x: point.x,
      y: point.y,
      t: point.t,
      pressure: point.pressure
    };
  }

  private cloneStyle(style: StrokeStyle): StrokeStyle {
    return {
      tool: style.tool,
      color: style.color,
      width: style.width,
      opacity: style.opacity
    };
  }

  private getNextElementZIndex(): number {
    let maxZIndex = this.strokeLayerZIndex;
    for (const element of this.elements) {
      maxZIndex = Math.max(maxZIndex, element.zIndex);
    }

    return maxZIndex + 1;
  }

  private calculateInitialImageDisplaySize(asset: ImageInsertAsset, bounds: ElementBounds): ElementBounds {
    const maxWidth = Math.max(1, Math.min(MAX_IMAGE_INSERT_WIDTH, Math.max(1, bounds.width) * IMAGE_CANVAS_FILL_RATIO));
    const maxHeight = Math.max(1, Math.min(MAX_IMAGE_INSERT_HEIGHT, Math.max(1, bounds.height) * IMAGE_CANVAS_FILL_RATIO));
    const scale = Math.min(maxWidth / asset.originalWidth, maxHeight / asset.originalHeight, 1);

    return {
      width: Math.max(1, asset.originalWidth * scale),
      height: Math.max(1, asset.originalHeight * scale)
    };
  }

  private buildShapeFrameFromPoints(shapeType: ShapeType, startPoint: StrokePoint, currentPoint: StrokePoint): ElementFrame {
    const minX = Math.min(startPoint.x, currentPoint.x);
    const minY = Math.min(startPoint.y, currentPoint.y);
    const maxX = Math.max(startPoint.x, currentPoint.x);
    const maxY = Math.max(startPoint.y, currentPoint.y);

    switch (shapeType) {
      case 'line':
        return {
          x: minX,
          y: minY,
          width: maxX - minX,
          height: maxY - minY
        };
      case 'circle':
      case 'rectangle':
      default:
        return {
          x: minX,
          y: minY,
          width: maxX - minX,
          height: maxY - minY
        };
    }
  }

  private buildShapeGeometry(
    shapeType: ShapeType,
    startPoint: StrokePoint,
    currentPoint: StrokePoint
  ): ShapeGeometry {
    if (shapeType === 'line') {
      return {
        kind: 'line',
        points: [
          { x: startPoint.x, y: startPoint.y },
          { x: currentPoint.x, y: currentPoint.y }
        ]
      };
    }

    const frame = this.buildShapeFrameFromPoints(shapeType, startPoint, currentPoint);
    const geometryKind = shapeType === 'circle' ? 'ellipse' : 'rect';
    return {
      kind: geometryKind,
      points: [
        { x: frame.x, y: frame.y },
        { x: frame.x + frame.width, y: frame.y + frame.height }
      ]
    };
  }

  private isValidShapeFrame(
    shapeType: ShapeType,
    frame: ElementFrame,
    startPoint: StrokePoint,
    currentPoint: StrokePoint
  ): boolean {
    if (shapeType === 'line') {
      const deltaX = currentPoint.x - startPoint.x;
      const deltaY = currentPoint.y - startPoint.y;
      return Math.sqrt(deltaX * deltaX + deltaY * deltaY) >= MIN_SHAPE_DRAG_DISTANCE;
    }

    return frame.width >= MIN_SHAPE_DRAG_DISTANCE && frame.height >= MIN_SHAPE_DRAG_DISTANCE;
  }

  private hasVisibleShapeFrame(
    shapeType: ShapeType,
    frame: ElementFrame,
    startPoint: StrokePoint,
    currentPoint: StrokePoint
  ): boolean {
    if (shapeType === 'line') {
      return startPoint.x !== currentPoint.x || startPoint.y !== currentPoint.y;
    }

    return frame.width > 0 && frame.height > 0;
  }

  private clampPointToBounds(point: StrokePoint, bounds: ElementBounds): StrokePoint {
    return {
      x: this.clampNumber(point.x, 0, Math.max(0, bounds.width)),
      y: this.clampNumber(point.y, 0, Math.max(0, bounds.height)),
      t: point.t,
      pressure: point.pressure
    };
  }

  private clampNumber(value: number, minValue: number, maxValue: number): number {
    if (!Number.isFinite(value)) {
      return minValue;
    }

    return Math.min(Math.max(value, minValue), maxValue);
  }

  private isEraseGestureActive(): boolean {
    return this.eraseSourceStrokes !== null;
  }

  private markFullRenderInvalidation(reason: RenderInvalidationReason): void {
    this.renderInvalidationSequence += 1;
    this.lastRenderInvalidation = {
      sequence: this.renderInvalidationSequence,
      mode: 'full',
      reason,
      dirtyRects: [],
      removedStrokeIds: [],
      addedRecords: []
    };
  }

  private markPartialRenderInvalidation(
    reason: Exclude<RenderInvalidationReason, 'load'>,
    removed: IndexedStrokeRecord[],
    added: IndexedStrokeRecord[]
  ): void {
    const dirtyRects = this.buildDirtyRectsFromRecords(removed, added);
    if (dirtyRects.length === 0) {
      return;
    }

    this.renderInvalidationSequence += 1;
    this.lastRenderInvalidation = {
      sequence: this.renderInvalidationSequence,
      mode: 'partial',
      reason,
      dirtyRects,
      removedStrokeIds: removed.map((record: IndexedStrokeRecord) => record.stroke.id),
      addedRecords: added.map((record: IndexedStrokeRecord): IndexedStrokeRecord => ({
        index: record.index,
        stroke: record.stroke
      }))
    };
  }

  private buildDirtyRectsFromRecords(removed: IndexedStrokeRecord[], added: IndexedStrokeRecord[]): BoundingBox[] {
    const dirtyRects: BoundingBox[] = [];

    for (const record of removed) {
      const strokeBounds = getStrokeRenderBoundingBox(record.stroke);
      if (strokeBounds !== null) {
        dirtyRects.push(strokeBounds);
      }
    }

    for (const record of added) {
      const strokeBounds = getStrokeRenderBoundingBox(record.stroke);
      if (strokeBounds !== null) {
        dirtyRects.push(strokeBounds);
      }
    }

    return this.mergeOverlappingDirtyRects(dirtyRects);
  }

  private mergeOverlappingDirtyRects(dirtyRects: BoundingBox[]): BoundingBox[] {
    const mergedDirtyRects: BoundingBox[] = [];

    for (const dirtyRect of dirtyRects) {
      let nextRect: BoundingBox = {
        minX: dirtyRect.minX,
        minY: dirtyRect.minY,
        maxX: dirtyRect.maxX,
        maxY: dirtyRect.maxY
      };
      let hasMerged = true;

      while (hasMerged) {
        hasMerged = false;

        for (let index = mergedDirtyRects.length - 1; index >= 0; index -= 1) {
          if (!doBoundingBoxesIntersect(mergedDirtyRects[index], nextRect)) {
            continue;
          }

          const mergedRect = mergeBoundingBoxes(mergedDirtyRects[index], nextRect);
          if (mergedRect === null) {
            continue;
          }

          nextRect = mergedRect;
          mergedDirtyRects.splice(index, 1);
          hasMerged = true;
        }
      }

      mergedDirtyRects.push(nextRect);
    }

    return mergedDirtyRects;
  }

  private rebuildStrokeSpatialIndex(): void {
    this.strokeSpatialIndex.clear();
    for (const stroke of this.strokes) {
      this.strokeSpatialIndex.upsertStroke(stroke);
    }
  }

  private applyStrokeSpatialIndexMutation(removed: IndexedStrokeRecord[], added: IndexedStrokeRecord[]): void {
    for (const record of removed) {
      this.strokeSpatialIndex.removeStrokeById(record.stroke.id);
    }

    for (const record of added) {
      this.strokeSpatialIndex.upsertStroke(record.stroke);
    }
  }

  private cloneRenderInvalidation(invalidation: RenderInvalidation): RenderInvalidation {
    return {
      sequence: invalidation.sequence,
      mode: invalidation.mode,
      reason: invalidation.reason,
      dirtyRects: invalidation.dirtyRects.map((dirtyRect: BoundingBox): BoundingBox => ({
        minX: dirtyRect.minX,
        minY: dirtyRect.minY,
        maxX: dirtyRect.maxX,
        maxY: dirtyRect.maxY
      })),
      removedStrokeIds: [...invalidation.removedStrokeIds],
      addedRecords: invalidation.addedRecords.map((record: IndexedStrokeRecord): IndexedStrokeRecord => ({
        index: record.index,
        stroke: record.stroke
      }))
    };
  }

  private stringifyError(error: Object): string {
    if (error instanceof Error) {
      return error.message;
    }

    return `${error}`;
  }

  private createRepository(): EditorRepositoryImpl {
    return new EditorRepositoryImpl(this.contextProvider());
  }

  private nextDebugSequence(): number {
    this.debugSequence += 1;
    return this.debugSequence;
  }

  private describeHistoryState(): string {
    const historyState: UndoRedoDebugState = this.undoRedoController.getDebugState();
    return `undo=${historyState.undoDepth} redo=${historyState.redoDepth}`;
  }

  private describeToolSetting(setting: ToolSetting): string {
    return `${setting.tool} color=${setting.color} width=${setting.width} opacity=${setting.opacity.toFixed(2)}`;
  }

  private describeStroke(stroke: Stroke | null): string {
    if (!stroke) {
      return 'none';
    }

    return `${stroke.style.tool} color=${stroke.style.color} width=${stroke.style.width} opacity=${stroke.style.opacity.toFixed(2)} points=${stroke.points.length}`;
  }
}
