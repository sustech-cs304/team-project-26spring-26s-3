import common from '@ohos.app.ability.common';
import { StorageKeys } from '../../common/constants/StorageKeys';
import { IdUtil } from '../../common/utils/IdUtil';
import { TimeUtil } from '../../common/utils/TimeUtil';
import { Notebook, NotebookEntity } from '../../domain/entities/Notebook';
import { NotebookPage, NotebookPageEntity } from '../../domain/entities/NotebookPage';
import {
  CreateNotebookPageRequest,
  CreateNotebookRequest,
  DeleteNotebookPageRequest,
  NotebookRepository,
  NotebookSortType,
  RenameNotebookRequest
} from '../../domain/repositories/NotebookRepository';
import { FileDataSource } from '../sources/local/FileDataSource';
import { PreferencesDataSource } from '../sources/local/PreferencesDataSource';

export class NotebookRepositoryImpl implements NotebookRepository {
  private static readonly NOTEBOOK_LIST_FILE_PATH: string = 'notebooks/notebook-list.json';
  private static readonly NOTEBOOK_PAGE_FILE_MISSING: string = '__notebook_page_file_missing__';

  private readonly preferencesDataSource: PreferencesDataSource;
  private readonly fileDataSource: FileDataSource;

  constructor(
    context: common.Context,
    preferencesDataSource?: PreferencesDataSource,
    fileDataSource?: FileDataSource
  ) {
    this.preferencesDataSource = preferencesDataSource ?? new PreferencesDataSource(context);
    this.fileDataSource = fileDataSource ?? new FileDataSource(context);
  }

  async getNotebookList(): Promise<Notebook[]> {
    const notebookList: Notebook[] = await this.loadNotebookList();
    const sortType: NotebookSortType = await this.getSortType();
    return this.sortNotebookList(notebookList, sortType);
  }

  async getNotebookById(notebookId: string): Promise<Notebook | null> {
    const notebookList: Notebook[] = await this.loadNotebookList();
    for (const notebook of notebookList) {
      if (notebook.id === notebookId) {
        return notebook;
      }
    }
    return null;
  }

  async createNotebook(request: CreateNotebookRequest): Promise<Notebook> {
    const notebookList: Notebook[] = await this.loadNotebookList();
    const currentTime: number = TimeUtil.now();
    const notebook: Notebook = {
      id: IdUtil.createNotebookId(),
      title: NotebookEntity.normalizeTitle(request.title),
      createdAt: currentTime,
      updatedAt: currentTime
    };

    notebookList.push(notebook);
    await this.persistNotebookList(notebookList);
    await this.persistNotebookPageList(notebook.id, [
      this.buildNotebookPage(notebook.id, 0, currentTime)
    ]);
    return notebook;
  }

  async renameNotebook(request: RenameNotebookRequest): Promise<Notebook | null> {
    const notebookList: Notebook[] = await this.loadNotebookList();

    for (let index: number = 0; index < notebookList.length; index += 1) {
      const currentNotebook: Notebook = notebookList[index];
      if (currentNotebook.id === request.notebookId) {
        const renamedNotebook: Notebook = {
          id: currentNotebook.id,
          title: NotebookEntity.normalizeTitle(request.title),
          createdAt: currentNotebook.createdAt,
          updatedAt: TimeUtil.now()
        };

        notebookList[index] = renamedNotebook;
        await this.persistNotebookList(notebookList);
        return renamedNotebook;
      }
    }

    return null;
  }

  async deleteNotebook(notebookId: string): Promise<boolean> {
    const notebookList: Notebook[] = await this.loadNotebookList();
    const filteredNotebookList: Notebook[] = [];
    let hasDeleted: boolean = false;

    for (const notebook of notebookList) {
      if (notebook.id === notebookId) {
        hasDeleted = true;
        continue;
      }
      filteredNotebookList.push(notebook);
    }

    if (!hasDeleted) {
      return false;
    }

    await this.fileDataSource.delete(this.buildNotebookPageListFilePath(notebookId));
    await this.persistNotebookList(filteredNotebookList);
    return true;
  }

  async getNotebookPages(notebookId: string): Promise<NotebookPage[]> {
    const notebook: Notebook | null = await this.getNotebookById(notebookId);
    if (notebook === null) {
      return [];
    }

    return this.loadOrBootstrapNotebookPageList(notebook);
  }

