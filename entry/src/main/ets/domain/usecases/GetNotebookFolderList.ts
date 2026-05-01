import { NotebookFolder } from '../entities/NotebookFolder';
import { NotebookRepository } from '../repositories/NotebookRepository';

export class GetNotebookFolderList {
  constructor(private readonly notebookRepository: NotebookRepository) {
  }

  async execute(): Promise<NotebookFolder[]> {
    return this.notebookRepository.getFolderList();
  }
}
