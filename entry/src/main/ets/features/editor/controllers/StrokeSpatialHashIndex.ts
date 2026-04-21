import { BoundingBox, getStrokeRenderBoundingBox } from '../../../common/utils/GeometryUtil';
import { Stroke } from '../../../domain/entities/Stroke';

const DEFAULT_SPATIAL_HASH_CELL_SIZE = 192;

export class StrokeSpatialHashIndex {
  private readonly cells: Map<string, Set<string>> = new Map<string, Set<string>>();
  private readonly boundsById: Map<string, BoundingBox> = new Map<string, BoundingBox>();
  private readonly cellKeysById: Map<string, string[]> = new Map<string, string[]>();
  private readonly normalizedCellSize: number;

  constructor(cellSize: number = DEFAULT_SPATIAL_HASH_CELL_SIZE) {
    this.normalizedCellSize = Math.max(32, Math.floor(cellSize));
  }

  clear(): void {
    this.cells.clear();
    this.boundsById.clear();
    this.cellKeysById.clear();
  }

  upsertStroke(stroke: Stroke): void {
    this.upsertStrokeBounds(stroke.id, getStrokeRenderBoundingBox(stroke));
  }

  upsertStrokeBounds(strokeId: string, bounds: BoundingBox | null): void {
    this.removeStrokeById(strokeId);
    if (bounds === null) {
      return;
    }

    const normalizedBounds: BoundingBox = this.cloneBoundingBox(bounds);
    const cellKeys = this.getCellKeysForBounds(normalizedBounds);
    for (const cellKey of cellKeys) {
      let cell = this.cells.get(cellKey);
      if (cell === undefined) {
        cell = new Set<string>();
        this.cells.set(cellKey, cell);
      }
      cell.add(strokeId);
    }

    this.boundsById.set(strokeId, normalizedBounds);
    this.cellKeysById.set(strokeId, cellKeys);
  }

  removeStrokeById(strokeId: string): void {
    const cellKeys = this.cellKeysById.get(strokeId);
    if (cellKeys !== undefined) {
      for (const cellKey of cellKeys) {
        const cell = this.cells.get(cellKey);
        if (cell === undefined) {
          continue;
        }

        cell.delete(strokeId);
        if (cell.size === 0) {
          this.cells.delete(cellKey);
        }
      }
      this.cellKeysById.delete(strokeId);
    }

    this.boundsById.delete(strokeId);
  }

  getBounds(strokeId: string): BoundingBox | null {
    const bounds = this.boundsById.get(strokeId);
    return bounds === undefined ? null : this.cloneBoundingBox(bounds);
  }

  queryStrokeIds(bounds: BoundingBox): string[] {
    const candidateIds = new Set<string>();
    for (const cellKey of this.getCellKeysForBounds(bounds)) {
      const cell = this.cells.get(cellKey);
      if (cell === undefined) {
        continue;
      }

      for (const strokeId of cell) {
        candidateIds.add(strokeId);
      }
    }

    return Array.from(candidateIds);
  }

  private getCellKeysForBounds(bounds: BoundingBox): string[] {
    const startX = Math.floor(bounds.minX / this.normalizedCellSize);
    const endX = Math.floor(bounds.maxX / this.normalizedCellSize);
    const startY = Math.floor(bounds.minY / this.normalizedCellSize);
    const endY = Math.floor(bounds.maxY / this.normalizedCellSize);
    const cellKeys: string[] = [];

    for (let gridX = startX; gridX <= endX; gridX += 1) {
      for (let gridY = startY; gridY <= endY; gridY += 1) {
        cellKeys.push(`${gridX}:${gridY}`);
      }
    }

    return cellKeys;
  }

  private cloneBoundingBox(bounds: BoundingBox): BoundingBox {
    return {
      minX: bounds.minX,
      minY: bounds.minY,
      maxX: bounds.maxX,
      maxY: bounds.maxY
    };
  }
}
