import { NotebookRepository, ReorderNotebookPagesRequest } from '../repositories/NotebookRepository';

export class ReorderNotebookPages {
  constructor(private readonly notebookRepository: NotebookRepository) {
  }

  async execute(request: ReorderNotebookPagesRequest): Promise<boolean> {
    return this.notebookRepository.reorderNotebookPages(request);
  }
}
