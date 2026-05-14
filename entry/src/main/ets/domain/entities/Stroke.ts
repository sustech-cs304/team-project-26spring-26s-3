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
  renderKey?: string;
  renderWarmupPoints?: StrokePoint[];
  points: StrokePoint[];
  style: StrokeStyle;
  createdAt: number;
  updatedAt: number;
}

export function getStrokeRenderKey(stroke: Stroke): string {
  if (typeof stroke.renderKey === 'string' && stroke.renderKey.length > 0) {
    return stroke.renderKey;
  }

  return stroke.id;
}
