import common from '@ohos.app.ability.common';
import { Notebook } from '../models/Notebook';
import { KeyValueStore, openKeyValueStore } from './KeyValueStore';
import { formatError } from '../utils/ErrorUtils';

const NOTEBOOK_PREFERENCES_NAME = 'canvas_notebook_store';
const NOTEBOOKS_KEY = 'notebooks';

export class NotebookRepository {
  constructor(private context: common.Context | undefined) {}

  async list(): Promise<Notebook[]> {
    const records = await this.loadAll();
    return this.sort(records);
  }

  async getById(id: string): Promise<Notebook | undefined> {
    const records = await this.loadAll();
    return records.find((item: Notebook) => item.id === id);
  }

  async create(title: string): Promise<Notebook> {
    const trimmedTitle = this.normalizeTitle(title);
    const records = await this.loadAll();
    const timestamp = Date.now();
    const notebook: Notebook = {
      id: this.generateId(),
      title: trimmedTitle,
      createdAt: timestamp,
      updatedAt: timestamp,
      pageIds: []
    };

    records.unshift(notebook);
    await this.saveAll(records);
    return notebook;
  }

  async rename(id: string, title: string): Promise<Notebook | undefined> {
    const trimmedTitle = this.normalizeTitle(title);
    const records = await this.loadAll();
    const target = records.find((item: Notebook) => item.id === id);
    if (!target) {
      return undefined;
    }

    target.title = trimmedTitle;
    target.updatedAt = Date.now();
    await this.saveAll(records);
    return target;
  }

  async delete(id: string): Promise<void> {
    const records = await this.loadAll();
    const nextRecords = records.filter((item: Notebook) => item.id !== id);
    await this.saveAll(nextRecords);
  }

  async syncPageIds(id: string, pageIds: string[]): Promise<Notebook | undefined> {
    const records = await this.loadAll();
    const target = records.find((item: Notebook) => item.id === id);
    if (!target) {
      return undefined;
    }

    target.pageIds = [...pageIds];
    target.updatedAt = Date.now();
    await this.saveAll(records);
    return target;
  }

  private async getStore(): Promise<KeyValueStore> {
    try {
      return await openKeyValueStore(this.context, NOTEBOOK_PREFERENCES_NAME);
    } catch (error) {
      throw new Error(`Failed to open notebook preferences: ${formatError(error)}`);
    }
  }

  private async loadAll(): Promise<Notebook[]> {
    try {
      const store = await this.getStore();
      const rawValue = await store.get(NOTEBOOKS_KEY, '[]') as string;
      return this.parse(rawValue);
    } catch (error) {
      throw new Error(`Failed to load notebooks: ${formatError(error)}`);
    }
  }

  private async saveAll(notebooks: Notebook[]): Promise<void> {
    try {
      const store = await this.getStore();
      const serialized = JSON.stringify(this.sort(notebooks));
      await store.put(NOTEBOOKS_KEY, serialized);
      await store.flush();
    } catch (error) {
      throw new Error(`Failed to save notebooks: ${formatError(error)}`);
    }
  }

  private parse(rawValue: string): Notebook[] {
    try {
      const parsed = JSON.parse(rawValue) as Notebook[];
      if (!Array.isArray(parsed)) {
        return [];
      }

      return parsed
        .filter((item: Notebook) => typeof item?.id === 'string' && typeof item?.title === 'string')
        .map((item: Notebook) => ({
          id: item.id,
          title: item.title,
          createdAt: Number(item.createdAt) || Date.now(),
          updatedAt: Number(item.updatedAt) || Date.now(),
          pageIds: Array.isArray(item.pageIds) ? item.pageIds : []
        }));
    } catch (_error) {
      return [];
    }
  }

  private sort(notebooks: Notebook[]): Notebook[] {
    return [...notebooks].sort((left: Notebook, right: Notebook) => right.updatedAt - left.updatedAt);
  }

  private normalizeTitle(title: string): string {
    const trimmed = title.trim();
    return trimmed.length > 0 ? trimmed : 'Untitled Notebook';
  }

  private generateId(): string {
    return `notebook_${Date.now()}_${Math.floor(Math.random() * 100000)}`;
  }
}
