import { Stroke, StrokePoint } from '../../domain/entities/Stroke';

const DEFAULT_POINT_MERGE_THRESHOLD = 0.5;
const SINGLE_POINT_OFFSET = 0.1;
const DEFAULT_STROKE_SAMPLING_STEP = 2;
const DEFAULT_RENDER_BOUNDS_PADDING = 12;
const RENDER_BOUNDS_WIDTH_FACTOR = 2.5;
const ERASE_SEGMENT_WARMUP_POINT_WINDOW = 8;

export interface BoundingBox {
  minX: number;
  minY: number;
  maxX: number;
  maxY: number;
}

export interface ErasedStrokeSegment {
  points: StrokePoint[];
  renderWarmupPoints: StrokePoint[];
}

export function getDistance(left: StrokePoint, right: StrokePoint): number {
  const deltaX = left.x - right.x;
  const deltaY = left.y - right.y;
  return Math.sqrt(deltaX * deltaX + deltaY * deltaY);
}

export function getPointToSegmentDistance(
  point: StrokePoint,
  start: StrokePoint,
  end: StrokePoint
): number {
  const segmentDeltaX = end.x - start.x;
  const segmentDeltaY = end.y - start.y;
  const squaredLength = segmentDeltaX * segmentDeltaX + segmentDeltaY * segmentDeltaY;

  if (squaredLength === 0) {
    return getDistance(point, start);
  }

  const ratio = ((point.x - start.x) * segmentDeltaX + (point.y - start.y) * segmentDeltaY) / squaredLength;
  const clampedRatio = Math.max(0, Math.min(1, ratio));
  const projectedPoint: StrokePoint = {
    x: start.x + segmentDeltaX * clampedRatio,
    y: start.y + segmentDeltaY * clampedRatio,
    t: start.t + (end.t - start.t) * clampedRatio
  };

  return getDistance(point, projectedPoint);
}

export function isSamePoint(
  left: StrokePoint,
  right: StrokePoint,
  threshold: number = DEFAULT_POINT_MERGE_THRESHOLD
): boolean {
  return getDistance(left, right) < threshold;
}

export function normalizePoints(
  points: StrokePoint[],
  threshold: number = DEFAULT_POINT_MERGE_THRESHOLD
): StrokePoint[] {
  if (points.length <= 1) {
    return [...points];
  }

  const normalized: StrokePoint[] = [points[0]];

  for (let index = 1; index < points.length; index += 1) {
    if (!isSamePoint(points[index - 1], points[index], threshold)) {
      normalized.push(points[index]);
    }
  }

  return normalized;
}

export function ensureRenderablePoints(points: StrokePoint[]): StrokePoint[] {
  if (points.length !== 1) {
    return points.map((point: StrokePoint) => clonePoint(point));
  }

  const point = points[0];
  return [
    clonePoint(point),
    {
      x: point.x + SINGLE_POINT_OFFSET,
      y: point.y + SINGLE_POINT_OFFSET,
      t: point.t,
      pressure: point.pressure
    }
  ];
}

export function getBoundingBox(points: StrokePoint[]): BoundingBox | null {
  if (points.length === 0) {
    return null;
  }

  let minX = points[0].x;
  let minY = points[0].y;
  let maxX = points[0].x;
  let maxY = points[0].y;

  for (let index = 1; index < points.length; index += 1) {
    const point = points[index];
    minX = Math.min(minX, point.x);
    minY = Math.min(minY, point.y);
    maxX = Math.max(maxX, point.x);
    maxY = Math.max(maxY, point.y);
  }

  return {
    minX,
    minY,
    maxX,
    maxY
  };
}

export function expandBoundingBox(box: BoundingBox, padding: number): BoundingBox {
  return {
    minX: box.minX - padding,
    minY: box.minY - padding,
    maxX: box.maxX + padding,
    maxY: box.maxY + padding
  };
}

export function mergeBoundingBoxes(left: BoundingBox | null, right: BoundingBox | null): BoundingBox | null {
  if (left === null) {
    return right === null ? null : { ...right };
  }

  if (right === null) {
    return { ...left };
  }

  return {
    minX: Math.min(left.minX, right.minX),
    minY: Math.min(left.minY, right.minY),
    maxX: Math.max(left.maxX, right.maxX),
    maxY: Math.max(left.maxY, right.maxY)
  };
}

export function clampBoundingBox(box: BoundingBox, width: number, height: number): BoundingBox | null {
  const maxWidth = Math.max(0, width);
  const maxHeight = Math.max(0, height);
  const minX = Math.max(0, Math.min(box.minX, maxWidth));
  const minY = Math.max(0, Math.min(box.minY, maxHeight));
  const maxX = Math.max(0, Math.min(box.maxX, maxWidth));
  const maxY = Math.max(0, Math.min(box.maxY, maxHeight));

  if (maxX <= minX || maxY <= minY) {
    return null;
  }

  return {
    minX,
    minY,
    maxX,
    maxY
  };
}

export function getStrokeRenderBoundingBox(stroke: Stroke): BoundingBox | null {
  const box = getBoundingBox(stroke.points);
  if (box === null) {
    return null;
  }

  const padding = Math.max(DEFAULT_RENDER_BOUNDS_PADDING, stroke.style.width * RENDER_BOUNDS_WIDTH_FACTOR);
  return expandBoundingBox(box, padding);
}

