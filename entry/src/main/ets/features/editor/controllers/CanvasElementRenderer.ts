import {
  CanvasElement,
  ElementOutlineStyle,
  ImageCanvasElement,
  ShapeCanvasElement,
  TextCanvasElement
} from '../../../domain/entities/CanvasElement';
import { CanvasDrawContext } from './CanvasDrawContext';
import { ShapeRenderer } from './ShapeRenderer';

interface CanvasResolvedColor {
  fillStyle: string;
  alpha: number;
}

const TEXT_HORIZONTAL_PADDING = 16;
const TEXT_VERTICAL_PADDING = 12;
const TEXT_LINE_HEIGHT_FACTOR = 1.35;
const TEXT_PADDING_LEFT = 8;
const TEXT_PADDING_TOP = 6;

export class CanvasElementRenderer {
  static drawElements(context: CanvasDrawContext, elements: CanvasElement[]): void {
    const sortedElements = elements
      .map((element: CanvasElement): CanvasElement => element)
      .sort((left: CanvasElement, right: CanvasElement): number => left.zIndex - right.zIndex);

    for (const element of sortedElements) {
      CanvasElementRenderer.drawElement(context, element);
    }
  }

  private static drawElement(context: CanvasDrawContext, element: CanvasElement): void {
    if (element.type === 'text') {
      CanvasElementRenderer.drawTextElement(context, element);
    } else if (element.type === 'shape') {
      CanvasElementRenderer.drawShapeElement(context, element);
    } else if (element.type === 'image') {
      CanvasElementRenderer.drawImageElement(context, element);
    }
  }

  private static drawTextElement(context: CanvasDrawContext, element: TextCanvasElement): void {
    const fontSize = Math.max(8, element.fontSize);
    const lineHeight = fontSize * TEXT_LINE_HEIGHT_FACTOR;
    const maxLineCount = Math.max(1, Math.floor((element.height - TEXT_VERTICAL_PADDING) / lineHeight));

    context.save();
    CanvasElementRenderer.drawTextBackground(context, element);
    const textColor = CanvasElementRenderer.resolveCanvasColor(element.color, '#111827');
    context.fillStyle = textColor.fillStyle;
    context.globalAlpha = textColor.alpha;
    context.font = `${fontSize}px monospace`;
    context.textBaseline = 'top';
    const lines = CanvasElementRenderer.buildWrappedTextLines(context, element.content, element.width);

    for (let index = 0; index < Math.min(lines.length, maxLineCount); index += 1) {
      context.fillText(lines[index], element.x + TEXT_PADDING_LEFT, element.y + TEXT_PADDING_TOP + index * lineHeight);
    }

    context.restore();
  }

  private static drawTextBackground(context: CanvasDrawContext, element: TextCanvasElement): void {
    const backgroundColor = CanvasElementRenderer.resolveCanvasColor(element.backgroundColor, '#FFFFFF');
    if (backgroundColor.alpha <= 0) {
      return;
    }

    context.fillStyle = backgroundColor.fillStyle;
    context.globalAlpha = backgroundColor.alpha;
    context.fillRect(element.x, element.y, element.width, element.height);
  }

  private static drawShapeElement(context: CanvasDrawContext, element: ShapeCanvasElement): void {
    ShapeRenderer.drawShape(context, element);
  }

  private static drawImageElement(context: CanvasDrawContext, element: ImageCanvasElement): void {
    const candidates: string[] = CanvasElementRenderer.buildImageSourceCandidates(element.uri);
    for (const candidate of candidates) {
      let imageBitmap: ImageBitmap | undefined = undefined;
      let hasSavedContext: boolean = false;
      try {
        imageBitmap = new ImageBitmap(candidate);
        context.save();
        hasSavedContext = true;
        context.globalAlpha = Math.max(0, Math.min(1, element.opacity));
        context.drawImage(imageBitmap, element.x, element.y, element.width, element.height);
        context.restore();
        hasSavedContext = false;
        CanvasElementRenderer.drawImageOutline(context, element);
        return;
      } catch (_error) {
        if (hasSavedContext) {
          try {
            context.restore();
          } catch (_restoreError) {
          }
        }
      } finally {
        if (imageBitmap !== undefined) {
          try {
            imageBitmap.close();
          } catch (_closeError) {
          }
        }
      }
    }

    CanvasElementRenderer.drawImagePlaceholder(context, element);
    CanvasElementRenderer.drawImageOutline(context, element);
  }

