if (!("finalizeConstruction" in ViewPU.prototype)) {
    Reflect.set(ViewPU.prototype, "finalizeConstruction", () => { });
}
interface NotebookListPage_Params {
}
import { AppRouter } from "@bundle:com.example.hosn/entry/ets/app/AppRouter";
import type { RouterParams } from "@bundle:com.example.hosn/entry/ets/app/AppRouter";
class NotebookListPage extends ViewPU {
    constructor(parent, params, __localStorage, elmtId = -1, paramsLambda = undefined, extraInfo) {
        super(parent, __localStorage, elmtId, extraInfo);
        if (typeof paramsLambda === "function") {
            this.paramsGenerator_ = paramsLambda;
        }
        this.setInitiallyProvidedValue(params);
        this.finalizeConstruction();
    }
    setInitiallyProvidedValue(params: NotebookListPage_Params) {
    }
    updateStateVars(params: NotebookListPage_Params) {
    }
    purgeVariableDependenciesOnElmtId(rmElmtId) {
    }
    aboutToBeDeleted() {
        SubscriberManager.Get().delete(this.id__());
        this.aboutToBeDeletedInternal();
    }
    initialRender() {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create({ space: 20 });
            Column.width('100%');
            Column.height('100%');
            Column.alignItems(HorizontalAlign.Start);
            Column.padding({
                left: { "id": 16777255, "type": 10002, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" },
                right: { "id": 16777255, "type": 10002, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" },
                top: { "id": 16777256, "type": 10002, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" },
                bottom: { "id": 16777256, "type": 10002, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" }
            });
            Column.backgroundColor({ "id": 16777244, "type": 10001, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create({ space: 8 });
            Column.width('100%');
            Column.alignItems(HorizontalAlign.Start);
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create({ "id": 16777237, "type": 10003, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
            Text.fontSize({ "id": 16777254, "type": 10002, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
            Text.fontWeight(FontWeight.Bold);
            Text.fontColor({ "id": 16777246, "type": 10001, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create({ "id": 16777236, "type": 10003, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
            Text.fontSize({ "id": 16777250, "type": 10002, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
            Text.fontColor({ "id": 16777247, "type": 10001, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
        }, Text);
        Text.pop();
        Column.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create({ space: 12 });
            Column.width('100%');
            Column.alignItems(HorizontalAlign.Start);
            Column.padding(20);
            Column.backgroundColor({ "id": 16777249, "type": 10001, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
            Column.borderRadius({ "id": 16777253, "type": 10002, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
            Column.border({
                width: 1,
                color: { "id": 16777245, "type": 10001, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" }
            });
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create({ "id": 16777234, "type": 10003, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
            Text.fontSize({ "id": 16777257, "type": 10002, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
            Text.fontWeight(FontWeight.Medium);
            Text.fontColor({ "id": 16777246, "type": 10001, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create({ "id": 16777233, "type": 10003, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
            Text.fontSize({ "id": 16777252, "type": 10002, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
            Text.fontColor({ "id": 16777247, "type": 10001, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Row.create({ space: 12 });
            Row.width('100%');
        }, Row);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Button.createWithLabel({ "id": 16777235, "type": 10003, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
            Button.layoutWeight(1);
            Button.height({ "id": 16777251, "type": 10002, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
            Button.onClick(() => {
                const params: RouterParams = {
                    notebookId: 'demo-notebook'
                };
                AppRouter.openEditor(params);
            });
        }, Button);
        Button.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Button.createWithLabel({ "id": 16777232, "type": 10003, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
            Button.layoutWeight(1);
            Button.height({ "id": 16777251, "type": 10002, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
            Button.onClick(() => {
                AppRouter.goHome();
            });
        }, Button);
        Button.pop();
        Row.pop();
        Column.pop();
        Column.pop();
    }
    rerender() {
        this.updateDirtyElements();
    }
    static getEntryName(): string {
        return "NotebookListPage";
    }
}
registerNamedRoute(() => new NotebookListPage(undefined, {}), "", { bundleName: "com.example.hosn", moduleName: "entry", pagePath: "features/notebook/pages/NotebookListPage", pageFullPath: "entry/src/main/ets/features/notebook/pages/NotebookListPage", integratedHsp: "false", moduleType: "followWithHap" });