export function doBoundingBoxesIntersect(left: BoundingBox, right: BoundingBox): boolean {
  return !(
    left.maxX < right.minX ||
    left.minX > right.maxX ||
    left.maxY < right.minY ||
    left.minY > right.maxY
  );
}

export function sampleStrokePoints(
  points: StrokePoint[],
  step: number = DEFAULT_STROKE_SAMPLING_STEP
): StrokePoint[] {
  if (points.length <= 1) {
    return points.map((point: StrokePoint) => clonePoint(point));
  }

  const sampledPoints: StrokePoint[] = [clonePoint(points[0])];
  const safeStep = Math.max(0.5, step);

  for (let index = 1; index < points.length; index += 1) {
    const start = points[index - 1];
    const end = points[index];
    const segmentLength = getDistance(start, end);

    if (segmentLength === 0) {
      continue;
    }

    const divisions = Math.max(1, Math.ceil(segmentLength / safeStep));
    for (let segmentIndex = 1; segmentIndex <= divisions; segmentIndex += 1) {
      sampledPoints.push(interpolatePoint(start, end, segmentIndex / divisions));
    }
  }

  return normalizePoints(sampledPoints, 0.05);
}

export function isPointWithinPathRadius(
  point: StrokePoint,
  path: StrokePoint[],
  radius: number
): boolean {
  if (path.length === 0) {
    return false;
  }

  if (path.length === 1) {
    return getDistance(point, path[0]) <= radius;
  }

  for (let index = 1; index < path.length; index += 1) {
    if (getPointToSegmentDistance(point, path[index - 1], path[index]) <= radius) {
      return true;
    }
  }

  return false;
}

export function eraseStrokePointsWithPath(
  points: StrokePoint[],
  eraserPath: StrokePoint[],
  radius: number,
  samplingStep: number = DEFAULT_STROKE_SAMPLING_STEP
): ErasedStrokeSegment[] {
  if (points.length === 0) {
    return [];
  }

  if (eraserPath.length === 0) {
    return [{
      points: points.map((point: StrokePoint) => clonePoint(point)),
      renderWarmupPoints: []
    }];
  }

  const sampledPoints = sampleStrokePoints(points, samplingStep);
  const remainingSegments: ErasedStrokeSegment[] = [];
  let currentSegment: StrokePoint[] = [];
  let currentSegmentStartIndex = -1;
  let hasErasedPoint = false;

  for (let pointIndex = 0; pointIndex < sampledPoints.length; pointIndex += 1) {
    const point = sampledPoints[pointIndex];
    if (isPointWithinPathRadius(point, eraserPath, radius)) {
      hasErasedPoint = true;
      if (currentSegment.length > 0) {
        remainingSegments.push(buildErasedStrokeSegment(sampledPoints, currentSegment, currentSegmentStartIndex));
        currentSegment = [];
        currentSegmentStartIndex = -1;
      }
      continue;
    }

    if (currentSegment.length === 0) {
      currentSegmentStartIndex = pointIndex;
    }
    currentSegment.push(clonePoint(point));
  }

  if (currentSegment.length > 0) {
    remainingSegments.push(buildErasedStrokeSegment(sampledPoints, currentSegment, currentSegmentStartIndex));
  }

  if (!hasErasedPoint) {
    return [{
      points: points.map((point: StrokePoint) => clonePoint(point)),
      renderWarmupPoints: []
    }];
  }

  return remainingSegments.filter((segment: ErasedStrokeSegment) => segment.points.length > 0);
}

function buildErasedStrokeSegment(
  sampledPoints: StrokePoint[],
  segmentPoints: StrokePoint[],
  startIndex: number
): ErasedStrokeSegment {
  const normalizedSegmentPoints = normalizePoints(segmentPoints, 0.05);
  const visiblePoints = normalizedSegmentPoints.length === 1
    ? ensureRenderablePoints(normalizedSegmentPoints)
    : normalizedSegmentPoints;
  const warmupStartIndex = Math.max(0, startIndex - ERASE_SEGMENT_WARMUP_POINT_WINDOW);
  const renderWarmupPoints = sampledPoints
    .slice(warmupStartIndex, Math.max(warmupStartIndex, startIndex))
    .map((point: StrokePoint) => clonePoint(point));

  return {
    points: visiblePoints.map((point: StrokePoint) => clonePoint(point)),
    renderWarmupPoints
  };
}

function interpolatePoint(start: StrokePoint, end: StrokePoint, ratio: number): StrokePoint {
  return {
    x: start.x + (end.x - start.x) * ratio,
    y: start.y + (end.y - start.y) * ratio,
    t: start.t + (end.t - start.t) * ratio,
    pressure: interpolatePressure(start.pressure, end.pressure, ratio)
  };
}

function interpolatePressure(start: number | undefined, end: number | undefined, ratio: number): number | undefined {
  if (start === undefined && end === undefined) {
    return undefined;
  }

  const safeStart = start ?? end ?? 0;
  const safeEnd = end ?? start ?? 0;
  return safeStart + (safeEnd - safeStart) * ratio;
}

function clonePoint(point: StrokePoint): StrokePoint {
  return {
    x: point.x,
    y: point.y,
    t: point.t,
    pressure: point.pressure
  };
}
