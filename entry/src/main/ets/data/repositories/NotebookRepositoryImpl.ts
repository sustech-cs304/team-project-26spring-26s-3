import common from '@ohos.app.ability.common';
import { StorageKeys } from '../../common/constants/StorageKeys';
import { IdUtil } from '../../common/utils/IdUtil';
import { TimeUtil } from '../../common/utils/TimeUtil';
import { Notebook, NotebookEntity } from '../../domain/entities/Notebook';
import { NotebookFolder, NotebookFolderEntity } from '../../domain/entities/NotebookFolder';
import { NotebookPage, NotebookPageEntity, NotebookPageTemplateType } from '../../domain/entities/NotebookPage';
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
  RenameNotebookFolderRequest,
  RenameNotebookRequest,
  ToggleNotebookFavoriteRequest,
  UpdateNotebookCoverRequest,
  UpdateNotebookFolderColorRequest,
  UpdateNotebookTagsRequest,
  UpdateNotebookPageCanvasRequest,
  UpdateNotebookPageTemplateRequest
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
    const usedCoverColorList: string[] = [];
    for (const existingNotebook of notebookList) {
      const normalizedColor: string = NotebookEntity.normalizeCoverColor(existingNotebook.coverColor);
      if (!usedCoverColorList.includes(normalizedColor)) {
        usedCoverColorList.push(normalizedColor);
      }
    }
    let coverColor: string = NotebookEntity.DEFAULT_COVER_COLOR;
    const availableCoverColorList: string[] = [];
    for (const color of NotebookEntity.COVER_COLOR_PALETTE) {
      if (!usedCoverColorList.includes(color)) {
        availableCoverColorList.push(color);
      }
    }
    if (availableCoverColorList.length > 0) {
      const randomIndex: number = Math.floor(Math.random() * availableCoverColorList.length);
      coverColor = availableCoverColorList[randomIndex];
    } else {
      const randomIndex: number = Math.floor(Math.random() * NotebookEntity.COVER_COLOR_PALETTE.length);
      coverColor = NotebookEntity.COVER_COLOR_PALETTE[randomIndex];
    }

    const notebook: Notebook = {
      id: IdUtil.createNotebookId(),
      title: NotebookEntity.normalizeTitle(request.title),
      folderId: '',
      createdAt: currentTime,
      updatedAt: currentTime,
      coverColor: coverColor,
      coverImageUri: '',
      pageCount: 1,
      isFavorite: false,
      tags: [],
      isDeleted: false,
      deletedAt: 0,
      lastOpenedAt: 0
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
      color: NotebookFolderEntity.normalizeColor(request.color),
      createdAt: currentTime,
      updatedAt: currentTime
    };

    folderList.push(folder);
    await this.persistFolderList(folderList);
    return folder;
  }

  async renameFolder(request: RenameNotebookFolderRequest): Promise<NotebookFolder | null> {
    const folderList: NotebookFolder[] = await this.loadFolderList();
    const folderIndex: number = this.findFolderIndexById(folderList, request.folderId);
    if (folderIndex < 0) {
      return null;
    }

    const currentFolder: NotebookFolder = folderList[folderIndex];
    const updatedFolder: NotebookFolder = {
      id: currentFolder.id,
      title: NotebookFolderEntity.normalizeTitle(request.title),
      color: NotebookFolderEntity.normalizeColor(currentFolder.color),
      createdAt: currentFolder.createdAt,
      updatedAt: currentFolder.updatedAt
    };
    folderList[folderIndex] = updatedFolder;
    await this.persistFolderList(folderList);
    return updatedFolder;
  }

  async updateFolderColor(request: UpdateNotebookFolderColorRequest): Promise<NotebookFolder | null> {
    const folderList: NotebookFolder[] = await this.loadFolderList();
    const folderIndex: number = this.findFolderIndexById(folderList, request.folderId);
    if (folderIndex < 0) {
      return null;
    }

    const currentFolder: NotebookFolder = folderList[folderIndex];
    const updatedFolder: NotebookFolder = {
      id: currentFolder.id,
      title: currentFolder.title,
      color: NotebookFolderEntity.normalizeColor(request.color),
      createdAt: currentFolder.createdAt,
      updatedAt: currentFolder.updatedAt
    };
    folderList[folderIndex] = updatedFolder;
    await this.persistFolderList(folderList);
    return updatedFolder;
  }

  async deleteFolder(folderId: string): Promise<boolean> {
    const folderList: NotebookFolder[] = await this.loadFolderList();
    const folderIndex: number = this.findFolderIndexById(folderList, folderId);
    if (folderIndex < 0) {
      return false;
    }

    const nextFolderList: NotebookFolder[] = [];
    for (let index: number = 0; index < folderList.length; index += 1) {
      if (index !== folderIndex) {
        nextFolderList.push(folderList[index]);
      }
    }

    const notebookList: Notebook[] = await this.loadNotebookList();
    const nextNotebookList: Notebook[] = [];
    const currentTime: number = TimeUtil.now();
    let hasNotebookMovedOut: boolean = false;
    for (const notebook of notebookList) {
      if (notebook.folderId === folderId) {
        hasNotebookMovedOut = true;
        nextNotebookList.push({
          id: notebook.id,
          title: notebook.title,
          folderId: '',
          createdAt: notebook.createdAt,
          updatedAt: currentTime,
          coverColor: NotebookEntity.normalizeCoverColor(notebook.coverColor),
          coverImageUri: NotebookEntity.normalizeCoverImageUri(notebook.coverImageUri),
          pageCount: NotebookEntity.normalizePageCount(notebook.pageCount),
          isFavorite: notebook.isFavorite === true,
          tags: this.normalizeTags(notebook.tags),
          isDeleted: notebook.isDeleted === true,
          deletedAt: this.normalizeTimestamp(notebook.deletedAt),
          lastOpenedAt: this.normalizeTimestamp(notebook.lastOpenedAt)
        });
      } else {
        nextNotebookList.push(notebook);
      }
    }

    await this.persistFolderList(nextFolderList);
    if (hasNotebookMovedOut) {
      await this.persistNotebookList(nextNotebookList);
    }
    return true;
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
          updatedAt: TimeUtil.now(),
          coverColor: NotebookEntity.normalizeCoverColor(currentNotebook.coverColor),
          coverImageUri: NotebookEntity.normalizeCoverImageUri(currentNotebook.coverImageUri),
          pageCount: NotebookEntity.normalizePageCount(currentNotebook.pageCount),
          isFavorite: currentNotebook.isFavorite === true,
          tags: this.normalizeTags(currentNotebook.tags),
          isDeleted: currentNotebook.isDeleted === true,
          deletedAt: this.normalizeTimestamp(currentNotebook.deletedAt),
          lastOpenedAt: this.normalizeTimestamp(currentNotebook.lastOpenedAt)
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
      updatedAt: currentTime,
      coverColor: NotebookEntity.normalizeCoverColor(currentNotebook.coverColor),
      coverImageUri: NotebookEntity.normalizeCoverImageUri(currentNotebook.coverImageUri),
      pageCount: NotebookEntity.normalizePageCount(currentNotebook.pageCount),
      isFavorite: currentNotebook.isFavorite === true,
      tags: this.normalizeTags(currentNotebook.tags),
      isDeleted: currentNotebook.isDeleted === true,
      deletedAt: this.normalizeTimestamp(currentNotebook.deletedAt),
      lastOpenedAt: this.normalizeTimestamp(currentNotebook.lastOpenedAt)
    };
    notebookList[notebookIndex] = movedNotebook;
    await this.persistNotebookList(notebookList);

    if (targetFolderIndex >= 0) {
      const targetFolder: NotebookFolder = folderList[targetFolderIndex];
      folderList[targetFolderIndex] = {
        id: targetFolder.id,
        title: targetFolder.title,
        color: NotebookFolderEntity.normalizeColor(targetFolder.color),
        createdAt: targetFolder.createdAt,
        updatedAt: currentTime
      };
    }
    if (currentNotebook.folderId.length > 0) {
      const previousFolderIndex: number = this.findFolderIndexById(folderList, currentNotebook.folderId);
      if (previousFolderIndex >= 0) {
        const previousFolder: NotebookFolder = folderList[previousFolderIndex];
        folderList[previousFolderIndex] = {
          id: previousFolder.id,
          title: previousFolder.title,
          color: NotebookFolderEntity.normalizeColor(previousFolder.color),
          createdAt: previousFolder.createdAt,
          updatedAt: currentTime
        };
      }
    }
    await this.persistFolderList(folderList);

    return movedNotebook;
  }

  async toggleNotebookFavorite(request: ToggleNotebookFavoriteRequest): Promise<Notebook | null> {
    const notebookList: Notebook[] = await this.loadNotebookList();
    const notebookIndex: number = this.findNotebookIndexById(notebookList, request.notebookId);
    if (notebookIndex < 0) {
      return null;
    }

    const notebook: Notebook = notebookList[notebookIndex];
    const updatedNotebook: Notebook = {
      id: notebook.id,
      title: notebook.title,
      folderId: notebook.folderId,
      createdAt: notebook.createdAt,
      updatedAt: TimeUtil.now(),
      coverColor: NotebookEntity.normalizeCoverColor(notebook.coverColor),
      coverImageUri: NotebookEntity.normalizeCoverImageUri(notebook.coverImageUri),
      pageCount: NotebookEntity.normalizePageCount(notebook.pageCount),
      isFavorite: request.isFavorite,
      tags: this.normalizeTags(notebook.tags),
      isDeleted: notebook.isDeleted === true,
      deletedAt: this.normalizeTimestamp(notebook.deletedAt),
      lastOpenedAt: this.normalizeTimestamp(notebook.lastOpenedAt)
    };
    notebookList[notebookIndex] = updatedNotebook;
    await this.persistNotebookList(notebookList);
    return updatedNotebook;
  }

  async updateNotebookTags(request: UpdateNotebookTagsRequest): Promise<Notebook | null> {
    const notebookList: Notebook[] = await this.loadNotebookList();
    const notebookIndex: number = this.findNotebookIndexById(notebookList, request.notebookId);
    if (notebookIndex < 0) {
      return null;
    }

    const notebook: Notebook = notebookList[notebookIndex];
    const updatedNotebook: Notebook = {
      id: notebook.id,
      title: notebook.title,
      folderId: notebook.folderId,
      createdAt: notebook.createdAt,
      updatedAt: TimeUtil.now(),
      coverColor: NotebookEntity.normalizeCoverColor(notebook.coverColor),
      coverImageUri: NotebookEntity.normalizeCoverImageUri(notebook.coverImageUri),
      pageCount: NotebookEntity.normalizePageCount(notebook.pageCount),
      isFavorite: notebook.isFavorite === true,
      tags: this.normalizeTags(request.tags),
      isDeleted: notebook.isDeleted === true,
      deletedAt: this.normalizeTimestamp(notebook.deletedAt),
      lastOpenedAt: this.normalizeTimestamp(notebook.lastOpenedAt)
    };
    notebookList[notebookIndex] = updatedNotebook;
    await this.persistNotebookList(notebookList);
    return updatedNotebook;
  }

  async updateNotebookCover(request: UpdateNotebookCoverRequest): Promise<Notebook | null> {
    const notebookList: Notebook[] = await this.loadNotebookList();
    const notebookIndex: number = this.findNotebookIndexById(notebookList, request.notebookId);
    if (notebookIndex < 0) {
      return null;
    }

    const notebook: Notebook = notebookList[notebookIndex];
    const updatedNotebook: Notebook = {
      id: notebook.id,
      title: notebook.title,
      folderId: notebook.folderId,
      createdAt: notebook.createdAt,
      updatedAt: TimeUtil.now(),
      coverColor: typeof request.coverColor === 'string' ?
        NotebookEntity.normalizeCoverColor(request.coverColor) :
        NotebookEntity.normalizeCoverColor(notebook.coverColor),
      coverImageUri: NotebookEntity.normalizeCoverImageUri(request.coverImageUri),
      pageCount: NotebookEntity.normalizePageCount(notebook.pageCount),
      isFavorite: notebook.isFavorite === true,
      tags: this.normalizeTags(notebook.tags),
      isDeleted: notebook.isDeleted === true,
      deletedAt: this.normalizeTimestamp(notebook.deletedAt),
      lastOpenedAt: this.normalizeTimestamp(notebook.lastOpenedAt)
    };
    notebookList[notebookIndex] = updatedNotebook;
    await this.persistNotebookList(notebookList);
    return updatedNotebook;
  }

  async touchNotebookLastOpened(notebookId: string): Promise<Notebook | null> {
    const notebookList: Notebook[] = await this.loadNotebookList();
    const notebookIndex: number = this.findNotebookIndexById(notebookList, notebookId);
    if (notebookIndex < 0) {
      return null;
    }

    const notebook: Notebook = notebookList[notebookIndex];
    const currentTime: number = TimeUtil.now();
    const updatedNotebook: Notebook = {
      id: notebook.id,
      title: notebook.title,
      folderId: notebook.folderId,
      createdAt: notebook.createdAt,
      updatedAt: currentTime,
      coverColor: NotebookEntity.normalizeCoverColor(notebook.coverColor),
      coverImageUri: NotebookEntity.normalizeCoverImageUri(notebook.coverImageUri),
      pageCount: NotebookEntity.normalizePageCount(notebook.pageCount),
      isFavorite: notebook.isFavorite === true,
      tags: this.normalizeTags(notebook.tags),
      isDeleted: notebook.isDeleted === true,
      deletedAt: this.normalizeTimestamp(notebook.deletedAt),
      lastOpenedAt: currentTime
    };
    notebookList[notebookIndex] = updatedNotebook;
    await this.persistNotebookList(notebookList);
    return updatedNotebook;
  }

  async restoreNotebook(notebookId: string): Promise<boolean> {
    const notebookList: Notebook[] = await this.loadNotebookList();
    const notebookIndex: number = this.findNotebookIndexById(notebookList, notebookId);
    if (notebookIndex < 0) {
      return false;
    }

    const notebook: Notebook = notebookList[notebookIndex];
    const restoredNotebook: Notebook = {
      id: notebook.id,
      title: notebook.title,
      folderId: notebook.folderId,
      createdAt: notebook.createdAt,
      updatedAt: TimeUtil.now(),
      coverColor: NotebookEntity.normalizeCoverColor(notebook.coverColor),
      coverImageUri: NotebookEntity.normalizeCoverImageUri(notebook.coverImageUri),
      pageCount: NotebookEntity.normalizePageCount(notebook.pageCount),
      isFavorite: notebook.isFavorite === true,
      tags: this.normalizeTags(notebook.tags),
      isDeleted: false,
      deletedAt: 0,
      lastOpenedAt: this.normalizeTimestamp(notebook.lastOpenedAt)
    };
    notebookList[notebookIndex] = restoredNotebook;
    await this.persistNotebookList(notebookList);
    if (restoredNotebook.folderId.length > 0) {
      await this.touchFolderUpdatedAt(restoredNotebook.folderId, TimeUtil.now());
    }
    return true;
  }

  async purgeNotebook(notebookId: string): Promise<boolean> {
    const notebookList: Notebook[] = await this.loadNotebookList();
    let removedFolderId: string = '';
    const notebookPageList: NotebookPage[] = await this.loadNotebookPageList(notebookId);
    const filteredNotebookList: Notebook[] = [];
    let hasDeleted: boolean = false;

    for (const notebook of notebookList) {
      if (notebook.id === notebookId) {
        hasDeleted = true;
        removedFolderId = notebook.folderId;
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
    if (removedFolderId.length > 0) {
      await this.touchFolderUpdatedAt(removedFolderId, TimeUtil.now());
    }
    return true;
  }

  async deleteNotebook(notebookId: string): Promise<boolean> {
    const notebookList: Notebook[] = await this.loadNotebookList();
    const notebookIndex: number = this.findNotebookIndexById(notebookList, notebookId);
    if (notebookIndex < 0) {
      return false;
    }

    const notebook: Notebook = notebookList[notebookIndex];
    const deletedNotebook: Notebook = {
      id: notebook.id,
      title: notebook.title,
      folderId: notebook.folderId,
      createdAt: notebook.createdAt,
      updatedAt: TimeUtil.now(),
      coverColor: NotebookEntity.normalizeCoverColor(notebook.coverColor),
      coverImageUri: NotebookEntity.normalizeCoverImageUri(notebook.coverImageUri),
      pageCount: NotebookEntity.normalizePageCount(notebook.pageCount),
      isFavorite: notebook.isFavorite === true,
      tags: this.normalizeTags(notebook.tags),
      isDeleted: true,
      deletedAt: TimeUtil.now(),
      lastOpenedAt: this.normalizeTimestamp(notebook.lastOpenedAt)
    };
    notebookList[notebookIndex] = deletedNotebook;
    await this.persistNotebookList(notebookList);
    if (deletedNotebook.folderId.length > 0) {
      await this.touchFolderUpdatedAt(deletedNotebook.folderId, TimeUtil.now());
    }
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
      updatedAt: currentTime,
      coverColor: NotebookEntity.normalizeCoverColor(notebook.coverColor),
      coverImageUri: NotebookEntity.normalizeCoverImageUri(notebook.coverImageUri),
      pageCount: NotebookEntity.normalizePageCount(notebook.pageCount) + 1,
      isFavorite: notebook.isFavorite === true,
      tags: this.normalizeTags(notebook.tags),
      isDeleted: notebook.isDeleted === true,
      deletedAt: this.normalizeTimestamp(notebook.deletedAt),
      lastOpenedAt: this.normalizeTimestamp(notebook.lastOpenedAt)
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
      updatedAt: currentTime,
      coverColor: NotebookEntity.normalizeCoverColor(notebook.coverColor),
      coverImageUri: NotebookEntity.normalizeCoverImageUri(notebook.coverImageUri),
      pageCount: Math.max(1, NotebookEntity.normalizePageCount(notebook.pageCount) - 1),
      isFavorite: notebook.isFavorite === true,
      tags: this.normalizeTags(notebook.tags),
      isDeleted: notebook.isDeleted === true,
      deletedAt: this.normalizeTimestamp(notebook.deletedAt),
      lastOpenedAt: this.normalizeTimestamp(notebook.lastOpenedAt)
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
      updatedAt: currentTime,
      coverColor: NotebookEntity.normalizeCoverColor(notebook.coverColor),
      coverImageUri: NotebookEntity.normalizeCoverImageUri(notebook.coverImageUri),
      pageCount: NotebookEntity.normalizePageCount(notebook.pageCount),
      isFavorite: notebook.isFavorite === true,
      tags: this.normalizeTags(notebook.tags),
      isDeleted: notebook.isDeleted === true,
      deletedAt: this.normalizeTimestamp(notebook.deletedAt),
      lastOpenedAt: this.normalizeTimestamp(notebook.lastOpenedAt)
    };
    await this.persistNotebookList(notebookList);
    return true;
  }

  async updateNotebookPageTemplate(request: UpdateNotebookPageTemplateRequest): Promise<NotebookPage | null> {
    const notebookList: Notebook[] = await this.loadNotebookList();
    const notebookIndex: number = this.findNotebookIndexById(notebookList, request.notebookId);
    if (notebookIndex < 0) {
      return null;
    }

    const notebook: Notebook = notebookList[notebookIndex];
    const notebookPageList: NotebookPage[] = await this.loadOrBootstrapNotebookPageList(notebook);
    const pageIndex: number = this.findNotebookPageIndexById(notebookPageList, request.pageId);
    if (pageIndex < 0) {
      return null;
    }

    const targetTemplateType: NotebookPageTemplateType = NotebookPageEntity.normalizeTemplateType(request.templateType);
    const currentNotebookPage: NotebookPage = notebookPageList[pageIndex];
    if (currentNotebookPage.templateType === targetTemplateType) {
      return currentNotebookPage;
    }

    const currentTime: number = TimeUtil.now();
    const updatedNotebookPage: NotebookPage = {
      id: currentNotebookPage.id,
      notebookId: currentNotebookPage.notebookId,
      order: currentNotebookPage.order,
      createdAt: currentNotebookPage.createdAt,
      updatedAt: currentTime,
      templateType: targetTemplateType,
      sourceFileUri: currentNotebookPage.sourceFileUri,
      sourceFileType: currentNotebookPage.sourceFileType
    };
    notebookPageList[pageIndex] = updatedNotebookPage;
    await this.persistNotebookPageList(request.notebookId, notebookPageList);

    notebookList[notebookIndex] = {
      id: notebook.id,
      title: notebook.title,
      folderId: notebook.folderId,
      createdAt: notebook.createdAt,
      updatedAt: currentTime,
      coverColor: NotebookEntity.normalizeCoverColor(notebook.coverColor),
      coverImageUri: NotebookEntity.normalizeCoverImageUri(notebook.coverImageUri),
      pageCount: NotebookEntity.normalizePageCount(notebook.pageCount),
      isFavorite: notebook.isFavorite === true,
      tags: this.normalizeTags(notebook.tags),
      isDeleted: notebook.isDeleted === true,
      deletedAt: this.normalizeTimestamp(notebook.deletedAt),
      lastOpenedAt: this.normalizeTimestamp(notebook.lastOpenedAt)
    };
    await this.persistNotebookList(notebookList);
    return updatedNotebookPage;
  }

  async updateNotebookPageCanvas(request: UpdateNotebookPageCanvasRequest): Promise<NotebookPageCanvas | null> {
    const notebookList: Notebook[] = await this.loadNotebookList();
    const notebookIndex: number = this.findNotebookIndexById(notebookList, request.notebookId);
    if (notebookIndex < 0) {
      return null;
    }

    const notebook: Notebook = notebookList[notebookIndex];
    const notebookPageList: NotebookPage[] = await this.loadOrBootstrapNotebookPageList(notebook);
    const pageIndex: number = this.findNotebookPageIndexById(notebookPageList, request.pageId);
    if (pageIndex < 0) {
      return null;
    }

    const currentNotebookPage: NotebookPage = notebookPageList[pageIndex];
    const currentNotebookPageCanvas: NotebookPageCanvas =
      await this.loadOrBootstrapNotebookPageCanvas(currentNotebookPage);
    const targetWidth: number = NotebookPageCanvasEntity.normalizeDimension(
      request.width,
      currentNotebookPageCanvas.width
    );
    const targetHeight: number = NotebookPageCanvasEntity.normalizeDimension(
      request.height,
      currentNotebookPageCanvas.height
    );

    if (currentNotebookPageCanvas.width === targetWidth && currentNotebookPageCanvas.height === targetHeight) {
      return currentNotebookPageCanvas;
    }

    const currentTime: number = TimeUtil.now();
    const updatedNotebookPage: NotebookPage = {
      id: currentNotebookPage.id,
      notebookId: currentNotebookPage.notebookId,
      order: currentNotebookPage.order,
      createdAt: currentNotebookPage.createdAt,
      updatedAt: currentTime,
      templateType: currentNotebookPage.templateType
    };
    const updatedNotebookPageCanvas: NotebookPageCanvas = {
      pageId: currentNotebookPageCanvas.pageId,
      notebookId: currentNotebookPageCanvas.notebookId,
      width: targetWidth,
      height: targetHeight,
      backgroundColor: currentNotebookPageCanvas.backgroundColor,
      createdAt: currentNotebookPageCanvas.createdAt,
      updatedAt: currentTime
    };

    notebookPageList[pageIndex] = updatedNotebookPage;
    await this.persistNotebookPageList(request.notebookId, notebookPageList);
    await this.persistNotebookPageCanvas(updatedNotebookPageCanvas);

    notebookList[notebookIndex] = {
      id: notebook.id,
      title: notebook.title,
      folderId: notebook.folderId,
      createdAt: notebook.createdAt,
      updatedAt: currentTime
    };
    await this.persistNotebookList(notebookList);
    return updatedNotebookPageCanvas;
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
          templateType: notebookPage.templateType,
          sourceFileUri: notebookPage.sourceFileUri,
          sourceFileType: notebookPage.sourceFileType
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
          backgroundImageUri: notebookPageCanvas.backgroundImageUri,
          createdAt: notebookPageCanvas.createdAt,
          updatedAt: currentTime
        });

        notebookList[notebookIndex] = {
          id: notebook.id,
          title: notebook.title,
          folderId: notebook.folderId,
          createdAt: notebook.createdAt,
          updatedAt: currentTime,
          coverColor: NotebookEntity.normalizeCoverColor(notebook.coverColor),
          coverImageUri: NotebookEntity.normalizeCoverImageUri(notebook.coverImageUri),
          pageCount: NotebookEntity.normalizePageCount(notebook.pageCount),
          isFavorite: notebook.isFavorite === true,
          tags: this.normalizeTags(notebook.tags),
          isDeleted: notebook.isDeleted === true,
          deletedAt: this.normalizeTimestamp(notebook.deletedAt),
          lastOpenedAt: this.normalizeTimestamp(notebook.lastOpenedAt)
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
          updatedAt: TimeUtil.isValidTimestamp(item.updatedAt) ? item.updatedAt : TimeUtil.now(),
          coverColor: NotebookEntity.normalizeCoverColor(item.coverColor),
          coverImageUri: NotebookEntity.normalizeCoverImageUri(item.coverImageUri),
          pageCount: NotebookEntity.normalizePageCount(item.pageCount),
          isFavorite: item.isFavorite === true,
          tags: this.normalizeTags(item.tags),
          isDeleted: item.isDeleted === true,
          deletedAt: this.normalizeTimestamp(item.deletedAt),
          lastOpenedAt: this.normalizeTimestamp(item.lastOpenedAt)
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
          color: NotebookFolderEntity.normalizeColor(typeof item.color === 'string' ? item.color : ''),
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
          templateType: NotebookPageEntity.normalizeTemplateType(item.templateType),
          sourceFileUri: typeof item.sourceFileUri === 'string' ? item.sourceFileUri.trim() : '',
          sourceFileType: typeof item.sourceFileType === 'string' ? item.sourceFileType.trim() : ''
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
          templateType: page.templateType,
          sourceFileUri: typeof page.sourceFileUri === 'string' ? page.sourceFileUri : '',
          sourceFileType: typeof page.sourceFileType === 'string' ? page.sourceFileType : ''
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
        backgroundImageUri: NotebookPageCanvasEntity.normalizeBackgroundImageUri(
          parsedNotebookPageCanvas.backgroundImageUri
        ),
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
    for (let index: number = 0; index < sortedFolderList.length; index += 1) {
      const folder: NotebookFolder = sortedFolderList[index];
      sortedFolderList[index] = {
        id: folder.id,
        title: folder.title,
        color: NotebookFolderEntity.normalizeColor(folder.color),
        createdAt: folder.createdAt,
        updatedAt: folder.updatedAt
      };
    }
    return sortedFolderList;
  }

  private async touchFolderUpdatedAt(folderId: string, updatedAt: number): Promise<void> {
    if (folderId.length === 0) {
      return;
    }

    const folderList: NotebookFolder[] = await this.loadFolderList();
    const folderIndex: number = this.findFolderIndexById(folderList, folderId);
    if (folderIndex < 0) {
      return;
    }

    const folder: NotebookFolder = folderList[folderIndex];
    folderList[folderIndex] = {
      id: folder.id,
      title: folder.title,
      color: NotebookFolderEntity.normalizeColor(folder.color),
      createdAt: folder.createdAt,
      updatedAt: updatedAt
    };
    await this.persistFolderList(folderList);
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
        templateType: notebookPage.templateType,
        sourceFileUri: notebookPage.sourceFileUri,
        sourceFileType: notebookPage.sourceFileType
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
      templateType: NotebookPageEntity.DEFAULT_TEMPLATE_TYPE,
      sourceFileUri: '',
      sourceFileType: ''
    };
  }

  private buildNotebookPageCanvas(notebookPage: NotebookPage, timestamp: number): NotebookPageCanvas {
    return {
      pageId: notebookPage.id,
      notebookId: notebookPage.notebookId,
      width: NotebookPageCanvasEntity.DEFAULT_WIDTH,
      height: NotebookPageCanvasEntity.DEFAULT_HEIGHT,
      backgroundColor: NotebookPageCanvasEntity.DEFAULT_BACKGROUND_COLOR,
      backgroundImageUri: '',
      createdAt: timestamp,
      updatedAt: timestamp
    };
  }

  private normalizeTags(rawTags?: string[]): string[] {
    if (!Array.isArray(rawTags)) {
      return [];
    }

    const tags: string[] = [];
    for (const rawTag of rawTags) {
      if (typeof rawTag !== 'string') {
        continue;
      }
      const normalizedTag: string = rawTag.trim();
      if (normalizedTag.length === 0) {
        continue;
      }
      if (!tags.includes(normalizedTag)) {
        tags.push(normalizedTag);
      }
    }
    return tags;
  }

  private normalizeTimestamp(rawTimestamp?: number): number {
    if (typeof rawTimestamp === 'number' && rawTimestamp > 0) {
      return rawTimestamp;
    }
    return 0;
  }

  private findNotebookIndexById(notebookList: Notebook[], notebookId: string): number {
    for (let index: number = 0; index < notebookList.length; index += 1) {
      if (notebookList[index].id === notebookId) {
        return index;
      }
    }
    return -1;
  }

  private findNotebookPageIndexById(notebookPageList: NotebookPage[], pageId: string): number {
    for (let index: number = 0; index < notebookPageList.length; index += 1) {
      if (notebookPageList[index].id === pageId) {
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
