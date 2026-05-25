import { describe, expect, it, vi } from 'vitest';
import type {
  ImageCanvasElement,
  ShapeCanvasElement,
  TextCanvasElement
} from '../entry/src/main/ets/domain/entities/CanvasElement';
import type { Stroke, StrokePoint, StrokeStyle } from '../entry/src/main/ets/domain/entities/Stroke';
import { StrokeController } from '../entry/src/main/ets/features/editor/controllers/StrokeController';
import { UndoRedoController } from '../entry/src/main/ets/features/editor/controllers/UndoRedoController';
import type { SelectionTarget } from '../entry/src/main/ets/features/editor/selection/SelectionTypes';

function point(x: number, y: number, t: number = 0, pressure?: number): StrokePoint {
  return pressure === undefined ? { x, y, t } : { x, y, t, pressure };
}

function style(overrides: Partial<StrokeStyle> = {}): StrokeStyle {
  return {
    tool: 'pen',
    color: '#101010',
    width: 6,
    opacity: 0.9,
    ...overrides
  };
}

function stroke(id: string, points: StrokePoint[] = [point(0, 0), point(4, 4)]): Stroke {
  return {
    id,
    pageId: 'page-1',
    renderKey: `${id}-render`,
    renderWarmupPoints: [point(-1, -1)],
    points,
    style: style(),
    createdAt: 10,
    updatedAt: 20
  };
}

function textElement(id: string, content: string = 'note'): TextCanvasElement {
  return {
    id,
    pageId: 'page-1',
    type: 'text',
    x: 10,
    y: 20,
    width: 120,
    height: 40,
    rotation: 0,
    zIndex: 1,
    createdAt: 1,
    updatedAt: 2,
    content,
    color: '#000000',
    fontSize: 18,
    backgroundColor: '#00FFFFFF'
  };
}

function shapeElement(id: string): ShapeCanvasElement {
  return {
    id,
    pageId: 'page-1',
    type: 'shape',
    x: 30,
    y: 40,
    width: 80,
    height: 60,
    rotation: 0,
    zIndex: 2,
    createdAt: 3,
    updatedAt: 4,
    shapeType: 'rectangle',
    geometry: {
      kind: 'rect',
      points: [
        { x: 0, y: 0 },
        { x: 80, y: 60 }
      ]
    },
    strokeColor: '#222222',
    fillColor: '#ffffff',
    strokeWidth: 2,
    opacity: 0.8
  };
}

function imageElement(id: string): ImageCanvasElement {
  return {
    id,
    pageId: 'page-1',
    type: 'image',
    x: 5,
    y: 6,
    width: 200,
    height: 100,
    rotation: 0,
    zIndex: 3,
    createdAt: 5,
    updatedAt: 6,
    uri: `file://${id}.png`,
    originalWidth: 400,
    originalHeight: 200,
    opacity: 0.7
  };
}

function selectionTarget(id: string, strokeIds: string[], elementId: string): SelectionTarget {
  return {
    id,
    kind: elementId.length > 0 ? 'textElement' : 'strokeGroup',
    bounds: { minX: 0, minY: 0, maxX: 10, maxY: 10 },
    outline: [point(0, 0), point(10, 10)],
    strokeIds,
    elementId,
    canMove: true,
    canShowMenu: true
  };
}

describe('StrokeController', () => {
  it('rejects empty page ids and tracks active stroke lifecycle', () => {
    vi.spyOn(Date, 'now').mockReturnValue(100);
    vi.spyOn(Math, 'random').mockReturnValue(0.25);

    const controller = new StrokeController();

    expect(controller.beginStroke('   ', point(0, 0), style())).toBeNull();
    expect(controller.appendPoint(point(1, 1))).toBeNull();
    expect(controller.hasActiveStroke()).toBe(false);

    const activeStroke = controller.beginStroke('page-1', point(0, 0, 1, 0.4), style({ width: 4 }));

    expect(activeStroke).not.toBeNull();
    expect(activeStroke?.id).toMatch(/^stroke_/);
    expect(controller.getActiveStrokeForRendering()).toBe(activeStroke);
    expect(controller.hasActiveStroke()).toBe(true);
    expect(controller.appendPoint(point(0.1, 0.1, 2, 0.5))?.points).toHaveLength(1);
    expect(controller.appendPoint(point(6, 0, 3, 0.6))?.points).toHaveLength(2);

    const renderable = controller.getActiveStroke();

    expect(renderable?.points.map((item) => item.x)).toEqual([0, 6]);
    expect(renderable?.style.width).toBe(4);

    const finished = controller.finishStroke();

    expect(finished?.pageId).toBe('page-1');
    expect(finished?.points).toHaveLength(2);
    expect(controller.hasActiveStroke()).toBe(false);
    expect(controller.finishStroke()).toBeNull();

    vi.restoreAllMocks();
  });

  it('cancels active strokes without returning completed content', () => {
    vi.spyOn(Date, 'now').mockReturnValue(200);
    vi.spyOn(Math, 'random').mockReturnValue(0.5);

    const controller = new StrokeController();

    controller.beginStroke('page-1', point(3, 3), style());
    expect(controller.hasActiveStroke()).toBe(true);

    controller.cancelStroke();

    expect(controller.hasActiveStroke()).toBe(false);
    expect(controller.getActiveStroke()).toBeNull();
    expect(controller.finishStroke()).toBeNull();

    vi.restoreAllMocks();
  });
});

