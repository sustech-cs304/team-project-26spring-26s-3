if (!("finalizeConstruction" in ViewPU.prototype)) {
    Reflect.set(ViewPU.prototype, "finalizeConstruction", () => { });
}
interface SortMenu_Params {
    selectedSortType?: NotebookSortType;
}
import { NotebookSortType } from "@bundle:com.example.hosn/entry/ets/domain/repositories/NotebookRepository";
export class SortMenu extends ViewPU {
    constructor(parent, params, __localStorage, elmtId = -1, paramsLambda = undefined, extraInfo) {
        super(parent, __localStorage, elmtId, extraInfo);
        if (typeof paramsLambda === "function") {
            this.paramsGenerator_ = paramsLambda;
        }
        this.__selectedSortType = new SynchedPropertySimpleTwoWayPU(params.selectedSortType, this, "selectedSortType");
        this.setInitiallyProvidedValue(params);
        this.finalizeConstruction();
    }
    setInitiallyProvidedValue(params: SortMenu_Params) {
    }
    updateStateVars(params: SortMenu_Params) {
    }
    purgeVariableDependenciesOnElmtId(rmElmtId) {
        this.__selectedSortType.purgeDependencyOnElmtId(rmElmtId);
    }
    aboutToBeDeleted() {
        this.__selectedSortType.aboutToBeDeleted();
        SubscriberManager.Get().delete(this.id__());
        this.aboutToBeDeletedInternal();
    }
    private __selectedSortType: SynchedPropertySimpleTwoWayPU<NotebookSortType>;
    get selectedSortType() {
        return this.__selectedSortType.get();
    }
    set selectedSortType(newValue: NotebookSortType) {
        this.__selectedSortType.set(newValue);
    }
    initialRender() {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create({ space: 12 });
            Column.width('100%');
            Column.alignItems(HorizontalAlign.Start);
            Column.padding(20);
            Column.backgroundColor({ "id": 16777285, "type": 10001, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
            Column.borderRadius({ "id": 16777289, "type": 10002, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
            Column.border({
                width: 1,
                color: { "id": 16777277, "type": 10001, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" }
            });
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create({ space: 4 });
            Column.width('100%');
            Column.alignItems(HorizontalAlign.Start);
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create({ "id": 16777266, "type": 10003, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
            Text.fontSize({ "id": 16777293, "type": 10002, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
            Text.fontWeight(FontWeight.Medium);
            Text.fontColor({ "id": 16777282, "type": 10001, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create({ "id": 16777265, "type": 10003, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
            Text.fontSize({ "id": 16777288, "type": 10002, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
            Text.fontColor({ "id": 16777283, "type": 10001, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
        }, Text);
        Text.pop();
        Column.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Row.create({ space: 8 });
            Row.width('100%');
        }, Row);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Button.createWithLabel({ "id": 16777268, "type": 10003, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
            Button.layoutWeight(1);
            Button.height({ "id": 16777287, "type": 10002, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
            Button.backgroundColor(this.selectedSortType === NotebookSortType.UPDATED_DESC ? { "id": 16777282, "type": 10001, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" } : { "id": 16777276, "type": 10001, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
            Button.fontColor(this.selectedSortType === NotebookSortType.UPDATED_DESC ? { "id": 16777280, "type": 10001, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" } : { "id": 16777282, "type": 10001, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
            Button.border({
                width: 1,
                color: this.selectedSortType === NotebookSortType.UPDATED_DESC ? { "id": 16777282, "type": 10001, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" } : { "id": 16777277, "type": 10001, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" }
            });
            Button.onClick(() => {
                this.selectedSortType = NotebookSortType.UPDATED_DESC;
            });
        }, Button);
        Button.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Button.createWithLabel({ "id": 16777264, "type": 10003, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
            Button.layoutWeight(1);
            Button.height({ "id": 16777287, "type": 10002, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
            Button.backgroundColor(this.selectedSortType === NotebookSortType.CREATED_DESC ? { "id": 16777282, "type": 10001, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" } : { "id": 16777276, "type": 10001, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
            Button.fontColor(this.selectedSortType === NotebookSortType.CREATED_DESC ? { "id": 16777280, "type": 10001, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" } : { "id": 16777282, "type": 10001, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
            Button.border({
                width: 1,
                color: this.selectedSortType === NotebookSortType.CREATED_DESC ? { "id": 16777282, "type": 10001, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" } : { "id": 16777277, "type": 10001, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" }
            });
            Button.onClick(() => {
                this.selectedSortType = NotebookSortType.CREATED_DESC;
            });
        }, Button);
        Button.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Button.createWithLabel({ "id": 16777267, "type": 10003, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
            Button.layoutWeight(1);
            Button.height({ "id": 16777287, "type": 10002, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
            Button.backgroundColor(this.selectedSortType === NotebookSortType.TITLE_ASC ? { "id": 16777282, "type": 10001, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" } : { "id": 16777276, "type": 10001, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
            Button.fontColor(this.selectedSortType === NotebookSortType.TITLE_ASC ? { "id": 16777280, "type": 10001, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" } : { "id": 16777282, "type": 10001, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
            Button.border({
                width: 1,
                color: this.selectedSortType === NotebookSortType.TITLE_ASC ? { "id": 16777282, "type": 10001, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" } : { "id": 16777277, "type": 10001, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" }
            });
            Button.onClick(() => {
                this.selectedSortType = NotebookSortType.TITLE_ASC;
            });
        }, Button);
        Button.pop();
        Row.pop();
        Column.pop();
    }
    rerender() {
        this.updateDirtyElements();
    }
}
