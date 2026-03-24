import common from '@ohos.app.ability.common';
import preferences from '@ohos.data.preferences';
import { NotePage } from '../models/NotePage';

const NOTEBOOK_PREFERENCES_NAME = 'canvas_notebook_store';

export class NotePageRepository {
  constructor(private context: common.Context) {}

  async listByNotebook(notebookId: string): Promise<NotePage[]> {
    const pages = await this.loadPages(notebookId);
    return this.sortPages(pages);
  }

  async create(notebookId: string, nextIndex: number): Promise<NotePage> {
    const pages = await this.loadPages(notebookId);
    const timestamp = Date.now();
    const page: NotePage = {
      id: this.generateId(),
      notebookId,
      index: nextIndex,
      createdAt: timestamp,
      updatedAt: timestamp,
      strokeIds: []
    };

    pages.push(page);
    await this.savePages(notebookId, pages);
    return page;
  }

  async delete(notebookId: string, pageId: string): Promise<void> {
    const pages = await this.loadPages(notebookId);
    const filteredPages = pages.filter((item: NotePage) => item.id !== pageId)
      .map((item: NotePage, index: number) => ({
        ...item,
        index,
        updatedAt: Date.now()
      }));
    await this.savePages(notebookId, filteredPages);
  }

  async updateStrokeIds(notebookId: string, pageId: string, strokeIds: string[]): Promise<NotePage | undefined> {
    const pages = await this.loadPages(notebookId);
    const target = pages.find((item: NotePage) => item.id === pageId);
    if (!target) {
      return undefined;
    }

    target.strokeIds = [...strokeIds];
    target.updatedAt = Date.now();
    await this.savePages(notebookId, pages);
    return target;
  }

  private async getStore(): Promise<preferences.Preferences> {
    try {
      return await preferences.getPreferences(this.context, NOTEBOOK_PREFERENCES_NAME);
    } catch (error) {
      throw new Error(`Failed to open page preferences: ${JSON.stringify(error)}`);
    }
  }

  private getPagesKey(notebookId: string): string {
    return `pages_${notebookId}`;
  }

  private async loadPages(notebookId: string): Promise<NotePage[]> {
    try {
      const store = await this.getStore();
      const rawValue = await store.get(this.getPagesKey(notebookId), '[]') as string;
      return this.parse(rawValue, notebookId);
    } catch (error) {
      throw new Error(`Failed to load pages: ${JSON.stringify(error)}`);
    }
  }

  private async savePages(notebookId: string, pages: NotePage[]): Promise<void> {
    try {
      const store = await this.getStore();
      const serialized = JSON.stringify(this.sortPages(pages));
      await store.put(this.getPagesKey(notebookId), serialized);
      await store.flush();
    } catch (error) {
      throw new Error(`Failed to save pages: ${JSON.stringify(error)}`);
    }
  }

  private parse(rawValue: string, notebookId: string): NotePage[] {
    try {
      const parsed = JSON.parse(rawValue) as NotePage[];
      if (!Array.isArray(parsed)) {
        return [];
      }

      return parsed
        .filter((item: NotePage) => typeof item?.id === 'string')
        .map((item: NotePage, index: number) => ({
          id: item.id,
          notebookId,
          index: Number(item.index) >= 0 ? Number(item.index) : index,
          createdAt: Number(item.createdAt) || Date.now(),
          updatedAt: Number(item.updatedAt) || Date.now(),
          strokeIds: Array.isArray(item.strokeIds) ? item.strokeIds : []
        }));
    } catch (_error) {
      return [];
    }
  }

  private sortPages(pages: NotePage[]): NotePage[] {
    return [...pages].sort((left: NotePage, right: NotePage) => left.index - right.index);
  }

  private generateId(): string {
    return `page_${Date.now()}_${Math.floor(Math.random() * 100000)}`;
  }
}
