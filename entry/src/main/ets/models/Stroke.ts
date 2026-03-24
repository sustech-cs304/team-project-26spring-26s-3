export interface Point {
  x: number;
  y: number;
  t: number;
}

export type ToolType = 'pen' | 'eraser';

export interface Stroke {
  id: string;
  pageId: string;
  tool: ToolType;
  color: string;
  width: number;
  points: Point[];
  createdAt: number;
}
