import { Stroke } from '../entities/Stroke';
import { EditorRepository } from '../repositories/EditorRepository';

export class RedoLastAction {
  constructor(private readonly editorRepository: EditorRepository) {}

  execute(pageId: string, nextStrokes: Stroke[]): Promise<Stroke[]> {
    return this.editorRepository.saveStrokes(pageId, nextStrokes).then((): Stroke[] => nextStrokes);
  }
}
