import common from '@ohos.app.ability.common';
import preferences from '@ohos.data.preferences';
import { Point, Stroke } from '../models/Stroke';

const NOTEBOOK_PREFERENCES_NAME = 'canvas_notebook_store';

export class StrokeRepository {
  constructor(private context: common.Context) {}

  async listByPage(pageId: string): Promise<Stroke[]> {
    const strokes = await this.loadStrokes(pageId);
    return this.sortStrokes(strokes);
  }

  async saveAll(pageId: string, strokes: Stroke[]): Promise<void> {
    try {
      const store = await this.getStore();
      const serialized = JSON.stringify(this.sortStrokes(strokes));
      await store.put(this.getPageKey(pageId), serialized);
      await store.flush();
    } catch (error) {
      throw new Error(`Failed to save strokes: ${JSON.stringify(error)}`);
    }
  }

  async deleteByPage(pageId: string): Promise<void> {
    try {
      const store = await this.getStore();
      await store.delete(this.getPageKey(pageId));
      await store.flush();
    } catch (error) {
      throw new Error(`Failed to delete strokes: ${JSON.stringify(error)}`);
    }
  }

  private async getStore(): Promise<preferences.Preferences> {
    try {
      return await preferences.getPreferences(this.context, NOTEBOOK_PREFERENCES_NAME);
    } catch (error) {
      throw new Error(`Failed to open stroke preferences: ${JSON.stringify(error)}`);
    }
  }

  private getPageKey(pageId: string): string {
    return `strokes_${pageId}`;
  }

  private async loadStrokes(pageId: string): Promise<Stroke[]> {
    try {
      const store = await this.getStore();
      const rawValue = await store.get(this.getPageKey(pageId), '[]') as string;
      return this.parse(rawValue, pageId);
    } catch (error) {
      throw new Error(`Failed to load strokes: ${JSON.stringify(error)}`);
    }
  }

  private parse(rawValue: string, pageId: string): Stroke[] {
    try {
      const parsed = JSON.parse(rawValue) as Stroke[];
      if (!Array.isArray(parsed)) {
        return [];
      }

      return parsed
        .filter((item: Stroke) => typeof item?.id === 'string')
        .map((item: Stroke) => {
          const stroke: Stroke = {
            id: item.id,
            pageId,
            tool: item.tool === 'eraser' ? 'eraser' : 'pen',
            color: typeof item.color === 'string' ? item.color : '#111827',
            width: Number(item.width) > 0 ? Number(item.width) : 4,
            points: this.parsePoints(item.points),
            createdAt: Number(item.createdAt) || Date.now()
          };
          return stroke;
        })
        .filter((item: Stroke) => item.points.length > 0);
    } catch (_error) {
      return [];
    }
  }

  private parsePoints(points: Point[]): Point[] {
    if (!Array.isArray(points)) {
      return [];
    }

    return points
      .filter((item: Point) => Number.isFinite(item?.x) && Number.isFinite(item?.y))
      .map((item: Point) => ({
        x: Number(item.x),
        y: Number(item.y),
        t: Number(item.t) || Date.now()
      }));
  }

  private sortStrokes(strokes: Stroke[]): Stroke[] {
    return [...strokes].sort((left: Stroke, right: Stroke) => left.createdAt - right.createdAt);
  }
}
