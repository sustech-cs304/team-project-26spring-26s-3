import { createId } from '../../../common/utils/IdUtil';
import { ensureRenderablePoints, isSamePoint, normalizePoints } from '../../../common/utils/GeometryUtil';
import { now } from '../../../common/utils/TimeUtil';
import { Stroke, StrokePoint, StrokeStyle } from '../../../domain/entities/Stroke';

export class StrokeController {
  private activeStroke: Stroke | null = null;

  beginStroke(pageId: string, point: StrokePoint, style: StrokeStyle): Stroke | null {
    if (pageId.trim().length === 0) {
      return null;
    }

    const timestamp = now();
    this.activeStroke = {
      id: createId('stroke'),
      pageId,
      points: [this.clonePoint(point)],
      style: this.cloneStyle(style),
      createdAt: timestamp,
      updatedAt: timestamp
    };

    return this.activeStroke;
  }

  appendPoint(point: StrokePoint): Stroke | null {
    if (!this.activeStroke) {
      return null;
    }

    const lastPoint = this.activeStroke.points[this.activeStroke.points.length - 1];
    if (lastPoint && isSamePoint(lastPoint, point)) {
      return this.activeStroke;
    }

    this.activeStroke.points.push(this.clonePoint(point));
    this.activeStroke.updatedAt = now();

    return this.activeStroke;
  }

  finishStroke(): Stroke | null {
    if (!this.activeStroke) {
      return null;
    }

    const normalizedPoints = normalizePoints(this.activeStroke.points);
    const renderablePoints = ensureRenderablePoints(normalizedPoints);

    if (renderablePoints.length === 0) {
      this.activeStroke = null;
      return null;
    }

    const completedStroke: Stroke = {
      id: this.activeStroke.id,
      pageId: this.activeStroke.pageId,
      points: renderablePoints.map((point: StrokePoint) => this.clonePoint(point)),
      style: this.cloneStyle(this.activeStroke.style),
      createdAt: this.activeStroke.createdAt,
      updatedAt: now()
    };

    this.activeStroke = null;
    return completedStroke;
  }

  cancelStroke(): void {
    this.activeStroke = null;
  }

  getActiveStroke(): Stroke | null {
    if (!this.activeStroke) {
      return null;
    }

    return this.cloneStroke(this.activeStroke);
  }

  hasActiveStroke(): boolean {
    return this.activeStroke !== null;
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
