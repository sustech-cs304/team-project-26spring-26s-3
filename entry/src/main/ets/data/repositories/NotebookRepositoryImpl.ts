import common from '@ohos.app.ability.common';
import { StorageKeys } from '../../common/constants/StorageKeys';
import { IdUtil } from '../../common/utils/IdUtil';
import { TimeUtil } from '../../common/utils/TimeUtil';
import { Notebook, NotebookEntity } from '../../domain/entities/Notebook';
import { NotebookFolder, NotebookFolderEntity } from '../../domain/entities/NotebookFolder';
import { NotebookPage, NotebookPageEntity } from '../../domain/entities/NotebookPage';
import { NotebookPageCanvas, NotebookPageCanvasEntity } from '../../domain/entities/NotebookPageCanvas';
import {
  CreateNotebookFolderRequest,
  CreateNotebookPageRequest,
  CreateNotebookRequest,
  DeleteNotebookPageRequest,
  GetNotebookPageCanvasRequest,
  MoveNotebookToFolderRequest,
  NotebookRepository,
  NotebookSortType,
  ReorderNotebookPagesRequest,
  RenameNotebookRequest
} from '../../domain/repositories/NotebookRepository';
import { FileDataSource } from '../sources/local/FileDataSource';
import { PreferencesDataSource } from '../sources/local/PreferencesDataSource';

export class NotebookRepositoryImpl implements NotebookRepository {
  private static readonly NOTEBOOK_LIST_FILE_PATH: string = 'notebooks/notebook-list.json';
  private static readonly NOTEBOOK_FOLDER_LIST_FILE_PATH: string = 'notebooks/folder-list.json';
  private static readonly NOTEBOOK_PAGE_FILE_MISSING: string = '__notebook_page_file_missing__';
  private static readonly NOTEBOOK_PAGE_CANVAS_FILE_MISSING: string = '__notebook_page_canvas_file_missing__';

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

  async getFolderList(): Promise<NotebookFolder[]> {
    const folderList: NotebookFolder[] = await this.loadFolderList();
    return this.sortFolderList(folderList);
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
      folderId: '',
      createdAt: currentTime,
      updatedAt: currentTime
    };

