import type { Notebook } from '../entities/Notebook';
import type { NotebookRepository, NotebookSortType } from '../repositories/NotebookRepository';
export class SortNotebookList {
    constructor(private readonly notebookRepository: NotebookRepository) {
    }
    async execute(sortType: NotebookSortType): Promise<Notebook[]> {
        await this.notebookRepository.saveSortType(sortType);
        return this.notebookRepository.getNotebookList();
    }
}
