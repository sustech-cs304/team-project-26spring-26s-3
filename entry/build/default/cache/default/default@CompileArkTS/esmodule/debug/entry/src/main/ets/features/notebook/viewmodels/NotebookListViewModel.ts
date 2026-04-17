import type common from "@ohos:app.ability.common";
import type { Notebook } from '../../../domain/entities/Notebook';
import { GetNotebookList } from "@bundle:com.example.hosn/entry/ets/domain/usecases/GetNotebookList";
import type { NotebookRepository } from '../../../domain/repositories/NotebookRepository';
import { NotebookRepositoryImpl } from "@bundle:com.example.hosn/entry/ets/data/repositories/NotebookRepositoryImpl";
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
