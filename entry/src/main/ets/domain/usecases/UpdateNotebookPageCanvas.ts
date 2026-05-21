import { NotebookPageCanvas } from '../entities/NotebookPageCanvas';
import { NotebookRepository, UpdateNotebookPageCanvasRequest } from '../repositories/NotebookRepository';

export class UpdateNotebookPageCanvas {
  constructor(private readonly notebookRepository: NotebookRepository) {
  }

  async execute(request: UpdateNotebookPageCanvasRequest): Promise<NotebookPageCanvas | null> {
    return this.notebookRepository.updateNotebookPageCanvas(request);
  }
}
