import { NotebookRepository } from '../repositories/NotebookRepository';

export class DeleteNotebook {
  constructor(private readonly notebookRepository: NotebookRepository) {
  }

  async execute(notebookId: string): Promise<boolean> {
    return this.notebookRepository.deleteNotebook(notebookId);
  }
}
