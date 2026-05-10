import common from '@ohos.app.ability.common';

import {
  BoundingBox,
  doBoundingBoxesIntersect,
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
  PAGE_CANVAS_CONTENT_VERSION,
  PageCanvasContent,
  ShapeCanvasElement,
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

const MAX_DEBUG_EVENTS = 20;
const SAVE_DEBOUNCE_MS = 900;
const EDITOR_BUILD_MARKER = 'editor-build-2026-04-20-state-link-sync-v1';
const DEFAULT_TEXT_ELEMENT_WIDTH = 220;
const DEFAULT_TEXT_ELEMENT_HEIGHT = 88;
const DEFAULT_TEXT_ELEMENT_TOP_OFFSET = 24;
const DEFAULT_SHAPE_STROKE_COLOR = '#111827';
const DEFAULT_SHAPE_STROKE_WIDTH = 2;
const DEFAULT_RECTANGLE_SHAPE_WIDTH = 160;
const DEFAULT_RECTANGLE_SHAPE_HEIGHT = 100;
const DEFAULT_CIRCLE_SHAPE_SIZE = 120;
const DEFAULT_LINE_SHAPE_WIDTH = 180;
const DEFAULT_LINE_SHAPE_HEIGHT = 2;
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
  private readonly instanceId: number = nextEditorViewModelInstanceId++;

  constructor(private readonly contextProvider: () => common.Context) {}

  async loadPage(pageId: string): Promise<void> {
    this.isLoading = true;
    this.errorMessage = '';
    this.pageId = pageId;
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

    const nextStrokes = this.strokes.slice();
    nextStrokes.push(completedStroke);
    this.strokes = nextStrokes;
    this.strokeSpatialIndex.upsertStroke(completedStroke);
    this.undoRedoController.recordAppendStroke(completedStroke);
    this.changeSequence += 1;
    this.persistenceStatus = 'pending stroke save';
    this.appendDebugEvent('finishStroke', `queuedSave count=${nextStrokes.length} stroke=${this.describeStroke(completedStroke)}`);
    this.schedulePersistCurrentStrokes('stroke');

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
    this.appendDebugEvent('undo', `requested count=${this.strokes.length} history=${this.describeHistoryState()}`);
    const undoResult: UndoRedoApplyResult = this.undoRedoController.undo(this.strokes);
    if (undoResult.removed.length === 0 && undoResult.added.length === 0) {
      this.appendDebugEvent('undo', 'skipped noChange');
      return;
    }

    this.strokes = undoResult.strokes;
    this.applyStrokeSpatialIndexMutation(undoResult.removed, undoResult.added);
    this.markPartialRenderInvalidation('undo', undoResult.removed, undoResult.added);
    this.changeSequence += 1;
    this.persistenceStatus = 'pending undo save';
    this.schedulePersistCurrentStrokes('undo', 0);
    this.errorMessage = '';
    this.appendDebugEvent('undo', `applied queuedSave count=${this.strokes.length} history=${this.describeHistoryState()}`);
  }

  async redo(): Promise<void> {
    if (this.pageId.length === 0) {
      this.errorMessage = 'Page is not loaded.';
      return;
    }

    this.cancelStroke();
    this.appendDebugEvent('redo', `requested count=${this.strokes.length} history=${this.describeHistoryState()}`);
    const redoResult: UndoRedoApplyResult = this.undoRedoController.redo(this.strokes);
    if (redoResult.removed.length === 0 && redoResult.added.length === 0) {
      this.appendDebugEvent('redo', 'skipped noChange');
      return;
    }

    this.strokes = redoResult.strokes;
    this.applyStrokeSpatialIndexMutation(redoResult.removed, redoResult.added);
    this.markPartialRenderInvalidation('redo', redoResult.removed, redoResult.added);
    this.changeSequence += 1;
    this.persistenceStatus = 'pending redo save';
    this.schedulePersistCurrentStrokes('redo', 0);
    this.errorMessage = '';
    this.appendDebugEvent('redo', `applied queuedSave count=${this.strokes.length} history=${this.describeHistoryState()}`);
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
    this.schedulePersistCurrentStrokes('clear', 0);
    this.errorMessage = '';
    this.appendDebugEvent('clear', `queuedSave history=${this.describeHistoryState()}`);
  }

  updateToolSetting(nextSetting: ToolSetting): void {
    if (this.isEraseGestureActive() || this.strokeController.hasActiveStroke()) {
      this.cancelStroke();
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

  insertTextElement(point: StrokePoint, bounds: ElementBounds): TextCanvasElement | null {
    if (this.pageId.length === 0) {
      this.errorMessage = 'Page is not loaded.';
      return null;
    }

    this.cancelStroke();
    const timestamp = now();
    const frame: ElementFrame = clampElementFrameToBounds({
      x: point.x - DEFAULT_TEXT_ELEMENT_WIDTH / 2,
      y: point.y - DEFAULT_TEXT_ELEMENT_TOP_OFFSET,
      width: DEFAULT_TEXT_ELEMENT_WIDTH,
      height: DEFAULT_TEXT_ELEMENT_HEIGHT
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
      fontSize: 18,
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

  insertShapeElement(point: StrokePoint, bounds: ElementBounds, shapeType: ShapeType): ShapeCanvasElement | null {
    if (this.pageId.length === 0) {
      this.errorMessage = 'Page is not loaded.';
      return null;
    }

    this.cancelStroke();
    const timestamp = now();
    const defaultFrame = this.buildDefaultShapeFrame(point, shapeType);
    const frame: ElementFrame = clampElementFrameToBounds(defaultFrame, bounds);
    const nextElement: ShapeCanvasElement = {
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
      shapeType,
      strokeColor: DEFAULT_SHAPE_STROKE_COLOR,
      fillColor: TRANSPARENT_ELEMENT_BACKGROUND_COLOR,
      strokeWidth: DEFAULT_SHAPE_STROKE_WIDTH,
      opacity: 1
    };

    this.elements = [...this.elements, nextElement];
    this.changeSequence += 1;
    this.persistenceStatus = 'pending shape save';
    this.schedulePersistCurrentStrokes('shape', 0);
    this.errorMessage = '';
    this.appendDebugEvent(
      'insertShape',
      `element=${nextElement.id} shape=${shapeType} x=${Math.round(nextElement.x)} y=${Math.round(nextElement.y)}`
    );
    return this.cloneShapeElement(nextElement);
  }

  updateTextElementContent(elementId: string, content: string): void {
    if (this.pageId.length === 0 || elementId.length === 0) {
      return;
    }

    let changed = false;
    const timestamp = now();
    this.elements = this.elements.map((element: CanvasElement): CanvasElement => {
      if (element.id !== elementId || element.type !== 'text') {
        return element;
      }

      if (element.content === content) {
        return element;
      }

      changed = true;
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
        content,
        color: element.color,
        fontSize: element.fontSize,
        backgroundColor: element.backgroundColor,
        updatedAt: timestamp
      };
    });

    if (!changed) {
      return;
    }

    this.changeSequence += 1;
    this.persistenceStatus = 'pending text edit save';
    this.schedulePersistCurrentStrokes('textEdit');
    this.errorMessage = '';
  }

  getActiveStroke(): Stroke | null {
    return this.strokeController.getActiveStroke();
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
    const eraseResult = this.eraseStrokes(sourceSnapshot, erasePath);
    this.clearEraseState();

    if (!eraseResult.changed) {
      this.strokes = sourceSnapshot;
      this.appendDebugEvent('erase', 'finish noChange');
      return null;
    }

    this.strokes = eraseResult.strokes;
    this.applyStrokeSpatialIndexMutation(eraseResult.removed, eraseResult.added);
    this.undoRedoController.recordDelta(eraseResult.removed, eraseResult.added, 'erase');
    this.markPartialRenderInvalidation('erase', eraseResult.removed, eraseResult.added);
    this.changeSequence += 1;
    this.persistenceStatus = 'pending erase save';
    this.schedulePersistCurrentStrokes('erase');
    this.errorMessage = '';
    this.appendDebugEvent('erase', `queuedSave count=${this.strokes.length} history=${this.describeHistoryState()}`);

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

    try {
      await this.createRepository().savePageContent(this.pageId, {
        version: PAGE_CANVAS_CONTENT_VERSION,
        strokes: strokeSnapshot,
        elements: elementSnapshot
      });
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

      if (remainingSegments.length === 1 && this.arePointListsEqual(remainingSegments[0], stroke.points)) {
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
        const nextStroke: Stroke = {
          id: this.buildDerivedStrokeId(stroke.id, segmentIndex, updateTime),
          pageId: stroke.pageId,
          points: remainingSegments[segmentIndex].map((point: StrokePoint) => this.clonePoint(point)),
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

  private cloneElements(elements: CanvasElement[]): CanvasElement[] {
    return elements.map((element: CanvasElement): CanvasElement => this.cloneElement(element));
  }

  private cloneElement(element: CanvasElement): CanvasElement {
    switch (element.type) {
      case 'text':
        return this.cloneTextElement(element);
      case 'shape':
        return this.cloneShapeElement(element);
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
      strokeColor: element.strokeColor,
      fillColor: element.fillColor,
      strokeWidth: element.strokeWidth,
      opacity: element.opacity
    };
  }

  private cloneStroke(stroke: Stroke): Stroke {
    return {
      id: stroke.id,
      pageId: stroke.pageId,
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

  private buildDefaultShapeFrame(point: StrokePoint, shapeType: ShapeType): ElementFrame {
    const size = this.getDefaultShapeSize(shapeType);
    return {
      x: point.x - size.width / 2,
      y: point.y - size.height / 2,
      width: size.width,
      height: size.height
    };
  }

  private getDefaultShapeSize(shapeType: ShapeType): ElementBounds {
    switch (shapeType) {
      case 'circle':
        return {
          width: DEFAULT_CIRCLE_SHAPE_SIZE,
          height: DEFAULT_CIRCLE_SHAPE_SIZE
        };
      case 'line':
        return {
          width: DEFAULT_LINE_SHAPE_WIDTH,
          height: DEFAULT_LINE_SHAPE_HEIGHT
        };
      case 'rectangle':
      default:
        return {
          width: DEFAULT_RECTANGLE_SHAPE_WIDTH,
          height: DEFAULT_RECTANGLE_SHAPE_HEIGHT
        };
    }
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
      dirtyRect: null,
      removedStrokeIds: [],
      addedRecords: []
    };
  }

  private markPartialRenderInvalidation(
    reason: Exclude<RenderInvalidationReason, 'load'>,
    removed: IndexedStrokeRecord[],
    added: IndexedStrokeRecord[]
  ): void {
    const dirtyRect = this.buildDirtyRectFromRecords(removed, added);
    if (dirtyRect === null) {
      return;
    }

    this.renderInvalidationSequence += 1;
    this.lastRenderInvalidation = {
      sequence: this.renderInvalidationSequence,
      mode: 'partial',
      reason,
      dirtyRect,
      removedStrokeIds: removed.map((record: IndexedStrokeRecord) => record.stroke.id),
      addedRecords: added.map((record: IndexedStrokeRecord): IndexedStrokeRecord => ({
        index: record.index,
        stroke: this.cloneStroke(record.stroke)
      }))
    };
  }

  private buildDirtyRectFromRecords(removed: IndexedStrokeRecord[], added: IndexedStrokeRecord[]): BoundingBox | null {
    let dirtyRect: BoundingBox | null = null;

    for (const record of removed) {
      dirtyRect = mergeBoundingBoxes(dirtyRect, getStrokeRenderBoundingBox(record.stroke));
    }

    for (const record of added) {
      dirtyRect = mergeBoundingBoxes(dirtyRect, getStrokeRenderBoundingBox(record.stroke));
    }

    return dirtyRect;
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
      dirtyRect: invalidation.dirtyRect === null ? null : {
        minX: invalidation.dirtyRect.minX,
        minY: invalidation.dirtyRect.minY,
        maxX: invalidation.dirtyRect.maxX,
        maxY: invalidation.dirtyRect.maxY
      },
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
