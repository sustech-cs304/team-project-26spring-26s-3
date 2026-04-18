import { NotebookPage } from '../entities/NotebookPage';
import { NotebookRepository } from '../repositories/NotebookRepository';

export class GetNotebookPages {
  constructor(private readonly notebookRepository: NotebookRepository) {
  }

  async execute(notebookId: string): Promise<NotebookPage[]> {
    return this.notebookRepository.getNotebookPages(notebookId);
  }
}
