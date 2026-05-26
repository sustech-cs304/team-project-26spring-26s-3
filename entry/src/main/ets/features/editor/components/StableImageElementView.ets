import { ImageCanvasElement } from '../../../domain/entities/CanvasElement';

const DEFAULT_IMAGE_ELEMENT: ImageCanvasElement = {
  id: '',
  pageId: '',
  type: 'image',
  x: 0,
  y: 0,
  width: 1,
  height: 1,
  rotation: 0,
  zIndex: 0,
  createdAt: 0,
  updatedAt: 0,
  uri: '',
  originalWidth: 1,
  originalHeight: 1,
  opacity: 1,
  outline: {
    lineStyle: 'none',
    color: '#111827',
    width: 0
  }
};

@Component
export struct StableImageElementView {
  @Prop element: ImageCanvasElement = DEFAULT_IMAGE_ELEMENT;
  @Prop contentReadyToken: number = 0;
  @Prop reportContentReady: boolean = false;
  @State private reportedContentReadyElementId: string = '';
  @State private reportedContentReadyToken: number = 0;
  onContentReady: (elementId: string, token: number) => void =
    (_elementId: string, _token: number): void => {};

  build() {
    Stack() {
      ForEach(
        this.buildImageSourceCandidates(this.element.uri),
        (candidate: string) => {
          Image(candidate)
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Fill)
            .opacity(this.element.opacity)
            .hitTestBehavior(HitTestMode.None)
            .onComplete(() => {
              this.reportContentReadyOnce();
            })
        },
        (candidate: string): string => candidate
      )
    }
    .width(this.element.width)
    .height(this.element.height)
    .position({
      x: this.element.x,
      y: this.element.y
    })
    .border({
      width: this.getImageOutlineWidth(),
      color: this.element.outline.color,
      style: this.getImageOutlineBorderStyle()
    })
    .zIndex(this.element.zIndex)
    .hitTestBehavior(HitTestMode.None)
  }

  private getImageOutlineWidth(): number {
    return this.element.outline.lineStyle === 'none' ? 0 : Math.max(0, this.element.outline.width);
  }

  private getImageOutlineBorderStyle(): BorderStyle {
    if (this.element.outline.lineStyle === 'dashed') {
      return BorderStyle.Dashed;
    }

    if (this.element.outline.lineStyle === 'dotted') {
      return BorderStyle.Dotted;
    }

    return BorderStyle.Solid;
  }

  private reportContentReadyOnce(): void {
    if (!this.reportContentReady || this.contentReadyToken <= 0) {
      return;
    }

    if (this.reportedContentReadyElementId === this.element.id &&
      this.reportedContentReadyToken === this.contentReadyToken) {
      return;
    }

    this.reportedContentReadyElementId = this.element.id;
    this.reportedContentReadyToken = this.contentReadyToken;
    this.onContentReady(this.element.id, this.contentReadyToken);
  }

  private buildImageSourceCandidates(path: string): string[] {
    const candidates: string[] = [];
    this.appendImageSourceCandidate(candidates, this.toImageSourceUri(path));
    const decodedPath: string = this.decodeUriSegment(path);
    if (decodedPath !== path) {
      this.appendImageSourceCandidate(candidates, this.toImageSourceUri(decodedPath));
    }

    if (path.startsWith('file://')) {
      const rawLocalPath: string = path.substring('file://'.length);
      this.appendImageSourceCandidate(candidates, this.toImageSourceUri(rawLocalPath));
      const decodedLocalPath: string = this.decodeUriSegment(rawLocalPath);
      if (decodedLocalPath !== rawLocalPath) {
        this.appendImageSourceCandidate(candidates, this.toImageSourceUri(decodedLocalPath));
      }
    }

    if (decodedPath.startsWith('file://')) {
      const decodedSchemePath: string = decodedPath.substring('file://'.length);
      this.appendImageSourceCandidate(candidates, this.toImageSourceUri(decodedSchemePath));
    }

    return candidates;
  }

  private appendImageSourceCandidate(candidates: string[], candidate: string): void {
    if (candidate.length === 0 || candidates.includes(candidate)) {
      return;
    }
    candidates.push(candidate);
  }

  private toImageSourceUri(path: string): string {
    const normalizedPath: string = path.trim();
    if (normalizedPath.length === 0) {
      return '';
    }
    if (normalizedPath.startsWith('file://')) {
      if (normalizedPath.startsWith('file:///')) {
        return normalizedPath;
      }
      const rawLocalPath: string = normalizedPath.substring('file://'.length);
      return rawLocalPath.startsWith('/') ? `file://${rawLocalPath}` : `file:///${rawLocalPath}`;
    }

    if (normalizedPath.startsWith('http://') || normalizedPath.startsWith('https://')) {
      return normalizedPath;
    }

    return normalizedPath.startsWith('/') ? `file://${normalizedPath}` : `file:///${normalizedPath}`;
  }

  private decodeUriSegment(text: string): string {
    try {
      return decodeURIComponent(text);
    } catch (_error) {
      return text;
    }
  }
}
