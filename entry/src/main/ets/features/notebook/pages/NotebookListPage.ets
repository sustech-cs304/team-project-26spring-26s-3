import common from '@ohos.app.ability.common';
import { AppRouter, RouterParams } from '../../../app/AppRouter';
import { Notebook } from '../../../domain/entities/Notebook';
import { NotebookSortType } from '../../../domain/repositories/NotebookRepository';
import { CreateNotebookDialog } from '../components/CreateNotebookDialog';
import { NotebookCard } from '../components/NotebookCard';
import { SortMenu } from '../components/SortMenu';
import { NotebookListViewModel } from '../viewmodels/NotebookListViewModel';

@Entry
@Component
struct NotebookListPage {
  @State private notebookList: Notebook[] = [];
  @State private isLoading: boolean = true;
  @State private isInputDialogVisible: boolean = false;
  @State private isRenameMode: boolean = false;
  @State private isSubmittingDialog: boolean = false;
  @State private draftNotebookTitle: string = '';
  @State private activeNotebookId: string = '';
  @State @Watch('onCurrentSortTypeChanged') private currentSortType: NotebookSortType = NotebookSortType.UPDATED_DESC;
  @State private isDeleteDialogVisible: boolean = false;
  @State private isDeletingNotebook: boolean = false;
  @State private deleteTargetNotebookId: string = '';
  @State private deleteTargetNotebookTitle: string = '';
  private notebookListViewModel?: NotebookListViewModel;
  private shouldHandleSortTypeChange: boolean = false;

  aboutToAppear(): void {
    this.loadNotebookList();
  }

  private ensureViewModel(): NotebookListViewModel {
    if (this.notebookListViewModel === undefined) {
      const hostContext: common.Context | undefined = this.getUIContext().getHostContext() as common.Context | undefined;
      if (hostContext === undefined) {
        throw new Error('Host context is unavailable.');
      }
      this.notebookListViewModel = new NotebookListViewModel(hostContext);
    }

    return this.notebookListViewModel as NotebookListViewModel;
  }

  private async loadNotebookList(): Promise<void> {
    this.isLoading = true;
    try {
      const viewModel: NotebookListViewModel = this.ensureViewModel();
      this.shouldHandleSortTypeChange = false;
      this.currentSortType = await viewModel.loadSortType();
      this.notebookList = await viewModel.loadNotebookList();
    } catch (_error) {
      this.notebookList = [];
      this.currentSortType = NotebookSortType.UPDATED_DESC;
    } finally {
      this.shouldHandleSortTypeChange = true;
      this.isLoading = false;
    }
  }

  private openCreateDialog(): void {
    this.closeDeleteDialog();
    this.activeNotebookId = '';
    this.draftNotebookTitle = '';
    this.isRenameMode = false;
    this.isInputDialogVisible = true;
  }

  private openRenameDialog(notebook: Notebook): void {
    this.closeDeleteDialog();
    this.activeNotebookId = notebook.id;
    this.draftNotebookTitle = notebook.title;
    this.isRenameMode = true;
    this.isInputDialogVisible = true;
  }

  private resetInputDialogState(): void {
    this.isInputDialogVisible = false;
    this.isRenameMode = false;
    this.activeNotebookId = '';
    this.draftNotebookTitle = '';
  }

  private closeInputDialog(): void {
    if (this.isSubmittingDialog) {
      return;
    }
    this.resetInputDialogState();
  }

  private async submitNotebookDialog(): Promise<void> {
    if (this.isSubmittingDialog) {
      return;
    }

    this.isSubmittingDialog = true;
    try {
      if (this.isRenameMode) {
        await this.ensureViewModel().renameNotebook(this.activeNotebookId, this.draftNotebookTitle);
      } else {
        await this.ensureViewModel().createNotebook(this.draftNotebookTitle);
      }
      this.notebookList = this.ensureViewModel().getCachedNotebookList();
      this.closeDeleteDialog();
      this.resetInputDialogState();
    } catch (_error) {
    } finally {
      this.isSubmittingDialog = false;
    }
  }

  private onCurrentSortTypeChanged(): void {
    if (!this.shouldHandleSortTypeChange) {
      return;
    }

    void this.applyCurrentSortType();
  }

