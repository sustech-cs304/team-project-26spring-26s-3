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
import { CanvasBoard, CanvasBoardContentChangeKind, CanvasInputMode } from '../components/CanvasBoard';
import { PageThumbnailCanvas } from '../components/PageThumbnailCanvas';
import {
  createEmptyPageThumbnailRenderSnapshot,
  PageThumbnailRenderSnapshot
} from '../controllers/PageThumbnailRenderer';
import { ToolPropertyPanel } from '../components/ToolPropertyPanel';
import { NotebookExportDialog } from '../../notebook/components/NotebookExportDialog';
import {
  buildNotebookExportSuffixChoice,
  createNotebookExportBaseName,
  stripNotebookExportExtension
} from '../../notebook/models/NotebookExportOptions';
import { DrawingEditorViewModel } from '../viewmodels/DrawingEditorViewModel';
import { EditorDebugSnapshot } from '../viewmodels/EditorDebugSnapshot';
import { EditorSessionRegistry } from '../viewmodels/EditorSessionRegistry';
import { EditorViewModel } from '../viewmodels/EditorViewModel';
import { PageThumbnailStore } from '../viewmodels/PageThumbnailStore';

interface PageCanvasRenderSize {
  width: number;
  height: number;
}

interface DocumentTouchPairMetrics {
  windowCenterX: number;
  windowCenterY: number;
  distance: number;
}

interface DocumentTouchAnchor {
  pageId: string;
  pageX: number;
  pageY: number;
}

interface PaperSizeTemplateOption {
  id: string;
  label: string;
  description: string;
  width: number;
  height: number;
}

