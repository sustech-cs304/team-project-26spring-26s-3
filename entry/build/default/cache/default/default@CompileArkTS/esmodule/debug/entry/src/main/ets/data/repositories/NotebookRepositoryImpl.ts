import type common from "@ohos:app.ability.common";
import { StorageKeys } from "@bundle:com.example.hosn/entry/ets/common/constants/StorageKeys";
import { IdUtil } from "@bundle:com.example.hosn/entry/ets/common/utils/IdUtil";
import { TimeUtil } from "@bundle:com.example.hosn/entry/ets/common/utils/TimeUtil";
import { NotebookEntity } from "@bundle:com.example.hosn/entry/ets/domain/entities/Notebook";
import type { Notebook } from "@bundle:com.example.hosn/entry/ets/domain/entities/Notebook";
import { NotebookSortType } from "@bundle:com.example.hosn/entry/ets/domain/repositories/NotebookRepository";
import type { CreateNotebookRequest, NotebookRepository, RenameNotebookRequest } from "@bundle:com.example.hosn/entry/ets/domain/repositories/NotebookRepository";
import { FileDataSource } from "@bundle:com.example.hosn/entry/ets/data/sources/local/FileDataSource";
import { PreferencesDataSource } from "@bundle:com.example.hosn/entry/ets/data/sources/local/PreferencesDataSource";
export class NotebookRepositoryImpl implements NotebookRepository {
    private static readonly NOTEBOOK_LIST_FILE_PATH: string = 'notebooks/notebook-list.json';
    private readonly preferencesDataSource: PreferencesDataSource;
    private readonly fileDataSource: FileDataSource;
    constructor(context: common.Context, preferencesDataSource?: PreferencesDataSource, fileDataSource?: FileDataSource) {
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
        await this.persistNotebookList(filteredNotebookList);
        return true;
    }
    async getSortType(): Promise<NotebookSortType> {
        const storedSortType: string = await this.preferencesDataSource.getString(StorageKeys.NOTEBOOK_SORT_TYPE, NotebookSortType.UPDATED_DESC);
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
        }
        catch (_error) {
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
}
