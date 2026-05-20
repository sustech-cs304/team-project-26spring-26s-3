import common from '@ohos.app.ability.common';
import router from '@ohos.router';

import { AppRouter, RouterParams } from '../../../app/AppRouter';
import { StrokeStyle } from '../../../domain/entities/Stroke';
import { ToolSetting } from '../../../domain/entities/ToolSetting';
import { CanvasBoard } from '../components/CanvasBoard';
import { ToolPropertyPanel } from '../components/ToolPropertyPanel';
import { DrawingEditorViewModel } from '../viewmodels/DrawingEditorViewModel';
import { EditorDebugSnapshot } from '../viewmodels/EditorDebugSnapshot';
import { EditorSessionRegistry } from '../viewmodels/EditorSessionRegistry';

const DEFAULT_NOTEBOOK_ID = 'demo-notebook';
const DEFAULT_PAGE_ID = `${DEFAULT_NOTEBOOK_ID}:page-1`;

@Entry
@Component
struct DrawingEditorPage {
  private viewModel: DrawingEditorViewModel | null = null;

  @State private notebookId: string = DEFAULT_NOTEBOOK_ID;
  @State private pageId: string = DEFAULT_PAGE_ID;
  @State private notebookTitle: string = 'Notebook';
  @State private pageLabel: string = 'Page';
  @State private isInitializing: boolean = true;
  @State private toolSetting: ToolSetting = {
    tool: 'pen',
    color: '#111827',
    width: 4,
    opacity: 1
  };
  @State private editorSnapshot: EditorDebugSnapshot = {
    instanceId: 0,
    pageId: DEFAULT_PAGE_ID,
    toolSetting: {
      tool: 'pen',
      color: '#111827',
      width: 4,
      opacity: 1
    },
    strokeCount: 0,
    activeStrokeStyle: null,
    undoDepth: 0,
    redoDepth: 0,
    recentEvents: [],
    errorMessage: '',
    persistenceStatus: 'idle'
  };
  @State private canvasVersion: number = 0;

  aboutToAppear(): void {
    void this.initializeEditor();
  }

  aboutToDisappear(): void {
    if (this.pageId.length > 0) {
      EditorSessionRegistry.clear(this.pageId);
    }
  }

  build() {
    Column({ space: 12 }) {
      this.buildHeader()
      this.buildToolbar()
      this.buildDebugPanel()

      if (this.isInitializing || this.viewModel === null) {
        this.buildLoadingState()
      } else {
        this.buildEditorWorkspace()
      }
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({
      left: $r('app.float.page_padding_horizontal'),
      right: $r('app.float.page_padding_horizontal'),
      top: $r('app.float.page_padding_vertical'),
      bottom: $r('app.float.page_padding_vertical')
    })
    .backgroundColor($r('app.color.app_background'))
  }

  @Builder
  private buildHeader(): void {
    Column({ space: 4 }) {
      Text(this.notebookTitle)
        .fontSize($r('app.float.hero_title_size'))
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.primary_text'))

      Text(`${this.pageLabel}  |  ${this.pageId}`)
        .fontSize($r('app.float.caption_text_size'))
        .fontColor($r('app.color.secondary_text'))
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private buildToolbar(): void {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Button('Undo')
          .layoutWeight(1)
          .height(36)
          .enabled(this.editorSnapshot.undoDepth > 0)
          .backgroundColor(this.editorSnapshot.undoDepth > 0 ? '#111827' : '#E5E7EB')
          .fontColor(this.editorSnapshot.undoDepth > 0 ? '#FFFFFF' : '#98A2B3')
          .onClick(() => {
            void this.handleUndo();
          })

        Button('Redo')
          .layoutWeight(1)
          .height(36)
          .enabled(this.editorSnapshot.redoDepth > 0)
          .backgroundColor(this.editorSnapshot.redoDepth > 0 ? '#111827' : '#E5E7EB')
          .fontColor(this.editorSnapshot.redoDepth > 0 ? '#FFFFFF' : '#98A2B3')
          .onClick(() => {
            void this.handleRedo();
          })

        Button('Clear')
          .layoutWeight(1)
          .height(36)
          .enabled(this.editorSnapshot.strokeCount > 0)
          .backgroundColor(this.editorSnapshot.strokeCount > 0 ? '#DC2626' : '#FECACA')
          .fontColor(this.editorSnapshot.strokeCount > 0 ? '#FFFFFF' : '#B91C1C')
          .onClick(() => {
            void this.handleClear();
          })

        Button('Back')
          .layoutWeight(1)
          .height(36)
          .backgroundColor('#FFFFFF')
          .fontColor('#111827')
          .onClick(() => {
            AppRouter.back();
          })
      }
      .width('100%')

      Row({ space: 8 }) {
        this.buildStatCard('Tool', this.getSelectedToolLabel())
        this.buildStatCard('Strokes', `${this.editorSnapshot.strokeCount}`)
        this.buildStatCard('Brush', `${this.toolSetting.width} px`)
        this.buildStatCard('Storage', this.editorSnapshot.persistenceStatus.length > 0 ? this.editorSnapshot.persistenceStatus : 'idle')
      }
      .width('100%')
    }
    .width('100%')
    .padding(12)
    .backgroundColor($r('app.color.surface_background'))
    .borderRadius($r('app.float.card_radius'))
    .border({ width: 1, color: $r('app.color.card_border') })
  }

  @Builder
  private buildStatCard(title: string, value: string): void {
    Column({ space: 4 }) {
      Text(title)
        .fontSize(11)
        .fontColor($r('app.color.secondary_text'))

      Text(value)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.primary_text'))
        .maxLines(1)
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 12, right: 12, top: 10, bottom: 10 })
    .backgroundColor('#F8FAFC')
    .borderRadius(12)
  }

