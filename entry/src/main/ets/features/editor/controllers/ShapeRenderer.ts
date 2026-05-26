import { ElementOutlineStyle, ShapeCanvasElement, ShapeGeometryPoint } from '../../../domain/entities/CanvasElement';
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
    const strokeWidth = ShapeRenderer.getVisibleOutlineWidth(element.outline);

    ShapeRenderer.fillRect(context, element, x, y, width, height, opacity);
    if (strokeWidth <= 0) {
      return;
    }

    context.globalAlpha = opacity;
    ShapeRenderer.configureOutline(context, element.outline, strokeWidth);
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
    const strokeWidth = ShapeRenderer.getVisibleOutlineWidth(element.outline);
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
    if (strokeWidth <= 0) {
      context.restore();
      return;
    }

    context.globalAlpha = opacity;
    ShapeRenderer.configureOutline(context, element.outline, strokeWidth / Math.max(radiusX, radiusY));
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
    const strokeWidth = ShapeRenderer.getVisibleOutlineWidth(element.outline);
    if (strokeWidth <= 0) {
      return;
    }

    context.globalAlpha = opacity;
    ShapeRenderer.configureOutline(context, element.outline, strokeWidth);
    context.lineWidth = strokeWidth;
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

  private static getVisibleOutlineWidth(outline: ElementOutlineStyle): number {
    if (outline.lineStyle === 'none' || outline.width <= 0) {
      return 0;
    }

    return Math.max(1, outline.width);
  }

  private static configureOutline(
    context: CanvasDrawContext,
    outline: ElementOutlineStyle,
    effectiveWidth: number
  ): void {
    context.strokeStyle = ShapeRenderer.resolveCanvasColor(outline.color, '#111827').fillStyle;
    if (context.setLineDash === undefined) {
      return;
    }

    if (outline.lineStyle === 'dashed') {
      context.setLineDash([Math.max(4, effectiveWidth * 3), Math.max(3, effectiveWidth * 2)]);
    } else if (outline.lineStyle === 'dotted') {
      context.setLineDash([Math.max(1, effectiveWidth), Math.max(3, effectiveWidth * 2)]);
    } else {
      context.setLineDash([]);
    }
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
