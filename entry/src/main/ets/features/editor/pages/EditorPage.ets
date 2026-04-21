import common from '@ohos.app.ability.common';
import router from '@ohos.router';

import { AppRouter, RouterParams } from '../../../app/AppRouter';
import { Notebook } from '../../../domain/entities/Notebook';
import { NotebookPage } from '../../../domain/entities/NotebookPage';
import { NotebookPageCanvas } from '../../../domain/entities/NotebookPageCanvas';
import { ToolSetting } from '../../../domain/entities/ToolSetting';
import { CanvasBoard } from '../components/CanvasBoard';
import { PageThumbnailPreview } from '../components/PageThumbnailPreview';
import { ToolPropertyPanel } from '../components/ToolPropertyPanel';
import { DrawingEditorViewModel } from '../viewmodels/DrawingEditorViewModel';
import { EditorDebugSnapshot } from '../viewmodels/EditorDebugSnapshot';
import { EditorSessionRegistry } from '../viewmodels/EditorSessionRegistry';
import { EditorViewModel } from '../viewmodels/EditorViewModel';

interface PageCanvasRenderSize {
  width: number;
  height: number;
}

const THUMBNAIL_REFRESH_INTERVAL_MS = 320;

@Entry
@Component
struct EditorPage {
  @State private notebookId: string = '';
  @State private notebookTitle: string = '';
  @State private notebookPageList: NotebookPage[] = [];
  @State private activePageId: string = '';
  @State private activePageCanvas: NotebookPageCanvas | null = null;
  @State private isLoading: boolean = true;
  @State private isCanvasLoading: boolean = false;
  @State private isCreatingPage: boolean = false;
  @State private isReorderingPages: boolean = false;
  @State private pageActionMenuPageId: string = '';
  @State private isDeletePageDialogVisible: boolean = false;
  @State private isDeletingPage: boolean = false;
  @State private deleteTargetPageId: string = '';
  @State private deleteTargetPageLabel: string = '';
  @State private deleteTargetPageOrder: number = -1;
  @State private hasMissingNotebookId: boolean = false;
  @State private isNotebookMissing: boolean = false;
  @State private toolSetting: ToolSetting = this.buildDefaultToolSetting();
  @State private editorSnapshot: EditorDebugSnapshot = this.buildEmptySnapshot('');
  @State private canvasVersion: number = 0;
  @State private thumbnailRefreshVersion: number = 0;
  private readonly pageCanvasRenderSizeMap: Map<string, PageCanvasRenderSize> = new Map<string, PageCanvasRenderSize>();
  private thumbnailRefreshTimerId: number = -1;
  private lastThumbnailRefreshTime: number = 0;
  private editorViewModel?: EditorViewModel;
  private drawingViewModel: DrawingEditorViewModel | null = null;
  private currentDrawingPageId: string = '';

  aboutToAppear(): void {
    void this.loadEditorState();
  }

  aboutToDisappear(): void {
    this.clearScheduledThumbnailRefresh();
    void this.flushActiveDrawingSession();
    EditorSessionRegistry.clearAll();
    this.drawingViewModel = null;
    this.currentDrawingPageId = '';
  }

