import { Stroke, StrokePoint, StrokeStyle } from '../../../domain/entities/Stroke';
import {
  CanvasElement,
  ElementOutlineStyle,
  ImageCanvasElement,
  ShapeCanvasElement,
  ShapeGeometry,
  ShapeGeometryPoint,
  TextCanvasElement
} from '../../../domain/entities/CanvasElement';
import { SelectionTarget } from '../selection/SelectionTypes';

const DEFAULT_HISTORY_LIMIT = 50;
export type EditorDeltaLabel =
  'erase' |
  'delete' |
  'copy' |
  'clear' |
  'move' |
  'resize' |
  'elementInsert' |
  'elementEdit' |
  'elementStyle' |
  'elementDelete' |
  'textEdit';

export interface AppendStrokeOperation {
  type: 'append_stroke';
  stroke: Stroke;
}

export interface IndexedStrokeRecord {
  index: number;
  stroke: Stroke;
}

export interface IndexedElementRecord {
  index: number;
  element: CanvasElement;
}

export interface EditorSelectionSnapshot {
  strokeIds: string[];
  strokeTargets: SelectionTarget[];
  elementIds: string[];
}

export interface ReplacePageDeltaOperation {
  type: 'replace_page_delta';
  removed: IndexedStrokeRecord[];
  added: IndexedStrokeRecord[];
  removedElements: IndexedElementRecord[];
  addedElements: IndexedElementRecord[];
  beforeSelection?: EditorSelectionSnapshot;
  afterSelection?: EditorSelectionSnapshot;
  label: EditorDeltaLabel;
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
  elements: CanvasElement[];
  removed: IndexedStrokeRecord[];
  added: IndexedStrokeRecord[];
  removedElements: IndexedElementRecord[];
  addedElements: IndexedElementRecord[];
  selection: EditorSelectionSnapshot | null;
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

  recordDelta(
    removed: IndexedStrokeRecord[],
    added: IndexedStrokeRecord[],
    label: EditorDeltaLabel,
    removedElements: IndexedElementRecord[] = [],
    addedElements: IndexedElementRecord[] = [],
    beforeSelection: EditorSelectionSnapshot = UndoRedoController.createEmptySelectionSnapshot(),
    afterSelection: EditorSelectionSnapshot = UndoRedoController.createEmptySelectionSnapshot()
  ): void {
    if (removed.length === 0 && added.length === 0 && removedElements.length === 0 && addedElements.length === 0) {
      return;
    }

    this.pushUndoOperation({
      type: 'replace_page_delta',
      removed: removed.map((record: IndexedStrokeRecord) => this.cloneIndexedStrokeRecord(record)),
      added: added.map((record: IndexedStrokeRecord) => this.cloneIndexedStrokeRecord(record)),
      removedElements: removedElements.map((record: IndexedElementRecord) => this.cloneIndexedElementRecord(record)),
      addedElements: addedElements.map((record: IndexedElementRecord) => this.cloneIndexedElementRecord(record)),
      beforeSelection: this.cloneSelectionSnapshot(beforeSelection),
      afterSelection: this.cloneSelectionSnapshot(afterSelection),
      label
    });
  }

  undo(currentStrokes: Stroke[], currentElements: CanvasElement[] = []): UndoRedoApplyResult {
    const operation = this.undoStack.pop();
    if (!operation) {
      return {
        strokes: currentStrokes.slice(),
        elements: currentElements.slice(),
        removed: [],
        added: [],
        removedElements: [],
        addedElements: [],
        selection: null
      };
    }

    this.redoStack.push(this.cloneOperation(operation));
    return this.applyInverse(operation, currentStrokes, currentElements);
  }

