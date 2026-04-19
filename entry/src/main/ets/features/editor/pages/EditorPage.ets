import common from '@ohos.app.ability.common';
import router from '@ohos.router';
import { AppRouter, RouterParams } from '../../../app/AppRouter';
import { Notebook } from '../../../domain/entities/Notebook';
import { NotebookPage } from '../../../domain/entities/NotebookPage';
import { NotebookPageCanvas } from '../../../domain/entities/NotebookPageCanvas';
import { EditorViewModel } from '../viewmodels/EditorViewModel';

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
  @State private isDeletePageDialogVisible: boolean = false;
  @State private isDeletingPage: boolean = false;
  @State private deleteTargetPageId: string = '';
  @State private deleteTargetPageLabel: string = '';
  @State private deleteTargetPageOrder: number = -1;
  @State private hasMissingNotebookId: boolean = false;
  @State private isNotebookMissing: boolean = false;
  private readonly thumbnailGuideLineList: number[] = [0, 1, 2, 3];
  private readonly paperGuideLineList: number[] = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12];
  private editorViewModel?: EditorViewModel;
  private pageCanvasRenderingContextSettings: RenderingContextSettings = new RenderingContextSettings(true);
  private pageCanvasRenderingContext: CanvasRenderingContext2D = new CanvasRenderingContext2D(
    this.pageCanvasRenderingContextSettings
  );

  aboutToAppear(): void {
    void this.loadEditorState();
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
      const routeParams: RouterParams = this.getRouteParams();
      const notebookId: string = typeof routeParams.notebookId === 'string' ? routeParams.notebookId : '';

      if (notebookId.length === 0) {
        this.resetNotebookState();
        this.hasMissingNotebookId = true;
        return;
      }

      this.notebookId = notebookId;
      const notebook: Notebook | null = await this.ensureViewModel().loadNotebook(notebookId);
      if (notebook === null) {
        this.resetNotebookState();
        this.isNotebookMissing = true;
        return;
      }

      this.notebookTitle = notebook.title;
      const viewModel: EditorViewModel = this.ensureViewModel();
      this.notebookPageList = await viewModel.loadNotebookPages(notebookId);
      this.syncActivePageId();
      await this.loadActivePageCanvas();
    } catch (_error) {
      this.resetNotebookState();
      this.isNotebookMissing = this.notebookId.length > 0;
    } finally {
      this.isLoading = false;
    }
  }

  private getRouteParams(): RouterParams {
    try {
      return router.getParams() as RouterParams;
    } catch (_error) {
      return {};
    }
  }

  private resetNotebookState(): void {
    this.notebookId = '';
    this.notebookTitle = '';
    this.notebookPageList = [];
    this.activePageId = '';
    this.activePageCanvas = null;
    this.isCanvasLoading = false;
    this.resetDeletePageDialogState();
  }

  private syncActivePageId(): void {
    if (this.notebookPageList.length === 0) {
      this.activePageId = '';
      return;
    }

    for (const notebookPage of this.notebookPageList) {
      if (notebookPage.id === this.activePageId) {
        return;
      }
    }

    this.activePageId = this.notebookPageList[this.notebookPageList.length - 1].id;
  }

  private async createNotebookPage(): Promise<void> {
    if (this.isCreatingPage || this.notebookId.length === 0) {
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
    if (this.isDeletingPage || this.isCreatingPage || this.isLoading || page.id === this.activePageId) {
      return;
    }

    this.activePageId = page.id;
    await this.loadActivePageCanvas();
  }

  private openDeletePageDialog(page: NotebookPage): void {
    if (this.isDeletingPage || this.isCreatingPage) {
      return;
    }

    this.deleteTargetPageId = page.id;
    this.deleteTargetPageLabel = this.getPageLabel(page.order);
    this.deleteTargetPageOrder = page.order;
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
    if (this.isDeletingPage || this.notebookId.length === 0 || this.deleteTargetPageId.length === 0) {
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

  private getActivePage(): NotebookPage | null {
    for (const notebookPage of this.notebookPageList) {
      if (notebookPage.id === this.activePageId) {
        return notebookPage;
      }
    }
    return null;
  }

  private async loadActivePageCanvas(): Promise<void> {
    if (this.notebookId.length === 0 || this.activePageId.length === 0) {
      this.activePageCanvas = null;
      this.isCanvasLoading = false;
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
      if (this.activePageId === targetPageId) {
        this.activePageCanvas = notebookPageCanvas;
      }
    } catch (_error) {
      if (this.activePageId === targetPageId) {
        this.activePageCanvas = null;
      }
    } finally {
      if (this.activePageId === targetPageId) {
        this.isCanvasLoading = false;
      }
    }
  }

  private formatChineseNumber(value: number): string {
    const digitTextList: string[] = ['零', '一', '二', '三', '四', '五', '六', '七', '八', '九'];
    const unitTextList: string[] = ['', '十', '百', '千'];

    if (value <= 0) {
      return digitTextList[0];
    }

    let remainingValue: number = value;
    let unitIndex: number = 0;
    let result: string = '';
    let shouldFillZero: boolean = false;

    while (remainingValue > 0) {
      const currentDigit: number = remainingValue % 10;
      if (currentDigit === 0) {
        if (result.length > 0) {
          shouldFillZero = true;
        }
      } else {
        let currentPart: string = `${digitTextList[currentDigit]}${unitTextList[unitIndex]}`;
        if (shouldFillZero) {
          currentPart = `零${currentPart}`;
          shouldFillZero = false;
        }
        result = `${currentPart}${result}`;
      }

      remainingValue = Math.floor(remainingValue / 10);
      unitIndex += 1;
    }

    if (result.startsWith('一十')) {
      return result.substring(1);
    }

    return result;
  }

  private getPageLabel(pageOrder: number): string {
    return `第${this.formatChineseNumber(pageOrder + 1)}页`;
  }

  private getActivePageLabel(): string {
    const activePage: NotebookPage | null = this.getActivePage();
    if (activePage === null) {
      return '';
    }
    return this.getPageLabel(activePage.order);
  }

  private getPageCountText(): string {
    return `共 ${this.notebookPageList.length.toString()} 页`;
  }

  private getNotebookSummaryText(): string {
    const activePage: NotebookPage | null = this.getActivePage();
    if (activePage === null) {
      return this.getPageCountText();
    }

    return `${this.getPageCountText()} · 当前 ${this.getPageLabel(activePage.order)}`;
  }

  private getActivePageIndexText(): string {
    const activePage: NotebookPage | null = this.getActivePage();
    if (activePage === null) {
      return this.getPageCountText();
    }

    return `${(activePage.order + 1).toString()}/${this.notebookPageList.length.toString()}`;
  }

  private getActiveCanvasBackgroundColor(): string {
    if (this.activePageCanvas === null) {
      return '#FFFFFF';
    }
    return this.activePageCanvas.backgroundColor;
  }

  private getDeleteTargetPageText(): string {
    return `页面：${this.deleteTargetPageLabel}`;
  }

  private getPageRenderKey(page: NotebookPage): string {
    return `${page.id}_${page.order.toString()}`;
  }

  build() {
    Stack() {
      if (this.isLoading) {
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
      } else if (this.hasMissingNotebookId || this.isNotebookMissing) {
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
      } else {
        Column({ space: 16 }) {
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

          Row({ space: 16 }) {
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

              Scroll() {
                Column({ space: 12 }) {
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
                    ForEach(this.notebookPageList, (page: NotebookPage) => {
                      Column({ space: 10 }) {
                        Column({ space: 10 }) {
                          Row()
                            .width('36%')
                            .height(10)
                            .backgroundColor(page.id === this.activePageId ?
                              $r('app.color.editor_accent_soft') : $r('app.color.app_background'))
                            .borderRadius(999)

                          ForEach(this.thumbnailGuideLineList, (guideIndex: number) => {
                            Row()
                              .width('100%')
                              .height(2)
                              .backgroundColor($r('app.color.editor_thumbnail_line'))
                              .opacity(guideIndex === this.thumbnailGuideLineList.length - 1 ? 0.45 : 0.75)
                              .borderRadius(999)
                          }, (guideIndex: number): string => guideIndex.toString())
                        }
                        .width('100%')
                        .height(132)
                        .padding(14)
                        .alignItems(HorizontalAlign.Start)
                        .backgroundColor($r('app.color.surface_background'))
                        .borderRadius(18)
                        .border({
                          width: 1,
                          color: page.id === this.activePageId ? $r('app.color.editor_accent') :
                            $r('app.color.editor_paper_border')
                        })

                        Row({ space: 8 }) {
                          Text(this.getPageLabel(page.order))
                            .layoutWeight(1)
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
                      .onClick(() => {
                        void this.selectNotebookPage(page);
                      })
                    }, (page: NotebookPage): string => this.getPageRenderKey(page))
                  }
                }
                .width('100%')
                .alignItems(HorizontalAlign.Start)
              }
              .layoutWeight(1)
              .width('100%')

              Button(this.isCreatingPage ? $r('app.string.editor_page_adding') : $r('app.string.editor_page_add'))
                .width('100%')
                .height($r('app.float.button_height'))
                .backgroundColor($r('app.color.editor_accent'))
                .fontColor($r('app.color.inverse_text'))
                .enabled(!this.isCreatingPage && !this.isDeletingPage)
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

                  Button(this.isDeletingPage ? $r('app.string.editor_page_deleting') :
                    $r('app.string.editor_page_delete_current'))
                    .height($r('app.float.button_height'))
                    .backgroundColor($r('app.color.danger_surface'))
                    .fontColor($r('app.color.danger_text'))
                    .enabled(!this.isDeletingPage && !this.isCreatingPage && this.getActivePage() !== null)
                    .onClick(() => {
                      const activePage: NotebookPage | null = this.getActivePage();
                      if (activePage !== null) {
                        this.openDeletePageDialog(activePage);
                      }
                    })
                }
              }
              .width('100%')
              .alignItems(VerticalAlign.Center)

              Stack() {
                Column()
                  .width('100%')
                  .height('100%')
                  .backgroundColor($r('app.color.editor_workspace_background'))
                  .borderRadius(32)

                if (this.notebookPageList.length === 0) {
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
                } else if (this.isCanvasLoading) {
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
                } else if (this.activePageCanvas === null) {
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
                } else {
                  Column({ space: 18 }) {
                    Stack() {
                      Column({ space: 0 }) {
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
                        }
                        .width('100%')
                        .justifyContent(FlexAlign.Start)
                        .padding({
                          left: 24,
                          right: 24,
                          top: 22,
                          bottom: 16
                        })

                        Column({ space: 24 }) {
                          ForEach(this.paperGuideLineList, (guideIndex: number) => {
                            Row()
                              .width('100%')
                              .height(2)
                              .backgroundColor($r('app.color.editor_paper_line'))
                              .opacity(guideIndex === this.paperGuideLineList.length - 1 ? 0.4 : 0.78)
                              .borderRadius(999)
                          }, (guideIndex: number): string => guideIndex.toString())
                        }
                        .width('100%')
                        .layoutWeight(1)
                        .padding({
                          left: 24,
                          right: 24,
                          top: 10,
                          bottom: 24
                        })
                        .alignItems(HorizontalAlign.Start)
                      }
                      .width('100%')
                      .height('100%')
                      .backgroundColor(this.getActiveCanvasBackgroundColor())
                      .borderRadius(30)

                      Canvas(this.pageCanvasRenderingContext)
                        .width('100%')
                        .height('100%')
                    }
                    .width('76%')
                    .height('100%')
                    .constraintSize({ maxWidth: 860 })
                    .borderRadius(30)
                    .border({
                      width: 1,
                      color: $r('app.color.editor_paper_border')
                    })
                  }
                  .width('100%')
                  .height('100%')
                  .padding(24)
                  .justifyContent(FlexAlign.Center)
                  .alignItems(HorizontalAlign.Center)
                }
              }
              .layoutWeight(1)
              .width('100%')
            }
            .layoutWeight(1)
            .height('100%')
            .padding(18)
            .backgroundColor($r('app.color.editor_sidebar_background'))
            .borderRadius(28)
            .border({
              width: 1,
              color: $r('app.color.editor_sidebar_border')
            })
          }
          .layoutWeight(1)
          .width('100%')
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

      if (this.isDeletePageDialogVisible) {
        Column() {
          Column({ space: 16 }) {
            Text($r('app.string.editor_page_delete_confirm_title'))
              .fontSize($r('app.float.section_title_size'))
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.primary_text'))

            Text(this.getDeleteTargetPageText())
              .fontSize($r('app.float.body_text_size'))
              .fontColor($r('app.color.primary_text'))

            Text($r('app.string.editor_page_delete_confirm_desc'))
              .fontSize($r('app.float.caption_text_size'))
              .fontColor($r('app.color.secondary_text'))

            Row({ space: 12 }) {
              Button($r('app.string.dialog_cancel'))
                .layoutWeight(1)
                .height($r('app.float.button_height'))
                .backgroundColor($r('app.color.app_background'))
                .fontColor($r('app.color.primary_text'))
                .onClick(() => {
                  this.closeDeletePageDialog();
                })

              Button(this.isDeletingPage ? $r('app.string.editor_page_deleting') :
                $r('app.string.editor_page_delete_current'))
                .layoutWeight(1)
                .height($r('app.float.button_height'))
                .backgroundColor($r('app.color.danger_text'))
                .fontColor($r('app.color.inverse_text'))
                .onClick(() => {
                  void this.confirmDeleteSelectedPage();
                })
            }
            .width('100%')
          }
          .width('100%')
          .constraintSize({ maxWidth: 560 })
          .alignItems(HorizontalAlign.Start)
          .padding(24)
          .backgroundColor($r('app.color.surface_background'))
          .borderRadius($r('app.float.card_radius'))
          .border({
            width: 1,
            color: $r('app.color.card_border')
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
        .backgroundColor($r('app.color.overlay_mask'))
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.editor_shell_background'))
  }
}