  @Builder
  private buildDebugPanel(): void {
    Column({ space: 6 }) {
      Text('Debug Output')
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor('#111827')

      Scroll() {
        Text(this.getDebugSummary())
          .width('100%')
          .fontSize(10)
          .fontColor('#334155')
          .lineHeight(14)
          .textAlign(TextAlign.Start)
      }
      .width('100%')
      .height(96)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 12, right: 12, top: 10, bottom: 10 })
    .backgroundColor('#F8FAFC')
    .borderRadius(12)
    .border({ width: 1, color: '#CBD5E1' })
  }

  @Builder
  private buildLoadingState(): void {
    Column({ space: 12 }) {
      Text('Loading drawing workspace...')
        .fontSize($r('app.float.section_title_size'))
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.primary_text'))

      Text('Preparing stroke session for the selected notebook page.')
        .fontSize($r('app.float.caption_text_size'))
        .fontColor($r('app.color.secondary_text'))
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .padding(20)
    .backgroundColor($r('app.color.surface_background'))
    .borderRadius($r('app.float.card_radius'))
    .border({ width: 1, color: $r('app.color.card_border') })
  }

  @Builder
  private buildEditorWorkspace(): void {
    Row({ space: 12 }) {
      Column({ space: 10 }) {
        ToolPropertyPanel({
          pageId: this.pageId,
          toolSetting: $toolSetting
        })

        if (this.editorSnapshot.errorMessage.length > 0) {
          Text(this.editorSnapshot.errorMessage)
            .width('100%')
            .fontSize($r('app.float.caption_text_size'))
            .fontColor('#B42318')
            .padding(12)
            .backgroundColor('#FEF3F2')
            .borderRadius(12)
        }
      }
      .width(280)
      .alignItems(HorizontalAlign.Start)

      Column() {
        CanvasBoard({
          pageId: this.pageId,
          canvasVersion: this.canvasVersion,
          toolSetting: this.toolSetting,
          isActivePage: true,
          editorSnapshot: $editorSnapshot
        })
      }
      .layoutWeight(1)
      .height('100%')
      .padding(8)
      .backgroundColor($r('app.color.surface_background'))
      .borderRadius($r('app.float.card_radius'))
      .border({ width: 1, color: $r('app.color.card_border') })
    }
    .width('100%')
    .layoutWeight(1)
    .alignItems(VerticalAlign.Top)
  }

  private async initializeEditor(): Promise<void> {
    this.isInitializing = true;

    const params = this.resolveRouterParams();
    this.notebookId = params.notebookId ?? DEFAULT_NOTEBOOK_ID;
    this.pageId = params.pageId ?? DEFAULT_PAGE_ID;
    this.notebookTitle = params.notebookTitle ?? this.notebookId;
    this.pageLabel = params.pageLabel ?? 'Page';
    this.toolSetting = this.buildDefaultToolSetting();
    this.editorSnapshot = this.buildEmptySnapshot(this.pageId);
    this.canvasVersion += 1;

    EditorSessionRegistry.clear(this.pageId);
    this.viewModel = EditorSessionRegistry.getOrCreate(
      this.pageId,
      this.getUIContext().getHostContext() as common.Context
    );

    try {
      const loadPageTask = this.viewModel.loadPage(this.pageId);
      this.syncEditorSnapshot();
      await loadPageTask;
      this.syncEditorSnapshot(true);
    } finally {
      this.isInitializing = false;
    }
  }

  private async handleUndo(): Promise<void> {
    if (!this.viewModel || this.isInitializing) {
      return;
    }

    const undoTask = this.viewModel.undo();
    this.syncEditorSnapshot(true);
    await undoTask;
    this.syncEditorSnapshot(true);
  }

  private async handleRedo(): Promise<void> {
    if (!this.viewModel || this.isInitializing) {
      return;
    }

    const redoTask = this.viewModel.redo();
    this.syncEditorSnapshot(true);
    await redoTask;
    this.syncEditorSnapshot(true);
  }

  private async handleClear(): Promise<void> {
    if (!this.viewModel || this.isInitializing) {
      return;
    }

    const clearTask = this.viewModel.clear();
    this.syncEditorSnapshot(true);
    await clearTask;
    this.syncEditorSnapshot(true);
  }

  private getSelectedToolLabel(): string {
    switch (this.toolSetting.tool) {
      case 'pen':
        return 'Pen';
      case 'pencil':
        return 'Pencil';
      case 'highlighter':
        return 'Highlighter';
      case 'eraser':
        return 'Eraser';
      default:
        return 'Pen';
    }
  }

  private getDebugSummary(): string {
    const snapshot = this.editorSnapshot;
    const latestEvent = snapshot.recentEvents.length > 0 ? snapshot.recentEvents[snapshot.recentEvents.length - 1] : 'none';
    const activeStroke = snapshot.activeStrokeStyle ? this.formatToolSetting(snapshot.activeStrokeStyle) : 'none';
    const events = snapshot.recentEvents.length > 0 ? snapshot.recentEvents.slice(-6).join('\n') : 'no events';

    return [
      `Tool: ${this.formatToolSetting(this.toolSetting)}`,
      `Last Event: ${latestEvent}`,
      `Strokes: ${snapshot.strokeCount}`,
      `Active: ${activeStroke}`,
      `Storage: ${snapshot.persistenceStatus}`,
      `History: undo=${snapshot.undoDepth} redo=${snapshot.redoDepth}`,
      `Error: ${snapshot.errorMessage.length > 0 ? snapshot.errorMessage : 'none'}`,
      'Events:',
      events
    ].join('\n');
  }

  private formatToolSetting(setting: ToolSetting | StrokeStyle): string {
    return `${setting.tool} ${setting.color} w=${setting.width} a=${setting.opacity.toFixed(2)}`;
  }

  private syncEditorSnapshot(redrawCanvas: boolean = false): void {
    if (!this.viewModel) {
      this.editorSnapshot = this.buildEmptySnapshot(this.pageId);
      if (redrawCanvas) {
        this.canvasVersion += 1;
      }
      return;
    }

    this.editorSnapshot = this.viewModel.getDebugSnapshot();
    this.toolSetting = this.viewModel.getToolSetting();
    if (redrawCanvas) {
      this.canvasVersion += 1;
    }
  }

  private buildDefaultToolSetting(): ToolSetting {
    return {
      tool: 'pen',
      color: '#111827',
      width: 4,
      opacity: 1
    };
  }

  private buildEmptySnapshot(pageId: string): EditorDebugSnapshot {
    return {
      instanceId: 0,
      pageId,
      toolSetting: this.buildDefaultToolSetting(),
      strokeCount: 0,
      elementCount: 0,
      selectedElementId: '',
      activeStrokeStyle: null,
      undoDepth: 0,
      redoDepth: 0,
      recentEvents: [],
      errorMessage: '',
      persistenceStatus: 'idle'
    };
  }

  private resolveRouterParams(): RouterParams {
    try {
      return router.getParams() as RouterParams;
    } catch (_error) {
      return {};
    }
  }
}
