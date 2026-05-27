import webview from '@ohos.web.webview';

import { TextCanvasElement } from '../../../domain/entities/CanvasElement';
import { TextElementOutlineView } from './TextElementOutlineView';

const DEFAULT_FORMULA_ELEMENT: TextCanvasElement = {
  id: '',
  pageId: '',
  type: 'text',
  x: 0,
  y: 0,
  width: 1,
  height: 1,
  rotation: 0,
  zIndex: 0,
  createdAt: 0,
  updatedAt: 0,
  content: '',
  color: '#111827',
  fontSize: 18,
  backgroundColor: '#00FFFFFF',
  outline: {
    lineStyle: 'none',
    color: '#111827',
    width: 2
  }
};

interface FormulaRenderPayload {
  latex: string;
  fallbackText: string;
  textColor: string;
  backgroundColor: string;
  fontSize: number;
}

@Component
export struct FormulaElementView {
  @Watch('onElementChanged')
  @Prop element: TextCanvasElement = DEFAULT_FORMULA_ELEMENT;

  private controller: webview.WebviewController = new webview.WebviewController();
  @State private isTemplateLoaded: boolean = false;
  @State private hasRenderFailure: boolean = false;
  @State private injectedPayloadKey: string = '';

  aboutToAppear(): void {
  }

  build() {
    Stack() {
      if (this.shouldUseWebFormulaRenderer()) {
        Web({
          src: $rawfile('formula/formula-template.html'),
          controller: this.controller
        })
          .width(this.element.width)
          .height(this.element.height)
          .position({
            x: this.element.x,
            y: this.element.y
          })
          .backgroundColor(this.element.backgroundColor)
          .javaScriptAccess(true)
          .fileAccess(true)
          .domStorageAccess(false)
          .zoomAccess(false)
          .mixedMode(MixedMode.None)
          .onPageEnd(() => {
            this.isTemplateLoaded = true;
            void this.injectFormulaPayload();
          })
          .onAppear(() => {
            void this.injectFormulaPayload();
          })
          .zIndex(this.element.zIndex)
          .hitTestBehavior(HitTestMode.None)
      } else {
        TextArea({
          text: this.getFallbackText()
        })
          .width(this.element.width)
          .height(this.element.height)
          .position({
            x: this.element.x,
            y: this.element.y
          })
          .padding({
            left: 8,
            right: 8,
            top: 6,
            bottom: 6
          })
          .fontSize(Math.max(8, this.element.fontSize))
          .lineHeight(this.getFallbackLineHeight())
          .fontFamily('monospace')
          .fontColor(this.element.color)
          .wordBreak(WordBreak.BREAK_ALL)
          .maxLines(1000)
          .barState(BarState.Off)
          .backgroundColor(this.element.backgroundColor)
          .zIndex(this.element.zIndex)
          .hitTestBehavior(HitTestMode.None)
      }

      TextElementOutlineView({ element: this.element })
    }
  }

  private onElementChanged(): void {
    this.hasRenderFailure = false;
    this.injectedPayloadKey = '';
    void this.injectFormulaPayload();
  }

  private shouldUseWebFormulaRenderer(): boolean {
    return !this.hasRenderFailure && this.getLatexContent().length > 0;
  }

  private getLatexContent(): string {
    return this.element.recognition?.latex?.trim() ?? '';
  }

  private getFallbackText(): string {
    return this.element.content.length === 0 ? 'Text' : this.element.content;
  }

  private getFallbackLineHeight(): number {
    return Math.max(8, this.element.fontSize) * 1.35;
  }

  private async injectFormulaPayload(): Promise<void> {
    if (!this.shouldUseWebFormulaRenderer() || !this.isTemplateLoaded) {
      return;
    }

    const payloadKey = `${this.element.id}_${this.element.updatedAt}_${this.getLatexContent()}`;
    if (this.injectedPayloadKey === payloadKey) {
      return;
    }

    const payload: FormulaRenderPayload = {
      latex: this.getLatexContent(),
      fallbackText: this.getFallbackText(),
      textColor: this.normalizeCssColor(this.element.color, '#111827'),
      backgroundColor: this.normalizeCssColor(this.element.backgroundColor, 'transparent'),
      fontSize: Math.max(8, this.element.fontSize)
    };

    const script =
      `window.renderFormulaFromHost && window.renderFormulaFromHost(${JSON.stringify(JSON.stringify(payload))});`;
    try {
      await this.controller.runJavaScript(script);
      this.injectedPayloadKey = payloadKey;
    } catch (_error) {
      this.hasRenderFailure = true;
    }
  }

  private escapeForHtml(value: string): string {
    return value
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#39;');
  }

  private normalizeCssColor(value: string, fallback: string): string {
    const normalized = value.trim().toUpperCase();
    if (normalized.length === 0 || normalized === 'TRANSPARENT') {
      return fallback;
    }

    if (/^#[0-9A-F]{8}$/.test(normalized)) {
      const alpha = Number.parseInt(normalized.substring(1, 3), 16) / 255;
      const red = Number.parseInt(normalized.substring(3, 5), 16);
      const green = Number.parseInt(normalized.substring(5, 7), 16);
      const blue = Number.parseInt(normalized.substring(7, 9), 16);
      return `rgba(${red}, ${green}, ${blue}, ${alpha})`;
    }

    return value.length === 0 ? fallback : value;
  }
}
