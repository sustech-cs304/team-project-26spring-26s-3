import common from '@ohos.app.ability.common';
import preferences from '@ohos.data.preferences';
import fileIo from '@ohos.file.fs';

import { NotebookRepositoryImpl } from './NotebookRepositoryImpl';
import {
  CanvasElement,
  PAGE_CANVAS_CONTENT_VERSION,
  PageCanvasContent,
  TextCanvasElement
} from '../../domain/entities/CanvasElement';
import { Stroke, StrokePoint, StrokeStyle } from '../../domain/entities/Stroke';
import { DrawableToolType, isDrawableToolType } from '../../domain/entities/ToolSetting';
import { EditorRepository } from '../../domain/repositories/EditorRepository';

const EDITOR_PREFERENCES_NAME = 'editor_store';
const PAGE_STROKES_KEY_PREFIX = 'page_strokes_';
const LEGACY_STORAGE_DIR_NAME = 'editor_store';
const LEGACY_FILE_SUFFIX = '.json';
const PAGE_CONTENT_VERSION = PAGE_CANVAS_CONTENT_VERSION;

const MEMORY_STORES: Map<string, Map<string, preferences.ValueType>> = new Map<string, Map<string, preferences.ValueType>>();

type ErrorRecordValue = Object | string | number | boolean | undefined | null;

interface KeyValueStore {
  get(key: string, defaultValue: preferences.ValueType): Promise<preferences.ValueType>;
  put(key: string, value: preferences.ValueType): Promise<void>;
  flush(): Promise<void>;
}

class MemoryStore implements KeyValueStore {
  constructor(private readonly name: string) {}

  async get(key: string, defaultValue: preferences.ValueType): Promise<preferences.ValueType> {
    const store = this.getStore();
    const value = store.get(key);
    return value === undefined ? defaultValue : value;
  }

  async put(key: string, value: preferences.ValueType): Promise<void> {
    this.getStore().set(key, value);
  }

  async flush(): Promise<void> {}

  private getStore(): Map<string, preferences.ValueType> {
    let store = MEMORY_STORES.get(this.name);
    if (!store) {
      store = new Map<string, preferences.ValueType>();
      MEMORY_STORES.set(this.name, store);
    }

    return store;
  }
}

export class EditorRepositoryImpl implements EditorRepository {
  private storageMode: 'unknown' | 'preferences' | 'memory' = 'unknown';

  constructor(private readonly context: common.Context) {}

  async getStrokes(pageId: string): Promise<Stroke[]> {
    try {
      const pageContent = await this.getPageContent(pageId);
      const strokes = pageContent.strokes;
      this.logDebug(`getStrokes pageId=${pageId} count=${strokes.length}`);
      return strokes;
    } catch (error) {
      throw new Error(`Failed to load strokes: ${this.stringifyError(error)}`);
    }
  }

  async saveStrokes(pageId: string, strokes: Stroke[]): Promise<void> {
    try {
      const pageContent = await this.getPageContent(pageId);
      await this.savePageContent(pageId, {
        version: PAGE_CONTENT_VERSION,
        strokes,
        elements: pageContent.elements
      });
      this.logDebug(`saveStrokes pageId=${pageId} count=${strokes.length}`);
    } catch (error) {
      throw new Error(`Failed to save strokes: ${this.stringifyError(error)}`);
    }
  }

  async clearStrokes(pageId: string): Promise<void> {
    try {
      const pageContent = await this.getPageContent(pageId);
      await this.savePageContent(pageId, {
        version: PAGE_CONTENT_VERSION,
        strokes: [],
        elements: pageContent.elements
      });
      this.logDebug(`clearStrokes pageId=${pageId}`);
    } catch (error) {
      throw new Error(`Failed to clear strokes: ${this.stringifyError(error)}`);
    }
  }

  async getPageContent(pageId: string): Promise<PageCanvasContent> {
    try {
      const rawValue = await this.readRawValue(pageId);
      const pageContent = this.deserializePageContent(rawValue, pageId);
      this.logDebug(
        `getPageContent pageId=${pageId} strokes=${pageContent.strokes.length} elements=${pageContent.elements.length}`
      );
      return pageContent;
    } catch (error) {
      throw new Error(`Failed to load page content: ${this.stringifyError(error)}`);
    }
  }

