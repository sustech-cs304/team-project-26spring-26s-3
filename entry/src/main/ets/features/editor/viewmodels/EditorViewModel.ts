import common from '@ohos.app.ability.common';
import { Notebook } from '../../../domain/entities/Notebook';
import { NotebookPage } from '../../../domain/entities/NotebookPage';
import { NotebookPageCanvas } from '../../../domain/entities/NotebookPageCanvas';
import { CreateNotebookPage } from '../../../domain/usecases/CreateNotebookPage';
import { DeleteNotebookPage } from '../../../domain/usecases/DeleteNotebookPage';
import { GetNotebookPageCanvas } from '../../../domain/usecases/GetNotebookPageCanvas';
import { GetNotebookPages } from '../../../domain/usecases/GetNotebookPages';
import { ReorderNotebookPages } from '../../../domain/usecases/ReorderNotebookPages';
import { NotebookRepository } from '../../../domain/repositories/NotebookRepository';
import { NotebookRepositoryImpl } from '../../../data/repositories/NotebookRepositoryImpl';

export class EditorViewModel {
  private readonly notebookRepository: NotebookRepository;
  private readonly createNotebookPageUseCase: CreateNotebookPage;
  private readonly deleteNotebookPageUseCase: DeleteNotebookPage;
  private readonly getNotebookPageCanvasUseCase: GetNotebookPageCanvas;
  private readonly getNotebookPagesUseCase: GetNotebookPages;
  private readonly reorderNotebookPagesUseCase: ReorderNotebookPages;
  private notebook: Notebook | null = null;
  private notebookPageList: NotebookPage[] = [];
  private activeNotebookPageCanvas: NotebookPageCanvas | null = null;

  constructor(context: common.Context, notebookRepository?: NotebookRepository) {
    this.notebookRepository = notebookRepository ?? new NotebookRepositoryImpl(context);
    this.createNotebookPageUseCase = new CreateNotebookPage(this.notebookRepository);
    this.deleteNotebookPageUseCase = new DeleteNotebookPage(this.notebookRepository);
    this.getNotebookPageCanvasUseCase = new GetNotebookPageCanvas(this.notebookRepository);
    this.getNotebookPagesUseCase = new GetNotebookPages(this.notebookRepository);
    this.reorderNotebookPagesUseCase = new ReorderNotebookPages(this.notebookRepository);
  }

  async loadNotebook(notebookId: string): Promise<Notebook | null> {
    this.notebook = await this.notebookRepository.getNotebookById(notebookId);
    return this.getCachedNotebook();
  }

  async loadNotebookPages(notebookId: string): Promise<NotebookPage[]> {
    this.notebookPageList = await this.getNotebookPagesUseCase.execute(notebookId);
    return this.getCachedNotebookPages();
  }

  async createNotebookPage(notebookId: string): Promise<NotebookPage | null> {
    const notebookPage: NotebookPage | null = await this.createNotebookPageUseCase.execute({
      notebookId: notebookId
    });

    this.notebook = await this.notebookRepository.getNotebookById(notebookId);
    this.notebookPageList = await this.getNotebookPagesUseCase.execute(notebookId);
    return notebookPage;
  }

  async deleteNotebookPage(notebookId: string, pageId: string): Promise<boolean> {
    const hasDeleted: boolean = await this.deleteNotebookPageUseCase.execute({
      notebookId: notebookId,
      pageId: pageId
    });

    this.notebook = await this.notebookRepository.getNotebookById(notebookId);
    this.notebookPageList = await this.getNotebookPagesUseCase.execute(notebookId);
    return hasDeleted;
  }

  async loadNotebookPageCanvas(notebookId: string, pageId: string): Promise<NotebookPageCanvas | null> {
    this.activeNotebookPageCanvas = await this.getNotebookPageCanvasUseCase.execute({
      notebookId: notebookId,
      pageId: pageId
    });
    return this.getCachedNotebookPageCanvas();
  }

  async reorderNotebookPages(notebookId: string, fromIndex: number, toIndex: number): Promise<boolean> {
    const hasReordered: boolean = await this.reorderNotebookPagesUseCase.execute({
      notebookId: notebookId,
      fromIndex: fromIndex,
      toIndex: toIndex
    });

    this.notebook = await this.notebookRepository.getNotebookById(notebookId);
    this.notebookPageList = await this.getNotebookPagesUseCase.execute(notebookId);
    return hasReordered;
  }

  getCachedNotebook(): Notebook | null {
    if (this.notebook === null) {
      return null;
    }

    return {
      id: this.notebook.id,
      title: this.notebook.title,
      folderId: this.notebook.folderId,
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