  async createNotebookPage(request: CreateNotebookPageRequest): Promise<NotebookPage | null> {
    const notebookList: Notebook[] = await this.loadNotebookList();
    const notebookIndex: number = this.findNotebookIndexById(notebookList, request.notebookId);
    if (notebookIndex < 0) {
      return null;
    }

    const notebookPageList: NotebookPage[] = await this.loadNotebookPageList(request.notebookId);
    const currentTime: number = TimeUtil.now();
    const notebookPage: NotebookPage = this.buildNotebookPage(
      request.notebookId,
      notebookPageList.length,
      currentTime
    );

    notebookPageList.push(notebookPage);
    await this.persistNotebookPageList(request.notebookId, notebookPageList);

    const notebook: Notebook = notebookList[notebookIndex];
    notebookList[notebookIndex] = {
      id: notebook.id,
      title: notebook.title,
      createdAt: notebook.createdAt,
      updatedAt: currentTime
    };
    await this.persistNotebookList(notebookList);
    return notebookPage;
  }

  async deleteNotebookPage(request: DeleteNotebookPageRequest): Promise<boolean> {
    const notebookList: Notebook[] = await this.loadNotebookList();
    const notebookIndex: number = this.findNotebookIndexById(notebookList, request.notebookId);
    if (notebookIndex < 0) {
      return false;
    }

    const notebookPageList: NotebookPage[] = await this.loadNotebookPageList(request.notebookId);
    const filteredNotebookPageList: NotebookPage[] = [];
    let hasDeleted: boolean = false;

    for (const notebookPage of notebookPageList) {
      if (notebookPage.id === request.pageId) {
        hasDeleted = true;
        continue;
      }
      filteredNotebookPageList.push(notebookPage);
    }

    if (!hasDeleted) {
      return false;
    }

    const reorderedNotebookPageList: NotebookPage[] = filteredNotebookPageList.map(
      (notebookPage: NotebookPage, index: number): NotebookPage => {
        return {
          id: notebookPage.id,
          notebookId: notebookPage.notebookId,
          order: index,
          createdAt: notebookPage.createdAt,
          updatedAt: notebookPage.updatedAt,
          templateType: notebookPage.templateType
        };
      }
    );
    await this.persistNotebookPageList(request.notebookId, reorderedNotebookPageList);

    const currentTime: number = TimeUtil.now();
    const notebook: Notebook = notebookList[notebookIndex];
    notebookList[notebookIndex] = {
      id: notebook.id,
      title: notebook.title,
      createdAt: notebook.createdAt,
      updatedAt: currentTime
    };
    await this.persistNotebookList(notebookList);
    return true;
  }

  async getSortType(): Promise<NotebookSortType> {
    const storedSortType: string = await this.preferencesDataSource.getString(
      StorageKeys.NOTEBOOK_SORT_TYPE,
      NotebookSortType.UPDATED_DESC
    );

    if (storedSortType === NotebookSortType.CREATED_DESC) {
      return NotebookSortType.CREATED_DESC;
    }

    if (storedSortType === NotebookSortType.TITLE_ASC) {
      return NotebookSortType.TITLE_ASC;
    }

    return NotebookSortType.UPDATED_DESC;
  }

  async saveSortType(sortType: NotebookSortType): Promise<void> {
    await this.preferencesDataSource.putString(StorageKeys.NOTEBOOK_SORT_TYPE, sortType);
  }

  private async loadNotebookList(): Promise<Notebook[]> {
    const preferenceContent: string = await this.preferencesDataSource.getString(StorageKeys.NOTEBOOK_LIST, '');
    const notebookListFromPreferences: Notebook[] = this.parseNotebookList(preferenceContent);
    if (notebookListFromPreferences.length > 0 || preferenceContent.length > 0) {
      return notebookListFromPreferences;
    }

    const fileContent: string = await this.fileDataSource.readText(NotebookRepositoryImpl.NOTEBOOK_LIST_FILE_PATH, '');
    const notebookListFromFile: Notebook[] = this.parseNotebookList(fileContent);

    if (fileContent.length > 0) {
      await this.preferencesDataSource.putString(StorageKeys.NOTEBOOK_LIST, fileContent);
    }

    return notebookListFromFile;
  }

  private async persistNotebookList(notebookList: Notebook[]): Promise<void> {
    const content: string = JSON.stringify(notebookList);
    await this.preferencesDataSource.putString(StorageKeys.NOTEBOOK_LIST, content);
    await this.fileDataSource.writeText(NotebookRepositoryImpl.NOTEBOOK_LIST_FILE_PATH, content);
  }

  private async loadNotebookPageList(notebookId: string): Promise<NotebookPage[]> {
    const fileContent: string = await this.fileDataSource.readText(this.buildNotebookPageListFilePath(notebookId), '[]');
    return this.parseNotebookPageList(notebookId, fileContent);
  }

  private async persistNotebookPageList(notebookId: string, notebookPageList: NotebookPage[]): Promise<void> {
    const content: string = JSON.stringify(notebookPageList);
    await this.fileDataSource.writeText(this.buildNotebookPageListFilePath(notebookId), content);
  }

