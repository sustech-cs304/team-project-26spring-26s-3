import common from '@ohos.app.ability.common';
import { Notebook } from '../../../domain/entities/Notebook';
import { GetNotebookList } from '../../../domain/usecases/GetNotebookList';
import { NotebookRepository } from '../../../domain/repositories/NotebookRepository';
import { NotebookRepositoryImpl } from '../../../data/repositories/NotebookRepositoryImpl';

export class NotebookListViewModel {
  private readonly notebookRepository: NotebookRepository;
  private readonly getNotebookListUseCase: GetNotebookList;
  private notebookList: Notebook[] = [];

  constructor(context: common.Context, notebookRepository?: NotebookRepository) {
    this.notebookRepository = notebookRepository ?? new NotebookRepositoryImpl(context);
    this.getNotebookListUseCase = new GetNotebookList(this.notebookRepository);
  }

  async loadNotebookList(): Promise<Notebook[]> {
    this.notebookList = await this.getNotebookListUseCase.execute();
    return this.notebookList.slice();
  }

  getCachedNotebookList(): Notebook[] {
    return this.notebookList.slice();
  }
}
