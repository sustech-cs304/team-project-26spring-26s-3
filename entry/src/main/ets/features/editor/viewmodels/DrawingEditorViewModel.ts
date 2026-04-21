import common from '@ohos.app.ability.common';

import {
  doBoundingBoxesIntersect,
  eraseStrokePointsWithPath,
  expandBoundingBox,
  getBoundingBox,
  isSamePoint
} from '../../../common/utils/GeometryUtil';
import { now } from '../../../common/utils/TimeUtil';
import { EditorRepositoryImpl } from '../../../data/repositories/EditorRepositoryImpl';
import { Stroke, StrokePoint, StrokeStyle } from '../../../domain/entities/Stroke';
import { DrawableToolType, ToolSetting } from '../../../domain/entities/ToolSetting';
import { SaveStroke } from '../../../domain/usecases/SaveStroke';
import { StrokeController } from '../controllers/StrokeController';
import { UndoRedoController, UndoRedoDebugState } from '../controllers/UndoRedoController';
import { EditorDebugSnapshot } from './EditorDebugSnapshot';

const DEFAULT_TOOL_SETTING: ToolSetting = {
  tool: 'pen',
  color: '#111827',
  width: 4,
  opacity: 1
};

interface EraseResult {
  strokes: Stroke[];
  changed: boolean;
}

const MAX_DEBUG_EVENTS = 20;
const SAVE_DEBOUNCE_MS = 900;
const EDITOR_BUILD_MARKER = 'editor-build-2026-04-20-state-link-sync-v1';
let nextEditorViewModelInstanceId = 1;

export class DrawingEditorViewModel {
  private readonly strokeController: StrokeController = new StrokeController();
  private readonly undoRedoController: UndoRedoController = new UndoRedoController();

