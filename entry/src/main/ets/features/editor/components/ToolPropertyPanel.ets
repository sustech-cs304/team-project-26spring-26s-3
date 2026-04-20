import common from '@ohos.app.ability.common';

import { ToolSetting, ToolType } from '../../../domain/entities/ToolSetting';
import { DrawingEditorViewModel } from '../viewmodels/DrawingEditorViewModel';
import { EditorSessionRegistry } from '../viewmodels/EditorSessionRegistry';

const COLOR_OPTIONS: string[] = ['#111827', '#2563EB', '#16A34A', '#DC2626', '#F59E0B'];
const TOOL_OPTIONS: ToolType[] = ['pen', 'pencil', 'highlighter', 'eraser'];
const WIDTH_OPTIONS: number[] = [2, 4, 8, 12, 20];

@Component
export struct ToolPropertyPanel {
  @Watch('onPageIdChanged')
  @Prop pageId: string = '';
  @Link toolSetting: ToolSetting;
  private viewModel: DrawingEditorViewModel | null = null;

  aboutToAppear(): void {
    this.resolveViewModel();
  }

  build() {
    Column({ space: 6 }) {
      this.buildSummaryCard()
      this.buildToolSelector()
      this.buildBrushSettings()
    }
    .width('100%')
    .padding(6)
    .backgroundColor('#FFFFFF')
    .borderRadius(14)
    .border({
      width: 1,
      color: '#E2E8F0'
    })
  }

  @Builder
  private buildSummaryCard(): void {
    Row() {
      Text(`${this.getToolLabel(this.getToolSetting().tool)}  ${this.getToolSetting().width}px`)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor('#111827')
        .layoutWeight(1)

      Text(`Opacity ${Math.round(this.getToolSetting().opacity * 100)}%`)
        .fontSize(11)
        .fontColor('#475569')
    }
    .width('100%')
    .justifyContent(FlexAlign.SpaceBetween)
    .alignItems(VerticalAlign.Center)
    .padding({
      left: 10,
      right: 10,
      top: 7,
      bottom: 7
    })
    .backgroundColor('#F8FAFC')
    .borderRadius(12)
  }

