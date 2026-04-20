import { Stroke } from '../entities/Stroke';
import { EditorRepository } from '../repositories/EditorRepository';

export class SaveStroke {
  constructor(private readonly editorRepository: EditorRepository) {}

  execute(pageId: string, strokes: Stroke[]): Promise<void> {
    return this.editorRepository.saveStrokes(pageId, strokes);
  }
}
