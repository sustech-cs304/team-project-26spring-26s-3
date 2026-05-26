import { TextCanvasElement } from '../../../domain/entities/CanvasElement';
import { TextElementOutlineView } from './TextElementOutlineView';

const TEXT_LINE_HEIGHT_FACTOR = 1.35;

const DEFAULT_TEXT_ELEMENT: TextCanvasElement = {
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

@Component
export struct TextElementView {
  @Prop element: TextCanvasElement = DEFAULT_TEXT_ELEMENT;

  build() {
    Stack() {
      TextArea({
        text: this.getDisplayText()
      })
        .width(this.element.width)
        .height(this.element.height)
        .position({
          x: 0,
          y: 0
        })
        .padding({
          left: 8,
          right: 8,
          top: 6,
          bottom: 6
        })
        .fontSize(Math.max(8, this.element.fontSize))
        .lineHeight(this.getTextLineHeight())
        .fontFamily('monospace')
        .fontColor(this.element.color)
        .wordBreak(WordBreak.BREAK_ALL)
        .maxLines(1000)
        .barState(BarState.Off)
        .backgroundColor(this.element.backgroundColor)
        .zIndex(this.element.zIndex)
        .hitTestBehavior(HitTestMode.None)

      TextElementOutlineView({ element: this.element, useElementPosition: false })
    }
    .width(this.element.width)
    .height(this.element.height)
    .position({
      x: this.element.x,
      y: this.element.y
    })
    .zIndex(this.element.zIndex)
    .hitTestBehavior(HitTestMode.None)
  }

  private getDisplayText(): string {
    return this.element.content.length === 0 ? 'Text' : this.element.content;
  }

  private getTextLineHeight(): number {
    return Math.max(8, this.element.fontSize) * TEXT_LINE_HEIGHT_FACTOR;
  }
}