  private pageId: string = '';
  private strokes: Stroke[] = [];
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
      this.strokes = await this.createRepository().getStrokes(pageId);
      this.resetTransientState();
      this.undoRedoController.seedLoadedStrokes(this.strokes);
      this.persistenceStatus = `loaded count=${this.strokes.length}`;
      this.appendDebugEvent('loadPage', `loaded strokes=${this.strokes.length}`);
    } catch (error) {
      this.errorMessage = this.stringifyError(error);
      this.strokes = [];
      this.resetTransientState();
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
    this.undoRedoController.recordAppendStroke(completedStroke);
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

  async undo(): Promise<Stroke[]> {
    if (this.pageId.length === 0) {
      this.errorMessage = 'Page is not loaded.';
      return this.getStrokes();
    }

    this.cancelStroke();
    const sourceSnapshot = this.cloneStrokes(this.strokes);
    const historySnapshot = this.undoRedoController.createSnapshot();
    this.appendDebugEvent('undo', `requested count=${this.strokes.length} history=${this.describeHistoryState()}`);

    try {
      const nextStrokes = this.undoRedoController.undo(this.strokes);
      this.strokes = nextStrokes;
      this.persistenceStatus = 'pending undo save';
      this.schedulePersistCurrentStrokes('undo', 0);
      this.errorMessage = '';
      this.appendDebugEvent('undo', `applied queuedSave count=${this.strokes.length} history=${this.describeHistoryState()}`);
    } catch (error) {
      this.strokes = sourceSnapshot;
      this.undoRedoController.restoreSnapshot(historySnapshot);
      this.errorMessage = this.stringifyError(error);
      this.persistenceStatus = `undoFailed restored error=${this.errorMessage}`;
      this.appendDebugEvent('undo', `failed restored error=${this.errorMessage}`);
    }

    return this.getStrokes();
  }

  async redo(): Promise<Stroke[]> {
    if (this.pageId.length === 0) {
      this.errorMessage = 'Page is not loaded.';
      return this.getStrokes();
    }

    this.cancelStroke();
    const sourceSnapshot = this.cloneStrokes(this.strokes);
    const historySnapshot = this.undoRedoController.createSnapshot();
    this.appendDebugEvent('redo', `requested count=${this.strokes.length} history=${this.describeHistoryState()}`);

    try {
      const nextStrokes = this.undoRedoController.redo(this.strokes);
      this.strokes = nextStrokes;
      this.persistenceStatus = 'pending redo save';
      this.schedulePersistCurrentStrokes('redo', 0);
      this.errorMessage = '';
      this.appendDebugEvent('redo', `applied queuedSave count=${this.strokes.length} history=${this.describeHistoryState()}`);
    } catch (error) {
      this.strokes = sourceSnapshot;
      this.undoRedoController.restoreSnapshot(historySnapshot);
      this.errorMessage = this.stringifyError(error);
      this.persistenceStatus = `redoFailed restored error=${this.errorMessage}`;
      this.appendDebugEvent('redo', `failed restored error=${this.errorMessage}`);
    }

    return this.getStrokes();
  }

  async clear(): Promise<void> {
    if (this.pageId.length === 0) {
      this.errorMessage = 'Page is not loaded.';
      return;
    }

    this.cancelStroke();
    const sourceSnapshot = this.cloneStrokes(this.strokes);
    this.appendDebugEvent('clear', `requested count=${sourceSnapshot.length} history=${this.describeHistoryState()}`);
    this.strokes = [];
    this.undoRedoController.recordReplacePage(sourceSnapshot, [], 'clear');
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

  async flushPendingSave(): Promise<void> {
    this.clearScheduledSave();
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
    this.undoRedoController.recordReplacePage(sourceSnapshot, this.strokes, 'erase');
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

    this.isPersisting = true;
    const snapshot = this.cloneStrokes(this.strokes);
    this.persistenceStatus = `saving ${reason}`;

    try {
      await this.createSaveStrokeUseCase().execute(this.pageId, snapshot);
      this.errorMessage = '';
      this.persistenceStatus = `saved ${reason} count=${snapshot.length}`;
      this.appendDebugEvent('persist', `saved reason=${reason} count=${snapshot.length}`);
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
        changed: false
      };
    }

    const result: Stroke[] = [];
    let changed = false;
    const expandedEraserBounds = expandBoundingBox(eraserBounds, this.toolSetting.width / 2);
    const updateTime = now();

    for (const stroke of sourceStrokes) {
      const strokeBounds = getBoundingBox(stroke.points);
      if (!strokeBounds) {
        continue;
      }

      const expandedStrokeBounds = expandBoundingBox(strokeBounds, stroke.style.width / 2);
      if (!doBoundingBoxesIntersect(expandedEraserBounds, expandedStrokeBounds)) {
        result.push(this.cloneStroke(stroke));
        continue;
      }

      const effectiveRadius = Math.max(1, this.toolSetting.width / 2 + stroke.style.width / 2);
      const samplingStep = Math.max(1, Math.min(this.toolSetting.width, stroke.style.width) / 2);
      const remainingSegments = eraseStrokePointsWithPath(stroke.points, eraserPath, effectiveRadius, samplingStep);

      if (remainingSegments.length === 1 && this.arePointListsEqual(remainingSegments[0], stroke.points)) {
        result.push(this.cloneStroke(stroke));
        continue;
      }

      changed = true;

      for (let index = 0; index < remainingSegments.length; index += 1) {
        result.push({
          id: this.buildDerivedStrokeId(stroke.id, index),
          pageId: stroke.pageId,
          points: remainingSegments[index].map((point: StrokePoint) => this.clonePoint(point)),
          style: this.cloneStyle(stroke.style),
          createdAt: stroke.createdAt,
          updatedAt: updateTime
        });
      }
    }

    return {
      strokes: result,
      changed
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

  private buildDerivedStrokeId(baseId: string, index: number): string {
    if (index === 0) {
      return baseId;
    }

    return `${baseId}__split_${index}`;
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

  private isEraseGestureActive(): boolean {
    return this.eraseSourceStrokes !== null;
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

  private createSaveStrokeUseCase(): SaveStroke {
    return new SaveStroke(this.createRepository());
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
