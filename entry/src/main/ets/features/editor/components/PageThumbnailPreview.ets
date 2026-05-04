import common from '@ohos.app.ability.common';

import { EditorRepositoryImpl } from '../../../data/repositories/EditorRepositoryImpl';
import { NotebookPageTemplateType } from '../../../domain/entities/NotebookPage';
import { Stroke, StrokePoint } from '../../../domain/entities/Stroke';
import { PageTemplateRenderer } from '../controllers/PageTemplateRenderer';
import { StrokeRenderer } from '../controllers/StrokeRenderer';
import { DrawingEditorViewModel } from '../viewmodels/DrawingEditorViewModel';
import { EditorSessionRegistry } from '../viewmodels/EditorSessionRegistry';

interface ThumbnailCanvasSize {
  width: number;
  height: number;
}

const THUMBNAIL_FALLBACK_WIDTH = 184;
const THUMBNAIL_FALLBACK_HEIGHT = 132;
const THUMBNAIL_INFERRED_CANVAS_MARGIN = 48;

@Component
export struct PageThumbnailPreview {
  @Watch('onPageSourceChanged')
  @Prop pageId: string = '';
  @Watch('onPageSourceChanged')
  @Prop isActive: boolean = false;
  @Watch('onRefreshVersionChanged')
  @Prop refreshVersion: number = 0;
  @Watch('onCanvasStyleChanged')
  @Prop templateType: NotebookPageTemplateType = NotebookPageTemplateType.BLANK;
  @Watch('onCanvasStyleChanged')
  @Prop paperBackgroundColor: string = '#FFFFFF';
  @Watch('onCanvasStyleChanged')
  @Prop canvasWidth: number = 0;
  @Watch('onCanvasStyleChanged')
  @Prop canvasHeight: number = 0;

