import common from '@ohos.app.ability.common';
import { Notebook } from '../../../domain/entities/Notebook';
import { NotebookFolder } from '../../../domain/entities/NotebookFolder';
import { CreateNotebook } from '../../../domain/usecases/CreateNotebook';
import { CreateNotebookFolder } from '../../../domain/usecases/CreateNotebookFolder';
import { DeleteNotebook } from '../../../domain/usecases/DeleteNotebook';
import { GetNotebookFolderList } from '../../../domain/usecases/GetNotebookFolderList';
import { GetNotebookList } from '../../../domain/usecases/GetNotebookList';
import { MoveNotebookToFolder } from '../../../domain/usecases/MoveNotebookToFolder';
import { RenameNotebook } from '../../../domain/usecases/RenameNotebook';
import { SortNotebookList } from '../../../domain/usecases/SortNotebookList';
import { NotebookRepository, NotebookSortType } from '../../../domain/repositories/NotebookRepository';
import { NotebookRepositoryImpl } from '../../../data/repositories/NotebookRepositoryImpl';

export class NotebookListViewModel {
  private readonly notebookRepository: NotebookRepository;
  private readonly createNotebookUseCase: CreateNotebook;
  private readonly createNotebookFolderUseCase: CreateNotebookFolder;
  private readonly deleteNotebookUseCase: DeleteNotebook;
  private readonly getNotebookFolderListUseCase: GetNotebookFolderList;
  private readonly getNotebookListUseCase: GetNotebookList;
  private readonly moveNotebookToFolderUseCase: MoveNotebookToFolder;
  private readonly renameNotebookUseCase: RenameNotebook;
  private readonly sortNotebookListUseCase: SortNotebookList;
  private notebookList: Notebook[] = [];
  private folderList: NotebookFolder[] = [];

  constructor(context: common.Context, notebookRepository?: NotebookRepository) {
    this.notebookRepository = notebookRepository ?? new NotebookRepositoryImpl(context);
    this.createNotebookUseCase = new CreateNotebook(this.notebookRepository);
    this.createNotebookFolderUseCase = new CreateNotebookFolder(this.notebookRepository);
    this.deleteNotebookUseCase = new DeleteNotebook(this.notebookRepository);
    this.getNotebookFolderListUseCase = new GetNotebookFolderList(this.notebookRepository);
    this.getNotebookListUseCase = new GetNotebookList(this.notebookRepository);
    this.moveNotebookToFolderUseCase = new MoveNotebookToFolder(this.notebookRepository);
    this.renameNotebookUseCase = new RenameNotebook(this.notebookRepository);
    this.sortNotebookListUseCase = new SortNotebookList(this.notebookRepository);
  }

  async loadNotebookList(): Promise<Notebook[]> {
    this.notebookList = await this.getNotebookListUseCase.execute();
    return this.cloneNotebookList(this.notebookList);
  }

  async loadSortType(): Promise<NotebookSortType> {
    return this.notebookRepository.getSortType();
  }

  async loadFolderList(): Promise<NotebookFolder[]> {
    this.folderList = await this.getNotebookFolderListUseCase.execute();
    return this.cloneFolderList(this.folderList);
  }

  async createNotebook(title: string): Promise<Notebook> {
    const notebook: Notebook = await this.createNotebookUseCase.execute({ title: title });
    this.notebookList = await this.getNotebookListUseCase.execute();
    return notebook;
  }

  async createFolder(title: string, color: string): Promise<NotebookFolder> {
    const folder: NotebookFolder = await this.createNotebookFolderUseCase.execute({ title: title, color: color });
    this.folderList = await this.getNotebookFolderListUseCase.execute();
    return folder;
  }

  async renameFolder(folderId: string, title: string): Promise<NotebookFolder | null> {
    const folder: NotebookFolder | null = await this.notebookRepository.renameFolder({
      folderId: folderId,
      title: title
    });
    this.folderList = await this.getNotebookFolderListUseCase.execute();
    return folder;
  }

  async updateFolderColor(folderId: string, color: string): Promise<NotebookFolder | null> {
    const folder: NotebookFolder | null = await this.notebookRepository.updateFolderColor({
      folderId: folderId,
      color: color
    });
    this.folderList = await this.getNotebookFolderListUseCase.execute();
    return folder;
  }

  async deleteFolder(folderId: string): Promise<boolean> {
    const hasDeleted: boolean = await this.notebookRepository.deleteFolder(folderId);
    this.folderList = await this.getNotebookFolderListUseCase.execute();
    this.notebookList = await this.getNotebookListUseCase.execute();
    return hasDeleted;
  }

