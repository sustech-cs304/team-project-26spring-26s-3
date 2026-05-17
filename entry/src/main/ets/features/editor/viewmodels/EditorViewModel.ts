import common from '@ohos.app.ability.common';
import { Notebook } from '../../../domain/entities/Notebook';
import { NotebookPage, NotebookPageTemplateType } from '../../../domain/entities/NotebookPage';
import { NotebookPageCanvas } from '../../../domain/entities/NotebookPageCanvas';
import { CreateNotebookPage } from '../../../domain/usecases/CreateNotebookPage';
import { DeleteNotebookPage } from '../../../domain/usecases/DeleteNotebookPage';
import { GetNotebookPageCanvas } from '../../../domain/usecases/GetNotebookPageCanvas';
import { GetNotebookPages } from '../../../domain/usecases/GetNotebookPages';
import { ReorderNotebookPages } from '../../../domain/usecases/ReorderNotebookPages';
import { UpdateNotebookPageCanvas } from '../../../domain/usecases/UpdateNotebookPageCanvas';
import { UpdateNotebookPageTemplate } from '../../../domain/usecases/UpdateNotebookPageTemplate';
import { NotebookRepository } from '../../../domain/repositories/NotebookRepository';
import { NotebookRepositoryImpl } from '../../../data/repositories/NotebookRepositoryImpl';

export class EditorViewModel {
  private readonly notebookRepository: NotebookRepository;
  private readonly createNotebookPageUseCase: CreateNotebookPage;
  private readonly deleteNotebookPageUseCase: DeleteNotebookPage;
  private readonly getNotebookPageCanvasUseCase: GetNotebookPageCanvas;
  private readonly getNotebookPagesUseCase: GetNotebookPages;
  private readonly reorderNotebookPagesUseCase: ReorderNotebookPages;
  private readonly updateNotebookPageCanvasUseCase: UpdateNotebookPageCanvas;
  private readonly updateNotebookPageTemplateUseCase: UpdateNotebookPageTemplate;
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
    this.updateNotebookPageCanvasUseCase = new UpdateNotebookPageCanvas(this.notebookRepository);
    this.updateNotebookPageTemplateUseCase = new UpdateNotebookPageTemplate(this.notebookRepository);
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

  async loadNotebookPageCanvases(notebookId: string, pageIds: string[]): Promise<NotebookPageCanvas[]> {
    const notebookPageCanvasList: NotebookPageCanvas[] = [];
    for (const pageId of pageIds) {
      const notebookPageCanvas: NotebookPageCanvas | null = await this.getNotebookPageCanvasUseCase.execute({
        notebookId: notebookId,
        pageId: pageId
      });

      if (notebookPageCanvas !== null) {
        notebookPageCanvasList.push(this.cloneNotebookPageCanvas(notebookPageCanvas));
      }
    }

    return notebookPageCanvasList;
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

  async updateNotebookPageTemplate(
    notebookId: string,
    pageId: string,
    templateType: NotebookPageTemplateType
  ): Promise<NotebookPage | null> {
    const updatedNotebookPage: NotebookPage | null = await this.updateNotebookPageTemplateUseCase.execute({
      notebookId: notebookId,
      pageId: pageId,
      templateType: templateType
    });

    this.notebook = await this.notebookRepository.getNotebookById(notebookId);
    this.notebookPageList = await this.getNotebookPagesUseCase.execute(notebookId);
    return updatedNotebookPage;
  }

  async updateNotebookPageCanvas(
    notebookId: string,
    pageId: string,
    width: number,
    height: number
  ): Promise<NotebookPageCanvas | null> {
    this.activeNotebookPageCanvas = await this.updateNotebookPageCanvasUseCase.execute({
      notebookId: notebookId,
      pageId: pageId,
      width: width,
      height: height
    });

    this.notebook = await this.notebookRepository.getNotebookById(notebookId);
    this.notebookPageList = await this.getNotebookPagesUseCase.execute(notebookId);
    return this.getCachedNotebookPageCanvas();
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
      updatedAt: this.notebook.updatedAt,
      coverColor: this.notebook.coverColor,
      coverImageUri: this.notebook.coverImageUri,
      pageCount: this.notebook.pageCount,
      isFavorite: this.notebook.isFavorite,
      tags: Array.isArray(this.notebook.tags) ? this.notebook.tags.slice() : [],
      isDeleted: this.notebook.isDeleted,
      deletedAt: this.notebook.deletedAt,
      lastOpenedAt: this.notebook.lastOpenedAt
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
        templateType: page.templateType,
        sourceFileUri: page.sourceFileUri,
        sourceFileType: page.sourceFileType
      };
    });
  }

  getCachedNotebookPageCanvas(): NotebookPageCanvas | null {
    if (this.activeNotebookPageCanvas === null) {
      return null;
    }

    return this.cloneNotebookPageCanvas(this.activeNotebookPageCanvas);
  }

  private cloneNotebookPageCanvas(notebookPageCanvas: NotebookPageCanvas): NotebookPageCanvas {
    return {
      pageId: notebookPageCanvas.pageId,
      notebookId: notebookPageCanvas.notebookId,
      width: notebookPageCanvas.width,
      height: notebookPageCanvas.height,
      backgroundColor: notebookPageCanvas.backgroundColor,
      backgroundImageUri: notebookPageCanvas.backgroundImageUri,
      createdAt: notebookPageCanvas.createdAt,
      updatedAt: notebookPageCanvas.updatedAt
    };
  }
}