  private async loadOrBootstrapNotebookPageList(notebook: Notebook): Promise<NotebookPage[]> {
    const filePath: string = this.buildNotebookPageListFilePath(notebook.id);
    const fileContent: string = await this.fileDataSource.readText(
      filePath,
      NotebookRepositoryImpl.NOTEBOOK_PAGE_FILE_MISSING
    );

    if (fileContent !== NotebookRepositoryImpl.NOTEBOOK_PAGE_FILE_MISSING) {
      return this.parseNotebookPageList(notebook.id, fileContent);
    }

    const defaultNotebookPageList: NotebookPage[] = [
      this.buildNotebookPage(notebook.id, 0, notebook.createdAt)
    ];
    await this.persistNotebookPageList(notebook.id, defaultNotebookPageList);
    return defaultNotebookPageList;
  }

  private parseNotebookList(content: string): Notebook[] {
    if (content.length === 0) {
      return [];
    }

    try {
      const parsedNotebookList: Notebook[] = JSON.parse(content) as Notebook[];
      if (!Array.isArray(parsedNotebookList)) {
        return [];
      }

      const normalizedNotebookList: Notebook[] = [];
      for (const item of parsedNotebookList) {
        const notebook: Notebook = {
          id: item.id,
          title: NotebookEntity.normalizeTitle(item.title),
          createdAt: TimeUtil.isValidTimestamp(item.createdAt) ? item.createdAt : TimeUtil.now(),
          updatedAt: TimeUtil.isValidTimestamp(item.updatedAt) ? item.updatedAt : TimeUtil.now()
        };
        normalizedNotebookList.push(notebook);
      }
      return normalizedNotebookList;
    } catch (_error) {
      return [];
    }
  }

  private parseNotebookPageList(notebookId: string, content: string): NotebookPage[] {
    if (content.length === 0) {
      return [];
    }

    try {
      const parsedNotebookPageList: NotebookPage[] = JSON.parse(content) as NotebookPage[];
      if (!Array.isArray(parsedNotebookPageList)) {
        return [];
      }

      const normalizedNotebookPageList: NotebookPage[] = [];
      for (let index: number = 0; index < parsedNotebookPageList.length; index += 1) {
        const item: NotebookPage = parsedNotebookPageList[index];
        const notebookPage: NotebookPage = {
          id: typeof item.id === 'string' && item.id.length > 0 ? item.id : IdUtil.createNotebookPageId(),
          notebookId: notebookId,
          order: NotebookPageEntity.normalizeOrder(item.order, index),
          createdAt: TimeUtil.isValidTimestamp(item.createdAt) ? item.createdAt : TimeUtil.now(),
          updatedAt: TimeUtil.isValidTimestamp(item.updatedAt) ? item.updatedAt : TimeUtil.now(),
          templateType: NotebookPageEntity.normalizeTemplateType(item.templateType)
        };
        normalizedNotebookPageList.push(notebookPage);
      }

      normalizedNotebookPageList.sort((left: NotebookPage, right: NotebookPage): number => {
        return left.order - right.order;
      });

      return normalizedNotebookPageList.map((page: NotebookPage, index: number): NotebookPage => {
        return {
          id: page.id,
          notebookId: page.notebookId,
          order: index,
          createdAt: page.createdAt,
          updatedAt: page.updatedAt,
          templateType: page.templateType
        };
      });
    } catch (_error) {
      return [];
    }
  }

  private sortNotebookList(notebookList: Notebook[], sortType: NotebookSortType): Notebook[] {
    const sortedNotebookList: Notebook[] = notebookList.slice();

    sortedNotebookList.sort((left: Notebook, right: Notebook): number => {
      if (sortType === NotebookSortType.CREATED_DESC) {
        return right.createdAt - left.createdAt;
      }

      if (sortType === NotebookSortType.TITLE_ASC) {
        return left.title.localeCompare(right.title);
      }

      return right.updatedAt - left.updatedAt;
    });

    return sortedNotebookList;
  }

  private buildNotebookPageListFilePath(notebookId: string): string {
    return `notebooks/pages/${notebookId}.json`;
  }

  private buildNotebookPage(notebookId: string, order: number, timestamp: number): NotebookPage {
    return {
      id: IdUtil.createNotebookPageId(),
      notebookId: notebookId,
      order: order,
      createdAt: timestamp,
      updatedAt: timestamp,
      templateType: NotebookPageEntity.DEFAULT_TEMPLATE_TYPE
    };
  }

  private findNotebookIndexById(notebookList: Notebook[], notebookId: string): number {
    for (let index: number = 0; index < notebookList.length; index += 1) {
      if (notebookList[index].id === notebookId) {
        return index;
      }
    }
    return -1;
  }
}
