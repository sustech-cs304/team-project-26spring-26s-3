import { Stroke } from './Stroke';

export const PAGE_CANVAS_CONTENT_VERSION = 2;
export const TRANSPARENT_ELEMENT_BACKGROUND_COLOR = '#00FFFFFF';
export const CANVAS_ELEMENT_TYPES = ['text', 'shape', 'image'] as const;
export const SHAPE_TYPES = ['rectangle', 'circle', 'line'] as const;
export const SHAPE_GEOMETRY_KINDS = ['rect', 'ellipse', 'line'] as const;
export const TEXT_RECOGNITION_SOURCES = ['ocr', 'formula'] as const;
export type CanvasElementType = typeof CANVAS_ELEMENT_TYPES[number];
export type ShapeType = typeof SHAPE_TYPES[number];
export type ShapeGeometryKind = typeof SHAPE_GEOMETRY_KINDS[number];
export type TextRecognitionSource = typeof TEXT_RECOGNITION_SOURCES[number];

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

export interface TextRecognitionMetadata {
  source: TextRecognitionSource;
  sid: string;
  recognizedAt: number;
  rawText: string;
  latex?: string;
}

export interface TextCanvasElement extends CanvasElementBase {
  type: 'text';
  content: string;
  color: string;
  fontSize: number;
  backgroundColor: string;
  recognition?: TextRecognitionMetadata;
}

export interface ShapeGeometryPoint {
  x: number;
  y: number;
}

export interface ShapeGeometry {
  kind: ShapeGeometryKind;
  points: ShapeGeometryPoint[];
}

export interface ShapeCanvasElement extends CanvasElementBase {
  type: 'shape';
  shapeType: ShapeType;
  geometry: ShapeGeometry;
  strokeColor: string;
  fillColor: string;
  strokeWidth: number;
  opacity: number;
}

export interface ImageCanvasElement extends CanvasElementBase {
  type: 'image';
  uri: string;
  originalWidth: number;
  originalHeight: number;
  opacity: number;
  sourceFileUri?: string;
  sourceFileType?: string;
}

export type CanvasElement = TextCanvasElement | ShapeCanvasElement | ImageCanvasElement;

export interface PageCanvasContent {
  version: number;
  strokes: Stroke[];
  elements: CanvasElement[];
}

export function isCanvasElementType(value: string): value is CanvasElementType {
  return CANVAS_ELEMENT_TYPES.includes(value as CanvasElementType);
}

export function isShapeType(value: string): value is ShapeType {
  return SHAPE_TYPES.includes(value as ShapeType);
}

export function isShapeGeometryKind(value: string): value is ShapeGeometryKind {
  return SHAPE_GEOMETRY_KINDS.includes(value as ShapeGeometryKind);
}
