import common from '@ohos.app.ability.common';

import {
  BoundingBox,
  doBoundingBoxesIntersect,
  ErasedStrokeSegment,
  eraseStrokePointsWithPath,
  expandBoundingBox,
  getBoundingBox,
  getStrokeRenderBoundingBox,
  mergeBoundingBoxes,
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
  ImageCanvasElement,
  PAGE_CANVAS_CONTENT_VERSION,
  PageCanvasContent,
  ShapeCanvasElement,
  ShapeGeometry,
  ShapeGeometryPoint,
  ShapeType,
  TextCanvasElement,
  TRANSPARENT_ELEMENT_BACKGROUND_COLOR
} from '../../../domain/entities/CanvasElement';
import { Stroke, StrokePoint, StrokeStyle } from '../../../domain/entities/Stroke';
import { DrawableToolType, ToolSetting } from '../../../domain/entities/ToolSetting';
import { StrokeController } from '../controllers/StrokeController';
import { StrokeSpatialHashIndex } from '../controllers/StrokeSpatialHashIndex';
import {
  IndexedStrokeRecord,
  UndoRedoApplyResult,
  UndoRedoController,
  UndoRedoDebugState
} from '../controllers/UndoRedoController';
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

type ElementEditGestureKind =
  'move' |
  'resizeTopLeft' |
  'resizeTopRight' |
  'resizeBottomLeft' |
  'resizeBottomRight' |
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

export interface ImageInsertAsset {
  uri: string;
  originalWidth: number;
  originalHeight: number;
}

const MAX_DEBUG_EVENTS = 20;
const SAVE_DEBOUNCE_MS = 900;
const INTERACTION_SAVE_DEBOUNCE_MS = 180;
const EDITOR_BUILD_MARKER = 'editor-build-2026-04-20-state-link-sync-v1';
const DEFAULT_TEXT_ELEMENT_TOP_OFFSET = 24;
const DEFAULT_SHAPE_STROKE_COLOR = '#111827';
const DEFAULT_SHAPE_STROKE_WIDTH = 2;
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
const MIN_SHAPE_ELEMENT_SIZE = 8;
const MAX_IMAGE_INSERT_WIDTH = 420;
const MAX_IMAGE_INSERT_HEIGHT = 320;
const IMAGE_CANVAS_FILL_RATIO = 0.6;
let nextEditorViewModelInstanceId = 1;

export class DrawingEditorViewModel {
  private readonly strokeController: StrokeController = new StrokeController();
  private readonly undoRedoController: UndoRedoController = new UndoRedoController();
  private readonly strokeSpatialIndex: StrokeSpatialHashIndex = new StrokeSpatialHashIndex();

  private pageId: string = '';
  private strokes: Stroke[] = [];
  private elements: CanvasElement[] = [];
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
  private shapeDraft: ShapeDraft | null = null;
  private selectedElementId: string = '';
  private elementEditGesture: ElementEditGesture | null = null;
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
    this.strokeSpatialIndex.upsertStroke(completedStroke);
    this.undoRedoController.recordAppendStroke(completedStroke);
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
    const operationStartedAt = Date.now();
    const beforeStrokeCount = this.strokes.length;
    const beforePointCount = this.countStrokePoints(this.strokes);
    this.appendDebugEvent('undo', `requested count=${this.strokes.length} history=${this.describeHistoryState()}`);
    const undoResult: UndoRedoApplyResult = EditorPerformanceTrace.measureSync(
      'undo.controller',
      () => this.undoRedoController.undo(this.strokes),
      `beforeStrokes=${beforeStrokeCount} beforePoints=${beforePointCount}`,
      6
    );
    if (undoResult.removed.length === 0 && undoResult.added.length === 0) {
      this.appendDebugEvent('undo', 'skipped noChange');
      return;
    }

    const applyStartedAt = Date.now();
    this.strokes = undoResult.strokes;
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
    const operationStartedAt = Date.now();
    const beforeStrokeCount = this.strokes.length;
    const beforePointCount = this.countStrokePoints(this.strokes);
    this.appendDebugEvent('redo', `requested count=${this.strokes.length} history=${this.describeHistoryState()}`);
    const redoResult: UndoRedoApplyResult = EditorPerformanceTrace.measureSync(
      'redo.controller',
      () => this.undoRedoController.redo(this.strokes),
      `beforeStrokes=${beforeStrokeCount} beforePoints=${beforePointCount}`,
      6
    );
    if (redoResult.removed.length === 0 && redoResult.added.length === 0) {
      this.appendDebugEvent('redo', 'skipped noChange');
      return;
    }

    const applyStartedAt = Date.now();
    this.strokes = redoResult.strokes;
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
    const sourceSnapshot = this.cloneStrokes(this.strokes);
    if (sourceSnapshot.length === 0) {
      this.appendDebugEvent('clear', 'skipped empty');
      return;
    }