  @Builder
  private buildToolSelector(): void {
    Column({ space: 6 }) {
      this.buildSectionHeader('Tools')

      Row({ space: 6 }) {
        ForEach(TOOL_OPTIONS, (tool: ToolType) => {
          Button() {
            this.buildToolGlyph(tool, this.isSelectedTool(tool))
          }
          .layoutWeight(1)
          .height(42)
          .backgroundColor(this.isSelectedTool(tool) ? '#0F172A' : '#FFFFFF')
          .borderRadius(12)
          .border({
            width: 1,
            color: this.isSelectedTool(tool) ? '#0F172A' : '#CBD5E1'
          })
          .onClick(() => {
            this.updateToolSetting({
              tool,
              color: this.getToolSetting().color,
              width: this.getToolSetting().width,
              opacity: this.getNextOpacityForTool(tool)
            });
          });
        }, (tool: ToolType) => tool)
      }
      .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(7)
    .backgroundColor('#F8FAFC')
    .borderRadius(12)
  }

  @Builder
  private buildBrushSettings(): void {
    Column({ space: 8 }) {
      this.buildSectionHeader('Stroke Settings')

      this.buildColorSelector()
      this.buildWidthSelector()
      this.buildOpacityEditor()
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(7)
    .backgroundColor('#F8FAFC')
    .borderRadius(12)
  }

  @Builder
  private buildSectionHeader(title: string): void {
    Row() {
      Text(title)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor('#111827')
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private buildColorSelector(): void {
    Column({ space: 6 }) {
      Text('Color')
        .fontSize(12)
        .fontColor('#475569')

      Row({ space: 5 }) {
        ForEach(COLOR_OPTIONS, (color: string) => {
          Stack() {}
            .width(20)
            .height(20)
            .backgroundColor(color)
            .borderRadius(10)
            .border({
              width: this.getToolSetting().color === color ? 3 : 1,
              color: this.getToolSetting().color === color ? '#111827' : '#CBD5E1'
            })
            .opacity(this.getToolSetting().tool === 'eraser' ? 0.4 : 1)
            .onClick(() => {
              if (this.getToolSetting().tool === 'eraser') {
                return;
              }

              this.updateToolSetting({
                tool: this.getToolSetting().tool,
                color,
                width: this.getToolSetting().width,
                opacity: this.getToolSetting().opacity
              });
            });
        }, (color: string) => color)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private buildWidthSelector(): void {
    Column({ space: 6 }) {
      Text('Width')
        .fontSize(12)
        .fontColor('#475569')

      Row({ space: 5 }) {
        ForEach(WIDTH_OPTIONS, (width: number) => {
          Button() {
            this.buildWidthGlyph(width, this.getToolSetting().width === width)
          }
          .layoutWeight(1)
          .height(28)
          .backgroundColor(this.getToolSetting().width === width ? '#0F172A' : '#FFFFFF')
          .borderRadius(10)
          .border({
            width: 1,
            color: this.getToolSetting().width === width ? '#0F172A' : '#CBD5E1'
          })
          .onClick(() => {
            this.updateToolSetting({
              tool: this.getToolSetting().tool,
              color: this.getToolSetting().color,
              width,
              opacity: this.getToolSetting().opacity
            });
          });
        }, (width: number) => `${width}`)
      }
      .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private buildOpacityEditor(): void {
    Column({ space: 6 }) {
      Text(`Opacity ${Math.round(this.getToolSetting().opacity * 100)}%`)
        .fontSize(12)
        .fontColor('#475569')

      Slider({
        value: this.getToolSetting().opacity * 100,
        min: 10,
        max: 100,
        step: 5,
        style: SliderStyle.OutSet
      })
        .enabled(this.getToolSetting().tool !== 'eraser')
        .opacity(this.getToolSetting().tool === 'eraser' ? 0.4 : 1)
        .showTips(false)
        .onChange((value: number) => {
          this.updateToolSetting({
            tool: this.getToolSetting().tool,
            color: this.getToolSetting().color,
            width: this.getToolSetting().width,
            opacity: value / 100
          });
        })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  private getToolSetting(): ToolSetting {
    return this.toolSetting;
  }

  private updateToolSetting(nextSetting: ToolSetting): void {
    const normalizedSetting: ToolSetting = {
      tool: nextSetting.tool,
      color: nextSetting.color,
      width: nextSetting.width,
      opacity: nextSetting.opacity
    };

    this.toolSetting = this.cloneToolSetting(normalizedSetting);

    const viewModel = this.getViewModel();
    if (!viewModel) {
      return;
    }

    viewModel.updateToolSetting(normalizedSetting);
  }

  private getToolLabel(tool: ToolType): string {
    switch (tool) {
      case 'pen':
        return 'Pen';
      case 'pencil':
        return 'Pencil';
      case 'highlighter':
        return 'Highlight';
      case 'eraser':
        return 'Eraser';
      default:
        return tool;
    }
  }

  @Builder
  private buildToolGlyph(tool: ToolType, isSelected: boolean): void {
    Stack({ alignContent: Alignment.Center }) {
      if (tool === 'pen') {
        this.buildPenGlyph(this.getToolAccent(tool, isSelected))
      } else if (tool === 'pencil') {
        this.buildPencilGlyph(this.getToolAccent(tool, isSelected))
      } else if (tool === 'highlighter') {
        this.buildHighlighterGlyph(this.getToolAccent(tool, isSelected), isSelected)
      } else {
        this.buildEraserGlyph(this.getToolAccent(tool, isSelected), isSelected)
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private buildPenGlyph(color: string): void {
    Stack({ alignContent: Alignment.Center }) {
      Column() {}
        .width(14)
        .height(4)
        .backgroundColor(color)
        .borderRadius(2)
        .offset({ x: -2, y: -1 })

      Column() {}
        .width(4)
        .height(9)
        .backgroundColor(color)
        .borderRadius(2)
        .offset({ x: 6, y: -1 })

      Column() {}
        .width(4)
        .height(4)
        .backgroundColor(color)
        .borderRadius(2)
        .offset({ x: 8, y: 5 })
    }
    .width(22)
    .height(22)
  }

  @Builder
  private buildPencilGlyph(color: string): void {
    Stack({ alignContent: Alignment.Center }) {
      Column() {}
        .width(15)
        .height(4)
        .backgroundColor(color)
        .borderRadius(2)
        .offset({ x: -1, y: 0 })

      Column() {}
        .width(4)
        .height(7)
        .backgroundColor('#F8FAFC')
        .borderRadius(2)
        .offset({ x: -8, y: 0 })

      Column() {}
        .width(4)
        .height(6)
        .backgroundColor('#D97706')
        .borderRadius(2)
        .offset({ x: 9, y: 0 })
    }
    .width(22)
    .height(22)
  }

  @Builder
  private buildHighlighterGlyph(color: string, isSelected: boolean): void {
    Stack({ alignContent: Alignment.Center }) {
      Column() {}
        .width(16)
        .height(8)
        .backgroundColor(color)
        .borderRadius(3)
        .offset({ y: -2 })

      Column() {}
        .width(13)
        .height(3)
        .backgroundColor(isSelected ? '#FEF3C7' : '#FCD34D')
        .borderRadius(2)
        .offset({ y: 6 })
    }
    .width(22)
    .height(22)
  }

  @Builder
  private buildEraserGlyph(color: string, isSelected: boolean): void {
    Stack({ alignContent: Alignment.Center }) {
      Column() {}
        .width(16)
        .height(9)
        .backgroundColor(color)
        .borderRadius(3)
        .offset({ y: -1 })

      Column() {}
        .width(7)
        .height(9)
        .backgroundColor(isSelected ? '#CBD5E1' : '#E2E8F0')
        .borderRadius(3)
        .offset({ x: -4, y: -1 })
    }
    .width(22)
    .height(22)
  }

  @Builder
  private buildWidthGlyph(width: number, isSelected: boolean): void {
    Column() {}
      .width(14)
      .height(Math.max(2, Math.min(12, width)))
      .backgroundColor(isSelected ? '#FFFFFF' : '#0F172A')
      .borderRadius(6)
  }

  private isSelectedTool(tool: ToolType): boolean {
    return this.getToolSetting().tool === tool;
  }

  private getToolAccent(tool: ToolType, isSelected: boolean): string {
    if (isSelected) {
      return '#FFFFFF';
    }

    switch (tool) {
      case 'pen':
        return '#111827';
      case 'pencil':
        return '#475569';
      case 'highlighter':
        return '#CA8A04';
      case 'eraser':
        return '#64748B';
      default:
        return '#111827';
    }
  }

  private getNextOpacityForTool(tool: ToolType): number {
    const toolSetting = this.getToolSetting();

    if (tool === 'eraser') {
      return toolSetting.opacity;
    }

    if (tool === 'highlighter' && toolSetting.opacity > 0.35) {
      return 0.35;
    }

    if (toolSetting.tool === 'highlighter' && toolSetting.opacity === 0.35) {
      return 1;
    }

    return toolSetting.opacity;
  }

  private cloneToolSetting(toolSetting: ToolSetting): ToolSetting {
    return {
      tool: toolSetting.tool,
      color: toolSetting.color,
      width: toolSetting.width,
      opacity: toolSetting.opacity
    };
  }

  private onPageIdChanged(): void {
    this.resolveViewModel();
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
      return;
    }

    this.viewModel = EditorSessionRegistry.getOrCreate(
      this.pageId,
      this.getUIContext().getHostContext() as common.Context
    );
  }
}