  redo(currentStrokes: Stroke[], currentElements: CanvasElement[] = []): UndoRedoApplyResult {
    const operation = this.redoStack.pop();
    if (!operation) {
      return {
        strokes: currentStrokes.slice(),
        elements: currentElements.slice(),
        removed: [],
        added: [],
        removedElements: [],
        addedElements: [],
        selection: null
      };
    }

    this.undoStack.push(this.cloneOperation(operation));
    return this.applyForward(operation, currentStrokes, currentElements);
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

  private applyForward(
    operation: EditorOperation,
    currentStrokes: Stroke[],
    currentElements: CanvasElement[]
  ): UndoRedoApplyResult {
    switch (operation.type) {
      case 'append_stroke': {
        const nextStrokes = currentStrokes.slice();
        const addedStroke = this.cloneStroke(operation.stroke);
        nextStrokes.push(this.cloneStroke(operation.stroke));
        return {
          strokes: nextStrokes,
          elements: currentElements.map((element: CanvasElement): CanvasElement => this.cloneElement(element)),
          removed: [],
          added: [{
            index: currentStrokes.length,
            stroke: addedStroke
          }],
          removedElements: [],
          addedElements: [],
          selection: UndoRedoController.createEmptySelectionSnapshot()
        };
      }
      case 'replace_page_delta':
        return this.applyDelta(
          currentStrokes,
          currentElements,
          operation.removed,
          operation.added,
          operation.removedElements,
          operation.addedElements,
          operation.afterSelection
        );
      default:
        return {
          strokes: currentStrokes.slice(),
          elements: currentElements.slice(),
          removed: [],
          added: [],
          removedElements: [],
          addedElements: [],
          selection: null
        };
    }
  }

  private applyInverse(
    operation: EditorOperation,
    currentStrokes: Stroke[],
    currentElements: CanvasElement[]
  ): UndoRedoApplyResult {
    switch (operation.type) {
      case 'append_stroke':
        return this.removeStrokeById(currentStrokes, currentElements, operation.stroke.id);
      case 'replace_page_delta':
        return this.applyDelta(
          currentStrokes,
          currentElements,
          operation.added,
          operation.removed,
          operation.addedElements,
          operation.removedElements,
          operation.beforeSelection
        );
      default:
        return {
          strokes: currentStrokes.slice(),
          elements: currentElements.slice(),
          removed: [],
          added: [],
          removedElements: [],
          addedElements: [],
          selection: null
        };
    }
  }

  private applyDelta(
    currentStrokes: Stroke[],
    currentElements: CanvasElement[],
    removed: IndexedStrokeRecord[],
    added: IndexedStrokeRecord[],
    removedElements: IndexedElementRecord[],
    addedElements: IndexedElementRecord[],
    selection: EditorSelectionSnapshot | undefined
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

    const nextElements = currentElements.slice();
    const removedElementIds = new Set<string>();
    for (const record of removedElements) {
      removedElementIds.add(record.element.id);
    }

    for (let index = nextElements.length - 1; index >= 0; index -= 1) {
      if (removedElementIds.has(nextElements[index].id)) {
        nextElements.splice(index, 1);
      }
    }

    const sortedAddedElements = addedElements
      .map((record: IndexedElementRecord) => this.cloneIndexedElementRecord(record))
      .sort((left: IndexedElementRecord, right: IndexedElementRecord) => left.index - right.index);

    for (const record of sortedAddedElements) {
      const insertionIndex = Math.max(0, Math.min(record.index, nextElements.length));
      nextElements.splice(insertionIndex, 0, this.cloneElement(record.element));
    }

    return {
      strokes: nextStrokes,
      elements: nextElements,
      removed: removed.map((record: IndexedStrokeRecord) => this.cloneIndexedStrokeRecord(record)),
      added: added.map((record: IndexedStrokeRecord) => this.cloneIndexedStrokeRecord(record)),
      removedElements: removedElements.map((record: IndexedElementRecord) => this.cloneIndexedElementRecord(record)),
      addedElements: addedElements.map((record: IndexedElementRecord) => this.cloneIndexedElementRecord(record)),
      selection: this.cloneSelectionSnapshot(selection ?? UndoRedoController.createEmptySelectionSnapshot())
    };
  }

  private removeStrokeById(
    strokes: Stroke[],
    elements: CanvasElement[],
    strokeId: string
  ): UndoRedoApplyResult {
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
      elements: elements.map((element: CanvasElement): CanvasElement => this.cloneElement(element)),
      removed: removedRecord === null ? [] : [removedRecord],
      added: [],
      removedElements: [],
      addedElements: [],
      selection: UndoRedoController.createEmptySelectionSnapshot()
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
          removedElements: operation.removedElements.map((record: IndexedElementRecord) =>
            this.cloneIndexedElementRecord(record)),
          addedElements: operation.addedElements.map((record: IndexedElementRecord) =>
            this.cloneIndexedElementRecord(record)),
          beforeSelection: this.cloneSelectionSnapshot(
            operation.beforeSelection ?? UndoRedoController.createEmptySelectionSnapshot()
          ),
          afterSelection: this.cloneSelectionSnapshot(
            operation.afterSelection ?? UndoRedoController.createEmptySelectionSnapshot()
          ),
          label: operation.label
        };
      default:
        return {
          type: 'replace_page_delta',
          removed: [],
          added: [],
          removedElements: [],
          addedElements: [],
          beforeSelection: UndoRedoController.createEmptySelectionSnapshot(),
          afterSelection: UndoRedoController.createEmptySelectionSnapshot(),
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

  private cloneIndexedElementRecord(record: IndexedElementRecord): IndexedElementRecord {
    return {
      index: record.index,
      element: this.cloneElement(record.element)
    };
  }

  private cloneSelectionSnapshot(snapshot: EditorSelectionSnapshot): EditorSelectionSnapshot {
    return {
      strokeIds: [...snapshot.strokeIds],
      strokeTargets: snapshot.strokeTargets.map((target: SelectionTarget): SelectionTarget =>
        UndoRedoController.cloneSelectionTarget(target)),
      elementIds: [...snapshot.elementIds]
    };
  }

  private static createEmptySelectionSnapshot(): EditorSelectionSnapshot {
    return {
      strokeIds: [],
      strokeTargets: [],
      elementIds: []
    };
  }

  private static cloneSelectionTarget(target: SelectionTarget): SelectionTarget {
    return {
      id: target.id,
      kind: target.kind,
      bounds: { ...target.bounds },
      outline: target.outline.map((point: StrokePoint): StrokePoint => ({
        x: point.x,
        y: point.y,
        t: point.t,
        pressure: point.pressure
      })),
      strokeIds: [...target.strokeIds],
      elementId: target.elementId,
      canMove: target.canMove,
      canShowMenu: target.canShowMenu
    };
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
      outline: this.cloneElementOutline(element.outline)
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
}
