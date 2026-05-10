import { Stroke } from './Stroke';

export const PAGE_CANVAS_CONTENT_VERSION = 2;
export const CANVAS_ELEMENT_TYPES = ['text', 'shape', 'image'] as const;
export type CanvasElementType = typeof CANVAS_ELEMENT_TYPES[number];

export interface CanvasElementBase {
  id: string;
  pageId: string;
  type: CanvasElementType;
  x: number;
  y: number;
  width: number;
  height: number;
  rotation: number;
  zIndex: number;
  createdAt: number;
  updatedAt: number;
}

export interface TextCanvasElement extends CanvasElementBase {
  type: 'text';
  content: string;
  color: string;
  fontSize: number;
  backgroundColor: string;
}

export type CanvasElement = TextCanvasElement;

export interface PageCanvasContent {
  version: number;
  strokes: Stroke[];
  elements: CanvasElement[];
}

export function isCanvasElementType(value: string): value is CanvasElementType {
  return CANVAS_ELEMENT_TYPES.includes(value as CanvasElementType);
}
