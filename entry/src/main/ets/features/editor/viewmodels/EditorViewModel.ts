import common from '@ohos.app.ability.common';
import { Notebook } from '../../../domain/entities/Notebook';
import { NotebookPage } from '../../../domain/entities/NotebookPage';
import { CreateNotebookPage } from '../../../domain/usecases/CreateNotebookPage';
import { GetNotebookPages } from '../../../domain/usecases/GetNotebookPages';
import { NotebookRepository } from '../../../domain/repositories/NotebookRepository';
import { NotebookRepositoryImpl } from '../../../data/repositories/NotebookRepositoryImpl';

export class EditorViewModel {
  private readonly notebookRepository: NotebookRepository;
  private readonly createNotebookPageUseCase: CreateNotebookPage;
  private readonly getNotebookPagesUseCase: GetNotebookPages;
  private notebook: Notebook | null = null;
  private notebookPageList: NotebookPage[] = [];

  constructor(context: common.Context, notebookRepository?: NotebookRepository) {
    this.notebookRepository = notebookRepository ?? new NotebookRepositoryImpl(context);
    this.createNotebookPageUseCase = new CreateNotebookPage(this.notebookRepository);
    this.getNotebookPagesUseCase = new GetNotebookPages(this.notebookRepository);
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
}
