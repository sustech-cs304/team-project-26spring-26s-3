import common from '@ohos.app.ability.common';

import { CanvasElement, TextCanvasElement } from '../../../domain/entities/CanvasElement';
import { DrawingEditorViewModel } from '../viewmodels/DrawingEditorViewModel';
import { EditorSessionRegistry } from '../viewmodels/EditorSessionRegistry';
import { ElementSelectionOverlay } from './ElementSelectionOverlay';
import { ImageElementView } from './ImageElementView';
import { ShapeElementView } from './ShapeElementView';

@Component
export struct ElementLayer {
  @Watch('onPageIdChanged')
  @Prop pageId: string = '';
  @Watch('onRefreshVersionChanged')
  @Prop refreshVersion: number = 0;

  @State private elements: CanvasElement[] = [];
  @State private selectedElementId: string = '';
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

      ForEach(this.elements, (element: CanvasElement) => {
        if (element.id === this.selectedElementId) {
          ElementSelectionOverlay({ element: element })
        }
      }, (element: CanvasElement): string => this.getSelectionRenderKey(element))
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
      ShapeElementView({ element: element })
    } else if (element.type === 'image') {
      ImageElementView({ element: element })
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

  private getSelectionRenderKey(element: CanvasElement): string {
    return `selection_${element.id}_${this.selectedElementId}_${element.updatedAt}_${element.x}_${element.y}_${element.width}_${element.height}`;
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
    this.selectedElementId = viewModel === null ? '' : viewModel.getSelectedElementId();
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
      this.selectedElementId = '';
      return;
    }

    this.viewModel = EditorSessionRegistry.getOrCreate(
      this.pageId,
      this.getUIContext().getHostContext() as common.Context
    );
  }
}
