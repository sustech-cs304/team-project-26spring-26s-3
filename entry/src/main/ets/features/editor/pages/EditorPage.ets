import common from '@ohos.app.ability.common';
import router from '@ohos.router';
import { AppRouter, RouterParams } from '../../../app/AppRouter';
import { Notebook } from '../../../domain/entities/Notebook';
import { NotebookPage } from '../../../domain/entities/NotebookPage';
import { EditorViewModel } from '../viewmodels/EditorViewModel';

@Entry
@Component
struct EditorPage {
  @State private notebookId: string = '';
  @State private notebookTitle: string = '';
  @State private notebookPageList: NotebookPage[] = [];
  @State private activePageId: string = '';
  @State private isLoading: boolean = true;
  @State private isCreatingPage: boolean = false;
  @State private isDeletePageDialogVisible: boolean = false;
  @State private isDeletingPage: boolean = false;
  @State private deleteTargetPageId: string = '';
  @State private deleteTargetPageLabel: string = '';
  @State private deleteTargetPageOrder: number = -1;
  @State private hasMissingNotebookId: boolean = false;
  @State private isNotebookMissing: boolean = false;
  private editorViewModel?: EditorViewModel;

  aboutToAppear(): void {
    this.loadEditorState();
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
    } catch (_error) {
    } finally {
      this.isCreatingPage = false;
    }
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
    } catch (_error) {
    } finally {
      this.isDeletingPage = false;
      if (hasDeleted) {
        this.resetDeletePageDialogState();
      }
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

  private formatTimestamp(timestamp: number): string {
    const date: Date = new Date(timestamp);
    const year: string = date.getFullYear().toString();
    const month: string = this.padNumber(date.getMonth() + 1);
    const day: string = this.padNumber(date.getDate());
    const hour: string = this.padNumber(date.getHours());
    const minute: string = this.padNumber(date.getMinutes());
    return `${year}-${month}-${day} ${hour}:${minute}`;
  }

  private padNumber(value: number): string {
    if (value >= 10) {
      return value.toString();
    }
    return `0${value.toString()}`;
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

  private getPageCreatedAtText(timestamp: number): string {
    return `创建时间：${this.formatTimestamp(timestamp)}`;
  }

  private getPageUpdatedAtText(timestamp: number): string {
    return `最近更新：${this.formatTimestamp(timestamp)}`;
  }

  private getActivePageCreatedText(): string {
    const activePage: NotebookPage | null = this.getActivePage();
    if (activePage === null) {
      return '';
    }
    return this.getPageCreatedAtText(activePage.createdAt);
  }

  private getDeleteTargetPageText(): string {
    return `页面：${this.deleteTargetPageLabel}`;
  }

  private getPageRenderKey(page: NotebookPage): string {
    return `${page.id}_${page.order.toString()}`;
  }

  build() {
    Stack() {
      Scroll() {
        Column({ space: 20 }) {
        Column({ space: 8 }) {
          if (this.notebookTitle.length > 0) {
            Text(this.notebookTitle)
              .fontSize($r('app.float.hero_title_size'))
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.primary_text'))
          } else {
            Text($r('app.string.editor_page_title'))
              .fontSize($r('app.float.hero_title_size'))
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.primary_text'))
          }

          Text($r('app.string.editor_page_desc'))
            .fontSize($r('app.float.body_text_size'))
            .fontColor($r('app.color.secondary_text'))
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)

        Row({ space: 12 }) {
          if (!this.hasMissingNotebookId && !this.isNotebookMissing) {
            Button(this.isCreatingPage ? $r('app.string.editor_page_adding') : $r('app.string.editor_page_add'))
              .height($r('app.float.button_height'))
              .backgroundColor($r('app.color.primary_text'))
              .fontColor($r('app.color.inverse_text'))
              .enabled(!this.isCreatingPage && !this.isLoading && this.notebookId.length > 0)
              .onClick(() => {
                this.createNotebookPage();
              })
          }

          Button($r('app.string.editor_back_notebooks'))
            .height($r('app.float.button_height'))
            .backgroundColor($r('app.color.app_background'))
            .fontColor($r('app.color.primary_text'))
            .onClick(() => {
              AppRouter.openNotebookList();
            })

          Button($r('app.string.editor_back_home'))
            .height($r('app.float.button_height'))
            .backgroundColor($r('app.color.app_background'))
            .fontColor($r('app.color.primary_text'))
            .onClick(() => {
              AppRouter.goHome();
            })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        if (this.isLoading) {
          Column({ space: 12 }) {
            Text($r('app.string.editor_loading'))
              .fontSize($r('app.float.section_title_size'))
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.primary_text'))

            Text($r('app.string.editor_loading_desc'))
              .fontSize($r('app.float.caption_text_size'))
              .fontColor($r('app.color.secondary_text'))
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding(20)
          .backgroundColor($r('app.color.surface_background'))
          .borderRadius($r('app.float.card_radius'))
          .border({
            width: 1,
            color: $r('app.color.card_border')
          })
        } else if (this.hasMissingNotebookId) {
          Column({ space: 12 }) {
            Text($r('app.string.editor_missing_notebook_title'))
              .fontSize($r('app.float.section_title_size'))
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.primary_text'))

            Text($r('app.string.editor_missing_notebook_desc'))
              .fontSize($r('app.float.body_text_size'))
              .fontColor($r('app.color.secondary_text'))
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding(20)
          .backgroundColor($r('app.color.surface_background'))
          .borderRadius($r('app.float.card_radius'))
          .border({
            width: 1,
            color: $r('app.color.card_border')
          })
        } else if (this.isNotebookMissing) {
          Column({ space: 12 }) {
            Text($r('app.string.editor_not_found_title'))
              .fontSize($r('app.float.section_title_size'))
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.primary_text'))

            Text($r('app.string.editor_not_found_desc'))
              .fontSize($r('app.float.body_text_size'))
              .fontColor($r('app.color.secondary_text'))
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding(20)
          .backgroundColor($r('app.color.surface_background'))
          .borderRadius($r('app.float.card_radius'))
          .border({
            width: 1,
            color: $r('app.color.card_border')
          })
        } else {
          Column({ space: 20 }) {
            Column({ space: 8 }) {
              Text($r('app.string.editor_page_summary_title'))
                .fontSize($r('app.float.section_title_size'))
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.primary_text'))

              Text($r('app.string.editor_page_summary_desc'))
                .fontSize($r('app.float.caption_text_size'))
                .fontColor($r('app.color.secondary_text'))

              Text(this.getPageCountText())
                .fontSize($r('app.float.body_text_size'))
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.primary_text'))
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
            .padding(20)
            .backgroundColor($r('app.color.surface_background'))
            .borderRadius($r('app.float.card_radius'))
            .border({
              width: 1,
              color: $r('app.color.card_border')
            })

            if (this.notebookPageList.length === 0) {
              Column({ space: 12 }) {
                Text($r('app.string.editor_page_empty_title'))
                  .fontSize($r('app.float.section_title_size'))
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.primary_text'))

                Text($r('app.string.editor_page_empty_desc'))
                  .fontSize($r('app.float.body_text_size'))
                  .fontColor($r('app.color.secondary_text'))

                Button(this.isCreatingPage ? $r('app.string.editor_page_adding') : $r('app.string.editor_page_create_first'))
                  .height($r('app.float.button_height'))
                  .backgroundColor($r('app.color.primary_text'))
                  .fontColor($r('app.color.inverse_text'))
                  .enabled(!this.isCreatingPage)
                  .onClick(() => {
                    this.createNotebookPage();
                  })
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)
              .padding(20)
              .backgroundColor($r('app.color.surface_background'))
              .borderRadius($r('app.float.card_radius'))
              .border({
                width: 1,
                color: $r('app.color.card_border')
              })
            } else {
              Column({ space: 12 }) {
                Text($r('app.string.editor_current_page_title'))
                  .fontSize($r('app.float.section_title_size'))
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.primary_text'))

                Column({ space: 8 }) {
                  Text(this.getActivePageLabel())
                    .fontSize($r('app.float.section_title_size'))
                    .fontWeight(FontWeight.Medium)
                    .fontColor($r('app.color.primary_text'))

                  Text($r('app.string.editor_current_page_desc'))
                    .fontSize($r('app.float.caption_text_size'))
                    .fontColor($r('app.color.secondary_text'))

                  Text(this.getActivePageCreatedText())
                    .fontSize($r('app.float.caption_text_size'))
                    .fontColor($r('app.color.secondary_text'))
                }
                .width('100%')
                .alignItems(HorizontalAlign.Start)
                .padding(20)
                .backgroundColor($r('app.color.surface_background'))
                .borderRadius($r('app.float.card_radius'))
                .border({
                  width: 1,
                  color: $r('app.color.primary_text')
                })
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)

              Column({ space: 12 }) {
              Text($r('app.string.editor_page_list_title'))
                  .fontSize($r('app.float.section_title_size'))
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.primary_text'))

                ForEach(this.notebookPageList, (page: NotebookPage) => {
                  Column({ space: 8 }) {
                    Row({ space: 8 }) {
                      Text(this.getPageLabel(page.order))
                        .fontSize($r('app.float.body_text_size'))
                        .fontWeight(FontWeight.Medium)
                        .fontColor($r('app.color.primary_text'))
                        .layoutWeight(1)

                      if (page.id === this.activePageId) {
                        Text($r('app.string.editor_page_current_badge'))
                          .fontSize($r('app.float.caption_text_size'))
                          .fontColor($r('app.color.primary_text'))
                      }

                      Button($r('app.string.editor_page_delete_button'))
                        .height(36)
                        .backgroundColor($r('app.color.danger_surface'))
                        .fontColor($r('app.color.danger_text'))
                        .enabled(!this.isDeletingPage && !this.isCreatingPage)
                        .opacity(this.isDeletingPage || this.isCreatingPage ? 0.7 : 1)
                        .onClick(() => {
                          if (!this.isDeletingPage && !this.isCreatingPage) {
                            this.openDeletePageDialog(page);
                          }
                        })
                    }
                    .width('100%')
                    .alignItems(VerticalAlign.Center)

                    Text(this.getPageCreatedAtText(page.createdAt))
                      .fontSize($r('app.float.caption_text_size'))
                      .fontColor($r('app.color.secondary_text'))

                    Text(this.getPageUpdatedAtText(page.updatedAt))
                      .fontSize($r('app.float.caption_text_size'))
                      .fontColor($r('app.color.secondary_text'))
                  }
                  .width('100%')
                  .alignItems(HorizontalAlign.Start)
                  .padding(20)
                  .backgroundColor($r('app.color.surface_background'))
                  .borderRadius($r('app.float.card_radius'))
                  .border({
                    width: 1,
                    color: page.id === this.activePageId ? $r('app.color.primary_text') : $r('app.color.card_border')
                  })
                }, (page: NotebookPage): string => this.getPageRenderKey(page))
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)
            }
          }
          .width('100%')
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding({
        left: $r('app.float.page_padding_horizontal'),
        right: $r('app.float.page_padding_horizontal'),
        top: $r('app.float.page_padding_vertical'),
        bottom: $r('app.float.page_padding_vertical')
      })
      }
      .width('100%')
      .height('100%')

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

              Button(this.isDeletingPage ? $r('app.string.editor_page_deleting') : $r('app.string.editor_page_delete_button'))
                .layoutWeight(1)
                .height($r('app.float.button_height'))
                .backgroundColor($r('app.color.danger_text'))
                .fontColor($r('app.color.inverse_text'))
                .onClick(() => {
                  this.confirmDeleteSelectedPage();
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
    .backgroundColor($r('app.color.app_background'))
  }
}
