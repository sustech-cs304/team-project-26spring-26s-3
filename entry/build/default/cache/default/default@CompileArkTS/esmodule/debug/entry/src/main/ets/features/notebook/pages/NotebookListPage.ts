if (!("finalizeConstruction" in ViewPU.prototype)) {
    Reflect.set(ViewPU.prototype, "finalizeConstruction", () => { });
}
interface NotebookListPage_Params {
    notebookList?: Notebook[];
    isLoading?: boolean;
    notebookListViewModel?: NotebookListViewModel;
}
import type common from "@ohos:app.ability.common";
import { AppRouter } from "@bundle:com.example.hosn/entry/ets/app/AppRouter";
import type { RouterParams } from "@bundle:com.example.hosn/entry/ets/app/AppRouter";
import type { Notebook } from '../../../domain/entities/Notebook';
import { NotebookCard } from "@bundle:com.example.hosn/entry/ets/features/notebook/components/NotebookCard";
import { NotebookListViewModel } from "@bundle:com.example.hosn/entry/ets/features/notebook/viewmodels/NotebookListViewModel";
class NotebookListPage extends ViewPU {
    constructor(parent, params, __localStorage, elmtId = -1, paramsLambda = undefined, extraInfo) {
        super(parent, __localStorage, elmtId, extraInfo);
        if (typeof paramsLambda === "function") {
            this.paramsGenerator_ = paramsLambda;
        }
        this.__notebookList = new ObservedPropertyObjectPU([], this, "notebookList");
        this.__isLoading = new ObservedPropertySimplePU(true, this, "isLoading");
        this.notebookListViewModel = undefined;
        this.setInitiallyProvidedValue(params);
        this.finalizeConstruction();
    }
    setInitiallyProvidedValue(params: NotebookListPage_Params) {
        if (params.notebookList !== undefined) {
            this.notebookList = params.notebookList;
        }
        if (params.isLoading !== undefined) {
            this.isLoading = params.isLoading;
        }
        if (params.notebookListViewModel !== undefined) {
            this.notebookListViewModel = params.notebookListViewModel;
        }
    }
    updateStateVars(params: NotebookListPage_Params) {
    }
    purgeVariableDependenciesOnElmtId(rmElmtId) {
        this.__notebookList.purgeDependencyOnElmtId(rmElmtId);
        this.__isLoading.purgeDependencyOnElmtId(rmElmtId);
    }
    aboutToBeDeleted() {
        this.__notebookList.aboutToBeDeleted();
        this.__isLoading.aboutToBeDeleted();
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
    private notebookListViewModel?: NotebookListViewModel;
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
            this.notebookList = await this.ensureViewModel().loadNotebookList();
        }
        catch (_error) {
            this.notebookList = [];
        }
        finally {
            this.isLoading = false;
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
            Scroll.create();
            Scroll.width('100%');
            Scroll.height('100%');
            Scroll.backgroundColor({ "id": 16777248, "type": 10001, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
        }, Scroll);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create({ space: 20 });
            Column.width('100%');
            Column.alignItems(HorizontalAlign.Start);
            Column.padding({
                left: { "id": 16777259, "type": 10002, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" },
                right: { "id": 16777259, "type": 10002, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" },
                top: { "id": 16777260, "type": 10002, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" },
                bottom: { "id": 16777260, "type": 10002, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" }
            });
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create({ space: 8 });
            Column.width('100%');
            Column.alignItems(HorizontalAlign.Start);
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create({ "id": 16777239, "type": 10003, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
            Text.fontSize({ "id": 16777258, "type": 10002, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
            Text.fontWeight(FontWeight.Bold);
            Text.fontColor({ "id": 16777250, "type": 10001, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create({ "id": 16777238, "type": 10003, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
            Text.fontSize({ "id": 16777254, "type": 10002, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
            Text.fontColor({ "id": 16777251, "type": 10001, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
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
            Text.create({ "id": 16777236, "type": 10003, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
            Text.fontSize({ "id": 16777261, "type": 10002, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
            Text.fontWeight(FontWeight.Medium);
            Text.fontColor({ "id": 16777250, "type": 10001, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(`${this.notebookList.length} ${{ "id": 16777235, "type": 10003, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" }}`);
            Text.fontSize({ "id": 16777256, "type": 10002, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
            Text.fontColor({ "id": 16777251, "type": 10001, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
        }, Text);
        Text.pop();
        Column.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Button.createWithLabel({ "id": 16777232, "type": 10003, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
            Button.height({ "id": 16777255, "type": 10002, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
            Button.onClick(() => {
                AppRouter.goHome();
            });
        }, Button);
        Button.pop();
        Row.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            If.create();
            if (this.isLoading) {
                this.ifElseBranchUpdateFunction(0, () => {
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Column.create({ space: 12 });
                        Column.width('100%');
                        Column.padding(32);
                        Column.backgroundColor({ "id": 16777253, "type": 10001, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
                        Column.borderRadius({ "id": 16777257, "type": 10002, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
                        Column.border({
                            width: 1,
                            color: { "id": 16777249, "type": 10001, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" }
                        });
                    }, Column);
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        LoadingProgress.create();
                        LoadingProgress.width(36);
                        LoadingProgress.height(36);
                    }, LoadingProgress);
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Text.create({ "id": 16777237, "type": 10003, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
                        Text.fontSize({ "id": 16777256, "type": 10002, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
                        Text.fontColor({ "id": 16777251, "type": 10001, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
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
                        Column.backgroundColor({ "id": 16777253, "type": 10001, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
                        Column.borderRadius({ "id": 16777257, "type": 10002, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
                        Column.border({
                            width: 1,
                            color: { "id": 16777249, "type": 10001, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" }
                        });
                    }, Column);
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Text.create({ "id": 16777234, "type": 10003, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
                        Text.fontSize({ "id": 16777261, "type": 10002, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
                        Text.fontWeight(FontWeight.Medium);
                        Text.fontColor({ "id": 16777250, "type": 10001, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
                    }, Text);
                    Text.pop();
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Text.create({ "id": 16777233, "type": 10003, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
                        Text.fontSize({ "id": 16777254, "type": 10002, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
                        Text.fontColor({ "id": 16777251, "type": 10001, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
                    }, Text);
                    Text.pop();
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Button.createWithLabel({ "id": 16777240, "type": 10003, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
                        Button.height({ "id": 16777255, "type": 10002, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
                        Button.onClick(() => {
                            this.loadNotebookList();
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
                                __Common__.create();
                                __Common__.onClick(() => {
                                    this.openNotebook(notebook.id);
                                });
                            }, __Common__);
                            {
                                this.observeComponentCreation2((elmtId, isInitialRender) => {
                                    if (isInitialRender) {
                                        let componentCall = new NotebookCard(this, {
                                            title: notebook.title,
                                            updatedAtText: `${{ "id": 16777241, "type": 10003, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" }}${this.formatTimestamp(notebook.updatedAt)}`
                                        }, undefined, elmtId, () => { }, { page: "entry/src/main/ets/features/notebook/pages/NotebookListPage.ets", line: 152, col: 15 });
                                        ViewPU.create(componentCall);
                                        let paramsLambda = () => {
                                            return {
                                                title: notebook.title,
                                                updatedAtText: `${{ "id": 16777241, "type": 10003, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" }}${this.formatTimestamp(notebook.updatedAt)}`
                                            };
                                        };
                                        componentCall.paramsGenerator_ = paramsLambda;
                                    }
                                    else {
                                        this.updateStateVarsOfChildByElmtId(elmtId, {});
                                    }
                                }, { name: "NotebookCard" });
                            }
                            __Common__.pop();
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
    }
    rerender() {
        this.updateDirtyElements();
    }
    static getEntryName(): string {
        return "NotebookListPage";
    }
}
registerNamedRoute(() => new NotebookListPage(undefined, {}), "", { bundleName: "com.example.hosn", moduleName: "entry", pagePath: "features/notebook/pages/NotebookListPage", pageFullPath: "entry/src/main/ets/features/notebook/pages/NotebookListPage", integratedHsp: "false", moduleType: "followWithHap" });
