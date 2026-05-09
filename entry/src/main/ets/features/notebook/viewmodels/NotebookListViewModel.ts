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

  async createFolder(title: string): Promise<NotebookFolder> {
    const folder: NotebookFolder = await this.createNotebookFolderUseCase.execute({ title: title });
    this.folderList = await this.getNotebookFolderListUseCase.execute();
    return folder;
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
        updatedAt: notebook.updatedAt
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
        createdAt: folder.createdAt,
        updatedAt: folder.updatedAt
      });
    }
    return clonedFolderList;
  }
}
