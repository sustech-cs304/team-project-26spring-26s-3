import { Stroke, StrokePoint, StrokeStyle } from '../../../domain/entities/Stroke';

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
      stroke: this.cloneStroke(stroke)
    });
  }

  recordDelta(removed: IndexedStrokeRecord[], added: IndexedStrokeRecord[], label: 'erase' | 'clear'): void {
    if (removed.length === 0 && added.length === 0) {
      return;
    }

    this.pushUndoOperation({
      type: 'replace_page_delta',
      removed: removed.map((record: IndexedStrokeRecord) => this.cloneIndexedStrokeRecord(record)),
      added: added.map((record: IndexedStrokeRecord) => this.cloneIndexedStrokeRecord(record)),
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

    this.redoStack.push(this.cloneOperation(operation));
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

    this.undoStack.push(this.cloneOperation(operation));
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
      undoStack: this.undoStack.map((operation: EditorOperation) => this.cloneOperation(operation)),
      redoStack: this.redoStack.map((operation: EditorOperation) => this.cloneOperation(operation))
    };
  }

  restoreSnapshot(snapshot: UndoRedoSnapshot): void {
    this.undoStack = snapshot.undoStack.map((operation: EditorOperation) => this.cloneOperation(operation));
    this.redoStack = snapshot.redoStack.map((operation: EditorOperation) => this.cloneOperation(operation));
  }

  getDebugState(): UndoRedoDebugState {
    return {
      undoDepth: this.undoStack.length,
      redoDepth: this.redoStack.length
    };
  }

  private pushUndoOperation(operation: EditorOperation): void {
    this.undoStack.push(this.cloneOperation(operation));
    if (this.undoStack.length > this.historyLimit) {
      this.undoStack.shift();
    }
    this.redoStack = [];
  }

  private applyForward(operation: EditorOperation, currentStrokes: Stroke[]): UndoRedoApplyResult {
    switch (operation.type) {
      case 'append_stroke': {
        const nextStrokes = currentStrokes.slice();
        const addedStroke = this.cloneStroke(operation.stroke);
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

    const sortedAdded = added
      .map((record: IndexedStrokeRecord) => this.cloneIndexedStrokeRecord(record))
      .sort((left: IndexedStrokeRecord, right: IndexedStrokeRecord) => left.index - right.index);

    for (const record of sortedAdded) {
      const insertionIndex = Math.max(0, Math.min(record.index, nextStrokes.length));
      nextStrokes.splice(insertionIndex, 0, this.cloneStroke(record.stroke));
    }

    return {
      strokes: nextStrokes,
      removed: removed.map((record: IndexedStrokeRecord) => this.cloneIndexedStrokeRecord(record)),
      added: added.map((record: IndexedStrokeRecord) => this.cloneIndexedStrokeRecord(record))
    };
  }

  private removeStrokeById(strokes: Stroke[], strokeId: string): UndoRedoApplyResult {
    const nextStrokes = strokes.slice();
    let removedRecord: IndexedStrokeRecord | null = null;

    for (let index = nextStrokes.length - 1; index >= 0; index -= 1) {
      if (nextStrokes[index].id === strokeId) {
        removedRecord = {
          index,
          stroke: this.cloneStroke(nextStrokes[index])
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

  private cloneOperation(operation: EditorOperation): EditorOperation {
    switch (operation.type) {
      case 'append_stroke':
        return {
          type: 'append_stroke',
          stroke: this.cloneStroke(operation.stroke)
        };
      case 'replace_page_delta':
        return {
          type: 'replace_page_delta',
          removed: operation.removed.map((record: IndexedStrokeRecord) => this.cloneIndexedStrokeRecord(record)),
          added: operation.added.map((record: IndexedStrokeRecord) => this.cloneIndexedStrokeRecord(record)),
          label: operation.label
        };
      default:
        return {
          type: 'replace_page_delta',
          removed: [],
          added: [],
          label: 'clear'
        };
    }
  }

  private cloneIndexedStrokeRecord(record: IndexedStrokeRecord): IndexedStrokeRecord {
    return {
      index: record.index,
      stroke: this.cloneStroke(record.stroke)
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
}
