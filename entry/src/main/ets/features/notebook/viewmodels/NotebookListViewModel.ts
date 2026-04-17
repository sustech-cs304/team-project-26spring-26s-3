import common from '@ohos.app.ability.common';
import { Notebook } from '../../../domain/entities/Notebook';
import { CreateNotebook } from '../../../domain/usecases/CreateNotebook';
import { GetNotebookList } from '../../../domain/usecases/GetNotebookList';
import { SortNotebookList } from '../../../domain/usecases/SortNotebookList';
import { NotebookRepository, NotebookSortType } from '../../../domain/repositories/NotebookRepository';
import { NotebookRepositoryImpl } from '../../../data/repositories/NotebookRepositoryImpl';

export class NotebookListViewModel {
  private readonly notebookRepository: NotebookRepository;
  private readonly createNotebookUseCase: CreateNotebook;
  private readonly getNotebookListUseCase: GetNotebookList;
  private readonly sortNotebookListUseCase: SortNotebookList;
  private notebookList: Notebook[] = [];

  constructor(context: common.Context, notebookRepository?: NotebookRepository) {
    this.notebookRepository = notebookRepository ?? new NotebookRepositoryImpl(context);
    this.createNotebookUseCase = new CreateNotebook(this.notebookRepository);
    this.getNotebookListUseCase = new GetNotebookList(this.notebookRepository);
    this.sortNotebookListUseCase = new SortNotebookList(this.notebookRepository);
  }

  async loadNotebookList(): Promise<Notebook[]> {
    this.notebookList = await this.getNotebookListUseCase.execute();
    return this.notebookList.slice();
  }

  async loadSortType(): Promise<NotebookSortType> {
    return this.notebookRepository.getSortType();
  }

  async createNotebook(title: string): Promise<Notebook> {
    const notebook: Notebook = await this.createNotebookUseCase.execute({ title: title });
    this.notebookList = await this.getNotebookListUseCase.execute();
    return notebook;
  }

  async changeSortType(sortType: NotebookSortType): Promise<Notebook[]> {
    this.notebookList = await this.sortNotebookListUseCase.execute(sortType);
    return this.notebookList.slice();
  }

  getCachedNotebookList(): Notebook[] {
    return this.notebookList.slice();
  }
}
