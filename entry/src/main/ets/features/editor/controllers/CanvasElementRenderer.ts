import { CanvasElement, ShapeCanvasElement, TextCanvasElement } from '../../../domain/entities/CanvasElement';

interface CanvasResolvedColor {
  fillStyle: string;
  alpha: number;
}

export class CanvasElementRenderer {
  static drawElements(context: CanvasRenderingContext2D, elements: CanvasElement[]): void {
    const sortedElements = elements
      .map((element: CanvasElement): CanvasElement => element)
      .sort((left: CanvasElement, right: CanvasElement): number => left.zIndex - right.zIndex);

    for (const element of sortedElements) {
      CanvasElementRenderer.drawElement(context, element);
    }
  }

  private static drawElement(context: CanvasRenderingContext2D, element: CanvasElement): void {
    if (element.type === 'text') {
      CanvasElementRenderer.drawTextElement(context, element);
    } else if (element.type === 'shape') {
      CanvasElementRenderer.drawShapeElement(context, element);
    }
  }

  private static drawTextElement(context: CanvasRenderingContext2D, element: TextCanvasElement): void {
    const lines = CanvasElementRenderer.buildTextLines(element.content);
    const fontSize = Math.max(8, element.fontSize);
    const padding = 8;
    const lineHeight = fontSize * 1.25;
    const maxLineCount = Math.max(1, Math.floor((element.height - padding * 2) / lineHeight));

    context.save();
    CanvasElementRenderer.drawTextBackground(context, element);
    const textColor = CanvasElementRenderer.resolveCanvasColor(element.color, '#111827');
    context.fillStyle = textColor.fillStyle;
    context.globalAlpha = textColor.alpha;
    context.font = `${fontSize}px sans-serif`;
    context.textBaseline = 'top';

    for (let index = 0; index < Math.min(lines.length, maxLineCount); index += 1) {
      context.fillText(lines[index], element.x + padding, element.y + padding + index * lineHeight);
    }

    context.restore();
  }

  private static drawTextBackground(context: CanvasRenderingContext2D, element: TextCanvasElement): void {
    const backgroundColor = CanvasElementRenderer.resolveCanvasColor(element.backgroundColor, '#FFFFFF');
    if (backgroundColor.alpha <= 0) {
      return;
    }

    context.fillStyle = backgroundColor.fillStyle;
    context.globalAlpha = backgroundColor.alpha;
    context.fillRect(element.x, element.y, element.width, element.height);
  }

  private static drawShapeElement(context: CanvasRenderingContext2D, element: ShapeCanvasElement): void {
    context.save();
    context.globalAlpha = element.opacity;

    if (element.shapeType === 'rectangle') {
      CanvasElementRenderer.drawRectangleShape(context, element);
    } else if (element.shapeType === 'circle') {
      CanvasElementRenderer.drawCircleShape(context, element);
    } else if (element.shapeType === 'line') {
      CanvasElementRenderer.drawLineShape(context, element);
    }

    context.restore();
  }

  private static drawRectangleShape(context: CanvasRenderingContext2D, element: ShapeCanvasElement): void {
    CanvasElementRenderer.fillShapeRect(context, element);
    context.strokeStyle = CanvasElementRenderer.resolveCanvasColor(element.strokeColor, '#111827').fillStyle;
    context.lineWidth = Math.max(1, element.strokeWidth);
    context.strokeRect(element.x, element.y, element.width, element.height);
  }

  private static drawCircleShape(context: CanvasRenderingContext2D, element: ShapeCanvasElement): void {
    const radiusX = Math.max(1, element.width / 2);
    const radiusY = Math.max(1, element.height / 2);

    context.save();
    context.translate(element.x + radiusX, element.y + radiusY);
    context.scale(radiusX, radiusY);
    context.beginPath();
    context.arc(0, 0, 1, 0, Math.PI * 2);
    CanvasElementRenderer.fillCurrentShapePath(context, element.fillColor);
    context.strokeStyle = CanvasElementRenderer.resolveCanvasColor(element.strokeColor, '#111827').fillStyle;
    context.lineWidth = Math.max(1, element.strokeWidth) / Math.max(radiusX, radiusY);
    context.stroke();
    context.restore();
  }

  private static drawLineShape(context: CanvasRenderingContext2D, element: ShapeCanvasElement): void {
    const y = element.y + element.height / 2;
    context.strokeStyle = CanvasElementRenderer.resolveCanvasColor(element.strokeColor, '#111827').fillStyle;
    context.lineWidth = Math.max(1, element.strokeWidth);
    context.lineCap = 'round';
    context.beginPath();
    context.moveTo(element.x, y);
    context.lineTo(element.x + element.width, y);
    context.stroke();
  }

  private static fillShapeRect(context: CanvasRenderingContext2D, element: ShapeCanvasElement): void {
    const fillColor = CanvasElementRenderer.resolveCanvasColor(element.fillColor, '#FFFFFF');
    if (fillColor.alpha <= 0) {
      return;
    }

    context.save();
    context.globalAlpha = context.globalAlpha * fillColor.alpha;
    context.fillStyle = fillColor.fillStyle;
    context.fillRect(element.x, element.y, element.width, element.height);
    context.restore();
  }

  private static fillCurrentShapePath(context: CanvasRenderingContext2D, fillColorValue: string): void {
    const fillColor = CanvasElementRenderer.resolveCanvasColor(fillColorValue, '#FFFFFF');
    if (fillColor.alpha <= 0) {
      return;
    }

    context.save();
    context.globalAlpha = context.globalAlpha * fillColor.alpha;
    context.fillStyle = fillColor.fillStyle;
    context.fill();
    context.restore();
  }

  private static buildTextLines(content: string): string[] {
    const normalizedContent = content.length === 0 ? 'Text' : content;
    const rawLines = normalizedContent.split('\n');
    const result: string[] = [];

    for (const line of rawLines) {
      result.push(line.length === 0 ? ' ' : line);
    }

    return result.length === 0 ? ['Text'] : result;
  }

  private static resolveCanvasColor(color: string, fallbackFillStyle: string): CanvasResolvedColor {
    const normalizedColor = color.trim().toUpperCase();
    if (normalizedColor.length === 0 ||
      normalizedColor === 'TRANSPARENT') {
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
