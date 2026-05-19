import { StrokePoint } from '../../../domain/entities/Stroke';
import { CanvasDrawContext } from './CanvasDrawContext';

export const SELECTION_DASH_COLOR = '#64748B';
export const SELECTION_DASH_WIDTH = 3.5;
export const SELECTION_DASH_LENGTH = 13;
export const SELECTION_DASH_GAP = 14;
const MAX_SELECTION_DASH_SEGMENTS = 2000;

interface DashDrawState {
  pathDistance: number;
  dashCount: number;
}

export class SelectionDashRenderer {
  static drawPath(
    context: CanvasDrawContext,
    points: StrokePoint[],
    closed: boolean,
    dashOffset: number = 0
  ): void {
    if (points.length < 2) {
      return;
    }

    const segmentCount = closed ? points.length : points.length - 1;
    const patternLength = SELECTION_DASH_LENGTH + SELECTION_DASH_GAP;
    let pathDistance = -SelectionDashRenderer.normalizeOffset(dashOffset, patternLength);
    let dashCount = 0;

    context.save();
    context.strokeStyle = SELECTION_DASH_COLOR;
    context.lineWidth = SELECTION_DASH_WIDTH;
    context.lineCap = 'round';
    context.lineJoin = 'round';
    context.globalAlpha = 0.92;

    for (let index = 0; index < segmentCount; index += 1) {
      const start = points[index];
      const end = points[(index + 1) % points.length];
      const state = SelectionDashRenderer.drawSegment(context, start, end, pathDistance, patternLength, dashCount);
      pathDistance = state.pathDistance;
      dashCount = state.dashCount;
      if (dashCount >= MAX_SELECTION_DASH_SEGMENTS) {
        break;
      }
    }

    context.globalAlpha = 1;
    context.restore();
  }

  private static drawSegment(
    context: CanvasDrawContext,
    start: StrokePoint,
    end: StrokePoint,
    pathDistance: number,
    patternLength: number,
    dashCount: number
  ): DashDrawState {
    const deltaX = end.x - start.x;
    const deltaY = end.y - start.y;
    const length = Math.sqrt(deltaX * deltaX + deltaY * deltaY);
    if (length <= 0.001) {
      return { pathDistance, dashCount };
    }

    const unitX = deltaX / length;
    const unitY = deltaY / length;
    let segmentDistance = 0;

    while (segmentDistance < length && dashCount < MAX_SELECTION_DASH_SEGMENTS) {
      const patternPosition = SelectionDashRenderer.normalizeOffset(pathDistance, patternLength);
      const remainingPattern = patternLength - patternPosition;
      const advance = Math.min(length - segmentDistance, remainingPattern);
      if (patternPosition < SELECTION_DASH_LENGTH) {
        const dashRemaining = SELECTION_DASH_LENGTH - patternPosition;
        const dashLength = Math.min(advance, dashRemaining);
        if (dashLength > 0) {
          const dashStart = segmentDistance;
          const dashEnd = segmentDistance + dashLength;
          context.beginPath();
          context.moveTo(start.x + unitX * dashStart, start.y + unitY * dashStart);
          context.lineTo(start.x + unitX * dashEnd, start.y + unitY * dashEnd);
          context.stroke();
          dashCount += 1;
        }
      }

      segmentDistance += advance;
      pathDistance += advance;
    }

    return { pathDistance, dashCount };
  }

  private static normalizeOffset(value: number, patternLength: number): number {
    const offset = value % patternLength;
    return offset < 0 ? offset + patternLength : offset;
  }
}
