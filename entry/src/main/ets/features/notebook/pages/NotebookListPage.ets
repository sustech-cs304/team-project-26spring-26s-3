import common from '@ohos.app.ability.common';
import { AppRouter, RouterParams } from '../../../app/AppRouter';
import { Notebook } from '../../../domain/entities/Notebook';
import { NotebookFolder } from '../../../domain/entities/NotebookFolder';
import { NotebookSortType } from '../../../domain/repositories/NotebookRepository';
import { CreateFolderDialog } from '../components/CreateFolderDialog';
import { CreateNotebookDialog } from '../components/CreateNotebookDialog';
import { MoveNotebookDialog } from '../components/MoveNotebookDialog';
import { NotebookCard } from '../components/NotebookCard';
import { SortMenu } from '../components/SortMenu';
import { NotebookListViewModel } from '../viewmodels/NotebookListViewModel';

@Entry
@Component
struct NotebookListPage {
  @State private notebookList: Notebook[] = [];
  @State private notebookListRenderVersion: number = 0;
  @State private folderList: NotebookFolder[] = [];
  @State private folderListRenderVersion: number = 0;
  @State private isLoading: boolean = true;
  @State private isInputDialogVisible: boolean = false;
  @State private isRenameMode: boolean = false;
  @State private isSubmittingDialog: boolean = false;
  @State private draftNotebookTitle: string = '';
  @State private activeNotebookId: string = '';
  @State private currentSortType: NotebookSortType = NotebookSortType.UPDATED_DESC;
  @State private isDeleteDialogVisible: boolean = false;
  @State private isDeletingNotebook: boolean = false;
  @State private deleteTargetNotebookId: string = '';
  @State private deleteTargetNotebookTitle: string = '';
  @State private isFolderDialogVisible: boolean = false;
  @State private isCreatingFolder: boolean = false;
  @State private draftFolderTitle: string = '';
  @State private isMoveDialogVisible: boolean = false;
  @State private isMovingNotebook: boolean = false;
  @State private moveTargetNotebookId: string = '';
  @State private moveTargetNotebookTitle: string = '';
  @State private selectedFolderId: string = '';
  private notebookListViewModel?: NotebookListViewModel;
  private hasLoadedInitialNotebookList: boolean = false;

  aboutToAppear(): void {
    if (!this.hasLoadedInitialNotebookList) {
      void this.loadNotebookList();
    }
  }

