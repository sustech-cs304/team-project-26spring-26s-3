import { DeleteNotebookPageRequest, NotebookRepository } from '../repositories/NotebookRepository';

export class DeleteNotebookPage {
  constructor(private readonly notebookRepository: NotebookRepository) {
  }

  async execute(request: DeleteNotebookPageRequest): Promise<boolean> {
    return this.notebookRepository.deleteNotebookPage(request);
  }
}
