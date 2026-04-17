if (!("finalizeConstruction" in ViewPU.prototype)) {
    Reflect.set(ViewPU.prototype, "finalizeConstruction", () => { });
}
interface EditorPage_Params {
}
import { AppRouter } from "@bundle:com.example.hosn/entry/ets/app/AppRouter";
class EditorPage extends ViewPU {
    constructor(parent, params, __localStorage, elmtId = -1, paramsLambda = undefined, extraInfo) {
        super(parent, __localStorage, elmtId, extraInfo);
        if (typeof paramsLambda === "function") {
            this.paramsGenerator_ = paramsLambda;
        }
        this.setInitiallyProvidedValue(params);
        this.finalizeConstruction();
    }
    setInitiallyProvidedValue(params: EditorPage_Params) {
    }
    updateStateVars(params: EditorPage_Params) {
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
            Text.create({ "id": 16777226, "type": 10003, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
            Text.fontSize({ "id": 16777254, "type": 10002, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
            Text.fontWeight(FontWeight.Bold);
            Text.fontColor({ "id": 16777246, "type": 10001, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create({ "id": 16777224, "type": 10003, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
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
            Text.create({ "id": 16777225, "type": 10003, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
            Text.fontSize({ "id": 16777252, "type": 10002, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
            Text.fontColor({ "id": 16777247, "type": 10001, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Button.createWithLabel({ "id": 16777223, "type": 10003, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
            Button.width('100%');
            Button.height({ "id": 16777251, "type": 10002, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
            Button.onClick(() => {
                AppRouter.goHome();
            });
        }, Button);
        Button.pop();
        Column.pop();
        Column.pop();
    }
    rerender() {
        this.updateDirtyElements();
    }
    static getEntryName(): string {
        return "EditorPage";
    }
}
registerNamedRoute(() => new EditorPage(undefined, {}), "", { bundleName: "com.example.hosn", moduleName: "entry", pagePath: "features/editor/pages/EditorPage", pageFullPath: "entry/src/main/ets/features/editor/pages/EditorPage", integratedHsp: "false", moduleType: "followWithHap" });
