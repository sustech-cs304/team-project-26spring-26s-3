import { NotebookPageTemplateType } from '../../../domain/entities/NotebookPage';
import { CanvasDrawContext } from './CanvasDrawContext';

export interface PageTemplateRenderRegion {
  x: number;
  y: number;
  width: number;
  height: number;
}

type PageTemplateRenderContext = CanvasDrawContext;

const TEMPLATE_LINE_COLOR = '#D7E3F3';
const TEMPLATE_GRID_COLOR = '#D8E5F8';
const TEMPLATE_DOT_COLOR = '#B8C5D8';
const LINED_SPACING = 46;
const GRID_SPACING = 36;
const DOT_SPACING = 28;
const DOT_RADIUS = 1.35;

export class PageTemplateRenderer {
  static drawTemplateBackground(
    context: PageTemplateRenderContext,
    templateType: NotebookPageTemplateType,
    width: number,
    height: number,
    backgroundColor: string,
    region?: PageTemplateRenderRegion,
    shouldFillBackground: boolean = true
  ): void {
    if (width <= 0 || height <= 0) {
      return;
    }

    const renderRegion: PageTemplateRenderRegion = this.normalizeRegion(region, width, height);
    if (renderRegion.width <= 0 || renderRegion.height <= 0) {
      return;
    }

    const normalizedTemplateType: NotebookPageTemplateType = this.normalizeTemplateType(templateType);
    context.save();
    if (shouldFillBackground) {
      context.fillStyle = backgroundColor;
      context.fillRect(renderRegion.x, renderRegion.y, renderRegion.width, renderRegion.height);
    }

    switch (normalizedTemplateType) {
      case NotebookPageTemplateType.LINED:
        this.drawHorizontalLines(context, renderRegion, LINED_SPACING, TEMPLATE_LINE_COLOR);
        break;
      case NotebookPageTemplateType.GRID:
        this.drawGrid(context, renderRegion, GRID_SPACING, TEMPLATE_GRID_COLOR);
        break;
      case NotebookPageTemplateType.DOTTED:
        this.drawDots(context, renderRegion, DOT_SPACING, TEMPLATE_DOT_COLOR);
        break;
      case NotebookPageTemplateType.BLANK:
      default:
        break;
    }

    context.restore();
  }

  private static normalizeTemplateType(templateType: NotebookPageTemplateType): NotebookPageTemplateType {
    switch (templateType) {
      case NotebookPageTemplateType.LINED:
        return NotebookPageTemplateType.LINED;
      case NotebookPageTemplateType.GRID:
        return NotebookPageTemplateType.GRID;
      case NotebookPageTemplateType.DOTTED:
        return NotebookPageTemplateType.DOTTED;
      case NotebookPageTemplateType.BLANK:
      default:
        return NotebookPageTemplateType.BLANK;
    }
  }

  private static drawHorizontalLines(
    context: PageTemplateRenderContext,
    region: PageTemplateRenderRegion,
    spacing: number,
    color: string
  ): void {
    const startY: number = Math.floor(region.y / spacing) * spacing;
    const endY: number = region.y + region.height;

    context.strokeStyle = color;
    context.lineWidth = 1;
    context.globalAlpha = 0.82;
    context.beginPath();

    for (let y: number = startY; y <= endY; y += spacing) {
      if (y < region.y) {
        continue;
      }
      const crispY: number = Math.round(y) + 0.5;
      context.moveTo(region.x, crispY);
      context.lineTo(region.x + region.width, crispY);
    }

    context.stroke();
    context.globalAlpha = 1;
  }

  private static drawGrid(
    context: PageTemplateRenderContext,
    region: PageTemplateRenderRegion,
    spacing: number,
    color: string
  ): void {
    const startX: number = Math.floor(region.x / spacing) * spacing;
    const startY: number = Math.floor(region.y / spacing) * spacing;
    const endX: number = region.x + region.width;
    const endY: number = region.y + region.height;

    context.strokeStyle = color;
    context.lineWidth = 1;
    context.globalAlpha = 0.74;
    context.beginPath();

    for (let x: number = startX; x <= endX; x += spacing) {
      if (x < region.x) {
        continue;
      }
      const crispX: number = Math.round(x) + 0.5;
      context.moveTo(crispX, region.y);
      context.lineTo(crispX, region.y + region.height);
    }

    for (let y: number = startY; y <= endY; y += spacing) {
      if (y < region.y) {
        continue;
      }
      const crispY: number = Math.round(y) + 0.5;
      context.moveTo(region.x, crispY);
      context.lineTo(region.x + region.width, crispY);
    }

    context.stroke();
    context.globalAlpha = 1;
  }

  private static drawDots(
    context: PageTemplateRenderContext,
    region: PageTemplateRenderRegion,
    spacing: number,
    color: string
  ): void {
    const startX: number = Math.floor(region.x / spacing) * spacing;
    const startY: number = Math.floor(region.y / spacing) * spacing;
    const endX: number = region.x + region.width;
    const endY: number = region.y + region.height;

    context.fillStyle = color;
    context.globalAlpha = 0.78;

    for (let x: number = startX; x <= endX; x += spacing) {
      if (x < region.x) {
        continue;
      }

      for (let y: number = startY; y <= endY; y += spacing) {
        if (y < region.y) {
          continue;
        }

        context.beginPath();
        context.arc(x, y, DOT_RADIUS, 0, Math.PI * 2);
        context.fill();
      }
    }

    context.globalAlpha = 1;
  }

  private static normalizeRegion(
    region: PageTemplateRenderRegion | undefined,
    width: number,
    height: number
  ): PageTemplateRenderRegion {
    if (region === undefined) {
      return {
        x: 0,
        y: 0,
        width: width,
        height: height
      };
    }

    const x: number = Math.max(0, Math.min(width, region.x));
    const y: number = Math.max(0, Math.min(height, region.y));
    const maxX: number = Math.max(x, Math.min(width, region.x + region.width));
    const maxY: number = Math.max(y, Math.min(height, region.y + region.height));

    return {
      x: x,
      y: y,
      width: maxX - x,
      height: maxY - y
    };
  }
}
