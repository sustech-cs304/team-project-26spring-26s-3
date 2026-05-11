import common from '@ohos.app.ability.common';

import { EditorRepositoryImpl } from '../../../data/repositories/EditorRepositoryImpl';
import { CanvasElement, PageCanvasContent, ShapeGeometryPoint } from '../../../domain/entities/CanvasElement';
import { NotebookPageTemplateType } from '../../../domain/entities/NotebookPage';
import { Stroke, StrokePoint } from '../../../domain/entities/Stroke';
import { CanvasElementRenderer } from '../controllers/CanvasElementRenderer';
import { PageTemplateRenderer } from '../controllers/PageTemplateRenderer';
import { StrokeRenderer } from '../controllers/StrokeRenderer';
import { DrawingEditorViewModel } from '../viewmodels/DrawingEditorViewModel';
import { EditorSessionRegistry } from '../viewmodels/EditorSessionRegistry';

interface ThumbnailCanvasSize {
  width: number;
  height: number;
}

const THUMBNAIL_FALLBACK_WIDTH = 200;
const THUMBNAIL_FALLBACK_HEIGHT = 145;
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
  @State private storedElements: CanvasElement[] = [];
  @State private isCanvasReady: boolean = false;
  private readonly renderingSettings: RenderingContextSettings = new RenderingContextSettings(true);
  private readonly thumbnailContext: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.renderingSettings);

  aboutToAppear(): void {
    void this.loadStoredPageContent();
  }

  build() {
    Canvas(this.thumbnailContext)
      .width('100%')
      .height('100%')
      .backgroundColor(this.paperBackgroundColor)
      .onReady(() => {
        this.isCanvasReady = true;
        void this.loadStoredPageContent();
        this.redrawThumbnail();
      })
  }

  private onPageSourceChanged(): void {
    void this.loadStoredPageContent();
    this.redrawThumbnail();
  }

  private onRefreshVersionChanged(): void {
    if (!this.isActive) {
      return;
    }

    this.redrawThumbnail();
  }

  private onCanvasStyleChanged(): void {
    this.redrawThumbnail();
  }

  private async loadStoredPageContent(): Promise<void> {
    const targetPageId = this.pageId;
    if (targetPageId.length === 0) {
      this.storedStrokes = [];
      this.storedElements = [];
      this.redrawThumbnail();
      return;
    }

    const activeSession: DrawingEditorViewModel | null = EditorSessionRegistry.get(targetPageId);
    if (activeSession !== null) {
      this.storedStrokes = activeSession.getStrokes();
      this.storedElements = activeSession.getElements();
      this.redrawThumbnail();
      return;
    }

    try {
      const hostContext: common.Context | undefined = this.getUIContext().getHostContext() as common.Context | undefined;
      if (hostContext === undefined) {
        return;
      }

      const pageContent: PageCanvasContent = await new EditorRepositoryImpl(hostContext).getPageContent(targetPageId);
      if (this.pageId !== targetPageId) {
        return;
      }

      this.storedStrokes = pageContent.strokes;
      this.storedElements = pageContent.elements;
      this.redrawThumbnail();
    } catch (_error) {
      if (this.pageId !== targetPageId) {
        return;
      }

      this.storedStrokes = [];
      this.storedElements = [];
      this.redrawThumbnail();
    }
  }

  private redrawThumbnail(): void {
    if (!this.isCanvasReady) {
      return;
    }

    const size: ThumbnailCanvasSize = this.getThumbnailCanvasSize();
    const strokes: Stroke[] = this.getRenderableStrokes();
    const elements: CanvasElement[] = this.getRenderableElements();
    const activeStroke = this.getActiveStroke();
    const sourceCanvasSize: ThumbnailCanvasSize = this.getSourceCanvasSize(size, strokes, elements, activeStroke);
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
    this.drawPageContent(strokes, elements, activeStroke);
    this.thumbnailContext.restore();
  }

  private drawPageContent(strokes: Stroke[], elements: CanvasElement[], activeStroke: Stroke | null): void {
    for (const stroke of strokes) {
      StrokeRenderer.drawStrokeFast(this.thumbnailContext, stroke);
    }

    CanvasElementRenderer.drawElements(this.thumbnailContext, elements);

    if (activeStroke !== null) {
      StrokeRenderer.drawPreviewStrokeFast(this.thumbnailContext, activeStroke);
    }
  }

  private getSourceCanvasSize(
    thumbnailSize: ThumbnailCanvasSize,
    strokes: Stroke[],
    elements: CanvasElement[],
    activeStroke: Stroke | null
  ): ThumbnailCanvasSize {
    if (this.canvasWidth > 0 && this.canvasHeight > 0) {
      return {
        width: this.canvasWidth,
        height: this.canvasHeight
      };
    }

    const inferredCanvasSize = this.inferCanvasSizeFromContent(thumbnailSize, strokes, elements, activeStroke);
    if (inferredCanvasSize !== null) {
      return inferredCanvasSize;
    }

    return {
      width: thumbnailSize.width,
      height: thumbnailSize.height
    };
  }

  private inferCanvasSizeFromContent(
    thumbnailSize: ThumbnailCanvasSize,
    strokes: Stroke[],
    elements: CanvasElement[],
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

    for (const element of elements) {
      maxX = Math.max(maxX, element.x + element.width);
      maxY = Math.max(maxY, element.y + element.height);
      hasPoint = true;
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

    return this.storedStrokes;
  }

  private getRenderableElements(): CanvasElement[] {
    const activeSession: DrawingEditorViewModel | null = this.isActive ? EditorSessionRegistry.get(this.pageId) : null;
    if (activeSession !== null) {
      return activeSession.getElements();
    }

    return this.storedElements.map((element: CanvasElement): CanvasElement => this.cloneElement(element));
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

  private cloneElement(element: CanvasElement): CanvasElement {
    if (element.type === 'text') {
      return {
        id: element.id,
        pageId: element.pageId,
        type: 'text',
        x: element.x,
        y: element.y,
        width: element.width,
        height: element.height,
        rotation: element.rotation,
        zIndex: element.zIndex,
        createdAt: element.createdAt,
        updatedAt: element.updatedAt,
        content: element.content,
        color: element.color,
        fontSize: element.fontSize,
        backgroundColor: element.backgroundColor
      };
    }

    if (element.type === 'shape') {
      return {
        id: element.id,
        pageId: element.pageId,
        type: 'shape',
        x: element.x,
        y: element.y,
        width: element.width,
        height: element.height,
        rotation: element.rotation,
        zIndex: element.zIndex,
        createdAt: element.createdAt,
        updatedAt: element.updatedAt,
        shapeType: element.shapeType,
        geometry: {
          kind: element.geometry.kind,
          points: element.geometry.points.map((point: ShapeGeometryPoint): ShapeGeometryPoint => {
            return {
              x: point.x,
              y: point.y
            };
          })
        },
        strokeColor: element.strokeColor,
        fillColor: element.fillColor,
        strokeWidth: element.strokeWidth,
        opacity: element.opacity
      };
    }

    return {
      id: element.id,
      pageId: element.pageId,
      type: 'image',
      x: element.x,
      y: element.y,
      width: element.width,
      height: element.height,
      rotation: element.rotation,
      zIndex: element.zIndex,
      createdAt: element.createdAt,
      updatedAt: element.updatedAt,
      uri: element.uri,
      originalWidth: element.originalWidth,
      originalHeight: element.originalHeight,
      opacity: element.opacity
    };
  }
}
