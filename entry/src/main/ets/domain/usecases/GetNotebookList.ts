import { Notebook } from '../entities/Notebook';
import { NotebookRepository } from '../repositories/NotebookRepository';

export class GetNotebookList {
  constructor(private readonly notebookRepository: NotebookRepository) {
  }

  async execute(): Promise<Notebook[]> {
    return this.notebookRepository.getNotebookList();
  }
}
