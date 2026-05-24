import { describe, expect, it, vi } from 'vitest';
import { clampElementFrameToBounds } from '../entry/src/main/ets/common/utils/ElementBoundsUtil';
import { createId, IdUtil } from '../entry/src/main/ets/common/utils/IdUtil';
import { now, TimeUtil } from '../entry/src/main/ets/common/utils/TimeUtil';
import { getStrokeRenderKey, type Stroke, type StrokePoint } from '../entry/src/main/ets/domain/entities/Stroke';
import { isDrawableToolType, isToolType } from '../entry/src/main/ets/domain/entities/ToolSetting';
import { StrokeSpatialHashIndex } from '../entry/src/main/ets/features/editor/controllers/StrokeSpatialHashIndex';

function point(x: number, y: number, t: number = 0): StrokePoint {
  return { x, y, t };
}

function stroke(id: string, points: StrokePoint[]): Stroke {
  return {
    id,
    pageId: 'page-1',
    points,
    style: {
      tool: 'pen',
      color: '#000000',
      width: 4,
      opacity: 1
    },
    createdAt: 1,
    updatedAt: 1
  };
}

describe('ElementBoundsUtil', () => {
  it('clamps element frames into page bounds', () => {
    expect(clampElementFrameToBounds({ x: -10, y: 200, width: 120, height: 0 }, { width: 100, height: 80 })).toEqual({
      x: 0,
      y: 79,
      width: 100,
      height: 1
    });

    expect(clampElementFrameToBounds({ x: Number.NaN, y: Number.POSITIVE_INFINITY, width: 20, height: 20 }, { width: 50, height: 50 })).toEqual({
      x: 0,
      y: 0,
      width: 20,
      height: 20
    });
  });
});

describe('IdUtil', () => {
  it('creates prefixed ids and convenience notebook ids', () => {
    vi.spyOn(Date, 'now').mockReturnValue(123456789);
    vi.spyOn(Math, 'random').mockReturnValue(0.5);

    expect(createId('custom')).toMatch(/^custom_[a-z0-9]+_[a-z0-9]+_[a-z0-9]+$/);
    expect(IdUtil.createNotebookId()).toMatch(/^notebook_/);
    expect(IdUtil.createNotebookFolderId()).toMatch(/^folder_/);
    expect(IdUtil.createNotebookPageId()).toMatch(/^page_/);

    vi.restoreAllMocks();
  });
});

describe('TimeUtil', () => {
  it('validates timestamps and formats dates', () => {
    vi.spyOn(Date, 'now').mockReturnValue(42);

    expect(now()).toBe(42);
    expect(TimeUtil.now()).toBe(42);
    expect(TimeUtil.toIsoString(0)).toBe('1970-01-01T00:00:00.000Z');
    expect(TimeUtil.isValidTimestamp(0)).toBe(true);
    expect(TimeUtil.isValidTimestamp(Number.NaN)).toBe(false);
    expect(TimeUtil.isValidTimestamp(Number.POSITIVE_INFINITY)).toBe(false);
    expect(TimeUtil.isValidTimestamp(-1)).toBe(false);

    vi.restoreAllMocks();
  });
});

describe('Stroke entity helpers', () => {
  it('uses explicit render keys when present', () => {
    expect(getStrokeRenderKey({ ...stroke('stroke-1', [point(0, 0)]), renderKey: 'render-1' })).toBe('render-1');
    expect(getStrokeRenderKey({ ...stroke('stroke-1', [point(0, 0)]), renderKey: '' })).toBe('stroke-1');
    expect(getStrokeRenderKey(stroke('stroke-2', [point(0, 0)]))).toBe('stroke-2');
  });
});

describe('ToolSetting guards', () => {
  it('identifies supported tool names', () => {
    expect(isToolType('pen')).toBe(true);
    expect(isToolType('edit')).toBe(true);
    expect(isToolType('unknown')).toBe(false);
    expect(isDrawableToolType('pen')).toBe(true);
    expect(isDrawableToolType('eraser')).toBe(false);
  });
});

describe('StrokeSpatialHashIndex', () => {
  it('indexes, updates, queries and removes stroke bounds', () => {
    const index = new StrokeSpatialHashIndex(64);

    index.upsertStrokeBounds('stroke-a', { minX: 0, minY: 0, maxX: 20, maxY: 20 });
    index.upsertStrokeBounds('stroke-b', { minX: 80, minY: 80, maxX: 100, maxY: 100 });

    expect(index.queryStrokeIds({ minX: 0, minY: 0, maxX: 63, maxY: 63 }).sort()).toEqual(['stroke-a']);
    expect(index.getBounds('stroke-a')).toEqual({ minX: 0, minY: 0, maxX: 20, maxY: 20 });

    index.upsertStrokeBounds('stroke-a', { minX: 80, minY: 80, maxX: 90, maxY: 90 });

    expect(index.queryStrokeIds({ minX: 0, minY: 0, maxX: 63, maxY: 63 })).toEqual([]);
    expect(index.queryStrokeIds({ minX: 64, minY: 64, maxX: 128, maxY: 128 }).sort()).toEqual(['stroke-a', 'stroke-b']);

    index.removeStrokeById('stroke-b');
    expect(index.queryStrokeIds({ minX: 64, minY: 64, maxX: 128, maxY: 128 })).toEqual(['stroke-a']);

    index.clear();
    expect(index.getBounds('stroke-a')).toBeNull();
  });

  it('can index complete stroke objects and ignore empty strokes', () => {
    const index = new StrokeSpatialHashIndex(32);

    index.upsertStroke(stroke('stroke-a', [point(0, 0), point(8, 8)]));
    index.upsertStroke(stroke('stroke-empty', []));

    expect(index.queryStrokeIds({ minX: -16, minY: -16, maxX: 24, maxY: 24 })).toEqual(['stroke-a']);
    expect(index.getBounds('stroke-empty')).toBeNull();
  });
});
