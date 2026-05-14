import { Stroke } from '../../../domain/entities/Stroke';

const DEFAULT_HISTORY_LIMIT = 50;

export interface AppendStrokeOperation {
  type: 'append_stroke';
  stroke: Stroke;
}

export interface IndexedStrokeRecord {
  index: number;
  stroke: Stroke;
}

export interface ReplacePageDeltaOperation {
  type: 'replace_page_delta';
  removed: IndexedStrokeRecord[];
  added: IndexedStrokeRecord[];
  label: 'erase' | 'clear';
}

export type EditorOperation = AppendStrokeOperation | ReplacePageDeltaOperation;

export interface UndoRedoSnapshot {
  undoStack: EditorOperation[];
  redoStack: EditorOperation[];
}

export interface UndoRedoDebugState {
  undoDepth: number;
  redoDepth: number;
}

export interface UndoRedoApplyResult {
  strokes: Stroke[];
  removed: IndexedStrokeRecord[];
  added: IndexedStrokeRecord[];
}

export class UndoRedoController {
  private undoStack: EditorOperation[] = [];
  private redoStack: EditorOperation[] = [];

  constructor(private readonly historyLimit: number = DEFAULT_HISTORY_LIMIT) {}

  recordAppendStroke(stroke: Stroke): void {
    this.pushUndoOperation({
      type: 'append_stroke',
      stroke
    });
  }

  recordDelta(removed: IndexedStrokeRecord[], added: IndexedStrokeRecord[], label: 'erase' | 'clear'): void {
    if (removed.length === 0 && added.length === 0) {
      return;
    }

    this.pushUndoOperation({
      type: 'replace_page_delta',
      removed: removed.map((record: IndexedStrokeRecord) => this.copyIndexedStrokeRecord(record)),
      added: added.map((record: IndexedStrokeRecord) => this.copyIndexedStrokeRecord(record)),
      label
    });
  }

  undo(currentStrokes: Stroke[]): UndoRedoApplyResult {
    const operation = this.undoStack.pop();
    if (!operation) {
      return {
        strokes: currentStrokes,
        removed: [],
        added: []
      };
    }

    this.redoStack.push(operation);
    return this.applyInverse(operation, currentStrokes);
  }

  redo(currentStrokes: Stroke[]): UndoRedoApplyResult {
    const operation = this.redoStack.pop();
    if (!operation) {
      return {
        strokes: currentStrokes,
        removed: [],
        added: []
      };
    }

    this.undoStack.push(operation);
    return this.applyForward(operation, currentStrokes);
  }

  canUndo(): boolean {
    return this.undoStack.length > 0;
  }

  canRedo(): boolean {
    return this.redoStack.length > 0;
  }

  reset(): void {
    this.undoStack = [];
    this.redoStack = [];
  }

  seedLoadedStrokes(strokes: Stroke[]): void {
    this.reset();
  }

  createSnapshot(): UndoRedoSnapshot {
    return {
      undoStack: this.undoStack.slice(),
      redoStack: this.redoStack.slice()
    };
  }

  restoreSnapshot(snapshot: UndoRedoSnapshot): void {
    this.undoStack = snapshot.undoStack.slice();
    this.redoStack = snapshot.redoStack.slice();
  }

  getDebugState(): UndoRedoDebugState {
    return {
      undoDepth: this.undoStack.length,
      redoDepth: this.redoStack.length
    };
  }

  private pushUndoOperation(operation: EditorOperation): void {
    // Completed strokes are treated as immutable records after they enter history.
    this.undoStack.push(operation);
    if (this.undoStack.length > this.historyLimit) {
      this.undoStack.shift();
    }
    this.redoStack = [];
  }

  private applyForward(operation: EditorOperation, currentStrokes: Stroke[]): UndoRedoApplyResult {
    switch (operation.type) {
      case 'append_stroke': {
        const nextStrokes = currentStrokes.slice();
        const addedStroke = operation.stroke;
        nextStrokes.push(addedStroke);
        return {
          strokes: nextStrokes,
          removed: [],
          added: [{
            index: currentStrokes.length,
            stroke: addedStroke
          }]
        };
      }
      case 'replace_page_delta':
        return this.applyDelta(currentStrokes, operation.removed, operation.added);
      default:
        return {
          strokes: currentStrokes,
          removed: [],
          added: []
        };
    }
  }

  private applyInverse(operation: EditorOperation, currentStrokes: Stroke[]): UndoRedoApplyResult {
    switch (operation.type) {
      case 'append_stroke':
        return this.removeStrokeById(currentStrokes, operation.stroke.id);
      case 'replace_page_delta':
        return this.applyDelta(currentStrokes, operation.added, operation.removed);
      default:
        return {
          strokes: currentStrokes,
          removed: [],
          added: []
        };
    }
  }

  private applyDelta(
    currentStrokes: Stroke[],
    removed: IndexedStrokeRecord[],
    added: IndexedStrokeRecord[]
  ): UndoRedoApplyResult {
    if (removed.length === 0 && added.length === 0) {
      return {
        strokes: currentStrokes,
        removed,
        added
      };
    }

    const nextStrokes = currentStrokes.slice();
    const removedIds = new Set<string>();

    for (const record of removed) {
      removedIds.add(record.stroke.id);
    }

    for (let index = nextStrokes.length - 1; index >= 0; index -= 1) {
      if (removedIds.has(nextStrokes[index].id)) {
        nextStrokes.splice(index, 1);
      }
    }

    const sortedAdded = added.length < 2
      ? added
      : added.slice().sort((left: IndexedStrokeRecord, right: IndexedStrokeRecord) => left.index - right.index);

    for (const record of sortedAdded) {
      const insertionIndex = Math.max(0, Math.min(record.index, nextStrokes.length));
      nextStrokes.splice(insertionIndex, 0, record.stroke);
    }

    return {
      strokes: nextStrokes,
      removed,
      added
    };
  }

  private removeStrokeById(strokes: Stroke[], strokeId: string): UndoRedoApplyResult {
    const lastIndex = strokes.length - 1;
    if (lastIndex >= 0 && strokes[lastIndex].id === strokeId) {
      return {
        strokes: strokes.slice(0, lastIndex),
        removed: [{
          index: lastIndex,
          stroke: strokes[lastIndex]
        }],
        added: []
      };
    }

    const nextStrokes = strokes.slice();
    let removedRecord: IndexedStrokeRecord | null = null;

    for (let index = nextStrokes.length - 1; index >= 0; index -= 1) {
      if (nextStrokes[index].id === strokeId) {
        removedRecord = {
          index,
          stroke: nextStrokes[index]
        };
        nextStrokes.splice(index, 1);
        break;
      }
    }

    return {
      strokes: nextStrokes,
      removed: removedRecord === null ? [] : [removedRecord],
      added: []
    };
  }

  private copyIndexedStrokeRecord(record: IndexedStrokeRecord): IndexedStrokeRecord {
    return {
      index: record.index,
      stroke: record.stroke
    };
  }
}
