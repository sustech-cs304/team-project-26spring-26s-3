import { BoundingBox } from '../../../common/utils/GeometryUtil';
import { StrokePoint } from '../../../domain/entities/Stroke';

export type SelectionTargetKind = 'strokeGroup' | 'textElement' | 'shapeElement' | 'imageElement';
export type SelectionContextMenuTarget = 'strokeGroup' | 'element';
export type LayerOrderAction = 'layerUp' | 'layerDown' | 'layerTop' | 'layerBottom';
export type SelectionAction =
  'delete' |
  'copy' |
  'resize' |
  'ocr' |
  'formula' |
  'fill' |
  'background' |
  'outline' |
  'layer' |
  LayerOrderAction;

export interface LayerActionAvailability {
  canMoveUp: boolean;
  canMoveDown: boolean;
  canMoveTop: boolean;
  canMoveBottom: boolean;
}

export type ResizeHandle =
  'topLeft' |
  'top' |
  'topRight' |
  'right' |
  'bottomRight' |
  'bottom' |
  'bottomLeft' |
  'left';

export interface ResizeHandlePoint {
  handle: ResizeHandle;
  x: number;
  y: number;
}

export interface SelectionActionResult {
  changed: boolean;
  changedStrokes: boolean;
  changedElements: boolean;
  elementSelectionChanged: boolean;
}

export interface SelectionTarget {
  id: string;
  kind: SelectionTargetKind;
  bounds: BoundingBox;
  outline: StrokePoint[];
  strokeIds: string[];
  elementId: string;
  canMove: boolean;
  canShowMenu: boolean;
}

export interface SelectionHitResult {
  target: SelectionTarget | null;
  kind: SelectionTargetKind | 'none';
  canMove: boolean;
  canShowMenu: boolean;
}
