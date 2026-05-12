import { PageCanvasContent } from '../entities/CanvasElement';
import { Stroke } from '../entities/Stroke';

export interface EditorRepository {
  getStrokes(pageId: string): Promise<Stroke[]>;
  saveStrokes(pageId: string, strokes: Stroke[]): Promise<void>;
  clearStrokes(pageId: string): Promise<void>;
  getPageContent(pageId: string): Promise<PageCanvasContent>;
  savePageContent(pageId: string, content: PageCanvasContent): Promise<void>;
}
