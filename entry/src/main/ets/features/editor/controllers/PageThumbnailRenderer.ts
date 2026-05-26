import { CanvasElement } from '../../../domain/entities/CanvasElement';
import { NotebookPageTemplateType } from '../../../domain/entities/NotebookPage';
import { Stroke, StrokePoint } from '../../../domain/entities/Stroke';
import { CanvasDrawContext } from './CanvasDrawContext';
import { CanvasElementRenderer } from './CanvasElementRenderer';
import { PageTemplateRenderer } from './PageTemplateRenderer';

export interface PageThumbnailViewportSize {
  width: number;
  height: number;
}

export interface PageThumbnailRenderSnapshot {
  pageId: string;
  templateType: NotebookPageTemplateType;
  paperBackgroundColor: string;
  backgroundImageUri: string;
  canvasWidth: number;
  canvasHeight: number;
  contentVersion: number;
  activeStrokeVersion: string;
  isLoading: boolean;
  strokes: Stroke[];
  elements: CanvasElement[];
  strokeLayerZIndex: number;
  activeStroke: Stroke | null;
}

interface PageThumbnailSourceSize {
  width: number;
  height: number;
}

const THUMBNAIL_FALLBACK_WIDTH = 200;
const THUMBNAIL_FALLBACK_HEIGHT = 145;
const THUMBNAIL_FRAME_BACKGROUND_COLOR = '#E8EEF6';
const MIN_THUMBNAIL_SOURCE_WIDTH = 1;
const MIN_THUMBNAIL_SOURCE_HEIGHT = 1;
const MIN_SCREEN_POINT_GAP = 0.8;
const MIN_SCREEN_LINE_WIDTH = 0.8;
const HIGHLIGHTER_WIDTH_SCALE = 1.9;
const HIGHLIGHTER_ALPHA_SCALE = 0.42;
const PENCIL_ALPHA_SCALE = 0.7;
const PREVIEW_ALPHA_SCALE = 0.88;

export function createEmptyPageThumbnailRenderSnapshot(pageId: string = ''): PageThumbnailRenderSnapshot {
  return {
    pageId,
    templateType: NotebookPageTemplateType.BLANK,
    paperBackgroundColor: '#FFFFFF',
    backgroundImageUri: '',
    canvasWidth: THUMBNAIL_FALLBACK_WIDTH,
    canvasHeight: THUMBNAIL_FALLBACK_HEIGHT,
    contentVersion: 0,
    activeStrokeVersion: '',
    isLoading: false,
    strokes: [],
    elements: [],
    strokeLayerZIndex: 0,
    activeStroke: null
  };
}

export class PageThumbnailRenderer {
  static getViewportSize(context: CanvasDrawContext): PageThumbnailViewportSize {
    const contextWidth = context.width ?? 0;
    const contextHeight = context.height ?? 0;
    return {
      width: contextWidth > 0 ? contextWidth : THUMBNAIL_FALLBACK_WIDTH,
      height: contextHeight > 0 ? contextHeight : THUMBNAIL_FALLBACK_HEIGHT
    };
  }

  static buildRenderKey(snapshot: PageThumbnailRenderSnapshot, viewportSize: PageThumbnailViewportSize): string {
    return [
      snapshot.pageId,
      snapshot.templateType,
      snapshot.paperBackgroundColor,
      snapshot.backgroundImageUri,
      Math.round(snapshot.canvasWidth),
      Math.round(snapshot.canvasHeight),
      snapshot.contentVersion,
      snapshot.activeStrokeVersion,
      snapshot.strokeLayerZIndex,
      snapshot.isLoading ? 'loading' : 'ready',
      Math.round(viewportSize.width),
      Math.round(viewportSize.height)
    ].join('|');
  }

  static draw(
    context: CanvasDrawContext,
    snapshot: PageThumbnailRenderSnapshot,
    viewportSize: PageThumbnailViewportSize
  ): void {
    const width = Math.max(1, viewportSize.width);
    const height = Math.max(1, viewportSize.height);
    const sourceSize = this.getSourceSize(snapshot, viewportSize);
    const scale = Math.min(width / sourceSize.width, height / sourceSize.height);
    const scaledWidth = sourceSize.width * scale;
    const scaledHeight = sourceSize.height * scale;
    const offsetX = (width - scaledWidth) / 2;
    const offsetY = (height - scaledHeight) / 2;

    context.clearRect(0, 0, width, height);
    context.fillStyle = THUMBNAIL_FRAME_BACKGROUND_COLOR;
    context.fillRect(0, 0, width, height);

    context.save();
    context.translate(offsetX, offsetY);
    context.scale(scale, scale);
    const didDrawBackgroundImage = this.drawBackgroundImage(context, snapshot.backgroundImageUri, sourceSize);
    PageTemplateRenderer.drawTemplateBackground(
      context,
      snapshot.templateType,
      sourceSize.width,
      sourceSize.height,
      snapshot.paperBackgroundColor,
      undefined,
      snapshot.backgroundImageUri.length === 0 || !didDrawBackgroundImage
    );
    this.drawContent(context, snapshot, scale);
    context.restore();
  }

  private static getSourceSize(
    snapshot: PageThumbnailRenderSnapshot,
    viewportSize: PageThumbnailViewportSize
  ): PageThumbnailSourceSize {
    const width = Number(snapshot.canvasWidth);
    const height = Number(snapshot.canvasHeight);
    if (Number.isFinite(width) && width > 0 && Number.isFinite(height) && height > 0) {
      return {
        width: Math.max(MIN_THUMBNAIL_SOURCE_WIDTH, width),
        height: Math.max(MIN_THUMBNAIL_SOURCE_HEIGHT, height)
      };
    }

    return {
      width: Math.max(MIN_THUMBNAIL_SOURCE_WIDTH, viewportSize.width),
      height: Math.max(MIN_THUMBNAIL_SOURCE_HEIGHT, viewportSize.height)
    };
  }