  onPageShow(): void {
    if (!this.hasLoadedInitialNotebookList || this.isLoading) {
      return;
    }

    void this.loadNotebookList();
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
      this.applyFolderList(await viewModel.loadFolderList());
      this.applyNotebookList(await viewModel.loadNotebookList());
    } catch (_error) {
      this.applyFolderList([]);
      this.applyNotebookList([]);
      this.currentSortType = NotebookSortType.UPDATED_DESC;
    } finally {
      this.hasLoadedInitialNotebookList = true;
      this.isLoading = false;
    }
  }

  private applyNotebookList(notebookList: Notebook[]): void {
    this.notebookList = notebookList;
    this.notebookListRenderVersion += 1;
  }

  private applyFolderList(folderList: NotebookFolder[]): void {
    this.folderList = folderList;
    this.folderListRenderVersion += 1;
  }

  private async refreshNotebookCollection(): Promise<void> {
    const viewModel: NotebookListViewModel = this.ensureViewModel();
    this.applyFolderList(await viewModel.loadFolderList());
    this.applyNotebookList(await viewModel.loadNotebookList());
  }

  private isActionBusy(): boolean {
    return this.isDeletingNotebook || this.isSubmittingDialog || this.isCreatingFolder || this.isMovingNotebook;
  }

  private dismissNotebookDialog(): void {
    this.isInputDialogVisible = false;
    this.isRenameMode = false;
    this.activeNotebookId = '';
    this.draftNotebookTitle = '';
  }

  private dismissDeleteDialog(): void {
    this.isDeleteDialogVisible = false;
    this.deleteTargetNotebookId = '';
    this.deleteTargetNotebookTitle = '';
  }

  private dismissFolderDialog(): void {
    this.isFolderDialogVisible = false;
    this.draftFolderTitle = '';
  }

  private dismissMoveDialog(): void {
    this.isMoveDialogVisible = false;
    this.isMovingNotebook = false;
    this.moveTargetNotebookId = '';
    this.moveTargetNotebookTitle = '';
    this.selectedFolderId = '';
  }

  private closePassiveDialogs(): void {
    if (!this.isDeletingNotebook) {
      this.dismissDeleteDialog();
    }

    if (!this.isCreatingFolder) {
      this.dismissFolderDialog();
    }

    if (!this.isMovingNotebook) {
      this.dismissMoveDialog();
    }
  }

  private openCreateDialog(): void {
    if (this.isActionBusy()) {
      return;
    }

    this.closePassiveDialogs();
    this.activeNotebookId = '';
    this.draftNotebookTitle = '';
    this.isRenameMode = false;
    this.isInputDialogVisible = true;
  }

  private openRenameDialog(notebook: Notebook): void {
    if (this.isActionBusy()) {
      return;
    }

    this.closePassiveDialogs();
    this.activeNotebookId = notebook.id;
    this.draftNotebookTitle = notebook.title;
    this.isRenameMode = true;
    this.isInputDialogVisible = true;
  }

  private closeInputDialog(): void {
    if (this.isSubmittingDialog) {
      return;
    }

    this.dismissNotebookDialog();
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
      await this.refreshNotebookCollection();
      this.dismissDeleteDialog();
      this.dismissNotebookDialog();
    } catch (_error) {
    } finally {
      this.isSubmittingDialog = false;
    }
  }

  private openFolderDialog(): void {
    if (this.isActionBusy()) {
      return;
    }

    this.closeInputDialog();
    this.dismissDeleteDialog();
    this.dismissMoveDialog();
    this.draftFolderTitle = '';
    this.isFolderDialogVisible = true;
  }

  private closeFolderDialog(): void {
    if (this.isCreatingFolder) {
      return;
    }

    this.dismissFolderDialog();
  }

  private async submitFolderDialog(): Promise<void> {
    if (this.isCreatingFolder) {
      return;
    }

    this.isCreatingFolder = true;
    try {
      await this.ensureViewModel().createFolder(this.draftFolderTitle);
      await this.refreshNotebookCollection();
      this.dismissFolderDialog();
    } catch (_error) {
    } finally {
      this.isCreatingFolder = false;
    }
  }

  private openMoveDialog(notebook: Notebook): void {
    if (this.isActionBusy()) {
      return;
    }

    this.closeInputDialog();
    this.dismissDeleteDialog();
    this.dismissFolderDialog();
    this.moveTargetNotebookId = notebook.id;
    this.moveTargetNotebookTitle = notebook.title;
    this.selectedFolderId = this.hasFolder(notebook.folderId) ? notebook.folderId : '';
    this.isMoveDialogVisible = true;
  }

  private closeMoveDialog(): void {
    if (this.isMovingNotebook) {
      return;
    }

    this.dismissMoveDialog();
  }

  private async confirmMoveSelectedNotebook(): Promise<void> {
    if (this.isMovingNotebook || this.moveTargetNotebookId.length === 0) {
      return;
    }

    this.isMovingNotebook = true;
    try {
      await this.ensureViewModel().moveNotebookToFolder(this.moveTargetNotebookId, this.selectedFolderId);
      await this.refreshNotebookCollection();
      this.dismissMoveDialog();
    } catch (_error) {
      this.isMovingNotebook = false;
    }
  }

  private onSortTypeSelected(sortType: NotebookSortType): void {
    if (this.currentSortType === sortType || this.isLoading) {
      return;
    }

    void this.applyCurrentSortType(sortType);
  }

  private async applyCurrentSortType(sortType: NotebookSortType): Promise<void> {
    const previousSortType: NotebookSortType = this.currentSortType;
    this.currentSortType = sortType;
    this.isLoading = true;
    try {
      this.applyNotebookList(await this.ensureViewModel().changeSortType(sortType));
    } catch (_error) {
      try {
        this.currentSortType = await this.ensureViewModel().loadSortType();
      } catch (_reloadError) {
        this.currentSortType = previousSortType;
      }
    } finally {
      this.isLoading = false;
    }
  }

  private openDeleteDialog(notebook: Notebook): void {
    if (this.isActionBusy()) {
      return;
    }

    this.closeInputDialog();
    this.dismissFolderDialog();
    this.dismissMoveDialog();
    this.deleteTargetNotebookId = notebook.id;
    this.deleteTargetNotebookTitle = notebook.title;
    this.isDeleteDialogVisible = true;
  }

  private closeDeleteDialog(): void {
    if (this.isDeletingNotebook) {
      return;
    }

    this.dismissDeleteDialog();
  }

  private async confirmDeleteSelectedNotebook(): Promise<void> {
    if (this.isDeletingNotebook || this.deleteTargetNotebookId.length === 0) {
      return;
    }

    let hasDeleted: boolean = false;
    this.isDeletingNotebook = true;
    try {
      hasDeleted = await this.ensureViewModel().deleteNotebook(this.deleteTargetNotebookId);
      await this.refreshNotebookCollection();
    } catch (_error) {
    } finally {
      this.isDeletingNotebook = false;
      if (hasDeleted) {
        this.dismissDeleteDialog();
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

  private getNotebookCountText(): string {
    return `${this.notebookList.length.toString()} 个笔记本`;
  }

  private getFolderCountText(): string {
    return `${this.folderList.length.toString()} 个文件夹`;
  }

  private getNotebookUpdatedAtText(timestamp: number): string {
    return `最近更新：${this.formatTimestamp(timestamp)}`;
  }

  private getDeleteTargetText(): string {
    return `笔记本：${this.deleteTargetNotebookTitle}`;
  }

  private hasFolder(folderId: string): boolean {
    if (folderId.length === 0) {
      return false;
    }

    for (const folder of this.folderList) {
      if (folder.id === folderId) {
        return true;
      }
    }

    return false;
  }

  private isNotebookUngrouped(notebook: Notebook): boolean {
    return notebook.folderId.length === 0 || !this.hasFolder(notebook.folderId);
  }

  private getUngroupedNotebookList(): Notebook[] {
    const ungroupedNotebookList: Notebook[] = [];
    for (const notebook of this.notebookList) {
      if (this.isNotebookUngrouped(notebook)) {
        ungroupedNotebookList.push(notebook);
      }
    }

    return ungroupedNotebookList;
  }

  private getFolderNotebookList(folderId: string): Notebook[] {
    const folderNotebookList: Notebook[] = [];
    for (const notebook of this.notebookList) {
      if (notebook.folderId === folderId) {
        folderNotebookList.push(notebook);
      }
    }

    return folderNotebookList;
  }

  private getFolderNotebookCountText(folderId: string): string {
    return `${this.getFolderNotebookList(folderId).length.toString()} 个笔记本`;
  }

  private hasNotebookContent(): boolean {
    return this.notebookList.length > 0 || this.folderList.length > 0;
  }

  @Builder
  private buildNotebookItem(notebook: Notebook): void {
    Column({ space: 12 }) {
      NotebookCard({
        title: notebook.title,
        updatedAtText: this.getNotebookUpdatedAtText(notebook.updatedAt)
      })

      Row({ space: 8 }) {
        Button($r('app.string.notebook_card_open'))
          .layoutWeight(1)
          .height($r('app.float.button_height'))
          .backgroundColor($r('app.color.app_background'))
          .fontColor($r('app.color.primary_text'))
          .opacity(this.isActionBusy() ? 0.7 : 1)
          .onClick(() => {
            if (!this.isActionBusy()) {
              this.openNotebook(notebook.id);
            }
          })

        Button($r('app.string.notebook_card_rename'))
          .layoutWeight(1)
          .height($r('app.float.button_height'))
          .backgroundColor($r('app.color.app_background'))
          .fontColor($r('app.color.primary_text'))
          .opacity(this.isActionBusy() ? 0.7 : 1)
          .onClick(() => {
            if (!this.isActionBusy()) {
              this.openRenameDialog(notebook);
            }
          })
      }
      .width('100%')

      Row({ space: 8 }) {
        Button($r('app.string.notebook_card_move'))
          .layoutWeight(1)
          .height($r('app.float.button_height'))
          .backgroundColor($r('app.color.app_background'))
          .fontColor($r('app.color.primary_text'))
          .opacity(this.isActionBusy() ? 0.7 : 1)
          .onClick(() => {
            if (!this.isActionBusy()) {
              this.openMoveDialog(notebook);
            }
          })

        Button($r('app.string.notebook_card_delete'))
          .layoutWeight(1)
          .height($r('app.float.button_height'))
          .backgroundColor($r('app.color.danger_surface'))
          .fontColor($r('app.color.danger_text'))
          .opacity(this.isActionBusy() ? 0.7 : 1)
          .onClick(() => {
            if (!this.isActionBusy()) {
              this.openDeleteDialog(notebook);
            }
          })
      }
      .width('100%')
    }
    .width('100%')
  }

  @Builder
  private buildFolderCard(folder: NotebookFolder): void {
    Column({ space: 12 }) {
      Column({ space: 4 }) {
        Text(folder.title)
          .fontSize($r('app.float.section_title_size'))
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.primary_text'))

        Text(this.getFolderNotebookCountText(folder.id))
          .fontSize($r('app.float.caption_text_size'))
          .fontColor($r('app.color.secondary_text'))
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      if (this.getFolderNotebookList(folder.id).length === 0) {
        Text($r('app.string.folder_card_empty_desc'))
          .width('100%')
          .fontSize($r('app.float.caption_text_size'))
          .fontColor($r('app.color.secondary_text'))
      } else {
        Column({ space: 12 }) {
          ForEach(this.getFolderNotebookList(folder.id), (notebook: Notebook) => {
            this.buildNotebookItem(notebook)
          }, (notebook: Notebook): string => `${this.notebookListRenderVersion}-${notebook.id}`)
        }
        .width('100%')
      }
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
  }

  @Builder
  private buildFolderSection(): void {
    Column({ space: 12 }) {
      Row({ space: 12 }) {
        Column({ space: 4 }) {
          Text($r('app.string.folder_section_title'))
            .fontSize($r('app.float.section_title_size'))
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.primary_text'))

          Text(this.getFolderCountText())
            .fontSize($r('app.float.caption_text_size'))
            .fontColor($r('app.color.secondary_text'))
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Button($r('app.string.folder_create_button'))
          .height($r('app.float.button_height'))
          .backgroundColor($r('app.color.app_background'))
          .fontColor($r('app.color.primary_text'))
          .onClick(() => {
            this.openFolderDialog();
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Text($r('app.string.folder_section_desc'))
        .width('100%')
        .fontSize($r('app.float.caption_text_size'))
        .fontColor($r('app.color.secondary_text'))

      if (this.folderList.length === 0) {
        Column({ space: 12 }) {
          Text($r('app.string.folder_empty_desc'))
            .width('100%')
            .fontSize($r('app.float.body_text_size'))
            .fontColor($r('app.color.secondary_text'))

          Button($r('app.string.folder_create_first'))
            .height($r('app.float.button_height'))
            .backgroundColor($r('app.color.primary_text'))
            .fontColor($r('app.color.inverse_text'))
            .onClick(() => {
              this.openFolderDialog();
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
          ForEach(this.folderList, (folder: NotebookFolder) => {
            this.buildFolderCard(folder)
          }, (folder: NotebookFolder): string => `${this.folderListRenderVersion}-${folder.id}`)
        }
        .width('100%')
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private buildUngroupedNotebookSection(): void {
    if (this.getUngroupedNotebookList().length > 0 || this.folderList.length === 0) {
      Column({ space: 12 }) {
        Column({ space: 4 }) {
          Text($r('app.string.folder_uncategorized_title'))
            .fontSize($r('app.float.section_title_size'))
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.primary_text'))

          Text(`${this.getUngroupedNotebookList().length.toString()} 个笔记本`)
            .fontSize($r('app.float.caption_text_size'))
            .fontColor($r('app.color.secondary_text'))
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)

        if (this.getUngroupedNotebookList().length === 0) {
          Text($r('app.string.folder_option_uncategorized'))
            .width('100%')
            .fontSize($r('app.float.caption_text_size'))
            .fontColor($r('app.color.secondary_text'))
        } else {
          Column({ space: 12 }) {
            ForEach(this.getUngroupedNotebookList(), (notebook: Notebook) => {
              this.buildNotebookItem(notebook)
            }, (notebook: Notebook): string => `${this.notebookListRenderVersion}-${notebook.id}`)
          }
          .width('100%')
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
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

              Text(this.getNotebookCountText())
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
            onSortTypeChange: (sortType: NotebookSortType): void => {
              this.onSortTypeSelected(sortType);
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
          } else if (!this.hasNotebookContent()) {
            Column({ space: 12 }) {
              Text($r('app.string.notebook_empty_title'))
                .fontSize($r('app.float.section_title_size'))
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.primary_text'))

              Text($r('app.string.notebook_empty_desc'))
                .fontSize($r('app.float.body_text_size'))
                .fontColor($r('app.color.secondary_text'))

              Row({ space: 12 }) {
                Button($r('app.string.notebook_create_first'))
                  .layoutWeight(1)
                  .height($r('app.float.button_height'))
                  .backgroundColor($r('app.color.primary_text'))
                  .fontColor($r('app.color.inverse_text'))
                  .onClick(() => {
                    this.openCreateDialog();
                  })

                Button($r('app.string.folder_create_first'))
                  .layoutWeight(1)
                  .height($r('app.float.button_height'))
                  .backgroundColor($r('app.color.app_background'))
                  .fontColor($r('app.color.primary_text'))
                  .onClick(() => {
                    this.openFolderDialog();
                  })
              }
              .width('100%')
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
            this.buildFolderSection()
            this.buildUngroupedNotebookSection()
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

            Text(this.getDeleteTargetText())
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

      if (this.isFolderDialogVisible) {
        Column() {
          CreateFolderDialog({
            title: $draftFolderTitle,
            isSubmitting: this.isCreatingFolder,
            onCancel: (): void => {
              this.closeFolderDialog();
            },
            onConfirm: (): void => {
              this.submitFolderDialog();
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

      if (this.isMoveDialogVisible) {
        Column() {
          MoveNotebookDialog({
            selectedFolderId: $selectedFolderId,
            notebookTitle: this.moveTargetNotebookTitle,
            folderList: this.folderList,
            isSubmitting: this.isMovingNotebook,
            onCancel: (): void => {
              this.closeMoveDialog();
            },
            onConfirm: (): void => {
              this.confirmMoveSelectedNotebook();
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
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.app_background'))
  }
}
