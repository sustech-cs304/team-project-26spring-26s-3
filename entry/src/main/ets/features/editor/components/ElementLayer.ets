import common from '@ohos.app.ability.common';

import { CanvasElement, ImageCanvasElement, TextCanvasElement } from '../../../domain/entities/CanvasElement';
import {
  DrawingEditorViewModel,
  ImageElementEditDraft
} from '../viewmodels/DrawingEditorViewModel';
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
  @Watch('onAutoCreateSessionChanged')
  @Prop autoCreateSession: boolean = true;
  @Prop editingElementId: string = '';
  @Prop renderContent: boolean = true;
  @Prop renderSelection: boolean = true;
  @Prop minZIndex: number = -1000000000;
  @Prop maxZIndex: number = 1000000000;
  @State private elements: CanvasElement[] = [];
  @State private selectedElementIds: string[] = [];
  @State private imageElementEditDraft: ImageElementEditDraft | null = null;
  private viewModel: DrawingEditorViewModel | null = null;

  aboutToAppear(): void {
    this.resolveViewModel();
    this.reloadElements();
  }

  build() {
    Stack() {
      ForEach(this.elements, (element: CanvasElement) => {
        if (this.shouldRenderElementContent(element)) {
          this.buildElement(element);
        }
      }, (element: CanvasElement): string => this.getElementRenderKey(element))

      ForEach(this.elements, (element: CanvasElement) => {
        if (this.shouldRenderElementSelection(element)) {
          ElementSelectionOverlay({ element: this.applyImageElementEditDraftFrame(element) })
        }
      }, (element: CanvasElement): string => this.getSelectionRenderKey(this.applyImageElementEditDraftFrame(element)))
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
      ShapeElementView({ element: element, renderVersion: this.refreshVersion })
    } else if (element.type === 'image') {
      ImageElementView({
        element: element,
        renderVersion: this.refreshVersion,
        translateX: this.getImageElementDraftTranslateX(element),
        translateY: this.getImageElementDraftTranslateY(element),
        scaleX: this.getImageElementDraftScaleX(element),
        scaleY: this.getImageElementDraftScaleY(element)
      })
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
    return `selection_${element.id}_${this.selectedElementIds.join('_')}_${element.updatedAt}_${element.x}_${element.y}_${element.width}_${element.height}_${element.zIndex}`;
  }

  private getElementRenderKey(element: CanvasElement): string {
    const geometryKey = `${element.x}_${element.y}_${element.width}_${element.height}_${element.zIndex}`;
    if (element.type === 'shape') {
      return `${element.id}_${element.updatedAt}_${geometryKey}_${element.outline.lineStyle}_${element.outline.color}_${element.outline.width}_${element.fillColor}`;
    }

    if (element.type === 'image') {
      return `${element.id}_${element.updatedAt}_${geometryKey}_${element.outline.lineStyle}_${element.outline.color}_${element.outline.width}`;
    }

    return `${element.id}_${element.updatedAt}_${geometryKey}`;
  }

  private onPageIdChanged(): void {
    this.resolveViewModel();
    this.reloadElements();
  }

  private onRefreshVersionChanged(): void {
    this.reloadElements();
  }

  private onAutoCreateSessionChanged(): void {
    this.resolveViewModel();
    this.reloadElements();
  }

  private reloadElements(): void {
    const viewModel = this.getViewModel();
    this.elements = viewModel === null ? [] : viewModel.getElementsForRendering();
    this.selectedElementIds = viewModel === null ? [] : viewModel.getSelectedElementIds();
    this.imageElementEditDraft = viewModel === null ? null : viewModel.getImageElementEditDraft();
  }

  private shouldRenderElementContent(element: CanvasElement): boolean {
    return this.renderContent &&
      element.id !== this.editingElementId &&
      element.zIndex >= this.minZIndex &&
      element.zIndex < this.maxZIndex;
  }

  private shouldRenderElementSelection(element: CanvasElement): boolean {
    return this.renderSelection &&
      this.selectedElementIds.includes(element.id) &&
      element.id !== this.editingElementId;
  }

  private applyImageElementEditDraftFrame(element: CanvasElement): CanvasElement {
    if (this.imageElementEditDraft === null || element.type !== 'image' || element.id !== this.imageElementEditDraft.elementId) {
      return element;
    }

    const imageElement = element as ImageCanvasElement;
    return {
      id: imageElement.id,
      pageId: imageElement.pageId,
      type: imageElement.type,
      x: this.imageElementEditDraft.currentFrame.x,
      y: this.imageElementEditDraft.currentFrame.y,
      width: this.imageElementEditDraft.currentFrame.width,
      height: this.imageElementEditDraft.currentFrame.height,
      rotation: imageElement.rotation,
      zIndex: imageElement.zIndex,
      createdAt: imageElement.createdAt,
      updatedAt: imageElement.updatedAt,
      uri: imageElement.uri,
      originalWidth: imageElement.originalWidth,
      originalHeight: imageElement.originalHeight,
      opacity: imageElement.opacity,
      outline: imageElement.outline,
      sourceFileUri: imageElement.sourceFileUri,
      sourceFileType: imageElement.sourceFileType
    };
  }

  private getImageElementDraftTranslateX(element: CanvasElement): number {
    if (this.imageElementEditDraft === null || element.type !== 'image' || element.id !== this.imageElementEditDraft.elementId) {
      return 0;
    }

    return this.imageElementEditDraft.currentFrame.x - this.imageElementEditDraft.originalFrame.x;
  }

  private getImageElementDraftTranslateY(element: CanvasElement): number {
    if (this.imageElementEditDraft === null || element.type !== 'image' || element.id !== this.imageElementEditDraft.elementId) {
      return 0;
    }

    return this.imageElementEditDraft.currentFrame.y - this.imageElementEditDraft.originalFrame.y;
  }

  private getImageElementDraftScaleX(element: CanvasElement): number {
    if (this.imageElementEditDraft === null || element.type !== 'image' || element.id !== this.imageElementEditDraft.elementId) {
      return 1;
    }

    return this.imageElementEditDraft.currentFrame.width / Math.max(1, this.imageElementEditDraft.originalFrame.width);
  }

  private getImageElementDraftScaleY(element: CanvasElement): number {
    if (this.imageElementEditDraft === null || element.type !== 'image' || element.id !== this.imageElementEditDraft.elementId) {
      return 1;
    }

    return this.imageElementEditDraft.currentFrame.height / Math.max(1, this.imageElementEditDraft.originalFrame.height);
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
      this.imageElementEditDraft = null;
      return;
    }

    const existingSession = EditorSessionRegistry.get(this.pageId);
    if (existingSession !== null) {
      this.viewModel = existingSession;
      return;
    }

    if (!this.autoCreateSession) {
      this.viewModel = null;
      this.imageElementEditDraft = null;
      return;
    }

    this.viewModel = EditorSessionRegistry.getOrCreate(
      this.pageId,
      this.getUIContext().getHostContext() as common.Context
    );
  }
}