  build() {
    Stack() {
      if (this.isLoading) {
        this.buildLoadingState();
      } else if (this.hasMissingNotebookId || this.isNotebookMissing) {
        this.buildMissingState();
      } else {
        this.buildEditorShell();
      }

      if (this.isDeletePageDialogVisible) {
        this.buildDeleteDialog();
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.app_background'))
  }

  @Builder
  private buildLoadingState(): void {
    Column({ space: 12 }) {
      LoadingProgress()
        .width(42)
        .height(42)

      Text($r('app.string.editor_loading'))
        .fontSize($r('app.float.section_title_size'))
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.primary_text'))

      Text($r('app.string.editor_loading_desc'))
        .fontSize($r('app.float.caption_text_size'))
        .fontColor($r('app.color.secondary_text'))
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .padding({
      left: $r('app.float.page_padding_horizontal'),
      right: $r('app.float.page_padding_horizontal'),
      top: $r('app.float.page_padding_vertical'),
      bottom: $r('app.float.page_padding_vertical')
    })
  }

  @Builder
  private buildMissingState(): void {
    Column() {
      Column({ space: 12 }) {
        Text(this.hasMissingNotebookId ? $r('app.string.editor_missing_notebook_title') :
          $r('app.string.editor_not_found_title'))
          .fontSize($r('app.float.section_title_size'))
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.primary_text'))

        Text(this.hasMissingNotebookId ? $r('app.string.editor_missing_notebook_desc') :
          $r('app.string.editor_not_found_desc'))
          .fontSize($r('app.float.body_text_size'))
          .fontColor($r('app.color.secondary_text'))

        Row({ space: 12 }) {
          Button($r('app.string.editor_nav_notebooks'))
            .height($r('app.float.button_height'))
            .backgroundColor($r('app.color.primary_text'))
            .fontColor($r('app.color.inverse_text'))
            .onClick(() => {
              AppRouter.openNotebookList();
            })

          Button($r('app.string.editor_nav_home'))
            .height($r('app.float.button_height'))
            .backgroundColor($r('app.color.surface_background'))
            .fontColor($r('app.color.primary_text'))
            .onClick(() => {
              AppRouter.goHome();
            })
        }
      }
      .width('100%')
      .constraintSize({ maxWidth: 560 })
      .alignItems(HorizontalAlign.Start)
      .padding(28)
      .backgroundColor($r('app.color.editor_toolbar_background'))
      .borderRadius(32)
      .border({
        width: 1,
        color: $r('app.color.editor_toolbar_border')
      })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .padding({
      left: $r('app.float.page_padding_horizontal'),
      right: $r('app.float.page_padding_horizontal'),
      top: $r('app.float.page_padding_vertical'),
      bottom: $r('app.float.page_padding_vertical')
    })
  }

  @Builder
  private buildEditorShell(): void {
    Column({ space: 16 }) {
      this.buildTopBar()

      Row({ space: 16 }) {
        this.buildSidebar()
        this.buildWorkspace()
      }
      .layoutWeight(1)
      .width('100%')
      .alignItems(VerticalAlign.Top)
    }
    .width('100%')
    .height('100%')
    .padding({
      left: $r('app.float.page_padding_horizontal'),
      right: $r('app.float.page_padding_horizontal'),
      top: $r('app.float.page_padding_vertical'),
      bottom: $r('app.float.page_padding_vertical')
    })
  }

  @Builder
  private buildTopBar(): void {
    Row({ space: 16 }) {
      Button($r('app.string.editor_nav_notebooks'))
        .height($r('app.float.button_height'))
        .backgroundColor($r('app.color.surface_background'))
        .fontColor($r('app.color.primary_text'))
        .onClick(() => {
          AppRouter.openNotebookList();
        })

      Column({ space: 4 }) {
        Text(this.notebookTitle)
          .fontSize($r('app.float.hero_title_size'))
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.primary_text'))

        Text(this.getNotebookSummaryText())
          .fontSize($r('app.float.caption_text_size'))
          .fontColor($r('app.color.secondary_text'))
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Button($r('app.string.editor_nav_home'))
        .height($r('app.float.button_height'))
        .backgroundColor($r('app.color.surface_background'))
        .fontColor($r('app.color.primary_text'))
        .onClick(() => {
          AppRouter.goHome();
        })
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({
      left: 20,
      right: 20,
      top: 16,
      bottom: 16
    })
    .backgroundColor($r('app.color.editor_toolbar_background'))
    .borderRadius(28)
    .border({
      width: 1,
      color: $r('app.color.editor_toolbar_border')
    })
  }

  @Builder
  private buildSidebar(): void {
    Column({ space: 14 }) {
      Row({ space: 10 }) {
        Text($r('app.string.editor_sidebar_title'))
          .fontSize($r('app.float.section_title_size'))
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.primary_text'))
          .layoutWeight(1)

        Text(this.getPageCountText())
          .fontSize($r('app.float.caption_text_size'))
          .fontColor($r('app.color.editor_accent'))
          .padding({
            left: 12,
            right: 12,
            top: 6,
            bottom: 6
          })
          .backgroundColor($r('app.color.editor_accent_soft'))
          .borderRadius(999)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (this.notebookPageList.length === 0) {
        Column({ space: 10 }) {
          Text($r('app.string.editor_page_empty_title'))
            .fontSize($r('app.float.body_text_size'))
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.primary_text'))

          Text($r('app.string.editor_page_empty_desc'))
            .fontSize($r('app.float.caption_text_size'))
            .fontColor($r('app.color.secondary_text'))
        }
        .layoutWeight(1)
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding(18)
        .backgroundColor($r('app.color.editor_thumbnail_background'))
        .borderRadius(22)
        .border({
          width: 1,
          color: $r('app.color.editor_sidebar_border')
        })
      } else {
        Scroll() {
          Column({ space: 12 }) {
            ForEach(this.notebookPageList, (page: NotebookPage) => {
              this.buildPageThumbnail(page);
            }, (page: NotebookPage): string => this.getPageRenderKey(page))
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }
        .layoutWeight(1)
        .width('100%')
      }

      Button(this.isCreatingPage ? $r('app.string.editor_page_adding') : $r('app.string.editor_page_add'))
        .width('100%')
        .height($r('app.float.button_height'))
        .backgroundColor($r('app.color.editor_accent'))
        .fontColor($r('app.color.inverse_text'))
        .enabled(!this.isCreatingPage && !this.isDeletingPage && !this.isReorderingPages)
        .onClick(() => {
          void this.createNotebookPage();
        })
    }
    .width(232)
    .height('100%')
    .padding(16)
    .backgroundColor($r('app.color.editor_sidebar_background'))
    .borderRadius(28)
    .border({
      width: 1,
      color: $r('app.color.editor_sidebar_border')
    })
  }

  @Builder
  private buildPageThumbnail(page: NotebookPage): void {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        Text(this.getPageLabel(page.order))
          .fontSize($r('app.float.body_text_size'))
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.primary_text'))

        if (page.id === this.activePageId) {
          Text($r('app.string.editor_page_current_badge'))
            .fontSize($r('app.float.caption_text_size'))
            .fontColor($r('app.color.editor_accent'))
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      PageThumbnailPreview({
        pageId: page.id,
        isActive: page.id === this.activePageId,
        refreshVersion: this.thumbnailRefreshVersion,
        paperBackgroundColor: page.id === this.activePageId ? this.getActiveCanvasBackgroundColor() : '#FFFFFF',
        canvasWidth: this.getThumbnailCanvasWidth(page.id),
        canvasHeight: this.getThumbnailCanvasHeight(page.id)
      })
      .width('100%')
      .height(132)
      .backgroundColor($r('app.color.surface_background'))
      .borderRadius(18)
      .border({
        width: 1,
        color: page.id === this.activePageId ? $r('app.color.editor_accent') :
          $r('app.color.editor_paper_border')
      })
      .onClick(() => {
        void this.selectNotebookPage(page);
      })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(12)
    .backgroundColor(page.id === this.activePageId ? $r('app.color.editor_thumbnail_active') :
      $r('app.color.editor_thumbnail_background'))
    .borderRadius(22)
    .border({
      width: page.id === this.activePageId ? 2 : 1,
      color: page.id === this.activePageId ? $r('app.color.editor_accent') :
        $r('app.color.editor_sidebar_border')
    })
  }

  @Builder
  private buildWorkspace(): void {
    Stack({ alignContent: Alignment.TopEnd }) {
      Column({ space: 16 }) {
        Row({ space: 12 }) {
          Column({ space: 4 }) {
            if (this.activePageId.length > 0) {
              Text(this.getActivePageLabel())
                .fontSize($r('app.float.section_title_size'))
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.primary_text'))
            } else {
              Text($r('app.string.editor_canvas_empty_title'))
                .fontSize($r('app.float.section_title_size'))
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.primary_text'))
            }

            Text($r('app.string.editor_workspace_desc'))
              .fontSize($r('app.float.caption_text_size'))
              .fontColor($r('app.color.secondary_text'))
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)

          if (this.notebookPageList.length > 0) {
            Row({ space: 8 }) {
              Button('...')
                .width(40)
                .height(40)
                .backgroundColor($r('app.color.surface_background'))
                .fontColor($r('app.color.secondary_text'))
                .enabled(!this.isCreatingPage && !this.isDeletingPage && !this.isReorderingPages)
                .borderRadius(12)
                .onClick(() => {
                  this.togglePageActionMenu(this.activePageId);
                })

              Text(this.getActivePageIndexText())
                .fontSize($r('app.float.caption_text_size'))
                .fontColor($r('app.color.editor_accent'))
                .padding({
                  left: 12,
                  right: 12,
                  top: 6,
                  bottom: 6
                })
                .backgroundColor($r('app.color.editor_accent_soft'))
                .borderRadius(999)
            }
            .alignItems(VerticalAlign.Center)
          }
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        this.buildWorkspaceSurface()
      }
      .width('100%')
      .height('100%')

      if (this.activePageId.length > 0 && this.isPageActionMenuVisible(this.activePageId)) {
        this.buildPageActionMenu()
      }
    }
    .layoutWeight(1)
    .height('100%')
    .padding(18)
    .backgroundColor($r('app.color.editor_toolbar_background'))
    .borderRadius(28)
    .border({
      width: 1,
      color: $r('app.color.editor_toolbar_border')
    })
  }

  @Builder
  private buildWorkspaceSurface(): void {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.editor_workspace_background'))
        .borderRadius(32)

      if (this.notebookPageList.length === 0) {
        this.buildWorkspaceEmptyState()
      } else if (this.isCanvasLoading) {
        this.buildWorkspaceLoadingState()
      } else if (this.activePageCanvas === null) {
        this.buildWorkspaceEmptyState()
      } else {
        Row({ space: 18 }) {
          this.buildDrawingSidebar()
          this.buildPaperSurface()
        }
        .width('100%')
        .height('100%')
        .padding(24)
        .alignItems(VerticalAlign.Top)
      }
    }
    .layoutWeight(1)
    .width('100%')
  }

  @Builder
  private buildWorkspaceEmptyState(): void {
    Column({ space: 12 }) {
      Text($r('app.string.editor_canvas_empty_title'))
        .fontSize($r('app.float.section_title_size'))
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.primary_text'))

      Text($r('app.string.editor_canvas_empty_desc'))
        .fontSize($r('app.float.body_text_size'))
        .fontColor($r('app.color.secondary_text'))
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .padding(24)
  }

  @Builder
  private buildWorkspaceLoadingState(): void {
    Column({ space: 12 }) {
      LoadingProgress()
        .width(42)
        .height(42)

      Text($r('app.string.editor_canvas_loading'))
        .fontSize($r('app.float.body_text_size'))
        .fontColor($r('app.color.secondary_text'))
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .padding(24)
  }

  @Builder
  private buildDrawingSidebar(): void {
    Column({ space: 12 }) {
      this.buildDrawingActionBar()

      ToolPropertyPanel({
        pageId: this.activePageId,
        toolSetting: $toolSetting
      })

      if (this.editorSnapshot.errorMessage.length > 0) {
        Text(this.editorSnapshot.errorMessage)
          .width('100%')
          .fontSize($r('app.float.caption_text_size'))
          .fontColor($r('app.color.danger_text'))
          .padding(12)
          .backgroundColor($r('app.color.danger_surface'))
          .borderRadius(14)
      }
    }
    .width(276)
    .height('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private buildDrawingActionBar(): void {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Button('Undo')
          .layoutWeight(1)
          .height(36)
          .enabled(this.editorSnapshot.undoDepth > 0 && !this.isCanvasLoading)
          .backgroundColor(this.editorSnapshot.undoDepth > 0 && !this.isCanvasLoading ?
            $r('app.color.primary_text') : $r('app.color.app_background'))
          .fontColor(this.editorSnapshot.undoDepth > 0 && !this.isCanvasLoading ?
            $r('app.color.inverse_text') : $r('app.color.secondary_text'))
          .onClick(() => {
            void this.handleUndo();
          })

        Button('Redo')
          .layoutWeight(1)
          .height(36)
          .enabled(this.editorSnapshot.redoDepth > 0 && !this.isCanvasLoading)
          .backgroundColor(this.editorSnapshot.redoDepth > 0 && !this.isCanvasLoading ?
            $r('app.color.primary_text') : $r('app.color.app_background'))
          .fontColor(this.editorSnapshot.redoDepth > 0 && !this.isCanvasLoading ?
            $r('app.color.inverse_text') : $r('app.color.secondary_text'))
          .onClick(() => {
            void this.handleRedo();
          })

        Button('Clear')
          .layoutWeight(1)
          .height(36)
          .enabled(this.editorSnapshot.strokeCount > 0 && !this.isCanvasLoading)
          .backgroundColor(this.editorSnapshot.strokeCount > 0 && !this.isCanvasLoading ?
            $r('app.color.danger_text') : $r('app.color.danger_surface'))
          .fontColor(this.editorSnapshot.strokeCount > 0 && !this.isCanvasLoading ?
            $r('app.color.inverse_text') : $r('app.color.danger_text'))
          .onClick(() => {
            void this.handleClear();
          })
      }
      .width('100%')
    }
    .width('100%')
    .padding(12)
    .backgroundColor($r('app.color.surface_background'))
    .borderRadius(18)
    .border({
      width: 1,
      color: $r('app.color.editor_sidebar_border')
    })
  }

  @Builder
  private buildPaperSurface(): void {
    Column({ space: 14 }) {
      Row({ space: 12 }) {
        Text(this.getActivePageLabel())
          .fontSize($r('app.float.section_title_size'))
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.primary_text'))

        Text($r('app.string.editor_canvas_ready_badge'))
          .fontSize($r('app.float.caption_text_size'))
          .fontColor($r('app.color.editor_accent'))
          .padding({
            left: 10,
            right: 10,
            top: 6,
            bottom: 6
          })
          .backgroundColor($r('app.color.editor_accent_soft'))
          .borderRadius(999)

        Text(this.getCanvasText())
          .fontSize($r('app.float.caption_text_size'))
          .fontColor($r('app.color.secondary_text'))
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Stack() {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(this.getActiveCanvasBackgroundColor())
          .borderRadius(30)

        CanvasBoard({
          pageId: this.activePageId,
          canvasVersion: this.canvasVersion,
          editorSnapshot: $editorSnapshot,
          onContentChanged: (immediate: boolean): void => {
            this.requestThumbnailRefresh(immediate);
          },
          onCanvasMetricsChanged: (width: number, height: number): void => {
            this.updatePageCanvasRenderSize(this.activePageId, width, height);
          }
        })
          .width('100%')
          .height('100%')
      }
      .width('100%')
      .layoutWeight(1)
      .borderRadius(30)
      .border({
        width: 1,
        color: $r('app.color.editor_paper_border')
      })
    }
    .layoutWeight(1)
    .height('100%')
    .constraintSize({ maxWidth: 860 })
  }

  @Builder
  private buildPageActionMenu(): void {
    Column({ space: 6 }) {
      Button($r('app.string.editor_page_move_up'))
        .width(132)
        .height(36)
        .backgroundColor($r('app.color.app_background'))
        .fontColor($r('app.color.primary_text'))
        .enabled(this.canMoveActivePageUp() && !this.isReorderingPages)
        .onClick(() => {
          const activePage: NotebookPage | null = this.getActivePage();
          if (activePage !== null) {
            this.moveNotebookPageByOffset(activePage, -1);
          }
        })

      Button($r('app.string.editor_page_move_down'))
        .width(132)
        .height(36)
        .backgroundColor($r('app.color.app_background'))
        .fontColor($r('app.color.primary_text'))
        .enabled(this.canMoveActivePageDown() && !this.isReorderingPages)
        .onClick(() => {
          const activePage: NotebookPage | null = this.getActivePage();
          if (activePage !== null) {
            this.moveNotebookPageByOffset(activePage, 1);
          }
        })

      Button($r('app.string.editor_page_delete_menu'))
        .width(132)
        .height(36)
        .backgroundColor($r('app.color.danger_surface'))
        .fontColor($r('app.color.danger_text'))
        .enabled(!this.isDeletingPage)
        .onClick(() => {
          const activePage: NotebookPage | null = this.getActivePage();
          if (activePage !== null) {
            this.openDeletePageDialog(activePage);
          }
        })
    }
    .padding(12)
    .margin({
      top: 48,
      right: 12
    })
    .backgroundColor($r('app.color.surface_background'))
    .borderRadius(16)
    .border({
      width: 1,
      color: $r('app.color.editor_sidebar_border')
    })
  }

  @Builder
  private buildDeleteDialog(): void {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.overlay_mask'))

      Column({ space: 14 }) {
        Text($r('app.string.editor_page_delete_confirm_title'))
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.primary_text'))

        Text(this.deleteTargetPageLabel.length > 0 ? `Delete ${this.deleteTargetPageLabel}` : 'Delete this page')
          .fontSize(14)
          .fontColor($r('app.color.secondary_text'))
          .textAlign(TextAlign.Center)

        Row({ space: 10 }) {
          Button('Cancel')
            .layoutWeight(1)
            .height(38)
            .enabled(!this.isDeletingPage)
            .backgroundColor($r('app.color.surface_background'))
            .fontColor($r('app.color.primary_text'))
            .border({ width: 1, color: $r('app.color.editor_sidebar_border') })
            .onClick(() => {
              this.closeDeletePageDialog();
            })

          Button(this.isDeletingPage ? $r('app.string.editor_page_deleting') :
            $r('app.string.editor_page_delete_button'))
            .layoutWeight(1)
            .height(38)
            .enabled(!this.isDeletingPage)
            .backgroundColor($r('app.color.danger_text'))
            .fontColor($r('app.color.inverse_text'))
            .onClick(() => {
              void this.confirmDeleteSelectedPage();
            })
        }
        .width('100%')
      }
      .width('80%')
      .constraintSize({ maxWidth: 420 })
      .padding(20)
      .backgroundColor($r('app.color.surface_background'))
      .borderRadius(20)
    }
    .width('100%')
    .height('100%')
  }

  private ensureViewModel(): EditorViewModel {
    if (this.editorViewModel === undefined) {
      const hostContext: common.Context | undefined = this.getUIContext().getHostContext() as common.Context | undefined;
      if (hostContext === undefined) {
        throw new Error('Host context is unavailable.');
      }
      this.editorViewModel = new EditorViewModel(hostContext);
    }

    return this.editorViewModel as EditorViewModel;
  }

  private async loadEditorState(): Promise<void> {
    this.isLoading = true;
    this.hasMissingNotebookId = false;
    this.isNotebookMissing = false;

    try {
      const routeParams: RouterParams = this.resolveRouteParams();
      const notebookId: string = typeof routeParams.notebookId === 'string' ? routeParams.notebookId : '';

      if (notebookId.length === 0) {
        this.resetState();
        this.hasMissingNotebookId = true;
        return;
      }

      this.notebookId = notebookId;
      const notebook: Notebook | null = await this.ensureViewModel().loadNotebook(notebookId);
      if (notebook === null) {
        this.resetState();
        this.isNotebookMissing = true;
        return;
      }

      this.notebookTitle = notebook.title;
      this.notebookPageList = await this.ensureViewModel().loadNotebookPages(notebookId);
      this.syncActivePageId(typeof routeParams.pageId === 'string' ? routeParams.pageId : '');
      await this.loadActivePageCanvas();
    } catch (_error) {
      this.resetState();
      this.isNotebookMissing = this.notebookId.length > 0;
    } finally {
      this.isLoading = false;
    }
  }

  private resetState(): void {
    this.notebookId = '';
    this.notebookTitle = '';
    this.notebookPageList = [];
    this.activePageId = '';
    this.activePageCanvas = null;
    this.isCanvasLoading = false;
    this.pageActionMenuPageId = '';
    this.resetDeletePageDialogState();
    this.resetDrawingState('');
  }

  private syncActivePageId(preferredPageId: string = ''): void {
    if (this.notebookPageList.length === 0) {
      this.activePageId = '';
      return;
    }

    if (preferredPageId.length > 0) {
      for (const page of this.notebookPageList) {
        if (page.id === preferredPageId) {
          this.activePageId = preferredPageId;
          return;
        }
      }
    }

    for (const page of this.notebookPageList) {
      if (page.id === this.activePageId) {
        return;
      }
    }

    this.activePageId = this.notebookPageList[this.notebookPageList.length - 1].id;
  }

  private async createNotebookPage(): Promise<void> {
    if (this.isCreatingPage || this.isReorderingPages || this.notebookId.length === 0) {
      return;
    }

    this.isCreatingPage = true;
    try {
      const notebookPage: NotebookPage | null = await this.ensureViewModel().createNotebookPage(this.notebookId);
      const cachedNotebook: Notebook | null = this.ensureViewModel().getCachedNotebook();
      const cachedNotebookPageList: NotebookPage[] = this.ensureViewModel().getCachedNotebookPages();

      if (cachedNotebook !== null) {
        this.notebookTitle = cachedNotebook.title;
      } else if (notebookPage === null) {
        this.isNotebookMissing = true;
      }

      this.notebookPageList = cachedNotebookPageList;
      this.syncActivePageId();
      this.closePageActionMenu();

      if (notebookPage !== null) {
        this.activePageId = notebookPage.id;
      }

      await this.loadActivePageCanvas();
    } catch (_error) {
    } finally {
      this.isCreatingPage = false;
    }
  }

  private async selectNotebookPage(page: NotebookPage): Promise<void> {
    if (this.isDeletingPage || this.isCreatingPage || this.isReorderingPages || this.isLoading) {
      return;
    }

    if (page.id === this.activePageId) {
      this.closePageActionMenu();
      return;
    }

    this.activePageId = page.id;
    this.closePageActionMenu();
    await this.loadActivePageCanvas();
  }

  private openDeletePageDialog(page: NotebookPage): void {
    if (this.isDeletingPage || this.isCreatingPage || this.isReorderingPages) {
      return;
    }

    this.deleteTargetPageId = page.id;
    this.deleteTargetPageLabel = this.getPageLabel(page.order);
    this.deleteTargetPageOrder = page.order;
    this.closePageActionMenu();
    this.isDeletePageDialogVisible = true;
  }

  private closeDeletePageDialog(): void {
    if (this.isDeletingPage) {
      return;
    }

    this.resetDeletePageDialogState();
  }

  private resetDeletePageDialogState(): void {
    this.isDeletePageDialogVisible = false;
    this.deleteTargetPageId = '';
    this.deleteTargetPageLabel = '';
    this.deleteTargetPageOrder = -1;
  }

  private async confirmDeleteSelectedPage(): Promise<void> {
    if (this.isDeletingPage || this.isReorderingPages || this.notebookId.length === 0 ||
      this.deleteTargetPageId.length === 0) {
      return;
    }

    const deletedPageId: string = this.deleteTargetPageId;
    const deletedPageOrder: number = this.deleteTargetPageOrder;
    const wasActivePage: boolean = deletedPageId === this.activePageId;
    let hasDeleted: boolean = false;

    this.isDeletingPage = true;
    try {
      hasDeleted = await this.ensureViewModel().deleteNotebookPage(this.notebookId, deletedPageId);
      const cachedNotebook: Notebook | null = this.ensureViewModel().getCachedNotebook();
      const cachedNotebookPageList: NotebookPage[] = this.ensureViewModel().getCachedNotebookPages();

      if (cachedNotebook !== null) {
        this.notebookTitle = cachedNotebook.title;
      } else if (hasDeleted) {
        this.isNotebookMissing = true;
      }

      this.notebookPageList = cachedNotebookPageList;
      this.closePageActionMenu();
      if (wasActivePage) {
        this.focusPageAfterDeletion(deletedPageOrder);
      } else {
        this.syncActivePageId();
      }

      await this.loadActivePageCanvas();
    } catch (_error) {
    } finally {
      this.isDeletingPage = false;
      if (hasDeleted) {
        this.resetDeletePageDialogState();
      }
    }
  }

  private focusPageAfterDeletion(deletedPageOrder: number): void {
    if (this.notebookPageList.length === 0) {
      this.activePageId = '';
      return;
    }

    let targetPageIndex: number = deletedPageOrder;
    if (targetPageIndex < 0) {
      targetPageIndex = 0;
    }
    if (targetPageIndex >= this.notebookPageList.length) {
      targetPageIndex = this.notebookPageList.length - 1;
    }

    this.activePageId = this.notebookPageList[targetPageIndex].id;
  }

  private async loadActivePageCanvas(): Promise<void> {
    if (this.notebookId.length === 0 || this.activePageId.length === 0) {
      this.activePageCanvas = null;
      this.isCanvasLoading = false;
      this.resetDrawingState('');
      return;
    }

    const targetPageId: string = this.activePageId;
    this.activePageCanvas = null;
    this.isCanvasLoading = true;
    try {
      const notebookPageCanvas: NotebookPageCanvas | null = await this.ensureViewModel().loadNotebookPageCanvas(
        this.notebookId,
        targetPageId
      );

      if (this.activePageId !== targetPageId) {
        return;
      }

      this.activePageCanvas = notebookPageCanvas;
      await this.loadDrawingSession(targetPageId);
    } catch (_error) {
      if (this.activePageId === targetPageId) {
        this.activePageCanvas = null;
        this.resetDrawingState(targetPageId);
      }
    } finally {
      if (this.activePageId === targetPageId) {
        this.isCanvasLoading = false;
      }
    }
  }

  private async loadDrawingSession(pageId: string): Promise<void> {
    const hostContext: common.Context | undefined = this.getUIContext().getHostContext() as common.Context | undefined;
    if (hostContext === undefined) {
      this.resetDrawingState(pageId);
      return;
    }

    if (this.currentDrawingPageId.length > 0 && this.currentDrawingPageId !== pageId) {
      await this.flushActiveDrawingSession();
      EditorSessionRegistry.clear(this.currentDrawingPageId);
    }
    EditorSessionRegistry.clear(pageId);

    this.currentDrawingPageId = pageId;
    this.drawingViewModel = EditorSessionRegistry.getOrCreate(pageId, hostContext);
    this.toolSetting = this.buildDefaultToolSetting();
    this.editorSnapshot = this.buildEmptySnapshot(pageId);
    this.canvasVersion += 1;

    const targetPageId: string = pageId;
    const viewModel: DrawingEditorViewModel = this.drawingViewModel;
    const loadPageTask = viewModel.loadPage(targetPageId);
    this.syncDrawingSnapshot(false, viewModel, targetPageId);
    await loadPageTask;
    if (this.activePageId === targetPageId && this.currentDrawingPageId === targetPageId) {
      this.syncDrawingSnapshot(true, viewModel, targetPageId);
    }
  }

  private resetDrawingState(pageId: string): void {
    if (this.currentDrawingPageId.length > 0) {
      void this.flushActiveDrawingSession();
      EditorSessionRegistry.clear(this.currentDrawingPageId);
    }
    this.drawingViewModel = null;
    this.currentDrawingPageId = pageId;
    this.toolSetting = this.buildDefaultToolSetting();
    this.editorSnapshot = this.buildEmptySnapshot(pageId);
    this.canvasVersion += 1;
  }

  private syncDrawingSnapshot(
    redrawCanvas: boolean = false,
    viewModel?: DrawingEditorViewModel | null,
    pageId?: string
  ): void {
    const targetViewModel: DrawingEditorViewModel | null = viewModel ?? this.drawingViewModel;
    const targetPageId: string = pageId ?? this.currentDrawingPageId;

    if (targetViewModel === null || targetPageId.length === 0) {
      this.toolSetting = this.buildDefaultToolSetting();
      this.editorSnapshot = this.buildEmptySnapshot(targetPageId);
      if (redrawCanvas) {
        this.canvasVersion += 1;
        this.requestThumbnailRefresh(true);
      }
      return;
    }

    if (this.currentDrawingPageId !== targetPageId) {
      return;
    }

    this.toolSetting = targetViewModel.getToolSetting();
    this.editorSnapshot = targetViewModel.getDebugSnapshot();
    if (redrawCanvas) {
      this.canvasVersion += 1;
      this.requestThumbnailRefresh(true);
    }
  }

  private requestThumbnailRefresh(immediate: boolean = false): void {
    if (immediate) {
      this.clearScheduledThumbnailRefresh();
      this.bumpThumbnailRefreshVersion();
      return;
    }

    if (this.thumbnailRefreshTimerId >= 0) {
      return;
    }

    const nowTime = Date.now();
    const elapsedTime = nowTime - this.lastThumbnailRefreshTime;
    const refreshDelay = elapsedTime >= THUMBNAIL_REFRESH_INTERVAL_MS
      ? 0
      : THUMBNAIL_REFRESH_INTERVAL_MS - elapsedTime;

    this.thumbnailRefreshTimerId = setTimeout(() => {
      this.thumbnailRefreshTimerId = -1;
      this.bumpThumbnailRefreshVersion();
    }, refreshDelay);
  }

  private bumpThumbnailRefreshVersion(): void {
    this.lastThumbnailRefreshTime = Date.now();
    this.thumbnailRefreshVersion += 1;
  }

  private clearScheduledThumbnailRefresh(): void {
    if (this.thumbnailRefreshTimerId < 0) {
      return;
    }

    clearTimeout(this.thumbnailRefreshTimerId);
    this.thumbnailRefreshTimerId = -1;
  }

  private updatePageCanvasRenderSize(pageId: string, width: number, height: number): void {
    if (pageId.length === 0 || width <= 0 || height <= 0) {
      return;
    }

    const cachedSize = this.pageCanvasRenderSizeMap.get(pageId);
    if (cachedSize !== undefined && cachedSize.width === width && cachedSize.height === height) {
      return;
    }

    this.pageCanvasRenderSizeMap.set(pageId, {
      width,
      height
    });
    this.requestThumbnailRefresh(true);
  }

  private async flushActiveDrawingSession(): Promise<void> {
    if (this.drawingViewModel === null) {
      return;
    }

    await this.drawingViewModel.flushPendingSave();
  }

  private getThumbnailCanvasWidth(pageId: string): number {
    const cachedSize = this.pageCanvasRenderSizeMap.get(pageId);
    return cachedSize === undefined ? 0 : cachedSize.width;
  }

  private getThumbnailCanvasHeight(pageId: string): number {
    const cachedSize = this.pageCanvasRenderSizeMap.get(pageId);
    return cachedSize === undefined ? 0 : cachedSize.height;
  }

  private async handleUndo(): Promise<void> {
    if (this.drawingViewModel === null || this.isCanvasLoading) {
      return;
    }

    const targetPageId: string = this.currentDrawingPageId;
    const undoTask = this.drawingViewModel.undo();
    this.syncDrawingSnapshot(true, this.drawingViewModel, targetPageId);
    await undoTask;
    this.syncDrawingSnapshot(true, this.drawingViewModel, targetPageId);
  }

  private async handleRedo(): Promise<void> {
    if (this.drawingViewModel === null || this.isCanvasLoading) {
      return;
    }

    const targetPageId: string = this.currentDrawingPageId;
    const redoTask = this.drawingViewModel.redo();
    this.syncDrawingSnapshot(true, this.drawingViewModel, targetPageId);
    await redoTask;
    this.syncDrawingSnapshot(true, this.drawingViewModel, targetPageId);
  }

  private async handleClear(): Promise<void> {
    if (this.drawingViewModel === null || this.isCanvasLoading) {
      return;
    }

    const targetPageId: string = this.currentDrawingPageId;
    const clearTask = this.drawingViewModel.clear();
    this.syncDrawingSnapshot(true, this.drawingViewModel, targetPageId);
    await clearTask;
    this.syncDrawingSnapshot(true, this.drawingViewModel, targetPageId);
  }

  private closePageActionMenu(): void {
    this.pageActionMenuPageId = '';
  }

  private togglePageActionMenu(pageId: string): void {
    if (this.isLoading || this.isCreatingPage || this.isDeletingPage || this.isReorderingPages) {
      return;
    }

    if (this.pageActionMenuPageId === pageId) {
      this.pageActionMenuPageId = '';
      return;
    }

    this.pageActionMenuPageId = pageId;
  }

  private isPageActionMenuVisible(pageId: string): boolean {
    return this.pageActionMenuPageId === pageId;
  }

  private canMovePageUp(page: NotebookPage): boolean {
    return page.order > 0;
  }

  private canMovePageDown(page: NotebookPage): boolean {
    return page.order < this.notebookPageList.length - 1;
  }

  private canMoveActivePageUp(): boolean {
    const activePage: NotebookPage | null = this.getActivePage();
    return activePage !== null && this.canMovePageUp(activePage);
  }

  private canMoveActivePageDown(): boolean {
    const activePage: NotebookPage | null = this.getActivePage();
    return activePage !== null && this.canMovePageDown(activePage);
  }

  private moveNotebookPageByOffset(page: NotebookPage, offset: number): void {
    if (this.isLoading || this.isCreatingPage || this.isDeletingPage || this.isReorderingPages) {
      return;
    }

    const targetIndex: number = page.order + offset;
    if (targetIndex < 0 || targetIndex >= this.notebookPageList.length) {
      return;
    }

    this.closePageActionMenu();
    void this.persistNotebookPageMove(page.order, targetIndex);
  }

  private async persistNotebookPageMove(fromIndex: number, toIndex: number): Promise<void> {
    if (fromIndex === toIndex || this.notebookId.length === 0) {
      return;
    }

    this.isReorderingPages = true;
    try {
      const hasReordered: boolean = await this.ensureViewModel().reorderNotebookPages(this.notebookId, fromIndex, toIndex);
      if (!hasReordered) {
        return;
      }

      const cachedNotebook: Notebook | null = this.ensureViewModel().getCachedNotebook();
      if (cachedNotebook !== null) {
        this.notebookTitle = cachedNotebook.title;
      }

      this.notebookPageList = this.ensureViewModel().getCachedNotebookPages();
      this.syncActivePageId(this.activePageId);
      await this.loadActivePageCanvas();
    } catch (_error) {
    } finally {
      this.isReorderingPages = false;
    }
  }

  private getActivePage(): NotebookPage | null {
    for (const notebookPage of this.notebookPageList) {
      if (notebookPage.id === this.activePageId) {
        return notebookPage;
      }
    }
    return null;
  }

  private getPageRenderKey(page: NotebookPage): string {
    return `${page.id}_${page.order.toString()}`;
  }

  private getPageLabel(pageOrder: number): string {
    return `Page ${pageOrder + 1}`;
  }

  private getPageCountText(): string {
    return `${this.notebookPageList.length} pages`;
  }

  private getNotebookSummaryText(): string {
    const activePage: NotebookPage | null = this.getActivePage();
    if (activePage === null) {
      return this.getPageCountText();
    }

    return `${this.getPageCountText()} | Current ${this.getPageLabel(activePage.order)}`;
  }

  private getActivePageLabel(): string {
    const activePage: NotebookPage | null = this.getActivePage();
    if (activePage === null) {
      return 'Page';
    }
    return this.getPageLabel(activePage.order);
  }

  private getActivePageIndexText(): string {
    const activePage: NotebookPage | null = this.getActivePage();
    if (activePage === null) {
      return this.getPageCountText();
    }

    return `${activePage.order + 1}/${this.notebookPageList.length}`;
  }

  private getActiveCanvasBackgroundColor(): string {
    if (this.activePageCanvas === null) {
      return '#FFFFFF';
    }
    return this.activePageCanvas.backgroundColor;
  }

  private getCanvasText(): string {
    if (this.isCanvasLoading) {
      return 'Loading';
    }
    if (this.activePageCanvas === null) {
      return 'Unavailable';
    }
    return `${this.activePageCanvas.width} x ${this.activePageCanvas.height}`;
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
      activeStrokeStyle: null,
      undoDepth: 0,
      redoDepth: 0,
      recentEvents: [],
      errorMessage: '',
      persistenceStatus: 'idle'
    };
  }

  private resolveRouteParams(): RouterParams {
    try {
      return router.getParams() as RouterParams;
    } catch (_error) {
      return {};
    }
  }
}
