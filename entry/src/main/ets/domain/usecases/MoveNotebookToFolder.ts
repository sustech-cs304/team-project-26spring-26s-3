import { Notebook } from '../entities/Notebook';
import { MoveNotebookToFolderRequest, NotebookRepository } from '../repositories/NotebookRepository';

export class MoveNotebookToFolder {
  constructor(private readonly notebookRepository: NotebookRepository) {
  }

  async execute(request: MoveNotebookToFolderRequest): Promise<Notebook | null> {
    return this.notebookRepository.moveNotebookToFolder(request);
  }
}