  private async applyCurrentSortType(): Promise<void> {
    if (this.isLoading) {
      return;
    }

    this.isLoading = true;
    try {
      this.notebookList = await this.ensureViewModel().changeSortType(this.currentSortType);
    } catch (_error) {
      this.shouldHandleSortTypeChange = false;
      try {
        this.currentSortType = await this.ensureViewModel().loadSortType();
      } catch (_reloadError) {
        this.currentSortType = NotebookSortType.UPDATED_DESC;
      } finally {
        this.shouldHandleSortTypeChange = true;
      }
    } finally {
      this.isLoading = false;
    }
  }

  private openDeleteDialog(notebook: Notebook): void {
    if (this.isDeletingNotebook || this.isSubmittingDialog) {
      return;
    }

    this.deleteTargetNotebookId = notebook.id;
    this.deleteTargetNotebookTitle = notebook.title;
    this.isDeleteDialogVisible = true;
  }

  private closeDeleteDialog(): void {
    if (this.isDeletingNotebook) {
      return;
    }

    this.resetDeleteDialogState();
  }

  private resetDeleteDialogState(): void {
    this.isDeleteDialogVisible = false;
    this.deleteTargetNotebookId = '';
    this.deleteTargetNotebookTitle = '';
  }

  private async confirmDeleteSelectedNotebook(): Promise<void> {
    if (this.isDeletingNotebook || this.deleteTargetNotebookId.length === 0) {
      return;
    }

    let hasDeleted: boolean = false;
    this.isDeletingNotebook = true;
    try {
      hasDeleted = await this.ensureViewModel().deleteNotebook(this.deleteTargetNotebookId);
      this.notebookList = this.ensureViewModel().getCachedNotebookList();
    } catch (_error) {
    } finally {
      this.isDeletingNotebook = false;
      if (hasDeleted) {
        this.resetDeleteDialogState();
      }
    }
  }

