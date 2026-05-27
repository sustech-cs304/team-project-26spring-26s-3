import { describe, expect, it } from 'vitest';
import {
  clampBoundingBox,
  doBoundingBoxesIntersect,
  ensureRenderablePoints,
  eraseStrokePointsWithPath,
  expandBoundingBox,
  getBoundingBox,
  getDistance,
  getPointToSegmentDistance,
  getStrokeRenderBoundingBox,
  isPointWithinPathRadius,
  isSamePoint,
  mergeBoundingBoxes,
  normalizePoints,
  sampleStrokePoints
} from '../entry/src/main/ets/common/utils/GeometryUtil';
import type { Stroke, StrokePoint } from '../entry/src/main/ets/domain/entities/Stroke';

function point(x: number, y: number, t: number = 0, pressure?: number): StrokePoint {
  return pressure === undefined ? { x, y, t } : { x, y, t, pressure };
}

function stroke(points: StrokePoint[], width: number = 4, overrides: Partial<Stroke> = {}): Stroke {
  return {
    id: 'stroke-1',
    pageId: 'page-1',
    points,
    style: {
      tool: 'pen',
      color: '#000000',
      width,
      opacity: 1
    },
    createdAt: 1,
    updatedAt: 1,
    ...overrides
  };
}

function expectBoxCloseTo(actual: ReturnType<typeof getStrokeRenderBoundingBox>, expected: {
  minX: number;
  minY: number;
  maxX: number;
  maxY: number;
}): void {
  expect(actual).not.toBeNull();
  expect(actual!.minX).toBeCloseTo(expected.minX);
  expect(actual!.minY).toBeCloseTo(expected.minY);
  expect(actual!.maxX).toBeCloseTo(expected.maxX);
  expect(actual!.maxY).toBeCloseTo(expected.maxY);
}

describe('GeometryUtil', () => {
  it('computes point and segment distances', () => {
    expect(getDistance(point(0, 0), point(3, 4))).toBe(5);
    expect(getPointToSegmentDistance(point(5, 5), point(0, 0), point(10, 0))).toBe(5);
    expect(getPointToSegmentDistance(point(3, 4), point(0, 0), point(0, 0))).toBe(5);
  });

  it('normalizes adjacent duplicate points', () => {
    const normalized = normalizePoints([
      point(0, 0),
      point(0.1, 0.1),
      point(4, 4),
      point(4.2, 4.2)
    ]);

    expect(normalized).toEqual([point(0, 0), point(4, 4)]);
    expect(isSamePoint(point(0, 0), point(0.4, 0))).toBe(true);
    expect(isSamePoint(point(0, 0), point(0.6, 0))).toBe(false);
  });

  it('expands single-point strokes for rendering', () => {
    const renderable = ensureRenderablePoints([point(10, 20, 1, 0.7)]);

    expect(renderable).toHaveLength(2);
    expect(renderable[0].x).toBe(10);
    expect(renderable[1].x).toBeCloseTo(10.1);
    expect(renderable[1].pressure).toBe(0.7);
  });

  it('creates, expands, merges and clamps bounding boxes', () => {
    const box = getBoundingBox([point(5, 2), point(-1, 7), point(3, 4)]);

    expect(box).toEqual({ minX: -1, minY: 2, maxX: 5, maxY: 7 });
    expect(expandBoundingBox(box!, 2)).toEqual({ minX: -3, minY: 0, maxX: 7, maxY: 9 });
    expect(mergeBoundingBoxes(box, { minX: -4, minY: 3, maxX: 2, maxY: 10 })).toEqual({
      minX: -4,
      minY: 2,
      maxX: 5,
      maxY: 10
    });
    expect(clampBoundingBox({ minX: -3, minY: 1, maxX: 6, maxY: 9 }, 5, 5)).toEqual({
      minX: 0,
      minY: 1,
      maxX: 5,
      maxY: 5
    });
    expect(clampBoundingBox({ minX: -3, minY: -3, maxX: -1, maxY: -1 }, 5, 5)).toBeNull();
  });

  it('includes width-based padding in stroke render bounds', () => {
    expect(getStrokeRenderBoundingBox(stroke([point(10, 20), point(30, 40)], 8))).toEqual({
      minX: -10,
      minY: 0,
      maxX: 50,
      maxY: 60
    });
    expect(getStrokeRenderBoundingBox(stroke([], 8))).toBeNull();
  });

  it('uses tool-specific render bounds and includes warmup points', () => {
    expectBoxCloseTo(getStrokeRenderBoundingBox(stroke([point(10, 20), point(30, 40)], 8, {
      style: {
        tool: 'highlighter',
        color: '#ffff00',
        width: 8,
        opacity: 0.4
      }
    })), {
      minX: -12.4,
      minY: -2.400000000000002,
      maxX: 52.4,
      maxY: 62.4
    });

    expect(getStrokeRenderBoundingBox(stroke([point(10, 20), point(30, 40)], 4, {
      renderWarmupPoints: [point(-6, 14)]
    }))).toEqual({
      minX: -18,
      minY: 2,
      maxX: 42,
      maxY: 52
    });
  });

  it('detects intersecting boxes and nearby path points', () => {
    expect(
      doBoundingBoxesIntersect(
        { minX: 0, minY: 0, maxX: 10, maxY: 10 },
        { minX: 10, minY: 10, maxX: 20, maxY: 20 }
      )
    ).toBe(true);
    expect(
      doBoundingBoxesIntersect(
        { minX: 0, minY: 0, maxX: 10, maxY: 10 },
        { minX: 11, minY: 11, maxX: 20, maxY: 20 }
      )
    ).toBe(false);
    expect(isPointWithinPathRadius(point(5, 1), [point(0, 0), point(10, 0)], 1.1)).toBe(true);
    expect(isPointWithinPathRadius(point(5, 2), [point(0, 0), point(10, 0)], 1.1)).toBe(false);
  });

  it('interpolates long stroke segments while sampling', () => {
    const sampled = sampleStrokePoints([point(0, 0, 0, 0.2), point(6, 0, 6, 0.8)], 2);

    expect(sampled).toHaveLength(4);
    expect(sampled.map((item) => item.x)).toEqual([0, 2, 4, 6]);
    expect(sampled[2].pressure).toBeCloseTo(0.6);
  });

  it('splits erased stroke points into remaining visible segments', () => {
    const segments = eraseStrokePointsWithPath(
      [point(0, 0), point(4, 0), point(8, 0)],
      [point(4, 0)],
      0.5,
      2
    );

    expect(segments).toHaveLength(2);
    expect(segments[0].points[0].x).toBe(0);
    expect(segments[1].points.at(-1)?.x).toBe(8);
    expect(segments.every((segment) => Array.isArray(segment.renderWarmupPoints))).toBe(true);
  });
});