    this.appendDebugEvent('clear', `requested count=${sourceSnapshot.length} history=${this.describeHistoryState()}`);
    const applyStartedAt = Date.now();
    this.strokes = [];
    this.strokeSpatialIndex.clear();
    this.undoRedoController.recordDelta(
      sourceSnapshot.map((stroke: Stroke, index: number): IndexedStrokeRecord => ({
        index,
        stroke: this.cloneStroke(stroke)
      })),
      [],
      'clear'
    );
    this.markPartialRenderInvalidation(
      'clear',
      sourceSnapshot.map((stroke: Stroke, index: number): IndexedStrokeRecord => ({
        index,
        stroke: this.cloneStroke(stroke)
      })),
      []
    );
    this.changeSequence += 1;
    this.persistenceStatus = 'pending clear save';
    this.schedulePersistCurrentStrokes('clear', INTERACTION_SAVE_DEBOUNCE_MS);
    this.errorMessage = '';
    this.appendDebugEvent('clear', `queuedSave history=${this.describeHistoryState()}`);
    EditorPerformanceTrace.record(
      'clear.total',
      Date.now() - applyStartedAt,
      `removed=${sourceSnapshot.length} removedPoints=${this.countStrokePoints(sourceSnapshot)} persistDelay=${INTERACTION_SAVE_DEBOUNCE_MS}`,
      8
    );
  }

  updateToolSetting(nextSetting: ToolSetting): void {
    if (this.isEraseGestureActive() || this.strokeController.hasActiveStroke()) {
      this.cancelStroke();
    }
    this.cancelShapeDraft();
    if (nextSetting.tool !== 'edit') {
      this.clearElementSelection();
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

  getSelectedElementId(): string {
    return this.selectedElementId;
  }

  getSelectedElement(): CanvasElement | null {
    const selectedElement = this.elements.find((element: CanvasElement): boolean => element.id === this.selectedElementId);
    return selectedElement === undefined ? null : this.cloneElement(selectedElement);
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
    this.selectedElementId = '';
  }

  hasSelectedElement(): boolean {
    return this.selectedElementId.length > 0 &&
      this.elements.some((element: CanvasElement): boolean => element.id === this.selectedElementId);
  }

  isSelectedElementDeleteHit(point: StrokePoint, hitTolerance: number): boolean {
    const selectedElement = this.getElementById(this.selectedElementId);
    if (selectedElement === null) {
      return false;
    }

    const center = this.getDeleteButtonCenter(selectedElement);
    const radius = Math.max(12, hitTolerance);
    const deltaX = point.x - center.x;
    const deltaY = point.y - center.y;
    return Math.sqrt(deltaX * deltaX + deltaY * deltaY) <= radius;
  }

  deleteSelectedElement(): CanvasElement | null {
    const selectedElement = this.getElementById(this.selectedElementId);
    if (selectedElement === null) {
      this.clearElementSelection();
      return null;
    }

    this.elements = this.elements.filter((element: CanvasElement): boolean => element.id !== selectedElement.id);
    this.selectedElementId = '';
    this.elementEditGesture = null;
    this.changeSequence += 1;
    this.persistenceStatus = 'pending element delete save';
    this.schedulePersistCurrentStrokes('elementDelete', 0);
    this.errorMessage = '';
    this.appendDebugEvent('deleteElement', `element=${selectedElement.id} type=${selectedElement.type}`);
    return this.cloneElement(selectedElement);
  }

  beginElementEditGesture(point: StrokePoint, bounds: ElementBounds, hitTolerance: number): boolean {
    if (this.pageId.length === 0) {
      return false;
    }

    this.cancelStroke();
    this.cancelShapeDraft();

    const selectedElement = this.getElementById(this.selectedElementId);
    if (selectedElement !== null) {
      const handleKind = this.hitTestElementEditHandle(point, selectedElement, hitTolerance);
      if (handleKind !== null) {
        this.elementEditGesture = {
          elementId: selectedElement.id,
          kind: handleKind,
          startPoint: this.clonePoint(point),
          originalElement: this.cloneElement(selectedElement)
        };
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

    this.selectedElementId = hitElement.id;
    this.elementEditGesture = {
      elementId: hitElement.id,
      kind: 'move',
      startPoint: this.clonePoint(point),
      originalElement: this.cloneElement(hitElement)
    };
    this.appendDebugEvent('beginElementEdit', `element=${hitElement.id} kind=move`);
    return true;
  }

  updateElementEditGesture(point: StrokePoint, bounds: ElementBounds): boolean {
    if (this.elementEditGesture === null) {
      return false;
    }

    const nextElement = this.buildElementFromEditGesture(this.elementEditGesture, point, bounds);
    if (nextElement === null) {
      return false;
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
    const editedElement = this.getElementById(gesture.elementId);
    if (editedElement === null || this.areElementsEquivalent(gesture.originalElement, editedElement)) {
      return null;
    }

    this.selectedElementId = editedElement.id;
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
      backgroundColor: TRANSPARENT_ELEMENT_BACKGROUND_COLOR
    };

    this.elements = [...this.elements, nextElement];
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
      opacity: 1
    };

    this.elements = [...this.elements, nextElement];
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

    this.elements = [...this.elements, nextElement];
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
      strokeColor: DEFAULT_SHAPE_STROKE_COLOR,
      fillColor: TRANSPARENT_ELEMENT_BACKGROUND_COLOR,
      strokeWidth: DEFAULT_SHAPE_STROKE_WIDTH,
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
        updatedAt: timestamp
      };
      updatedTextElement = this.cloneTextElement(nextElement);
      return nextElement;
    });

    if (!changed) {
      return null;
    }

    this.changeSequence += 1;
    this.persistenceStatus = 'pending text edit save';
    this.schedulePersistCurrentStrokes('textEdit', 0);
    this.errorMessage = '';
    this.appendDebugEvent('textEdit', `element=${elementId} length=${content.length}`);
    return updatedTextElement;
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
    this.strokes = eraseResult.strokes;
    this.applyStrokeSpatialIndexMutation(eraseResult.removed, eraseResult.added);
    this.undoRedoController.recordDelta(eraseResult.removed, eraseResult.added, 'erase');
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
    this.selectedElementId = '';
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
            elements: elementSnapshot
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
    const sortedElements = this.elements
      .map((element: CanvasElement): CanvasElement => element)
      .sort((left: CanvasElement, right: CanvasElement): number => right.zIndex - left.zIndex);

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
      const verticalCenter = element.y + element.height / 2;
      if (this.isPointNearGeometryPoint(point, { x: element.x, y: verticalCenter }, hitTolerance)) {
        return 'resizeTextLeft';
      }

      if (this.isPointNearGeometryPoint(point, { x: element.x + element.width, y: verticalCenter }, hitTolerance)) {
        return 'resizeTextRight';
      }
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

    for (const handle of handles) {
      if (this.isPointNearGeometryPoint(point, handle.point, hitTolerance)) {
        return handle.kind;
      }
    }

    return null;
  }

  private isPointNearGeometryPoint(point: StrokePoint, targetPoint: ShapeGeometryPoint, tolerance: number): boolean {
    const deltaX = point.x - targetPoint.x;
    const deltaY = point.y - targetPoint.y;
    return Math.sqrt(deltaX * deltaX + deltaY * deltaY) <= Math.max(1, tolerance);
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
      case 'resizeTopRight':
      case 'resizeBottomLeft':
      case 'resizeBottomRight':
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

    const minSize = gesture.originalElement.type === 'image' ? MIN_IMAGE_ELEMENT_SIZE : MIN_SHAPE_ELEMENT_SIZE;
    const frame = this.clampFrameWithMinimumSize(targetFrame, bounds, minSize, minSize);
    return this.cloneElementWithFrame(gesture.originalElement, frame);
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
      case 'resizeTopRight':
        return this.normalizeFrame(left, clampedY, clampedX, bottom);
      case 'resizeBottomLeft':
        return this.normalizeFrame(clampedX, top, right, clampedY);
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
    const anchoredFrame = this.buildAnchoredTextFrame(
      originalElement,
      kind,
      this.clampFrameWithMinimumSize(
        targetFrame,
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

  private replaceElementInMemory(nextElement: CanvasElement): void {
    this.elements = this.elements.map((element: CanvasElement): CanvasElement => {
      return element.id === nextElement.id ? this.cloneElement(nextElement) : element;
    });
  }

  private getElementById(elementId: string): CanvasElement | null {
    const element = this.elements.find((candidate: CanvasElement): boolean => candidate.id === elementId);
    return element === undefined ? null : element;
  }

  private getDeleteButtonCenter(element: CanvasElement): ShapeGeometryPoint {
    if (element.type === 'shape' && element.shapeType === 'line' && element.geometry.points.length >= 2) {
      const startPoint = element.geometry.points[0];
      const endPoint = element.geometry.points[1];
      return {
        x: Math.max(startPoint.x, endPoint.x) - 8,
        y: Math.min(startPoint.y, endPoint.y) + 8
      };
    }

    return {
      x: element.x + Math.max(12, element.width - 18),
      y: element.y + 18
    };
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
      backgroundColor: element.backgroundColor
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
      strokeColor: element.strokeColor,
      fillColor: element.fillColor,
      strokeWidth: element.strokeWidth,
      opacity: element.opacity
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
      opacity: element.opacity
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
    let maxZIndex = 0;
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
        stroke: this.cloneStroke(record.stroke)
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
        stroke: this.cloneStroke(record.stroke)
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
