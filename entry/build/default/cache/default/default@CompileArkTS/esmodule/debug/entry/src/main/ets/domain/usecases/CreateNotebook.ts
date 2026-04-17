import type { Notebook } from '../entities/Notebook';
import type { CreateNotebookRequest, NotebookRepository } from '../repositories/NotebookRepository';
export class CreateNotebook {
    constructor(private readonly notebookRepository: NotebookRepository) {
    }
    async execute(request: CreateNotebookRequest): Promise<Notebook> {
        return this.notebookRepository.createNotebook(request);
    }
}
