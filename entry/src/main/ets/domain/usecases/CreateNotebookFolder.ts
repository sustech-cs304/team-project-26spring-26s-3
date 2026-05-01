import { NotebookFolder } from '../entities/NotebookFolder';
import { CreateNotebookFolderRequest, NotebookRepository } from '../repositories/NotebookRepository';

export class CreateNotebookFolder {
  constructor(private readonly notebookRepository: NotebookRepository) {
  }

  async execute(request: CreateNotebookFolderRequest): Promise<NotebookFolder> {
    return this.notebookRepository.createFolder(request);
  }
}
