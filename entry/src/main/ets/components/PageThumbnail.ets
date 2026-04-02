import common from '@ohos.app.ability.common';
import { PageTemplate } from '../models/NotePage';
import { Stroke } from '../models/Stroke';
import { StrokeRepository } from '../services/StrokeRepository';
import { DEFAULT_PAGE_TEMPLATE, normalizePageTemplate } from '../utils/PageTemplateUtils';

const THUMBNAIL_BACKGROUND = '#FFFDF7';
const THUMBNAIL_GUIDE = '#E2E8F0';
const THUMBNAIL_DOT = '#CBD5E1';
const THUMBNAIL_PAGE_WIDTH = 1600;
const THUMBNAIL_PAGE_HEIGHT = 900;
const THUMBNAIL_GUIDE_START = 72;
const THUMBNAIL_GUIDE_GAP = 64;
const THUMBNAIL_SIDE_PADDING = 10;
const THUMBNAIL_GRID_START_X = 64;

@Component
export struct PageThumbnail {
  @Watch('handleInputChange') @Prop pageId: string = '';
  @Watch('handleInputChange') @Prop pageUpdatedAt: number = 0;
  @Watch('handleInputChange') @Prop template: PageTemplate = DEFAULT_PAGE_TEMPLATE;
  @Prop strokeCount: number = 0;
  @Watch('handleRefreshSignalChange') @StorageLink('page_thumbnail_refresh_signal') private pageThumbnailRefreshSignal: string = '';

  @State private strokes: Stroke[] = [];
  @State private currentTemplate: PageTemplate = DEFAULT_PAGE_TEMPLATE;

