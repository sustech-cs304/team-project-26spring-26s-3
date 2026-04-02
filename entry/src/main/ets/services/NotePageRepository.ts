import common from '@ohos.app.ability.common';
import { NotePage, PageTemplate } from '../models/NotePage';
import { KeyValueStore, openKeyValueStore } from './KeyValueStore';
import { formatError } from '../utils/ErrorUtils';
import { DEFAULT_PAGE_TEMPLATE, normalizePageTemplate } from '../utils/PageTemplateUtils';

const NOTEBOOK_PREFERENCES_NAME = 'canvas_notebook_store';

export class NotePageRepository {
  constructor(private context: common.Context | undefined) {}

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
      strokeIds: [],
      template: DEFAULT_PAGE_TEMPLATE
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

  async reorder(notebookId: string, pageId: string, targetIndex: number): Promise<NotePage[]> {
    const pages = this.sortPages(await this.loadPages(notebookId));
    const currentIndex = pages.findIndex((item: NotePage) => item.id === pageId);
    if (currentIndex < 0) {
      return pages;
    }

    const nextIndex = Math.max(0, Math.min(targetIndex, pages.length - 1));
    if (currentIndex === nextIndex) {
      return pages;
    }

    const nextPages = [...pages];
    const [movedPage] = nextPages.splice(currentIndex, 1);
    nextPages.splice(nextIndex, 0, movedPage);

    const timestamp = Date.now();
    const reorderedPages = nextPages.map((item: NotePage, index: number) => ({
      ...item,
      index,
      updatedAt: item.index === index ? item.updatedAt : timestamp
    }));

    await this.savePages(notebookId, reorderedPages);
    return reorderedPages;
  }

  async updateTemplate(notebookId: string, pageId: string, template: PageTemplate): Promise<NotePage | undefined> {
    const pages = await this.loadPages(notebookId);
    const target = pages.find((item: NotePage) => item.id === pageId);
    if (!target) {
      return undefined;
    }

    if (target.template === template) {
      return target;
    }

    target.template = template;
    target.updatedAt = Date.now();
    await this.savePages(notebookId, pages);
    return target;
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

  private async getStore(): Promise<KeyValueStore> {
    try {
      return await openKeyValueStore(this.context, NOTEBOOK_PREFERENCES_NAME);
    } catch (error) {
      throw new Error(`Failed to open page preferences: ${formatError(error)}`);
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
      throw new Error(`Failed to load pages: ${formatError(error)}`);
    }
  }

  private async savePages(notebookId: string, pages: NotePage[]): Promise<void> {
    try {
      const store = await this.getStore();
      const serialized = JSON.stringify(this.sortPages(pages));
      await store.put(this.getPagesKey(notebookId), serialized);
      await store.flush();
    } catch (error) {
      throw new Error(`Failed to save pages: ${formatError(error)}`);
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
        .map((item: NotePage, index: number) => {
          const template = typeof item.template === 'string' ? item.template : undefined;
          return {
            id: item.id,
            notebookId,
            index: Number(item.index) >= 0 ? Number(item.index) : index,
            createdAt: Number(item.createdAt) || Date.now(),
            updatedAt: Number(item.updatedAt) || Date.now(),
            strokeIds: Array.isArray(item.strokeIds) ? item.strokeIds : [],
            template: normalizePageTemplate(template)
          };
        });
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
