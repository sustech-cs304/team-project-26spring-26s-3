import { DrawableToolType } from './ToolSetting';

export interface StrokePoint {
  x: number;
  y: number;
  t: number;
  pressure?: number;
}

export interface StrokeStyle {
  tool: DrawableToolType;
  color: string;
  width: number;
  opacity: number;
}

export interface Stroke {
  id: string;
  pageId: string;
  points: StrokePoint[];
  style: StrokeStyle;
  createdAt: number;
  updatedAt: number;
}
