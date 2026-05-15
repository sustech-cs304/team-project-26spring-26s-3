import { StrokePoint } from '../../../domain/entities/Stroke';
import {
  SELECTION_DASH_GAP,
  SELECTION_DASH_LENGTH,
  SELECTION_DASH_WIDTH,
  SelectionDashRenderer
} from '../controllers/SelectionDashRenderer';
import { SelectedStrokeGroup } from '../viewmodels/DrawingEditorViewModel';

const DASH_ANIMATION_INTERVAL_MS = 64;
const DASH_ANIMATION_STEP = 2.5;
const ANIMATED_SELECTION_POINT_LIMIT = 1400;
const SELECTION_DIRTY_PADDING = 18;

interface SelectionDirtyRect {
  minX: number;
  minY: number;
  maxX: number;
  maxY: number;
}

@Component
export struct StrokeSelectionOverlay {
  @Watch('onGroupsChanged')
  @Prop groups: SelectedStrokeGroup[] = [];
  @Watch('onGroupsChanged')
  @Prop refreshVersion: number = 0;
  @Watch('onPausedChanged')
  @Prop paused: boolean = false;

  @State private isCanvasReady: boolean = false;
  private dashOffset: number = 0;
  private animationTimerId: number = -1;
  private outlinePointCount: number = 0;
  private lastDirtyRect: SelectionDirtyRect | null = null;
  private lastCanvasWidth: number = 0;
  private lastCanvasHeight: number = 0;
  private shouldClearFullCanvasOnNextRedraw: boolean = false;
  private readonly renderingSettings: RenderingContextSettings = new RenderingContextSettings(true);
  private readonly selectionContext: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.renderingSettings);

  aboutToAppear(): void {
    this.outlinePointCount = this.getOutlinePointCount();
    this.startAnimation();
  }

  aboutToDisappear(): void {
    this.stopAnimation();
  }

  build() {
    Canvas(this.selectionContext)
      .width('100%')
      .height('100%')
      .backgroundColor('#00000000')
      .onReady(() => {
        this.isCanvasReady = true;
        this.redrawSelection();
      })
      .hitTestBehavior(HitTestMode.None)
  }

  private onGroupsChanged(): void {
    this.outlinePointCount = this.getOutlinePointCount();
    if (this.paused) {
      this.shouldClearFullCanvasOnNextRedraw = true;
    }
    this.redrawSelection();
    if (this.canAnimateSelection()) {
      this.startAnimation();
    } else {
      this.stopAnimation();
    }
  }

  private onPausedChanged(): void {
    this.shouldClearFullCanvasOnNextRedraw = true;
    if (this.paused) {
      this.stopAnimation();
      this.redrawSelection();
      return;
    }

    this.redrawSelection();
    if (this.canAnimateSelection()) {
      this.startAnimation();
    }
  }

  private startAnimation(): void {
    if (this.animationTimerId >= 0 || !this.canAnimateSelection()) {
      return;
    }

    this.animationTimerId = setInterval(() => {
      this.dashOffset = (this.dashOffset + DASH_ANIMATION_STEP) % (SELECTION_DASH_LENGTH + SELECTION_DASH_GAP);
      this.redrawSelection();
    }, DASH_ANIMATION_INTERVAL_MS);
  }

  private stopAnimation(): void {
    if (this.animationTimerId < 0) {
      return;
    }

    clearInterval(this.animationTimerId);
    this.animationTimerId = -1;
  }

  private canAnimateSelection(): boolean {
    return this.groups.length > 0 && !this.paused && this.outlinePointCount <= ANIMATED_SELECTION_POINT_LIMIT;
  }

  private redrawSelection(): void {
    if (!this.isCanvasReady) {
      return;
    }

    const width = this.selectionContext.width;
    const height = this.selectionContext.height;
    const currentDirtyRect = this.getCurrentDirtyRect();
    const shouldClearFullCanvas = this.shouldClearFullCanvasOnNextRedraw ||
      width !== this.lastCanvasWidth || height !== this.lastCanvasHeight;
    if (shouldClearFullCanvas) {
      this.selectionContext.clearRect(0, 0, width, height);
      this.lastDirtyRect = null;
      this.shouldClearFullCanvasOnNextRedraw = false;
    } else {
      this.clearDirtyRect(this.mergeDirtyRects(this.lastDirtyRect, currentDirtyRect), width, height);
    }

    this.lastCanvasWidth = width;
    this.lastCanvasHeight = height;
    if (this.groups.length === 0) {
      this.lastDirtyRect = null;
      return;
    }

    for (const group of this.groups) {
      const outline = group.outline.length > 0 ? group.outline : this.buildBoundsOutline(group);
      SelectionDashRenderer.drawPath(this.selectionContext, outline, true, this.dashOffset);
    }

    this.lastDirtyRect = currentDirtyRect;
  }

  private getOutlinePointCount(): number {
    let pointCount = 0;
    for (const group of this.groups) {
      pointCount += group.outline.length > 0 ? group.outline.length : 4;
    }

    return pointCount;
  }

  private buildBoundsOutline(group: SelectedStrokeGroup): StrokePoint[] {
    return [
      { x: group.bounds.minX, y: group.bounds.minY, t: 0 },
      { x: group.bounds.maxX, y: group.bounds.minY, t: 0 },
      { x: group.bounds.maxX, y: group.bounds.maxY, t: 0 },
      { x: group.bounds.minX, y: group.bounds.maxY, t: 0 }
    ];
  }

  private getCurrentDirtyRect(): SelectionDirtyRect | null {
    let dirtyRect: SelectionDirtyRect | null = null;
    for (const group of this.groups) {
      const groupRect = this.expandDirtyRect({
        minX: group.bounds.minX,
        minY: group.bounds.minY,
        maxX: group.bounds.maxX,
        maxY: group.bounds.maxY
      }, Math.max(SELECTION_DIRTY_PADDING, SELECTION_DASH_WIDTH * 4));
      dirtyRect = this.mergeDirtyRects(dirtyRect, groupRect);
    }

    return dirtyRect;
  }

  private clearDirtyRect(rect: SelectionDirtyRect | null, canvasWidth: number, canvasHeight: number): void {
    if (rect === null) {
      return;
    }

    const minX = Math.max(0, Math.floor(rect.minX));
    const minY = Math.max(0, Math.floor(rect.minY));
    const maxX = Math.min(canvasWidth, Math.ceil(rect.maxX));
    const maxY = Math.min(canvasHeight, Math.ceil(rect.maxY));
    if (maxX <= minX || maxY <= minY) {
      return;
    }

    this.selectionContext.clearRect(minX, minY, maxX - minX, maxY - minY);
  }

  private expandDirtyRect(rect: SelectionDirtyRect, padding: number): SelectionDirtyRect {
    return {
      minX: rect.minX - padding,
      minY: rect.minY - padding,
      maxX: rect.maxX + padding,
      maxY: rect.maxY + padding
    };
  }

  private mergeDirtyRects(left: SelectionDirtyRect | null, right: SelectionDirtyRect | null): SelectionDirtyRect | null {
    if (left === null) {
      return right;
    }
    if (right === null) {
      return left;
    }

    return {
      minX: Math.min(left.minX, right.minX),
      minY: Math.min(left.minY, right.minY),
      maxX: Math.max(left.maxX, right.maxX),
      maxY: Math.max(left.maxY, right.maxY)
    };
  }
}
