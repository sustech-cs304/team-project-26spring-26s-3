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
  @State private isCreateDialogVisible: boolean = false;
  @State private isCreatingNotebook: boolean = false;
  @State private draftNotebookTitle: string = '';
  @State private currentSortType: NotebookSortType = NotebookSortType.UPDATED_DESC;
  private notebookListViewModel?: NotebookListViewModel;

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
      this.currentSortType = await viewModel.loadSortType();
      this.notebookList = await viewModel.loadNotebookList();
    } catch (_error) {
      this.notebookList = [];
      this.currentSortType = NotebookSortType.UPDATED_DESC;
    } finally {
      this.isLoading = false;
    }
  }

  private openCreateDialog(): void {
    this.draftNotebookTitle = '';
    this.isCreateDialogVisible = true;
  }

  private closeCreateDialog(): void {
    if (this.isCreatingNotebook) {
      return;
    }
    this.isCreateDialogVisible = false;
    this.draftNotebookTitle = '';
  }

  private async createNotebook(): Promise<void> {
    if (this.isCreatingNotebook) {
      return;
    }

    this.isCreatingNotebook = true;
    try {
      await this.ensureViewModel().createNotebook(this.draftNotebookTitle);
      this.notebookList = this.ensureViewModel().getCachedNotebookList();
      this.isCreateDialogVisible = false;
      this.draftNotebookTitle = '';
    } catch (_error) {
    } finally {
      this.isCreatingNotebook = false;
    }
  }

  private async changeSortType(sortType: NotebookSortType): Promise<void> {
    if (this.isLoading || this.currentSortType === sortType) {
      return;
    }

    this.isLoading = true;
    this.currentSortType = sortType;
    try {
      this.notebookList = await this.ensureViewModel().changeSortType(sortType);
    } catch (_error) {
    } finally {
      this.isLoading = false;
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
            selectedSortType: this.currentSortType,
            onSortSelected: (sortType: NotebookSortType): void => {
              this.changeSortType(sortType);
            }
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
                NotebookCard({
                  title: notebook.title,
                  updatedAtText: `${$r('app.string.notebook_updated_prefix')}${this.formatTimestamp(notebook.updatedAt)}`
                })
                  .onClick(() => {
                    this.openNotebook(notebook.id);
                  })
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

      if (this.isCreateDialogVisible) {
        Column() {
          CreateNotebookDialog({
            title: $draftNotebookTitle,
            isSubmitting: this.isCreatingNotebook,
            onCancel: (): void => {
              this.closeCreateDialog();
            },
            onConfirm: (): void => {
              this.createNotebook();
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
