if (!("finalizeConstruction" in ViewPU.prototype)) {
    Reflect.set(ViewPU.prototype, "finalizeConstruction", () => { });
}
interface CreateNotebookDialog_Params {
    title?: string;
    isRenameMode?: boolean;
    isSubmitting?: boolean;
    onCancel?: () => void;
    onConfirm?: () => void;
}
export class CreateNotebookDialog extends ViewPU {
    constructor(parent, params, __localStorage, elmtId = -1, paramsLambda = undefined, extraInfo) {
        super(parent, __localStorage, elmtId, extraInfo);
        if (typeof paramsLambda === "function") {
            this.paramsGenerator_ = paramsLambda;
        }
        this.__title = new SynchedPropertySimpleTwoWayPU(params.title, this, "title");
        this.isRenameMode = false;
        this.isSubmitting = false;
        this.onCancel = (): void => { };
        this.onConfirm = (): void => { };
        this.setInitiallyProvidedValue(params);
        this.finalizeConstruction();
    }
    setInitiallyProvidedValue(params: CreateNotebookDialog_Params) {
        if (params.isRenameMode !== undefined) {
            this.isRenameMode = params.isRenameMode;
        }
        if (params.isSubmitting !== undefined) {
            this.isSubmitting = params.isSubmitting;
        }
        if (params.onCancel !== undefined) {
            this.onCancel = params.onCancel;
        }
        if (params.onConfirm !== undefined) {
            this.onConfirm = params.onConfirm;
        }
    }
    updateStateVars(params: CreateNotebookDialog_Params) {
    }
    purgeVariableDependenciesOnElmtId(rmElmtId) {
        this.__title.purgeDependencyOnElmtId(rmElmtId);
    }
    aboutToBeDeleted() {
        this.__title.aboutToBeDeleted();
        SubscriberManager.Get().delete(this.id__());
        this.aboutToBeDeletedInternal();
    }
    private __title: SynchedPropertySimpleTwoWayPU<string>;
    get title() {
        return this.__title.get();
    }
    set title(newValue: string) {
        this.__title.set(newValue);
    }
    private isRenameMode: boolean;
    private isSubmitting: boolean;
    private onCancel: () => void;
    private onConfirm: () => void;
    initialRender() {
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
            Column.create({ space: 6 });
            Column.width('100%');
            Column.alignItems(HorizontalAlign.Start);
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(this.isRenameMode ? { "id": 16777260, "type": 10003, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" } : { "id": 16777240, "type": 10003, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
            Text.fontSize({ "id": 16777293, "type": 10002, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
            Text.fontWeight(FontWeight.Bold);
            Text.fontColor({ "id": 16777282, "type": 10001, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(this.isRenameMode ? { "id": 16777259, "type": 10003, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" } : { "id": 16777239, "type": 10003, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
            Text.fontSize({ "id": 16777288, "type": 10002, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
            Text.fontColor({ "id": 16777283, "type": 10001, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
        }, Text);
        Text.pop();
        Column.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            TextInput.create({
                placeholder: this.isRenameMode ? { "id": 16777261, "type": 10003, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" } : { "id": 16777242, "type": 10003, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" },
                text: this.title
            });
            TextInput.width('100%');
            TextInput.height({ "id": 16777287, "type": 10002, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
            TextInput.fontSize({ "id": 16777286, "type": 10002, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
            TextInput.backgroundColor({ "id": 16777276, "type": 10001, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
            TextInput.borderRadius({ "id": 16777289, "type": 10002, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
            TextInput.padding({
                left: 16,
                right: 16
            });
            TextInput.onChange((value: string) => {
                this.title = value;
            });
        }, TextInput);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(this.isRenameMode ? { "id": 16777262, "type": 10003, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" } : { "id": 16777243, "type": 10003, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
            Text.width('100%');
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
                if (!this.isSubmitting) {
                    this.onCancel();
                }
            });
        }, Button);
        Button.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Button.createWithLabel(this.isSubmitting
                ? (this.isRenameMode ? { "id": 16777263, "type": 10003, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" } : { "id": 16777244, "type": 10003, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" })
                : (this.isRenameMode ? { "id": 16777258, "type": 10003, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" } : { "id": 16777238, "type": 10003, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" }));
            Button.layoutWeight(1);
            Button.height({ "id": 16777287, "type": 10002, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
            Button.backgroundColor({ "id": 16777282, "type": 10001, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
            Button.fontColor({ "id": 16777280, "type": 10001, params: [], "bundleName": "com.example.hosn", "moduleName": "entry" });
            Button.onClick(() => {
                if (!this.isSubmitting) {
                    this.onConfirm();
                }
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
