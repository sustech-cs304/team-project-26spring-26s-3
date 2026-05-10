import { CanvasElement, TextCanvasElement } from '../../../domain/entities/CanvasElement';

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
    context.fillStyle = element.color;
    context.globalAlpha = 1;
    context.font = `${fontSize}px sans-serif`;
    context.textBaseline = 'top';

    for (let index = 0; index < Math.min(lines.length, maxLineCount); index += 1) {
      context.fillText(lines[index], element.x + padding, element.y + padding + index * lineHeight);
    }

    context.restore();
  }

  private static drawTextBackground(context: CanvasRenderingContext2D, element: TextCanvasElement): void {
    if (CanvasElementRenderer.isTransparentColor(element.backgroundColor)) {
      return;
    }

    context.fillStyle = element.backgroundColor;
    context.globalAlpha = 1;
    context.fillRect(element.x, element.y, element.width, element.height);
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

  private static isTransparentColor(color: string): boolean {
    const normalizedColor = color.trim().toUpperCase();
    return normalizedColor.length === 0 ||
      normalizedColor === 'TRANSPARENT' ||
      normalizedColor === '#00000000' ||
      normalizedColor === '#FFFFFF00';
  }
}