    notebookList.push(notebook);
    const firstNotebookPage: NotebookPage = this.buildNotebookPage(notebook.id, 0, currentTime);
    await this.persistNotebookList(notebookList);
    await this.persistNotebookPageList(notebook.id, [firstNotebookPage]);
    await this.persistNotebookPageCanvas(this.buildNotebookPageCanvas(firstNotebookPage, currentTime));
    return notebook;
  }

  async createFolder(request: CreateNotebookFolderRequest): Promise<NotebookFolder> {
    const folderList: NotebookFolder[] = await this.loadFolderList();
    const currentTime: number = TimeUtil.now();
    const folder: NotebookFolder = {
      id: IdUtil.createNotebookFolderId(),
      title: NotebookFolderEntity.normalizeTitle(request.title),
      createdAt: currentTime,
      updatedAt: currentTime
    };

    folderList.push(folder);
    await this.persistFolderList(folderList);
    return folder;
  }

  async renameNotebook(request: RenameNotebookRequest): Promise<Notebook | null> {
    const notebookList: Notebook[] = await this.loadNotebookList();

    for (let index: number = 0; index < notebookList.length; index += 1) {
      const currentNotebook: Notebook = notebookList[index];
      if (currentNotebook.id === request.notebookId) {
        const renamedNotebook: Notebook = {
          id: currentNotebook.id,
          title: NotebookEntity.normalizeTitle(request.title),
          folderId: currentNotebook.folderId,
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

  async moveNotebookToFolder(request: MoveNotebookToFolderRequest): Promise<Notebook | null> {
    const targetFolderId: string = NotebookEntity.normalizeFolderId(request.folderId);
    const notebookList: Notebook[] = await this.loadNotebookList();
    const notebookIndex: number = this.findNotebookIndexById(notebookList, request.notebookId);
    if (notebookIndex < 0) {
      return null;
    }

    const folderList: NotebookFolder[] = await this.loadFolderList();
    const targetFolderIndex: number = targetFolderId.length === 0 ? -1 : this.findFolderIndexById(folderList, targetFolderId);
    if (targetFolderId.length > 0 && targetFolderIndex < 0) {
      return null;
    }

    const currentNotebook: Notebook = notebookList[notebookIndex];
    if (currentNotebook.folderId === targetFolderId) {
      return currentNotebook;
    }

    const currentTime: number = TimeUtil.now();
    const movedNotebook: Notebook = {
      id: currentNotebook.id,
      title: currentNotebook.title,
      folderId: targetFolderId,
      createdAt: currentNotebook.createdAt,
      updatedAt: currentTime
    };
    notebookList[notebookIndex] = movedNotebook;
    await this.persistNotebookList(notebookList);

    if (targetFolderIndex >= 0) {
      const targetFolder: NotebookFolder = folderList[targetFolderIndex];
      folderList[targetFolderIndex] = {
        id: targetFolder.id,
        title: targetFolder.title,
        createdAt: targetFolder.createdAt,
        updatedAt: currentTime
      };
      await this.persistFolderList(folderList);
    }

    return movedNotebook;
  }

  async deleteNotebook(notebookId: string): Promise<boolean> {
    const notebookList: Notebook[] = await this.loadNotebookList();
    const notebookPageList: NotebookPage[] = await this.loadNotebookPageList(notebookId);
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

    for (const notebookPage of notebookPageList) {
      await this.fileDataSource.delete(this.buildNotebookPageCanvasFilePath(notebookPage.id));
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

  async getNotebookPageCanvas(request: GetNotebookPageCanvasRequest): Promise<NotebookPageCanvas | null> {
    const notebook: Notebook | null = await this.getNotebookById(request.notebookId);
    if (notebook === null) {
      return null;
    }

    const notebookPageList: NotebookPage[] = await this.loadOrBootstrapNotebookPageList(notebook);
    for (const notebookPage of notebookPageList) {
      if (notebookPage.id === request.pageId) {
        return this.loadOrBootstrapNotebookPageCanvas(notebookPage);
      }
    }

    return null;
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
    await this.persistNotebookPageCanvas(this.buildNotebookPageCanvas(notebookPage, currentTime));

    const notebook: Notebook = notebookList[notebookIndex];
    notebookList[notebookIndex] = {
      id: notebook.id,
      title: notebook.title,
      folderId: notebook.folderId,
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

    await this.fileDataSource.delete(this.buildNotebookPageCanvasFilePath(request.pageId));
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
      folderId: notebook.folderId,
      createdAt: notebook.createdAt,
      updatedAt: currentTime
    };
    await this.persistNotebookList(notebookList);
    return true;
  }

  async reorderNotebookPages(request: ReorderNotebookPagesRequest): Promise<boolean> {
    const notebookList: Notebook[] = await this.loadNotebookList();
    const notebookIndex: number = this.findNotebookIndexById(notebookList, request.notebookId);
    if (notebookIndex < 0) {
      return false;
    }

    const notebook: Notebook = notebookList[notebookIndex];
    const notebookPageList: NotebookPage[] = await this.loadOrBootstrapNotebookPageList(notebook);
    const reorderedNotebookPageList: NotebookPage[] = this.buildReorderedNotebookPageList(
      notebookPageList,
      request.fromIndex,
      request.toIndex
    );

    if (reorderedNotebookPageList.length === 0) {
      return false;
    }

    await this.persistNotebookPageList(request.notebookId, reorderedNotebookPageList);

    const currentTime: number = TimeUtil.now();
    notebookList[notebookIndex] = {
      id: notebook.id,
      title: notebook.title,
      folderId: notebook.folderId,
      createdAt: notebook.createdAt,
      updatedAt: currentTime
    };
    await this.persistNotebookList(notebookList);
    return true;
  }

  async touchNotebookPageUpdatedAt(pageId: string): Promise<boolean> {
    const notebookList: Notebook[] = await this.loadNotebookList();
    if (notebookList.length === 0) {
      return false;
    }

    const currentTime: number = TimeUtil.now();
    for (let notebookIndex: number = 0; notebookIndex < notebookList.length; notebookIndex += 1) {
      const notebook: Notebook = notebookList[notebookIndex];
      const notebookPageList: NotebookPage[] = await this.loadNotebookPageList(notebook.id);

      for (let pageIndex: number = 0; pageIndex < notebookPageList.length; pageIndex += 1) {
        const notebookPage: NotebookPage = notebookPageList[pageIndex];
        if (notebookPage.id !== pageId) {
          continue;
        }

        const updatedNotebookPage: NotebookPage = {
          id: notebookPage.id,
          notebookId: notebookPage.notebookId,
          order: notebookPage.order,
          createdAt: notebookPage.createdAt,
          updatedAt: currentTime,
          templateType: notebookPage.templateType
        };
        notebookPageList[pageIndex] = updatedNotebookPage;
        await this.persistNotebookPageList(notebook.id, notebookPageList);

        const notebookPageCanvas: NotebookPageCanvas = await this.loadOrBootstrapNotebookPageCanvas(updatedNotebookPage);
        await this.persistNotebookPageCanvas({
          pageId: notebookPageCanvas.pageId,
          notebookId: notebookPageCanvas.notebookId,
          width: notebookPageCanvas.width,
          height: notebookPageCanvas.height,
          backgroundColor: notebookPageCanvas.backgroundColor,
          createdAt: notebookPageCanvas.createdAt,
          updatedAt: currentTime
        });

        notebookList[notebookIndex] = {
          id: notebook.id,
          title: notebook.title,
          folderId: notebook.folderId,
          createdAt: notebook.createdAt,
          updatedAt: currentTime
        };
        await this.persistNotebookList(notebookList);
        return true;
      }
    }

    return false;
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

  private async loadFolderList(): Promise<NotebookFolder[]> {
    const preferenceContent: string = await this.preferencesDataSource.getString(StorageKeys.NOTEBOOK_FOLDER_LIST, '');
    const folderListFromPreferences: NotebookFolder[] = this.parseFolderList(preferenceContent);
    if (folderListFromPreferences.length > 0 || preferenceContent.length > 0) {
      return folderListFromPreferences;
    }

    const fileContent: string = await this.fileDataSource.readText(NotebookRepositoryImpl.NOTEBOOK_FOLDER_LIST_FILE_PATH, '');
    const folderListFromFile: NotebookFolder[] = this.parseFolderList(fileContent);

    if (fileContent.length > 0) {
      await this.preferencesDataSource.putString(StorageKeys.NOTEBOOK_FOLDER_LIST, fileContent);
    }

    return folderListFromFile;
  }

  private async persistNotebookList(notebookList: Notebook[]): Promise<void> {
    const content: string = JSON.stringify(notebookList);
    await this.preferencesDataSource.putString(StorageKeys.NOTEBOOK_LIST, content);
    await this.fileDataSource.writeText(NotebookRepositoryImpl.NOTEBOOK_LIST_FILE_PATH, content);
  }

  private async persistFolderList(folderList: NotebookFolder[]): Promise<void> {
    const content: string = JSON.stringify(folderList);
    await this.preferencesDataSource.putString(StorageKeys.NOTEBOOK_FOLDER_LIST, content);
    await this.fileDataSource.writeText(NotebookRepositoryImpl.NOTEBOOK_FOLDER_LIST_FILE_PATH, content);
  }

  private async loadNotebookPageList(notebookId: string): Promise<NotebookPage[]> {
    const fileContent: string = await this.fileDataSource.readText(this.buildNotebookPageListFilePath(notebookId), '[]');
    return this.parseNotebookPageList(notebookId, fileContent);
  }

  private async persistNotebookPageList(notebookId: string, notebookPageList: NotebookPage[]): Promise<void> {
    const content: string = JSON.stringify(notebookPageList);
    await this.fileDataSource.writeText(this.buildNotebookPageListFilePath(notebookId), content);
  }

  private async persistNotebookPageCanvas(notebookPageCanvas: NotebookPageCanvas): Promise<void> {
    const content: string = JSON.stringify(notebookPageCanvas);
    await this.fileDataSource.writeText(this.buildNotebookPageCanvasFilePath(notebookPageCanvas.pageId), content);
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
    await this.persistNotebookPageCanvas(this.buildNotebookPageCanvas(defaultNotebookPageList[0], notebook.createdAt));
    return defaultNotebookPageList;
  }

  private async loadOrBootstrapNotebookPageCanvas(notebookPage: NotebookPage): Promise<NotebookPageCanvas> {
    const fileContent: string = await this.fileDataSource.readText(
      this.buildNotebookPageCanvasFilePath(notebookPage.id),
      NotebookRepositoryImpl.NOTEBOOK_PAGE_CANVAS_FILE_MISSING
    );

    if (fileContent !== NotebookRepositoryImpl.NOTEBOOK_PAGE_CANVAS_FILE_MISSING) {
      return this.parseNotebookPageCanvas(notebookPage, fileContent);
    }

    const notebookPageCanvas: NotebookPageCanvas = this.buildNotebookPageCanvas(notebookPage, notebookPage.createdAt);
    await this.persistNotebookPageCanvas(notebookPageCanvas);
    return notebookPageCanvas;
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
          folderId: NotebookEntity.normalizeFolderId(item.folderId),
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

  private parseFolderList(content: string): NotebookFolder[] {
    if (content.length === 0) {
      return [];
    }

    try {
      const parsedFolderList: NotebookFolder[] = JSON.parse(content) as NotebookFolder[];
      if (!Array.isArray(parsedFolderList)) {
        return [];
      }

      const normalizedFolderList: NotebookFolder[] = [];
      for (const item of parsedFolderList) {
        const folder: NotebookFolder = {
          id: typeof item.id === 'string' ? item.id : IdUtil.createNotebookFolderId(),
          title: NotebookFolderEntity.normalizeTitle(item.title),
          createdAt: TimeUtil.isValidTimestamp(item.createdAt) ? item.createdAt : TimeUtil.now(),
          updatedAt: TimeUtil.isValidTimestamp(item.updatedAt) ? item.updatedAt : TimeUtil.now()
        };
        normalizedFolderList.push(folder);
      }

      return normalizedFolderList;
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

  private parseNotebookPageCanvas(notebookPage: NotebookPage, content: string): NotebookPageCanvas {
    if (content.length === 0) {
      return this.buildNotebookPageCanvas(notebookPage, notebookPage.createdAt);
    }

    try {
      const parsedNotebookPageCanvas: NotebookPageCanvas = JSON.parse(content) as NotebookPageCanvas;
      return {
        pageId: notebookPage.id,
        notebookId: notebookPage.notebookId,
        width: NotebookPageCanvasEntity.normalizeDimension(
          parsedNotebookPageCanvas.width,
          NotebookPageCanvasEntity.DEFAULT_WIDTH
        ),
        height: NotebookPageCanvasEntity.normalizeDimension(
          parsedNotebookPageCanvas.height,
          NotebookPageCanvasEntity.DEFAULT_HEIGHT
        ),
        backgroundColor: NotebookPageCanvasEntity.normalizeBackgroundColor(parsedNotebookPageCanvas.backgroundColor),
        createdAt: TimeUtil.isValidTimestamp(parsedNotebookPageCanvas.createdAt) ? parsedNotebookPageCanvas.createdAt : notebookPage.createdAt,
        updatedAt: TimeUtil.isValidTimestamp(parsedNotebookPageCanvas.updatedAt) ? parsedNotebookPageCanvas.updatedAt : notebookPage.updatedAt
      };
    } catch (_error) {
      return this.buildNotebookPageCanvas(notebookPage, notebookPage.createdAt);
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

  private sortFolderList(folderList: NotebookFolder[]): NotebookFolder[] {
    const sortedFolderList: NotebookFolder[] = folderList.slice();
    sortedFolderList.sort((left: NotebookFolder, right: NotebookFolder): number => {
      return left.title.localeCompare(right.title);
    });
    return sortedFolderList;
  }

  private buildReorderedNotebookPageList(
    notebookPageList: NotebookPage[],
    fromIndex: number,
    toIndex: number
  ): NotebookPage[] {
    if (fromIndex < 0 || fromIndex >= notebookPageList.length || toIndex < 0 || notebookPageList.length === 0) {
      return [];
    }

    const normalizedToIndex: number = Math.min(toIndex, notebookPageList.length - 1);
    const reorderedNotebookPageList: NotebookPage[] = notebookPageList.slice();
    const movedNotebookPageList: NotebookPage[] = reorderedNotebookPageList.splice(fromIndex, 1);
    if (movedNotebookPageList.length === 0) {
      return [];
    }

    reorderedNotebookPageList.splice(normalizedToIndex, 0, movedNotebookPageList[0]);
    return reorderedNotebookPageList.map((notebookPage: NotebookPage, index: number): NotebookPage => {
      return {
        id: notebookPage.id,
        notebookId: notebookPage.notebookId,
        order: index,
        createdAt: notebookPage.createdAt,
        updatedAt: notebookPage.updatedAt,
        templateType: notebookPage.templateType
      };
    });
  }

  private buildNotebookPageListFilePath(notebookId: string): string {
    return `notebooks/pages/${notebookId}.json`;
  }

  private buildNotebookPageCanvasFilePath(pageId: string): string {
    return `notebooks/canvases/${pageId}.json`;
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

  private buildNotebookPageCanvas(notebookPage: NotebookPage, timestamp: number): NotebookPageCanvas {
    return {
      pageId: notebookPage.id,
      notebookId: notebookPage.notebookId,
      width: NotebookPageCanvasEntity.DEFAULT_WIDTH,
      height: NotebookPageCanvasEntity.DEFAULT_HEIGHT,
      backgroundColor: NotebookPageCanvasEntity.DEFAULT_BACKGROUND_COLOR,
      createdAt: timestamp,
      updatedAt: timestamp
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

  private findFolderIndexById(folderList: NotebookFolder[], folderId: string): number {
    for (let index: number = 0; index < folderList.length; index += 1) {
      if (folderList[index].id === folderId) {
        return index;
      }
    }

    return -1;
  }
}
