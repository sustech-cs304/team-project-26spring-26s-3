import { BoundingBox, expandBoundingBox } from '../../../common/utils/GeometryUtil';
import { StrokePoint } from '../../../domain/entities/Stroke';
import {
  ResizeHandle,
  ResizeHandlePoint,
  SelectionContextMenuTarget,
  SelectionHitResult,
  SelectionTarget
} from './SelectionTypes';

export class SelectionController {
  static hitTestTargets(targets: SelectionTarget[], point: StrokePoint, hitTolerance: number): SelectionHitResult {
    const strokeTarget = SelectionController.findHitTarget(targets, point, hitTolerance, true);
    if (strokeTarget !== null) {
      return {
        target: strokeTarget,
        kind: strokeTarget.kind,
        canMove: strokeTarget.canMove,
        canShowMenu: strokeTarget.canShowMenu
      };
    }

    const elementTarget = SelectionController.findHitTarget(targets, point, hitTolerance, false);
    if (elementTarget !== null) {
      return {
        target: elementTarget,
        kind: elementTarget.kind,
        canMove: elementTarget.canMove,
        canShowMenu: elementTarget.canShowMenu
      };
    }

    return {
      target: null,
      kind: 'none',
      canMove: false,
      canShowMenu: false
    };
  }

  static getContextMenuTarget(target: SelectionTarget): SelectionContextMenuTarget {
    return target.kind === 'strokeGroup' ? 'strokeGroup' : 'element';
  }

  static getResizeHandlePoints(bounds: BoundingBox): ResizeHandlePoint[] {
    const centerX = (bounds.minX + bounds.maxX) / 2;
    const centerY = (bounds.minY + bounds.maxY) / 2;
    return [
      { handle: 'topLeft', x: bounds.minX, y: bounds.minY },
      { handle: 'top', x: centerX, y: bounds.minY },
      { handle: 'topRight', x: bounds.maxX, y: bounds.minY },
      { handle: 'right', x: bounds.maxX, y: centerY },
      { handle: 'bottomRight', x: bounds.maxX, y: bounds.maxY },
      { handle: 'bottom', x: centerX, y: bounds.maxY },
      { handle: 'bottomLeft', x: bounds.minX, y: bounds.maxY },
      { handle: 'left', x: bounds.minX, y: centerY }
    ];
  }

  static hitTestResizeHandle(bounds: BoundingBox, point: StrokePoint, hitTolerance: number): ResizeHandle | null {
    for (const handlePoint of SelectionController.getResizeHandlePoints(bounds)) {
      const deltaX = point.x - handlePoint.x;
      const deltaY = point.y - handlePoint.y;
      if (Math.sqrt(deltaX * deltaX + deltaY * deltaY) <= Math.max(1, hitTolerance)) {
        return handlePoint.handle;
      }
    }

    return null;
  }

  static isPointInTargetBounds(bounds: BoundingBox, point: StrokePoint, hitTolerance: number): boolean {
    return SelectionController.isPointInBoundingBox(point, expandBoundingBox(bounds, hitTolerance));
  }

  private static findHitTarget(
    targets: SelectionTarget[],
    point: StrokePoint,
    hitTolerance: number,
    strokeOnly: boolean
  ): SelectionTarget | null {
    for (const target of targets) {
      if ((target.kind === 'strokeGroup') !== strokeOnly) {
        continue;
      }

      if (SelectionController.isPointInBoundingBox(point, expandBoundingBox(target.bounds, hitTolerance))) {
        return target;
      }
    }

    return null;
  }

  private static isPointInBoundingBox(point: StrokePoint, bounds: BoundingBox): boolean {
    return point.x >= bounds.minX && point.x <= bounds.maxX &&
      point.y >= bounds.minY && point.y <= bounds.maxY;
  }
}
