import { NotebookPage } from '../entities/NotebookPage';
import { NotebookRepository, UpdateNotebookPageTemplateRequest } from '../repositories/NotebookRepository';

export class UpdateNotebookPageTemplate {
  constructor(private readonly notebookRepository: NotebookRepository) {
  }

  async execute(request: UpdateNotebookPageTemplateRequest): Promise<NotebookPage | null> {
    return this.notebookRepository.updateNotebookPageTemplate(request);
  }
}
