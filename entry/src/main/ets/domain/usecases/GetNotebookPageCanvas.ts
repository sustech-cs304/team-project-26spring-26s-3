import { NotebookPageCanvas } from '../entities/NotebookPageCanvas';
import { GetNotebookPageCanvasRequest, NotebookRepository } from '../repositories/NotebookRepository';

export class GetNotebookPageCanvas {
  constructor(private readonly notebookRepository: NotebookRepository) {
  }

  async execute(request: GetNotebookPageCanvasRequest): Promise<NotebookPageCanvas | null> {
    return this.notebookRepository.getNotebookPageCanvas(request);
  }
}