  private static drawBackgroundImage(
    context: CanvasDrawContext,
    backgroundImageUri: string,
    sourceSize: PageThumbnailSourceSize
  ): boolean {
    const normalizedUri = this.resolveImageUri(backgroundImageUri);
    if (normalizedUri.length === 0 || sourceSize.width <= 0 || sourceSize.height <= 0) {
      return false;
    }

    const candidates = this.buildImageSourceCandidates(normalizedUri);
    for (const candidate of candidates) {
      let imageBitmap: ImageBitmap | undefined = undefined;
      try {
        imageBitmap = new ImageBitmap(candidate);
        context.drawImage(imageBitmap, 0, 0, sourceSize.width, sourceSize.height);
        return true;
      } catch (_error) {
      } finally {
        if (imageBitmap !== undefined) {
          try {
            imageBitmap.close();
          } catch (_closeError) {
          }
        }
      }
    }

    return false;
  }

  private static resolveImageUri(uri: string): string {
    if (typeof uri !== 'string') {
      return '';
    }

    const normalizedUri = uri.trim();
    if (normalizedUri.length === 0) {
      return '';
    }
    if (normalizedUri.startsWith('file://')) {
      if (normalizedUri.startsWith('file:///')) {
        return normalizedUri;
      }
      const rawLocalPath = normalizedUri.substring('file://'.length);
      return rawLocalPath.startsWith('/') ? `file://${rawLocalPath}` : `file:///${rawLocalPath}`;
    }
    if (normalizedUri.startsWith('http://') || normalizedUri.startsWith('https://')) {
      return normalizedUri;
    }
    return `file://${normalizedUri}`;
  }

  private static buildImageSourceCandidates(uri: string): string[] {
    const candidates: string[] = [];
    this.appendImageSourceCandidate(candidates, uri);

    if (uri.startsWith('file://')) {
      const rawLocalPath = uri.substring('file://'.length);
      this.appendImageSourceCandidate(candidates, rawLocalPath);
      if (!rawLocalPath.startsWith('/')) {
        this.appendImageSourceCandidate(candidates, `/${rawLocalPath}`);
      }
    }

    return candidates;
  }

  private static appendImageSourceCandidate(candidates: string[], candidate: string): void {
    if (candidate.length === 0 || candidates.includes(candidate)) {
      return;
    }
    candidates.push(candidate);
  }

  private static drawContent(
    context: CanvasDrawContext,
    snapshot: PageThumbnailRenderSnapshot,
    scale: number
  ): void {
    CanvasElementRenderer.drawElements(
      context,
      snapshot.elements.filter((element: CanvasElement): boolean => element.zIndex < snapshot.strokeLayerZIndex)
    );

    for (const stroke of snapshot.strokes) {
      this.drawStroke(context, stroke, scale, 1);
    }

    if (snapshot.activeStroke !== null) {
      this.drawStroke(context, snapshot.activeStroke, scale, PREVIEW_ALPHA_SCALE);
    }

    CanvasElementRenderer.drawElements(
      context,
      snapshot.elements.filter((element: CanvasElement): boolean => element.zIndex >= snapshot.strokeLayerZIndex)
    );
  }

  private static drawStroke(
    context: CanvasDrawContext,
    stroke: Stroke,
    scale: number,
    opacityMultiplier: number
  ): void {
    if (stroke.points.length === 0) {
      return;
    }

    const safeScale = Math.max(0.001, scale);
    const widthScale = stroke.style.tool === 'highlighter' ? HIGHLIGHTER_WIDTH_SCALE : 1;
    const alphaScale = stroke.style.tool === 'highlighter'
      ? HIGHLIGHTER_ALPHA_SCALE
      : (stroke.style.tool === 'pencil' ? PENCIL_ALPHA_SCALE : 1);
    const lineWidth = Math.max(MIN_SCREEN_LINE_WIDTH / safeScale, stroke.style.width * widthScale);

    context.save();
    context.strokeStyle = stroke.style.color;
    context.globalAlpha = Math.max(0, Math.min(1, stroke.style.opacity * alphaScale * opacityMultiplier));
    context.lineWidth = lineWidth;
    context.lineCap = stroke.style.tool === 'highlighter' ? 'butt' : 'round';
    context.lineJoin = 'round';
    context.beginPath();
    this.traceDecimatedPolyline(context, stroke.points, safeScale);
    context.stroke();
    context.restore();
  }

  private static traceDecimatedPolyline(
    context: CanvasDrawContext,
    points: StrokePoint[],
    scale: number
  ): void {
    const firstPoint = points[0];
    context.moveTo(firstPoint.x, firstPoint.y);

    if (points.length === 1) {
      context.lineTo(firstPoint.x + 0.1, firstPoint.y + 0.1);
      return;
    }

    const minimumPageDistance = Math.max(1, MIN_SCREEN_POINT_GAP / scale);
    let lastDrawnPoint = firstPoint;
    for (let index = 1; index < points.length; index += 1) {
      const point = points[index];
      const isLastPoint = index === points.length - 1;
      if (!isLastPoint && this.getSquaredDistance(lastDrawnPoint, point) < minimumPageDistance * minimumPageDistance) {
        continue;
      }

      context.lineTo(point.x, point.y);
      lastDrawnPoint = point;
    }
  }

  private static getSquaredDistance(left: StrokePoint, right: StrokePoint): number {
    const deltaX = left.x - right.x;
    const deltaY = left.y - right.y;
    return deltaX * deltaX + deltaY * deltaY;
  }
}