const SIDEBAR_EXPANDED_PADDING = 16;
const THUMBNAIL_RENDER_INTERVAL_MS = 320;
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
const DOCUMENT_PAGE_EDITABLE_WINDOW_PADDING_FACTOR = 1.25;
const DOCUMENT_ZOOM_MIN_SCALE = 0.6;
const DOCUMENT_ZOOM_MAX_SCALE = 2.8;
const DOCUMENT_ZOOM_COMMIT_EPSILON = 0.015;
const DOCUMENT_GESTURE_PREVIEW_INTERVAL_MS = 16;
const DOCUMENT_NAVIGATION_FOCUS_INTERVAL_MS = 48;
const ACTIVE_PAGE_CANVAS_LOAD_DELAY_MS = 360;
const DOCUMENT_SINGLE_FINGER_PAN_THRESHOLD_SCREEN_PX = 4;
const WORKSPACE_TOOL_OPTIONS: ToolType[] = ['pen', 'pencil', 'highlighter', 'eraser', 'lasso', 'text', 'shape', 'edit'];
const SHAPE_TOOL_OPTIONS: ShapeType[] = ['rectangle', 'circle', 'line'];
const PAGE_TEMPLATE_OPTIONS: NotebookPageTemplateType[] = [
  NotebookPageTemplateType.BLANK,
  NotebookPageTemplateType.LINED,
  NotebookPageTemplateType.GRID,
  NotebookPageTemplateType.DOTTED
];
const PAPER_SIZE_TEMPLATE_OPTIONS: PaperSizeTemplateOption[] = [
  {
    id: 'default',
    label: '默认宽屏',
    description: '2200 x 1600',
    width: NotebookPageCanvasEntity.DEFAULT_WIDTH,
    height: NotebookPageCanvasEntity.DEFAULT_HEIGHT
  },
  {
    id: 'a4',
    label: 'A4 竖版',
    description: '2200 x 3112',
    width: 2200,
    height: 3112
  },
  {
    id: 'a4_landscape',
    label: 'A4 横版',
    description: '2200 x 1556',
    width: 2200,
    height: 1556
  },
  {
    id: 'a5',
    label: 'A5 竖版',
    description: '1800 x 2546',
    width: 1800,
    height: 2546
  },
  {
    id: 'letter',
    label: 'Letter',
    description: '2200 x 2847',
    width: 2200,
    height: 2847
  },
  {
    id: 'square',
    label: '方形',
    description: '2000 x 2000',
    width: 2000,
    height: 2000
  }
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
  @State private isExportDialogVisible: boolean = false;
  @State private isPickingExportPath: boolean = false;
  @State private draftExportFileName: string = '';
  @State private draftExportPath: string = '';
  @State private draftExportFormat: string = 'pdf';
  @State private hasMissingNotebookId: boolean = false;
  @State private isNotebookMissing: boolean = false;
  @State private toolSetting: ToolSetting = this.buildDefaultToolSetting();
  @State private canvasInputMode: CanvasInputMode = 'stylus';
  @State private focusedPageId: string = '';
  private lastWritingTool: ToolType = 'pen';
  @State private selectedShapeType: ShapeType = 'rectangle';
  @State private editorSnapshot: EditorDebugSnapshot = this.buildEmptySnapshot('');
  @State private canvasVersion: number = 0;
  @State private elementLayerRefreshVersion: number = 0;
  @State private thumbnailRenderTick: number = 0;
  @State private isPagePreviewCollapsed: boolean = false;
  @State private isToolDropdownVisible: boolean = false;
  @State private isShapeDropdownVisible: boolean = false;
  @State private isPageTemplateDropdownVisible: boolean = false;
  private isDocumentTouchNavigationActive: boolean = false;
  @State private workspaceViewportWidth: number = 0;
  @State private workspaceViewportHeight: number = 0;
  @State private documentZoomScale: number = 1;
  @State private documentHorizontalOffset: number = 0;
  @State private documentScrollOffsetY: number = 0;
  @State private documentGesturePreviewScale: number = 1;
  @State private documentGesturePreviewOffsetX: number = 0;
  @State private documentGesturePreviewOffsetY: number = 0;
  @State private documentViewportRefreshVersion: number = 0;
  @State private hasWorkspaceViewport: boolean = false;
  @State private retainedEditablePageVersion: number = 0;
  private workspaceViewportWindowX: number = 0;
  private workspaceViewportWindowY: number = 0;
  private readonly pageCanvasRenderSizeMap: Map<string, PageCanvasRenderSize> = new Map<string, PageCanvasRenderSize>();
  private readonly pageCanvasMetadataMap: Map<string, NotebookPageCanvas> = new Map<string, NotebookPageCanvas>();
  private readonly pageCanvasByPageId: Map<string, NotebookPageCanvas> = new Map<string, NotebookPageCanvas>();
  private readonly knownPageCanvasMetadataPageIds: Set<string> = new Set<string>();
  private readonly retainedEditablePageIds: Set<string> = new Set<string>();
  private readonly canvasVersionByPageId: Map<string, number> = new Map<string, number>();
  private thumbnailRenderTimerId: number = -1;
  private activePageCanvasLoadTimerId: number = -1;
  private lastThumbnailRenderTime: number = 0;
  private lastNavigationFocusUpdateTime: number = 0;
  private documentGestureStartZoomScale: number = 1;
  private documentGestureStartHorizontalOffset: number = 0;
  private documentGestureStartScrollOffsetY: number = 0;
  private documentGestureTargetZoomScale: number = 1;
  private documentGestureTargetHorizontalOffset: number = 0;
  private documentGestureTargetScrollOffsetY: number = 0;
  private documentGestureAnchorPageId: string = '';
  private documentGestureAnchorPageUnitX: number = 0.5;
  private documentGestureAnchorPageUnitY: number = 0.5;
  private lastDocumentGesturePreviewTime: number = 0;
  private isDocumentSingleFingerPanPending: boolean = false;
  private documentSingleFingerPanTouchId: number = -1;
  private documentSingleFingerPanStartWindowX: number = 0;
  private documentSingleFingerPanStartWindowY: number = 0;
  private isDocumentPanGestureActive: boolean = false;
  private documentPanStartWindowX: number = 0;
  private documentPanStartWindowY: number = 0;
  private isDocumentViewportGestureActive: boolean = false;
  private documentViewportGestureStartDistance: number = 1;
  private documentViewportGestureStartWorkspaceX: number = 0;
  private documentViewportGestureStartWorkspaceY: number = 0;
  private lastDocumentTouchSignature: string = '';
  private pendingDocumentViewportPageId: string = '';
  private editorViewModel?: EditorViewModel;
  private thumbnailStore?: PageThumbnailStore;
  private drawingViewModel: DrawingEditorViewModel | null = null;
  private currentDrawingPageId: string = '';

  aboutToAppear(): void {
    void this.loadEditorState();
  }

  aboutToDisappear(): void {
    this.clearScheduledThumbnailRender();
    this.clearScheduledActivePageCanvasLoad();
    void this.flushActiveDrawingSession();
    EditorSessionRegistry.clearAll();
    this.drawingViewModel = null;
    this.currentDrawingPageId = '';
    this.focusedPageId = '';
    this.isToolDropdownVisible = false;
    this.isShapeDropdownVisible = false;
    this.isPageTemplateDropdownVisible = false;
    this.isDocumentTouchNavigationActive = false;
    this.resetPendingDocumentSingleFingerPan();
    this.isDocumentViewportGestureActive = false;
    this.documentViewportGestureStartDistance = 1;
    this.documentViewportGestureStartWorkspaceX = 0;
    this.documentViewportGestureStartWorkspaceY = 0;
    this.endDocumentPanGesture(false);
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

      if (this.isExportDialogVisible) {
        this.buildNotebookExportDialog();
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

        Button() {
          Image($r('app.media.export_note'))
            .width(18)
            .height(18)
        }
        .width(34)
        .height(34)
        .padding(0)
        .backgroundColor($r('app.color.surface_background'))
        .borderRadius(12)
        .border({
          width: 1,
          color: $r('app.color.editor_toolbar_border')
        })
        .onClick(() => {
          this.openNotebookExportDialog();
        })
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
        PageThumbnailCanvas({
          snapshot: this.buildPageThumbnailSnapshot(page),
          renderTick: this.thumbnailRenderTick,
          onNeedSnapshot: (pageId: string): void => {
            this.requestThumbnailSnapshot(pageId);
          }
        })
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.surface_background'))
        .borderRadius(18)
        .border({
          width: 1,
          color: this.isPageVisuallySelected(page.id) ? $r('app.color.editor_accent') :
            $r('app.color.editor_paper_border')
        })

        Text(this.getPageOrderText(page.id, pageIndex))
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.isPageVisuallySelected(page.id) ? '#FFFFFF' : $r('app.color.primary_text'))
          .width(24)
          .height(24)
          .textAlign(TextAlign.Center)
          .backgroundColor(this.isPageVisuallySelected(page.id) ? $r('app.color.editor_accent') : '#FFFFFF')
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
      width: 2,
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

              this.buildInputModeToggleButton()
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
      } else if (!this.isWorkspaceViewportReady()) {
        this.buildWorkspaceLoadingState()
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
    .onAreaChange((_oldValue: Area, newValue: Area) => {
      this.handleWorkspaceAreaChange(newValue);
    })
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
          this.closeTransientDropdowns();
          this.resetDocumentZoomScale();
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
      Row({ space: 8 }) {
        Column({ space: 7 }) {
          this.buildTemplateSectionTitle('线条模板')

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

        Column({ space: 7 }) {
          this.buildTemplateSectionTitle('纸张大小')

          ForEach(PAPER_SIZE_TEMPLATE_OPTIONS, (option: PaperSizeTemplateOption) => {
            this.buildPaperSizeTemplateOption(option)
          }, (option: PaperSizeTemplateOption): string => option.id)
        }
        .width(232)
        .padding(7)
        .backgroundColor('#F8FAFC')
        .borderRadius(12)
        .border({
          width: 1,
          color: '#E2E8F0'
        })
      }
      .alignItems(VerticalAlign.Top)
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
  private buildTemplateSectionTitle(title: string): void {
    Text(title)
      .fontSize(14)
      .fontWeight(FontWeight.Medium)
      .fontColor('#111827')
      .width('100%')
  }

  @Builder
  private buildPaperSurface(): void {
    Stack({ alignContent: Alignment.TopStart }) {
      Column({ space: DOCUMENT_PAGE_GAP }) {
        ForEach(this.notebookPageList, (page: NotebookPage, index: number) => {
          this.buildDocumentPageSurface(page, index);
        }, (page: NotebookPage): string => this.getDocumentPageRenderKey(page))
      }
      .width(this.getDocumentContentWidth())
      .height(this.getDocumentContentHeight())
      .padding({
        left: DOCUMENT_PAGE_HORIZONTAL_PADDING,
        right: DOCUMENT_PAGE_HORIZONTAL_PADDING,
        top: DOCUMENT_PAGE_HORIZONTAL_PADDING,
        bottom: DOCUMENT_PAGE_HORIZONTAL_PADDING
      })
      .alignItems(HorizontalAlign.Center)
      .offset({
        x: this.getDocumentVisualOffsetX(),
        y: this.getDocumentContentOffsetY()
      })
      .scale({
        x: this.getDocumentVisualScale(),
        y: this.getDocumentVisualScale(),
        centerX: 0,
        centerY: 0
      })

    }
    .width('100%')
    .layoutWeight(1)
    .height('100%')
    .backgroundColor($r('app.color.editor_workspace_background'))
    .borderRadius(30)
    .clip(true)
    .border({
      width: 1,
      color: $r('app.color.editor_paper_border')
    })
    .onTouch((event: TouchEvent) => {
      this.handleDocumentSurfaceTouch(event);
    })
  }

  @Builder
  private buildDocumentPageSurface(page: NotebookPage, pageIndex: number): void {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        Text(this.getPageOrderText(page.id, pageIndex))
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.isPageVisuallySelected(page.id) ? '#FFFFFF' : '#475569')
          .padding({
            left: 10,
            right: 10,
            top: 5,
            bottom: 5
          })
          .backgroundColor(this.isPageVisuallySelected(page.id) ? $r('app.color.editor_accent') : '#FFFFFF')
          .borderRadius(999)

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
          .opacity(this.isPageVisuallySelected(page.id) ? 1 : 0)

        Blank()
          .layoutWeight(1)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .height(DOCUMENT_PAGE_HEADER_HEIGHT)

      Stack() {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(this.getPageFrameBackgroundColor(page.id))
          .borderRadius(24)

        if (this.shouldRenderDocumentPagePreviewBacking(page.id)) {
          PageThumbnailCanvas({
            snapshot: this.buildPageThumbnailSnapshot(page),
            renderTick: this.thumbnailRenderTick,
            onNeedSnapshot: (pageId: string): void => {
              this.requestThumbnailSnapshot(pageId);
            }
          })
            .width('100%')
            .height('100%')
        }

        if (this.shouldRenderEditableDocumentPage(page.id)) {
          CanvasBoard({
            pageId: page.id,
            canvasVersion: this.getCanvasVersionForPage(page.id),
            viewportRefreshVersion: this.documentViewportRefreshVersion,
            elementVersion: this.elementLayerRefreshVersion,
            selectedShapeType: this.selectedShapeType,
            templateType: this.resolvePageTemplateType(page.templateType),
            paperBackgroundColor: this.getPageCanvasBackgroundColor(page.id),
            backgroundImageUri: this.getPageCanvasBackgroundImageUri(page.id),
            pageWidth: this.getPageCanvasWidth(page.id),
            pageHeight: this.getPageCanvasHeight(page.id),
            toolSetting: this.toolSetting,
            inputMode: this.canvasInputMode,
            isActivePage: this.isDocumentPageActive(page.id),
            autoLoadSession: this.shouldAutoLoadDocumentPageSession(page.id),
            editorSnapshot: $editorSnapshot,
            onPageInteractionStart: (pageId: string): void => {
              this.activateDocumentPageForInteraction(pageId);
            },
            onDocumentTouch: (event: TouchEvent): void => {
              this.handleDocumentSurfaceTouch(event);
            },
            onContentChanged: (immediate: boolean, kind: CanvasBoardContentChangeKind): void => {
              if (kind === 'element') {
                this.refreshElementLayer();
              }
              this.restoreWritingToolAfterOneShotElementInsertion();
              if (immediate || kind === 'stroke') {
                this.captureActiveSessionForThumbnail();
                this.requestThumbnailRender(immediate);
              }
            },
            onCanvasMetricsChanged: (width: number, height: number): void => {
              this.updatePageCanvasRenderSize(page.id, width, height);
            }
          })
            .width('100%')
            .height('100%')
        } else if (this.shouldRenderDocumentPagePreview(page.id)) {
          PageThumbnailCanvas({
            snapshot: this.buildPageThumbnailSnapshot(page),
            renderTick: this.thumbnailRenderTick,
            onNeedSnapshot: (pageId: string): void => {
              this.requestThumbnailSnapshot(pageId);
            }
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
          .hitTestBehavior(HitTestMode.None)
        }
      }
      .width(this.getDocumentPageSurfaceWidth())
      .height(this.getDocumentPageSurfaceHeightForPage(page.id))
      .borderRadius(24)
      .clip(true)
      .border({
        width: 2,
        color: this.isPageVisuallySelected(page.id) ? $r('app.color.editor_accent') : $r('app.color.editor_paper_border')
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
  private buildInputModeToggleButton(): void {
    Button(this.getInputModeButtonLabel())
    .height(32)
    .padding({
      left: 10,
      right: 10
    })
    .fontSize(12)
    .backgroundColor(this.canvasInputMode === 'touch' ? '#0F172A' : '#FFFFFF')
    .fontColor(this.canvasInputMode === 'touch' ? '#FFFFFF' : '#475569')
    .borderRadius(10)
    .border({
      width: 1,
      color: this.canvasInputMode === 'touch' ? '#0F172A' : '#CBD5E1'
    })
    .enabled(!this.isCanvasLoading)
    .onClick(() => {
      this.toggleCanvasInputMode();
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
  private buildPaperSizeTemplateOption(option: PaperSizeTemplateOption): void {
    Button() {
      Row({ space: 8 }) {
        this.buildPaperSizeTemplateGlyph(option, this.isActivePaperSizeTemplate(option))

        Column({ space: 2 }) {
          Text(option.label)
            .fontSize(13)
            .fontWeight(this.isActivePaperSizeTemplate(option) ? FontWeight.Medium : FontWeight.Regular)
            .fontColor(this.isActivePaperSizeTemplate(option) ? '#FFFFFF' : '#334155')
            .width('100%')
            .textAlign(TextAlign.Start)

          Text(option.description)
            .fontSize(11)
            .fontColor(this.isActivePaperSizeTemplate(option) ? '#E2E8F0' : '#64748B')
            .width('100%')
            .textAlign(TextAlign.Start)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Text(this.isActivePaperSizeTemplate(option) ? '✓' : '')
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
    .height(46)
    .padding({
      left: 8,
      right: 8
    })
    .backgroundColor(this.isActivePaperSizeTemplate(option) ? '#0F172A' : '#FFFFFF')
    .borderRadius(10)
    .border({
      width: 1,
      color: this.isActivePaperSizeTemplate(option) ? '#0F172A' : '#CBD5E1'
    })
    .enabled(!this.isUpdatingPageTemplate && !this.isCanvasLoading)
    .onClick(() => {
      void this.updateActivePageCanvasSize(option);
    })
  }

  @Builder
  private buildPaperSizeTemplateGlyph(option: PaperSizeTemplateOption, isSelected: boolean): void {
    Stack({ alignContent: Alignment.Center }) {
      Column() {}
        .width(this.getPaperSizeGlyphWidth(option))
        .height(this.getPaperSizeGlyphHeight(option))
        .backgroundColor(isSelected ? '#FFFFFF' : '#F8FAFC')
        .borderRadius(4)
        .border({
          width: 1,
          color: isSelected ? '#E2E8F0' : '#CBD5E1'
        })
    }
    .width(30)
    .height(24)
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
  private buildNotebookExportDialog(): void {
    Column() {
      NotebookExportDialog({
        fileName: $draftExportFileName,
        outputPath: $draftExportPath,
        selectedFormat: $draftExportFormat,
        notebookTitle: this.notebookTitle,
        isChoosingPath: this.isPickingExportPath,
        onCancel: (): void => {
          this.closeNotebookExportDialog();
        },
        onChoosePath: (): void => {
          void this.selectNotebookExportPath();
        },
        onConfirm: (): void => {
          this.confirmNotebookExportDialog();
        }
      })
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
    .backgroundColor($r('app.color.overlay_mask'))
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

  private ensureThumbnailStore(): PageThumbnailStore {
    if (this.thumbnailStore === undefined) {
      const hostContext: common.Context | undefined = this.getUIContext().getHostContext() as common.Context | undefined;
      if (hostContext === undefined) {
        throw new Error('Host context is unavailable.');
      }
      this.thumbnailStore = new PageThumbnailStore(hostContext);
    }

    return this.thumbnailStore as PageThumbnailStore;
  }

  private buildPageThumbnailSnapshot(page: NotebookPage): PageThumbnailRenderSnapshot {
    try {
      return this.ensureThumbnailStore().buildSnapshot({
        pageId: page.id,
        templateType: this.resolvePageTemplateType(page.templateType),
        paperBackgroundColor: this.getPageCanvasBackgroundColor(page.id),
        backgroundImageUri: this.getPageCanvasBackgroundImageUri(page.id),
        canvasWidth: this.getPageCanvasWidth(page.id),
        canvasHeight: this.getPageCanvasHeight(page.id),
        activeSession: page.id === this.currentDrawingPageId ? this.drawingViewModel : null
      });
    } catch (_error) {
      return createEmptyPageThumbnailRenderSnapshot(page.id);
    }
  }

  private requestThumbnailSnapshot(pageId: string): void {
    void this.ensureThumbnailSnapshot(pageId);
  }

  private async ensureThumbnailSnapshot(pageId: string): Promise<void> {
    if (pageId.length === 0) {
      return;
    }

    try {
      const hasLoaded = await this.ensureThumbnailStore().ensurePageContent(pageId);
      if (hasLoaded) {
        this.requestThumbnailRender(true);
      }
    } catch (_error) {
    }
  }

  private captureActiveSessionForThumbnail(): void {
    if (this.currentDrawingPageId.length === 0 || this.drawingViewModel === null) {
      return;
    }

    this.captureThumbnailSession(this.currentDrawingPageId, this.drawingViewModel);
  }

  private captureThumbnailSession(pageId: string, viewModel: DrawingEditorViewModel | null): void {
    try {
      this.ensureThumbnailStore().captureSession(pageId, viewModel);
    } catch (_error) {
    }
  }

  private retainThumbnailPages(): void {
    try {
      this.ensureThumbnailStore().retainPages(this.notebookPageList.map((page: NotebookPage): string => page.id));
    } catch (_error) {
    }
    this.prunePageCachesForCurrentPageList();
  }

  private prunePageCachesForCurrentPageList(): void {
    const pageIdSet: Set<string> = new Set<string>(this.notebookPageList.map((page: NotebookPage): string => page.id));
    for (const pageId of Array.from(this.pageCanvasByPageId.keys())) {
      if (!pageIdSet.has(pageId)) {
        this.pageCanvasByPageId.delete(pageId);
      }
    }
    for (const pageId of Array.from(this.pageCanvasMetadataMap.keys())) {
      if (!pageIdSet.has(pageId)) {
        this.pageCanvasMetadataMap.delete(pageId);
      }
    }
    for (const pageId of Array.from(this.pageCanvasRenderSizeMap.keys())) {
      if (!pageIdSet.has(pageId)) {
        this.pageCanvasRenderSizeMap.delete(pageId);
      }
    }
    for (const pageId of Array.from(this.canvasVersionByPageId.keys())) {
      if (!pageIdSet.has(pageId)) {
        this.canvasVersionByPageId.delete(pageId);
      }
    }
    for (const pageId of Array.from(this.knownPageCanvasMetadataPageIds.keys())) {
      if (!pageIdSet.has(pageId)) {
        this.knownPageCanvasMetadataPageIds.delete(pageId);
      }
    }

    let hasPrunedRetainedPage = false;
    for (const pageId of Array.from(this.retainedEditablePageIds.keys())) {
      if (!pageIdSet.has(pageId)) {
        this.retainedEditablePageIds.delete(pageId);
        hasPrunedRetainedPage = true;
      }
    }
    if (hasPrunedRetainedPage) {
      this.retainedEditablePageVersion += 1;
    }
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
      this.retainThumbnailPages();
      this.syncActivePageId(typeof routeParams.pageId === 'string' ? routeParams.pageId : '');
      await this.loadNotebookPageCanvasMetadata();
      this.queueDocumentViewportRestore(this.activePageId);
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
    this.focusedPageId = '';
    this.pageCanvasByPageId.clear();
    this.knownPageCanvasMetadataPageIds.clear();
    this.retainedEditablePageIds.clear();
    this.canvasVersionByPageId.clear();
    this.canvasVersion += 1;
    this.retainedEditablePageVersion += 1;
    this.activePageCanvas = null;
    this.pageCanvasMetadataMap.clear();
    this.pageCanvasRenderSizeMap.clear();
    this.isCanvasLoading = false;
    this.isUpdatingPageTemplate = false;
    this.pageActionMenuPageId = '';
    this.isPageTemplateDropdownVisible = false;
    this.canvasInputMode = 'stylus';
    this.isDocumentTouchNavigationActive = false;
    this.resetPendingDocumentSingleFingerPan();
    this.documentZoomScale = 1;
    this.documentHorizontalOffset = 0;
    this.documentScrollOffsetY = 0;
    this.documentGesturePreviewScale = 1;
    this.documentGesturePreviewOffsetX = 0;
    this.documentGesturePreviewOffsetY = 0;
    this.isDocumentViewportGestureActive = false;
    this.hasWorkspaceViewport = false;
    this.documentViewportGestureStartDistance = 1;
    this.documentViewportGestureStartWorkspaceX = 0;
    this.documentViewportGestureStartWorkspaceY = 0;
    this.pendingDocumentViewportPageId = '';
    this.endDocumentPanGesture(false);
    this.resetDeletePageDialogState();
    this.resetDrawingState('');
  }

  private syncActivePageId(preferredPageId: string = ''): void {
    if (this.notebookPageList.length === 0) {
      this.activePageId = '';
      this.focusedPageId = '';
      return;
    }

    if (preferredPageId.length > 0) {
      for (const page of this.notebookPageList) {
        if (page.id === preferredPageId) {
          this.activePageId = preferredPageId;
          this.focusedPageId = preferredPageId;
          this.retainEditableDocumentPage(preferredPageId);
          return;
        }
      }
    }

    for (const page of this.notebookPageList) {
      if (page.id === this.activePageId) {
        if (!this.isKnownNotebookPage(this.focusedPageId)) {
          this.focusedPageId = this.activePageId;
        }
        this.retainEditableDocumentPage(this.activePageId);
        return;
      }
    }

    this.activePageId = this.notebookPageList[0].id;
    this.focusedPageId = this.activePageId;
    this.retainEditableDocumentPage(this.activePageId);
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
      this.retainThumbnailPages();
      this.syncActivePageId();
      this.closePageActionMenu();

      if (notebookPage !== null) {
        this.activePageId = notebookPage.id;
        this.focusedPageId = notebookPage.id;
        this.retainEditableDocumentPage(notebookPage.id);
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
    this.focusedPageId = page.id;
    this.retainEditableDocumentPage(page.id);
    this.requestDocumentViewportForPage(page.id);
    this.closePageActionMenu();
    await this.loadActivePageCanvas();
  }

  private activateDocumentPageForInteraction(pageId: string): void {
    if (pageId.length === 0 || this.isLoading || this.isCreatingPage || this.isDeletingPage ||
      this.isReorderingPages || this.isUpdatingPageTemplate) {
      return;
    }

    const hostContext: common.Context | undefined = this.getUIContext().getHostContext() as common.Context | undefined;
    if (hostContext === undefined) {
      return;
    }

    if (this.activePageId !== pageId) {
      this.requestActiveDrawingSessionSave();
      this.activePageId = pageId;
      this.focusedPageId = pageId;
      this.retainEditableDocumentPage(pageId);
      this.activePageCanvas = null;
      this.pendingDocumentViewportPageId = '';
      this.closePageActionMenu();
      this.scheduleActivePageCanvasLoad(pageId);
    }

    const viewModel = EditorSessionRegistry.getOrCreate(pageId, hostContext);
    this.currentDrawingPageId = pageId;
    this.drawingViewModel = viewModel;
    this.applySharedToolSettingToViewModel(viewModel);
    this.syncDrawingSnapshot(false, viewModel, pageId, false);
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
      this.retainThumbnailPages();
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
      this.focusedPageId = '';
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
    this.focusedPageId = this.activePageId;
    this.retainEditableDocumentPage(this.activePageId);
  }

  private async loadActivePageCanvas(): Promise<void> {
    this.clearScheduledActivePageCanvasLoad();
    if (this.notebookId.length === 0 || this.activePageId.length === 0) {
      this.activePageCanvas = null;
      this.isCanvasLoading = false;
      this.resetDrawingState('');
      return;
    }

    const targetPageId: string = this.activePageId;
    const cachedPageCanvas: NotebookPageCanvas | null = this.getCachedPageCanvas(targetPageId);
    const cachedSession = EditorSessionRegistry.get(targetPageId);
    if (cachedPageCanvas !== null && cachedSession !== null &&
      cachedSession.isLoadedForPage(targetPageId)) {
      if (this.currentDrawingPageId.length > 0 && this.currentDrawingPageId !== targetPageId) {
        this.requestActiveDrawingSessionSave();
      }
      if (this.activePageId !== targetPageId) {
        return;
      }
      this.activePageCanvas = cachedPageCanvas;
      this.attachLoadedDrawingSession(targetPageId, cachedSession, false);
      this.isCanvasLoading = false;
      this.restorePendingDocumentViewportIfReady();
      return;
    }

    this.activePageCanvas = cachedPageCanvas;
    this.isCanvasLoading = true;
    try {
      const notebookPageCanvas: NotebookPageCanvas | null = cachedPageCanvas !== null
        ? cachedPageCanvas
        : await this.ensureViewModel().loadNotebookPageCanvas(this.notebookId, targetPageId);

      if (this.activePageId !== targetPageId) {
        return;
      }

      this.cachePageCanvas(targetPageId, notebookPageCanvas);
      this.activePageCanvas = notebookPageCanvas;
      if (notebookPageCanvas !== null) {
        this.pageCanvasMetadataMap.set(targetPageId, notebookPageCanvas);
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
        this.restorePendingDocumentViewportIfReady();
      }
    }
  }

  private async loadNotebookPageCanvasMetadata(): Promise<void> {
    if (this.notebookId.length === 0 || this.notebookPageList.length === 0) {
      return;
    }

    const pageIds: string[] = this.notebookPageList.map((page: NotebookPage): string => page.id);
    const notebookPageCanvasList: NotebookPageCanvas[] = await this.ensureViewModel().loadNotebookPageCanvases(
      this.notebookId,
      pageIds
    );
    for (const notebookPageCanvas of notebookPageCanvasList) {
      this.knownPageCanvasMetadataPageIds.add(notebookPageCanvas.pageId);
      this.pageCanvasMetadataMap.set(notebookPageCanvas.pageId, notebookPageCanvas);
      this.pageCanvasByPageId.set(notebookPageCanvas.pageId, this.cloneNotebookPageCanvasValue(notebookPageCanvas));
      this.updatePageCanvasRenderSize(
        notebookPageCanvas.pageId,
        notebookPageCanvas.width,
        notebookPageCanvas.height
      );
    }
  }

  private hasCachedPageCanvas(pageId: string): boolean {
    return this.pageCanvasByPageId.has(pageId);
  }

  private getCachedPageCanvas(pageId: string): NotebookPageCanvas | null {
    const cachedCanvas = this.pageCanvasByPageId.get(pageId);
    return cachedCanvas === undefined ? null : this.cloneNotebookPageCanvasValue(cachedCanvas);
  }

  private cachePageCanvas(pageId: string, pageCanvas: NotebookPageCanvas | null): void {
    if (pageId.length === 0) {
      return;
    }

    this.knownPageCanvasMetadataPageIds.add(pageId);
    if (pageCanvas === null) {
      this.pageCanvasByPageId.delete(pageId);
      this.pageCanvasMetadataMap.delete(pageId);
      return;
    }

    this.pageCanvasByPageId.set(pageId, this.cloneNotebookPageCanvasValue(pageCanvas));
    this.pageCanvasMetadataMap.set(pageId, this.cloneNotebookPageCanvasValue(pageCanvas));
  }

  private getCanvasVersionForPage(pageId: string): number {
    const renderTick = this.canvasVersion;
    const pageVersion = this.canvasVersionByPageId.get(pageId);
    return renderTick >= 0 && pageVersion !== undefined ? pageVersion : 0;
  }

  private bumpCanvasVersionForPage(pageId: string): void {
    if (pageId.length === 0) {
      this.canvasVersion += 1;
      return;
    }

    const currentVersion = this.canvasVersionByPageId.get(pageId);
    this.canvasVersionByPageId.set(pageId, currentVersion === undefined ? 1 : currentVersion + 1);
    this.canvasVersion += 1;
  }

  private async loadDrawingSession(pageId: string): Promise<void> {
    const hostContext: common.Context | undefined = this.getUIContext().getHostContext() as common.Context | undefined;
    if (hostContext === undefined) {
      this.resetDrawingState(pageId);
      return;
    }

    if (this.currentDrawingPageId.length > 0 && this.currentDrawingPageId !== pageId) {
      this.requestActiveDrawingSessionSave();
    }

    this.currentDrawingPageId = pageId;
    this.drawingViewModel = EditorSessionRegistry.getOrCreate(pageId, hostContext);
    this.applySharedToolSettingToViewModel(this.drawingViewModel);
    this.editorSnapshot = this.buildEmptySnapshot(pageId);
    this.bumpCanvasVersionForPage(pageId);

    const targetPageId: string = pageId;
    const viewModel: DrawingEditorViewModel = this.drawingViewModel;
    this.syncDrawingSnapshot(false, viewModel, targetPageId);
    if (!viewModel.isLoadedForPage(targetPageId)) {
      await EditorSessionRegistry.ensureLoaded(targetPageId, hostContext, this.cloneToolSetting(this.toolSetting));
      if (this.activePageId === targetPageId && this.currentDrawingPageId === targetPageId) {
        this.syncDrawingSnapshot(true, viewModel, targetPageId);
      }
    } else {
      this.captureThumbnailSession(targetPageId, viewModel);
      this.requestThumbnailRender(true);
    }
  }

  private attachLoadedDrawingSession(
    pageId: string,
    viewModel: DrawingEditorViewModel,
    refreshThumbnailImmediately: boolean
  ): void {
    this.currentDrawingPageId = pageId;
    this.drawingViewModel = viewModel;
    this.applySharedToolSettingToViewModel(viewModel);
    this.syncDrawingSnapshot(false, viewModel, pageId, refreshThumbnailImmediately);
  }

  private resetDrawingState(pageId: string): void {
    if (this.currentDrawingPageId.length > 0) {
      void this.flushActiveDrawingSession();
      EditorSessionRegistry.clear(this.currentDrawingPageId);
    }
    this.drawingViewModel = null;
    this.currentDrawingPageId = pageId;
    this.editorSnapshot = this.buildEmptySnapshot(pageId);
    this.bumpCanvasVersionForPage(pageId);
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
      this.editorSnapshot = this.buildEmptySnapshot(targetPageId);
      if (redrawCanvas) {
        this.bumpCanvasVersionForPage(targetPageId);
        this.refreshElementLayer();
        this.requestThumbnailRender(true);
      }
      return;
    }

    if (this.currentDrawingPageId !== targetPageId) {
      return;
    }

    this.applySharedToolSettingToViewModel(targetViewModel);
    this.editorSnapshot = this.buildSnapshotWithSharedToolSetting(targetViewModel);
    if (redrawCanvas) {
      this.captureThumbnailSession(targetPageId, targetViewModel);
      this.bumpCanvasVersionForPage(targetPageId);
      this.refreshElementLayer();
      this.requestThumbnailRender(refreshThumbnailImmediately);
    }
  }

  private applySharedToolSettingToViewModel(viewModel: DrawingEditorViewModel): void {
    const currentSetting = viewModel.getToolSetting();
    if (currentSetting.tool === this.toolSetting.tool &&
      currentSetting.color === this.toolSetting.color &&
      currentSetting.width === this.toolSetting.width &&
      currentSetting.opacity === this.toolSetting.opacity) {
      return;
    }

    viewModel.updateToolSetting(this.cloneToolSetting(this.toolSetting));
  }

  private buildSnapshotWithSharedToolSetting(viewModel: DrawingEditorViewModel): EditorDebugSnapshot {
    const snapshot = viewModel.getDebugSnapshot();
    return {
      instanceId: snapshot.instanceId,
      pageId: snapshot.pageId,
      toolSetting: this.cloneToolSetting(this.toolSetting),
      strokeCount: snapshot.strokeCount,
      elementCount: snapshot.elementCount,
      selectedElementId: snapshot.selectedElementId,
      activeStrokeStyle: snapshot.activeStrokeStyle,
      undoDepth: snapshot.undoDepth,
      redoDepth: snapshot.redoDepth,
      recentEvents: snapshot.recentEvents,
      errorMessage: snapshot.errorMessage,
      persistenceStatus: snapshot.persistenceStatus
    };
  }

  private refreshElementLayer(): void {
    this.elementLayerRefreshVersion += 1;
  }

  private requestThumbnailRender(immediate: boolean = false): void {
    if (immediate) {
      this.clearScheduledThumbnailRender();
      this.bumpThumbnailRenderTick();
      return;
    }

    if (this.thumbnailRenderTimerId >= 0) {
      return;
    }

    const nowTime = Date.now();
    const elapsedTime = nowTime - this.lastThumbnailRenderTime;
    const refreshDelay = elapsedTime >= THUMBNAIL_RENDER_INTERVAL_MS
      ? 0
      : THUMBNAIL_RENDER_INTERVAL_MS - elapsedTime;

    this.thumbnailRenderTimerId = setTimeout(() => {
      this.thumbnailRenderTimerId = -1;
      this.bumpThumbnailRenderTick();
    }, refreshDelay);
  }

  private bumpThumbnailRenderTick(): void {
    this.lastThumbnailRenderTime = Date.now();
    this.thumbnailRenderTick += 1;
  }

  private clearScheduledThumbnailRender(): void {
    if (this.thumbnailRenderTimerId < 0) {
      return;
    }

    clearTimeout(this.thumbnailRenderTimerId);
    this.thumbnailRenderTimerId = -1;
  }

  private scheduleActivePageCanvasLoad(pageId: string): void {
    this.clearScheduledActivePageCanvasLoad();
    if (pageId.length === 0) {
      return;
    }

    this.activePageCanvasLoadTimerId = setTimeout(() => {
      this.activePageCanvasLoadTimerId = -1;
      if (pageId !== this.activePageId) {
        return;
      }

      if (this.isDocumentPanGestureActive || this.isDocumentViewportGestureActive || this.isDocumentTouchNavigationActive) {
        this.scheduleActivePageCanvasLoad(pageId);
        return;
      }

      void this.loadActivePageCanvas();
    }, ACTIVE_PAGE_CANVAS_LOAD_DELAY_MS);
  }

  private clearScheduledActivePageCanvasLoad(): void {
    if (this.activePageCanvasLoadTimerId < 0) {
      return;
    }

    clearTimeout(this.activePageCanvasLoadTimerId);
    this.activePageCanvasLoadTimerId = -1;
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
    this.requestThumbnailRender(true);
  }

  private async flushActiveDrawingSession(): Promise<void> {
    if (this.drawingViewModel === null) {
      return;
    }

    this.captureActiveSessionForThumbnail();
    await this.drawingViewModel.flushPendingSave();
  }

  private requestActiveDrawingSessionSave(): void {
    if (this.drawingViewModel === null) {
      return;
    }

    this.captureActiveSessionForThumbnail();
    this.drawingViewModel.requestDeferredSave('pageSwitch');
  }

  private getPageThumbnailHeight(_pageId: string): number {
    return Math.round(
      PAGE_THUMBNAIL_WIDTH * NotebookPageCanvasEntity.DEFAULT_HEIGHT / NotebookPageCanvasEntity.DEFAULT_WIDTH
    );
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
      return this.normalizeCanvasRenderSize(this.activePageCanvas.width, this.activePageCanvas.height);
    }

    return {
      width: 1600,
      height: 900
    };
  }

  private handleWorkspaceAreaChange(area: Area): void {
    const nextWidth = this.resolveAreaWidth(area);
    const nextHeight = this.resolveAreaHeight(area);
    this.workspaceViewportWindowX = this.resolveAreaPosition(area.globalPosition.x);
    this.workspaceViewportWindowY = this.resolveAreaPosition(area.globalPosition.y);
    const hasWidthChanged = nextWidth > 0 && nextWidth !== this.workspaceViewportWidth;
    const hasHeightChanged = nextHeight > 0 && nextHeight !== this.workspaceViewportHeight;
    const canUseViewport = nextWidth > 0 && nextHeight > 0;
    const shouldMarkViewportReady = canUseViewport && !this.hasWorkspaceViewport;
    if (!hasWidthChanged && !hasHeightChanged && !shouldMarkViewportReady) {
      return;
    }

    if (hasWidthChanged) {
      this.workspaceViewportWidth = nextWidth;
    }
    if (hasHeightChanged) {
      this.workspaceViewportHeight = nextHeight;
    }
    if (canUseViewport) {
      this.hasWorkspaceViewport = true;
    }
    this.documentHorizontalOffset = this.clampDocumentHorizontalOffset(this.documentHorizontalOffset);
    this.applyDocumentScrollOffset(this.documentScrollOffsetY);
    this.restorePendingDocumentViewportIfReady();
  }

  private isWorkspaceViewportReady(): boolean {
    return this.hasWorkspaceViewport && this.workspaceViewportWidth > 0 && this.workspaceViewportHeight > 0;
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

  private resolveAreaPosition(value: Length | undefined): number {
    const numericValue = Number(value);
    if (Number.isFinite(numericValue)) {
      return numericValue;
    }

    return 0;
  }

  private getDocumentPageSurfaceWidth(): number {
    return this.getDocumentPageSurfaceBaseWidth();
  }

  private getDocumentPageSurfaceWidthForScale(scale: number): number {
    return Math.round(this.getDocumentPageSurfaceBaseWidth() * scale);
  }

  private getDocumentPageSurfaceBaseWidth(): number {
    const availableWidth = this.workspaceViewportWidth > 0
      ? this.workspaceViewportWidth - DOCUMENT_PAGE_HORIZONTAL_PADDING * 2
      : DOCUMENT_PAGE_SURFACE_MAX_WIDTH;
    return Math.max(DOCUMENT_PAGE_SURFACE_MIN_WIDTH, Math.round(availableWidth));
  }

  private getDocumentPageSurfaceHeight(_pageId: string, targetWidth: number): number {
    return Math.max(
      240,
      Math.round(targetWidth * NotebookPageCanvasEntity.DEFAULT_HEIGHT / NotebookPageCanvasEntity.DEFAULT_WIDTH)
    );
  }

  private getDocumentPageSurfaceHeightForPage(pageId: string): number {
    return this.getDocumentPageSurfaceHeight(pageId, this.getDocumentPageSurfaceWidth());
  }

  private getDocumentPageSurfaceHeightForScale(pageId: string, scale: number): number {
    return Math.round(this.getDocumentPageSurfaceHeightForPage(pageId) * scale);
  }

  private getDocumentPageBlockTopForScale(pageId: string, scale: number): number {
    return Math.round(this.getDocumentPageBlockTop(pageId) * scale);
  }

  private getDocumentPageBlockHeightForScale(pageId: string, scale: number): number {
    return Math.round(this.getDocumentPageBlockHeight(pageId) * scale);
  }

  private getDocumentPageAnchorContentXForScale(pageUnitX: number, scale: number): number {
    return Math.round((DOCUMENT_PAGE_HORIZONTAL_PADDING + this.clampUnit(pageUnitX) *
      this.getDocumentPageSurfaceWidth()) * scale);
  }

  private getDocumentPageAnchorContentYForScale(pageId: string, pageUnitY: number, scale: number): number {
    const pageContentTop = this.getDocumentPageBlockTop(pageId) + DOCUMENT_PAGE_HEADER_HEIGHT + 10;
    const pageSurfaceHeight = this.getDocumentPageSurfaceHeightForPage(pageId);
    return Math.round((pageContentTop + this.clampUnit(pageUnitY) * pageSurfaceHeight) * scale);
  }

  private getDocumentContentHeightForScale(scale: number): number {
    if (this.notebookPageList.length === 0) {
      return Math.max(1, this.workspaceViewportHeight);
    }
    return Math.round(this.getDocumentContentHeightForScaleOne() * scale);
  }

  private getDocumentContentHeightForScaleOne(): number {
    let height = DOCUMENT_PAGE_HORIZONTAL_PADDING * 2;
    for (let index = 0; index < this.notebookPageList.length; index += 1) {
      height += this.getDocumentPageBlockHeight(this.notebookPageList[index].id);
      if (index < this.notebookPageList.length - 1) {
        height += DOCUMENT_PAGE_GAP;
      }
    }
    return height;
  }

  private clampDocumentScrollOffsetForScale(offset: number, scale: number): number {
    const viewportHeight = Math.max(1, this.workspaceViewportHeight);
    const maxOffset = Math.max(0, this.getDocumentContentHeightForScale(scale) - viewportHeight);
    if (!Number.isFinite(offset)) {
      return 0;
    }
    return Math.max(0, Math.min(maxOffset, offset));
  }

  private clampUnit(value: number): number {
    if (!Number.isFinite(value)) {
      return 0.5;
    }
    return Math.max(0, Math.min(1, value));
  }

  private isDocumentPageActive(pageId: string): boolean {
    return pageId === this.activePageId;
  }

  private isKnownNotebookPage(pageId: string): boolean {
    if (pageId.length === 0) {
      return false;
    }

    for (const page of this.notebookPageList) {
      if (page.id === pageId) {
        return true;
      }
    }

    return false;
  }

  private getVisualPageId(): string {
    if (this.focusedPageId.length > 0) {
      return this.focusedPageId;
    }

    if (this.activePageId.length > 0) {
      return this.activePageId;
    }

    return this.notebookPageList.length === 0 ? '' : this.notebookPageList[0].id;
  }

  private isPageVisuallySelected(pageId: string): boolean {
    return pageId.length > 0 && pageId === this.getVisualPageId();
  }

  private focusNotebookPageForNavigation(pageId: string): void {
    if (pageId.length === 0 || pageId === this.focusedPageId || !this.isKnownNotebookPage(pageId)) {
      return;
    }

    this.focusedPageId = pageId;
    if ((this.isDocumentViewportGestureActive || this.isDocumentTouchNavigationActive) &&
      this.activePageCanvasLoadTimerId >= 0 && this.activePageId !== pageId) {
      this.clearScheduledActivePageCanvasLoad();
    }
  }

  private retainEditableDocumentPage(pageId: string): void {
    if (pageId.length === 0 || this.retainedEditablePageIds.has(pageId)) {
      return;
    }

    this.retainedEditablePageIds.add(pageId);
    this.retainedEditablePageVersion += 1;
  }

  private isDocumentPageRetainedEditable(pageId: string): boolean {
    const retainedVersion = this.retainedEditablePageVersion;
    return retainedVersion >= 0 && this.retainedEditablePageIds.has(pageId);
  }

  private promoteNavigationPageToActive(pageId: string): void {
    if (pageId.length === 0 || !this.isKnownNotebookPage(pageId) || this.isLoading || this.isCreatingPage ||
      this.isDeletingPage || this.isReorderingPages || this.isUpdatingPageTemplate) {
      return;
    }

    this.focusedPageId = pageId;
    this.retainEditableDocumentPage(pageId);
    if (this.activePageId === pageId) {
      return;
    }

    this.requestActiveDrawingSessionSave();
    this.activePageId = pageId;
    this.activePageCanvas = this.getCachedPageCanvas(pageId);
    this.pendingDocumentViewportPageId = '';
    this.closePageActionMenu();

    const existingSession = EditorSessionRegistry.get(pageId);
    if (existingSession !== null && existingSession.isLoadedForPage(pageId)) {
      this.attachLoadedDrawingSession(pageId, existingSession, false);
    }

    if (!this.hasCachedPageCanvas(pageId) || existingSession === null || !existingSession.isLoadedForPage(pageId)) {
      this.scheduleActivePageCanvasLoad(pageId);
    }
  }

  private isContinuousDocumentViewEnabled(): boolean {
    return true;
  }

  private isDocumentNavigationModeEnabled(): boolean {
    return this.isContinuousDocumentViewEnabled() && this.isDocumentTouchNavigationActive;
  }

  private shouldRenderEditableDocumentPage(pageId: string): boolean {
    return this.isDocumentPageActive(pageId) || this.isDocumentPageRetainedEditable(pageId) ||
      this.isDocumentPageWithinEditableWindow(pageId);
  }

  private shouldAutoLoadDocumentPageSession(pageId: string): boolean {
    const existingSession = EditorSessionRegistry.get(pageId);
    return this.isDocumentPageActive(pageId) ||
      this.isDocumentPageRetainedEditable(pageId) ||
      (existingSession !== null && existingSession.isLoadedForPage(pageId));
  }

  private isDocumentPageSessionLoaded(pageId: string): boolean {
    const existingSession = EditorSessionRegistry.get(pageId);
    return existingSession !== null && existingSession.isLoadedForPage(pageId);
  }

  private shouldRenderDocumentPagePreviewBacking(pageId: string): boolean {
    if (!this.shouldRenderEditableDocumentPage(pageId)) {
      return false;
    }

    if (!this.shouldAutoLoadDocumentPageSession(pageId)) {
      return true;
    }

    return !this.isDocumentPageSessionLoaded(pageId) ||
      (this.isDocumentPageActive(pageId) && this.isCanvasLoading);
  }

  private shouldRenderDocumentPagePreview(pageId: string): boolean {
    return this.isDocumentPageActive(pageId) || this.isDocumentPageWithinRenderWindow(pageId);
  }

  private isDocumentPageWithinRenderWindow(pageId: string): boolean {
    return this.isDocumentPageWithinViewportWindow(pageId, DOCUMENT_PAGE_RENDER_WINDOW_PADDING_FACTOR);
  }

  private isDocumentPageWithinEditableWindow(pageId: string): boolean {
    return this.isDocumentPageWithinViewportWindow(pageId, DOCUMENT_PAGE_EDITABLE_WINDOW_PADDING_FACTOR);
  }

  private isDocumentPageWithinViewportWindow(pageId: string, paddingFactor: number): boolean {
    const viewportHeight = Math.max(1, this.workspaceViewportHeight);
    const padding = viewportHeight * Math.max(0, paddingFactor);
    const scrollOffsetY = this.getDocumentRenderWindowScrollOffsetY();
    const renderWindowTop = Math.max(0, scrollOffsetY - padding);
    const renderWindowBottom = scrollOffsetY + viewportHeight + padding;
    const pageTop = this.getDocumentPageBlockTopForScale(pageId, this.documentZoomScale);
    const pageBottom = pageTop + this.getDocumentPageBlockHeightForScale(pageId, this.documentZoomScale);
    return pageBottom >= renderWindowTop && pageTop <= renderWindowBottom;
  }

  private getDocumentRenderWindowScrollOffsetY(): number {
    return this.documentScrollOffsetY;
  }

  private resetDocumentZoomScale(): void {
    this.documentZoomScale = this.clampDocumentZoomScale(1);
    this.documentHorizontalOffset = 0;
    this.applyDocumentScrollOffset(this.documentScrollOffsetY);
  }

  private getDocumentVisualScale(): number {
    return this.documentZoomScale * this.documentGesturePreviewScale;
  }

  private clampDocumentZoomScale(scale: number): number {
    return Math.max(DOCUMENT_ZOOM_MIN_SCALE, Math.min(DOCUMENT_ZOOM_MAX_SCALE, scale));
  }

  private beginDocumentViewportGesture(
    pageId: string,
    centerX: number,
    centerY: number,
    windowCenterX: number,
    windowCenterY: number
  ): void {
    if (!this.isContinuousDocumentViewEnabled()) {
      return;
    }

    this.isDocumentViewportGestureActive = true;
    this.clearScheduledActivePageCanvasLoad();
    this.endDocumentPanGesture(false);
    this.documentViewportGestureStartWorkspaceX = windowCenterX - this.workspaceViewportWindowX;
    this.documentViewportGestureStartWorkspaceY = windowCenterY - this.workspaceViewportWindowY;
    this.documentGestureStartZoomScale = this.documentZoomScale;
    this.documentGestureStartHorizontalOffset = this.documentHorizontalOffset;
    this.documentGestureStartScrollOffsetY = this.documentScrollOffsetY;
    this.documentGestureTargetZoomScale = this.documentZoomScale;
    this.documentGestureTargetHorizontalOffset = this.documentHorizontalOffset;
    this.documentGestureTargetScrollOffsetY = this.documentScrollOffsetY;
    this.documentGesturePreviewScale = 1;
    this.documentGesturePreviewOffsetX = 0;
    this.documentGesturePreviewOffsetY = 0;
    this.lastDocumentGesturePreviewTime = 0;
    this.lastNavigationFocusUpdateTime = 0;

    const anchorPageId = pageId.length > 0 ? pageId : this.activePageId;
    this.focusNotebookPageForNavigation(anchorPageId);
    const surfaceWidth = this.getDocumentPageSurfaceWidthForScale(this.documentGestureStartZoomScale);
    const surfaceHeight = this.getDocumentPageSurfaceHeight(anchorPageId, surfaceWidth);
    this.documentGestureAnchorPageId = anchorPageId;
    this.documentGestureAnchorPageUnitX = this.clampUnit(centerX / Math.max(1, surfaceWidth));
    this.documentGestureAnchorPageUnitY = this.clampUnit(centerY / Math.max(1, surfaceHeight));
  }

  private updateDocumentViewportGesture(
    scaleRatio: number,
    windowCenterX: number,
    windowCenterY: number
  ): void {
    if (!this.isContinuousDocumentViewEnabled() || !this.isDocumentViewportGestureActive) {
      return;
    }

    const currentTouchWorkspaceX = windowCenterX - this.workspaceViewportWindowX;
    const currentTouchWorkspaceY = windowCenterY - this.workspaceViewportWindowY;
    const centerDeltaX = currentTouchWorkspaceX - this.documentViewportGestureStartWorkspaceX;
    const centerDeltaY = currentTouchWorkspaceY - this.documentViewportGestureStartWorkspaceY;
    const nextZoomScale = this.clampDocumentZoomScale(this.documentGestureStartZoomScale * scaleRatio);
    const previewScale = nextZoomScale / Math.max(0.001, this.documentGestureStartZoomScale);
    const startBaseOffsetX = this.getDocumentContentBaseOffsetXForScale(this.documentGestureStartZoomScale);
    const targetBaseOffsetX = this.getDocumentContentBaseOffsetXForScale(nextZoomScale);
    const startAnchorContentX = this.getDocumentPageAnchorContentXForScale(
      this.documentGestureAnchorPageUnitX,
      this.documentGestureStartZoomScale
    );
    const startAnchorContentY = this.getDocumentPageAnchorContentYForScale(
      this.documentGestureAnchorPageId,
      this.documentGestureAnchorPageUnitY,
      this.documentGestureStartZoomScale
    );
    const targetAnchorContentX = this.getDocumentPageAnchorContentXForScale(
      this.documentGestureAnchorPageUnitX,
      nextZoomScale
    );
    const targetAnchorContentY = this.getDocumentPageAnchorContentYForScale(
      this.documentGestureAnchorPageId,
      this.documentGestureAnchorPageUnitY,
      nextZoomScale
    );
    this.documentGestureTargetZoomScale = nextZoomScale;
    this.documentGestureTargetHorizontalOffset = this.clampDocumentHorizontalOffsetForScale(
      this.documentGestureStartHorizontalOffset + centerDeltaX + startBaseOffsetX - targetBaseOffsetX +
        startAnchorContentX - targetAnchorContentX,
      nextZoomScale,
      this.shouldCenterContentForViewportGesture(nextZoomScale)
    );
    this.documentGestureTargetScrollOffsetY = this.clampDocumentScrollOffsetForScale(
      this.documentGestureStartScrollOffsetY - centerDeltaY + targetAnchorContentY - startAnchorContentY,
      nextZoomScale
    );

    const nextPreviewOffsetX = centerDeltaX + startAnchorContentX - startAnchorContentX * previewScale;
    const nextPreviewOffsetY = centerDeltaY + startAnchorContentY - startAnchorContentY * previewScale;
    this.applyDocumentGesturePreview(previewScale, nextPreviewOffsetX, nextPreviewOffsetY);
    this.updateNavigationFocusedPageFromViewport(false);
  }

  private endDocumentViewportGesture(): void {
    if (!this.isDocumentViewportGestureActive) {
      return;
    }

    this.isDocumentViewportGestureActive = false;
    this.documentViewportGestureStartDistance = 1;
    this.documentViewportGestureStartWorkspaceX = 0;
    this.documentViewportGestureStartWorkspaceY = 0;
    const hasCommittedZoomChange = this.shouldCommitDocumentZoomChange(this.documentGestureTargetZoomScale);
    const nextZoomScale = hasCommittedZoomChange
      ? this.documentGestureTargetZoomScale
      : this.documentGestureStartZoomScale;
    this.documentGesturePreviewScale = 1;
    this.documentGesturePreviewOffsetX = 0;
    this.documentGesturePreviewOffsetY = 0;
    this.documentZoomScale = nextZoomScale;
    this.documentHorizontalOffset = this.clampDocumentHorizontalOffsetForScale(
      this.documentGestureTargetHorizontalOffset,
      this.documentZoomScale,
      hasCommittedZoomChange && this.shouldCenterContentForViewportGesture(nextZoomScale)
    );
    const nextScrollOffset = this.clampDocumentScrollOffsetForScale(
      this.documentGestureTargetScrollOffsetY,
      this.documentZoomScale
    );
    this.applyDocumentScrollOffset(nextScrollOffset);
    this.updateNavigationFocusedPageFromViewport(true);
    this.isDocumentTouchNavigationActive = false;
  }

  private shouldCommitDocumentZoomChange(nextZoomScale: number): boolean {
    return Math.abs(nextZoomScale - this.documentGestureStartZoomScale) >= DOCUMENT_ZOOM_COMMIT_EPSILON;
  }

  private applyDocumentGesturePreview(
    previewScale: number,
    offsetX: number,
    offsetY: number
  ): void {
    const nowTime = Date.now();
    if (this.lastDocumentGesturePreviewTime > 0 &&
      nowTime - this.lastDocumentGesturePreviewTime < DOCUMENT_GESTURE_PREVIEW_INTERVAL_MS) {
      return;
    }

    this.lastDocumentGesturePreviewTime = nowTime;
    this.documentGesturePreviewScale = previewScale;
    this.documentGesturePreviewOffsetX = offsetX;
    this.documentGesturePreviewOffsetY = offsetY;
  }

  private getDocumentContentWidth(): number {
    return this.getDocumentPageSurfaceWidth() + DOCUMENT_PAGE_HORIZONTAL_PADDING * 2;
  }

  private getDocumentContentHeight(): number {
    return this.getDocumentContentHeightForScale(1);
  }

  private getDocumentVisualOffsetX(): number {
    return this.getDocumentContentBaseOffsetXForScale(this.documentZoomScale) +
      this.documentHorizontalOffset +
      this.documentGesturePreviewOffsetX;
  }

  private getDocumentContentOffsetY(): number {
    return -this.documentScrollOffsetY + this.documentGesturePreviewOffsetY;
  }

  private clampDocumentHorizontalOffset(offset: number): number {
    return this.clampDocumentHorizontalOffsetForScale(offset, this.documentZoomScale);
  }

  private clampDocumentHorizontalOffsetForScale(
    offset: number,
    scale: number,
    centerContentWhenFits: boolean = true
  ): number {
    const viewportWidth = Math.max(1, this.workspaceViewportWidth);
    const contentWidth = this.getDocumentContentWidthForScale(scale);
    const overflowWidth = Math.max(0, contentWidth - viewportWidth);
    if (overflowWidth <= 0) {
      if (centerContentWhenFits) {
        return 0;
      }

      const halfUnderflow = Math.max(0, viewportWidth - contentWidth) / 2;
      return Math.max(-halfUnderflow, Math.min(halfUnderflow, offset));
    }

    const halfOverflow = overflowWidth / 2;
    return Math.max(-halfOverflow, Math.min(halfOverflow, offset));
  }

  private shouldCenterContentForViewportGesture(nextZoomScale: number): boolean {
    return nextZoomScale <= this.documentGestureStartZoomScale;
  }

  private getDocumentContentWidthForScale(scale: number): number {
    return Math.round(this.getDocumentContentWidth() * scale);
  }

  private getDocumentContentBaseOffsetXForScale(scale: number): number {
    const viewportWidth = Math.max(1, this.workspaceViewportWidth);
    const contentWidth = this.getDocumentContentWidthForScale(scale);
    return (viewportWidth - contentWidth) / 2;
  }

  private getDocumentScrollOffsetForPage(pageId: string): number {
    return Math.max(0, this.getDocumentPageBlockTopForScale(pageId, this.documentZoomScale));
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

  private scrollDocumentToPage(pageId: string): void {
    if (!this.isContinuousDocumentViewEnabled() || pageId.length === 0) {
      return;
    }

    this.focusNotebookPageForNavigation(pageId);
    const targetOffset = this.getDocumentScrollOffsetForPage(pageId);
    this.applyDocumentScrollOffset(targetOffset);
  }

  private requestDocumentViewportForPage(pageId: string): void {
    if (!this.isContinuousDocumentViewEnabled() || pageId.length === 0) {
      return;
    }

    this.pendingDocumentViewportPageId = pageId;
    this.restorePendingDocumentViewportIfReady();
  }

  private queueDocumentViewportRestore(pageId: string): void {
    this.pendingDocumentViewportPageId = pageId;
    this.documentScrollOffsetY = 0;
    this.documentHorizontalOffset = 0;
  }

  private restorePendingDocumentViewportIfReady(): void {
    if (this.pendingDocumentViewportPageId.length === 0) {
      return;
    }

    if (!this.isWorkspaceViewportReady() || this.isCanvasLoading) {
      return;
    }

    if (this.pendingDocumentViewportPageId !== this.activePageId) {
      this.pendingDocumentViewportPageId = '';
      return;
    }

    this.scrollDocumentToPage(this.pendingDocumentViewportPageId);
    this.pendingDocumentViewportPageId = '';
  }

  private applyDocumentScrollOffset(offset: number): void {
    this.documentScrollOffsetY = this.clampDocumentScrollOffsetForScale(offset, this.documentZoomScale);
  }

  private handleDocumentSurfaceTouch(event: TouchEvent): void {
    if (!this.isContinuousDocumentViewEnabled() || this.isStylusTouchEvent(event) ||
      !this.shouldHandleDocumentTouchForInputMode(event)) {
      return;
    }

    const touchSignature = this.buildDocumentTouchSignature(event);
    if (touchSignature === this.lastDocumentTouchSignature) {
      return;
    }
    this.lastDocumentTouchSignature = touchSignature;

    const activeTouches: TouchObject[] = this.getDocumentActiveTouches(event);
    if (event.type === TouchType.Cancel) {
      this.cancelDocumentTouchNavigation();
      return;
    }

    if (event.type === TouchType.Up && this.isDocumentViewportGestureActive && activeTouches.length < 2) {
      this.endDocumentViewportGesture();
      return;
    }

    if (activeTouches.length >= 2) {
      this.resetPendingDocumentSingleFingerPan();
      this.endDocumentPanGesture(false);
      this.isDocumentTouchNavigationActive = true;
      const pairMetrics = this.getDocumentTouchPairMetrics(activeTouches[0], activeTouches[1]);

      if (!this.isDocumentViewportGestureActive || event.type === TouchType.Down) {
        const anchor = this.resolveDocumentTouchAnchor(
          pairMetrics.windowCenterX - this.workspaceViewportWindowX,
          pairMetrics.windowCenterY - this.workspaceViewportWindowY
        );
        this.documentViewportGestureStartDistance = Math.max(1, pairMetrics.distance);
        this.beginDocumentViewportGesture(
          anchor.pageId,
          anchor.pageX,
          anchor.pageY,
          pairMetrics.windowCenterX,
          pairMetrics.windowCenterY
        );
      } else {
        const scaleRatio = Math.max(
          0.1,
          pairMetrics.distance / Math.max(1, this.documentViewportGestureStartDistance)
        );
        this.updateDocumentViewportGesture(
          scaleRatio,
          pairMetrics.windowCenterX,
          pairMetrics.windowCenterY
        );
      }
      return;
    }

    if (this.isDocumentViewportGestureActive) {
      this.endDocumentViewportGesture();
      return;
    }

    if (activeTouches.length === 1) {
      this.resetPendingDocumentSingleFingerPan();
      this.endDocumentPanGesture(false);
      return;
    }

    if (event.type === TouchType.Up) {
      this.resetPendingDocumentSingleFingerPan();
      this.endDocumentPanGesture(false);
    }
  }

  private handleDocumentSingleFingerPanTouch(event: TouchEvent, touch: TouchObject): void {
    if (event.type === TouchType.Down) {
      this.beginPendingDocumentSingleFingerPan(touch);
      return;
    }

    if (event.type === TouchType.Move) {
      if (this.isDocumentPanGestureActive) {
        this.updateDocumentPanGestureAt(touch.windowX, touch.windowY);
        return;
      }

      if (!this.isDocumentSingleFingerPanPending || touch.id !== this.documentSingleFingerPanTouchId) {
        this.beginPendingDocumentSingleFingerPan(touch);
        return;
      }

      if (!this.hasDocumentSingleFingerPanExceededThreshold(touch)) {
        return;
      }

      this.isDocumentTouchNavigationActive = true;
      this.isDocumentSingleFingerPanPending = false;
      this.beginDocumentPanGestureAt(
        this.documentSingleFingerPanStartWindowX,
        this.documentSingleFingerPanStartWindowY
      );
      this.updateDocumentPanGestureAt(touch.windowX, touch.windowY);
      return;
    }

    if (event.type === TouchType.Up) {
      this.finishDocumentSingleFingerPan();
    }
  }

  private beginPendingDocumentSingleFingerPan(touch: TouchObject): void {
    this.isDocumentSingleFingerPanPending = true;
    this.documentSingleFingerPanTouchId = touch.id;
    this.documentSingleFingerPanStartWindowX = touch.windowX;
    this.documentSingleFingerPanStartWindowY = touch.windowY;
  }

  private hasDocumentSingleFingerPanExceededThreshold(touch: TouchObject): boolean {
    const deltaX = touch.windowX - this.documentSingleFingerPanStartWindowX;
    const deltaY = touch.windowY - this.documentSingleFingerPanStartWindowY;
    return Math.sqrt(deltaX * deltaX + deltaY * deltaY) >= DOCUMENT_SINGLE_FINGER_PAN_THRESHOLD_SCREEN_PX;
  }

  private finishDocumentSingleFingerPan(): void {
    if (this.isDocumentPanGestureActive) {
      this.endDocumentPanGesture(true);
    }

    this.resetPendingDocumentSingleFingerPan();
    this.isDocumentTouchNavigationActive = false;
  }

  private resetPendingDocumentSingleFingerPan(): void {
    this.isDocumentSingleFingerPanPending = false;
    this.documentSingleFingerPanTouchId = -1;
    this.documentSingleFingerPanStartWindowX = 0;
    this.documentSingleFingerPanStartWindowY = 0;
  }

  private cancelDocumentTouchNavigation(): void {
    this.resetPendingDocumentSingleFingerPan();
    this.endDocumentPanGesture(false);
    this.endDocumentViewportGesture();
    this.isDocumentTouchNavigationActive = false;
  }

  private getDocumentActiveTouches(event: TouchEvent): TouchObject[] {
    if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      return event.touches;
    }

    if (event.touches.length > 0) {
      return event.touches;
    }

    return event.changedTouches;
  }

  private isStylusTouchEvent(event: TouchEvent): boolean {
    return event.sourceTool === SourceTool.Pen;
  }

  private shouldHandleDocumentTouchForInputMode(event: TouchEvent): boolean {
    if (this.canvasInputMode === 'stylus') {
      return true;
    }

    const activeTouches: TouchObject[] = this.getDocumentActiveTouches(event);
    return activeTouches.length >= 2 || this.isDocumentViewportGestureActive || event.type === TouchType.Cancel;
  }

  private buildDocumentTouchSignature(event: TouchEvent): string {
    const touches = this.getDocumentActiveTouches(event);
    const touchSignature = touches
      .map((touch: TouchObject): string => {
        return `${touch.id}:${Math.round(touch.windowX)}:${Math.round(touch.windowY)}`;
      })
      .join(',');
    return `${event.type}:${event.sourceTool}:${touchSignature}`;
  }

  private getDocumentTouchPairMetrics(firstTouch: TouchObject, secondTouch: TouchObject): DocumentTouchPairMetrics {
    const deltaX = secondTouch.x - firstTouch.x;
    const deltaY = secondTouch.y - firstTouch.y;

    return {
      windowCenterX: (firstTouch.windowX + secondTouch.windowX) / 2,
      windowCenterY: (firstTouch.windowY + secondTouch.windowY) / 2,
      distance: Math.sqrt(deltaX * deltaX + deltaY * deltaY)
    };
  }

  private resolveDocumentTouchAnchor(workspaceX: number, workspaceY: number): DocumentTouchAnchor {
    if (this.notebookPageList.length === 0) {
      return {
        pageId: this.activePageId,
        pageX: 0,
        pageY: 0
      };
    }

    const scale = this.documentZoomScale;
    const contentX = workspaceX - this.getDocumentContentBaseOffsetXForScale(scale) - this.documentHorizontalOffset;
    const contentY = workspaceY + this.documentScrollOffsetY;
    const pageSurfaceWidth = this.getDocumentPageSurfaceWidthForScale(scale);
    let fallbackPage = this.notebookPageList[0];
    let fallbackDistance = Number.MAX_VALUE;

    for (const page of this.notebookPageList) {
      const pageTop = this.getDocumentPageBlockTopForScale(page.id, scale) +
        Math.round((DOCUMENT_PAGE_HEADER_HEIGHT + 10) * scale);
      const pageHeight = this.getDocumentPageSurfaceHeightForScale(page.id, scale);
      const distance = this.getDistanceToRange(contentY, pageTop, pageTop + pageHeight);
      if (distance < fallbackDistance) {
        fallbackDistance = distance;
        fallbackPage = page;
      }

      if (contentY >= pageTop && contentY <= pageTop + pageHeight) {
        return {
          pageId: page.id,
          pageX: this.clampDocumentAnchorCoordinate(contentX - DOCUMENT_PAGE_HORIZONTAL_PADDING * scale,
            pageSurfaceWidth),
          pageY: this.clampDocumentAnchorCoordinate(contentY - pageTop, pageHeight)
        };
      }
    }

    const fallbackTop =
      this.getDocumentPageBlockTopForScale(fallbackPage.id, scale) +
        Math.round((DOCUMENT_PAGE_HEADER_HEIGHT + 10) * scale);
    const fallbackHeight = this.getDocumentPageSurfaceHeightForScale(fallbackPage.id, scale);
    return {
      pageId: fallbackPage.id,
      pageX: this.clampDocumentAnchorCoordinate(contentX - DOCUMENT_PAGE_HORIZONTAL_PADDING * scale,
        pageSurfaceWidth),
      pageY: this.clampDocumentAnchorCoordinate(contentY - fallbackTop, fallbackHeight)
    };
  }

  private getDistanceToRange(value: number, minValue: number, maxValue: number): number {
    if (value < minValue) {
      return minValue - value;
    }

    if (value > maxValue) {
      return value - maxValue;
    }

    return 0;
  }

  private clampDocumentAnchorCoordinate(value: number, maxValue: number): number {
    if (!Number.isFinite(value)) {
      return 0;
    }

    return Math.max(0, Math.min(Math.max(0, maxValue), value));
  }

  private beginDocumentPanGestureAt(windowX: number, windowY: number): void {
    this.closeTransientDropdowns();
    this.isDocumentPanGestureActive = true;
    this.documentPanStartWindowX = windowX;
    this.documentPanStartWindowY = windowY;
    this.documentGestureStartHorizontalOffset = this.documentHorizontalOffset;
    this.documentGestureStartScrollOffsetY = this.documentScrollOffsetY;
    this.documentGestureTargetHorizontalOffset = this.documentHorizontalOffset;
    this.documentGestureTargetScrollOffsetY = this.documentScrollOffsetY;
    this.documentGesturePreviewScale = 1;
    this.documentGesturePreviewOffsetX = 0;
    this.documentGesturePreviewOffsetY = 0;
    this.lastDocumentGesturePreviewTime = 0;
  }

  private updateDocumentPanGestureAt(windowX: number, windowY: number): void {
    if (!this.isDocumentPanGestureActive) {
      return;
    }

    const deltaX = windowX - this.documentPanStartWindowX;
    const deltaY = windowY - this.documentPanStartWindowY;
    this.documentGestureTargetHorizontalOffset = this.clampDocumentHorizontalOffsetForScale(
      this.documentGestureStartHorizontalOffset + deltaX,
      this.documentZoomScale
    );
    this.documentGestureTargetScrollOffsetY = this.clampDocumentScrollOffsetForScale(
      this.documentGestureStartScrollOffsetY - deltaY,
      this.documentZoomScale
    );
    this.applyDocumentGesturePreview(
      1,
      this.documentGestureTargetHorizontalOffset - this.documentGestureStartHorizontalOffset,
      this.documentGestureStartScrollOffsetY - this.documentGestureTargetScrollOffsetY
    );
    this.updateNavigationFocusedPageFromViewport(false);
  }

  private endDocumentPanGesture(commitCenteredPage: boolean): void {
    if (!this.isDocumentPanGestureActive) {
      return;
    }

    this.isDocumentPanGestureActive = false;
    this.documentPanStartWindowX = 0;
    this.documentPanStartWindowY = 0;
    this.documentGesturePreviewScale = 1;
    this.documentGesturePreviewOffsetX = 0;
    this.documentGesturePreviewOffsetY = 0;
    this.documentHorizontalOffset = this.clampDocumentHorizontalOffsetForScale(
      this.documentGestureTargetHorizontalOffset,
      this.documentZoomScale
    );
    this.applyDocumentScrollOffset(this.documentGestureTargetScrollOffsetY);
    this.updateNavigationFocusedPageFromViewport(true);
    if (commitCenteredPage) {
      void this.commitViewportCenteredPage();
    }
  }

  private getViewportCenteredPageId(): string {
    return this.getViewportCenteredPageIdForViewport(this.documentScrollOffsetY, this.documentZoomScale);
  }

  private getViewportCenteredPageIdForViewport(scrollOffsetY: number, zoomScale: number): string {
    if (this.notebookPageList.length === 0) {
      return '';
    }

    const viewportHeight = this.workspaceViewportHeight > 0 ? this.workspaceViewportHeight : 1;
    const clampedScrollOffsetY = this.clampDocumentScrollOffsetForScale(scrollOffsetY, zoomScale);
    const viewportTop = clampedScrollOffsetY;
    const viewportBottom = clampedScrollOffsetY + viewportHeight;
    let bestPageId = this.notebookPageList[0].id;
    let bestVisibleHeight = -1;
    let bestDistanceToTop = Number.MAX_VALUE;

    for (const page of this.notebookPageList) {
      const pageTop = this.getDocumentPageBlockTopForScale(page.id, zoomScale);
      const pageBottom = pageTop + this.getDocumentPageBlockHeightForScale(page.id, zoomScale);
      const visibleHeight = Math.max(0, Math.min(viewportBottom, pageBottom) - Math.max(viewportTop, pageTop));
      const distanceToTop = this.getDistanceToRange(viewportTop, pageTop, pageBottom);
      if (visibleHeight > bestVisibleHeight ||
        (visibleHeight === bestVisibleHeight && distanceToTop < bestDistanceToTop)) {
        bestVisibleHeight = visibleHeight;
        bestDistanceToTop = distanceToTop;
        bestPageId = page.id;
      }

    }

    return bestPageId;
  }

  private updateNavigationFocusedPageFromViewport(force: boolean = false): void {
    if (!this.isContinuousDocumentViewEnabled() || this.notebookPageList.length === 0) {
      return;
    }

    const nowTime = Date.now();
    if (!force && this.lastNavigationFocusUpdateTime > 0 &&
      nowTime - this.lastNavigationFocusUpdateTime < DOCUMENT_NAVIGATION_FOCUS_INTERVAL_MS) {
      return;
    }

    const targetZoomScale = this.isDocumentViewportGestureActive
      ? this.documentGestureTargetZoomScale
      : this.documentZoomScale;
    const targetScrollOffsetY = this.isDocumentViewportGestureActive || this.isDocumentPanGestureActive
      ? this.documentGestureTargetScrollOffsetY
      : this.documentScrollOffsetY;
    const targetPageId = this.getViewportCenteredPageIdForViewport(targetScrollOffsetY, targetZoomScale);
    this.lastNavigationFocusUpdateTime = nowTime;
    this.focusNotebookPageForNavigation(targetPageId);
    if (force) {
      this.promoteNavigationPageToActive(targetPageId);
    }
  }

  private async commitViewportCenteredPage(): Promise<void> {
    if (!this.isContinuousDocumentViewEnabled() || this.isLoading || this.isCreatingPage ||
      this.isDeletingPage || this.isReorderingPages || this.isUpdatingPageTemplate) {
      return;
    }

    const targetPageId = this.getViewportCenteredPageId();
    if (targetPageId.length === 0 || targetPageId === this.activePageId) {
      return;
    }

    this.promoteNavigationPageToActive(targetPageId);
  }

  private getDocumentZoomText(): string {
    return `${Math.round(this.documentZoomScale * 100)}%`;
  }

  private getPageCanvasBackgroundColor(pageId: string): string {
    if (pageId === this.activePageId) {
      return this.getActiveCanvasBackgroundColor();
    }

    const cachedCanvas = this.pageCanvasMetadataMap.get(pageId);
    if (cachedCanvas !== undefined && typeof cachedCanvas.backgroundColor === 'string' &&
      cachedCanvas.backgroundColor.length > 0) {
      return cachedCanvas.backgroundColor;
    }

    return '#FFFFFF';
  }

  private getPageFrameBackgroundColor(_pageId: string): string {
    return '#E8EEF6';
  }

  private getPageCanvasBackgroundImageUri(pageId: string): string {
    if (this.activePageCanvas !== null && this.activePageCanvas.pageId === pageId &&
      typeof this.activePageCanvas.backgroundImageUri === 'string') {
      return this.activePageCanvas.backgroundImageUri;
    }

    const cachedCanvas = this.pageCanvasMetadataMap.get(pageId);
    if (cachedCanvas !== undefined && typeof cachedCanvas.backgroundImageUri === 'string') {
      return cachedCanvas.backgroundImageUri;
    }

    return '';
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
      this.captureActiveSessionForThumbnail();
      this.requestThumbnailRender(true);
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
    this.endDocumentPanGesture(false);
    this.endDocumentViewportGesture();
    this.resetPendingDocumentSingleFingerPan();
    this.isDocumentTouchNavigationActive = false;
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

    if (tool === 'edit' || tool === 'lasso') {
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

  private isWorkspaceToolActive(tool: ToolType): boolean {
    return this.toolSetting.tool === tool;
  }

  private toggleCanvasInputMode(): void {
    this.canvasInputMode = this.canvasInputMode === 'stylus' ? 'touch' : 'stylus';
    this.closeTransientDropdowns();
    this.endDocumentPanGesture(false);
    this.endDocumentViewportGesture();
    this.resetPendingDocumentSingleFingerPan();
    this.isDocumentTouchNavigationActive = false;
  }

  private getInputModeButtonLabel(): string {
    return this.canvasInputMode === 'stylus' ? 'Input: Pen' : 'Input: Finger';
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
    EditorSessionRegistry.updateToolSettingForAll(nextSetting);

    if (this.drawingViewModel !== null) {
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
    EditorSessionRegistry.updateToolSettingForAll(nextSetting);

    if (this.drawingViewModel !== null) {
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
      case 'lasso':
        return 'Lasso';
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

  private openNotebookExportDialog(): void {
    if (this.isLoading || this.hasMissingNotebookId || this.isNotebookMissing || this.notebookId.length === 0 ||
      this.isPickingExportPath) {
      return;
    }

    this.closeTransientDropdowns();
    this.draftExportFileName = createNotebookExportBaseName(this.notebookTitle);
    this.draftExportPath = '';
    this.draftExportFormat = 'pdf';
    this.isExportDialogVisible = true;
  }

  private closeNotebookExportDialog(): void {
    if (this.isPickingExportPath) {
      return;
    }

    this.dismissNotebookExportDialog();
  }

  private confirmNotebookExportDialog(): void {
    if (this.isPickingExportPath) {
      return;
    }

    this.dismissNotebookExportDialog();
  }

  private dismissNotebookExportDialog(): void {
    this.isExportDialogVisible = false;
    this.draftExportFileName = '';
    this.draftExportPath = '';
    this.draftExportFormat = 'pdf';
  }

  private async selectNotebookExportPath(): Promise<void> {
    if (this.isPickingExportPath) {
      return;
    }

    const hostContext: common.Context | undefined = this.getUIContext().getHostContext() as common.Context | undefined;
    if (hostContext === undefined) {
      return;
    }

    this.isPickingExportPath = true;
    try {
      const saveOptions = new picker.DocumentSaveOptions();
      saveOptions.newFileNames = [this.getExportPickerBaseFileName()];
      saveOptions.fileSuffixChoices = [buildNotebookExportSuffixChoice(this.draftExportFormat)];
      const documentPicker = new picker.DocumentViewPicker(hostContext);
      const selectedUris: string[] = await documentPicker.save(saveOptions);
      if (selectedUris.length > 0) {
        this.draftExportPath = selectedUris[0];
      }
    } catch (_error) {
    } finally {
      this.isPickingExportPath = false;
    }
  }

  private getExportPickerBaseFileName(): string {
    const cleanName: string = stripNotebookExportExtension(this.draftExportFileName);
    if (cleanName.length > 0) {
      return cleanName;
    }
    return createNotebookExportBaseName(this.notebookTitle);
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
      this.retainThumbnailPages();
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
    this.retainThumbnailPages();
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
    this.retainThumbnailPages();
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

  private getVisualPage(): NotebookPage | null {
    const visualPageId = this.getVisualPageId();
    for (const notebookPage of this.notebookPageList) {
      if (notebookPage.id === visualPageId) {
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

  private isActivePaperSizeTemplate(option: PaperSizeTemplateOption): boolean {
    const activeSize: PageCanvasRenderSize = this.getActiveCanvasBounds();
    const optionSize: PageCanvasRenderSize = this.normalizeCanvasRenderSize(option.width, option.height);
    return activeSize.width === optionSize.width && activeSize.height === optionSize.height;
  }

  private getPaperSizeGlyphScale(option: PaperSizeTemplateOption): number {
    return Math.min(
      30 / Math.max(1, option.width),
      24 / Math.max(1, option.height)
    );
  }

  private getPaperSizeGlyphWidth(option: PaperSizeTemplateOption): number {
    return Math.max(14, Math.round(option.width * this.getPaperSizeGlyphScale(option)));
  }

  private getPaperSizeGlyphHeight(option: PaperSizeTemplateOption): number {
    return Math.max(14, Math.round(option.height * this.getPaperSizeGlyphScale(option)));
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

  private async updateActivePageCanvasSize(option: PaperSizeTemplateOption): Promise<void> {
    if (this.isUpdatingPageTemplate || this.isLoading || this.isCreatingPage || this.isDeletingPage ||
      this.isReorderingPages || this.isCanvasLoading || this.notebookId.length === 0 || this.activePageId.length === 0) {
      return;
    }

    const activePage: NotebookPage | null = this.getActivePage();
    if (activePage === null) {
      return;
    }

    const targetSize: PageCanvasRenderSize = this.normalizeCanvasRenderSize(option.width, option.height);
    if (this.isActivePaperSizeTemplate(option)) {
      this.closePageTemplateDropdown();
      return;
    }

    const pageId: string = activePage.id;
    const rollbackCanvas: NotebookPageCanvas | null = this.cloneNotebookPageCanvas(this.activePageCanvas);
    const cachedRollbackSize = this.pageCanvasRenderSizeMap.get(pageId);
    const rollbackSize: PageCanvasRenderSize | null = cachedRollbackSize === undefined ? null : {
      width: cachedRollbackSize.width,
      height: cachedRollbackSize.height
    };

    this.isUpdatingPageTemplate = true;
    this.closeToolDropdown();
    this.closePageActionMenu();
    this.applyActivePageCanvasSizeLocally(activePage, targetSize.width, targetSize.height);
    this.bumpCanvasVersionForPage(pageId);
    this.documentViewportRefreshVersion += 1;
    this.requestThumbnailRender(true);
    this.closePageTemplateDropdown();

    try {
      const updatedNotebookPageCanvas: NotebookPageCanvas | null = await this.ensureViewModel().updateNotebookPageCanvas(
        this.notebookId,
        pageId,
        targetSize.width,
        targetSize.height
      );

      if (updatedNotebookPageCanvas === null) {
        this.restoreActivePageCanvasAfterFailedSizeUpdate(pageId, rollbackCanvas, rollbackSize);
        return;
      }

      const cachedNotebook: Notebook | null = this.ensureViewModel().getCachedNotebook();
      if (cachedNotebook !== null) {
        this.notebookTitle = cachedNotebook.title;
      }

      this.notebookPageList = this.ensureViewModel().getCachedNotebookPages();
      this.retainThumbnailPages();
      this.syncActivePageId(pageId);
      this.activePageCanvas = updatedNotebookPageCanvas;
      this.cachePageCanvas(pageId, updatedNotebookPageCanvas);
      this.updatePageCanvasRenderSize(pageId, updatedNotebookPageCanvas.width, updatedNotebookPageCanvas.height);
      this.documentHorizontalOffset = this.clampDocumentHorizontalOffset(this.documentHorizontalOffset);
      this.applyDocumentScrollOffset(this.documentScrollOffsetY);
      this.bumpCanvasVersionForPage(pageId);
      this.documentViewportRefreshVersion += 1;
      this.requestThumbnailRender(true);
    } catch (_error) {
      this.restoreActivePageCanvasAfterFailedSizeUpdate(pageId, rollbackCanvas, rollbackSize);
    } finally {
      this.isUpdatingPageTemplate = false;
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

    this.bumpCanvasVersionForPage(pageId);
    this.requestThumbnailRender(true);
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
      this.retainThumbnailPages();
      this.syncActivePageId(pageId);
      this.bumpCanvasVersionForPage(pageId);
      this.requestThumbnailRender(true);
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
    this.retainThumbnailPages();
    this.syncActivePageId(pageId);
    return true;
  }

  private restoreNotebookPageListAfterFailedTemplateUpdate(
    rollbackPageList: NotebookPage[],
    rollbackActivePageId: string
  ): void {
    this.notebookPageList = this.cloneNotebookPageList(rollbackPageList);
    this.retainThumbnailPages();
    this.activePageId = rollbackActivePageId;
    this.syncActivePageId(rollbackActivePageId);
    this.bumpCanvasVersionForPage(rollbackActivePageId);
    this.requestThumbnailRender(true);
  }

  private applyActivePageCanvasSizeLocally(activePage: NotebookPage, width: number, height: number): void {
    const currentTime: number = Date.now();
    const currentCanvas: NotebookPageCanvas | null = this.activePageCanvas;
    this.activePageCanvas = {
      pageId: activePage.id,
      notebookId: activePage.notebookId,
      width: width,
      height: height,
      backgroundColor: currentCanvas === null
        ? NotebookPageCanvasEntity.DEFAULT_BACKGROUND_COLOR
        : currentCanvas.backgroundColor,
      createdAt: currentCanvas === null ? activePage.createdAt : currentCanvas.createdAt,
      updatedAt: currentTime
    };
    this.cachePageCanvas(activePage.id, this.activePageCanvas);
    this.updatePageCanvasRenderSize(activePage.id, width, height);
    this.documentHorizontalOffset = this.clampDocumentHorizontalOffset(this.documentHorizontalOffset);
    this.applyDocumentScrollOffset(this.documentScrollOffsetY);
  }

  private restoreActivePageCanvasAfterFailedSizeUpdate(
    pageId: string,
    rollbackCanvas: NotebookPageCanvas | null,
    rollbackSize: PageCanvasRenderSize | null
  ): void {
    this.activePageCanvas = this.cloneNotebookPageCanvas(rollbackCanvas);
    this.cachePageCanvas(pageId, this.activePageCanvas);
    if (rollbackSize === null) {
      this.pageCanvasRenderSizeMap.delete(pageId);
    } else {
      this.pageCanvasRenderSizeMap.set(pageId, {
        width: rollbackSize.width,
        height: rollbackSize.height
      });
    }
    this.documentHorizontalOffset = this.clampDocumentHorizontalOffset(this.documentHorizontalOffset);
    this.applyDocumentScrollOffset(this.documentScrollOffsetY);
    this.bumpCanvasVersionForPage(pageId);
    this.documentViewportRefreshVersion += 1;
    this.requestThumbnailRender(true);
  }

  private getPageRenderKey(page: NotebookPage): string {
    return `${page.id}_${this.resolvePageTemplateType(page.templateType)}`;
  }

  private getDocumentPageRenderKey(page: NotebookPage): string {
    const cachedSize = this.pageCanvasRenderSizeMap.get(page.id);
    const widthKey = cachedSize === undefined ? NotebookPageCanvasEntity.DEFAULT_WIDTH : cachedSize.width;
    const heightKey = cachedSize === undefined ? NotebookPageCanvasEntity.DEFAULT_HEIGHT : cachedSize.height;
    return `${this.getPageRenderKey(page)}_${widthKey}x${heightKey}`;
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

  private cloneNotebookPageCanvas(notebookPageCanvas: NotebookPageCanvas | null): NotebookPageCanvas | null {
    if (notebookPageCanvas === null) {
      return null;
    }

    return this.cloneNotebookPageCanvasValue(notebookPageCanvas);
  }

  private cloneNotebookPageCanvasValue(notebookPageCanvas: NotebookPageCanvas): NotebookPageCanvas {
    return {
      pageId: notebookPageCanvas.pageId,
      notebookId: notebookPageCanvas.notebookId,
      width: notebookPageCanvas.width,
      height: notebookPageCanvas.height,
      backgroundColor: notebookPageCanvas.backgroundColor,
      createdAt: notebookPageCanvas.createdAt,
      updatedAt: notebookPageCanvas.updatedAt
    };
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
    if (this.isPageVisuallySelected(page.id)) {
      return $r('app.color.editor_thumbnail_active');
    }

    return $r('app.color.editor_thumbnail_background');
  }

  private getPageThumbnailBorderColor(page: NotebookPage): ResourceColor {
    if (this.isPageVisuallySelected(page.id)) {
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
    const visualPage: NotebookPage | null = this.getVisualPage();
    if (visualPage === null) {
      return this.getPageCountText();
    }

    return `${this.getPageCountText()} | Current ${this.getPageLabel(visualPage.order)}`;
  }

  private getActivePageLabel(): string {
    const visualPage: NotebookPage | null = this.getVisualPage();
    if (visualPage === null) {
      return 'Page';
    }
    return this.getPageLabel(visualPage.order);
  }

  private getActivePageIndexText(): string {
    const visualPage: NotebookPage | null = this.getVisualPage();
    if (visualPage === null) {
      return this.getPageCountText();
    }

    return `${visualPage.order + 1}/${this.notebookPageList.length}`;
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

    return {
      width: normalizedWidth,
      height: normalizedHeight
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

  private cloneToolSetting(toolSetting: ToolSetting): ToolSetting {
    return {
      tool: toolSetting.tool,
      color: toolSetting.color,
      width: toolSetting.width,
      opacity: toolSetting.opacity
    };
  }

  private buildEmptySnapshot(pageId: string): EditorDebugSnapshot {
    return {
      instanceId: 0,
      pageId,
      toolSetting: this.cloneToolSetting(this.toolSetting),
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