  private readonly renderingSettings: RenderingContextSettings = new RenderingContextSettings(true);
  private readonly context2D: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.renderingSettings);
  private isCanvasReady: boolean = false;
  private strokeRepository?: StrokeRepository;

  async aboutToAppear(): Promise<void> {
    this.currentTemplate = this.template;
    await this.loadThumbnail();
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Canvas(this.context2D)
        .width(112)
        .height(84)
        .backgroundColor(THUMBNAIL_BACKGROUND)
        .borderRadius(14)
        .onReady(() => {
          this.isCanvasReady = true;
          this.redraw();
        })

      if (this.strokeCount === 0) {
        Text('Empty')
          .fontSize(11)
          .fontColor('#94A3B8')
      }
    }
    .width(112)
    .height(84)
    .border({
      width: 1,
      color: '#D7E0EA'
    })
    .borderRadius(14)
    .clip(true)
  }

  private handleInputChange(): void {
    this.currentTemplate = this.template;
    void this.loadThumbnail();
  }

  private handleRefreshSignalChange(): void {
    if (this.pageThumbnailRefreshSignal.startsWith(`${this.pageId}|`)) {
      const template = this.readTemplateFromSignal(this.pageThumbnailRefreshSignal);
      if (template) {
        this.currentTemplate = template;
        this.redraw();
      }
      void this.loadThumbnail();
    }
  }

  private async loadThumbnail(): Promise<void> {
    if (this.pageId.length === 0) {
      this.strokes = [];
      this.redraw();
      return;
    }

    try {
      this.strokes = await this.getStrokeRepository().listByPage(this.pageId);
    } catch (_error) {
      this.strokes = [];
    }
    this.redraw();
  }

  private redraw(): void {
    if (!this.isCanvasReady) {
      return;
    }

    const width = this.context2D.width > 0 ? this.context2D.width : 112;
    const height = this.context2D.height > 0 ? this.context2D.height : 84;
    this.context2D.clearRect(0, 0, width, height);
    this.context2D.fillStyle = THUMBNAIL_BACKGROUND;
    this.context2D.fillRect(0, 0, width, height);
    this.drawGuides(width, height);

    this.strokes.forEach((stroke: Stroke) => {
      this.drawStroke(stroke, width, height);
    });
  }

  private drawGuides(width: number, height: number): void {
    if (this.currentTemplate === 'blank') {
      return;
    }

    const scaleX = width / THUMBNAIL_PAGE_WIDTH;
    const scaleY = height / THUMBNAIL_PAGE_HEIGHT;
    if (this.currentTemplate === 'dot') {
      this.drawDotGuides(scaleX, scaleY);
      return;
    }

    this.context2D.beginPath();
    this.context2D.lineWidth = 0.8;
    this.context2D.strokeStyle = THUMBNAIL_GUIDE;

    let y = THUMBNAIL_GUIDE_START;
    while (y <= THUMBNAIL_PAGE_HEIGHT) {
      this.context2D.moveTo(THUMBNAIL_SIDE_PADDING * scaleX, y * scaleY);
      this.context2D.lineTo(width - THUMBNAIL_SIDE_PADDING * scaleX, y * scaleY);
      y += THUMBNAIL_GUIDE_GAP;
    }

    if (this.currentTemplate === 'grid') {
      let x = THUMBNAIL_GRID_START_X;
      while (x <= THUMBNAIL_PAGE_WIDTH) {
        this.context2D.moveTo(x * scaleX, 0);
        this.context2D.lineTo(x * scaleX, height);
        x += THUMBNAIL_GUIDE_GAP;
      }
    }

    this.context2D.stroke();
  }

  private drawDotGuides(scaleX: number, scaleY: number): void {
    this.context2D.beginPath();
    this.context2D.fillStyle = THUMBNAIL_DOT;

    let y = THUMBNAIL_GUIDE_START;
    while (y <= THUMBNAIL_PAGE_HEIGHT) {
      let x = THUMBNAIL_GRID_START_X;
      while (x <= THUMBNAIL_PAGE_WIDTH) {
        this.context2D.moveTo(x * scaleX + 1, y * scaleY);
        this.context2D.arc(x * scaleX, y * scaleY, 1.2, 0, Math.PI * 2);
        x += THUMBNAIL_GUIDE_GAP;
      }
      y += THUMBNAIL_GUIDE_GAP;
    }

    this.context2D.fill();
  }

  private drawStroke(stroke: Stroke, width: number, height: number): void {
    if (stroke.points.length === 0) {
      return;
    }

    const scaleX = width / THUMBNAIL_PAGE_WIDTH;
    const scaleY = height / THUMBNAIL_PAGE_HEIGHT;
    this.context2D.beginPath();
    this.context2D.globalCompositeOperation = stroke.tool === 'eraser' ? 'destination-out' : 'source-over';
    this.context2D.lineWidth = Math.max(0.8, stroke.width * Math.min(scaleX, scaleY));
    this.context2D.lineCap = 'round';
    this.context2D.lineJoin = 'round';
    this.context2D.strokeStyle = stroke.color;

    const firstPoint = stroke.points[0];
    this.context2D.moveTo(firstPoint.x * scaleX, firstPoint.y * scaleY);
    stroke.points.slice(1).forEach((point) => {
      this.context2D.lineTo(point.x * scaleX, point.y * scaleY);
    });

    if (stroke.points.length === 1) {
      this.context2D.lineTo((firstPoint.x + 0.1) * scaleX, (firstPoint.y + 0.1) * scaleY);
    }

    this.context2D.stroke();
    this.context2D.globalCompositeOperation = 'source-over';
  }

  private getStrokeRepository(): StrokeRepository {
    if (!this.strokeRepository) {
      this.strokeRepository = new StrokeRepository(this.getHostContext());
    }
    return this.strokeRepository;
  }

  private getHostContext(): common.Context | undefined {
    const hostContext = this.getUIContext().getHostContext();
    return hostContext as common.Context | undefined;
  }

  private readTemplateFromSignal(signal: string): PageTemplate | undefined {
    const marker = 'template:';
    const markerIndex = signal.indexOf(marker);
    if (markerIndex < 0) {
      return undefined;
    }

    const rawTemplate = signal.slice(markerIndex + marker.length);
    return normalizePageTemplate(rawTemplate);
  }
}
