import { Stroke, StrokePoint, StrokeStyle } from '../../../domain/entities/Stroke';

const DEFAULT_HISTORY_LIMIT = 50;

export interface AppendStrokeOperation {
  type: 'append_stroke';
  stroke: Stroke;
}

export interface ReplacePageOperation {
  type: 'replace_page';
  before: Stroke[];
  after: Stroke[];
  label: 'erase' | 'clear';
}

export type EditorOperation = AppendStrokeOperation | ReplacePageOperation;

export interface UndoRedoSnapshot {
  undoStack: EditorOperation[];
  redoStack: EditorOperation[];
}

export interface UndoRedoDebugState {
  undoDepth: number;
  redoDepth: number;
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

  recordReplacePage(before: Stroke[], after: Stroke[], label: 'erase' | 'clear'): void {
    if (this.areStrokeListsEqual(before, after)) {
      return;
    }

    this.pushUndoOperation({
      type: 'replace_page',
      before: this.cloneStrokes(before),
      after: this.cloneStrokes(after),
      label
    });
  }

  undo(currentStrokes: Stroke[]): Stroke[] {
    const operation = this.undoStack.pop();
    if (!operation) {
      return this.cloneStrokes(currentStrokes);
    }

    this.redoStack.push(this.cloneOperation(operation));
    return this.applyInverse(operation, currentStrokes);
  }

  redo(currentStrokes: Stroke[]): Stroke[] {
    const operation = this.redoStack.pop();
    if (!operation) {
      return this.cloneStrokes(currentStrokes);
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

  private applyForward(operation: EditorOperation, currentStrokes: Stroke[]): Stroke[] {
    switch (operation.type) {
      case 'append_stroke': {
        const nextStrokes = this.cloneStrokes(currentStrokes);
        nextStrokes.push(this.cloneStroke(operation.stroke));
        return nextStrokes;
      }
      case 'replace_page':
        return this.cloneStrokes(operation.after);
      default:
        return this.cloneStrokes(currentStrokes);
    }
  }

  private applyInverse(operation: EditorOperation, currentStrokes: Stroke[]): Stroke[] {
    switch (operation.type) {
      case 'append_stroke':
        return this.removeStrokeById(currentStrokes, operation.stroke.id);
      case 'replace_page':
        return this.cloneStrokes(operation.before);
      default:
        return this.cloneStrokes(currentStrokes);
    }
  }

  private removeStrokeById(strokes: Stroke[], strokeId: string): Stroke[] {
    const nextStrokes = this.cloneStrokes(strokes);

    for (let index = nextStrokes.length - 1; index >= 0; index -= 1) {
      if (nextStrokes[index].id === strokeId) {
        nextStrokes.splice(index, 1);
        break;
      }
    }

    return nextStrokes;
  }

  private cloneOperation(operation: EditorOperation): EditorOperation {
    switch (operation.type) {
      case 'append_stroke':
        return {
          type: 'append_stroke',
          stroke: this.cloneStroke(operation.stroke)
        };
      case 'replace_page':
        return {
          type: 'replace_page',
          before: this.cloneStrokes(operation.before),
          after: this.cloneStrokes(operation.after),
          label: operation.label
        };
      default:
        return {
          type: 'replace_page',
          before: [],
          after: [],
          label: 'clear'
        };
    }
  }

  private areStrokeListsEqual(left: Stroke[], right: Stroke[]): boolean {
    if (left.length !== right.length) {
      return false;
    }

    for (let index = 0; index < left.length; index += 1) {
      if (!this.areStrokesEqual(left[index], right[index])) {
        return false;
      }
    }

    return true;
  }

  private areStrokesEqual(left: Stroke, right: Stroke): boolean {
    if (
      left.id !== right.id ||
      left.pageId !== right.pageId ||
      left.createdAt !== right.createdAt ||
      left.updatedAt !== right.updatedAt
    ) {
      return false;
    }

    if (
      left.style.tool !== right.style.tool ||
      left.style.color !== right.style.color ||
      left.style.width !== right.style.width ||
      left.style.opacity !== right.style.opacity
    ) {
      return false;
    }

    if (left.points.length !== right.points.length) {
      return false;
    }

    for (let index = 0; index < left.points.length; index += 1) {
      if (!this.arePointsEqual(left.points[index], right.points[index])) {
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
}
