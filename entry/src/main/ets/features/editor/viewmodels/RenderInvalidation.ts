import { BoundingBox } from '../../../common/utils/GeometryUtil';
import { IndexedStrokeRecord } from '../controllers/UndoRedoController';

export type RenderInvalidationMode = 'full' | 'partial';
export type RenderInvalidationReason = 'load' | 'erase' | 'undo' | 'redo' | 'clear' | 'move';

export interface RenderInvalidation {
  sequence: number;
  mode: RenderInvalidationMode;
  reason: RenderInvalidationReason;
  dirtyRects: BoundingBox[];
  removedStrokeIds: string[];
  addedRecords: IndexedStrokeRecord[];
}
