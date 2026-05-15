import common from '@ohos.app.ability.common';
import picker from '@ohos.file.picker';
import router from '@ohos.router';

import { AppRouter, RouterParams } from '../../../app/AppRouter';
import { ImageAssetDataSource, ImportedImageAsset } from '../../../data/sources/local/ImageAssetDataSource';
import { Notebook } from '../../../domain/entities/Notebook';
import { NotebookPage, NotebookPageTemplateType } from '../../../domain/entities/NotebookPage';
import { ShapeType } from '../../../domain/entities/CanvasElement';
import { NotebookPageCanvas, NotebookPageCanvasEntity } from '../../../domain/entities/NotebookPageCanvas';
import { ToolSetting, ToolType } from '../../../domain/entities/ToolSetting';
import { CanvasBoard, CanvasBoardContentChangeKind } from '../components/CanvasBoard';
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

const SIDEBAR_EXPANDED_PADDING = 16;
const THUMBNAIL_REFRESH_INTERVAL_MS = 320;
const SIDEBAR_EXPANDED_WIDTH = 232;
const SIDEBAR_COLLAPSED_WIDTH = 56;
const PAGE_THUMBNAIL_WIDTH = SIDEBAR_EXPANDED_WIDTH - SIDEBAR_EXPANDED_PADDING * 2;
const WORKSPACE_MENU_BUTTON_FONT_SIZE = 26;
const PAGE_TEMPLATE_DROPDOWN_LEFT = 384;
const DOCUMENT_PAGE_GAP = 10;
const DOCUMENT_PAGE_HORIZONTAL_PADDING = 12;
const DOCUMENT_PAGE_HEADER_HEIGHT = 28;
const DOCUMENT_PAGE_SURFACE_MAX_WIDTH = 980;
const DOCUMENT_PAGE_SURFACE_MIN_WIDTH = 320;
const DOCUMENT_PAGE_RENDER_WINDOW_PADDING_FACTOR = 1.25;
const DOCUMENT_ZOOM_MIN_SCALE = 0.72;
const DOCUMENT_ZOOM_MAX_SCALE = 2.2;
const DOCUMENT_ZOOM_STEP = 0.08;
const WORKSPACE_TOOL_OPTIONS: ToolType[] = ['pen', 'pencil', 'highlighter', 'eraser', 'text', 'shape', 'edit'];
const SHAPE_TOOL_OPTIONS: ShapeType[] = ['rectangle', 'circle', 'line'];
const PAGE_TEMPLATE_OPTIONS: NotebookPageTemplateType[] = [
  NotebookPageTemplateType.BLANK,
  NotebookPageTemplateType.LINED,
  NotebookPageTemplateType.GRID,
  NotebookPageTemplateType.DOTTED
];

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
  @State private isUpdatingPageTemplate: boolean = false;
  @State private isImportingImage: boolean = false;
  @State private pageActionMenuPageId: string = '';
  @State private isDeletePageDialogVisible: boolean = false;
  @State private isDeletingPage: boolean = false;
  @State private deleteTargetPageId: string = '';
  @State private deleteTargetPageLabel: string = '';
  @State private deleteTargetPageOrder: number = -1;
  @State private hasMissingNotebookId: boolean = false;
  @State private isNotebookMissing: boolean = false;
  @State private toolSetting: ToolSetting = this.buildDefaultToolSetting();
  private lastWritingTool: ToolType = 'pen';
  @State private selectedShapeType: ShapeType = 'rectangle';
  @State private editorSnapshot: EditorDebugSnapshot = this.buildEmptySnapshot('');
  @State private canvasVersion: number = 0;
  @State private elementLayerRefreshVersion: number = 0;
  @State private thumbnailRefreshVersion: number = 0;
  @State private isPagePreviewCollapsed: boolean = false;
  @State private isToolDropdownVisible: boolean = false;
  @State private isShapeDropdownVisible: boolean = false;
  @State private isPageTemplateDropdownVisible: boolean = false;
  @State private isCanvasPanModeEnabled: boolean = false;
  @State private workspaceViewportWidth: number = 0;
  @State private workspaceViewportHeight: number = 0;
  @State private documentZoomScale: number = 1;
  @State private documentHorizontalOffset: number = 0;
  @State private documentScrollOffsetY: number = 0;
  @State private documentGesturePreviewScale: number = 1;
  @State private documentGesturePreviewOffsetX: number = 0;
  private readonly pageCanvasRenderSizeMap: Map<string, PageCanvasRenderSize> = new Map<string, PageCanvasRenderSize>();
  private readonly documentScroller: Scroller = new Scroller();
  private thumbnailRefreshTimerId: number = -1;
  private lastThumbnailRefreshTime: number = 0;
  private documentGestureStartZoomScale: number = 1;
  private documentGestureTargetZoomScale: number = 1;
  private documentGestureTargetHorizontalOffset: number = 0;
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
    this.isToolDropdownVisible = false;
    this.isShapeDropdownVisible = false;
    this.isPageTemplateDropdownVisible = false;
    this.isCanvasPanModeEnabled = false;
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
              this.closeTransientDropdowns();
              AppRouter.openNotebookList();
            })

          Button($r('app.string.editor_nav_home'))
            .height($r('app.float.button_height'))
            .backgroundColor($r('app.color.surface_background'))
            .fontColor($r('app.color.primary_text'))
            .onClick(() => {
              this.closeTransientDropdowns();
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
    Stack({ alignContent: Alignment.Center }) {
      Row() {
        Button('返回')
          .height(34)
          .padding({
            left: 12,
            right: 12
          })
          .backgroundColor($r('app.color.surface_background'))
          .fontColor($r('app.color.primary_text'))
          .onClick(() => {
            this.closeTransientDropdowns();
            AppRouter.back();
          })

        Blank()
          .layoutWeight(1)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Text(this.notebookTitle)
        .fontSize($r('app.float.section_title_size'))
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.primary_text'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.Center)
        .constraintSize({ maxWidth: '40%' })
    }
    .width('100%')
    .padding({
      left: 16,
      right: 16,
      top: 10,
      bottom: 10
    })
    .backgroundColor($r('app.color.editor_toolbar_background'))
    .borderRadius(28)
    .border({
      width: 1,
      color: $r('app.color.editor_toolbar_border')
    })
    .onClick(() => {
      this.closeToolDropdown();
      this.closeShapeDropdown();
    })
  }

  @Builder
  private buildSidebar(): void {
    Column({ space: 14 }) {
      Row({ space: this.isPagePreviewCollapsed ? 6 : 10 }) {
        if (!this.isPagePreviewCollapsed) {
          // Text($r('app.string.editor_sidebar_title'))
          //   .fontSize($r('app.float.section_title_size'))
          //   .fontWeight(FontWeight.Medium)
          //   .fontColor($r('app.color.primary_text'))
          //   .layoutWeight(1)

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

        if (!this.isPagePreviewCollapsed) {
          Blank()
            .layoutWeight(1)
        }

        if (!this.isPagePreviewCollapsed) {
          Button() {
            Text('+')
              .fontColor('#000000')
              .fontSize(22)
              .fontWeight(FontWeight.Bold)
              .textAlign(TextAlign.Center)
              .width('100%')
          }
          .width(32)
          .height(32)
          .padding(0)
          .backgroundColor('#fff2f2f2')
          .borderRadius(10)
          .enabled(!this.isCreatingPage && !this.isDeletingPage && !this.isReorderingPages &&
            !this.isUpdatingPageTemplate)
          .onClick(() => {
            this.closeTransientDropdowns();
            void this.createNotebookPage();
          })
        }

        Button() {
          Text(this.isPagePreviewCollapsed ? '>' : '<')
            .fontColor('#000000')
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .textAlign(TextAlign.Center)
            .width('100%')
        }
        .width(32)
        .height(32)
        .padding(0)
        .backgroundColor('#fff2f2f2')
        .borderRadius(10)
        .onClick(() => {
          this.closeTransientDropdowns();
          this.isPagePreviewCollapsed = !this.isPagePreviewCollapsed;
        })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .justifyContent(FlexAlign.End)

      if (!this.isPagePreviewCollapsed) {
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
          List({ space: 12 }) {
            ForEach(this.notebookPageList, (page: NotebookPage, index: number) => {
              ListItem() {
                this.buildPageThumbnail(page, index);
              }
              .width('100%')
              .height(this.getPageThumbnailHeight(page.id))
            }, (page: NotebookPage): string => this.getPageRenderKey(page))
              .onMove((from: number, to: number): void => {
                this.handlePageListItemMove(from, to);
              })
          }
          .layoutWeight(1)
          .width('100%')
          .scrollBar(BarState.Off)
        }

      }
    }
    .width(this.isPagePreviewCollapsed ? SIDEBAR_COLLAPSED_WIDTH : SIDEBAR_EXPANDED_WIDTH)
    .height('100%')
    .padding(this.isPagePreviewCollapsed ? 10 : SIDEBAR_EXPANDED_PADDING)
    .backgroundColor($r('app.color.editor_sidebar_background'))
    .borderRadius(28)
    .border({
      width: 1,
      color: $r('app.color.editor_sidebar_border')
    })
    .onClick(() => {
      this.closeToolDropdown();
      this.closeShapeDropdown();
    })
  }

  @Builder
  private buildPageThumbnail(page: NotebookPage, pageIndex: number): void {
    Column() {
      Stack({ alignContent: Alignment.BottomEnd }) {
        PageThumbnailPreview({
          pageId: page.id,
          isActive: page.id === this.activePageId,
          refreshVersion: this.thumbnailRefreshVersion,
          templateType: this.resolvePageTemplateType(page.templateType),
          paperBackgroundColor: page.id === this.activePageId ? this.getActiveCanvasBackgroundColor() : '#FFFFFF',
          canvasWidth: this.getThumbnailCanvasWidth(page.id),
          canvasHeight: this.getThumbnailCanvasHeight(page.id)
        })
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.surface_background'))
        .borderRadius(18)
        .border({
          width: 1,
          color: page.id === this.activePageId ? $r('app.color.editor_accent') :
            $r('app.color.editor_paper_border')
        })

        Text(this.getPageOrderText(page.id, pageIndex))
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor(page.id === this.activePageId ? '#FFFFFF' : $r('app.color.primary_text'))
          .width(24)
          .height(24)
          .textAlign(TextAlign.Center)
          .backgroundColor(page.id === this.activePageId ? $r('app.color.editor_accent') : '#FFFFFF')
          .borderRadius(6)
          .margin({
            right: 8,
            bottom: 8
          })

        Text('⋮⋮')
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.secondary_text'))
          .opacity(this.canDragReorderPages() ? 0.72 : 0.28)
          .margin({
            left: 10,
            top: 8
          })
          .align(Alignment.TopStart)
      }
      .width('100%')
      .layoutWeight(1)
      .onClick(() => {
        this.closeTransientDropdowns();
        void this.selectNotebookPage(page);
      })
    }
    .width('100%')
    .height(this.getPageThumbnailHeight(page.id))
    .alignItems(HorizontalAlign.Start)
    // .padding(12)
    .backgroundColor(this.getPageThumbnailBackgroundColor(page))
    .borderRadius(22)
    .border({
      width: page.id === this.activePageId ? 2 : 1,
      color: this.getPageThumbnailBorderColor(page)
    })
  }

  @Builder
  private buildWorkspace(): void {
    Stack({ alignContent: Alignment.TopEnd }) {
      Column({ space: 16 }) {
        Row({ space: 12 }) {

          if (this.notebookPageList.length > 0) {
            Row({ space: 8 }) {
              ForEach(WORKSPACE_TOOL_OPTIONS, (tool: ToolType) => {
                Button(this.getWorkspaceToolLabel(tool))
                  .height(32)
                  .padding({
                    left: 10,
                    right: 10
                  })
                  .fontSize(12)
                  .backgroundColor(this.isWorkspaceToolActive(tool) ? '#0F172A' : '#FFFFFF')
                  .fontColor(this.isWorkspaceToolActive(tool) ? '#FFFFFF' : '#475569')
                  .borderRadius(10)
                  .border({
                    width: 1,
                    color: this.isWorkspaceToolActive(tool) ? '#0F172A' : '#CBD5E1'
                  })
                  .enabled(!this.isCanvasLoading)
                  .onClick(() => {
                    this.handleWorkspaceToolButtonClick(tool);
                  })
              }, (tool: ToolType): string => tool)

              this.buildCanvasPanToolbarButton()

              Button('Image')
                .height(32)
                .padding({
                  left: 10,
                  right: 10
                })
                .fontSize(12)
                .backgroundColor('#FFFFFF')
                .fontColor('#475569')
                .borderRadius(10)
                .border({
                  width: 1,
                  color: '#CBD5E1'
                })
                .enabled(!this.isCanvasLoading && !this.isImportingImage)
                .onClick(() => {
                  void this.handleImageInsertRequest();
                })

              this.buildPageTemplateToolbarButton()
            }
            .alignItems(VerticalAlign.Center)

            Blank()
              .layoutWeight(1)

            Row({ space: 8 }) {
              Button() {
                if (this.editorSnapshot.undoDepth > 0 && !this.isCanvasLoading) {
                  Image($r('app.media.undo_white'))
                    .width(18)
                    .height(18)
                } else {
                  Image($r('app.media.undo'))
                    .width(18)
                    .height(18)
                    .opacity(0.45)
                }
              }
                .width(40)
                .height(40)
                .enabled(this.editorSnapshot.undoDepth > 0 && !this.isCanvasLoading)
                .backgroundColor(this.editorSnapshot.undoDepth > 0 && !this.isCanvasLoading ?
                  $r('app.color.primary_text') : $r('app.color.app_background'))
                .borderRadius(12)
                .onClick(() => {
                  this.closeTransientDropdowns();
                  void this.handleUndo();
                })

              Button() {
                if (this.editorSnapshot.redoDepth > 0 && !this.isCanvasLoading) {
                  Image($r('app.media.redo_white'))
                    .width(18)
                    .height(18)
                } else {
                  Image($r('app.media.redo'))
                    .width(18)
                    .height(18)
                    .opacity(0.45)
                }
              }
                .width(40)
                .height(40)
                .enabled(this.editorSnapshot.redoDepth > 0 && !this.isCanvasLoading)
                .backgroundColor(this.editorSnapshot.redoDepth > 0 && !this.isCanvasLoading ?
                  $r('app.color.primary_text') : $r('app.color.app_background'))
                .borderRadius(12)
                .onClick(() => {
                  this.closeTransientDropdowns();
                  void this.handleRedo();
                })

              Button() {
                if (this.editorSnapshot.strokeCount > 0 && !this.isCanvasLoading) {
                  Image($r('app.media.clear_white'))
                    .width(18)
                    .height(18)
                } else {
                  Image($r('app.media.clear'))
                    .width(18)
                    .height(18)
                    .opacity(0.45)
                }
              }
                .width(40)
                .height(40)
                .enabled(this.editorSnapshot.strokeCount > 0 && !this.isCanvasLoading)
                .backgroundColor(this.editorSnapshot.strokeCount > 0 && !this.isCanvasLoading ?
                  $r('app.color.danger_text') : $r('app.color.danger_surface'))
                .borderRadius(12)
                .onClick(() => {
                  this.closeTransientDropdowns();
                  void this.handleClear();
                })

              Button() {
                Image($r('app.media.page'))
                  .width(18)
                  .height(18)
              }
                .width(40)
                .height(40)
                .backgroundColor('#fff3f3f3')
                .enabled(!this.isCreatingPage && !this.isDeletingPage && !this.isReorderingPages &&
                  !this.isUpdatingPageTemplate)
                .borderRadius(12)
                .onClick(() => {
                  this.closeToolDropdown();
                  this.closeShapeDropdown();
                  this.closePageTemplateDropdown();
                  this.togglePageActionMenu(this.activePageId);
                })

              this.buildDocumentZoomToolbar()

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
        .zIndex(10)

        this.buildWorkspaceSurface()
      }
      .width('100%')
      .height('100%')
      .onClick(() => {
        this.closeToolDropdown();
        this.closeShapeDropdown();
      })

      if (this.activePageId.length > 0 && this.isPageActionMenuVisible(this.activePageId)) {
        this.buildPageActionMenu()
      }

      if (this.isToolDropdownVisible) {
        this.buildToolDropdown()
      }

      if (this.isShapeDropdownVisible) {
        this.buildShapeDropdown()
      }

      if (this.isPageTemplateDropdownVisible) {
        this.buildPageTemplateDropdown()
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
      } else {
        Row() {
          this.buildPaperSurface()
        }
        .width('100%')
        .height('100%')
        .alignItems(VerticalAlign.Top)
      }
    }
    .layoutWeight(1)
    .width('100%')
    .clip(true)
    .zIndex(0)
    .onClick(() => {
      this.closeTransientDropdowns();
    })
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
  private buildDocumentZoomToolbar(): void {
    Row({ space: 6 }) {
      Button('-')
        .width(30)
        .height(30)
        .padding(0)
        .fontSize(14)
        .backgroundColor('#FFFFFF')
        .fontColor('#475569')
        .borderRadius(10)
        .border({
          width: 1,
          color: '#CBD5E1'
        })
        .enabled(this.canDecreaseDocumentZoom())
        .opacity(this.canDecreaseDocumentZoom() ? 1 : 0.45)
        .onClick(() => {
          this.adjustDocumentZoomScale(-DOCUMENT_ZOOM_STEP);
        })

      Button(this.getDocumentZoomText())
        .height(30)
        .padding({
          left: 10,
          right: 10
        })
        .fontSize(12)
        .backgroundColor('#FFFFFF')
        .fontColor('#475569')
        .borderRadius(10)
        .border({
          width: 1,
          color: '#CBD5E1'
        })
        .onClick(() => {
          this.resetDocumentZoomScale();
        })

      Button('+')
        .width(30)
        .height(30)
        .padding(0)
        .fontSize(14)
        .backgroundColor('#FFFFFF')
        .fontColor('#475569')
        .borderRadius(10)
        .border({
          width: 1,
          color: '#CBD5E1'
        })
        .enabled(this.canIncreaseDocumentZoom())
        .opacity(this.canIncreaseDocumentZoom() ? 1 : 0.45)
        .onClick(() => {
          this.adjustDocumentZoomScale(DOCUMENT_ZOOM_STEP);
        })
    }
    .alignItems(VerticalAlign.Center)
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
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private buildToolDropdown(): void {
    Row() {
      ToolPropertyPanel({
        pageId: this.activePageId,
        toolSetting: $toolSetting
      })
      .width(276)
    }
    .width('100%')
    .margin({
      top: 52
    })
    .justifyContent(FlexAlign.Start)
    .alignItems(VerticalAlign.Top)
  }

  @Builder
  private buildShapeDropdown(): void {
    Row() {
      Column({ space: 7 }) {
        Text('Shape')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor('#111827')
          .width('100%')

        ForEach(SHAPE_TOOL_OPTIONS, (shapeType: ShapeType) => {
          this.buildShapeOption(shapeType)
        }, (shapeType: ShapeType): string => shapeType)
      }
      .width(204)
      .padding(7)
      .backgroundColor('#F8FAFC')
      .borderRadius(12)
      .border({
        width: 1,
        color: '#E2E8F0'
      })
    }
    .width('100%')
    .margin({
      top: 52
    })
    .justifyContent(FlexAlign.Start)
    .alignItems(VerticalAlign.Top)
  }

  @Builder
  private buildShapeOption(shapeType: ShapeType): void {
    Button() {
      Row({ space: 8 }) {
        this.buildShapeGlyph(shapeType, this.selectedShapeType === shapeType)

        Text(this.getShapeLabel(shapeType))
          .fontSize(13)
          .fontWeight(this.selectedShapeType === shapeType ? FontWeight.Medium : FontWeight.Regular)
          .fontColor(this.selectedShapeType === shapeType ? '#FFFFFF' : '#334155')
          .layoutWeight(1)
          .textAlign(TextAlign.Start)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .height(38)
    .padding({
      left: 8,
      right: 8
    })
    .backgroundColor(this.selectedShapeType === shapeType ? '#0F172A' : '#FFFFFF')
    .borderRadius(10)
    .border({
      width: 1,
      color: this.selectedShapeType === shapeType ? '#0F172A' : '#CBD5E1'
    })
    .enabled(!this.isCanvasLoading)
    .onClick(() => {
      this.selectedShapeType = shapeType;
      this.handleWorkspaceToolChange('shape');
      this.closeShapeDropdown();
    })
  }

  @Builder
  private buildShapeGlyph(shapeType: ShapeType, isSelected: boolean): void {
    Stack({ alignContent: Alignment.Center }) {
      if (shapeType === 'rectangle') {
        Column() {}
          .width(24)
          .height(16)
          .backgroundColor('#00FFFFFF')
          .border({
            width: 2,
            color: isSelected ? '#FFFFFF' : '#111827'
          })
      } else if (shapeType === 'circle') {
        Column() {}
          .width(20)
          .height(20)
          .backgroundColor('#00FFFFFF')
          .borderRadius('50%')
          .border({
            width: 2,
            color: isSelected ? '#FFFFFF' : '#111827'
          })
      } else if (shapeType === 'line') {
        Column() {}
          .width(24)
          .height(2)
          .backgroundColor(isSelected ? '#FFFFFF' : '#111827')
      }
    }
    .width(28)
    .height(20)
  }

  @Builder
  private buildPageTemplateDropdown(): void {
    Row() {
      Column({ space: 7 }) {
        Text('页面模板')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor('#111827')
          .width('100%')

        ForEach(PAGE_TEMPLATE_OPTIONS, (templateType: NotebookPageTemplateType) => {
          this.buildPageTemplateOption(templateType)
        }, (templateType: NotebookPageTemplateType): string => templateType)
      }
      .width(204)
      .padding(7)
      .backgroundColor('#F8FAFC')
      .borderRadius(12)
      .border({
        width: 1,
        color: '#E2E8F0'
      })
    }
    .width('100%')
    .margin({
      top: 52,
      left: PAGE_TEMPLATE_DROPDOWN_LEFT
    })
    .justifyContent(FlexAlign.Start)
    .alignItems(VerticalAlign.Top)
  }

  @Builder
  private buildPaperSurface(): void {
    Scroll(this.documentScroller) {
      Column({ space: DOCUMENT_PAGE_GAP }) {
        ForEach(this.notebookPageList, (page: NotebookPage, index: number) => {
          this.buildDocumentPageSurface(page, index);
        }, (page: NotebookPage): string => this.getPageRenderKey(page))
      }
      .width('100%')
      .padding({
        left: DOCUMENT_PAGE_HORIZONTAL_PADDING,
        right: DOCUMENT_PAGE_HORIZONTAL_PADDING,
        top: DOCUMENT_PAGE_HORIZONTAL_PADDING,
        bottom: DOCUMENT_PAGE_HORIZONTAL_PADDING
      })
      .alignItems(HorizontalAlign.Center)
      .offset({
        x: this.getDocumentVisualOffsetX(),
        y: 0
      })
      .scale({
        x: this.documentGesturePreviewScale,
        y: this.documentGesturePreviewScale,
        centerX: Math.max(0, this.workspaceViewportWidth / 2),
        centerY: 0
      })
    }
    .width('100%')
    .layoutWeight(1)
    .height('100%')
    .scrollable(this.getDocumentScrollDirection())
    .enableScrollInteraction(this.isDocumentNavigationModeEnabled())
    .onDidScroll((_xOffset: number, _yOffset: number, _scrollState: ScrollState) => {
      this.handleDocumentDidScroll();
    })
    .onScrollStop(() => {
      void this.commitViewportCenteredPage();
    })
    .scrollBar(BarState.Off)
    .backgroundColor($r('app.color.editor_workspace_background'))
    .borderRadius(30)
    .clip(true)
    .border({
      width: 1,
      color: $r('app.color.editor_paper_border')
    })
    .onAreaChange((_oldValue: Area, newValue: Area) => {
      this.handleWorkspaceAreaChange(newValue);
    })
  }

  @Builder
  private buildDocumentPageSurface(page: NotebookPage, pageIndex: number): void {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        Text(this.getPageOrderText(page.id, pageIndex))
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.isDocumentPageActive(page.id) ? '#FFFFFF' : '#475569')
          .padding({
            left: 10,
            right: 10,
            top: 5,
            bottom: 5
          })
          .backgroundColor(this.isDocumentPageActive(page.id) ? $r('app.color.editor_accent') : '#FFFFFF')
          .borderRadius(999)

        if (this.isDocumentPageActive(page.id)) {
          Text('Current')
            .fontSize(11)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.editor_accent'))
            .padding({
              left: 8,
              right: 8,
              top: 4,
              bottom: 4
            })
            .backgroundColor($r('app.color.editor_accent_soft'))
            .borderRadius(999)
        }

        Blank()
          .layoutWeight(1)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Stack() {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(this.getPageCanvasBackgroundColor(page.id))
          .borderRadius(24)

        if (this.shouldRenderEditableDocumentPage(page.id)) {
          CanvasBoard({
            pageId: page.id,
            canvasVersion: this.canvasVersion,
            elementVersion: this.elementLayerRefreshVersion,
            selectedShapeType: this.selectedShapeType,
            templateType: this.resolvePageTemplateType(page.templateType),
            paperBackgroundColor: this.getPageCanvasBackgroundColor(page.id),
            pageWidth: this.getPageCanvasWidth(page.id),
            pageHeight: this.getPageCanvasHeight(page.id),
            isPanModeEnabled: this.isCanvasPanModeEnabled,
            isDocumentViewportMode: this.isContinuousDocumentViewEnabled(),
            activeTool: this.toolSetting.tool,
            editorSnapshot: $editorSnapshot,
            onContentChanged: (immediate: boolean, kind: CanvasBoardContentChangeKind): void => {
              if (kind === 'element') {
                this.refreshElementLayer();
              }
              this.restoreWritingToolAfterOneShotElementInsertion();
              if (immediate || kind === 'stroke') {
                this.requestThumbnailRefresh(immediate);
              }
            },
            onCanvasMetricsChanged: (width: number, height: number): void => {
              this.updatePageCanvasRenderSize(page.id, width, height);
            },
            onDocumentViewportGestureStart: (): void => {
              this.beginDocumentViewportGesture();
            },
            onDocumentViewportGestureUpdate: (scaleRatio: number, deltaX: number, deltaY: number): void => {
              this.updateDocumentViewportGesture(scaleRatio, deltaX, deltaY);
            },
            onDocumentViewportGestureEnd: (): void => {
              this.endDocumentViewportGesture();
            }
          })
            .width('100%')
            .height('100%')
        } else if (this.shouldRenderDocumentPagePreview(page.id)) {
          PageThumbnailPreview({
            pageId: page.id,
            isActive: false,
            refreshVersion: this.thumbnailRefreshVersion,
            templateType: this.resolvePageTemplateType(page.templateType),
            paperBackgroundColor: this.getPageCanvasBackgroundColor(page.id),
            canvasWidth: this.getPageCanvasWidth(page.id),
            canvasHeight: this.getPageCanvasHeight(page.id)
          })
            .width('100%')
            .height('100%')
        }

        if (this.isDocumentPageActive(page.id) && this.isCanvasLoading && !this.isDocumentNavigationModeEnabled()) {
          Column({ space: 10 }) {
            LoadingProgress()
              .width(28)
              .height(28)

            Text($r('app.string.editor_loading'))
              .fontSize(12)
              .fontColor($r('app.color.secondary_text'))
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .backgroundColor('#66FFFFFF')
        }
      }
      .width(this.getDocumentPageSurfaceWidth())
      .height(this.getDocumentPageSurfaceHeightForPage(page.id))
      .borderRadius(24)
      .clip(true)
      .border({
        width: this.isDocumentPageActive(page.id) ? 2 : 1,
        color: this.isDocumentPageActive(page.id) ? $r('app.color.editor_accent') : $r('app.color.editor_paper_border')
      })
      .shadow({
        radius: 18,
        color: '#14000000',
        offsetX: 0,
        offsetY: 6
      })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
    .onClick(() => {
      if (this.isDocumentPageActive(page.id)) {
        return;
      }
      this.closeTransientDropdowns();
      void this.selectNotebookPage(page);
    })
  }

  @Builder
  private buildPageActionMenu(): void {
    Column({ space: 6 }) {
      Button($r('app.string.editor_page_move_up'))
        .width('100%')
        .height(34)
        .backgroundColor($r('app.color.app_background'))
        .fontColor($r('app.color.primary_text'))
        .enabled(this.canMoveActivePageUp() && !this.isReorderingPages && !this.isUpdatingPageTemplate)
        .onClick(() => {
          this.closeToolDropdown();
          const activePage: NotebookPage | null = this.getActivePage();
          if (activePage !== null) {
            this.moveNotebookPageByOffset(activePage, -1);
          }
        })

      Button($r('app.string.editor_page_move_down'))
        .width('100%')
        .height(34)
        .backgroundColor($r('app.color.app_background'))
        .fontColor($r('app.color.primary_text'))
        .enabled(this.canMoveActivePageDown() && !this.isReorderingPages && !this.isUpdatingPageTemplate)
        .onClick(() => {
          this.closeToolDropdown();
          const activePage: NotebookPage | null = this.getActivePage();
          if (activePage !== null) {
            this.moveNotebookPageByOffset(activePage, 1);
          }
        })

      Button($r('app.string.editor_page_delete_menu'))
        .width('100%')
        .height(34)
        .backgroundColor($r('app.color.danger_surface'))
        .fontColor($r('app.color.danger_text'))
        .enabled(!this.isDeletingPage && !this.isUpdatingPageTemplate)
        .onClick(() => {
          this.closeToolDropdown();
          const activePage: NotebookPage | null = this.getActivePage();
          if (activePage !== null) {
            this.openDeletePageDialog(activePage);
          }
        })
    }
    .width(156)
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
  private buildCanvasPanToolbarButton(): void {
    Button('Pan')
    .height(32)
    .padding({
      left: 10,
      right: 10
    })
    .fontSize(12)
    .backgroundColor(this.isCanvasPanModeEnabled ? '#0F172A' : '#FFFFFF')
    .fontColor(this.isCanvasPanModeEnabled ? '#FFFFFF' : '#475569')
    .borderRadius(10)
    .border({
      width: 1,
      color: this.isCanvasPanModeEnabled ? '#0F172A' : '#CBD5E1'
    })
    .enabled(!this.isCanvasLoading)
    .onClick(() => {
      this.toggleCanvasPanMode();
    })
  }

  @Builder
  private buildPageTemplateToolbarButton(): void {
    Button('Template')
    .height(32)
    .padding({
      left: 10,
      right: 10
    })
    .fontSize(12)
    .backgroundColor(this.isPageTemplateDropdownVisible ? '#0F172A' : '#FFFFFF')
    .fontColor(this.isPageTemplateDropdownVisible ? '#FFFFFF' : '#475569')
    .borderRadius(10)
    .border({
      width: 1,
      color: this.isPageTemplateDropdownVisible ? '#0F172A' : '#CBD5E1'
    })
    .enabled(!this.isUpdatingPageTemplate && !this.isCanvasLoading)
    .onClick(() => {
      this.togglePageTemplateDropdown();
    })
  }

  @Builder
  private buildPageTemplateOption(templateType: NotebookPageTemplateType): void {
    Button() {
      Row({ space: 8 }) {
        this.buildPageTemplateGlyph(templateType, this.isActivePageTemplate(templateType))

        Text(this.getPageTemplateLabel(templateType))
          .fontSize(13)
          .fontWeight(this.isActivePageTemplate(templateType) ? FontWeight.Medium : FontWeight.Regular)
          .fontColor(this.isActivePageTemplate(templateType) ? '#FFFFFF' : '#334155')
          .layoutWeight(1)
          .textAlign(TextAlign.Start)

        Text(this.isActivePageTemplate(templateType) ? '✓' : '')
          .fontSize(13)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF')
          .width(14)
          .textAlign(TextAlign.Center)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .height(38)
    .padding({
      left: 8,
      right: 8
    })
    .backgroundColor(this.isActivePageTemplate(templateType) ? '#0F172A' : '#FFFFFF')
    .borderRadius(10)
    .border({
      width: 1,
      color: this.isActivePageTemplate(templateType) ? '#0F172A' : '#CBD5E1'
    })
    .enabled(!this.isUpdatingPageTemplate && !this.isCanvasLoading)
    .onClick(() => {
      void this.updateActivePageTemplate(templateType);
    })
  }

  @Builder
  private buildPageTemplateGlyph(templateType: NotebookPageTemplateType, isSelected: boolean): void {
    Stack({ alignContent: Alignment.Center }) {
      Column() {}
        .width(30)
        .height(22)
        .backgroundColor(isSelected ? '#FFFFFF' : '#F8FAFC')
        .borderRadius(6)
        .border({
          width: 1,
          color: isSelected ? '#E2E8F0' : '#CBD5E1'
        })

      if (templateType === NotebookPageTemplateType.LINED) {
        this.buildPageTemplateLinesGlyph(isSelected ? '#2563EB' : '#94A3B8')
      } else if (templateType === NotebookPageTemplateType.GRID) {
        this.buildPageTemplateGridGlyph(isSelected ? '#2563EB' : '#94A3B8')
      } else if (templateType === NotebookPageTemplateType.DOTTED) {
        this.buildPageTemplateDotsGlyph(isSelected ? '#2563EB' : '#94A3B8')
      }
    }
    .width(30)
    .height(22)
  }

  @Builder
  private buildPageTemplateLinesGlyph(color: string): void {
    Column({ space: 4 }) {
      ForEach([0, 1, 2], (item: number) => {
        Column() {}
          .width(20)
          .height(1)
          .backgroundColor(color)
      }, (item: number): string => `${item}`)
    }
    .width(22)
    .height(14)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private buildPageTemplateGridGlyph(color: string): void {
    Stack({ alignContent: Alignment.Center }) {
      Column() {}
        .width(20)
        .height(1)
        .backgroundColor(color)
        .offset({ y: -5 })

      Column() {}
        .width(20)
        .height(1)
        .backgroundColor(color)

      Column() {}
        .width(20)
        .height(1)
        .backgroundColor(color)
        .offset({ y: 5 })

      Column() {}
        .width(1)
        .height(16)
        .backgroundColor(color)
        .offset({ x: -6 })

      Column() {}
        .width(1)
        .height(16)
        .backgroundColor(color)

      Column() {}
        .width(1)
        .height(16)
        .backgroundColor(color)
        .offset({ x: 6 })
    }
    .width(22)
    .height(16)
  }

  @Builder
  private buildPageTemplateDotsGlyph(color: string): void {
    Stack({ alignContent: Alignment.Center }) {
      this.buildPageTemplateDot(-7, -5, color)
      this.buildPageTemplateDot(0, -5, color)
      this.buildPageTemplateDot(7, -5, color)
      this.buildPageTemplateDot(-7, 0, color)
      this.buildPageTemplateDot(0, 0, color)
      this.buildPageTemplateDot(7, 0, color)
      this.buildPageTemplateDot(-7, 5, color)
      this.buildPageTemplateDot(0, 5, color)
      this.buildPageTemplateDot(7, 5, color)
    }
    .width(22)
    .height(16)
  }

  @Builder
  private buildPageTemplateDot(offsetX: number, offsetY: number, color: string): void {
    Column() {}
      .width(3)
      .height(3)
      .backgroundColor(color)
      .borderRadius(2)
      .offset({ x: offsetX, y: offsetY })
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
          Button('取消')
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
    this.isUpdatingPageTemplate = false;
    this.pageActionMenuPageId = '';
    this.isPageTemplateDropdownVisible = false;
    this.isCanvasPanModeEnabled = false;
    this.documentZoomScale = 1;
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
    if (this.isCreatingPage || this.isReorderingPages || this.isUpdatingPageTemplate || this.notebookId.length === 0) {
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
    if (this.isDeletingPage || this.isCreatingPage || this.isReorderingPages || this.isUpdatingPageTemplate ||
      this.isLoading) {
      return;
    }

    if (page.id === this.activePageId) {
      this.closePageActionMenu();
      return;
    }

    this.activePageId = page.id;
    this.scrollDocumentToPage(page.id, false);
    this.closePageActionMenu();
    await this.loadActivePageCanvas();
  }

  private openDeletePageDialog(page: NotebookPage): void {
    if (this.isDeletingPage || this.isCreatingPage || this.isReorderingPages || this.isUpdatingPageTemplate) {
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
      this.isUpdatingPageTemplate || this.deleteTargetPageId.length === 0) {
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
      if (notebookPageCanvas !== null) {
        this.updatePageCanvasRenderSize(targetPageId, notebookPageCanvas.width, notebookPageCanvas.height);
      }
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
    }

    this.currentDrawingPageId = pageId;
    this.drawingViewModel = EditorSessionRegistry.getOrCreate(pageId, hostContext);
    this.toolSetting = this.buildDefaultToolSetting();
    this.editorSnapshot = this.buildEmptySnapshot(pageId);
    this.canvasVersion += 1;

    const targetPageId: string = pageId;
    const viewModel: DrawingEditorViewModel = this.drawingViewModel;
    this.syncDrawingSnapshot(false, viewModel, targetPageId);
    if (!viewModel.isLoadedForPage(targetPageId)) {
      const loadPageTask = viewModel.loadPage(targetPageId);
      await loadPageTask;
      if (this.activePageId === targetPageId && this.currentDrawingPageId === targetPageId) {
        this.syncDrawingSnapshot(true, viewModel, targetPageId);
      }
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
    pageId?: string,
    refreshThumbnailImmediately: boolean = true
  ): void {
    const targetViewModel: DrawingEditorViewModel | null = viewModel ?? this.drawingViewModel;
    const targetPageId: string = pageId ?? this.currentDrawingPageId;

    if (targetViewModel === null || targetPageId.length === 0) {
      this.toolSetting = this.buildDefaultToolSetting();
      this.editorSnapshot = this.buildEmptySnapshot(targetPageId);
      if (redrawCanvas) {
        this.canvasVersion += 1;
        this.refreshElementLayer();
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
      this.refreshElementLayer();
      this.requestThumbnailRefresh(refreshThumbnailImmediately);
    }
  }

  private refreshElementLayer(): void {
    this.elementLayerRefreshVersion += 1;
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

    const normalizedSize: PageCanvasRenderSize = this.normalizeCanvasRenderSize(width, height);
    const cachedSize = this.pageCanvasRenderSizeMap.get(pageId);
    if (cachedSize !== undefined && cachedSize.width === normalizedSize.width && cachedSize.height === normalizedSize.height) {
      return;
    }

    this.pageCanvasRenderSizeMap.set(pageId, normalizedSize);
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
    if (cachedSize !== undefined) {
      return cachedSize.width;
    }

    return this.getPageCanvasWidth(pageId);
  }

  private getThumbnailCanvasHeight(pageId: string): number {
    const cachedSize = this.pageCanvasRenderSizeMap.get(pageId);
    if (cachedSize !== undefined) {
      return cachedSize.height;
    }

    return this.getPageCanvasHeight(pageId);
  }

  private getPageThumbnailHeight(pageId: string): number {
    const canvasWidth: number = this.getThumbnailCanvasWidth(pageId);
    const canvasHeight: number = this.getThumbnailCanvasHeight(pageId);
    return Math.round(PAGE_THUMBNAIL_WIDTH * canvasHeight / Math.max(1, canvasWidth));
  }

  private getActiveCanvasBounds(): PageCanvasRenderSize {
    const cachedSize = this.pageCanvasRenderSizeMap.get(this.activePageId);
    if (cachedSize !== undefined && cachedSize.width > 0 && cachedSize.height > 0) {
      return {
        width: cachedSize.width,
        height: cachedSize.height
      };
    }

    if (this.activePageCanvas !== null) {
      return {
        width: this.activePageCanvas.width,
        height: this.activePageCanvas.height
      };
    }

    return {
      width: 1600,
      height: 900
    };
  }

  private handleWorkspaceAreaChange(area: Area): void {
    const nextWidth = this.resolveAreaWidth(area);
    const nextHeight = this.resolveAreaHeight(area);
    const hasWidthChanged = nextWidth > 0 && nextWidth !== this.workspaceViewportWidth;
    const hasHeightChanged = nextHeight > 0 && nextHeight !== this.workspaceViewportHeight;
    if (!hasWidthChanged && !hasHeightChanged) {
      return;
    }

    if (hasWidthChanged) {
      this.workspaceViewportWidth = nextWidth;
    }
    if (hasHeightChanged) {
      this.workspaceViewportHeight = nextHeight;
    }
    this.documentHorizontalOffset = this.clampDocumentHorizontalOffset(this.documentHorizontalOffset);
  }

  private resolveAreaWidth(area: Area): number {
    const numericWidth = Number(area.width);
    if (Number.isFinite(numericWidth) && numericWidth > 0) {
      return Math.round(numericWidth);
    }

    return 0;
  }

  private resolveAreaHeight(area: Area): number {
    const numericHeight = Number(area.height);
    if (Number.isFinite(numericHeight) && numericHeight > 0) {
      return Math.round(numericHeight);
    }

    return 0;
  }

  private getDocumentPageSurfaceWidth(): number {
    return this.getDocumentPageSurfaceWidthForScale(this.documentZoomScale);
  }

  private getDocumentPageSurfaceWidthForScale(scale: number): number {
    const availableWidth = this.workspaceViewportWidth > 0
      ? this.workspaceViewportWidth - DOCUMENT_PAGE_HORIZONTAL_PADDING * 2
      : DOCUMENT_PAGE_SURFACE_MAX_WIDTH;
    const scaledWidth = Math.round(availableWidth * scale);
    return Math.max(DOCUMENT_PAGE_SURFACE_MIN_WIDTH, scaledWidth);
  }

  private getDocumentPageSurfaceHeight(pageId: string, targetWidth: number): number {
    const pageWidth = this.getPageCanvasWidth(pageId);
    const pageHeight = this.getPageCanvasHeight(pageId);
    return Math.max(240, Math.round(targetWidth * pageHeight / Math.max(1, pageWidth)));
  }

  private getDocumentPageSurfaceHeightForPage(pageId: string): number {
    return this.getDocumentPageSurfaceHeight(pageId, this.getDocumentPageSurfaceWidth());
  }

  private isDocumentPageActive(pageId: string): boolean {
    return pageId === this.activePageId;
  }

  private isContinuousDocumentViewEnabled(): boolean {
    return true;
  }

  private isDocumentNavigationModeEnabled(): boolean {
    return this.isContinuousDocumentViewEnabled() && this.isCanvasPanModeEnabled;
  }

  private shouldRenderEditableDocumentPage(pageId: string): boolean {
    return this.isDocumentPageActive(pageId) && !this.isCanvasLoading && !this.isDocumentNavigationModeEnabled();
  }

  private shouldRenderDocumentPagePreview(pageId: string): boolean {
    return this.isDocumentPageActive(pageId) || this.isDocumentPageWithinRenderWindow(pageId);
  }

  private isDocumentPageWithinRenderWindow(pageId: string): boolean {
    const viewportHeight = Math.max(1, this.workspaceViewportHeight);
    const padding = viewportHeight * DOCUMENT_PAGE_RENDER_WINDOW_PADDING_FACTOR;
    const renderWindowTop = Math.max(0, this.documentScrollOffsetY - padding);
    const renderWindowBottom = this.documentScrollOffsetY + viewportHeight + padding;
    const pageTop = this.getDocumentPageBlockTop(pageId);
    const pageBottom = pageTop + this.getDocumentPageBlockHeight(pageId);
    return pageBottom >= renderWindowTop && pageTop <= renderWindowBottom;
  }

  private getDocumentScrollDirection(): ScrollDirection {
    return this.isContinuousDocumentViewEnabled() ? ScrollDirection.Vertical : ScrollDirection.None;
  }

  private adjustDocumentZoomScale(delta: number): void {
    this.setDocumentZoomScale(this.documentZoomScale + delta);
  }

  private resetDocumentZoomScale(): void {
    this.setDocumentZoomScale(1);
    this.documentHorizontalOffset = 0;
  }

  private clampDocumentZoomScale(scale: number): number {
    return Math.max(DOCUMENT_ZOOM_MIN_SCALE, Math.min(DOCUMENT_ZOOM_MAX_SCALE, scale));
  }

  private beginDocumentViewportGesture(): void {
    this.documentGestureStartZoomScale = this.documentZoomScale;
    this.documentGestureTargetZoomScale = this.documentZoomScale;
    this.documentGestureTargetHorizontalOffset = this.documentHorizontalOffset;
    this.documentGesturePreviewScale = 1;
    this.documentGesturePreviewOffsetX = 0;
    this.syncDocumentScrollOffsetFromScroller();
  }

  private updateDocumentViewportGesture(scaleRatio: number, deltaX: number, deltaY: number): void {
    const nextZoomScale = this.clampDocumentZoomScale(this.documentGestureStartZoomScale * scaleRatio);
    this.documentGestureTargetZoomScale = nextZoomScale;
    this.documentGestureTargetHorizontalOffset = this.clampDocumentHorizontalOffsetForScale(
      this.documentGestureTargetHorizontalOffset + deltaX,
      nextZoomScale
    );
    this.documentGesturePreviewScale = nextZoomScale / Math.max(0.001, this.documentZoomScale);
    this.documentGesturePreviewOffsetX = this.documentGestureTargetHorizontalOffset - this.documentHorizontalOffset;
    if (deltaY !== 0) {
      this.documentScroller.scrollBy(0, -deltaY);
      this.handleDocumentDidScroll();
    }
  }

  private endDocumentViewportGesture(): void {
    this.syncDocumentScrollOffsetFromScroller();
    const previousZoomScale = this.documentZoomScale;
    const nextZoomScale = this.documentGestureTargetZoomScale;
    const zoomRatio = nextZoomScale / Math.max(0.001, previousZoomScale);
    this.documentZoomScale = nextZoomScale;
    this.documentHorizontalOffset = this.clampDocumentHorizontalOffsetForScale(
      this.documentGestureTargetHorizontalOffset,
      this.documentZoomScale
    );
    this.documentGesturePreviewScale = 1;
    this.documentGesturePreviewOffsetX = 0;
    const nextScrollOffset = Math.max(0, this.documentScrollOffsetY * zoomRatio);
    this.documentScrollOffsetY = nextScrollOffset;
    this.documentScroller.scrollTo({
      xOffset: 0,
      yOffset: nextScrollOffset,
      animation: false
    });
    void this.commitViewportCenteredPage();
  }

  private setDocumentZoomScale(scale: number): void {
    this.documentZoomScale = this.clampDocumentZoomScale(scale);
    this.documentHorizontalOffset = this.clampDocumentHorizontalOffset(this.documentHorizontalOffset);
  }

  private getDocumentContentWidth(): number {
    return this.getDocumentPageSurfaceWidth() + DOCUMENT_PAGE_HORIZONTAL_PADDING * 2;
  }

  private getDocumentVisualOffsetX(): number {
    return this.documentHorizontalOffset + this.documentGesturePreviewOffsetX;
  }

  private clampDocumentHorizontalOffset(offset: number): number {
    return this.clampDocumentHorizontalOffsetForScale(offset, this.documentZoomScale);
  }

  private clampDocumentHorizontalOffsetForScale(offset: number, scale: number): number {
    const viewportWidth = Math.max(1, this.workspaceViewportWidth);
    const overflowWidth = Math.max(0, this.getDocumentContentWidthForScale(scale) - viewportWidth);
    if (overflowWidth <= 0) {
      return 0;
    }

    const halfOverflow = overflowWidth / 2;
    return Math.max(-halfOverflow, Math.min(halfOverflow, offset));
  }

  private getDocumentContentWidthForScale(scale: number): number {
    return this.getDocumentPageSurfaceWidthForScale(scale) + DOCUMENT_PAGE_HORIZONTAL_PADDING * 2;
  }

  private getDocumentScrollOffsetForPage(pageId: string): number {
    let offset = DOCUMENT_PAGE_HORIZONTAL_PADDING;
    for (let index = 0; index < this.notebookPageList.length; index += 1) {
      const page = this.notebookPageList[index];
      if (page.id === pageId) {
        return Math.max(0, offset);
      }

      offset += DOCUMENT_PAGE_HEADER_HEIGHT;
      offset += 10;
      offset += this.getDocumentPageSurfaceHeightForPage(page.id);
      offset += DOCUMENT_PAGE_GAP;
    }

    return Math.max(0, offset);
  }

  private getDocumentPageBlockTop(pageId: string): number {
    let offset = DOCUMENT_PAGE_HORIZONTAL_PADDING;
    for (const page of this.notebookPageList) {
      if (page.id === pageId) {
        return offset;
      }

      offset += this.getDocumentPageBlockHeight(page.id);
      offset += DOCUMENT_PAGE_GAP;
    }

    return offset;
  }

  private getDocumentPageBlockHeight(pageId: string): number {
    return DOCUMENT_PAGE_HEADER_HEIGHT + 10 + this.getDocumentPageSurfaceHeightForPage(pageId);
  }

  private scrollDocumentToPage(pageId: string, smooth: boolean): void {
    if (!this.isContinuousDocumentViewEnabled() || pageId.length === 0) {
      return;
    }

    const targetOffset = this.getDocumentScrollOffsetForPage(pageId);
    this.documentScrollOffsetY = targetOffset;
    this.documentScroller.scrollTo({
      xOffset: 0,
      yOffset: targetOffset,
      animation: smooth
    });
  }

  private handleDocumentDidScroll(): void {
    this.syncDocumentScrollOffsetFromScroller();
  }

  private syncDocumentScrollOffsetFromScroller(): void {
    const currentOffset = this.documentScroller.currentOffset();
    const numericOffset = Number(currentOffset.yOffset);
    if (Number.isFinite(numericOffset)) {
      this.documentScrollOffsetY = Math.max(0, numericOffset);
    }
  }

  private getViewportCenteredPageId(): string {
    if (this.notebookPageList.length === 0) {
      return '';
    }

    const viewportHeight = this.workspaceViewportHeight > 0 ? this.workspaceViewportHeight : 1;
    const viewportCenterY = this.documentScrollOffsetY + viewportHeight / 2;
    let pageTopOffset = DOCUMENT_PAGE_HORIZONTAL_PADDING;
    let bestPageId = this.notebookPageList[0].id;
    let bestDistance = Number.MAX_VALUE;

    for (const page of this.notebookPageList) {
      const pageSurfaceHeight = this.getDocumentPageSurfaceHeightForPage(page.id);
      const pageContentTop = pageTopOffset + DOCUMENT_PAGE_HEADER_HEIGHT + 10;
      const pageCenterY = pageContentTop + pageSurfaceHeight / 2;
      const distance = Math.abs(viewportCenterY - pageCenterY);
      if (distance < bestDistance) {
        bestDistance = distance;
        bestPageId = page.id;
      }

      pageTopOffset = pageContentTop + pageSurfaceHeight + DOCUMENT_PAGE_GAP;
    }

    return bestPageId;
  }

  private async commitViewportCenteredPage(): Promise<void> {
    if (!this.isContinuousDocumentViewEnabled() || this.isLoading || this.isCreatingPage ||
      this.isDeletingPage || this.isReorderingPages || this.isUpdatingPageTemplate) {
      return;
    }

    this.syncDocumentScrollOffsetFromScroller();
    const targetPageId = this.getViewportCenteredPageId();
    if (targetPageId.length === 0 || targetPageId === this.activePageId) {
      return;
    }

    this.activePageId = targetPageId;
    this.closePageActionMenu();
    await this.loadActivePageCanvas();
  }

  private canDecreaseDocumentZoom(): boolean {
    return this.documentZoomScale > DOCUMENT_ZOOM_MIN_SCALE + 0.001;
  }

  private canIncreaseDocumentZoom(): boolean {
    return this.documentZoomScale < DOCUMENT_ZOOM_MAX_SCALE - 0.001;
  }

  private getDocumentZoomText(): string {
    return `${Math.round(this.documentZoomScale * 100)}%`;
  }

  private getPageCanvasBackgroundColor(pageId: string): string {
    if (pageId === this.activePageId) {
      return this.getActiveCanvasBackgroundColor();
    }

    return '#FFFFFF';
  }

  private getPageCanvasWidth(pageId: string): number {
    const cachedSize = this.pageCanvasRenderSizeMap.get(pageId);
    if (cachedSize !== undefined && cachedSize.width > 0) {
      return cachedSize.width;
    }

    if (pageId === this.activePageId) {
      return this.getActiveCanvasWidth();
    }

    return NotebookPageCanvasEntity.DEFAULT_WIDTH;
  }

  private getPageCanvasHeight(pageId: string): number {
    const cachedSize = this.pageCanvasRenderSizeMap.get(pageId);
    if (cachedSize !== undefined && cachedSize.height > 0) {
      return cachedSize.height;
    }

    if (pageId === this.activePageId) {
      return this.getActiveCanvasHeight();
    }

    return NotebookPageCanvasEntity.DEFAULT_HEIGHT;
  }

  private async handleUndo(): Promise<void> {
    if (this.drawingViewModel === null || this.isCanvasLoading) {
      return;
    }

    const targetPageId: string = this.currentDrawingPageId;
    await this.drawingViewModel.undo();
    this.syncDrawingSnapshot(true, this.drawingViewModel, targetPageId, false);
  }

  private async handleRedo(): Promise<void> {
    if (this.drawingViewModel === null || this.isCanvasLoading) {
      return;
    }

    const targetPageId: string = this.currentDrawingPageId;
    await this.drawingViewModel.redo();
    this.syncDrawingSnapshot(true, this.drawingViewModel, targetPageId, false);
  }

  private async handleClear(): Promise<void> {
    if (this.drawingViewModel === null || this.isCanvasLoading) {
      return;
    }

    const targetPageId: string = this.currentDrawingPageId;
    await this.drawingViewModel.clear();
    this.syncDrawingSnapshot(true, this.drawingViewModel, targetPageId, false);
  }

  private async handleImageInsertRequest(): Promise<void> {
    if (this.isImportingImage || this.isCanvasLoading || this.activePageId.length === 0 ||
      this.drawingViewModel === null) {
      return;
    }

    const hostContext: common.Context | undefined = this.getUIContext().getHostContext() as common.Context | undefined;
    if (hostContext === undefined) {
      return;
    }

    this.closeTransientDropdowns();
    this.isImportingImage = true;
    try {
      const selectOptions = new picker.PhotoSelectOptions();
      selectOptions.MIMEType = picker.PhotoViewMIMETypes.IMAGE_TYPE;
      selectOptions.maxSelectNumber = 1;

      const photoPicker = new picker.PhotoViewPicker(hostContext);
      const selectResult = await photoPicker.select(selectOptions);
      const selectedUri = selectResult.photoUris.length > 0 ? selectResult.photoUris[0] : '';
      if (selectedUri.length === 0) {
        return;
      }

      const importedAsset: ImportedImageAsset = await new ImageAssetDataSource(hostContext).importImage(selectedUri);
      const insertedElement = this.drawingViewModel.insertImageElement(importedAsset, this.getActiveCanvasBounds());
      if (insertedElement === null) {
        this.syncDrawingSnapshot(false, this.drawingViewModel, this.currentDrawingPageId);
        return;
      }

      this.refreshElementLayer();
      this.syncDrawingSnapshot(false, this.drawingViewModel, this.currentDrawingPageId);
      this.requestThumbnailRefresh(true);
    } catch (error) {
      if (this.drawingViewModel !== null) {
        this.drawingViewModel.appendDebugEvent('insertImage', `failed error=${this.stringifyError(error)}`);
        this.syncDrawingSnapshot(false, this.drawingViewModel, this.currentDrawingPageId);
      }
    } finally {
      this.isImportingImage = false;
    }
  }

  private handleWorkspaceToolButtonClick(tool: ToolType): void {
    const isCurrentTool = this.toolSetting.tool === tool;
    this.isCanvasPanModeEnabled = false;
    if (tool === 'text') {
      this.handleWorkspaceToolChange(tool);
      this.closeTransientDropdowns();
      return;
    }

    if (tool === 'shape') {
      this.handleWorkspaceToolChange(tool);
      this.closePageActionMenu();
      this.closeToolDropdown();
      this.closePageTemplateDropdown();
      this.isShapeDropdownVisible = isCurrentTool ? !this.isShapeDropdownVisible : true;
      return;
    }

    if (tool === 'edit') {
      this.handleWorkspaceToolChange(tool);
      this.closeTransientDropdowns();
      return;
    }

    this.handleWorkspaceToolChange(tool);
    this.closePageActionMenu();
    this.closePageTemplateDropdown();
    this.closeShapeDropdown();

    if (isCurrentTool) {
      this.isToolDropdownVisible = !this.isToolDropdownVisible;
      return;
    }

    this.isToolDropdownVisible = true;
  }

  private toggleCanvasPanMode(): void {
    if (this.isCanvasLoading) {
      return;
    }

    const enablePanMode = !this.isCanvasPanModeEnabled;
    this.closeToolDropdown();
    this.closePageActionMenu();
    this.closePageTemplateDropdown();
    this.isCanvasPanModeEnabled = enablePanMode;
    if (!enablePanMode) {
      void this.commitViewportCenteredPage();
    }
  }

  private isWorkspaceToolActive(tool: ToolType): boolean {
    return !this.isCanvasPanModeEnabled && this.toolSetting.tool === tool;
  }

  private handleWorkspaceToolChange(tool: ToolType): void {
    if (this.isWritingTool(tool)) {
      this.lastWritingTool = tool;
    }

    const nextSetting: ToolSetting = {
      tool,
      color: this.toolSetting.color,
      width: this.toolSetting.width,
      opacity: tool === 'eraser' ? 1 : this.toolSetting.opacity
    };

    this.toolSetting = {
      tool: nextSetting.tool,
      color: nextSetting.color,
      width: nextSetting.width,
      opacity: nextSetting.opacity
    };

    if (this.drawingViewModel !== null) {
      this.drawingViewModel.updateToolSetting(nextSetting);
      this.syncDrawingSnapshot(false, this.drawingViewModel, this.currentDrawingPageId);
    }
  }

  private restoreWritingToolAfterOneShotElementInsertion(): void {
    if (this.toolSetting.tool !== 'text' && this.toolSetting.tool !== 'shape') {
      return;
    }

    const nextTool: ToolType = this.isWritingTool(this.lastWritingTool) ? this.lastWritingTool : 'pen';
    const nextSetting: ToolSetting = {
      tool: nextTool,
      color: this.toolSetting.color,
      width: this.toolSetting.width,
      opacity: this.toolSetting.opacity
    };

    this.toolSetting = {
      tool: nextSetting.tool,
      color: nextSetting.color,
      width: nextSetting.width,
      opacity: nextSetting.opacity
    };
    this.isToolDropdownVisible = false;
    this.isShapeDropdownVisible = false;

    if (this.drawingViewModel !== null) {
      this.drawingViewModel.updateToolSetting(nextSetting);
      this.syncDrawingSnapshot(false, this.drawingViewModel, this.currentDrawingPageId);
    }
  }

  private isWritingTool(tool: ToolType): boolean {
    return tool === 'pen' || tool === 'pencil' || tool === 'highlighter';
  }

  private getWorkspaceToolLabel(tool: ToolType): string {
    switch (tool) {
      case 'pen':
        return 'Pen';
      case 'pencil':
        return 'Pencil';
      case 'highlighter':
        return 'Highlight';
      case 'eraser':
        return 'Eraser';
      case 'text':
        return 'Text';
      case 'shape':
        return 'Shape';
      case 'edit':
        return 'Edit';
      default:
        return tool;
    }
  }

  private getShapeLabel(shapeType: ShapeType): string {
    switch (shapeType) {
      case 'rectangle':
        return 'Rectangle';
      case 'circle':
        return 'Circle';
      case 'line':
        return 'Line';
      default:
        return shapeType;
    }
  }

  private closePageActionMenu(): void {
    this.pageActionMenuPageId = '';
  }

  private closeToolDropdown(): void {
    this.isToolDropdownVisible = false;
  }

  private closeShapeDropdown(): void {
    this.isShapeDropdownVisible = false;
  }

  private closePageTemplateDropdown(): void {
    this.isPageTemplateDropdownVisible = false;
  }

  private closeTransientDropdowns(): void {
    this.closePageActionMenu();
    this.closeToolDropdown();
    this.closeShapeDropdown();
    this.closePageTemplateDropdown();
  }

  private togglePageActionMenu(pageId: string): void {
    if (this.isLoading || this.isCreatingPage || this.isDeletingPage || this.isReorderingPages ||
      this.isUpdatingPageTemplate) {
      return;
    }

    if (this.pageActionMenuPageId === pageId) {
      this.pageActionMenuPageId = '';
      return;
    }

    this.pageActionMenuPageId = pageId;
  }

  private togglePageTemplateDropdown(): void {
    if (this.isLoading || this.isCreatingPage || this.isDeletingPage || this.isReorderingPages ||
      this.isUpdatingPageTemplate || this.isCanvasLoading || this.activePageId.length === 0) {
      return;
    }

    this.closeToolDropdown();
    this.closeShapeDropdown();
    this.closePageActionMenu();
    this.isPageTemplateDropdownVisible = !this.isPageTemplateDropdownVisible;
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

  private canDragReorderPages(): boolean {
    return !this.isLoading && !this.isCreatingPage && !this.isDeletingPage && !this.isReorderingPages &&
      !this.isUpdatingPageTemplate && this.notebookId.length > 0 && this.notebookPageList.length > 1;
  }

  private moveNotebookPageByOffset(page: NotebookPage, offset: number): void {
    const targetIndex: number = page.order + offset;
    this.closePageActionMenu();
    this.moveNotebookPageByIndex(page.order, targetIndex);
  }

  private handlePageListItemMove(fromIndex: number, toIndex: number): void {
    this.moveNotebookPageByIndex(fromIndex, toIndex);
  }

  private moveNotebookPageByIndex(fromIndex: number, toIndex: number): void {
    if (!this.canDragReorderPages() || fromIndex === toIndex) {
      return;
    }

    if (fromIndex < 0 || fromIndex >= this.notebookPageList.length ||
      toIndex < 0 || toIndex >= this.notebookPageList.length) {
      return;
    }

    const rollbackPageList: NotebookPage[] = this.cloneNotebookPageList(this.notebookPageList);
    const rollbackActivePageId: string = this.activePageId;
    if (!this.applyNotebookPageMoveLocally(fromIndex, toIndex)) {
      return;
    }

    void this.persistNotebookPageMove(fromIndex, toIndex, rollbackPageList, rollbackActivePageId);
  }

  private async persistNotebookPageMove(
    fromIndex: number,
    toIndex: number,
    rollbackPageList: NotebookPage[],
    rollbackActivePageId: string
  ): Promise<void> {
    if (fromIndex === toIndex || this.notebookId.length === 0) {
      return;
    }

    this.isReorderingPages = true;
    try {
      const hasReordered: boolean = await this.ensureViewModel().reorderNotebookPages(this.notebookId, fromIndex, toIndex);
      if (!hasReordered) {
        this.restoreNotebookPageListAfterFailedMove(rollbackPageList, rollbackActivePageId);
        return;
      }

      const cachedNotebook: Notebook | null = this.ensureViewModel().getCachedNotebook();
      if (cachedNotebook !== null) {
        this.notebookTitle = cachedNotebook.title;
      }

      this.notebookPageList = this.ensureViewModel().getCachedNotebookPages();
      this.syncActivePageId(this.activePageId);
    } catch (_error) {
      this.restoreNotebookPageListAfterFailedMove(rollbackPageList, rollbackActivePageId);
    } finally {
      this.isReorderingPages = false;
    }
  }

  private applyNotebookPageMoveLocally(fromIndex: number, toIndex: number): boolean {
    if (fromIndex === toIndex) {
      return false;
    }

    const reorderedNotebookPageList: NotebookPage[] = this.buildReorderedNotebookPageList(
      this.notebookPageList,
      fromIndex,
      toIndex
    );
    if (reorderedNotebookPageList.length === 0) {
      return false;
    }

    this.notebookPageList = reorderedNotebookPageList;
    this.syncActivePageId(this.activePageId);
    return true;
  }

  private buildReorderedNotebookPageList(
    notebookPageList: NotebookPage[],
    fromIndex: number,
    toIndex: number
  ): NotebookPage[] {
    if (fromIndex < 0 || fromIndex >= notebookPageList.length || toIndex < 0 || notebookPageList.length === 0) {
      return [];
    }

    const normalizedToIndex: number = this.normalizePageIndexForLength(toIndex, notebookPageList.length);
    const reorderedNotebookPageList: NotebookPage[] = this.cloneNotebookPageList(notebookPageList);
    const movedNotebookPageList: NotebookPage[] = reorderedNotebookPageList.splice(fromIndex, 1);
    if (movedNotebookPageList.length === 0) {
      return [];
    }

    reorderedNotebookPageList.splice(normalizedToIndex, 0, movedNotebookPageList[0]);
    return reorderedNotebookPageList.map((notebookPage: NotebookPage, index: number): NotebookPage => {
      return {
        id: notebookPage.id,
        notebookId: notebookPage.notebookId,
        order: index,
        createdAt: notebookPage.createdAt,
        updatedAt: notebookPage.updatedAt,
        templateType: this.resolvePageTemplateType(notebookPage.templateType)
      };
    });
  }

  private normalizePageIndexForLength(index: number, pageCount: number): number {
    if (pageCount === 0) {
      return -1;
    }

    if (index < 0) {
      return 0;
    }

    return Math.min(index, pageCount - 1);
  }

  private restoreNotebookPageListAfterFailedMove(
    rollbackPageList: NotebookPage[],
    rollbackActivePageId: string
  ): void {
    if (rollbackPageList.length === 0) {
      return;
    }

    this.notebookPageList = this.cloneNotebookPageList(rollbackPageList);
    this.activePageId = rollbackActivePageId;
    this.syncActivePageId(rollbackActivePageId);
  }

  private getActivePage(): NotebookPage | null {
    for (const notebookPage of this.notebookPageList) {
      if (notebookPage.id === this.activePageId) {
        return notebookPage;
      }
    }
    return null;
  }

  private getActivePageTemplateType(): NotebookPageTemplateType {
    const activePage: NotebookPage | null = this.getActivePage();
    return activePage === null ? NotebookPageTemplateType.BLANK : this.resolvePageTemplateType(activePage.templateType);
  }

  private isActivePageTemplate(templateType: NotebookPageTemplateType): boolean {
    return this.getActivePageTemplateType() === templateType;
  }

  private getPageTemplateLabel(templateType: NotebookPageTemplateType): string {
    switch (templateType) {
      case NotebookPageTemplateType.LINED:
        return '横线';
      case NotebookPageTemplateType.GRID:
        return '方格';
      case NotebookPageTemplateType.DOTTED:
        return '点阵';
      case NotebookPageTemplateType.BLANK:
      default:
        return '空白';
    }
  }

  private async updateActivePageTemplate(templateType: NotebookPageTemplateType): Promise<void> {
    if (this.isUpdatingPageTemplate || this.isLoading || this.isCreatingPage || this.isDeletingPage ||
      this.isReorderingPages || this.isCanvasLoading || this.notebookId.length === 0 || this.activePageId.length === 0) {
      return;
    }

    const activePage: NotebookPage | null = this.getActivePage();
    if (activePage === null) {
      return;
    }

    if (this.resolvePageTemplateType(activePage.templateType) === templateType) {
      this.closePageTemplateDropdown();
      return;
    }

    const pageId: string = activePage.id;
    const rollbackPageList: NotebookPage[] = this.cloneNotebookPageList(this.notebookPageList);
    const rollbackActivePageId: string = this.activePageId;

    this.isUpdatingPageTemplate = true;
    this.closeToolDropdown();
    this.closePageActionMenu();

    if (!this.applyNotebookPageTemplateLocally(pageId, templateType)) {
      this.isUpdatingPageTemplate = false;
      return;
    }

    this.canvasVersion += 1;
    this.requestThumbnailRefresh(true);
    this.closePageTemplateDropdown();

    try {
      const updatedNotebookPage: NotebookPage | null = await this.ensureViewModel().updateNotebookPageTemplate(
        this.notebookId,
        pageId,
        templateType
      );

      if (updatedNotebookPage === null) {
        this.restoreNotebookPageListAfterFailedTemplateUpdate(rollbackPageList, rollbackActivePageId);
        return;
      }

      const cachedNotebook: Notebook | null = this.ensureViewModel().getCachedNotebook();
      if (cachedNotebook !== null) {
        this.notebookTitle = cachedNotebook.title;
      }

      this.notebookPageList = this.ensureViewModel().getCachedNotebookPages();
      this.syncActivePageId(pageId);
      this.canvasVersion += 1;
      this.requestThumbnailRefresh(true);
    } catch (_error) {
      this.restoreNotebookPageListAfterFailedTemplateUpdate(rollbackPageList, rollbackActivePageId);
    } finally {
      this.isUpdatingPageTemplate = false;
    }
  }

  private applyNotebookPageTemplateLocally(
    pageId: string,
    templateType: NotebookPageTemplateType
  ): boolean {
    let hasUpdated: boolean = false;
    const currentTime: number = Date.now();
    const nextNotebookPageList: NotebookPage[] = this.notebookPageList.map((page: NotebookPage): NotebookPage => {
      if (page.id !== pageId) {
        return {
          id: page.id,
          notebookId: page.notebookId,
          order: page.order,
          createdAt: page.createdAt,
          updatedAt: page.updatedAt,
          templateType: this.resolvePageTemplateType(page.templateType)
        };
      }

      hasUpdated = true;
      return {
        id: page.id,
        notebookId: page.notebookId,
        order: page.order,
        createdAt: page.createdAt,
        updatedAt: currentTime,
        templateType: templateType
      };
    });

    if (!hasUpdated) {
      return false;
    }

    this.notebookPageList = nextNotebookPageList;
    this.syncActivePageId(pageId);
    return true;
  }

  private restoreNotebookPageListAfterFailedTemplateUpdate(
    rollbackPageList: NotebookPage[],
    rollbackActivePageId: string
  ): void {
    this.notebookPageList = this.cloneNotebookPageList(rollbackPageList);
    this.activePageId = rollbackActivePageId;
    this.syncActivePageId(rollbackActivePageId);
    this.canvasVersion += 1;
    this.requestThumbnailRefresh(true);
  }

  private getPageRenderKey(page: NotebookPage): string {
    return `${page.id}_${this.resolvePageTemplateType(page.templateType)}`;
  }

  private getPageOrderText(pageId: string, fallbackIndex: number): string {
    const pageIndex: number = this.getPageIndexById(pageId);
    if (pageIndex >= 0) {
      return `${pageIndex + 1}`;
    }

    if (fallbackIndex >= 0) {
      return `${fallbackIndex + 1}`;
    }

    return '1';
  }

  private getPageIndexById(pageId: string): number {
    for (let index: number = 0; index < this.notebookPageList.length; index += 1) {
      if (this.notebookPageList[index].id === pageId) {
        return index;
      }
    }

    return -1;
  }

  private cloneNotebookPageList(notebookPageList: NotebookPage[]): NotebookPage[] {
    return notebookPageList.map((page: NotebookPage): NotebookPage => {
      return {
        id: page.id,
        notebookId: page.notebookId,
        order: page.order,
        createdAt: page.createdAt,
        updatedAt: page.updatedAt,
        templateType: this.resolvePageTemplateType(page.templateType)
      };
    });
  }

  private resolvePageTemplateType(templateType?: NotebookPageTemplateType): NotebookPageTemplateType {
    switch (templateType) {
      case NotebookPageTemplateType.LINED:
        return NotebookPageTemplateType.LINED;
      case NotebookPageTemplateType.GRID:
        return NotebookPageTemplateType.GRID;
      case NotebookPageTemplateType.DOTTED:
        return NotebookPageTemplateType.DOTTED;
      case NotebookPageTemplateType.BLANK:
      default:
        return NotebookPageTemplateType.BLANK;
    }
  }

  private getPageThumbnailBackgroundColor(page: NotebookPage): ResourceColor {
    if (page.id === this.activePageId) {
      return $r('app.color.editor_thumbnail_active');
    }

    return $r('app.color.editor_thumbnail_background');
  }

  private getPageThumbnailBorderColor(page: NotebookPage): ResourceColor {
    if (page.id === this.activePageId) {
      return $r('app.color.editor_accent');
    }

    return $r('app.color.editor_sidebar_border');
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

  private getActiveCanvasWidth(): number {
    if (this.activePageCanvas === null) {
      return NotebookPageCanvasEntity.DEFAULT_WIDTH;
    }

    return this.normalizeCanvasRenderSize(this.activePageCanvas.width, this.activePageCanvas.height).width;
  }

  private getActiveCanvasHeight(): number {
    if (this.activePageCanvas === null) {
      return NotebookPageCanvasEntity.DEFAULT_HEIGHT;
    }

    return this.normalizeCanvasRenderSize(this.activePageCanvas.width, this.activePageCanvas.height).height;
  }

  private normalizeCanvasRenderSize(width: number, height: number): PageCanvasRenderSize {
    const normalizedWidth = NotebookPageCanvasEntity.normalizeDimension(
      width,
      NotebookPageCanvasEntity.DEFAULT_WIDTH
    );
    const normalizedHeight = NotebookPageCanvasEntity.normalizeDimension(
      height,
      NotebookPageCanvasEntity.DEFAULT_HEIGHT
    );

    if (normalizedWidth >= normalizedHeight) {
      return {
        width: normalizedWidth,
        height: normalizedHeight
      };
    }

    return {
      width: normalizedHeight,
      height: normalizedWidth
    };
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

  private resolveRouteParams(): RouterParams {
    try {
      return router.getParams() as RouterParams;
    } catch (_error) {
      return {};
    }
  }

  private stringifyError(error: Object): string {
    if (error instanceof Error) {
      return error.message.length > 0 ? error.message : error.name;
    }

    const errorRecord = error as Record<string, Object>;
    const message = typeof errorRecord.message === 'string' ? errorRecord.message : '';
    if (message.length > 0) {
      return message;
    }

    try {
      const serialized = JSON.stringify(error);
      if (serialized.length > 0 && serialized !== '{}') {
        return serialized;
      }
    } catch (_jsonError) {
    }

    return `${error}`;
  }
}
