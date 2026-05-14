import common from '@ohos.app.ability.common';

import { Notebook } from '../../../domain/entities/Notebook';
import { NotebookPage } from '../../../domain/entities/NotebookPage';
import { NotebookPageCanvas } from '../../../domain/entities/NotebookPageCanvas';
import { NotebookRepository } from '../../../domain/repositories/NotebookRepository';
import { NotebookRepositoryImpl } from '../../../data/repositories/NotebookRepositoryImpl';

export class NotebookEditorViewModel {
  private readonly notebookRepository: NotebookRepository;
  private notebook: Notebook | null = null;
  private notebookPageList: NotebookPage[] = [];
  private activeNotebookPageCanvas: NotebookPageCanvas | null = null;

  constructor(context: common.Context, notebookRepository?: NotebookRepository) {
    this.notebookRepository = notebookRepository ?? new NotebookRepositoryImpl(context);
  }

  async loadNotebook(notebookId: string): Promise<Notebook | null> {
    this.notebook = await this.notebookRepository.getNotebookById(notebookId);
    return this.getCachedNotebook();
  }

  async loadNotebookPages(notebookId: string): Promise<NotebookPage[]> {
    this.notebookPageList = await this.notebookRepository.getNotebookPages(notebookId);
    return this.getCachedNotebookPages();
  }

  async createNotebookPage(notebookId: string): Promise<NotebookPage | null> {
    const notebookPage = await this.notebookRepository.createNotebookPage({ notebookId });
    this.notebook = await this.notebookRepository.getNotebookById(notebookId);
    this.notebookPageList = await this.notebookRepository.getNotebookPages(notebookId);
    return notebookPage;
  }

  async deleteNotebookPage(notebookId: string, pageId: string): Promise<boolean> {
    const hasDeleted = await this.notebookRepository.deleteNotebookPage({ notebookId, pageId });
    this.notebook = await this.notebookRepository.getNotebookById(notebookId);
    this.notebookPageList = await this.notebookRepository.getNotebookPages(notebookId);
    return hasDeleted;
  }

  async loadNotebookPageCanvas(notebookId: string, pageId: string): Promise<NotebookPageCanvas | null> {
    this.activeNotebookPageCanvas = await this.notebookRepository.getNotebookPageCanvas({ notebookId, pageId });
    return this.getCachedNotebookPageCanvas();
  }

  async reorderNotebookPages(notebookId: string, fromIndex: number, toIndex: number): Promise<boolean> {
    const hasReordered = await this.notebookRepository.reorderNotebookPages({ notebookId, fromIndex, toIndex });
    this.notebook = await this.notebookRepository.getNotebookById(notebookId);
    this.notebookPageList = await this.notebookRepository.getNotebookPages(notebookId);
    return hasReordered;
  }

  getCachedNotebook(): Notebook | null {
    if (this.notebook === null) {
      return null;
    }

    return {
      id: this.notebook.id,
      title: this.notebook.title,
      createdAt: this.notebook.createdAt,
      updatedAt: this.notebook.updatedAt
    };
  }

  getCachedNotebookPages(): NotebookPage[] {
    return this.notebookPageList.map((page: NotebookPage): NotebookPage => {
      return {
        id: page.id,
        notebookId: page.notebookId,
        order: page.order,
        createdAt: page.createdAt,
        updatedAt: page.updatedAt,
        templateType: page.templateType
      };
    });
  }

  getCachedNotebookPageCanvas(): NotebookPageCanvas | null {
    if (this.activeNotebookPageCanvas === null) {
      return null;
    }

    return {
      pageId: this.activeNotebookPageCanvas.pageId,
      notebookId: this.activeNotebookPageCanvas.notebookId,
      width: this.activeNotebookPageCanvas.width,
      height: this.activeNotebookPageCanvas.height,
      backgroundColor: this.activeNotebookPageCanvas.backgroundColor,
      createdAt: this.activeNotebookPageCanvas.createdAt,
      updatedAt: this.activeNotebookPageCanvas.updatedAt
    };
  }
}