  private openNotebook(notebookId: string): void {
    const params: RouterParams = {
      notebookId: notebookId,
      source: 'notebook_list'
    };
    AppRouter.openEditor(params);
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

  build() {
    Stack() {
      Scroll() {
        Column({ space: 20 }) {
          Column({ space: 8 }) {
            Text($r('app.string.notebook_page_title'))
              .fontSize($r('app.float.hero_title_size'))
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.primary_text'))

            Text($r('app.string.notebook_page_desc'))
              .fontSize($r('app.float.body_text_size'))
              .fontColor($r('app.color.secondary_text'))
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')

          Row({ space: 12 }) {
            Column({ space: 4 }) {
              Text($r('app.string.notebook_list_section_title'))
                .fontSize($r('app.float.section_title_size'))
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.primary_text'))

              Text(`${this.notebookList.length} ${$r('app.string.notebook_list_count_suffix')}`)
                .fontSize($r('app.float.caption_text_size'))
                .fontColor($r('app.color.secondary_text'))
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)

            Button($r('app.string.notebook_create_button'))
              .height($r('app.float.button_height'))
              .backgroundColor($r('app.color.primary_text'))
              .fontColor($r('app.color.inverse_text'))
              .onClick(() => {
                this.openCreateDialog();
              })

            Button($r('app.string.notebook_back_home'))
              .height($r('app.float.button_height'))
              .backgroundColor($r('app.color.app_background'))
              .fontColor($r('app.color.primary_text'))
              .onClick(() => {
                AppRouter.goHome();
              })
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)

          SortMenu({
            selectedSortType: $currentSortType
          })

          if (this.isLoading) {
            Column({ space: 12 }) {
              LoadingProgress()
                .width(36)
                .height(36)

              Text($r('app.string.notebook_loading'))
                .fontSize($r('app.float.caption_text_size'))
                .fontColor($r('app.color.secondary_text'))
            }
            .width('100%')
            .padding(32)
            .backgroundColor($r('app.color.surface_background'))
            .borderRadius($r('app.float.card_radius'))
            .border({
              width: 1,
              color: $r('app.color.card_border')
            })
          } else if (this.notebookList.length === 0) {
            Column({ space: 12 }) {
              Text($r('app.string.notebook_empty_title'))
                .fontSize($r('app.float.section_title_size'))
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.primary_text'))

              Text($r('app.string.notebook_empty_desc'))
                .fontSize($r('app.float.body_text_size'))
                .fontColor($r('app.color.secondary_text'))

              Button($r('app.string.notebook_create_first'))
                .height($r('app.float.button_height'))
                .backgroundColor($r('app.color.primary_text'))
                .fontColor($r('app.color.inverse_text'))
                .onClick(() => {
                  this.openCreateDialog();
                })
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
            .padding(24)
            .backgroundColor($r('app.color.surface_background'))
            .borderRadius($r('app.float.card_radius'))
            .border({
              width: 1,
              color: $r('app.color.card_border')
            })
          } else {
            Column({ space: 12 }) {
              ForEach(this.notebookList, (notebook: Notebook) => {
                Column({ space: 12 }) {
                  NotebookCard({
                    title: notebook.title,
                    updatedAtText: `${$r('app.string.notebook_updated_prefix')}${this.formatTimestamp(notebook.updatedAt)}`
                  })

                  Row({ space: 8 }) {
                    Button($r('app.string.notebook_card_open'))
                      .layoutWeight(1)
                      .height($r('app.float.button_height'))
                      .backgroundColor($r('app.color.app_background'))
                      .fontColor($r('app.color.primary_text'))
                      .opacity(this.isDeletingNotebook || this.isSubmittingDialog ? 0.7 : 1)
                      .onClick(() => {
                        if (!this.isDeletingNotebook && !this.isSubmittingDialog) {
                          this.openNotebook(notebook.id);
                        }
                      })

                    Button($r('app.string.notebook_card_rename'))
                      .layoutWeight(1)
                      .height($r('app.float.button_height'))
                      .backgroundColor($r('app.color.app_background'))
                      .fontColor($r('app.color.primary_text'))
                      .opacity(this.isDeletingNotebook || this.isSubmittingDialog ? 0.7 : 1)
                      .onClick(() => {
                        if (!this.isDeletingNotebook && !this.isSubmittingDialog) {
                          this.openRenameDialog(notebook);
                        }
                      })

                    Button($r('app.string.notebook_card_delete'))
                      .layoutWeight(1)
                      .height($r('app.float.button_height'))
                      .backgroundColor($r('app.color.danger_surface'))
                      .fontColor($r('app.color.danger_text'))
                      .opacity(this.isDeletingNotebook || this.isSubmittingDialog ? 0.7 : 1)
                      .onClick(() => {
                        if (!this.isDeletingNotebook && !this.isSubmittingDialog) {
                          this.openDeleteDialog(notebook);
                        }
                      })
                  }
                  .width('100%')
                }
                .width('100%')
              }, (notebook: Notebook): string => notebook.id)
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
      .backgroundColor($r('app.color.app_background'))

      if (this.isDeleteDialogVisible) {
        Column() {
          Column({ space: 16 }) {
            Text($r('app.string.notebook_delete_confirm_title'))
              .fontSize($r('app.float.section_title_size'))
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.primary_text'))

            Text(`${$r('app.string.notebook_delete_target_prefix')}${this.deleteTargetNotebookTitle}`)
              .fontSize($r('app.float.body_text_size'))
              .fontColor($r('app.color.primary_text'))

            Text($r('app.string.notebook_delete_confirm_desc'))
              .fontSize($r('app.float.caption_text_size'))
              .fontColor($r('app.color.secondary_text'))

            Row({ space: 12 }) {
              Button($r('app.string.dialog_cancel'))
                .layoutWeight(1)
                .height($r('app.float.button_height'))
                .backgroundColor($r('app.color.app_background'))
                .fontColor($r('app.color.primary_text'))
                .onClick(() => {
                  this.closeDeleteDialog();
                })

              Button(this.isDeletingNotebook ? $r('app.string.notebook_deleting') : $r('app.string.notebook_delete_confirm'))
                .layoutWeight(1)
                .height($r('app.float.button_height'))
                .backgroundColor($r('app.color.danger_text'))
                .fontColor($r('app.color.inverse_text'))
                .onClick(() => {
                  this.confirmDeleteSelectedNotebook();
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
        .alignItems(HorizontalAlign.Center)
        .padding({
          left: $r('app.float.page_padding_horizontal'),
          right: $r('app.float.page_padding_horizontal'),
          top: $r('app.float.page_padding_vertical'),
          bottom: $r('app.float.page_padding_vertical')
        })
        .backgroundColor($r('app.color.overlay_mask'))
      }

      if (this.isInputDialogVisible) {
        Column() {
          CreateNotebookDialog({
            title: $draftNotebookTitle,
            isRenameMode: this.isRenameMode,
            isSubmitting: this.isSubmittingDialog,
            onCancel: (): void => {
              this.closeInputDialog();
            },
            onConfirm: (): void => {
              this.submitNotebookDialog();
            }
          })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.End)
        .alignItems(HorizontalAlign.Center)
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
