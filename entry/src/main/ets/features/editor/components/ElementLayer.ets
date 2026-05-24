import common from '@ohos.app.ability.common';

import { CanvasElement, TextCanvasElement } from '../../../domain/entities/CanvasElement';
import { DrawingEditorViewModel } from '../viewmodels/DrawingEditorViewModel';
import { EditorSessionRegistry } from '../viewmodels/EditorSessionRegistry';
import { ElementSelectionOverlay } from './ElementSelectionOverlay';
import { FormulaElementView } from './FormulaElementView';
import { ImageElementView } from './ImageElementView';
import { ShapeElementView } from './ShapeElementView';

const TEXT_LINE_HEIGHT_FACTOR = 1.35;

@Component
export struct ElementLayer {
  @Watch('onPageIdChanged')
  @Prop pageId: string = '';
  @Watch('onRefreshVersionChanged')
  @Prop refreshVersion: number = 0;
  @Prop editingElementId: string = '';
  @State private elements: CanvasElement[] = [];
  @State private selectedElementIds: string[] = [];
  private viewModel: DrawingEditorViewModel | null = null;

  aboutToAppear(): void {
    this.resolveViewModel();
    this.reloadElements();
  }

  build() {
    Stack() {
      ForEach(this.elements, (element: CanvasElement) => {
        if (element.id !== this.editingElementId) {
          this.buildElement(element);
        }
      }, (element: CanvasElement): string => `${element.id}_${element.updatedAt}`)

      ForEach(this.elements, (element: CanvasElement) => {
        if (this.selectedElementIds.includes(element.id) && element.id !== this.editingElementId) {
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
      if (this.shouldRenderFormula(element)) {
        this.buildFormulaElement(element);
      } else {
        this.buildTextElement(element);
      }
    } else if (element.type === 'shape') {
      ShapeElementView({ element: element })
    } else if (element.type === 'image') {
      ImageElementView({ element: element })
    }
  }

  @Builder
  private buildFormulaElement(element: TextCanvasElement): void {
    FormulaElementView({ element })
  }

  @Builder
  private buildTextElement(element: TextCanvasElement): void {
    TextArea({
      text: this.getDisplayText(element)
    })
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
      .lineHeight(this.getTextLineHeight(element))
      .fontFamily('monospace')
      .fontColor(element.color)
      .wordBreak(WordBreak.BREAK_ALL)
      .maxLines(1000)
      .barState(BarState.Off)
      .backgroundColor(element.backgroundColor)
      .zIndex(element.zIndex)
      .hitTestBehavior(HitTestMode.None)
  }

  private getDisplayText(element: TextCanvasElement): string {
    return element.content.length === 0 ? 'Text' : element.content;
  }

  private shouldRenderFormula(element: TextCanvasElement): boolean {
    return element.recognition?.source === 'formula' &&
      typeof element.recognition.latex === 'string' &&
      element.recognition.latex.trim().length > 0;
  }

  private getTextLineHeight(element: TextCanvasElement): number {
    return Math.max(8, element.fontSize) * TEXT_LINE_HEIGHT_FACTOR;
  }

  private getSelectionRenderKey(element: CanvasElement): string {
    return `selection_${element.id}_${this.selectedElementIds.join('_')}_${element.updatedAt}_${element.x}_${element.y}_${element.width}_${element.height}`;
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
    this.selectedElementIds = viewModel === null ? [] : viewModel.getSelectedElementIds();
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
      this.selectedElementIds = [];
      return;
    }

    this.viewModel = EditorSessionRegistry.getOrCreate(
      this.pageId,
      this.getUIContext().getHostContext() as common.Context
    );
  }
}