  async savePageContent(pageId: string, content: PageCanvasContent): Promise<void> {
    const normalizedContent: PageCanvasContent = {
      version: PAGE_CONTENT_VERSION,
      strokes: content.strokes,
      elements: content.elements
    };
    const serialized = this.serializePageContent(normalizedContent);
    this.logDebug(
      `savePageContent beforePut pageId=${pageId} strokes=${content.strokes.length} elements=${content.elements.length} bytes=${serialized.length}`
    );

    try {
      await this.writeRawValue(pageId, serialized);
      await this.syncNotebookUpdatedAt(pageId);
      this.logDebug(`savePageContent pageId=${pageId}`);
    } catch (error) {
      throw new Error(`Failed to save page content: ${this.stringifyError(error)}`);
    }
  }

  private async readRawValue(pageId: string): Promise<string> {
    const pageKey = this.buildPageKey(pageId);
    return this.withStore('getStrokes', async (store: KeyValueStore) => {
      const rawValue = await store.get(pageKey, '') as string;
      if (rawValue.length > 0) {
        return rawValue;
      }

      const migratedValue = await this.tryMigrateLegacyFileData(store, pageId);
      return migratedValue ?? '[]';
    });
  }

  private async writeRawValue(pageId: string, value: string): Promise<void> {
    const pageKey = this.buildPageKey(pageId);
    await this.withStore('saveStrokes', async (store: KeyValueStore) => {
      await store.put(pageKey, value);
      await store.flush();
    });
  }

  private async withStore<T>(operationName: string, action: (store: KeyValueStore) => Promise<T>): Promise<T> {
    const store = await this.openStore();

    try {
      return await action(store);
    } catch (error) {
      if (this.storageMode === 'memory') {
        throw error;
      }

      this.logDebug(`recoverStore op=${operationName} reason=${this.stringifyError(error)}`);
      await this.removeStoreFromCache();
      const freshStore = await this.openStore();
      return await action(freshStore);
    }
  }

  private async openStore(): Promise<KeyValueStore> {
    try {
      const store = await preferences.getPreferences(this.context, EDITOR_PREFERENCES_NAME);
      this.logStorageMode('preferences');
      return store as KeyValueStore;
    } catch (error) {
      if (this.shouldUseMemoryStore(error)) {
        this.logStorageMode('memory', this.stringifyError(error));
        return new MemoryStore(EDITOR_PREFERENCES_NAME);
      }

      throw new Error(`Failed to open preferences store "${EDITOR_PREFERENCES_NAME}": ${this.stringifyError(error)}`);
    }
  }

  private async removeStoreFromCache(): Promise<void> {
    try {
      await preferences.removePreferencesFromCache(this.context, EDITOR_PREFERENCES_NAME);
      this.storageMode = 'unknown';
      this.logDebug(`removeStoreFromCache name=${EDITOR_PREFERENCES_NAME}`);
    } catch (error) {
      this.logDebug(`removeStoreFromCache failed error=${this.stringifyError(error)}`);
    }
  }

  private async tryMigrateLegacyFileData(store: KeyValueStore, pageId: string): Promise<string | undefined> {
    const legacyRawValue = await this.readLegacyFileValue(pageId);
    if (legacyRawValue === undefined) {
      return undefined;
    }

    const strokes = this.deserializeStrokes(legacyRawValue, pageId);
    if (legacyRawValue !== '[]' && strokes.length === 0) {
      this.logDebug(`skipLegacyMigration pageId=${pageId} reason=invalidLegacyPayload`);
      return undefined;
    }

    await store.put(this.buildPageKey(pageId), legacyRawValue);
    await store.flush();
    this.logDebug(`migrateLegacyFile pageId=${pageId} count=${strokes.length}`);
    return legacyRawValue;
  }

  private async readLegacyFileValue(pageId: string): Promise<string | undefined> {
    const legacyFilePath = this.buildLegacyFilePath(pageId);
    if (legacyFilePath.length === 0) {
      return undefined;
    }

    try {
      return await fileIo.readText(legacyFilePath);
    } catch (error) {
      if (this.isNoSuchFileError(error)) {
        return undefined;
      }

      this.logDebug(`readLegacyFile failed pageId=${pageId} error=${this.stringifyError(error)}`);
      return undefined;
    }
  }

  private buildPageKey(pageId: string): string {
    return `${PAGE_STROKES_KEY_PREFIX}${pageId}`;
  }

  private buildLegacyFilePath(pageId: string): string {
    const filesDir = this.getFilesDir();
    if (filesDir.length === 0) {
      return '';
    }

    return `${filesDir}/${LEGACY_STORAGE_DIR_NAME}/${encodeURIComponent(pageId)}${LEGACY_FILE_SUFFIX}`;
  }

