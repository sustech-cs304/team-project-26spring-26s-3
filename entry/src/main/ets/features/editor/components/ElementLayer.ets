import common from '@ohos.app.ability.common';

import { CanvasElement, ShapeCanvasElement, TextCanvasElement } from '../../../domain/entities/CanvasElement';
import { DrawingEditorViewModel } from '../viewmodels/DrawingEditorViewModel';
import { EditorSessionRegistry } from '../viewmodels/EditorSessionRegistry';

@Component
export struct ElementLayer {
  @Watch('onPageIdChanged')
  @Prop pageId: string = '';
  @Watch('onRefreshVersionChanged')
  @Prop refreshVersion: number = 0;

  @State private elements: CanvasElement[] = [];
  private viewModel: DrawingEditorViewModel | null = null;

  aboutToAppear(): void {
    this.resolveViewModel();
    this.reloadElements();
  }

  build() {
    Stack() {
      ForEach(this.elements, (element: CanvasElement) => {
        this.buildElement(element);
      }, (element: CanvasElement): string => `${element.id}_${element.updatedAt}`)
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.None)
  }

  @Builder
  private buildElement(element: CanvasElement): void {
    if (element.type === 'text') {
      this.buildTextElement(element);
    } else if (element.type === 'shape') {
      this.buildShapeElement(element);
    }
  }

  @Builder
  private buildTextElement(element: TextCanvasElement): void {
    Text(this.getDisplayText(element))
      .width(element.width)
      .height(element.height)
      .position({
        x: element.x,
        y: element.y
      })
      .padding({
        left: 8,
        right: 8,
        top: 6,
        bottom: 6
      })
      .fontSize(Math.max(8, element.fontSize))
      .fontColor(element.color)
      .backgroundColor(element.backgroundColor)
      .textAlign(TextAlign.Start)
      .zIndex(element.zIndex)
      .hitTestBehavior(HitTestMode.None)
  }

  private getDisplayText(element: TextCanvasElement): string {
    return element.content.length === 0 ? 'Text' : element.content;
  }

  @Builder
  private buildShapeElement(element: ShapeCanvasElement): void {
    if (element.shapeType === 'rectangle') {
      this.buildRectangleShapeElement(element);
    } else if (element.shapeType === 'circle') {
      this.buildCircleShapeElement(element);
    } else if (element.shapeType === 'line') {
      this.buildLineShapeElement(element);
    }
  }

  @Builder
  private buildRectangleShapeElement(element: ShapeCanvasElement): void {
    Column() {}
      .width(element.width)
      .height(element.height)
      .position({
        x: element.x,
        y: element.y
      })
      .backgroundColor(element.fillColor)
      .border({
        width: element.strokeWidth,
        color: element.strokeColor
      })
      .opacity(element.opacity)
      .zIndex(element.zIndex)
      .hitTestBehavior(HitTestMode.None)
  }

  @Builder
  private buildCircleShapeElement(element: ShapeCanvasElement): void {
    Column() {}
      .width(element.width)
      .height(element.height)
      .position({
        x: element.x,
        y: element.y
      })
      .backgroundColor(element.fillColor)
      .borderRadius('50%')
      .border({
        width: element.strokeWidth,
        color: element.strokeColor
      })
      .opacity(element.opacity)
      .zIndex(element.zIndex)
      .hitTestBehavior(HitTestMode.None)
  }

  @Builder
  private buildLineShapeElement(element: ShapeCanvasElement): void {
    Column() {}
      .width(element.width)
      .height(Math.max(1, element.strokeWidth))
      .position({
        x: element.x,
        y: element.y + Math.max(0, (element.height - Math.max(1, element.strokeWidth)) / 2)
      })
      .backgroundColor(element.strokeColor)
      .opacity(element.opacity)
      .zIndex(element.zIndex)
      .hitTestBehavior(HitTestMode.None)
  }

  private onPageIdChanged(): void {
    this.resolveViewModel();
    this.reloadElements();
  }

  private onRefreshVersionChanged(): void {
    this.reloadElements();
  }

  private reloadElements(): void {
    const viewModel = this.getViewModel();
    this.elements = viewModel === null ? [] : viewModel.getElements();
  }

  private getViewModel(): DrawingEditorViewModel | null {
    if (!this.viewModel) {
      this.resolveViewModel();
    }

    return this.viewModel;
  }

  private resolveViewModel(): void {
    if (this.pageId.length === 0) {
      this.viewModel = null;
      this.elements = [];
      return;
    }

    this.viewModel = EditorSessionRegistry.getOrCreate(
      this.pageId,
      this.getUIContext().getHostContext() as common.Context
    );
  }
}