  private static drawImageOutline(context: CanvasDrawContext, element: ImageCanvasElement): void {
    const lineWidth = CanvasElementRenderer.getVisibleOutlineWidth(element.outline);
    if (lineWidth <= 0) {
      return;
    }

    context.save();
    try {
      context.globalAlpha = 1;
      context.strokeStyle = element.outline.color;
      context.lineWidth = lineWidth;
      CanvasElementRenderer.applyLineDash(context, element.outline, lineWidth);
      context.strokeRect(
        element.x + lineWidth / 2,
        element.y + lineWidth / 2,
        Math.max(0, element.width - lineWidth),
        Math.max(0, element.height - lineWidth)
      );
    } finally {
      try {
        context.restore();
      } catch (_restoreError) {
      }
    }
  }

  private static getVisibleOutlineWidth(outline: ElementOutlineStyle): number {
    if (outline.lineStyle === 'none' || outline.width <= 0) {
      return 0;
    }

    return Math.max(1, outline.width);
  }

  private static applyLineDash(context: CanvasDrawContext, outline: ElementOutlineStyle, lineWidth: number): void {
    if (context.setLineDash === undefined) {
      return;
    }

    if (outline.lineStyle === 'dashed') {
      context.setLineDash([Math.max(4, lineWidth * 3), Math.max(3, lineWidth * 2)]);
    } else if (outline.lineStyle === 'dotted') {
      context.setLineDash([Math.max(1, lineWidth), Math.max(3, lineWidth * 2)]);
    } else {
      context.setLineDash([]);
    }
  }

  private static buildImageSourceCandidates(path: string): string[] {
    const candidates: string[] = [];
    CanvasElementRenderer.appendImageSourceCandidate(candidates, path);

    if (path.startsWith('file://')) {
      const rawLocalPath: string = path.substring('file://'.length);
      CanvasElementRenderer.appendImageSourceCandidate(candidates, rawLocalPath);
      if (!rawLocalPath.startsWith('/')) {
        CanvasElementRenderer.appendImageSourceCandidate(candidates, `/${rawLocalPath}`);
      }
    } else if (!path.startsWith('http://') && !path.startsWith('https://')) {
      CanvasElementRenderer.appendImageSourceCandidate(candidates, `file://${path}`);
    }

    return candidates;
  }

  private static appendImageSourceCandidate(candidates: string[], candidate: string): void {
    if (candidate.length === 0) {
      return;
    }
    if (!candidates.includes(candidate)) {
      candidates.push(candidate);
    }
  }

  private static drawImagePlaceholder(context: CanvasDrawContext, element: ImageCanvasElement): void {
    context.save();
    try {
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
    } finally {
      try {
        context.restore();
      } catch (_restoreError) {
      }
    }
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

  private static buildWrappedTextLines(context: CanvasDrawContext, content: string, width: number): string[] {
    const hardLines = CanvasElementRenderer.buildTextLines(content);
    const result: string[] = [];
    const contentWidth = Math.max(1, width - TEXT_HORIZONTAL_PADDING);

    for (const hardLine of hardLines) {
      let currentLine = '';
      for (let index = 0; index < hardLine.length; index += 1) {
        const nextCharacter = hardLine.charAt(index);
        const nextLine = currentLine + nextCharacter;
        if (currentLine.length === 0 || context.measureText(nextLine).width <= contentWidth) {
          currentLine = nextLine;
        } else {
          result.push(currentLine);
          currentLine = nextCharacter;
        }
      }
      result.push(currentLine.length === 0 ? ' ' : currentLine);
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