  private async syncNotebookUpdatedAt(pageId: string): Promise<void> {
    const hasUpdatedNotebook = await new NotebookRepositoryImpl(this.context).touchNotebookPageUpdatedAt(pageId);
    if (!hasUpdatedNotebook) {
      this.logDebug(`syncNotebookUpdatedAt skipped pageId=${pageId} reason=pageNotFound`);
    }
  }

  private getFilesDir(): string {
    const contextRecord = this.context as unknown as Record<string, ErrorRecordValue>;
    const filesDir = contextRecord.filesDir;
    return typeof filesDir === 'string' ? filesDir : '';
  }

  private serializePageContent(content: PageCanvasContent): string {
    return JSON.stringify(content);
  }

  private deserializePageContent(rawValue: string, pageId: string): PageCanvasContent {
    try {
      const parsed = JSON.parse(rawValue) as Object;
      if (Array.isArray(parsed)) {
        return {
          version: PAGE_CONTENT_VERSION,
          strokes: this.parseStrokeList(parsed, pageId),
          elements: []
        };
      }

      if (!parsed || typeof parsed !== 'object') {
        return this.buildEmptyPageContent();
      }

      const record = parsed as Record<string, Object>;
      return {
        version: PAGE_CONTENT_VERSION,
        strokes: this.parseStrokeList(record.strokes, pageId),
        elements: this.parseElementList(record.elements, pageId)
      };
    } catch (_error) {
      return this.buildEmptyPageContent();
    }
  }

  private buildEmptyPageContent(): PageCanvasContent {
    return {
      version: PAGE_CONTENT_VERSION,
      strokes: [],
      elements: []
    };
  }

  private deserializeStrokes(rawValue: string, pageId: string): Stroke[] {
    return this.deserializePageContent(rawValue, pageId).strokes;
  }

  private parseStrokeList(value: Object, pageId: string): Stroke[] {
    if (!Array.isArray(value)) {
      return [];
    }

    const result: Stroke[] = [];

    for (const item of value) {
      const stroke = this.parseStroke(item, pageId);
      if (stroke) {
        result.push(stroke);
      }
    }

    return result;
  }

  private parseElementList(value: Object, pageId: string): CanvasElement[] {
    if (!Array.isArray(value)) {
      return [];
    }

    const result: CanvasElement[] = [];

    for (const item of value) {
      const element = this.parseElement(item, pageId);
      if (element) {
        result.push(element);
      }
    }

    return result.sort((left: CanvasElement, right: CanvasElement): number => left.zIndex - right.zIndex);
  }

  private parseElement(value: Object, pageId: string): CanvasElement | null {
    if (!value || typeof value !== 'object') {
      return null;
    }

    const candidate = value as Record<string, Object>;
    const type = typeof candidate.type === 'string' ? candidate.type : '';
    if (type === 'text') {
      return this.parseTextElement(candidate, pageId);
    }

    return null;
  }

  private parseTextElement(candidate: Record<string, Object>, pageId: string): TextCanvasElement | null {
    const id = typeof candidate.id === 'string' ? candidate.id : '';
    if (id.length === 0) {
      return null;
    }

    const x = this.parseFiniteNumber(candidate.x, 80);
    const y = this.parseFiniteNumber(candidate.y, 80);
    const width = Math.max(80, this.parseFiniteNumber(candidate.width, 220));
    const height = Math.max(40, this.parseFiniteNumber(candidate.height, 96));
    const rotation = this.parseFiniteNumber(candidate.rotation, 0);
    const zIndex = Math.max(0, Math.floor(this.parseFiniteNumber(candidate.zIndex, 0)));
    const createdAt = this.parseFiniteNumber(candidate.createdAt, Date.now());
    const updatedAt = this.parseFiniteNumber(candidate.updatedAt, createdAt);
    const content = typeof candidate.content === 'string' ? candidate.content : '';
    const color = typeof candidate.color === 'string' && candidate.color.length > 0 ? candidate.color : '#111827';
    const fontSize = Math.max(8, this.parseFiniteNumber(candidate.fontSize, 18));
    const backgroundColor = typeof candidate.backgroundColor === 'string' && candidate.backgroundColor.length > 0 ?
      candidate.backgroundColor : '#FFFFFF00';

    return {
      id,
      pageId,
      type: 'text',
      x,
      y,
      width,
      height,
      rotation,
      zIndex,
      createdAt,
      updatedAt,
      content,
      color,
      fontSize,
      backgroundColor
    };
  }

