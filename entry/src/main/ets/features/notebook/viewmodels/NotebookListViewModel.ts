import common from '@ohos.app.ability.common';
import { Notebook } from '../../../domain/entities/Notebook';
import { CreateNotebook } from '../../../domain/usecases/CreateNotebook';
import { DeleteNotebook } from '../../../domain/usecases/DeleteNotebook';
import { GetNotebookList } from '../../../domain/usecases/GetNotebookList';
import { RenameNotebook } from '../../../domain/usecases/RenameNotebook';
import { SortNotebookList } from '../../../domain/usecases/SortNotebookList';
import { NotebookRepository, NotebookSortType } from '../../../domain/repositories/NotebookRepository';
import { NotebookRepositoryImpl } from '../../../data/repositories/NotebookRepositoryImpl';

export class NotebookListViewModel {
  private readonly notebookRepository: NotebookRepository;
  private readonly createNotebookUseCase: CreateNotebook;
  private readonly deleteNotebookUseCase: DeleteNotebook;
  private readonly getNotebookListUseCase: GetNotebookList;
  private readonly renameNotebookUseCase: RenameNotebook;
  private readonly sortNotebookListUseCase: SortNotebookList;
  private notebookList: Notebook[] = [];

  constructor(context: common.Context, notebookRepository?: NotebookRepository) {
    this.notebookRepository = notebookRepository ?? new NotebookRepositoryImpl(context);
    this.createNotebookUseCase = new CreateNotebook(this.notebookRepository);
    this.deleteNotebookUseCase = new DeleteNotebook(this.notebookRepository);
    this.getNotebookListUseCase = new GetNotebookList(this.notebookRepository);
    this.renameNotebookUseCase = new RenameNotebook(this.notebookRepository);
    this.sortNotebookListUseCase = new SortNotebookList(this.notebookRepository);
  }

  async loadNotebookList(): Promise<Notebook[]> {
    this.notebookList = await this.getNotebookListUseCase.execute();
    return this.cloneNotebookList(this.notebookList);
  }

  async loadSortType(): Promise<NotebookSortType> {
    return this.notebookRepository.getSortType();
  }

  async createNotebook(title: string): Promise<Notebook> {
    const notebook: Notebook = await this.createNotebookUseCase.execute({ title: title });
    this.notebookList = await this.getNotebookListUseCase.execute();
    return notebook;
  }

  async renameNotebook(notebookId: string, title: string): Promise<Notebook | null> {
    const notebook: Notebook | null = await this.renameNotebookUseCase.execute({
      notebookId: notebookId,
      title: title
    });
    this.notebookList = await this.getNotebookListUseCase.execute();
    return notebook;
  }

  async deleteNotebook(notebookId: string): Promise<boolean> {
    const hasDeleted: boolean = await this.deleteNotebookUseCase.execute(notebookId);
    this.notebookList = await this.getNotebookListUseCase.execute();
    return hasDeleted;
  }

  async changeSortType(sortType: NotebookSortType): Promise<Notebook[]> {
    this.notebookList = await this.sortNotebookListUseCase.execute(sortType);
    return this.cloneNotebookList(this.notebookList);
  }

  getCachedNotebookList(): Notebook[] {
    return this.cloneNotebookList(this.notebookList);
  }

  private cloneNotebookList(notebookList: Notebook[]): Notebook[] {
    const clonedNotebookList: Notebook[] = [];
    for (const notebook of notebookList) {
      clonedNotebookList.push({
        id: notebook.id,
        title: notebook.title,
        createdAt: notebook.createdAt,
        updatedAt: notebook.updatedAt
      });
    }
    return clonedNotebookList;
  }
}