describe('UndoRedoController', () => {
  it('undoes and redoes appended strokes while preserving clones', () => {
    const controller = new UndoRedoController();
    const originalStroke = stroke('stroke-a');

    controller.recordAppendStroke(originalStroke);
    originalStroke.points[0].x = 999;

    const afterUndo = controller.undo([stroke('stroke-a'), stroke('stroke-b')]);

    expect(afterUndo.strokes.map((item) => item.id)).toEqual(['stroke-b']);
    expect(afterUndo.removed).toHaveLength(1);
    expect(afterUndo.removed[0].stroke.points[0].x).toBe(0);
    expect(controller.canRedo()).toBe(true);

    const afterRedo = controller.redo(afterUndo.strokes);

    expect(afterRedo.strokes.map((item) => item.id)).toEqual(['stroke-b', 'stroke-a']);
    expect(afterRedo.added[0].index).toBe(1);
    expect(afterRedo.added[0].stroke.points[0].x).toBe(0);
    expect(controller.canRedo()).toBe(false);
  });

  it('applies replace-page deltas for strokes, elements and selection snapshots', () => {
    const controller = new UndoRedoController();
    const removedStroke = stroke('stroke-old');
    const addedStroke = stroke('stroke-new', [point(10, 10), point(20, 20)]);
    const removedElement = textElement('element-old', 'old');
    const addedElement = textElement('element-new', 'new');

    controller.recordDelta(
      [{ index: 0, stroke: removedStroke }],
      [{ index: 1, stroke: addedStroke }],
      'elementEdit',
      [{ index: 0, element: removedElement }],
      [{ index: 1, element: addedElement }],
      {
        strokeIds: ['stroke-old'],
        strokeTargets: [selectionTarget('selection-old', ['stroke-old'], '')],
        elementIds: ['element-old']
      },
      {
        strokeIds: ['stroke-new'],
        strokeTargets: [selectionTarget('selection-new', ['stroke-new'], 'element-new')],
        elementIds: ['element-new']
      }
    );

    const afterUndo = controller.undo([stroke('stroke-keep'), addedStroke], [textElement('element-keep'), addedElement]);

    expect(afterUndo.strokes.map((item) => item.id)).toEqual(['stroke-old', 'stroke-keep']);
    expect(afterUndo.elements.map((item) => item.id)).toEqual(['element-old', 'element-keep']);
    expect(afterUndo.selection?.strokeIds).toEqual(['stroke-old']);
    expect(afterUndo.selection?.strokeTargets[0].outline[1].x).toBe(10);
    expect(afterUndo.selection?.elementIds).toEqual(['element-old']);

    const afterRedo = controller.redo(afterUndo.strokes, afterUndo.elements);

    expect(afterRedo.strokes.map((item) => item.id)).toEqual(['stroke-keep', 'stroke-new']);
    expect(afterRedo.elements.map((item) => item.id)).toEqual(['element-keep', 'element-new']);
    expect(afterRedo.selection?.strokeIds).toEqual(['stroke-new']);
    expect(afterRedo.selection?.strokeTargets[0].elementId).toBe('element-new');
    expect(afterRedo.selection?.elementIds).toEqual(['element-new']);
  });

  it('clones shape and image elements through undo and redo deltas', () => {
    const controller = new UndoRedoController();
    const removedShape = shapeElement('shape-old');
    const addedImage = imageElement('image-new');

    controller.recordDelta(
      [],
      [],
      'elementEdit',
      [{ index: 0, element: removedShape }],
      [{ index: 1, element: addedImage }]
    );

    removedShape.geometry.points[0].x = 999;
    addedImage.uri = 'mutated';

    const afterUndo = controller.undo([stroke('stroke-keep')], [textElement('element-keep'), imageElement('image-new')]);

    expect(afterUndo.elements.map((item) => item.id)).toEqual(['shape-old', 'element-keep']);
    expect(afterUndo.elements[0].type).toBe('shape');
    expect((afterUndo.elements[0] as ShapeCanvasElement).geometry.points[0].x).toBe(0);

    const afterRedo = controller.redo(afterUndo.strokes, afterUndo.elements);

    expect(afterRedo.elements.map((item) => item.id)).toEqual(['element-keep', 'image-new']);
    expect(afterRedo.elements[1].type).toBe('image');
    expect((afterRedo.elements[1] as ImageCanvasElement).uri).toBe('file://image-new.png');
  });

  it('ignores empty deltas and enforces history limit', () => {
    const controller = new UndoRedoController(2);

    controller.recordDelta([], [], 'clear');
    expect(controller.canUndo()).toBe(false);

    controller.recordAppendStroke(stroke('stroke-1'));
    controller.recordAppendStroke(stroke('stroke-2'));
    controller.recordAppendStroke(stroke('stroke-3'));

    expect(controller.getDebugState()).toEqual({ undoDepth: 2, redoDepth: 0 });

    const firstUndo = controller.undo([stroke('stroke-1'), stroke('stroke-2'), stroke('stroke-3')]);
    const secondUndo = controller.undo(firstUndo.strokes);
    const thirdUndo = controller.undo(secondUndo.strokes);

    expect(firstUndo.strokes.map((item) => item.id)).toEqual(['stroke-1', 'stroke-2']);
    expect(secondUndo.strokes.map((item) => item.id)).toEqual(['stroke-1']);
    expect(thirdUndo.strokes.map((item) => item.id)).toEqual(['stroke-1']);
  });

  it('restores snapshots independently from later mutations', () => {
    const controller = new UndoRedoController();
    const appendedStroke = stroke('stroke-a');

    controller.recordAppendStroke(appendedStroke);
    const snapshot = controller.createSnapshot();
    snapshot.undoStack[0].type === 'append_stroke' && (snapshot.undoStack[0].stroke.points[0].x = 500);

    const restoredController = new UndoRedoController();
    restoredController.restoreSnapshot(controller.createSnapshot());

    const result = restoredController.undo([stroke('stroke-a')]);

    expect(result.removed[0].stroke.points[0].x).toBe(0);
  });
});
