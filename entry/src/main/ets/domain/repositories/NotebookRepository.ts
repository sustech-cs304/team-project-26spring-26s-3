import { Notebook } from '../entities/Notebook';
import { NotebookFolder } from '../entities/NotebookFolder';
import { NotebookPage, NotebookPageTemplateType } from '../entities/NotebookPage';
import { NotebookPageCanvas } from '../entities/NotebookPageCanvas';

export enum NotebookSortType {
  UPDATED_DESC = 'updated_desc',
  CREATED_DESC = 'created_desc',
  TITLE_ASC = 'title_asc'
}

export interface CreateNotebookRequest {
  title: string;
}

export interface CreateNotebookFolderRequest {
  title: string;
  color: string;
}

export interface RenameNotebookRequest {
  notebookId: string;
  title: string;
}

export interface RenameNotebookFolderRequest {
  folderId: string;
  title: string;
}

export interface UpdateNotebookFolderColorRequest {
  folderId: string;
  color: string;
}

export interface MoveNotebookToFolderRequest {
  notebookId: string;
  folderId: string;
}

export interface ToggleNotebookFavoriteRequest {
  notebookId: string;
  isFavorite: boolean;
}

export interface UpdateNotebookTagsRequest {
  notebookId: string;
  tags: string[];
}

export interface UpdateNotebookCoverRequest {
  notebookId: string;
  coverImageUri: string;
  coverColor?: string;
}

export interface CreateNotebookPageRequest {
  notebookId: string;
}

export interface DeleteNotebookPageRequest {
  notebookId: string;
  pageId: string;
}

export interface ReorderNotebookPagesRequest {
  notebookId: string;
  fromIndex: number;
  toIndex: number;
}

export interface UpdateNotebookPageTemplateRequest {
  notebookId: string;
  pageId: string;
  templateType: NotebookPageTemplateType;
}

export interface GetNotebookPageCanvasRequest {
  notebookId: string;
  pageId: string;
}

export interface UpdateNotebookPageCanvasRequest {
  notebookId: string;
  pageId: string;
  width: number;
  height: number;
}

export interface NotebookRepository {
  getNotebookList(): Promise<Notebook[]>;
  getFolderList(): Promise<NotebookFolder[]>;
  getNotebookById(notebookId: string): Promise<Notebook | null>;
  createNotebook(request: CreateNotebookRequest): Promise<Notebook>;
  createFolder(request: CreateNotebookFolderRequest): Promise<NotebookFolder>;
  renameFolder(request: RenameNotebookFolderRequest): Promise<NotebookFolder | null>;
  updateFolderColor(request: UpdateNotebookFolderColorRequest): Promise<NotebookFolder | null>;
  deleteFolder(folderId: string): Promise<boolean>;
  renameNotebook(request: RenameNotebookRequest): Promise<Notebook | null>;
  moveNotebookToFolder(request: MoveNotebookToFolderRequest): Promise<Notebook | null>;
  toggleNotebookFavorite(request: ToggleNotebookFavoriteRequest): Promise<Notebook | null>;
  updateNotebookTags(request: UpdateNotebookTagsRequest): Promise<Notebook | null>;
  updateNotebookCover(request: UpdateNotebookCoverRequest): Promise<Notebook | null>;
  touchNotebookLastOpened(notebookId: string): Promise<Notebook | null>;
  restoreNotebook(notebookId: string): Promise<boolean>;
  purgeNotebook(notebookId: string): Promise<boolean>;
  deleteNotebook(notebookId: string): Promise<boolean>;
  getNotebookPages(notebookId: string): Promise<NotebookPage[]>;
  getNotebookPageCanvas(request: GetNotebookPageCanvasRequest): Promise<NotebookPageCanvas | null>;
  createNotebookPage(request: CreateNotebookPageRequest): Promise<NotebookPage | null>;
  deleteNotebookPage(request: DeleteNotebookPageRequest): Promise<boolean>;
  reorderNotebookPages(request: ReorderNotebookPagesRequest): Promise<boolean>;
  updateNotebookPageTemplate(request: UpdateNotebookPageTemplateRequest): Promise<NotebookPage | null>;
  updateNotebookPageCanvas(request: UpdateNotebookPageCanvasRequest): Promise<NotebookPageCanvas | null>;
  touchNotebookPageUpdatedAt(pageId: string): Promise<boolean>;
  getSortType(): Promise<NotebookSortType>;
  saveSortType(sortType: NotebookSortType): Promise<void>;
}
