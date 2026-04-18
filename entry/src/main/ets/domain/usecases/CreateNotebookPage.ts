import { NotebookPage } from '../entities/NotebookPage';
import { CreateNotebookPageRequest, NotebookRepository } from '../repositories/NotebookRepository';

export class CreateNotebookPage {
  constructor(private readonly notebookRepository: NotebookRepository) {
  }

  async execute(request: CreateNotebookPageRequest): Promise<NotebookPage | null> {
    return this.notebookRepository.createNotebookPage(request);
  }
}