  @State private storedStrokes: Stroke[] = [];
  @State private isCanvasReady: boolean = false;
  private readonly renderingSettings: RenderingContextSettings = new RenderingContextSettings(true);
  private readonly thumbnailContext: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.renderingSettings);

  aboutToAppear(): void {
    void this.loadStoredStrokes();
  }

  build() {
    Canvas(this.thumbnailContext)
      .width('100%')
      .height('100%')
      .backgroundColor(this.paperBackgroundColor)
      .onReady(() => {
        this.isCanvasReady = true;
        void this.loadStoredStrokes();
        this.redrawThumbnail();
      })
  }

  private onPageSourceChanged(): void {
    void this.loadStoredStrokes();
    this.redrawThumbnail();
  }

  private onRefreshVersionChanged(): void {
    this.redrawThumbnail();
  }

  private onCanvasStyleChanged(): void {
    this.redrawThumbnail();
  }

  private async loadStoredStrokes(): Promise<void> {
    if (this.pageId.length === 0) {
      this.storedStrokes = [];
      this.redrawThumbnail();
      return;
    }

    if (this.isActive && EditorSessionRegistry.get(this.pageId) !== null) {
      this.redrawThumbnail();
      return;
    }

    try {
      const hostContext: common.Context | undefined = this.getUIContext().getHostContext() as common.Context | undefined;
      if (hostContext === undefined) {
        return;
      }

      this.storedStrokes = await new EditorRepositoryImpl(hostContext).getStrokes(this.pageId);
      this.redrawThumbnail();
    } catch (_error) {
      this.storedStrokes = [];
      this.redrawThumbnail();
    }
  }

  private redrawThumbnail(): void {
    if (!this.isCanvasReady) {
      return;
    }

    const size: ThumbnailCanvasSize = this.getThumbnailCanvasSize();
    const strokes: Stroke[] = this.getRenderableStrokes();
    const activeStroke = this.getActiveStroke();
    const sourceCanvasSize: ThumbnailCanvasSize = this.getSourceCanvasSize(size, strokes, activeStroke);
    const scale = Math.min(size.width / sourceCanvasSize.width, size.height / sourceCanvasSize.height);
    const scaledWidth = sourceCanvasSize.width * scale;
    const scaledHeight = sourceCanvasSize.height * scale;
    const offsetX = (size.width - scaledWidth) / 2;
    const offsetY = (size.height - scaledHeight) / 2;

    this.thumbnailContext.clearRect(0, 0, size.width, size.height);
    this.thumbnailContext.fillStyle = this.paperBackgroundColor;
    this.thumbnailContext.fillRect(0, 0, size.width, size.height);

    this.thumbnailContext.save();
    this.thumbnailContext.translate(offsetX, offsetY);
    this.thumbnailContext.scale(scale, scale);
    PageTemplateRenderer.drawTemplateBackground(
      this.thumbnailContext,
      this.getTemplateType(),
      sourceCanvasSize.width,
      sourceCanvasSize.height,
      this.paperBackgroundColor
    );
    this.drawPageStrokes(strokes, activeStroke);
    this.thumbnailContext.restore();
  }

  private drawPageStrokes(strokes: Stroke[], activeStroke: Stroke | null): void {
    for (const stroke of strokes) {
      StrokeRenderer.drawStroke(this.thumbnailContext, stroke);
    }

    if (activeStroke !== null) {
      StrokeRenderer.drawPreviewStroke(this.thumbnailContext, activeStroke);
    }
  }

  private getSourceCanvasSize(
    thumbnailSize: ThumbnailCanvasSize,
    strokes: Stroke[],
    activeStroke: Stroke | null
  ): ThumbnailCanvasSize {
    if (this.canvasWidth > 0 && this.canvasHeight > 0) {
      return {
        width: this.canvasWidth,
        height: this.canvasHeight
      };
    }

    const inferredCanvasSize = this.inferCanvasSizeFromStrokes(thumbnailSize, strokes, activeStroke);
    if (inferredCanvasSize !== null) {
      return inferredCanvasSize;
    }

    return {
      width: thumbnailSize.width,
      height: thumbnailSize.height
    };
  }

  private inferCanvasSizeFromStrokes(
    thumbnailSize: ThumbnailCanvasSize,
    strokes: Stroke[],
    activeStroke: Stroke | null
  ): ThumbnailCanvasSize | null {
    let maxX = 0;
    let maxY = 0;
    let hasPoint = false;

    for (const stroke of strokes) {
      for (const point of stroke.points) {
        maxX = Math.max(maxX, point.x);
        maxY = Math.max(maxY, point.y);
        hasPoint = true;
      }
    }

    if (activeStroke !== null) {
      for (const point of activeStroke.points) {
        maxX = Math.max(maxX, point.x);
        maxY = Math.max(maxY, point.y);
        hasPoint = true;
      }
    }

    if (!hasPoint) {
      return null;
    }

    const thumbnailAspectRatio = thumbnailSize.width / Math.max(1, thumbnailSize.height);
    let inferredWidth = Math.max(1, maxX + THUMBNAIL_INFERRED_CANVAS_MARGIN);
    let inferredHeight = Math.max(1, maxY + THUMBNAIL_INFERRED_CANVAS_MARGIN);
    const inferredAspectRatio = inferredWidth / inferredHeight;

    if (inferredAspectRatio < thumbnailAspectRatio) {
      inferredWidth = inferredHeight * thumbnailAspectRatio;
    } else {
      inferredHeight = inferredWidth / thumbnailAspectRatio;
    }

    return {
      width: inferredWidth,
      height: inferredHeight
    };
  }

  private getRenderableStrokes(): Stroke[] {
    const activeSession: DrawingEditorViewModel | null = this.isActive ? EditorSessionRegistry.get(this.pageId) : null;
    if (activeSession !== null) {
      return activeSession.getStrokesForRendering();
    }

    return this.storedStrokes.map((stroke: Stroke): Stroke => this.cloneStroke(stroke));
  }

  private getActiveStroke(): Stroke | null {
    if (!this.isActive) {
      return null;
    }

    const activeSession: DrawingEditorViewModel | null = EditorSessionRegistry.get(this.pageId);
    if (activeSession === null) {
      return null;
    }

    return activeSession.getActiveStroke();
  }

  private getThumbnailCanvasSize(): ThumbnailCanvasSize {
    return {
      width: this.thumbnailContext.width > 0 ? this.thumbnailContext.width : THUMBNAIL_FALLBACK_WIDTH,
      height: this.thumbnailContext.height > 0 ? this.thumbnailContext.height : THUMBNAIL_FALLBACK_HEIGHT
    };
  }

  private getTemplateType(): NotebookPageTemplateType {
    switch (this.templateType) {
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

  private cloneStroke(stroke: Stroke): Stroke {
    return {
      id: stroke.id,
      pageId: stroke.pageId,
      points: stroke.points.map((point: StrokePoint): StrokePoint => {
        return {
          x: point.x,
          y: point.y,
          t: point.t,
          pressure: point.pressure
        };
      }),
      style: {
        tool: stroke.style.tool,
        color: stroke.style.color,
        width: stroke.style.width,
        opacity: stroke.style.opacity
      },
      createdAt: stroke.createdAt,
      updatedAt: stroke.updatedAt
    };
  }
}
