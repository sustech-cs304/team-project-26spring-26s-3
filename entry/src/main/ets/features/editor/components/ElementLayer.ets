import common from '@ohos.app.ability.common';

import { ElementFrame } from '../../../common/utils/ElementBoundsUtil';
import { CanvasElement, ImageCanvasElement, TextCanvasElement } from '../../../domain/entities/CanvasElement';
import {
  DrawingEditorViewModel,
  ImageElementEditDraft
} from '../viewmodels/DrawingEditorViewModel';
import { EditorSessionRegistry } from '../viewmodels/EditorSessionRegistry';
import { ElementSelectionOverlay } from './ElementSelectionOverlay';
import { FormulaElementView } from './FormulaElementView';
import { ShapeElementView } from './ShapeElementView';
import { StableImageElementView } from './StableImageElementView';
import { TextElementView } from './TextElementView';

const ELEMENT_LAYER_Z_INDEX_MIN = -1000000000;
const ELEMENT_LAYER_Z_INDEX_MAX = 1000000000;

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
  @Prop minZIndex: number = ELEMENT_LAYER_Z_INDEX_MIN;
  @Prop maxZIndex: number = ELEMENT_LAYER_Z_INDEX_MAX;
  @Prop contentLayerRole: string = 'all';
  @Prop imageContentReadyElementId: string = '';
  @Prop imageContentReadyRole: string = '';
  @Prop imageContentReadyToken: number = 0;
  @State private elements: CanvasElement[] = [];
  @State private selectedElementIds: string[] = [];
  @State private imageElementEditDraft: ImageElementEditDraft | null = null;
  onImageContentReady: (elementId: string, token: number) => void =
    (_elementId: string, _token: number): void => {};
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
      this.buildImageElement(element);
    }
  }

  @Builder
  private buildImageElement(element: ImageCanvasElement): void {
    StableImageElementView({
      element: this.getImageElementForDisplay(element),
      contentReadyToken: this.imageContentReadyToken,
      reportContentReady: this.shouldTrackImageContentReady(element),
      onContentReady: (elementId: string, token: number): void => {
        this.onImageContentReady(elementId, token);
      }
    })
  }

  @Builder
  private buildFormulaElement(element: TextCanvasElement): void {
    FormulaElementView({ element })
  }

  @Builder
  private buildTextElement(element: TextCanvasElement): void {
    TextElementView({ element })
  }

  private shouldRenderFormula(element: TextCanvasElement): boolean {
    return element.recognition?.source === 'formula' &&
      typeof element.recognition.latex === 'string' &&
      element.recognition.latex.trim().length > 0;
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
      return this.getImageElementRenderKey(element as ImageCanvasElement);
    }

    const textElement = element as TextCanvasElement;
    return `${element.id}_${element.updatedAt}_${geometryKey}_${textElement.backgroundColor}_${textElement.outline.lineStyle}_${textElement.outline.color}_${textElement.outline.width}`;
  }

  private getImageElementRenderKey(element: ImageCanvasElement): string {
    const currentElement = this.getCurrentImageElement(element);
    return `${currentElement.id}_${currentElement.uri}_${currentElement.sourceFileUri ?? ''}_${currentElement.sourceFileType ?? ''}`;
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
    if (element.type === 'image') {
      const currentElement = this.getCurrentImageElement(element as ImageCanvasElement);
      return this.renderContent &&
        currentElement.id !== this.editingElementId &&
        currentElement.zIndex >= this.minZIndex &&
        currentElement.zIndex < this.maxZIndex;
    }

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
    if (element.type !== 'image') {
      return element;
    }

    const imageElement = this.getCurrentImageElement(element as ImageCanvasElement);
    if (this.imageElementEditDraft === null || imageElement.id !== this.imageElementEditDraft.elementId) {
      return imageElement;
    }

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

  private getImageElementDisplayFrame(element: ImageCanvasElement): ElementFrame {
    const currentElement = this.getCurrentImageElement(element);
    if (this.imageElementEditDraft !== null && currentElement.id === this.imageElementEditDraft.elementId) {
      return {
        x: this.imageElementEditDraft.currentFrame.x,
        y: this.imageElementEditDraft.currentFrame.y,
        width: this.imageElementEditDraft.currentFrame.width,
        height: this.imageElementEditDraft.currentFrame.height
      };
    }

    return {
      x: currentElement.x,
      y: currentElement.y,
      width: currentElement.width,
      height: currentElement.height
    };
  }

  private getImageElementForDisplay(element: ImageCanvasElement): ImageCanvasElement {
    const currentElement = this.getCurrentImageElement(element);
    const displayFrame = this.getImageElementDisplayFrame(currentElement);
    return {
      id: currentElement.id,
      pageId: currentElement.pageId,
      type: currentElement.type,
      x: displayFrame.x,
      y: displayFrame.y,
      width: displayFrame.width,
      height: displayFrame.height,
      rotation: currentElement.rotation,
      zIndex: currentElement.zIndex,
      createdAt: currentElement.createdAt,
      updatedAt: currentElement.updatedAt,
      uri: currentElement.uri,
      originalWidth: currentElement.originalWidth,
      originalHeight: currentElement.originalHeight,
      opacity: currentElement.opacity,
      outline: currentElement.outline,
      sourceFileUri: currentElement.sourceFileUri,
      sourceFileType: currentElement.sourceFileType
    };
  }

  private shouldTrackImageContentReady(element: ImageCanvasElement): boolean {
    return this.contentLayerRole === this.imageContentReadyRole &&
      this.imageContentReadyElementId.length > 0 &&
      element.id === this.imageContentReadyElementId &&
      this.imageContentReadyToken > 0;
  }

  private getCurrentImageElement(element: ImageCanvasElement): ImageCanvasElement {
    const currentElement = this.elements.find((candidate: CanvasElement): boolean =>
      candidate.type === 'image' && candidate.id === element.id) as ImageCanvasElement | undefined;
    return currentElement === undefined ? element : currentElement;
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
