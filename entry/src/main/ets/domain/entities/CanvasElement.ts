import { Stroke } from './Stroke';

export const PAGE_CANVAS_CONTENT_VERSION = 3;
export const DEFAULT_STROKE_LAYER_Z_INDEX = 0;
export const TRANSPARENT_ELEMENT_BACKGROUND_COLOR = '#00FFFFFF';
export const CANVAS_ELEMENT_TYPES = ['text', 'shape', 'image'] as const;
export const SHAPE_TYPES = ['rectangle', 'circle', 'line'] as const;
export const SHAPE_GEOMETRY_KINDS = ['rect', 'ellipse', 'line'] as const;
export const TEXT_RECOGNITION_SOURCES = ['ocr', 'formula'] as const;
export const ELEMENT_OUTLINE_LINE_STYLES = ['none', 'solid', 'dashed', 'dotted'] as const;
export type CanvasElementType = typeof CANVAS_ELEMENT_TYPES[number];
export type ShapeType = typeof SHAPE_TYPES[number];
export type ShapeGeometryKind = typeof SHAPE_GEOMETRY_KINDS[number];
export type TextRecognitionSource = typeof TEXT_RECOGNITION_SOURCES[number];
export type ElementOutlineLineStyle = typeof ELEMENT_OUTLINE_LINE_STYLES[number];

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

export interface ElementOutlineStyle {
  lineStyle: ElementOutlineLineStyle;
  color: string;
  width: number;
}

export interface ShapeCanvasElement extends CanvasElementBase {
  type: 'shape';
  shapeType: ShapeType;
  geometry: ShapeGeometry;
  fillColor: string;
  outline: ElementOutlineStyle;
  opacity: number;
}

export interface ImageCanvasElement extends CanvasElementBase {
  type: 'image';
  uri: string;
  originalWidth: number;
  originalHeight: number;
  opacity: number;
  outline: ElementOutlineStyle;
  sourceFileUri?: string;
  sourceFileType?: string;
}

export type CanvasElement = TextCanvasElement | ShapeCanvasElement | ImageCanvasElement;

export interface PageCanvasContent {
  version: number;
  strokes: Stroke[];
  elements: CanvasElement[];
  strokeLayerZIndex: number;
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

export function isElementOutlineLineStyle(value: string): value is ElementOutlineLineStyle {
  return ELEMENT_OUTLINE_LINE_STYLES.includes(value as ElementOutlineLineStyle);
}
