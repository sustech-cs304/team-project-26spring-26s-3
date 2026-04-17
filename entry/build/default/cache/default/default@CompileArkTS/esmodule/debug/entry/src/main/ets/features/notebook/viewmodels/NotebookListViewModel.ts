import type common from "@ohos:app.ability.common";
import type { Notebook } from '../../../domain/entities/Notebook';
import { CreateNotebook } from "@bundle:com.example.hosn/entry/ets/domain/usecases/CreateNotebook";
import { DeleteNotebook } from "@bundle:com.example.hosn/entry/ets/domain/usecases/DeleteNotebook";
import { GetNotebookList } from "@bundle:com.example.hosn/entry/ets/domain/usecases/GetNotebookList";
import { RenameNotebook } from "@bundle:com.example.hosn/entry/ets/domain/usecases/RenameNotebook";
import { SortNotebookList } from "@bundle:com.example.hosn/entry/ets/domain/usecases/SortNotebookList";
import type { NotebookRepository, NotebookSortType } from '../../../domain/repositories/NotebookRepository';
import { NotebookRepositoryImpl } from "@bundle:com.example.hosn/entry/ets/data/repositories/NotebookRepositoryImpl";
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
        return this.notebookList.slice();
    }
    getCachedNotebookList(): Notebook[] {
        return this.notebookList.slice();
    }
}
