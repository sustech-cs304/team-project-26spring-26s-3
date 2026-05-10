import { StrokeStyle } from '../../../domain/entities/Stroke';
import { ToolSetting } from '../../../domain/entities/ToolSetting';

export interface EditorDebugSnapshot {
  instanceId: number;
  pageId: string;
  toolSetting: ToolSetting;
  strokeCount: number;
  elementCount: number;
  activeStrokeStyle: StrokeStyle | null;
  undoDepth: number;
  redoDepth: number;
  recentEvents: string[];
  errorMessage: string;
  persistenceStatus: string;
}
