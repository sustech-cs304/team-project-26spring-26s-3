import { Notebook } from '../entities/Notebook';
import { NotebookPage } from '../entities/NotebookPage';

export enum NotebookSortType {
  UPDATED_DESC = 'updated_desc',
  CREATED_DESC = 'created_desc',
  TITLE_ASC = 'title_asc'
}

export interface CreateNotebookRequest {
  title: string;
}

export interface RenameNotebookRequest {
  notebookId: string;
  title: string;
}

export interface CreateNotebookPageRequest {
  notebookId: string;
}

export interface DeleteNotebookPageRequest {
  notebookId: string;
  pageId: string;
}

export interface NotebookRepository {
  getNotebookList(): Promise<Notebook[]>;
  getNotebookById(notebookId: string): Promise<Notebook | null>;
  createNotebook(request: CreateNotebookRequest): Promise<Notebook>;
  renameNotebook(request: RenameNotebookRequest): Promise<Notebook | null>;
  deleteNotebook(notebookId: string): Promise<boolean>;
  getNotebookPages(notebookId: string): Promise<NotebookPage[]>;
  createNotebookPage(request: CreateNotebookPageRequest): Promise<NotebookPage | null>;
  deleteNotebookPage(request: DeleteNotebookPageRequest): Promise<boolean>;
  getSortType(): Promise<NotebookSortType>;
  saveSortType(sortType: NotebookSortType): Promise<void>;
}