  async renameNotebook(notebookId: string, title: string): Promise<Notebook | null> {
    const notebook: Notebook | null = await this.renameNotebookUseCase.execute({
      notebookId: notebookId,
      title: title
    });
    this.notebookList = await this.getNotebookListUseCase.execute();
    return notebook;
  }

  async deleteNotebook(notebookId: string): Promise<boolean> {
    const hasDeleted: boolean = await this.deleteNotebookUseCase.execute(notebookId);
    this.notebookList = await this.getNotebookListUseCase.execute();
    return hasDeleted;
  }

  async moveNotebookToFolder(notebookId: string, folderId: string): Promise<Notebook | null> {
    const notebook: Notebook | null = await this.moveNotebookToFolderUseCase.execute({
      notebookId: notebookId,
      folderId: folderId
    });
    this.notebookList = await this.getNotebookListUseCase.execute();
    this.folderList = await this.getNotebookFolderListUseCase.execute();
    return notebook;
  }

  async toggleNotebookFavorite(notebookId: string, isFavorite: boolean): Promise<Notebook | null> {
    const notebook: Notebook | null = await this.notebookRepository.toggleNotebookFavorite({
      notebookId: notebookId,
      isFavorite: isFavorite
    });
    this.notebookList = await this.getNotebookListUseCase.execute();
    return notebook;
  }

  async updateNotebookTags(notebookId: string, tags: string[]): Promise<Notebook | null> {
    const notebook: Notebook | null = await this.notebookRepository.updateNotebookTags({
      notebookId: notebookId,
      tags: tags
    });
    this.notebookList = await this.getNotebookListUseCase.execute();
    return notebook;
  }

  async updateNotebookCover(notebookId: string, coverImageUri: string, coverColor?: string): Promise<Notebook | null> {
    const notebook: Notebook | null = await this.notebookRepository.updateNotebookCover({
      notebookId: notebookId,
      coverImageUri: coverImageUri,
      coverColor: coverColor
    });
    this.notebookList = await this.getNotebookListUseCase.execute();
    return notebook;
  }

  async touchNotebookLastOpened(notebookId: string): Promise<Notebook | null> {
    const notebook: Notebook | null = await this.notebookRepository.touchNotebookLastOpened(notebookId);
    this.notebookList = await this.getNotebookListUseCase.execute();
    return notebook;
  }

  async restoreNotebook(notebookId: string): Promise<boolean> {
    const hasRestored: boolean = await this.notebookRepository.restoreNotebook(notebookId);
    this.notebookList = await this.getNotebookListUseCase.execute();
    return hasRestored;
  }

  async purgeNotebook(notebookId: string): Promise<boolean> {
    const hasPurged: boolean = await this.notebookRepository.purgeNotebook(notebookId);
    this.notebookList = await this.getNotebookListUseCase.execute();
    return hasPurged;
  }

  async changeSortType(sortType: NotebookSortType): Promise<Notebook[]> {
    this.notebookList = await this.sortNotebookListUseCase.execute(sortType);
    return this.cloneNotebookList(this.notebookList);
  }

  getCachedNotebookList(): Notebook[] {
    return this.cloneNotebookList(this.notebookList);
  }

  getCachedFolderList(): NotebookFolder[] {
    return this.cloneFolderList(this.folderList);
  }

  private cloneNotebookList(notebookList: Notebook[]): Notebook[] {
    const clonedNotebookList: Notebook[] = [];
    for (const notebook of notebookList) {
      clonedNotebookList.push({
        id: notebook.id,
        title: notebook.title,
        folderId: notebook.folderId,
        createdAt: notebook.createdAt,
        updatedAt: notebook.updatedAt,
        coverColor: notebook.coverColor,
        coverImageUri: notebook.coverImageUri,
        pageCount: notebook.pageCount,
        isFavorite: notebook.isFavorite === true,
        tags: Array.isArray(notebook.tags) ? notebook.tags.slice() : [],
        isDeleted: notebook.isDeleted === true,
        deletedAt: typeof notebook.deletedAt === 'number' ? notebook.deletedAt : 0,
        lastOpenedAt: typeof notebook.lastOpenedAt === 'number' ? notebook.lastOpenedAt : 0
      });
    }
    return clonedNotebookList;
  }

  private cloneFolderList(folderList: NotebookFolder[]): NotebookFolder[] {
    const clonedFolderList: NotebookFolder[] = [];
    for (const folder of folderList) {
      clonedFolderList.push({
        id: folder.id,
        title: folder.title,
        color: folder.color,
        createdAt: folder.createdAt,
        updatedAt: folder.updatedAt
      });
    }
    return clonedFolderList;
  }
}
