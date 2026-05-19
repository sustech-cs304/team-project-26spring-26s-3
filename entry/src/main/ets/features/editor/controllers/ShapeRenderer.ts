import { ShapeCanvasElement, ShapeGeometryPoint } from '../../../domain/entities/CanvasElement';
import { CanvasDrawContext } from './CanvasDrawContext';

interface CanvasResolvedColor {
  fillStyle: string;
  alpha: number;
}

export class ShapeRenderer {
  static drawShape(
    context: CanvasDrawContext,
    element: ShapeCanvasElement,
    originX: number = 0,
    originY: number = 0,
    opacityMultiplier: number = 1
  ): void {
    const opacity = Math.max(0, Math.min(1, element.opacity * opacityMultiplier));
    context.save();

    if (element.geometry.kind === 'line') {
      ShapeRenderer.drawLineShape(context, element, originX, originY, opacity);
    } else if (element.geometry.kind === 'ellipse') {
      ShapeRenderer.drawEllipseShape(context, element, originX, originY, opacity);
    } else {
      ShapeRenderer.drawRectShape(context, element, originX, originY, opacity);
    }

    context.restore();
  }

  private static drawRectShape(
    context: CanvasDrawContext,
    element: ShapeCanvasElement,
    originX: number,
    originY: number,
    opacity: number
  ): void {
    const x = element.x - originX;
    const y = element.y - originY;
    const width = element.width;
    const height = element.height;
    const strokeWidth = Math.max(1, element.strokeWidth);

    ShapeRenderer.fillRect(context, element, x, y, width, height, opacity);
    context.globalAlpha = opacity;
    context.strokeStyle = ShapeRenderer.resolveCanvasColor(element.strokeColor, '#111827').fillStyle;
    context.lineWidth = strokeWidth;
    context.strokeRect(x + strokeWidth / 2, y + strokeWidth / 2, Math.max(0, width - strokeWidth), Math.max(0, height - strokeWidth));
  }

  private static drawEllipseShape(
    context: CanvasDrawContext,
    element: ShapeCanvasElement,
    originX: number,
    originY: number,
    opacity: number
  ): void {
    const strokeWidth = Math.max(1, element.strokeWidth);
    const radiusX = Math.max(1, (element.width - strokeWidth) / 2);
    const radiusY = Math.max(1, (element.height - strokeWidth) / 2);
    const centerX = element.x - originX + element.width / 2;
    const centerY = element.y - originY + element.height / 2;

    context.save();
    context.translate(centerX, centerY);
    context.scale(radiusX, radiusY);
    context.beginPath();
    context.arc(0, 0, 1, 0, Math.PI * 2);
    ShapeRenderer.fillCurrentPath(context, element.fillColor, opacity);
    context.globalAlpha = opacity;
    context.strokeStyle = ShapeRenderer.resolveCanvasColor(element.strokeColor, '#111827').fillStyle;
    context.lineWidth = strokeWidth / Math.max(radiusX, radiusY);
    context.stroke();
    context.restore();
  }

  private static drawLineShape(
    context: CanvasDrawContext,
    element: ShapeCanvasElement,
    originX: number,
    originY: number,
    opacity: number
  ): void {
    const points = element.geometry.points;
    if (points.length < 2) {
      return;
    }

    const startPoint = ShapeRenderer.toLocalPoint(points[0], originX, originY);
    const endPoint = ShapeRenderer.toLocalPoint(points[1], originX, originY);
    context.globalAlpha = opacity;
    context.strokeStyle = ShapeRenderer.resolveCanvasColor(element.strokeColor, '#111827').fillStyle;
    context.lineWidth = Math.max(1, element.strokeWidth);
    context.lineCap = 'round';
    context.lineJoin = 'round';
    context.beginPath();
    context.moveTo(startPoint.x, startPoint.y);
    context.lineTo(endPoint.x, endPoint.y);
    context.stroke();
  }

  private static fillRect(
    context: CanvasDrawContext,
    element: ShapeCanvasElement,
    x: number,
    y: number,
    width: number,
    height: number,
    opacity: number
  ): void {
    const fillColor = ShapeRenderer.resolveCanvasColor(element.fillColor, '#FFFFFF');
    if (fillColor.alpha <= 0) {
      return;
    }

    context.save();
    context.globalAlpha = opacity * fillColor.alpha;
    context.fillStyle = fillColor.fillStyle;
    context.fillRect(x, y, width, height);
    context.restore();
  }

  private static fillCurrentPath(context: CanvasDrawContext, fillColorValue: string, opacity: number): void {
    const fillColor = ShapeRenderer.resolveCanvasColor(fillColorValue, '#FFFFFF');
    if (fillColor.alpha <= 0) {
      return;
    }

    context.save();
    context.globalAlpha = opacity * fillColor.alpha;
    context.fillStyle = fillColor.fillStyle;
    context.fill();
    context.restore();
  }

  private static toLocalPoint(point: ShapeGeometryPoint, originX: number, originY: number): ShapeGeometryPoint {
    return {
      x: point.x - originX,
      y: point.y - originY
    };
  }

  private static resolveCanvasColor(color: string, fallbackFillStyle: string): CanvasResolvedColor {
    const normalizedColor = color.trim().toUpperCase();
    if (normalizedColor.length === 0 || normalizedColor === 'TRANSPARENT') {
      return {
        fillStyle: fallbackFillStyle,
        alpha: 0
      };
    }

    if (/^#[0-9A-F]{8}$/.test(normalizedColor)) {
      return {
        fillStyle: `#${normalizedColor.substring(3)}`,
        alpha: Number.parseInt(normalizedColor.substring(1, 3), 16) / 255
      };
    }

    return {
      fillStyle: color.length === 0 ? fallbackFillStyle : color,
      alpha: 1
    };
  }
}
