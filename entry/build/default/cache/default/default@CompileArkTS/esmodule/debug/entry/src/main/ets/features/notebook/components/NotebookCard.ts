if (!("finalizeConstruction" in ViewPU.prototype)) {
    Reflect.set(ViewPU.prototype, "finalizeConstruction", () => { });
}
interface NotebookCard_Params {
    title?: string;
    updatedAtText?: string;
}
export class NotebookCard extends ViewPU {
    constructor(parent, params, __localStorage, elmtId = -1, paramsLambda = undefined, extraInfo) {
        super(parent, __localStorage, elmtId, extraInfo);
        if (typeof paramsLambda === "function") {
            this.paramsGenerator_ = paramsLambda;
        }
        this.title = '';
        this.updatedAtText = '';
        this.setInitiallyProvidedValue(params);
        this.finalizeConstruction();
    }
    setInitiallyProvidedValue(params: NotebookCard_Params) {
        if (params.title !== undefined) {
            this.title = params.title;
        }
        if (params.updatedAtText !== undefined) {
            this.updatedAtText = params.updatedAtText;
        }
    }
    updateStateVars(params: NotebookCard_Params) {
    }
    purgeVariableDependenciesOnElmtId(rmElmtId) {
    }
    aboutToBeDeleted() {
        SubscriberManager.Get().delete(this.id__());
        this.aboutToBeDeletedInternal();
    }
    private title: string;
    private updatedAtText: string;
    initialRender() {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create({ space: 8 });
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
            Text.create(this.title);
            Text.fontSize({ "id": 16777293, "type": 10002, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
            Text.fontWeight(FontWeight.Medium);
            Text.fontColor({ "id": 16777282, "type": 10001, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
            Text.maxLines(2);
            Text.textOverflow({ overflow: TextOverflow.Ellipsis });
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(this.updatedAtText);
            Text.fontSize({ "id": 16777288, "type": 10002, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
            Text.fontColor({ "id": 16777283, "type": 10001, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
            Text.maxLines(1);
        }, Text);
        Text.pop();
        Column.pop();
    }
    rerender() {
        this.updateDirtyElements();
    }
}
