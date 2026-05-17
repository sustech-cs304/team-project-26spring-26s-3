import {
  createEmptyPageThumbnailRenderSnapshot,
  PageThumbnailRenderer,
  PageThumbnailRenderSnapshot
} from '../controllers/PageThumbnailRenderer';

@Component
export struct PageThumbnailCanvas {
  @Watch('onRenderInputChanged')
  @Prop snapshot: PageThumbnailRenderSnapshot = createEmptyPageThumbnailRenderSnapshot();
  @Watch('onRenderInputChanged')
  @Prop renderTick: number = 0;
  onNeedSnapshot: (pageId: string) => void = (_pageId: string): void => {};

  @State private isCanvasReady: boolean = false;
  private readonly renderingSettings: RenderingContextSettings = new RenderingContextSettings(true);
  private readonly thumbnailContext: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.renderingSettings);
  private lastRenderKey: string = '';
  private lastRequestedPageId: string = '';

  aboutToAppear(): void {
    this.requestSnapshotIfNeeded();
  }

  build() {
    Canvas(this.thumbnailContext)
      .width('100%')
      .height('100%')
      .backgroundColor(this.snapshot.paperBackgroundColor)
      .onReady(() => {
        this.isCanvasReady = true;
        this.requestSnapshotIfNeeded();
        this.renderIfNeeded(true);
      })
  }

  private onRenderInputChanged(): void {
    this.requestSnapshotIfNeeded();
    this.renderIfNeeded(false);
  }

  private requestSnapshotIfNeeded(): void {
    if (this.snapshot.pageId.length === 0 || this.snapshot.isLoading) {
      return;
    }

    if (this.snapshot.contentVersion > 0 || this.lastRequestedPageId === this.snapshot.pageId) {
      return;
    }

    this.lastRequestedPageId = this.snapshot.pageId;
    this.onNeedSnapshot(this.snapshot.pageId);
  }

  private renderIfNeeded(force: boolean): void {
    if (!this.isCanvasReady) {
      return;
    }

    const viewportSize = PageThumbnailRenderer.getViewportSize(this.thumbnailContext);
    const renderKey = PageThumbnailRenderer.buildRenderKey(this.snapshot, viewportSize);
    if (!force && renderKey === this.lastRenderKey) {
      return;
    }

    this.lastRenderKey = renderKey;
    PageThumbnailRenderer.draw(this.thumbnailContext, this.snapshot, viewportSize);
  }
}
