if (!("finalizeConstruction" in ViewPU.prototype)) {
    Reflect.set(ViewPU.prototype, "finalizeConstruction", () => { });
}
interface NotebookListPage_Params {
    notebookList?: Notebook[];
    isLoading?: boolean;
    isInputDialogVisible?: boolean;
    isRenameMode?: boolean;
    isSubmittingDialog?: boolean;
    draftNotebookTitle?: string;
    activeNotebookId?: string;
    currentSortType?: NotebookSortType;
    isDeleteDialogVisible?: boolean;
    isDeletingNotebook?: boolean;
    deleteTargetNotebookId?: string;
    deleteTargetNotebookTitle?: string;
    notebookListViewModel?: NotebookListViewModel;
    shouldHandleSortTypeChange?: boolean;
}
import type common from "@ohos:app.ability.common";
import { AppRouter } from "@bundle:com.example.hosn/entry/ets/app/AppRouter";
import type { RouterParams } from "@bundle:com.example.hosn/entry/ets/app/AppRouter";
import type { Notebook } from '../../../domain/entities/Notebook';
import { NotebookSortType } from "@bundle:com.example.hosn/entry/ets/domain/repositories/NotebookRepository";
import { CreateNotebookDialog } from "@bundle:com.example.hosn/entry/ets/features/notebook/components/CreateNotebookDialog";
import { NotebookCard } from "@bundle:com.example.hosn/entry/ets/features/notebook/components/NotebookCard";
import { SortMenu } from "@bundle:com.example.hosn/entry/ets/features/notebook/components/SortMenu";
import { NotebookListViewModel } from "@bundle:com.example.hosn/entry/ets/features/notebook/viewmodels/NotebookListViewModel";
class NotebookListPage extends ViewPU {
    constructor(parent, params, __localStorage, elmtId = -1, paramsLambda = undefined, extraInfo) {
        super(parent, __localStorage, elmtId, extraInfo);
        if (typeof paramsLambda === "function") {
            this.paramsGenerator_ = paramsLambda;
        }
        this.__notebookList = new ObservedPropertyObjectPU([], this, "notebookList");
        this.__isLoading = new ObservedPropertySimplePU(true, this, "isLoading");
        this.__isInputDialogVisible = new ObservedPropertySimplePU(false, this, "isInputDialogVisible");
        this.__isRenameMode = new ObservedPropertySimplePU(false, this, "isRenameMode");
        this.__isSubmittingDialog = new ObservedPropertySimplePU(false, this, "isSubmittingDialog");
        this.__draftNotebookTitle = new ObservedPropertySimplePU('', this, "draftNotebookTitle");
        this.__activeNotebookId = new ObservedPropertySimplePU('', this, "activeNotebookId");
        this.__currentSortType = new ObservedPropertySimplePU(NotebookSortType.UPDATED_DESC, this, "currentSortType");
        this.__isDeleteDialogVisible = new ObservedPropertySimplePU(false, this, "isDeleteDialogVisible");
        this.__isDeletingNotebook = new ObservedPropertySimplePU(false, this, "isDeletingNotebook");
        this.__deleteTargetNotebookId = new ObservedPropertySimplePU('', this, "deleteTargetNotebookId");
        this.__deleteTargetNotebookTitle = new ObservedPropertySimplePU('', this, "deleteTargetNotebookTitle");
        this.notebookListViewModel = undefined;
        this.shouldHandleSortTypeChange = false;
        this.setInitiallyProvidedValue(params);
        this.declareWatch("currentSortType", this.onCurrentSortTypeChanged);
        this.finalizeConstruction();
    }
    setInitiallyProvidedValue(params: NotebookListPage_Params) {
        if (params.notebookList !== undefined) {
            this.notebookList = params.notebookList;
        }
        if (params.isLoading !== undefined) {
            this.isLoading = params.isLoading;
        }
        if (params.isInputDialogVisible !== undefined) {
            this.isInputDialogVisible = params.isInputDialogVisible;
        }
        if (params.isRenameMode !== undefined) {
            this.isRenameMode = params.isRenameMode;
        }
        if (params.isSubmittingDialog !== undefined) {
            this.isSubmittingDialog = params.isSubmittingDialog;
        }
        if (params.draftNotebookTitle !== undefined) {
            this.draftNotebookTitle = params.draftNotebookTitle;
        }
        if (params.activeNotebookId !== undefined) {
            this.activeNotebookId = params.activeNotebookId;
        }
        if (params.currentSortType !== undefined) {
            this.currentSortType = params.currentSortType;
        }
        if (params.isDeleteDialogVisible !== undefined) {
            this.isDeleteDialogVisible = params.isDeleteDialogVisible;
        }
        if (params.isDeletingNotebook !== undefined) {
            this.isDeletingNotebook = params.isDeletingNotebook;
        }
        if (params.deleteTargetNotebookId !== undefined) {
            this.deleteTargetNotebookId = params.deleteTargetNotebookId;
        }
        if (params.deleteTargetNotebookTitle !== undefined) {
            this.deleteTargetNotebookTitle = params.deleteTargetNotebookTitle;
        }
        if (params.notebookListViewModel !== undefined) {
            this.notebookListViewModel = params.notebookListViewModel;
        }
        if (params.shouldHandleSortTypeChange !== undefined) {
            this.shouldHandleSortTypeChange = params.shouldHandleSortTypeChange;
        }
    }
    updateStateVars(params: NotebookListPage_Params) {
    }
    purgeVariableDependenciesOnElmtId(rmElmtId) {
        this.__notebookList.purgeDependencyOnElmtId(rmElmtId);
        this.__isLoading.purgeDependencyOnElmtId(rmElmtId);
        this.__isInputDialogVisible.purgeDependencyOnElmtId(rmElmtId);
        this.__isRenameMode.purgeDependencyOnElmtId(rmElmtId);
        this.__isSubmittingDialog.purgeDependencyOnElmtId(rmElmtId);
        this.__draftNotebookTitle.purgeDependencyOnElmtId(rmElmtId);
        this.__activeNotebookId.purgeDependencyOnElmtId(rmElmtId);
        this.__currentSortType.purgeDependencyOnElmtId(rmElmtId);
        this.__isDeleteDialogVisible.purgeDependencyOnElmtId(rmElmtId);
        this.__isDeletingNotebook.purgeDependencyOnElmtId(rmElmtId);
        this.__deleteTargetNotebookId.purgeDependencyOnElmtId(rmElmtId);
        this.__deleteTargetNotebookTitle.purgeDependencyOnElmtId(rmElmtId);
    }
    aboutToBeDeleted() {
        this.__notebookList.aboutToBeDeleted();
        this.__isLoading.aboutToBeDeleted();
        this.__isInputDialogVisible.aboutToBeDeleted();
        this.__isRenameMode.aboutToBeDeleted();
        this.__isSubmittingDialog.aboutToBeDeleted();
        this.__draftNotebookTitle.aboutToBeDeleted();
        this.__activeNotebookId.aboutToBeDeleted();
        this.__currentSortType.aboutToBeDeleted();
        this.__isDeleteDialogVisible.aboutToBeDeleted();
        this.__isDeletingNotebook.aboutToBeDeleted();
        this.__deleteTargetNotebookId.aboutToBeDeleted();
        this.__deleteTargetNotebookTitle.aboutToBeDeleted();
        SubscriberManager.Get().delete(this.id__());
        this.aboutToBeDeletedInternal();
    }
    private __notebookList: ObservedPropertyObjectPU<Notebook[]>;
    get notebookList() {
        return this.__notebookList.get();
    }
    set notebookList(newValue: Notebook[]) {
        this.__notebookList.set(newValue);
    }
    private __isLoading: ObservedPropertySimplePU<boolean>;
    get isLoading() {
        return this.__isLoading.get();
    }
    set isLoading(newValue: boolean) {
        this.__isLoading.set(newValue);
    }
    private __isInputDialogVisible: ObservedPropertySimplePU<boolean>;
    get isInputDialogVisible() {
        return this.__isInputDialogVisible.get();
    }
    set isInputDialogVisible(newValue: boolean) {
        this.__isInputDialogVisible.set(newValue);
    }
    private __isRenameMode: ObservedPropertySimplePU<boolean>;
    get isRenameMode() {
        return this.__isRenameMode.get();
    }
    set isRenameMode(newValue: boolean) {
        this.__isRenameMode.set(newValue);
    }
    private __isSubmittingDialog: ObservedPropertySimplePU<boolean>;
    get isSubmittingDialog() {
        return this.__isSubmittingDialog.get();
    }
    set isSubmittingDialog(newValue: boolean) {
        this.__isSubmittingDialog.set(newValue);
    }
    private __draftNotebookTitle: ObservedPropertySimplePU<string>;
    get draftNotebookTitle() {
        return this.__draftNotebookTitle.get();
    }
    set draftNotebookTitle(newValue: string) {
        this.__draftNotebookTitle.set(newValue);
    }
    private __activeNotebookId: ObservedPropertySimplePU<string>;
    get activeNotebookId() {
        return this.__activeNotebookId.get();
    }
    set activeNotebookId(newValue: string) {
        this.__activeNotebookId.set(newValue);
    }
    private __currentSortType: ObservedPropertySimplePU<NotebookSortType>;
    get currentSortType() {
        return this.__currentSortType.get();
    }
    set currentSortType(newValue: NotebookSortType) {
        this.__currentSortType.set(newValue);
    }
    private __isDeleteDialogVisible: ObservedPropertySimplePU<boolean>;
    get isDeleteDialogVisible() {
        return this.__isDeleteDialogVisible.get();
    }
    set isDeleteDialogVisible(newValue: boolean) {
        this.__isDeleteDialogVisible.set(newValue);
    }
    private __isDeletingNotebook: ObservedPropertySimplePU<boolean>;
    get isDeletingNotebook() {
        return this.__isDeletingNotebook.get();
    }
    set isDeletingNotebook(newValue: boolean) {
        this.__isDeletingNotebook.set(newValue);
    }
    private __deleteTargetNotebookId: ObservedPropertySimplePU<string>;
    get deleteTargetNotebookId() {
        return this.__deleteTargetNotebookId.get();
    }
    set deleteTargetNotebookId(newValue: string) {
        this.__deleteTargetNotebookId.set(newValue);
    }
    private __deleteTargetNotebookTitle: ObservedPropertySimplePU<string>;
    get deleteTargetNotebookTitle() {
        return this.__deleteTargetNotebookTitle.get();
    }
    set deleteTargetNotebookTitle(newValue: string) {
        this.__deleteTargetNotebookTitle.set(newValue);
    }
    private notebookListViewModel?: NotebookListViewModel;
    private shouldHandleSortTypeChange: boolean;
    aboutToAppear(): void {
        this.loadNotebookList();
    }
    private ensureViewModel(): NotebookListViewModel {
        if (this.notebookListViewModel === undefined) {
            const hostContext: common.Context | undefined = this.getUIContext().getHostContext() as common.Context | undefined;
            if (hostContext === undefined) {
                throw new Error('Host context is unavailable.');
            }
            this.notebookListViewModel = new NotebookListViewModel(hostContext);
        }
        return this.notebookListViewModel as NotebookListViewModel;
    }
    private async loadNotebookList(): Promise<void> {
        this.isLoading = true;
        try {
            const viewModel: NotebookListViewModel = this.ensureViewModel();
            this.shouldHandleSortTypeChange = false;
            this.currentSortType = await viewModel.loadSortType();
            this.notebookList = await viewModel.loadNotebookList();
        }
        catch (_error) {
            this.notebookList = [];
            this.currentSortType = NotebookSortType.UPDATED_DESC;
        }
        finally {
            this.shouldHandleSortTypeChange = true;
            this.isLoading = false;
        }
    }
    private openCreateDialog(): void {
        this.closeDeleteDialog();
        this.activeNotebookId = '';
        this.draftNotebookTitle = '';
        this.isRenameMode = false;
        this.isInputDialogVisible = true;
    }
    private openRenameDialog(notebook: Notebook): void {
        this.closeDeleteDialog();
        this.activeNotebookId = notebook.id;
        this.draftNotebookTitle = notebook.title;
        this.isRenameMode = true;
        this.isInputDialogVisible = true;
    }
    private resetInputDialogState(): void {
        this.isInputDialogVisible = false;
        this.isRenameMode = false;
        this.activeNotebookId = '';
        this.draftNotebookTitle = '';
    }
    private closeInputDialog(): void {
        if (this.isSubmittingDialog) {
            return;
        }
        this.resetInputDialogState();
    }
    private async submitNotebookDialog(): Promise<void> {
        if (this.isSubmittingDialog) {
            return;
        }
        this.isSubmittingDialog = true;
        try {
            if (this.isRenameMode) {
                await this.ensureViewModel().renameNotebook(this.activeNotebookId, this.draftNotebookTitle);
            }
            else {
                await this.ensureViewModel().createNotebook(this.draftNotebookTitle);
            }
            this.notebookList = this.ensureViewModel().getCachedNotebookList();
            this.closeDeleteDialog();
            this.resetInputDialogState();
        }
        catch (_error) {
        }
        finally {
            this.isSubmittingDialog = false;
        }
    }
    private onCurrentSortTypeChanged(): void {
        if (!this.shouldHandleSortTypeChange) {
            return;
        }
        void this.applyCurrentSortType();
    }
    private async applyCurrentSortType(): Promise<void> {
        if (this.isLoading) {
            return;
        }
        this.isLoading = true;
        try {
            this.notebookList = await this.ensureViewModel().changeSortType(this.currentSortType);
        }
        catch (_error) {
            this.shouldHandleSortTypeChange = false;
            try {
                this.currentSortType = await this.ensureViewModel().loadSortType();
            }
            catch (_reloadError) {
                this.currentSortType = NotebookSortType.UPDATED_DESC;
            }
            finally {
                this.shouldHandleSortTypeChange = true;
            }
        }
        finally {
            this.isLoading = false;
        }
    }
    private openDeleteDialog(notebook: Notebook): void {
        if (this.isDeletingNotebook || this.isSubmittingDialog) {
            return;
        }
        this.deleteTargetNotebookId = notebook.id;
        this.deleteTargetNotebookTitle = notebook.title;
        this.isDeleteDialogVisible = true;
    }
    private closeDeleteDialog(): void {
        if (this.isDeletingNotebook) {
            return;
        }
        this.resetDeleteDialogState();
    }
    private resetDeleteDialogState(): void {
        this.isDeleteDialogVisible = false;
        this.deleteTargetNotebookId = '';
        this.deleteTargetNotebookTitle = '';
    }
    private async confirmDeleteSelectedNotebook(): Promise<void> {
        if (this.isDeletingNotebook || this.deleteTargetNotebookId.length === 0) {
            return;
        }
        let hasDeleted: boolean = false;
        this.isDeletingNotebook = true;
        try {
            hasDeleted = await this.ensureViewModel().deleteNotebook(this.deleteTargetNotebookId);
            this.notebookList = this.ensureViewModel().getCachedNotebookList();
        }
        catch (_error) {
        }
        finally {
            this.isDeletingNotebook = false;
            if (hasDeleted) {
                this.resetDeleteDialogState();
            }
        }
    }
    private openNotebook(notebookId: string): void {
        const params: RouterParams = {
            notebookId: notebookId,
            source: 'notebook_list'
        };
        AppRouter.openEditor(params);
    }
    private formatTimestamp(timestamp: number): string {
        const date: Date = new Date(timestamp);
        const year: string = date.getFullYear().toString();
        const month: string = this.padNumber(date.getMonth() + 1);
        const day: string = this.padNumber(date.getDate());
        const hour: string = this.padNumber(date.getHours());
        const minute: string = this.padNumber(date.getMinutes());
        return `${year}-${month}-${day} ${hour}:${minute}`;
    }
    private padNumber(value: number): string {
        if (value >= 10) {
            return value.toString();
        }
        return `0${value.toString()}`;
    }
    initialRender() {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Stack.create();
            Stack.width('100%');
            Stack.height('100%');
            Stack.backgroundColor({ "id": 16777276, "type": 10001, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
        }, Stack);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Scroll.create();
            Scroll.width('100%');
            Scroll.height('100%');
            Scroll.backgroundColor({ "id": 16777276, "type": 10001, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
        }, Scroll);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create({ space: 20 });
            Column.width('100%');
            Column.alignItems(HorizontalAlign.Start);
            Column.padding({
                left: { "id": 16777291, "type": 10002, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" },
                right: { "id": 16777291, "type": 10002, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" },
                top: { "id": 16777292, "type": 10002, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" },
                bottom: { "id": 16777292, "type": 10002, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" }
            });
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create({ space: 8 });
            Column.alignItems(HorizontalAlign.Start);
            Column.width('100%');
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create({ "id": 16777256, "type": 10003, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
            Text.fontSize({ "id": 16777290, "type": 10002, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
            Text.fontWeight(FontWeight.Bold);
            Text.fontColor({ "id": 16777282, "type": 10001, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create({ "id": 16777255, "type": 10003, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
            Text.fontSize({ "id": 16777286, "type": 10002, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
            Text.fontColor({ "id": 16777283, "type": 10001, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
        }, Text);
        Text.pop();
        Column.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Row.create({ space: 12 });
            Row.width('100%');
            Row.alignItems(VerticalAlign.Center);
        }, Row);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create({ space: 4 });
            Column.layoutWeight(1);
            Column.alignItems(HorizontalAlign.Start);
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create({ "id": 16777253, "type": 10003, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
            Text.fontSize({ "id": 16777293, "type": 10002, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
            Text.fontWeight(FontWeight.Medium);
            Text.fontColor({ "id": 16777282, "type": 10001, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(`${this.notebookList.length} ${{ "id": 16777252, "type": 10003, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" }}`);
            Text.fontSize({ "id": 16777288, "type": 10002, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
            Text.fontColor({ "id": 16777283, "type": 10001, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
        }, Text);
        Text.pop();
        Column.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Button.createWithLabel({ "id": 16777237, "type": 10003, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
            Button.height({ "id": 16777287, "type": 10002, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
            Button.backgroundColor({ "id": 16777282, "type": 10001, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
            Button.fontColor({ "id": 16777280, "type": 10001, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
            Button.onClick(() => {
                this.openCreateDialog();
            });
        }, Button);
        Button.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Button.createWithLabel({ "id": 16777233, "type": 10003, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
            Button.height({ "id": 16777287, "type": 10002, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
            Button.backgroundColor({ "id": 16777276, "type": 10001, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
            Button.fontColor({ "id": 16777282, "type": 10001, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
            Button.onClick(() => {
                AppRouter.goHome();
            });
        }, Button);
        Button.pop();
        Row.pop();
        {
            this.observeComponentCreation2((elmtId, isInitialRender) => {
                if (isInitialRender) {
                    let componentCall = new SortMenu(this, {
                        selectedSortType: this.__currentSortType
                    }, undefined, elmtId, () => { }, { page: "entry/src/main/ets/features/notebook/pages/NotebookListPage.ets", line: 259, col: 11 });
                    ViewPU.create(componentCall);
                    let paramsLambda = () => {
                        return {
                            selectedSortType: this.currentSortType
                        };
                    };
                    componentCall.paramsGenerator_ = paramsLambda;
                }
                else {
                    this.updateStateVarsOfChildByElmtId(elmtId, {});
                }
            }, { name: "SortMenu" });
        }
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            If.create();
            if (this.isLoading) {
                this.ifElseBranchUpdateFunction(0, () => {
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Column.create({ space: 12 });
                        Column.width('100%');
                        Column.padding(32);
                        Column.backgroundColor({ "id": 16777285, "type": 10001, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
                        Column.borderRadius({ "id": 16777289, "type": 10002, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
                        Column.border({
                            width: 1,
                            color: { "id": 16777277, "type": 10001, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" }
                        });
                    }, Column);
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        LoadingProgress.create();
                        LoadingProgress.width(36);
                        LoadingProgress.height(36);
                    }, LoadingProgress);
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Text.create({ "id": 16777254, "type": 10003, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
                        Text.fontSize({ "id": 16777288, "type": 10002, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
                        Text.fontColor({ "id": 16777283, "type": 10001, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
                    }, Text);
                    Text.pop();
                    Column.pop();
                });
            }
            else if (this.notebookList.length === 0) {
                this.ifElseBranchUpdateFunction(1, () => {
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Column.create({ space: 12 });
                        Column.width('100%');
                        Column.alignItems(HorizontalAlign.Start);
                        Column.padding(24);
                        Column.backgroundColor({ "id": 16777285, "type": 10001, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
                        Column.borderRadius({ "id": 16777289, "type": 10002, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
                        Column.border({
                            width: 1,
                            color: { "id": 16777277, "type": 10001, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" }
                        });
                    }, Column);
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Text.create({ "id": 16777251, "type": 10003, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
                        Text.fontSize({ "id": 16777293, "type": 10002, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
                        Text.fontWeight(FontWeight.Medium);
                        Text.fontColor({ "id": 16777282, "type": 10001, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
                    }, Text);
                    Text.pop();
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Text.create({ "id": 16777250, "type": 10003, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
                        Text.fontSize({ "id": 16777286, "type": 10002, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
                        Text.fontColor({ "id": 16777283, "type": 10001, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
                    }, Text);
                    Text.pop();
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Button.createWithLabel({ "id": 16777241, "type": 10003, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
                        Button.height({ "id": 16777287, "type": 10002, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
                        Button.backgroundColor({ "id": 16777282, "type": 10001, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
                        Button.fontColor({ "id": 16777280, "type": 10001, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
                        Button.onClick(() => {
                            this.openCreateDialog();
                        });
                    }, Button);
                    Button.pop();
                    Column.pop();
                });
            }
            else {
                this.ifElseBranchUpdateFunction(2, () => {
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Column.create({ space: 12 });
                        Column.width('100%');
                    }, Column);
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        ForEach.create();
                        const forEachItemGenFunction = _item => {
                            const notebook = _item;
                            this.observeComponentCreation2((elmtId, isInitialRender) => {
                                Column.create({ space: 12 });
                                Column.width('100%');
                            }, Column);
                            {
                                this.observeComponentCreation2((elmtId, isInitialRender) => {
                                    if (isInitialRender) {
                                        let componentCall = new NotebookCard(this, {
                                            title: notebook.title,
                                            updatedAtText: `${{ "id": 16777269, "type": 10003, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" }}${this.formatTimestamp(notebook.updatedAt)}`
                                        }, undefined, elmtId, () => { }, { page: "entry/src/main/ets/features/notebook/pages/NotebookListPage.ets", line: 313, col: 19 });
                                        ViewPU.create(componentCall);
                                        let paramsLambda = () => {
                                            return {
                                                title: notebook.title,
                                                updatedAtText: `${{ "id": 16777269, "type": 10003, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" }}${this.formatTimestamp(notebook.updatedAt)}`
                                            };
                                        };
                                        componentCall.paramsGenerator_ = paramsLambda;
                                    }
                                    else {
                                        this.updateStateVarsOfChildByElmtId(elmtId, {});
                                    }
                                }, { name: "NotebookCard" });
                            }
                            this.observeComponentCreation2((elmtId, isInitialRender) => {
                                Row.create({ space: 8 });
                                Row.width('100%');
                            }, Row);
                            this.observeComponentCreation2((elmtId, isInitialRender) => {
                                Button.createWithLabel({ "id": 16777235, "type": 10003, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
                                Button.layoutWeight(1);
                                Button.height({ "id": 16777287, "type": 10002, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
                                Button.backgroundColor({ "id": 16777276, "type": 10001, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
                                Button.fontColor({ "id": 16777282, "type": 10001, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
                                Button.opacity(this.isDeletingNotebook || this.isSubmittingDialog ? 0.7 : 1);
                                Button.onClick(() => {
                                    if (!this.isDeletingNotebook && !this.isSubmittingDialog) {
                                        this.openNotebook(notebook.id);
                                    }
                                });
                            }, Button);
                            Button.pop();
                            this.observeComponentCreation2((elmtId, isInitialRender) => {
                                Button.createWithLabel({ "id": 16777236, "type": 10003, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
                                Button.layoutWeight(1);
                                Button.height({ "id": 16777287, "type": 10002, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
                                Button.backgroundColor({ "id": 16777276, "type": 10001, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
                                Button.fontColor({ "id": 16777282, "type": 10001, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
                                Button.opacity(this.isDeletingNotebook || this.isSubmittingDialog ? 0.7 : 1);
                                Button.onClick(() => {
                                    if (!this.isDeletingNotebook && !this.isSubmittingDialog) {
                                        this.openRenameDialog(notebook);
                                    }
                                });
                            }, Button);
                            Button.pop();
                            this.observeComponentCreation2((elmtId, isInitialRender) => {
                                Button.createWithLabel({ "id": 16777234, "type": 10003, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
                                Button.layoutWeight(1);
                                Button.height({ "id": 16777287, "type": 10002, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
                                Button.backgroundColor({ "id": 16777278, "type": 10001, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
                                Button.fontColor({ "id": 16777279, "type": 10001, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
                                Button.opacity(this.isDeletingNotebook || this.isSubmittingDialog ? 0.7 : 1);
                                Button.onClick(() => {
                                    if (!this.isDeletingNotebook && !this.isSubmittingDialog) {
                                        this.openDeleteDialog(notebook);
                                    }
                                });
                            }, Button);
                            Button.pop();
                            Row.pop();
                            Column.pop();
                        };
                        this.forEachUpdateFunction(elmtId, this.notebookList, forEachItemGenFunction, (notebook: Notebook): string => notebook.id, false, false);
                    }, ForEach);
                    ForEach.pop();
                    Column.pop();
                });
            }
        }, If);
        If.pop();
        Column.pop();
        Scroll.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            If.create();
            if (this.isDeleteDialogVisible) {
                this.ifElseBranchUpdateFunction(0, () => {
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Column.create();
                        Column.width('100%');
                        Column.height('100%');
                        Column.justifyContent(FlexAlign.Center);
                        Column.alignItems(HorizontalAlign.Center);
                        Column.padding({
                            left: { "id": 16777291, "type": 10002, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" },
                            right: { "id": 16777291, "type": 10002, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" },
                            top: { "id": 16777292, "type": 10002, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" },
                            bottom: { "id": 16777292, "type": 10002, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" }
                        });
                        Column.backgroundColor({ "id": 16777281, "type": 10001, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
                    }, Column);
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Column.create({ space: 16 });
                        Column.width('100%');
                        Column.constraintSize({ maxWidth: 560 });
                        Column.alignItems(HorizontalAlign.Start);
                        Column.padding(24);
                        Column.backgroundColor({ "id": 16777285, "type": 10001, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
                        Column.borderRadius({ "id": 16777289, "type": 10002, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
                        Column.border({
                            width: 1,
                            color: { "id": 16777277, "type": 10001, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" }
                        });
                    }, Column);
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Text.create({ "id": 16777247, "type": 10003, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
                        Text.fontSize({ "id": 16777293, "type": 10002, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
                        Text.fontWeight(FontWeight.Bold);
                        Text.fontColor({ "id": 16777282, "type": 10001, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
                    }, Text);
                    Text.pop();
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Text.create(`${{ "id": 16777248, "type": 10003, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" }}${this.deleteTargetNotebookTitle}`);
                        Text.fontSize({ "id": 16777286, "type": 10002, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
                        Text.fontColor({ "id": 16777282, "type": 10001, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
                    }, Text);
                    Text.pop();
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Text.create({ "id": 16777246, "type": 10003, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
                        Text.fontSize({ "id": 16777288, "type": 10002, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
                        Text.fontColor({ "id": 16777283, "type": 10001, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
                    }, Text);
                    Text.pop();
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Row.create({ space: 12 });
                        Row.width('100%');
                    }, Row);
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Button.createWithLabel({ "id": 16777223, "type": 10003, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
                        Button.layoutWeight(1);
                        Button.height({ "id": 16777287, "type": 10002, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
                        Button.backgroundColor({ "id": 16777276, "type": 10001, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
                        Button.fontColor({ "id": 16777282, "type": 10001, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
                        Button.onClick(() => {
                            this.closeDeleteDialog();
                        });
                    }, Button);
                    Button.pop();
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Button.createWithLabel(this.isDeletingNotebook ? { "id": 16777249, "type": 10003, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" } : { "id": 16777245, "type": 10003, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
                        Button.layoutWeight(1);
                        Button.height({ "id": 16777287, "type": 10002, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
                        Button.backgroundColor({ "id": 16777279, "type": 10001, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
                        Button.fontColor({ "id": 16777280, "type": 10001, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
                        Button.onClick(() => {
                            this.confirmDeleteSelectedNotebook();
                        });
                    }, Button);
                    Button.pop();
                    Row.pop();
                    Column.pop();
                    Column.pop();
                });
            }
            else {
                this.ifElseBranchUpdateFunction(1, () => {
                });
            }
        }, If);
        If.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            If.create();
            if (this.isInputDialogVisible) {
                this.ifElseBranchUpdateFunction(0, () => {
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Column.create();
                        Column.width('100%');
                        Column.height('100%');
                        Column.justifyContent(FlexAlign.End);
                        Column.alignItems(HorizontalAlign.Center);
                        Column.padding({
                            left: { "id": 16777291, "type": 10002, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" },
                            right: { "id": 16777291, "type": 10002, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" },
                            top: { "id": 16777292, "type": 10002, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" },
                            bottom: { "id": 16777292, "type": 10002, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" }
                        });
                        Column.backgroundColor({ "id": 16777281, "type": 10001, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
                    }, Column);
                    {
                        this.observeComponentCreation2((elmtId, isInitialRender) => {
                            if (isInitialRender) {
                                let componentCall = new CreateNotebookDialog(this, {
                                    title: this.__draftNotebookTitle,
                                    isRenameMode: this.isRenameMode,
                                    isSubmitting: this.isSubmittingDialog,
                                    onCancel: (): void => {
                                        this.closeInputDialog();
                                    },
                                    onConfirm: (): void => {
                                        this.submitNotebookDialog();
                                    }
                                }, undefined, elmtId, () => { }, { page: "entry/src/main/ets/features/notebook/pages/NotebookListPage.ets", line: 439, col: 11 });
                                ViewPU.create(componentCall);
                                let paramsLambda = () => {
                                    return {
                                        title: this.draftNotebookTitle,
                                        isRenameMode: this.isRenameMode,
                                        isSubmitting: this.isSubmittingDialog,
                                        onCancel: (): void => {
                                            this.closeInputDialog();
                                        },
                                        onConfirm: (): void => {
                                            this.submitNotebookDialog();
                                        }
                                    };
                                };
                                componentCall.paramsGenerator_ = paramsLambda;
                            }
                            else {
                                this.updateStateVarsOfChildByElmtId(elmtId, {});
                            }
                        }, { name: "CreateNotebookDialog" });
                    }
                    Column.pop();
                });
            }
            else {
                this.ifElseBranchUpdateFunction(1, () => {
                });
            }
        }, If);
        If.pop();
        Stack.pop();
    }
    rerender() {
        this.updateDirtyElements();
    }
    static getEntryName(): string {
        return "NotebookListPage";
    }
}
registerNamedRoute(() => new NotebookListPage(undefined, {}), "", { bundleName: "com.example.hosn", moduleName: "entry", pagePath: "features/notebook/pages/NotebookListPage", pageFullPath: "entry/src/main/ets/features/notebook/pages/NotebookListPage", integratedHsp: "false", moduleType: "followWithHap" });
