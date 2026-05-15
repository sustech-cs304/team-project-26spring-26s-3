import { BoundingBox, expandBoundingBox } from '../../../common/utils/GeometryUtil';
import { StrokePoint } from '../../../domain/entities/Stroke';
import { SelectionContextMenuTarget, SelectionHitResult, SelectionTarget } from './SelectionTypes';

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
