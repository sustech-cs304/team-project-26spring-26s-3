import common from '@ohos.app.ability.common';

import { CanvasElement, PageCanvasContent } from '../../../domain/entities/CanvasElement';
import { NotebookPageTemplateType } from '../../../domain/entities/NotebookPage';
import { Stroke } from '../../../domain/entities/Stroke';
import { EditorRepositoryImpl } from '../../../data/repositories/EditorRepositoryImpl';
import {
  createEmptyPageThumbnailRenderSnapshot,
  PageThumbnailRenderSnapshot
} from '../controllers/PageThumbnailRenderer';
import { DrawingEditorViewModel } from './DrawingEditorViewModel';

export interface PageThumbnailSnapshotRequest {
  pageId: string;
  templateType: NotebookPageTemplateType;
  paperBackgroundColor: string;
  backgroundImageUri: string;
  canvasWidth: number;
  canvasHeight: number;
  activeSession: DrawingEditorViewModel | null;
}

interface CachedPageThumbnailContent {
  revision: number;
  strokes: Stroke[];
  elements: CanvasElement[];
}

export class PageThumbnailStore {
  private readonly repository: EditorRepositoryImpl;
  private readonly contentByPageId: Map<string, CachedPageThumbnailContent> =
    new Map<string, CachedPageThumbnailContent>();
  private readonly loadingPageIds: Set<string> = new Set<string>();
  private nextRevision: number = 1;

  constructor(context: common.Context) {
    this.repository = new EditorRepositoryImpl(context);
  }

  async ensurePageContent(pageId: string): Promise<boolean> {
    if (pageId.length === 0 || this.contentByPageId.has(pageId) || this.loadingPageIds.has(pageId)) {
      return false;
    }

    this.loadingPageIds.add(pageId);
    try {
      const pageContent: PageCanvasContent = await this.repository.getPageContent(pageId);
      this.replacePageContent(pageId, pageContent.strokes, pageContent.elements);
      return true;
    } catch (_error) {
      this.replacePageContent(pageId, [], []);
      return true;
    } finally {
      this.loadingPageIds.delete(pageId);
    }
  }

  captureSession(pageId: string, session: DrawingEditorViewModel | null): boolean {
    if (pageId.length === 0 || session === null) {
      return false;
    }

    this.replacePageContent(pageId, session.getStrokesForRendering(), session.getElementsForRendering());
    return true;
  }

  retainPages(pageIds: string[]): void {
    const retainedPageIds = new Set<string>(pageIds);
    const cachedPageIds: string[] = Array.from(this.contentByPageId.keys());

    for (const pageId of cachedPageIds) {
      if (!retainedPageIds.has(pageId)) {
        this.contentByPageId.delete(pageId);
      }
    }
  }

  buildSnapshot(request: PageThumbnailSnapshotRequest): PageThumbnailRenderSnapshot {
    if (request.pageId.length === 0) {
      return createEmptyPageThumbnailRenderSnapshot();
    }

    const cachedContent = this.contentByPageId.get(request.pageId);
    const hasActiveSession = request.activeSession !== null &&
      request.activeSession.isLoadedForPage(request.pageId);
    const strokes = hasActiveSession
      ? (request.activeSession as DrawingEditorViewModel).getStrokesForRendering()
      : (cachedContent === undefined ? [] : cachedContent.strokes);
    const elements = hasActiveSession
      ? (request.activeSession as DrawingEditorViewModel).getElementsForRendering()
      : (cachedContent === undefined ? [] : cachedContent.elements);
    const activeStroke = hasActiveSession
      ? (request.activeSession as DrawingEditorViewModel).getActiveStrokeForRendering()
      : null;
    const contentVersion = cachedContent === undefined ? 0 : cachedContent.revision;

    return {
      pageId: request.pageId,
      templateType: request.templateType,
      paperBackgroundColor: request.paperBackgroundColor,
      backgroundImageUri: request.backgroundImageUri,
      canvasWidth: request.canvasWidth,
      canvasHeight: request.canvasHeight,
      contentVersion,
      activeStrokeVersion: this.getActiveStrokeVersion(activeStroke),
      isLoading: this.loadingPageIds.has(request.pageId),
      strokes,
      elements,
      activeStroke
    };
  }

  private replacePageContent(pageId: string, strokes: Stroke[], elements: CanvasElement[]): void {
    this.contentByPageId.set(pageId, {
      revision: this.allocateRevision(),
      strokes,
      elements
    });
  }

  private allocateRevision(): number {
    const revision = this.nextRevision;
    this.nextRevision += 1;
    return revision;
  }

  private getActiveStrokeVersion(activeStroke: Stroke | null): string {
    if (activeStroke === null) {
      return '';
    }

    return `${activeStroke.id}:${activeStroke.points.length}:${activeStroke.updatedAt}`;
  }
}
