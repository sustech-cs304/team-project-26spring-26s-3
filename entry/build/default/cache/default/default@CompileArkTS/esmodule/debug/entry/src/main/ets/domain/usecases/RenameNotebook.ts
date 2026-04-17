import type { Notebook } from '../entities/Notebook';
import type { NotebookRepository, RenameNotebookRequest } from '../repositories/NotebookRepository';
export class RenameNotebook {
    constructor(private readonly notebookRepository: NotebookRepository) {
    }
    async execute(request: RenameNotebookRequest): Promise<Notebook | null> {
        return this.notebookRepository.renameNotebook(request);
    }
}
