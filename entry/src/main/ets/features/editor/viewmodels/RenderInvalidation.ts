import { BoundingBox } from '../../../common/utils/GeometryUtil';
import { IndexedStrokeRecord } from '../controllers/UndoRedoController';

export type RenderInvalidationMode = 'full' | 'partial';
export type RenderInvalidationReason = 'load' | 'erase' | 'undo' | 'redo' | 'clear';

export interface RenderInvalidation {
  sequence: number;
  mode: RenderInvalidationMode;
  reason: RenderInvalidationReason;
  dirtyRect: BoundingBox | null;
  removedStrokeIds: string[];
  addedRecords: IndexedStrokeRecord[];
}
