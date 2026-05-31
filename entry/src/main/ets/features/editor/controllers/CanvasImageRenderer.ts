import { CanvasDrawContext } from './CanvasDrawContext';

export class CanvasImageRenderer {
  static drawImage(
    context: CanvasDrawContext,
    uri: string,
    x: number,
    y: number,
    width: number,
    height: number,
    opacity: number = 1
  ): boolean {
    if (width <= 0 || height <= 0) {
      return false;
    }

    const normalizedUri = CanvasImageRenderer.normalizeImageUri(uri);
    if (normalizedUri.length === 0) {
      return false;
    }

    const candidates = CanvasImageRenderer.buildImageSourceCandidates(normalizedUri);
    for (const candidate of candidates) {
      let imageBitmap: ImageBitmap | undefined = undefined;
      let hasSavedContext = false;
      try {
        imageBitmap = new ImageBitmap(candidate);
        context.save();
        hasSavedContext = true;
        context.globalAlpha = Math.max(0, Math.min(1, opacity));
        context.drawImage(imageBitmap, x, y, width, height);
        context.restore();
        hasSavedContext = false;
        return true;
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

    return false;
  }

  static hasImageSource(uri: string): boolean {
    return CanvasImageRenderer.normalizeImageUri(uri).length > 0;
  }

  private static normalizeImageUri(uri: string): string {
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
    CanvasImageRenderer.appendImageSourceCandidate(candidates, uri);
    const decodedUri = CanvasImageRenderer.decodeUriSegment(uri);
    if (decodedUri !== uri) {
      CanvasImageRenderer.appendImageSourceCandidate(candidates, decodedUri);
    }

    if (uri.startsWith('file://')) {
      const rawLocalPath = uri.substring('file://'.length);
      CanvasImageRenderer.appendImageSourceCandidate(candidates, rawLocalPath);
      if (!rawLocalPath.startsWith('/')) {
        CanvasImageRenderer.appendImageSourceCandidate(candidates, `/${rawLocalPath}`);
      }
      const decodedLocalPath = CanvasImageRenderer.decodeUriSegment(rawLocalPath);
      if (decodedLocalPath !== rawLocalPath) {
        CanvasImageRenderer.appendImageSourceCandidate(candidates, decodedLocalPath);
        if (!decodedLocalPath.startsWith('/')) {
          CanvasImageRenderer.appendImageSourceCandidate(candidates, `/${decodedLocalPath}`);
        }
      }
    }

    if (decodedUri.startsWith('file://')) {
      const decodedSchemePath = decodedUri.substring('file://'.length);
      CanvasImageRenderer.appendImageSourceCandidate(candidates, decodedSchemePath);
      if (!decodedSchemePath.startsWith('/')) {
        CanvasImageRenderer.appendImageSourceCandidate(candidates, `/${decodedSchemePath}`);
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

  private static decodeUriSegment(text: string): string {
    try {
      return decodeURIComponent(text);
    } catch (_error) {
      return text;
    }
  }
}
