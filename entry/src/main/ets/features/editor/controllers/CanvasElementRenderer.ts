import { CanvasElement, ImageCanvasElement, ShapeCanvasElement, TextCanvasElement } from '../../../domain/entities/CanvasElement';
import { ShapeRenderer } from './ShapeRenderer';

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
    } else if (element.type === 'image') {
      CanvasElementRenderer.drawImagePlaceholder(context, element);
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
    ShapeRenderer.drawShape(context, element);
  }

  private static drawImagePlaceholder(context: CanvasRenderingContext2D, element: ImageCanvasElement): void {
    context.save();
    context.globalAlpha = Math.max(0, Math.min(1, element.opacity));
    context.fillStyle = '#F8FAFC';
    context.fillRect(element.x, element.y, element.width, element.height);
    context.strokeStyle = '#94A3B8';
    context.lineWidth = 1;
    context.strokeRect(element.x, element.y, element.width, element.height);
    context.fillStyle = '#475569';
    context.font = '14px sans-serif';
    context.textBaseline = 'middle';
    context.textAlign = 'center';
    context.fillText('Image', element.x + element.width / 2, element.y + element.height / 2);
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