  private parseFiniteNumber(value: Object, fallbackValue: number): number {
    const numericValue = Number(value);
    return Number.isFinite(numericValue) ? numericValue : fallbackValue;
  }

  private parseStroke(value: Object, pageId: string): Stroke | null {
    const candidate = value as Record<string, Object>;
    const id = typeof candidate.id === 'string' ? candidate.id : '';
    const createdAt = Number(candidate.createdAt);
    const updatedAt = Number(candidate.updatedAt);
    const points = this.parsePoints(candidate.points);
    const style = this.parseStyle(candidate.style);

    if (id.length === 0 || points.length === 0 || !style) {
      return null;
    }

    return {
      id,
      pageId,
      points,
      style,
      createdAt: Number.isFinite(createdAt) ? createdAt : Date.now(),
      updatedAt: Number.isFinite(updatedAt) ? updatedAt : Date.now()
    };
  }

  private parsePoints(value: Object): StrokePoint[] {
    if (!Array.isArray(value)) {
      return [];
    }

    const result: StrokePoint[] = [];

    for (const item of value) {
      const point = item as Record<string, Object>;
      const x = Number(point.x);
      const y = Number(point.y);
      const t = Number(point.t);
      const pressure = point.pressure === undefined ? undefined : Number(point.pressure);

      if (!Number.isFinite(x) || !Number.isFinite(y) || !Number.isFinite(t)) {
        continue;
      }

      result.push({
        x,
        y,
        t,
        pressure: pressure !== undefined && Number.isFinite(pressure) ? pressure : undefined
      });
    }

    return result;
  }

  private parseStyle(value: Object): StrokeStyle | null {
    if (!value || typeof value !== 'object') {
      return null;
    }

    const style = value as Record<string, Object>;
    const toolValue = typeof style.tool === 'string' ? style.tool : '';
    const color = typeof style.color === 'string' ? style.color : '';
    const width = Number(style.width);
    const opacity = Number(style.opacity);

    if (
      !isDrawableToolType(toolValue) ||
      color.length === 0 ||
      !Number.isFinite(width) ||
      width <= 0 ||
      !Number.isFinite(opacity) ||
      opacity <= 0 ||
      opacity > 1
    ) {
      return null;
    }

    return {
      tool: toolValue as DrawableToolType,
      color,
      width,
      opacity
    };
  }

  private isNoSuchFileError(error: Object): boolean {
    const errorRecord = error as Record<string, ErrorRecordValue>;
    const code = typeof errorRecord.code === 'number' ? errorRecord.code : Number(errorRecord.code);
    if (code === 13900002) {
      return true;
    }

    const message = this.stringifyError(error).toLowerCase();
    return message.includes('no such file') || message.includes('no such file or directory');
  }

  private shouldUseMemoryStore(error: Object): boolean {
    const errorRecord = error as Record<string, ErrorRecordValue>;
    const code = typeof errorRecord.code === 'number' ? errorRecord.code : Number(errorRecord.code);
    if (code === 401 || code === 801 || code === 100001 || code === 15500000 || code === 15501001) {
      return true;
    }

    const message = this.stringifyError(error).toLowerCase();
    return message.includes('preview')
      || message.includes('capability not supported')
      || message.includes('stage mode only')
      || message.includes('ui preview');
  }

  private logStorageMode(mode: 'preferences' | 'memory', reason?: string): void {
    if (this.storageMode === mode) {
      return;
    }

    this.storageMode = mode;
    const suffix = reason ? ` reason=${reason}` : '';
    this.logDebug(`openStore mode=${mode}${suffix}`);
  }

  private logDebug(message: string): void {
    console.info(`[EditorRepository] ${message}`);
  }

  private stringifyError(error: Object): string {
    if (error instanceof Error) {
      if (error.message.length > 0) {
        return error.message;
      }

      return error.name;
    }

    const errorRecord = error as Record<string, ErrorRecordValue>;
    const message = typeof errorRecord.message === 'string' ? errorRecord.message : '';
    if (message.length > 0) {
      return message;
    }

    const name = typeof errorRecord.name === 'string' ? errorRecord.name : '';
    if (name.length > 0) {
      return name;
    }

    try {
      const serialized = JSON.stringify(error);
      if (serialized.length > 0 && serialized !== '{}') {
        return serialized;
      }
    } catch (_jsonError) {}

    return `${error}`;
  }
}
