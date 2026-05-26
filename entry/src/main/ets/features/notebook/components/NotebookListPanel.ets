import common from '@ohos.app.ability.common';
import picker from '@ohos.file.picker';
import { AppRouter, RouterParams } from '../../../app/AppRouter';
import { ImageAssetDataSource, ImportedImageAsset } from '../../../data/sources/local/ImageAssetDataSource';
import { Notebook, NotebookEntity } from '../../../domain/entities/Notebook';
import { NotebookFolder, NotebookFolderEntity } from '../../../domain/entities/NotebookFolder';
import { NotebookPage, NotebookPageTemplateType } from '../../../domain/entities/NotebookPage';
import { NotebookPageCanvas, NotebookPageCanvasEntity } from '../../../domain/entities/NotebookPageCanvas';
import { NotebookSortType } from '../../../domain/repositories/NotebookRepository';
import { PageThumbnailCanvas } from '../../editor/components/PageThumbnailCanvas';
import {
  createEmptyPageThumbnailRenderSnapshot,
  PageThumbnailRenderSnapshot
} from '../../editor/controllers/PageThumbnailRenderer';
import { PageThumbnailStore } from '../../editor/viewmodels/PageThumbnailStore';
import { CreateFolderDialog } from './CreateFolderDialog';
import { CreateNotebookDialog } from './CreateNotebookDialog';
import { MoveNotebookDialog } from './MoveNotebookDialog';
import { NotebookExportDialog } from './NotebookExportDialog';
import {
  buildNotebookExportSuffixChoice,
  createNotebookExportBaseName,
  stripNotebookExportExtension
} from '../models/NotebookExportOptions';
import { NotebookExportResult, NotebookExportService } from '../services/NotebookExportService';
import { NotebookImportService } from '../services/NotebookImportService';
import { NotebookListViewModel } from '../viewmodels/NotebookListViewModel';

enum SidebarSection {
  ALL = 'all',
  RECENT = 'recent',
  FAVORITES = 'favorites',
  FOLDERS = 'folders',
  TAGS = 'tags',
  RECYCLE = 'recycle'
}

enum AllNotesTimeRange {
  ALL = 'all',
  TODAY = 'today',
  LAST_7_DAYS = 'last_7_days',
  LAST_30_DAYS = 'last_30_days'
}

enum AllNotesSortFilterType {
  TAG = 'tag',
  CREATED_AT = 'created_at',
  UPDATED_AT = 'updated_at'
}

enum TagChipDisplayMode {
  COMPACT = 'compact',
  ROOMY = 'roomy'
}

enum TagDialogMode {
  MENU = 'menu',
  ADD = 'add',
  EDIT_PICK = 'edit_pick',
  EDIT_FORM = 'edit_form',
  DELETE_PICK = 'delete_pick',
  CONFIRM = 'confirm'
}

enum PendingTagOperation {
  NONE = 'none',
  ADD = 'add',
  EDIT = 'edit',
  DELETE = 'delete'
}

class ActionMenuAnchor {
  notebookId: string = '';
  left: number = 0;
  top: number = 0;
  width: number = 0;
  height: number = 0;
}

class FolderActionMenuAnchor {
  folderId: string = '';
  left: number = 0;
  top: number = 0;
  width: number = 0;
  height: number = 0;
}

class MenuPosition {
  x: Length = 0;
  y: Length = 0;
}

class WorkspaceToolMenuAnchor {
  left: number = 0;
  top: number = 0;
  width: number = 0;
  height: number = 0;
}

@Component
export struct NotebookListPanel {
  @Prop @Watch('onReloadNotebookSignalChanged') reloadNotebookSignal: number = 0;
  @Prop @Watch('onSearchTextChanged') searchText: string = '';
  @Prop isSidebarCollapsed: boolean = false;
  private readonly actionMenuWidth: number = 236;
  private readonly actionMenuHeight: number = 300;
  private readonly actionMenuGap: number = 8;
  private readonly folderActionMenuWidth: number = 188;
  private readonly folderActionMenuHeight: number = 154;
  private readonly folderActionMenuGap: number = 8;
  private readonly sortMenuWidth: number = 130;
  private readonly sortMenuHeight: number = 114;
  private readonly workspaceToolButtonSize: number = 36;
  private readonly defaultWorkspaceWidth: number = 960;
  private readonly defaultPanelWidth: number = 1200;
  private readonly defaultPanelHeight: number = 800;
  private readonly landscapeSidebarWidth: number = 230;
  private readonly portraitSidebarWidth: number = 161.2;
  private readonly workspacePanelPadding: number = 16;
  private readonly gridCardHorizontalInset: number = 4;
  private readonly oneMinuteMs: number = 60 * 1000;
  private readonly oneHourMs: number = 60 * 60 * 1000;
  private readonly oneDayMs: number = 24 * 60 * 60 * 1000;
  private readonly oneWeekMs: number = 7 * 24 * 60 * 60 * 1000;
  private readonly oneMonthMs: number = 30 * 24 * 60 * 60 * 1000;
  private readonly oneYearMs: number = 365 * 24 * 60 * 60 * 1000;
  private readonly maxNotebookTagCount: number = 4;
  private readonly compactTagChineseLimit: number = 2;
  private readonly compactTagAsciiLimit: number = 4;
  private readonly roomyTagChineseLimit: number = 4;
  private readonly roomyTagAsciiLimit: number = 8;
  private readonly recentNotebookCardHeight: number = 304;
  private readonly recentCoverSlotMaxSize: number = 192;

  @State private notebookList: Notebook[] = [];
  @State private notebookListRenderVersion: number = 0;
  @State private folderList: NotebookFolder[] = [];
  @State private folderListRenderVersion: number = 0;
  @State private isLoading: boolean = true;
  @State private importFailureMessage: string = '';
  @State private currentSection: SidebarSection = SidebarSection.ALL;
  @State private selectedTag: string = '';
  @State private selectedFolderInSidebar: string = '';
  @State private activeActionMenuNotebookId: string = '';
  @State private activeFolderActionMenuFolderId: string = '';
  @State private useLargeNotebookCards: boolean = true;
  @State private isTopSortDropdownVisible: boolean = false;
  @State private topSortMenuAnchor: WorkspaceToolMenuAnchor = new WorkspaceToolMenuAnchor();
  @State private allNotesSortFilterType: AllNotesSortFilterType = AllNotesSortFilterType.UPDATED_AT;
  @State private allNotesCreatedTimeRange: AllNotesTimeRange = AllNotesTimeRange.ALL;
  @State private allNotesUpdatedTimeRange: AllNotesTimeRange = AllNotesTimeRange.ALL;
  @State private allNotesSelectedTagFilter: string = '';
  @State private isAllNotesSortFilterPanelVisible: boolean = false;
  @State private workspaceAreaLeft: number = 0;
  @State private workspaceAreaTop: number = 0;
  @State private workspaceAreaWidth: number = 0;
  @State private workspaceAreaHeight: number = 0;
  @State private panelAreaWidth: number = 0;
  @State private panelAreaHeight: number = 0;
  @State private workspaceScrollOffsetY: number = 0;
  @State private actionMenuAnchors: ActionMenuAnchor[] = [];
  @State private folderActionMenuAnchors: FolderActionMenuAnchor[] = [];
  @State private isCreateActionMenuVisible: boolean = false;
  @State private createActionMenuAnchor: ActionMenuAnchor = new ActionMenuAnchor();

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
  @State private draftFolderColor: string = NotebookFolderEntity.DEFAULT_COLOR;
  @State private isFolderRenameDialogVisible: boolean = false;
  @State private draftFolderRenameTitle: string = '';
  @State private folderRenameTargetId: string = '';
  @State private isRenamingFolder: boolean = false;
  @State private isFolderColorDialogVisible: boolean = false;
  @State private folderColorTargetId: string = '';
  @State private draftFolderEditColor: string = NotebookFolderEntity.DEFAULT_COLOR;
  @State private folderEditColorR: number = 124;
  @State private folderEditColorG: number = 155;
  @State private folderEditColorB: number = 255;
  @State private isUpdatingFolderColor: boolean = false;
  @State private isFolderDeleteDialogVisible: boolean = false;
  @State private folderDeleteTargetId: string = '';
  @State private folderDeleteTargetTitle: string = '';
  @State private isDeletingFolder: boolean = false;
  @State private isPickingNotebookCover: boolean = false;
  @State private isNotebookCoverDialogVisible: boolean = false;
  @State private notebookCoverTargetId: string = '';
  @State private notebookCoverTargetTitle: string = '';
  @State private draftNotebookColor: string = NotebookEntity.DEFAULT_COVER_COLOR;
  @State private notebookColorR: number = 124;
  @State private notebookColorG: number = 155;
  @State private notebookColorB: number = 255;
  @State private isUpdatingNotebookCover: boolean = false;

  @State private isMoveDialogVisible: boolean = false;
  @State private isMovingNotebook: boolean = false;
  @State private moveTargetNotebookId: string = '';
  @State private moveTargetNotebookTitle: string = '';
  @State private selectedFolderId: string = '';

  @State private isTagDialogVisible: boolean = false;
  @State private isUpdatingTags: boolean = false;
  @State private tagTargetNotebookId: string = '';
  @State private tagTargetNotebookTitle: string = '';
  @State private tagDialogMode: TagDialogMode = TagDialogMode.MENU;
  @State private tagDraftText: string = '';
  @State private tagSelectedText: string = '';
  @State private tagDialogMessage: string = '';
  @State private pendingTagOperation: PendingTagOperation = PendingTagOperation.NONE;
  @State private pendingTagOldText: string = '';
  @State private pendingTagNewText: string = '';

  @State private isExportDialogVisible: boolean = false;
  @State private isPickingExportPath: boolean = false;
  @State private isExportingNotebook: boolean = false;
  @State private exportFailureMessage: string = '';
  @State private exportTargetNotebookId: string = '';
  @State private exportTargetNotebookTitle: string = '';
  @State private draftExportFileName: string = '';
  @State private draftExportPath: string = '';
  @State private draftExportFormat: string = 'pdf';
  @State private draftExportScope: string = 'all';
  @State private draftExportPageRange: string = '';

  private notebookListViewModel?: NotebookListViewModel;
  private notebookImportService?: NotebookImportService;
  private notebookExportService?: NotebookExportService;
  private pageThumbnailStore?: PageThumbnailStore;
  private hasLoadedInitialNotebookList: boolean = false;
  @State private notebookCoverRenderTick: number = 0;
  @State private searchContentRenderVersion: number = 0;
  @State private isSearchContentLoading: boolean = false;
  private readonly notebookCoverPageMap: Map<string, NotebookPage> = new Map<string, NotebookPage>();
  private readonly notebookCoverCanvasMap: Map<string, NotebookPageCanvas> = new Map<string, NotebookPageCanvas>();
  private readonly notebookCoverLoadingIds: Set<string> = new Set<string>();
  private readonly notebookSearchContentMap: Map<string, string> = new Map<string, string>();
  private readonly notebookSearchContentUpdatedAtMap: Map<string, number> = new Map<string, number>();
  private readonly notebookSearchContentLoadingIds: Set<string> = new Set<string>();

  aboutToAppear(): void {
    if (!this.hasLoadedInitialNotebookList) {
      void this.loadNotebookList();
      return;
    }

    void this.refreshNotebookCollection();
  }

  private onReloadNotebookSignalChanged(): void {
    if (!this.hasLoadedInitialNotebookList || this.isLoading) {
      return;
    }

    void this.refreshNotebookCollection();
  }

  private onSearchTextChanged(): void {
    if (!this.hasSearchQuery()) {
      this.isSearchContentLoading = false;
      return;
    }

    this.closeActionMenu();
    this.closeFolderActionMenu();
    this.closeCreateActionMenu();
    this.closeTopSortDropdown();
    void this.ensureSearchContentForActiveNotebooks();
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

  private ensureImportService(): NotebookImportService {
    if (this.notebookImportService === undefined) {
      const hostContext: common.Context | undefined = this.getUIContext().getHostContext() as common.Context | undefined;
      if (hostContext === undefined) {
        throw new Error('Host context is unavailable.');
      }
      this.notebookImportService = new NotebookImportService(hostContext);
    }

    return this.notebookImportService as NotebookImportService;
  }

  private ensureExportService(): NotebookExportService {
    if (this.notebookExportService === undefined) {
      const hostContext: common.Context | undefined = this.getUIContext().getHostContext() as common.Context | undefined;
      if (hostContext === undefined) {
        throw new Error('Host context is unavailable.');
      }
      this.notebookExportService = new NotebookExportService(hostContext);
    }

    return this.notebookExportService as NotebookExportService;
  }

  private ensurePageThumbnailStore(): PageThumbnailStore {
    if (this.pageThumbnailStore === undefined) {
      const hostContext: common.Context | undefined = this.getUIContext().getHostContext() as common.Context | undefined;
      if (hostContext === undefined) {
        throw new Error('Host context is unavailable.');
      }
      this.pageThumbnailStore = new PageThumbnailStore(hostContext);
    }

    return this.pageThumbnailStore as PageThumbnailStore;
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
    this.retainNotebookSearchContentCache(notebookList);
    this.retainNotebookCoverCache(notebookList);
    this.preloadNotebookCoverSnapshots(notebookList);
    if (this.hasSearchQuery()) {
      void this.ensureSearchContentForActiveNotebooks();
    }
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

  private async importNotebookFromTopbar(): Promise<void> {
    if (this.isActionBusy() || this.isLoading) {
      return;
    }

    this.isLoading = true;
    this.importFailureMessage = '';
    try {
      const importResult = await this.ensureImportService().importFromPicker();
      if (importResult !== null) {
        const viewModel: NotebookListViewModel = this.ensureViewModel();
        this.currentSortType = await viewModel.loadSortType();
        try {
          await viewModel.touchNotebookLastOpened(importResult.notebookId);
        } catch (_touchError) {
        }
        await this.refreshNotebookCollection();
        AppRouter.openEditor({
          notebookId: importResult.notebookId,
          notebookTitle: importResult.notebookTitle,
          pageId: importResult.openedPageId
        });
      } else {
        this.importFailureMessage = this.ensureImportService().getLastFailureMessage();
      }
    } catch (_error) {
      this.importFailureMessage = '导入失败，未创建空白笔记本。请尝试其他文件，或先转换为 PDF 再导入。';
    } finally {
      this.isLoading = false;
    }
  }

  private isActionBusy(): boolean {
    return this.isDeletingNotebook || this.isSubmittingDialog || this.isCreatingFolder || this.isMovingNotebook || this.isUpdatingTags ||
      this.isRenamingFolder || this.isUpdatingFolderColor || this.isDeletingFolder || this.isPickingNotebookCover ||
      this.isUpdatingNotebookCover || this.isPickingExportPath || this.isExportingNotebook;
  }

  private isNotebookDeleted(notebook: Notebook): boolean {
    return notebook.isDeleted === true;
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
    this.draftFolderColor = NotebookFolderEntity.DEFAULT_COLOR;
  }

  private dismissFolderRenameDialog(): void {
    this.isFolderRenameDialogVisible = false;
    this.folderRenameTargetId = '';
    this.draftFolderRenameTitle = '';
  }

  private dismissFolderColorDialog(): void {
    this.isFolderColorDialogVisible = false;
    this.folderColorTargetId = '';
    this.draftFolderEditColor = NotebookFolderEntity.DEFAULT_COLOR;
    this.folderEditColorR = 124;
    this.folderEditColorG = 155;
    this.folderEditColorB = 255;
  }

  private dismissFolderDeleteDialog(): void {
    this.isFolderDeleteDialogVisible = false;
    this.folderDeleteTargetId = '';
    this.folderDeleteTargetTitle = '';
  }

  private dismissNotebookCoverDialog(): void {
    this.isNotebookCoverDialogVisible = false;
    this.notebookCoverTargetId = '';
    this.notebookCoverTargetTitle = '';
    this.draftNotebookColor = NotebookEntity.DEFAULT_COVER_COLOR;
    this.notebookColorR = 124;
    this.notebookColorG = 155;
    this.notebookColorB = 255;
  }

  private dismissMoveDialog(): void {
    this.isMoveDialogVisible = false;
    this.isMovingNotebook = false;
    this.moveTargetNotebookId = '';
    this.moveTargetNotebookTitle = '';
    this.selectedFolderId = '';
  }

  private dismissTagDialog(): void {
    this.isTagDialogVisible = false;
    this.isUpdatingTags = false;
    this.tagDraftText = '';
    this.tagSelectedText = '';
    this.tagDialogMode = TagDialogMode.MENU;
    this.tagDialogMessage = '';
    this.pendingTagOperation = PendingTagOperation.NONE;
    this.pendingTagOldText = '';
    this.pendingTagNewText = '';
    this.tagTargetNotebookId = '';
    this.tagTargetNotebookTitle = '';
  }

  private dismissExportDialog(): void {
    this.isExportDialogVisible = false;
    this.isExportingNotebook = false;
    this.exportTargetNotebookId = '';
    this.exportTargetNotebookTitle = '';
    this.draftExportFileName = '';
    this.draftExportPath = '';
    this.draftExportFormat = 'pdf';
    this.draftExportScope = 'all';
    this.draftExportPageRange = '';
  }

  private closeImportFailureMessage(): void {
    this.importFailureMessage = '';
  }

  private closeExportFailureMessage(): void {
    this.exportFailureMessage = '';
  }

  private closePassiveDialogs(): void {
    this.closeActionMenu();
    this.closeFolderActionMenu();
    this.closeCreateActionMenu();
    this.closeTopSortDropdown();

    if (!this.isDeletingNotebook) {
      this.dismissDeleteDialog();
    }

    if (!this.isCreatingFolder) {
      this.dismissFolderDialog();
    }

    if (!this.isMovingNotebook) {
      this.dismissMoveDialog();
    }

    if (!this.isUpdatingTags) {
      this.dismissTagDialog();
    }

    if (!this.isRenamingFolder) {
      this.dismissFolderRenameDialog();
    }

    if (!this.isUpdatingFolderColor) {
      this.dismissFolderColorDialog();
    }

    if (!this.isDeletingFolder) {
      this.dismissFolderDeleteDialog();
    }

    if (!this.isUpdatingNotebookCover && !this.isPickingNotebookCover) {
      this.dismissNotebookCoverDialog();
    }

    if (!this.isPickingExportPath) {
      this.dismissExportDialog();
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
    this.dismissTagDialog();
    this.dismissFolderRenameDialog();
    this.dismissFolderColorDialog();
    this.dismissFolderDeleteDialog();
    this.draftFolderTitle = '';
    this.draftFolderColor = this.pickRandomAvailableFolderColor();
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
      await this.ensureViewModel().createFolder(this.draftFolderTitle, this.draftFolderColor);
      await this.refreshNotebookCollection();
      this.dismissFolderDialog();
    } catch (_error) {
    } finally {
      this.isCreatingFolder = false;
    }
  }

  private getFolderById(folderId: string): NotebookFolder | undefined {
    for (const folder of this.folderList) {
      if (folder.id === folderId) {
        return folder;
      }
    }
    return undefined;
  }

  private openFolderRenameDialog(folderId: string): void {
    const folder: NotebookFolder | undefined = this.getFolderById(folderId);
    if (folder === undefined || this.isActionBusy()) {
      return;
    }

    this.closeFolderActionMenu();
    this.dismissFolderColorDialog();
    this.dismissFolderDeleteDialog();
    this.folderRenameTargetId = folder.id;
    this.draftFolderRenameTitle = folder.title;
    this.isFolderRenameDialogVisible = true;
  }

  private closeFolderRenameDialog(): void {
    if (this.isRenamingFolder) {
      return;
    }
    this.dismissFolderRenameDialog();
  }

  private async submitFolderRenameDialog(): Promise<void> {
    if (this.isRenamingFolder || this.folderRenameTargetId.length === 0) {
      return;
    }

    this.isRenamingFolder = true;
    try {
      await this.ensureViewModel().renameFolder(this.folderRenameTargetId, this.draftFolderRenameTitle);
      await this.refreshNotebookCollection();
      this.dismissFolderRenameDialog();
    } catch (_error) {
    } finally {
      this.isRenamingFolder = false;
    }
  }

  private openFolderColorDialog(folderId: string): void {
    const folder: NotebookFolder | undefined = this.getFolderById(folderId);
    if (folder === undefined || this.isActionBusy()) {
      return;
    }

    this.closeFolderActionMenu();
    this.dismissFolderRenameDialog();
    this.dismissFolderDeleteDialog();
    this.folderColorTargetId = folder.id;
    this.syncEditRgbFromColor(folder.color);
    this.isFolderColorDialogVisible = true;
  }

  private closeFolderColorDialog(): void {
    if (this.isUpdatingFolderColor) {
      return;
    }
    this.dismissFolderColorDialog();
  }

  private async submitFolderColorDialog(): Promise<void> {
    if (this.isUpdatingFolderColor || this.folderColorTargetId.length === 0) {
      return;
    }

    this.isUpdatingFolderColor = true;
    try {
      await this.ensureViewModel().updateFolderColor(this.folderColorTargetId, this.draftFolderEditColor);
      await this.refreshNotebookCollection();
      this.dismissFolderColorDialog();
    } catch (_error) {
    } finally {
      this.isUpdatingFolderColor = false;
    }
  }

  private openFolderDeleteDialog(folderId: string): void {
    const folder: NotebookFolder | undefined = this.getFolderById(folderId);
    if (folder === undefined || this.isActionBusy()) {
      return;
    }

    this.closeFolderActionMenu();
    this.dismissFolderRenameDialog();
    this.dismissFolderColorDialog();
    this.folderDeleteTargetId = folder.id;
    this.folderDeleteTargetTitle = folder.title;
    this.isFolderDeleteDialogVisible = true;
  }

  private closeFolderDeleteDialog(): void {
    if (this.isDeletingFolder) {
      return;
    }
    this.dismissFolderDeleteDialog();
  }

  private async submitFolderDeleteDialog(): Promise<void> {
    if (this.isDeletingFolder || this.folderDeleteTargetId.length === 0) {
      return;
    }

    this.isDeletingFolder = true;
    try {
      await this.ensureViewModel().deleteFolder(this.folderDeleteTargetId);
      await this.refreshNotebookCollection();
      if (this.selectedFolderInSidebar === this.folderDeleteTargetId) {
        this.selectedFolderInSidebar = '';
      }
      this.dismissFolderDeleteDialog();
    } catch (_error) {
    } finally {
      this.isDeletingFolder = false;
    }
  }

  private openMoveDialog(notebook: Notebook): void {
    if (this.isActionBusy()) {
      return;
    }

    this.closeInputDialog();
    this.dismissDeleteDialog();
    this.dismissFolderDialog();
    this.dismissTagDialog();
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

  private openTagDialog(notebook: Notebook): void {
    if (this.isActionBusy()) {
      return;
    }
    if (notebook.id.length === 0) {
      return;
    }

    this.closeInputDialog();
    this.dismissDeleteDialog();
    this.dismissFolderDialog();
    this.dismissMoveDialog();
    this.tagTargetNotebookId = notebook.id;
    this.tagTargetNotebookTitle = notebook.title;
    this.tagDialogMode = TagDialogMode.MENU;
    this.tagDraftText = '';
    this.tagSelectedText = '';
    this.tagDialogMessage = '';
    this.pendingTagOperation = PendingTagOperation.NONE;
    this.pendingTagOldText = '';
    this.pendingTagNewText = '';
    this.isTagDialogVisible = true;
  }

  private closeTagDialog(): void {
    if (this.isUpdatingTags) {
      return;
    }

    this.dismissTagDialog();
  }

  private async confirmTagDialog(): Promise<void> {
    if (this.isUpdatingTags || this.tagTargetNotebookId.length === 0 ||
      this.pendingTagOperation === PendingTagOperation.NONE) {
      return;
    }

    const currentTags: string[] = this.getTagTargetNotebookTags();
    let nextTags: string[] = currentTags;
    if (this.pendingTagOperation === PendingTagOperation.ADD) {
      nextTags = currentTags.concat([this.pendingTagNewText]);
    } else if (this.pendingTagOperation === PendingTagOperation.EDIT) {
      nextTags = this.buildEditedTagList(currentTags, this.pendingTagOldText, this.pendingTagNewText);
    } else if (this.pendingTagOperation === PendingTagOperation.DELETE) {
      nextTags = this.buildDeletedTagList(currentTags, this.pendingTagOldText);
    }

    this.isUpdatingTags = true;
    try {
      await this.ensureViewModel().updateNotebookTags(this.tagTargetNotebookId, nextTags);
      await this.refreshNotebookCollection();
      this.dismissTagDialog();
    } catch (_error) {
      this.isUpdatingTags = false;
    }
  }

  private openExportDialog(notebook: Notebook): void {
    if (this.isActionBusy()) {
      return;
    }
    if (notebook.id.length === 0) {
      return;
    }

    this.closePassiveDialogs();
    this.exportTargetNotebookId = notebook.id;
    this.exportTargetNotebookTitle = notebook.title;
    this.draftExportFileName = createNotebookExportBaseName(notebook.title);
    this.draftExportPath = '';
    this.draftExportFormat = 'pdf';
    this.draftExportScope = 'all';
    this.draftExportPageRange = '';
    this.isExportDialogVisible = true;
  }

  private closeExportDialog(): void {
    if (this.isPickingExportPath || this.isExportingNotebook) {
      return;
    }

    this.dismissExportDialog();
  }

  private async confirmExportDialog(): Promise<void> {
    if (this.isPickingExportPath || this.isExportingNotebook) {
      return;
    }

    const outputUris: string[] = this.parseExportOutputUris(this.draftExportPath);
    if (outputUris.length === 0) {
      await this.selectExportPathFromDialog();
      if (this.parseExportOutputUris(this.draftExportPath).length === 0) {
        return;
      }
    }

    this.isExportingNotebook = true;
    this.exportFailureMessage = '';
    try {
      const exportResult: NotebookExportResult = await this.ensureExportService().exportNotebook({
        notebookId: this.exportTargetNotebookId,
        fileName: this.getExportPickerBaseFileName(),
        format: this.draftExportFormat,
        outputUris: this.parseExportOutputUris(this.draftExportPath)
      });
      if (exportResult.success) {
        this.dismissExportDialog();
      } else {
        this.exportFailureMessage = exportResult.message;
      }
    } catch (_error) {
      this.exportFailureMessage = '导出失败，请重新选择保存位置后再试。';
    } finally {
      this.isExportingNotebook = false;
    }
  }

  private async selectExportPathFromDialog(): Promise<void> {
    if (this.isPickingExportPath || this.isExportingNotebook) {
      return;
    }

    const hostContext: common.Context | undefined = this.getUIContext().getHostContext() as common.Context | undefined;
    if (hostContext === undefined) {
      return;
    }

    this.isPickingExportPath = true;
    try {
      const saveOptions = new picker.DocumentSaveOptions();
      const exportService: NotebookExportService = this.ensureExportService();
      const pageCount: number = await exportService.getNotebookPageCount(this.exportTargetNotebookId);
      saveOptions.newFileNames = exportService.buildExportFileNames(
        this.getExportPickerBaseFileName(),
        this.draftExportFormat,
        pageCount
      );
      saveOptions.fileSuffixChoices = [buildNotebookExportSuffixChoice(this.draftExportFormat)];
      const documentPicker = new picker.DocumentViewPicker(hostContext);
      const selectedUris: string[] = await documentPicker.save(saveOptions);
      if (selectedUris.length > 0) {
        this.draftExportPath = selectedUris.join('\n');
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
    return createNotebookExportBaseName(this.exportTargetNotebookTitle);
  }

  private parseExportOutputUris(rawPath: string): string[] {
    const rawParts: string[] = rawPath.split('\n');
    const result: string[] = [];
    for (const rawPart of rawParts) {
      const normalizedPart: string = rawPart.trim();
      if (normalizedPart.length > 0 && !result.includes(normalizedPart)) {
        result.push(normalizedPart);
      }
    }
    return result;
  }

  private changeExportFormat(format: string): void {
    this.draftExportFormat = format;
    this.draftExportPath = '';
  }

  private normalizeTagList(rawTags?: string[]): string[] {
    const tags: string[] = [];
    if (!Array.isArray(rawTags)) {
      return tags;
    }

    for (const rawTag of rawTags) {
      if (typeof rawTag !== 'string') {
        continue;
      }
      const normalizedTag: string = rawTag.trim();
      if (normalizedTag.length === 0 || tags.includes(normalizedTag)) {
        continue;
      }
      tags.push(normalizedTag);
    }

    return tags;
  }

  private getNotebookDisplayTags(notebook: Notebook, limit: number = this.maxNotebookTagCount): string[] {
    const tags: string[] = this.normalizeTagList(notebook.tags);
    return tags.slice(0, Math.max(0, limit));
  }

  private getTagTargetNotebook(): Notebook | undefined {
    return this.getNotebookById(this.tagTargetNotebookId);
  }

  private getTagTargetNotebookTags(): string[] {
    const notebook: Notebook | undefined = this.getTagTargetNotebook();
    return notebook === undefined ? [] : this.normalizeTagList(notebook.tags);
  }

  private normalizeSingleTag(rawTag: string): string {
    return rawTag.trim();
  }

  private containsTagSeparator(tag: string): boolean {
    return tag.includes(',') || tag.includes('，');
  }

  private isAsciiText(value: string): boolean {
    for (let index: number = 0; index < value.length; index += 1) {
      if (value.charCodeAt(index) > 127) {
        return false;
      }
    }
    return true;
  }

  private getTagChipContentLimit(tag: string, mode: TagChipDisplayMode): number {
    if (mode === TagChipDisplayMode.ROOMY) {
      return this.isAsciiText(tag) ? this.roomyTagAsciiLimit : this.roomyTagChineseLimit;
    }
    return this.isAsciiText(tag) ? this.compactTagAsciiLimit : this.compactTagChineseLimit;
  }

  private formatTagChipText(tag: string, mode: TagChipDisplayMode = TagChipDisplayMode.COMPACT): string {
    const normalizedTag: string = tag.trim();
    const limit: number = this.getTagChipContentLimit(normalizedTag, mode);
    if (normalizedTag.length <= limit) {
      return normalizedTag;
    }
    return `${normalizedTag.slice(0, limit)}…`;
  }

  private buildEditedTagList(tags: string[], oldTag: string, newTag: string): string[] {
    const result: string[] = [];
    for (const tag of tags) {
      const nextTag: string = tag === oldTag ? newTag : tag;
      if (nextTag.length > 0 && !result.includes(nextTag)) {
        result.push(nextTag);
      }
    }
    return result;
  }

  private buildDeletedTagList(tags: string[], deletedTag: string): string[] {
    const result: string[] = [];
    for (const tag of tags) {
      if (tag !== deletedTag && !result.includes(tag)) {
        result.push(tag);
      }
    }
    return result;
  }

  private showTagMenu(): void {
    this.tagDialogMode = TagDialogMode.MENU;
    this.tagDraftText = '';
    this.tagSelectedText = '';
    this.tagDialogMessage = '';
    this.pendingTagOperation = PendingTagOperation.NONE;
    this.pendingTagOldText = '';
    this.pendingTagNewText = '';
  }

  private startAddTag(): void {
    const currentTags: string[] = this.getTagTargetNotebookTags();
    if (currentTags.length >= this.maxNotebookTagCount) {
      this.tagDialogMessage = `最多只能添加 ${this.maxNotebookTagCount} 个标签，请先编辑或删除已有标签。`;
      return;
    }

    this.tagDraftText = '';
    this.tagSelectedText = '';
    this.tagDialogMessage = '';
    this.pendingTagOperation = PendingTagOperation.NONE;
    this.tagDialogMode = TagDialogMode.ADD;
  }

  private startEditTagPick(): void {
    const currentTags: string[] = this.getTagTargetNotebookTags();
    if (currentTags.length === 0) {
      this.tagDialogMessage = '当前笔记本还没有标签可编辑。';
      return;
    }

    this.tagDraftText = '';
    this.tagSelectedText = '';
    this.tagDialogMessage = '';
    this.pendingTagOperation = PendingTagOperation.NONE;
    this.tagDialogMode = TagDialogMode.EDIT_PICK;
  }

  private startDeleteTagPick(): void {
    const currentTags: string[] = this.getTagTargetNotebookTags();
    if (currentTags.length === 0) {
      this.tagDialogMessage = '当前笔记本还没有标签可删除。';
      return;
    }

    this.tagDraftText = '';
    this.tagSelectedText = '';
    this.tagDialogMessage = '';
    this.pendingTagOperation = PendingTagOperation.NONE;
    this.tagDialogMode = TagDialogMode.DELETE_PICK;
  }

  private selectTagForEdit(tag: string): void {
    this.tagSelectedText = tag;
    this.tagDraftText = tag;
    this.tagDialogMessage = '';
    this.tagDialogMode = TagDialogMode.EDIT_FORM;
  }

  private selectTagForDelete(tag: string): void {
    this.tagSelectedText = tag;
    this.tagDialogMessage = '';
    this.pendingTagOperation = PendingTagOperation.DELETE;
    this.pendingTagOldText = tag;
    this.pendingTagNewText = '';
    this.tagDialogMode = TagDialogMode.CONFIRM;
  }

  private prepareAddTagConfirm(): void {
    const newTag: string = this.normalizeSingleTag(this.tagDraftText);
    const currentTags: string[] = this.getTagTargetNotebookTags();
    if (currentTags.length >= this.maxNotebookTagCount) {
      this.tagDialogMessage = `最多只能添加 ${this.maxNotebookTagCount} 个标签，请先编辑或删除已有标签。`;
      return;
    }
    if (newTag.length === 0) {
      this.tagDialogMessage = '请输入标签名称。';
      return;
    }
    if (this.containsTagSeparator(newTag)) {
      this.tagDialogMessage = '一次只能新增一个标签，请不要用逗号分隔。';
      return;
    }
    if (currentTags.includes(newTag)) {
      this.tagDialogMessage = '这个标签已经存在。';
      return;
    }

    this.tagDialogMessage = '';
    this.pendingTagOperation = PendingTagOperation.ADD;
    this.pendingTagOldText = '';
    this.pendingTagNewText = newTag;
    this.tagDialogMode = TagDialogMode.CONFIRM;
  }

  private prepareEditTagConfirm(): void {
    const oldTag: string = this.tagSelectedText;
    const newTag: string = this.normalizeSingleTag(this.tagDraftText);
    const currentTags: string[] = this.getTagTargetNotebookTags();
    if (oldTag.length === 0 || !currentTags.includes(oldTag)) {
      this.tagDialogMessage = '请选择要编辑的标签。';
      return;
    }
    if (newTag.length === 0) {
      this.tagDialogMessage = '请输入新的标签名称。';
      return;
    }
    if (this.containsTagSeparator(newTag)) {
      this.tagDialogMessage = '一次只能编辑一个标签，请不要用逗号分隔。';
      return;
    }
    if (newTag !== oldTag && currentTags.includes(newTag)) {
      this.tagDialogMessage = '这个标签已经存在。';
      return;
    }

    this.tagDialogMessage = '';
    this.pendingTagOperation = PendingTagOperation.EDIT;
    this.pendingTagOldText = oldTag;
    this.pendingTagNewText = newTag;
    this.tagDialogMode = TagDialogMode.CONFIRM;
  }

  private getPendingTagConfirmTitle(): string {
    if (this.pendingTagOperation === PendingTagOperation.ADD) {
      return '确认新增标签？';
    }
    if (this.pendingTagOperation === PendingTagOperation.EDIT) {
      return '确认编辑标签？';
    }
    if (this.pendingTagOperation === PendingTagOperation.DELETE) {
      return '确认删除标签？';
    }
    return '确认操作？';
  }

  private getPendingTagConfirmDescription(): string {
    if (this.pendingTagOperation === PendingTagOperation.ADD) {
      return `将新增标签“${this.pendingTagNewText}”。`;
    }
    if (this.pendingTagOperation === PendingTagOperation.EDIT) {
      return `将“${this.pendingTagOldText}”改为“${this.pendingTagNewText}”。`;
    }
    if (this.pendingTagOperation === PendingTagOperation.DELETE) {
      return `将删除标签“${this.pendingTagOldText}”。`;
    }
    return '';
  }

  private getPendingTagConfirmButtonText(): string {
    if (this.pendingTagOperation === PendingTagOperation.DELETE) {
      return this.isUpdatingTags ? '删除中...' : '确认删除';
    }
    return this.isUpdatingTags ? '保存中...' : '确认';
  }

  private getPendingTagConfirmButtonColor(): ResourceColor {
    return this.pendingTagOperation === PendingTagOperation.DELETE ? $r('app.color.danger_text') :
      $r('app.color.primary_text');
  }

  private returnFromTagConfirm(): void {
    if (this.pendingTagOperation === PendingTagOperation.ADD) {
      this.tagDialogMode = TagDialogMode.ADD;
    } else if (this.pendingTagOperation === PendingTagOperation.EDIT) {
      this.tagDialogMode = TagDialogMode.EDIT_FORM;
    } else if (this.pendingTagOperation === PendingTagOperation.DELETE) {
      this.tagDialogMode = TagDialogMode.DELETE_PICK;
    } else {
      this.tagDialogMode = TagDialogMode.MENU;
    }

    this.pendingTagOperation = PendingTagOperation.NONE;
    this.pendingTagOldText = '';
    this.pendingTagNewText = '';
    this.tagDialogMessage = '';
  }

  @Builder
  private buildTagDialogMessage(): void {
    if (this.tagDialogMessage.length > 0) {
      Text(this.tagDialogMessage)
        .width('100%')
        .fontSize($r('app.float.caption_text_size'))
        .fontColor($r('app.color.danger_text'))
    }
  }

  @Builder
  private buildTagDialogCurrentTags(): void {
    Column({ space: 8 }) {
      Text('当前标签')
        .fontSize($r('app.float.caption_text_size'))
        .fontColor($r('app.color.secondary_text'))

      if (this.getTagTargetNotebookTags().length > 0) {
        Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start, alignItems: ItemAlign.Start }) {
          ForEach(this.getTagTargetNotebookTags(), (tag: string) => {
            Text(tag)
              .fontSize(12)
              .fontColor('#556080')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .padding({ left: 9, right: 9, top: 4, bottom: 4 })
              .margin({ right: 6, bottom: 6 })
              .backgroundColor('#EEF2FF')
              .borderRadius(8)
          }, (tag: string): string => `tag-current-${tag}`)
        }
        .width('100%')
      } else {
        Text('还没有标签')
          .fontSize($r('app.float.caption_text_size'))
          .fontColor($r('app.color.secondary_text'))
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private buildTagPickList(isDeleteMode: boolean): void {
    Column({ space: 10 }) {
      Text(isDeleteMode ? '选择要删除的标签' : '选择要编辑的标签')
        .fontSize($r('app.float.body_text_size'))
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.primary_text'))

      ForEach(this.getTagTargetNotebookTags(), (tag: string) => {
        Button(tag)
          .width('100%')
          .height(40)
          .backgroundColor(isDeleteMode ? $r('app.color.danger_surface') : '#F4F6FB')
          .fontColor(isDeleteMode ? $r('app.color.danger_text') : $r('app.color.primary_text'))
          .borderRadius(10)
          .onClick(() => {
            if (isDeleteMode) {
              this.selectTagForDelete(tag);
            } else {
              this.selectTagForEdit(tag);
            }
          })
      }, (tag: string): string => `tag-pick-${isDeleteMode ? 'delete' : 'edit'}-${tag}`)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private buildTagDialogFooter(primaryText: string, primaryAction: () => void, backAction?: () => void,
    primaryColor?: ResourceColor): void {
    Row({ space: 12 }) {
      Button(backAction === undefined ? '取消' : '返回')
        .layoutWeight(1)
        .height($r('app.float.button_height'))
        .backgroundColor($r('app.color.app_background'))
        .fontColor($r('app.color.primary_text'))
        .enabled(!this.isUpdatingTags)
        .onClick(() => {
          const handler = backAction;
          if (handler === undefined) {
            this.closeTagDialog();
          } else {
            handler();
          }
        })

      Button(primaryText)
        .layoutWeight(1)
        .height($r('app.float.button_height'))
        .backgroundColor(primaryColor === undefined ? $r('app.color.primary_text') : primaryColor)
        .fontColor($r('app.color.inverse_text'))
        .enabled(!this.isUpdatingTags)
        .onClick(() => {
          primaryAction();
        })
    }
    .width('100%')
  }

  @Builder
  private buildTagDialogBody(): void {
    if (this.tagDialogMode === TagDialogMode.MENU) {
      this.buildTagDialogCurrentTags()

      Row({ space: 10 }) {
        Button('新增标签')
          .layoutWeight(1)
          .height($r('app.float.button_height'))
          .backgroundColor('#EEF2FF')
          .fontColor('#2E6BFF')
          .onClick(() => {
            this.startAddTag();
          })

        Button('编辑标签')
          .layoutWeight(1)
          .height($r('app.float.button_height'))
          .backgroundColor('#F4F6FB')
          .fontColor($r('app.color.primary_text'))
          .onClick(() => {
            this.startEditTagPick();
          })

        Button('删除标签')
          .layoutWeight(1)
          .height($r('app.float.button_height'))
          .backgroundColor($r('app.color.danger_surface'))
          .fontColor($r('app.color.danger_text'))
          .onClick(() => {
            this.startDeleteTagPick();
          })
      }
      .width('100%')

      this.buildTagDialogMessage()

      Button('关闭')
        .width('100%')
        .height($r('app.float.button_height'))
        .backgroundColor($r('app.color.app_background'))
        .fontColor($r('app.color.primary_text'))
        .onClick(() => {
          this.closeTagDialog();
        })
    } else if (this.tagDialogMode === TagDialogMode.ADD) {
      TextInput({ text: this.tagDraftText, placeholder: '输入一个新标签' })
        .width('100%')
        .onChange((value: string) => {
          this.tagDraftText = value;
        })

      this.buildTagDialogMessage()

      this.buildTagDialogFooter('下一步', (): void => {
        this.prepareAddTagConfirm();
      }, (): void => {
        this.showTagMenu();
      })
    } else if (this.tagDialogMode === TagDialogMode.EDIT_PICK) {
      this.buildTagPickList(false)
      this.buildTagDialogMessage()

      Button('返回')
        .width('100%')
        .height($r('app.float.button_height'))
        .backgroundColor($r('app.color.app_background'))
        .fontColor($r('app.color.primary_text'))
        .onClick(() => {
          this.showTagMenu();
        })
    } else if (this.tagDialogMode === TagDialogMode.EDIT_FORM) {
      Text(`正在编辑：${this.tagSelectedText}`)
        .fontSize($r('app.float.caption_text_size'))
        .fontColor($r('app.color.secondary_text'))

      TextInput({ text: this.tagDraftText, placeholder: '输入新的标签名称' })
        .width('100%')
        .onChange((value: string) => {
          this.tagDraftText = value;
        })

      this.buildTagDialogMessage()

      this.buildTagDialogFooter('下一步', (): void => {
        this.prepareEditTagConfirm();
      }, (): void => {
        this.startEditTagPick();
      })
    } else if (this.tagDialogMode === TagDialogMode.DELETE_PICK) {
      this.buildTagPickList(true)
      this.buildTagDialogMessage()

      Button('返回')
        .width('100%')
        .height($r('app.float.button_height'))
        .backgroundColor($r('app.color.app_background'))
        .fontColor($r('app.color.primary_text'))
        .onClick(() => {
          this.showTagMenu();
        })
    } else if (this.tagDialogMode === TagDialogMode.CONFIRM) {
      Column({ space: 8 }) {
        Text(this.getPendingTagConfirmTitle())
          .fontSize($r('app.float.body_text_size'))
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.primary_text'))

        Text(this.getPendingTagConfirmDescription())
          .fontSize($r('app.float.caption_text_size'))
          .fontColor($r('app.color.secondary_text'))
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      this.buildTagDialogFooter(this.getPendingTagConfirmButtonText(), (): void => {
        this.confirmTagDialog();
      }, (): void => {
        this.returnFromTagConfirm();
      }, this.getPendingTagConfirmButtonColor())
    }
  }

  private onSortTypeSelected(sortType: NotebookSortType): void {
    this.closeTopSortDropdown();
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
    this.dismissTagDialog();
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

  private async restoreNotebook(notebookId: string): Promise<void> {
    if (this.isActionBusy()) {
      return;
    }

    this.isDeletingNotebook = true;
    try {
      await this.ensureViewModel().restoreNotebook(notebookId);
      await this.refreshNotebookCollection();
    } catch (_error) {
    } finally {
      this.isDeletingNotebook = false;
    }
  }

  private async purgeNotebook(notebookId: string): Promise<void> {
    if (this.isActionBusy()) {
      return;
    }

    this.isDeletingNotebook = true;
    try {
      await this.ensureViewModel().purgeNotebook(notebookId);
      await this.refreshNotebookCollection();
    } catch (_error) {
    } finally {
      this.isDeletingNotebook = false;
    }
  }

  private async toggleNotebookFavorite(notebookId: string): Promise<void> {
    if (this.isActionBusy()) {
      return;
    }

    let currentFavoriteState: boolean = false;
    for (const item of this.notebookList) {
      if (item.id === notebookId) {
        currentFavoriteState = item.isFavorite === true;
        break;
      }
    }

    const nextFavoriteState: boolean = !currentFavoriteState;
    const nextNotebookList: Notebook[] = [];
    for (const item of this.notebookList) {
      if (item.id === notebookId) {
        nextNotebookList.push({
          id: item.id,
          title: item.title,
          folderId: item.folderId,
          createdAt: item.createdAt,
          updatedAt: item.updatedAt,
          coverColor: item.coverColor,
          coverImageUri: item.coverImageUri,
          pageCount: item.pageCount,
          isFavorite: nextFavoriteState,
          tags: Array.isArray(item.tags) ? item.tags.slice() : [],
          isDeleted: item.isDeleted === true,
          deletedAt: typeof item.deletedAt === 'number' ? item.deletedAt : 0,
          lastOpenedAt: typeof item.lastOpenedAt === 'number' ? item.lastOpenedAt : 0,
          lastEditedPageId: this.getNotebookLastEditedPageId(item)
        });
      } else {
        nextNotebookList.push(item);
      }
    }
    this.applyNotebookList(nextNotebookList);

    try {
      await this.ensureViewModel().toggleNotebookFavorite(notebookId, nextFavoriteState);
    } catch (_error) {
      await this.refreshNotebookCollection();
    }
  }

  private async openNotebook(notebookId: string): Promise<void> {
    this.closeActionMenu();
    const notebook: Notebook | undefined = this.getNotebookById(notebookId);
    const lastEditedPageId: string = notebook === undefined ? '' : this.getNotebookLastEditedPageId(notebook);
    const openedAt: number = Date.now();
    if (notebook !== undefined) {
      this.applyNotebookList(this.buildNotebookListWithTouchedLastOpened(notebookId, openedAt));
    }

    try {
      await this.ensureViewModel().touchNotebookLastOpened(notebookId);
    } catch (_error) {
    }

    const params: RouterParams = {
      notebookId: notebookId,
      source: 'notebook_list'
    };
    if (lastEditedPageId.length > 0) {
      params.pageId = lastEditedPageId;
    }
    AppRouter.openEditor(params);
  }

  private buildNotebookListWithTouchedLastOpened(notebookId: string, openedAt: number): Notebook[] {
    const nextNotebookList: Notebook[] = [];
    for (const item of this.notebookList) {
      if (item.id === notebookId) {
        nextNotebookList.push({
          id: item.id,
          title: item.title,
          folderId: item.folderId,
          createdAt: item.createdAt,
          updatedAt: openedAt,
          coverColor: item.coverColor,
          coverImageUri: item.coverImageUri,
          pageCount: item.pageCount,
          isFavorite: item.isFavorite === true,
          tags: Array.isArray(item.tags) ? item.tags.slice() : [],
          isDeleted: item.isDeleted === true,
          deletedAt: typeof item.deletedAt === 'number' ? item.deletedAt : 0,
          lastOpenedAt: openedAt,
          lastEditedPageId: this.getNotebookLastEditedPageId(item)
        });
      } else {
        nextNotebookList.push(item);
      }
    }
    return nextNotebookList;
  }

  private formatTimestamp(timestamp: number): string {
    if (!Number.isFinite(timestamp) || timestamp <= 0) {
      return '--';
    }

    const now: number = Date.now();
    const elapsed: number = Math.max(0, now - timestamp);
    if (elapsed < this.oneMinuteMs) {
      return `${Math.max(1, Math.floor(elapsed / 1000))}秒前`;
    }

    if (elapsed <= this.oneDayMs) {
      const hours: number = Math.floor(elapsed / this.oneHourMs);
      const minutes: number = Math.max(1, Math.floor((elapsed % this.oneHourMs) / this.oneMinuteMs));
      return `${hours}时${minutes}分钟前`;
    }

    if (elapsed <= this.oneWeekMs) {
      return `${Math.max(1, Math.floor(elapsed / this.oneDayMs))}天前`;
    }

    if (elapsed <= this.oneMonthMs) {
      return `${Math.max(1, Math.floor(elapsed / this.oneWeekMs))}周前`;
    }

    const date: Date = new Date(timestamp);
    const month: string = this.padNumber(date.getMonth() + 1);
    const day: string = this.padNumber(date.getDate());
    if (elapsed <= this.oneYearMs) {
      return `${month}月${day}日`;
    }

    const year: string = date.getFullYear().toString();
    return `${year}年${month}月${day}日`;
  }

  private padNumber(value: number): string {
    if (value >= 10) {
      return value.toString();
    }
    return `0${value.toString()}`;
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

  private getActiveNotebookList(): Notebook[] {
    const activeNotebookList: Notebook[] = [];
    for (const notebook of this.notebookList) {
      if (!this.isNotebookDeleted(notebook)) {
        activeNotebookList.push(notebook);
      }
    }
    return activeNotebookList;
  }

  private compareNotebookByCurrentSort(left: Notebook, right: Notebook): number {
    if (this.currentSortType === NotebookSortType.CREATED_DESC) {
      const createdDiff: number = right.createdAt - left.createdAt;
      return createdDiff !== 0 ? createdDiff : left.title.localeCompare(right.title);
    }

    if (this.currentSortType === NotebookSortType.TITLE_ASC) {
      const titleDiff: number = left.title.localeCompare(right.title);
      return titleDiff !== 0 ? titleDiff : right.updatedAt - left.updatedAt;
    }

    const updatedDiff: number = right.updatedAt - left.updatedAt;
    return updatedDiff !== 0 ? updatedDiff : left.title.localeCompare(right.title);
  }

  private sortNotebookListByCurrentSort(notebookList: Notebook[]): Notebook[] {
    const sortedNotebookList: Notebook[] = notebookList.slice();
    sortedNotebookList.sort((left: Notebook, right: Notebook): number => {
      return this.compareNotebookByCurrentSort(left, right);
    });
    return sortedNotebookList;
  }

  private getDeletedNotebookList(): Notebook[] {
    const deletedNotebookList: Notebook[] = [];
    for (const notebook of this.notebookList) {
      if (this.isNotebookDeleted(notebook)) {
        deletedNotebookList.push(notebook);
      }
    }
    deletedNotebookList.sort((left: Notebook, right: Notebook): number => {
      const leftDeletedAt: number = typeof left.deletedAt === 'number' ? left.deletedAt : 0;
      const rightDeletedAt: number = typeof right.deletedAt === 'number' ? right.deletedAt : 0;
      return rightDeletedAt - leftDeletedAt;
    });
    return deletedNotebookList;
  }

  private getFavoriteNotebookList(): Notebook[] {
    const favoriteNotebookList: Notebook[] = [];
    for (const notebook of this.getActiveNotebookList()) {
      if (notebook.isFavorite === true) {
        favoriteNotebookList.push(notebook);
      }
    }
    return this.sortNotebookListByCurrentSort(favoriteNotebookList);
  }

  private getRecentOpenedNotebookList(shouldApplyCurrentSort: boolean = false): Notebook[] {
    const recentNotebookList: Notebook[] = [];
    for (const notebook of this.getActiveNotebookList()) {
      if (typeof notebook.lastOpenedAt === 'number' && notebook.lastOpenedAt > 0) {
        recentNotebookList.push(notebook);
      }
    }
    if (shouldApplyCurrentSort) {
      return this.sortNotebookListByCurrentSort(recentNotebookList);
    }
    recentNotebookList.sort((left: Notebook, right: Notebook): number => {
      const leftLastOpenedAt: number = typeof left.lastOpenedAt === 'number' ? left.lastOpenedAt : 0;
      const rightLastOpenedAt: number = typeof right.lastOpenedAt === 'number' ? right.lastOpenedAt : 0;
      return rightLastOpenedAt - leftLastOpenedAt;
    });
    return recentNotebookList;
  }

  private getAllTagList(): string[] {
    const allTagList: string[] = [];
    for (const notebook of this.getActiveNotebookList()) {
      const tags: string[] = Array.isArray(notebook.tags) ? notebook.tags : [];
      for (const rawTag of tags) {
        const tag: string = rawTag.trim();
        if (tag.length === 0 || allTagList.includes(tag)) {
          continue;
        }
        allTagList.push(tag);
      }
    }

    allTagList.sort((left: string, right: string): number => left.localeCompare(right));
    return allTagList;
  }

  private getTagNotebookList(tag: string): Notebook[] {
    const tagNotebookList: Notebook[] = [];
    for (const notebook of this.getActiveNotebookList()) {
      const tags: string[] = Array.isArray(notebook.tags) ? notebook.tags : [];
      if (tags.includes(tag)) {
        tagNotebookList.push(notebook);
      }
    }
    return this.sortNotebookListByCurrentSort(tagNotebookList);
  }

  private getFolderNotebookList(folderId: string): Notebook[] {
    const folderNotebookList: Notebook[] = [];
    for (const notebook of this.getActiveNotebookList()) {
      if (notebook.folderId === folderId) {
        folderNotebookList.push(notebook);
      }
    }

    return this.sortNotebookListByCurrentSort(folderNotebookList);
  }

  private getUngroupedNotebookList(): Notebook[] {
    const ungroupedNotebookList: Notebook[] = [];
    for (const notebook of this.getActiveNotebookList()) {
      if (notebook.folderId.length === 0 || !this.hasFolder(notebook.folderId)) {
        ungroupedNotebookList.push(notebook);
      }
    }

    return this.sortNotebookListByCurrentSort(ungroupedNotebookList);
  }

  private normalizeSearchQuery(value: string): string {
    return value.trim().replace(/\s+/g, ' ').toLowerCase();
  }

  private hasSearchQuery(): boolean {
    return this.normalizeSearchQuery(this.searchText).length > 0;
  }

  private matchesSearchText(value: string | undefined, query: string): boolean {
    if (typeof value !== 'string' || value.length === 0) {
      return false;
    }

    return value.toLowerCase().includes(query);
  }

  private getNotebookSearchContent(notebookId: string): string {
    const content: string | undefined = this.notebookSearchContentMap.get(notebookId);
    return content === undefined ? '' : content;
  }

  private shouldKeepNotebookBySearch(notebook: Notebook, query: string): boolean {
    if (query.length === 0) {
      return true;
    }

    if (this.matchesSearchText(notebook.title, query)) {
      return true;
    }

    const tags: string[] = Array.isArray(notebook.tags) ? notebook.tags : [];
    for (const tag of tags) {
      if (this.matchesSearchText(tag, query)) {
        return true;
      }
    }

    const folder: NotebookFolder | undefined = this.getFolderById(notebook.folderId);
    if (folder !== undefined && this.matchesSearchText(folder.title, query)) {
      return true;
    }

    return this.matchesSearchText(this.getNotebookSearchContent(notebook.id), query);
  }

  private shouldKeepFolderBySearch(folder: NotebookFolder, query: string): boolean {
    if (query.length === 0) {
      return true;
    }

    if (this.matchesSearchText(folder.title, query)) {
      return true;
    }

    for (const notebook of this.getFolderNotebookList(folder.id)) {
      if (this.shouldKeepNotebookBySearch(notebook, query)) {
        return true;
      }
    }

    return false;
  }

  private getSearchMatchedNotebookList(): Notebook[] {
    const query: string = this.normalizeSearchQuery(this.searchText);
    const result: Notebook[] = [];
    const contentRenderVersion: number = this.searchContentRenderVersion;
    if (contentRenderVersion < 0) {
      return result;
    }

    for (const notebook of this.getActiveNotebookList()) {
      if (this.shouldKeepNotebookBySearch(notebook, query)) {
        result.push(notebook);
      }
    }
    return this.sortNotebookListByCurrentSort(result);
  }

  private getSearchMatchedFolderList(): NotebookFolder[] {
    const query: string = this.normalizeSearchQuery(this.searchText);
    const result: NotebookFolder[] = [];
    const contentRenderVersion: number = this.searchContentRenderVersion;
    if (contentRenderVersion < 0) {
      return result;
    }

    for (const folder of this.getSortedFolderListForAllNotes()) {
      if (this.shouldKeepFolderBySearch(folder, query)) {
        result.push(folder);
      }
    }
    return result;
  }

  private getSearchMatchedNotebookCountInFolder(folderId: string): number {
    const query: string = this.normalizeSearchQuery(this.searchText);
    if (query.length === 0) {
      return this.getFolderNotebookList(folderId).length;
    }

    const folder: NotebookFolder | undefined = this.getFolderById(folderId);
    if (folder !== undefined && this.matchesSearchText(folder.title, query)) {
      return this.getFolderNotebookList(folderId).length;
    }

    let count: number = 0;
    for (const notebook of this.getFolderNotebookList(folderId)) {
      if (this.shouldKeepNotebookBySearch(notebook, query)) {
        count += 1;
      }
    }
    return count;
  }

  private retainNotebookSearchContentCache(notebookList: Notebook[]): void {
    const retainedNotebookIds: Set<string> = new Set<string>();
    for (const notebook of notebookList) {
      retainedNotebookIds.add(notebook.id);
    }

    const cachedNotebookIds: string[] = Array.from(this.notebookSearchContentMap.keys());
    for (const notebookId of cachedNotebookIds) {
      if (!retainedNotebookIds.has(notebookId)) {
        this.notebookSearchContentMap.delete(notebookId);
        this.notebookSearchContentUpdatedAtMap.delete(notebookId);
      }
    }
  }

  private shouldLoadNotebookSearchContent(notebook: Notebook): boolean {
    if (this.isNotebookDeleted(notebook) || this.notebookSearchContentLoadingIds.has(notebook.id)) {
      return false;
    }

    const cachedUpdatedAt: number | undefined = this.notebookSearchContentUpdatedAtMap.get(notebook.id);
    return cachedUpdatedAt === undefined || cachedUpdatedAt < notebook.updatedAt;
  }

  private async ensureSearchContentForActiveNotebooks(): Promise<void> {
    if (!this.hasSearchQuery()) {
      return;
    }

    if (this.isSearchContentLoading) {
      return;
    }

    const notebooksToLoad: Notebook[] = [];
    for (const notebook of this.getActiveNotebookList()) {
      if (this.shouldLoadNotebookSearchContent(notebook)) {
        notebooksToLoad.push(notebook);
      }
    }

    if (notebooksToLoad.length === 0) {
      return;
    }

    this.isSearchContentLoading = true;
    try {
      for (const notebook of notebooksToLoad) {
        await this.loadNotebookSearchContent(notebook);
      }
    } finally {
      this.isSearchContentLoading = this.notebookSearchContentLoadingIds.size > 0;
      this.searchContentRenderVersion += 1;
    }
  }

  private async loadNotebookSearchContent(notebook: Notebook): Promise<void> {
    if (this.notebookSearchContentLoadingIds.has(notebook.id)) {
      return;
    }

    this.notebookSearchContentLoadingIds.add(notebook.id);
    try {
      const content: string = await this.ensureViewModel().loadNotebookSearchContent(notebook.id);
      this.notebookSearchContentMap.set(notebook.id, content);
      this.notebookSearchContentUpdatedAtMap.set(notebook.id, notebook.updatedAt);
      this.searchContentRenderVersion += 1;
    } catch (_error) {
      this.notebookSearchContentMap.set(notebook.id, '');
      this.notebookSearchContentUpdatedAtMap.set(notebook.id, notebook.updatedAt);
      this.searchContentRenderVersion += 1;
    } finally {
      this.notebookSearchContentLoadingIds.delete(notebook.id);
    }
  }

  private getCurrentDayStartTimestamp(): number {
    const now: Date = new Date();
    const dayStart: Date = new Date(now.getFullYear(), now.getMonth(), now.getDate(), 0, 0, 0, 0);
    return dayStart.getTime();
  }

  private getRangeLowerBound(range: AllNotesTimeRange): number {
    const now: number = Date.now();
    const day: number = 24 * 60 * 60 * 1000;
    if (range === AllNotesTimeRange.TODAY) {
      return this.getCurrentDayStartTimestamp();
    }
    if (range === AllNotesTimeRange.LAST_7_DAYS) {
      return now - 7 * day;
    }
    if (range === AllNotesTimeRange.LAST_30_DAYS) {
      return now - 30 * day;
    }
    return 0;
  }

  private shouldKeepNotebookByAllNotesFilter(notebook: Notebook): boolean {
    if (this.allNotesSortFilterType === AllNotesSortFilterType.TAG) {
      if (this.allNotesSelectedTagFilter.length === 0) {
        return true;
      }
      const tags: string[] = Array.isArray(notebook.tags) ? notebook.tags : [];
      return tags.includes(this.allNotesSelectedTagFilter);
    }

    if (this.allNotesSortFilterType === AllNotesSortFilterType.CREATED_AT) {
      const lowerBound: number = this.getRangeLowerBound(this.allNotesCreatedTimeRange);
      if (lowerBound <= 0) {
        return true;
      }
      return notebook.createdAt >= lowerBound;
    }

    const lowerBound: number = this.getRangeLowerBound(this.allNotesUpdatedTimeRange);
    if (lowerBound <= 0) {
      return true;
    }
    return notebook.updatedAt >= lowerBound;
  }

  private getFilteredActiveNotebookList(): Notebook[] {
    const result: Notebook[] = [];
    for (const notebook of this.getActiveNotebookList()) {
      if (this.shouldKeepNotebookByAllNotesFilter(notebook)) {
        result.push(notebook);
      }
    }
    return this.sortNotebookListByCurrentSort(result);
  }

  private filterNotebookListByWorkspaceFilter(notebookList: Notebook[]): Notebook[] {
    const result: Notebook[] = [];
    for (const notebook of notebookList) {
      if (this.shouldKeepNotebookByAllNotesFilter(notebook)) {
        result.push(notebook);
      }
    }
    return result;
  }

  private getSortedFolderListForAllNotes(): NotebookFolder[] {
    const sortedFolderList: NotebookFolder[] = this.folderList.slice();
    if (this.currentSortType === NotebookSortType.CREATED_DESC) {
      sortedFolderList.sort((left: NotebookFolder, right: NotebookFolder): number => right.createdAt - left.createdAt);
    } else if (this.currentSortType === NotebookSortType.TITLE_ASC) {
      sortedFolderList.sort((left: NotebookFolder, right: NotebookFolder): number => left.title.localeCompare(right.title));
    } else {
      sortedFolderList.sort((left: NotebookFolder, right: NotebookFolder): number => right.updatedAt - left.updatedAt);
    }
    return sortedFolderList;
  }

  private hasAllNotesSectionContent(): boolean {
    return this.getFilteredActiveNotebookList().length > 0;
  }

  private getSidebarCount(section: SidebarSection): number {
    if (this.hasSearchQuery()) {
      if (section === SidebarSection.FOLDERS) {
        return this.getSearchMatchedFolderList().length;
      }
      if (section === SidebarSection.TAGS) {
        return this.getAllTagList().length;
      }
      if (section === SidebarSection.RECYCLE) {
        return 0;
      }
      return this.getSearchMatchedNotebookList().length;
    }

    if (section === SidebarSection.ALL) {
      return this.getActiveNotebookList().length;
    }
    if (section === SidebarSection.RECENT) {
      return this.getRecentOpenedNotebookList().length;
    }
    if (section === SidebarSection.FAVORITES) {
      return this.getFavoriteNotebookList().length;
    }
    if (section === SidebarSection.FOLDERS) {
      return this.folderList.length;
    }
    if (section === SidebarSection.TAGS) {
      return this.getAllTagList().length;
    }
    return this.getDeletedNotebookList().length;
  }

  private closeActionMenu(): void {
    this.activeActionMenuNotebookId = '';
  }

  private closeFolderActionMenu(): void {
    this.activeFolderActionMenuFolderId = '';
  }

  private closeCreateActionMenu(): void {
    this.isCreateActionMenuVisible = false;
  }

  private closeTopSortDropdown(): void {
    this.isTopSortDropdownVisible = false;
  }

  private getNotebookById(notebookId: string): Notebook | undefined {
    for (const notebook of this.notebookList) {
      if (notebook.id === notebookId) {
        return notebook;
      }
    }
    return undefined;
  }

  private isNotebookFavorite(notebookId: string): boolean {
    const notebook: Notebook | undefined = this.getNotebookById(notebookId);
    if (notebook === undefined) {
      return false;
    }
    return notebook.isFavorite === true;
  }

  private resolveLengthValue(value: Length | undefined): number {
    if (typeof value === 'number') {
      return Number.isFinite(value) ? value : 0;
    }

    if (typeof value === 'string') {
      const parsedValue: number = parseFloat(value);
      return Number.isFinite(parsedValue) ? parsedValue : 0;
    }

    return 0;
  }

  private updateWorkspaceArea(area: Area): void {
    const left: number = this.resolveLengthValue(area.globalPosition.x);
    const top: number = this.resolveLengthValue(area.globalPosition.y);
    const width: number = this.resolveLengthValue(area.width);
    const height: number = this.resolveLengthValue(area.height);
    if (left === this.workspaceAreaLeft && top === this.workspaceAreaTop &&
      width === this.workspaceAreaWidth && height === this.workspaceAreaHeight) {
      return;
    }

    this.workspaceAreaLeft = left;
    this.workspaceAreaTop = top;
    this.workspaceAreaWidth = width;
    this.workspaceAreaHeight = height;
  }

  private updatePanelArea(area: Area): void {
    const width: number = this.resolveLengthValue(area.width);
    const height: number = this.resolveLengthValue(area.height);
    if (width === this.panelAreaWidth && height === this.panelAreaHeight) {
      return;
    }

    this.panelAreaWidth = width;
    this.panelAreaHeight = height;
  }

  private getMeasuredWorkspaceWidth(): number {
    if (this.workspaceAreaWidth > 0) {
      return this.workspaceAreaWidth;
    }
    return this.defaultWorkspaceWidth;
  }

  private getMeasuredPanelWidth(): number {
    if (this.panelAreaWidth > 0) {
      return this.panelAreaWidth;
    }
    return this.defaultPanelWidth;
  }

  private getMeasuredPanelHeight(): number {
    if (this.panelAreaHeight > 0) {
      return this.panelAreaHeight;
    }
    return this.defaultPanelHeight;
  }

  private isPanelPortrait(): boolean {
    return this.getMeasuredPanelHeight() > this.getMeasuredPanelWidth();
  }

  private getRecentCardWidth(): Length {
    if (!this.isPanelPortrait()) {
      return '20%';
    }

    const collapsedWorkspaceWidth: number = this.getPortraitCollapsedWorkspaceWidth();
    const targetWidth: number = Math.round(collapsedWorkspaceWidth / 4);
    return Math.max(targetWidth, 1);
  }

  private getPortraitCollapsedWorkspaceWidth(): number {
    const panelWidth: number = this.getMeasuredPanelWidth();
    return Math.max(1, panelWidth - this.workspacePanelPadding * 2);
  }

  private getFolderCardWidth(): string {
    return this.isPanelPortrait() ? '50%' : '33.333%';
  }

  private getNotebookListItemWidth(): string {
    return this.isPanelPortrait() ? '100%' : '50%';
  }

  private getNotebookDisplayCardWidth(): Length {
    return this.useLargeNotebookCards ? this.getRecentCardWidth() : this.getNotebookListItemWidth();
  }

  private getNotebookGridJustifyContent(): FlexAlign {
    return FlexAlign.Start;
  }

  private getNotebookDisplayGridJustifyContent(): FlexAlign {
    return this.useLargeNotebookCards ? this.getRecentGridJustifyContent() : this.getNotebookGridJustifyContent();
  }

  private getFolderGridJustifyContent(): FlexAlign {
    return FlexAlign.Start;
  }

  private getRecentGridJustifyContent(): FlexAlign {
    return FlexAlign.Start;
  }

  private getSidebarWidth(): number {
    if (this.isSidebarCollapsed) {
      return 0;
    }
    return this.isPanelPortrait() ? this.portraitSidebarWidth : this.landscapeSidebarWidth;
  }

  private getNotebookCoverAspectRatio(notebook: Notebook): number {
    const coverCanvas: NotebookPageCanvas | null = this.getNotebookCoverCanvas(notebook.id);
    const width: number = coverCanvas === null
      ? NotebookPageCanvasEntity.DEFAULT_WIDTH
      : NotebookPageCanvasEntity.normalizeDimension(coverCanvas.width, NotebookPageCanvasEntity.DEFAULT_WIDTH);
    const height: number = coverCanvas === null
      ? NotebookPageCanvasEntity.DEFAULT_HEIGHT
      : NotebookPageCanvasEntity.normalizeDimension(coverCanvas.height, NotebookPageCanvasEntity.DEFAULT_HEIGHT);
    return Math.max(0.1, width / Math.max(1, height));
  }

  private retainNotebookCoverCache(notebookList: Notebook[]): void {
    const retainedNotebookIds: Set<string> = new Set<string>();
    for (const notebook of notebookList) {
      retainedNotebookIds.add(notebook.id);
    }

    for (const notebookId of Array.from(this.notebookCoverPageMap.keys())) {
      if (!retainedNotebookIds.has(notebookId)) {
        this.notebookCoverPageMap.delete(notebookId);
      }
    }
    for (const notebookId of Array.from(this.notebookCoverCanvasMap.keys())) {
      if (!retainedNotebookIds.has(notebookId)) {
        this.notebookCoverCanvasMap.delete(notebookId);
      }
    }
    for (const notebookId of Array.from(this.notebookCoverLoadingIds.keys())) {
      if (!retainedNotebookIds.has(notebookId)) {
        this.notebookCoverLoadingIds.delete(notebookId);
      }
    }
  }

  private preloadNotebookCoverSnapshots(notebookList: Notebook[]): void {
    for (const notebook of notebookList) {
      if (this.isNotebookDeleted(notebook)) {
        continue;
      }
      void this.ensureNotebookCoverSnapshot(notebook);
    }
  }

  private getNotebookLastEditedPageId(notebook: Notebook): string {
    return NotebookEntity.normalizeLastEditedPageId(notebook.lastEditedPageId);
  }

  private getNotebookCoverPage(notebookId: string): NotebookPage | null {
    const page = this.notebookCoverPageMap.get(notebookId);
    return page === undefined ? null : page;
  }

  private getNotebookCoverCanvas(notebookId: string): NotebookPageCanvas | null {
    const canvas = this.notebookCoverCanvasMap.get(notebookId);
    return canvas === undefined ? null : canvas;
  }

  private hasNotebookCoverSnapshot(notebook: Notebook): boolean {
    const renderTick: number = this.notebookCoverRenderTick;
    return renderTick >= 0 && this.getNotebookCoverPage(notebook.id) !== null &&
      this.getNotebookCoverCanvas(notebook.id) !== null;
  }

  private buildNotebookCoverSnapshot(notebook: Notebook): PageThumbnailRenderSnapshot {
    const coverPage: NotebookPage | null = this.getNotebookCoverPage(notebook.id);
    const coverCanvas: NotebookPageCanvas | null = this.getNotebookCoverCanvas(notebook.id);
    if (coverPage === null || coverCanvas === null) {
      return createEmptyPageThumbnailRenderSnapshot(this.getNotebookLastEditedPageId(notebook));
    }

    try {
      return this.ensurePageThumbnailStore().buildSnapshot({
        pageId: coverPage.id,
        templateType: this.resolveNotebookPageTemplateType(coverPage.templateType),
        paperBackgroundColor: NotebookPageCanvasEntity.normalizeBackgroundColor(coverCanvas.backgroundColor),
        backgroundImageUri: NotebookPageCanvasEntity.normalizeBackgroundImageUri(coverCanvas.backgroundImageUri),
        canvasWidth: NotebookPageCanvasEntity.normalizeDimension(
          coverCanvas.width,
          NotebookPageCanvasEntity.DEFAULT_WIDTH
        ),
        canvasHeight: NotebookPageCanvasEntity.normalizeDimension(
          coverCanvas.height,
          NotebookPageCanvasEntity.DEFAULT_HEIGHT
        ),
        activeSession: null
      });
    } catch (_error) {
      return createEmptyPageThumbnailRenderSnapshot(coverPage.id);
    }
  }

  private requestNotebookCoverSnapshot(notebookId: string): void {
    const notebook: Notebook | undefined = this.getNotebookById(notebookId);
    if (notebook === undefined) {
      return;
    }

    void this.ensureNotebookCoverSnapshot(notebook);
  }

  private async ensureNotebookCoverSnapshot(notebook: Notebook): Promise<void> {
    if (notebook.id.length === 0 || this.notebookCoverLoadingIds.has(notebook.id)) {
      return;
    }

    const cachedPage: NotebookPage | null = this.getNotebookCoverPage(notebook.id);
    const cachedCanvas: NotebookPageCanvas | null = this.getNotebookCoverCanvas(notebook.id);
    const targetLastEditedPageId: string = this.getNotebookLastEditedPageId(notebook);
    if (cachedPage !== null && cachedCanvas !== null &&
      (targetLastEditedPageId.length === 0 || cachedPage.id === targetLastEditedPageId)) {
      try {
        const hasLoaded = await this.ensurePageThumbnailStore().ensurePageContent(cachedPage.id);
        if (hasLoaded) {
          this.notebookCoverRenderTick += 1;
        }
      } catch (_error) {
      }
      return;
    }

    this.notebookCoverLoadingIds.add(notebook.id);
    try {
      const pageList: NotebookPage[] = await this.ensureViewModel().loadNotebookPages(notebook.id);
      const coverPage: NotebookPage | null = this.resolveNotebookCoverPage(pageList, targetLastEditedPageId);
      if (coverPage === null) {
        this.notebookCoverPageMap.delete(notebook.id);
        this.notebookCoverCanvasMap.delete(notebook.id);
        this.notebookCoverRenderTick += 1;
        return;
      }

      const coverCanvas: NotebookPageCanvas | null = await this.ensureViewModel().loadNotebookPageCanvas(
        notebook.id,
        coverPage.id
      );
      if (coverCanvas === null) {
        this.notebookCoverPageMap.delete(notebook.id);
        this.notebookCoverCanvasMap.delete(notebook.id);
        this.notebookCoverRenderTick += 1;
        return;
      }

      this.notebookCoverPageMap.set(notebook.id, this.cloneNotebookPage(coverPage));
      this.notebookCoverCanvasMap.set(notebook.id, this.cloneNotebookPageCanvas(coverCanvas));
      await this.ensurePageThumbnailStore().ensurePageContent(coverPage.id);
      this.notebookCoverRenderTick += 1;
    } catch (_error) {
    } finally {
      this.notebookCoverLoadingIds.delete(notebook.id);
    }
  }

  private resolveNotebookCoverPage(pageList: NotebookPage[], lastEditedPageId: string): NotebookPage | null {
    if (pageList.length === 0) {
      return null;
    }

    if (lastEditedPageId.length > 0) {
      for (const page of pageList) {
        if (page.id === lastEditedPageId) {
          return page;
        }
      }
    }

    return pageList[0];
  }

  private cloneNotebookPage(page: NotebookPage): NotebookPage {
    return {
      id: page.id,
      notebookId: page.notebookId,
      order: page.order,
      createdAt: page.createdAt,
      updatedAt: page.updatedAt,
      templateType: this.resolveNotebookPageTemplateType(page.templateType),
      sourceFileUri: typeof page.sourceFileUri === 'string' ? page.sourceFileUri : '',
      sourceFileType: typeof page.sourceFileType === 'string' ? page.sourceFileType : ''
    };
  }

  private cloneNotebookPageCanvas(canvas: NotebookPageCanvas): NotebookPageCanvas {
    return {
      pageId: canvas.pageId,
      notebookId: canvas.notebookId,
      width: NotebookPageCanvasEntity.normalizeDimension(canvas.width, NotebookPageCanvasEntity.DEFAULT_WIDTH),
      height: NotebookPageCanvasEntity.normalizeDimension(canvas.height, NotebookPageCanvasEntity.DEFAULT_HEIGHT),
      backgroundColor: NotebookPageCanvasEntity.normalizeBackgroundColor(canvas.backgroundColor),
      backgroundImageUri: NotebookPageCanvasEntity.normalizeBackgroundImageUri(canvas.backgroundImageUri),
      createdAt: canvas.createdAt,
      updatedAt: canvas.updatedAt
    };
  }

  private resolveNotebookPageTemplateType(templateType?: NotebookPageTemplateType): NotebookPageTemplateType {
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

  private updateActionMenuAnchor(notebookId: string, area: Area): void {
    const left: number = this.resolveLengthValue(area.globalPosition.x) - this.workspaceAreaLeft;
    const top: number = this.resolveLengthValue(area.globalPosition.y) - this.workspaceAreaTop + this.workspaceScrollOffsetY;
    const width: number = this.resolveLengthValue(area.width);
    const height: number = this.resolveLengthValue(area.height);
    let targetAnchor: ActionMenuAnchor | undefined = undefined;
    for (const anchor of this.actionMenuAnchors) {
      if (anchor.notebookId === notebookId) {
        targetAnchor = anchor;
        break;
      }
    }

    if (targetAnchor === undefined) {
      const createdAnchor: ActionMenuAnchor = new ActionMenuAnchor();
      createdAnchor.notebookId = notebookId;
      createdAnchor.left = left;
      createdAnchor.top = top;
      createdAnchor.width = width;
      createdAnchor.height = height;
      this.actionMenuAnchors.push(createdAnchor);
      return;
    }

    if (targetAnchor.left === left && targetAnchor.top === top &&
      targetAnchor.width === width && targetAnchor.height === height) {
      return;
    }

    targetAnchor.left = left;
    targetAnchor.top = top;
    targetAnchor.width = width;
    targetAnchor.height = height;
  }

  private updateFolderActionMenuAnchor(folderId: string, area: Area): void {
    const left: number = this.resolveLengthValue(area.globalPosition.x) - this.workspaceAreaLeft;
    const top: number = this.resolveLengthValue(area.globalPosition.y) - this.workspaceAreaTop + this.workspaceScrollOffsetY;
    const width: number = this.resolveLengthValue(area.width);
    const height: number = this.resolveLengthValue(area.height);
    let targetAnchor: FolderActionMenuAnchor | undefined = undefined;
    for (const anchor of this.folderActionMenuAnchors) {
      if (anchor.folderId === folderId) {
        targetAnchor = anchor;
        break;
      }
    }

    if (targetAnchor === undefined) {
      const createdAnchor: FolderActionMenuAnchor = new FolderActionMenuAnchor();
      createdAnchor.folderId = folderId;
      createdAnchor.left = left;
      createdAnchor.top = top;
      createdAnchor.width = width;
      createdAnchor.height = height;
      this.folderActionMenuAnchors.push(createdAnchor);
      return;
    }

    if (targetAnchor.left === left && targetAnchor.top === top &&
      targetAnchor.width === width && targetAnchor.height === height) {
      return;
    }

    targetAnchor.left = left;
    targetAnchor.top = top;
    targetAnchor.width = width;
    targetAnchor.height = height;
  }

  private getActiveActionMenuAnchor(): ActionMenuAnchor | undefined {
    for (const anchor of this.actionMenuAnchors) {
      if (anchor.notebookId === this.activeActionMenuNotebookId) {
        return anchor;
      }
    }
    return undefined;
  }

  private getActiveFolderActionMenuAnchor(): FolderActionMenuAnchor | undefined {
    for (const anchor of this.folderActionMenuAnchors) {
      if (anchor.folderId === this.activeFolderActionMenuFolderId) {
        return anchor;
      }
    }
    return undefined;
  }

  private getActiveActionMenuPosition(): Position {
    const anchor = this.getActiveActionMenuAnchor();
    const position: MenuPosition = new MenuPosition();
    if (anchor === undefined || this.workspaceAreaWidth <= 0 || this.workspaceAreaHeight <= 0) {
      return position;
    }

    let menuLeft: number = anchor.left + anchor.width - this.actionMenuWidth;
    if (menuLeft < 0) {
      menuLeft = 0;
    }
    if (menuLeft + this.actionMenuWidth > this.workspaceAreaWidth) {
      menuLeft = Math.max(this.workspaceAreaWidth - this.actionMenuWidth - 8, 0);
    }

    let menuTop: number = anchor.top - this.workspaceScrollOffsetY + anchor.height + this.actionMenuGap;
    if (menuTop + this.actionMenuHeight > this.workspaceAreaHeight) {
      menuTop = Math.max(anchor.top - this.workspaceScrollOffsetY - this.actionMenuHeight - this.actionMenuGap, 0);
    }

    position.x = menuLeft;
    position.y = menuTop;
    return position;
  }

  private getActiveFolderActionMenuPosition(): Position {
    const anchor = this.getActiveFolderActionMenuAnchor();
    const position: MenuPosition = new MenuPosition();
    if (anchor === undefined || this.workspaceAreaWidth <= 0 || this.workspaceAreaHeight <= 0) {
      return position;
    }

    let menuLeft: number = anchor.left + anchor.width - this.folderActionMenuWidth;
    if (menuLeft < 0) {
      menuLeft = 0;
    }
    if (menuLeft + this.folderActionMenuWidth > this.workspaceAreaWidth) {
      menuLeft = Math.max(this.workspaceAreaWidth - this.folderActionMenuWidth - 8, 0);
    }

    let menuTop: number = anchor.top - this.workspaceScrollOffsetY + anchor.height + this.folderActionMenuGap;
    if (menuTop + this.folderActionMenuHeight > this.workspaceAreaHeight) {
      menuTop = Math.max(anchor.top - this.workspaceScrollOffsetY - this.folderActionMenuHeight - this.folderActionMenuGap, 0);
    }

    position.x = menuLeft;
    position.y = menuTop;
    return position;
  }

  private getCreateActionMenuPosition(): Position {
    const position: MenuPosition = new MenuPosition();
    const anchor: ActionMenuAnchor = this.createActionMenuAnchor;
    if (!this.isCreateActionMenuVisible || this.workspaceAreaWidth <= 0 || this.workspaceAreaHeight <= 0) {
      return position;
    }

    let menuLeft: number = anchor.left + anchor.width - this.folderActionMenuWidth;
    if (menuLeft < 0) {
      menuLeft = 0;
    }
    if (menuLeft + this.folderActionMenuWidth > this.workspaceAreaWidth) {
      menuLeft = Math.max(this.workspaceAreaWidth - this.folderActionMenuWidth - 8, 0);
    }

    let menuTop: number = anchor.top - this.workspaceScrollOffsetY + anchor.height + this.folderActionMenuGap;
    if (menuTop + this.folderActionMenuHeight > this.workspaceAreaHeight) {
      menuTop = Math.max(anchor.top - this.workspaceScrollOffsetY - this.folderActionMenuHeight - this.folderActionMenuGap, 0);
    }

    position.x = menuLeft;
    position.y = menuTop;
    return position;
  }

  private getTopSortMenuPosition(): Position {
    const position: MenuPosition = new MenuPosition();
    const anchor: WorkspaceToolMenuAnchor = this.topSortMenuAnchor;
    if (!this.isTopSortDropdownVisible || this.workspaceAreaWidth <= 0 || this.workspaceAreaHeight <= 0) {
      return position;
    }

    let menuLeft: number = anchor.left + anchor.width - this.sortMenuWidth;
    if (menuLeft < 0) {
      menuLeft = 0;
    }
    if (menuLeft + this.sortMenuWidth > this.workspaceAreaWidth) {
      menuLeft = Math.max(this.workspaceAreaWidth - this.sortMenuWidth - 8, 0);
    }

    let menuTop: number = anchor.top - this.workspaceScrollOffsetY + anchor.height + this.folderActionMenuGap;
    if (menuTop + this.sortMenuHeight > this.workspaceAreaHeight) {
      menuTop = Math.max(anchor.top - this.workspaceScrollOffsetY - this.sortMenuHeight - this.folderActionMenuGap, 0);
    }

    position.x = menuLeft;
    position.y = menuTop;
    return position;
  }

  private toggleActionMenu(notebookId: string): void {
    if (this.activeActionMenuNotebookId === notebookId) {
      this.closeActionMenu();
      return;
    }

    this.closeFolderActionMenu();
    this.closeCreateActionMenu();
    this.closeTopSortDropdown();
    this.activeActionMenuNotebookId = notebookId;
  }

  private toggleFolderActionMenu(folderId: string): void {
    if (this.activeFolderActionMenuFolderId === folderId) {
      this.closeFolderActionMenu();
      return;
    }

    this.closeActionMenu();
    this.closeCreateActionMenu();
    this.closeTopSortDropdown();
    this.activeFolderActionMenuFolderId = folderId;
  }

  private updateCreateActionMenuAnchor(area: Area): void {
    this.createActionMenuAnchor.notebookId = '__create__';
    this.createActionMenuAnchor.left = this.resolveLengthValue(area.globalPosition.x) - this.workspaceAreaLeft;
    this.createActionMenuAnchor.top = this.resolveLengthValue(area.globalPosition.y) - this.workspaceAreaTop + this.workspaceScrollOffsetY;
    this.createActionMenuAnchor.width = this.resolveLengthValue(area.width);
    this.createActionMenuAnchor.height = this.resolveLengthValue(area.height);
  }

  private updateTopSortMenuAnchor(area: Area): void {
    this.topSortMenuAnchor.left = this.resolveLengthValue(area.globalPosition.x) - this.workspaceAreaLeft;
    this.topSortMenuAnchor.top = this.resolveLengthValue(area.globalPosition.y) - this.workspaceAreaTop + this.workspaceScrollOffsetY;
    this.topSortMenuAnchor.width = this.resolveLengthValue(area.width);
    this.topSortMenuAnchor.height = this.resolveLengthValue(area.height);
  }

  private toggleTopSortDropdown(): void {
    if (this.isTopSortDropdownVisible) {
      this.closeTopSortDropdown();
      return;
    }
    this.closeActionMenu();
    this.closeFolderActionMenu();
    this.closeCreateActionMenu();
    this.isTopSortDropdownVisible = true;
  }

  private toggleCreateActionMenu(): void {
    if (this.isCreateActionMenuVisible) {
      this.closeCreateActionMenu();
      return;
    }
    this.closeActionMenu();
    this.closeFolderActionMenu();
    this.closeTopSortDropdown();
    this.isCreateActionMenuVisible = true;
  }

  private openCreateDialogFromCreateMenu(): void {
    this.closeCreateActionMenu();
    this.openCreateDialog();
  }

  private importNotebookFromCreateMenu(): void {
    this.closeCreateActionMenu();
    void this.importNotebookFromTopbar();
  }

  private openFolderDialogFromCreateMenu(): void {
    this.closeCreateActionMenu();
    this.openFolderDialog();
  }

  private openRenameDialogFromActionMenu(): void {
    const notebook: Notebook | undefined = this.getNotebookById(this.activeActionMenuNotebookId);
    this.closeActionMenu();
    if (notebook !== undefined) {
      this.openRenameDialog(notebook);
    }
  }

  private openMoveDialogFromActionMenu(): void {
    const notebook: Notebook | undefined = this.getNotebookById(this.activeActionMenuNotebookId);
    this.closeActionMenu();
    if (notebook !== undefined) {
      this.openMoveDialog(notebook);
    }
  }

  private openExportDialogFromActionMenu(): void {
    const notebook: Notebook | undefined = this.getNotebookById(this.activeActionMenuNotebookId);
    this.closeActionMenu();
    if (notebook !== undefined) {
      this.openExportDialog(notebook);
    }
  }

  private openTagDialogFromActionMenu(): void {
    const notebook: Notebook | undefined = this.getNotebookById(this.activeActionMenuNotebookId);
    this.closeActionMenu();
    if (notebook !== undefined) {
      this.openTagDialog(notebook);
    }
  }

  private openDeleteDialogFromActionMenu(): void {
    const notebook: Notebook | undefined = this.getNotebookById(this.activeActionMenuNotebookId);
    this.closeActionMenu();
    if (notebook !== undefined) {
      this.openDeleteDialog(notebook);
    }
  }

  private openNotebookCoverDialogFromActionMenu(): void {
    if (this.isActionBusy()) {
      return;
    }

    const notebook: Notebook | undefined = this.getNotebookById(this.activeActionMenuNotebookId);
    this.closeActionMenu();
    if (notebook === undefined) {
      return;
    }

    this.notebookCoverTargetId = notebook.id;
    this.notebookCoverTargetTitle = notebook.title;
    this.syncNotebookRgbFromColor(NotebookEntity.normalizeCoverColor(notebook.coverColor));
    this.isNotebookCoverDialogVisible = true;
  }

  private closeNotebookCoverDialog(): void {
    if (this.isPickingNotebookCover || this.isUpdatingNotebookCover) {
      return;
    }
    this.dismissNotebookCoverDialog();
  }

  private async selectNotebookCoverImageFromDialog(): Promise<void> {
    if (this.isPickingNotebookCover || this.isUpdatingNotebookCover || this.notebookCoverTargetId.length === 0) {
      return;
    }

    const hostContext: common.Context | undefined = this.getUIContext().getHostContext() as common.Context | undefined;
    if (hostContext === undefined) {
      return;
    }

    this.isPickingNotebookCover = true;
    try {
      const selectOptions = new picker.PhotoSelectOptions();
      selectOptions.MIMEType = picker.PhotoViewMIMETypes.IMAGE_TYPE;
      selectOptions.maxSelectNumber = 1;

      const photoPicker = new picker.PhotoViewPicker(hostContext);
      const selectResult = await photoPicker.select(selectOptions);
      const selectedUri: string = selectResult.photoUris.length > 0 ? selectResult.photoUris[0] : '';
      if (selectedUri.length === 0) {
        return;
      }

      const importedAsset: ImportedImageAsset = await new ImageAssetDataSource(hostContext).importImage(selectedUri);
      await this.ensureViewModel().updateNotebookCover(this.notebookCoverTargetId, importedAsset.uri);
      await this.refreshNotebookCollection();
      this.dismissNotebookCoverDialog();
    } catch (_error) {
    } finally {
      this.isPickingNotebookCover = false;
    }
  }

  private async applyNotebookTitleCoverFromDialog(): Promise<void> {
    if (this.isPickingNotebookCover || this.isUpdatingNotebookCover || this.notebookCoverTargetId.length === 0) {
      return;
    }

    this.isUpdatingNotebookCover = true;
    try {
      await this.ensureViewModel().updateNotebookCover(
        this.notebookCoverTargetId,
        NotebookEntity.TITLE_COVER_IMAGE_URI,
        this.draftNotebookColor
      );
      await this.refreshNotebookCollection();
      this.dismissNotebookCoverDialog();
    } catch (_error) {
    } finally {
      this.isUpdatingNotebookCover = false;
    }
  }

  private async applyDefaultNotebookCoverFromDialog(): Promise<void> {
    if (this.isPickingNotebookCover || this.isUpdatingNotebookCover || this.notebookCoverTargetId.length === 0) {
      return;
    }

    this.isUpdatingNotebookCover = true;
    try {
      await this.ensureViewModel().updateNotebookCover(this.notebookCoverTargetId, '');
      await this.refreshNotebookCollection();
      this.dismissNotebookCoverDialog();
    } catch (_error) {
    } finally {
      this.isUpdatingNotebookCover = false;
    }
  }

  private selectSection(section: SidebarSection): void {
    this.closeActionMenu();
    this.closeFolderActionMenu();
    this.closeCreateActionMenu();
    this.closeTopSortDropdown();
    if (section !== SidebarSection.ALL) {
      this.isAllNotesSortFilterPanelVisible = false;
    }
    this.currentSection = section;
    if (section !== SidebarSection.TAGS) {
      this.selectedTag = '';
    }
    if (section !== SidebarSection.FOLDERS) {
      this.selectedFolderInSidebar = '';
    }
  }

  private formatFolderActivityTimestamp(folderId: string): string {
    const folder: NotebookFolder | undefined = this.getFolderById(folderId);
    if (folder === undefined) {
      return '--';
    }
    return this.formatTimestamp(folder.updatedAt);
  }

  private clampRgbChannel(value: number): number {
    if (!Number.isFinite(value)) {
      return 0;
    }
    if (value < 0) {
      return 0;
    }
    if (value > 255) {
      return 255;
    }
    return Math.round(value);
  }

  private padHexFromChannel(value: number): string {
    const hexValue: string = this.clampRgbChannel(value).toString(16).toUpperCase();
    return hexValue.length === 1 ? `0${hexValue}` : hexValue;
  }

  private composeHexFromRgb(r: number, g: number, b: number): string {
    return `#${this.padHexFromChannel(r)}${this.padHexFromChannel(g)}${this.padHexFromChannel(b)}`;
  }

  private syncEditRgbFromColor(color: string): void {
    const normalizedColor: string = NotebookFolderEntity.normalizeColor(color);
    this.folderEditColorR = parseInt(normalizedColor.slice(1, 3), 16);
    this.folderEditColorG = parseInt(normalizedColor.slice(3, 5), 16);
    this.folderEditColorB = parseInt(normalizedColor.slice(5, 7), 16);
    this.draftFolderEditColor = normalizedColor;
  }

  private syncEditColorFromRgb(): void {
    this.draftFolderEditColor = this.composeHexFromRgb(this.folderEditColorR, this.folderEditColorG, this.folderEditColorB);
  }

  private syncNotebookRgbFromColor(color: string): void {
    const normalizedColor: string = NotebookEntity.normalizeCoverColor(color);
    this.notebookColorR = parseInt(normalizedColor.slice(1, 3), 16);
    this.notebookColorG = parseInt(normalizedColor.slice(3, 5), 16);
    this.notebookColorB = parseInt(normalizedColor.slice(5, 7), 16);
    this.draftNotebookColor = normalizedColor;
  }

  private syncNotebookColorFromRgb(): void {
    this.draftNotebookColor = this.composeHexFromRgb(this.notebookColorR, this.notebookColorG, this.notebookColorB);
  }

  private pickRandomAvailableFolderColor(): string {
    const usedColors: string[] = [];
    for (const folder of this.folderList) {
      const normalizedColor: string = NotebookFolderEntity.normalizeColor(folder.color);
      if (!usedColors.includes(normalizedColor)) {
        usedColors.push(normalizedColor);
      }
    }

    const availableColors: string[] = [];
    for (const color of NotebookFolderEntity.COLOR_PALETTE) {
      if (!usedColors.includes(color)) {
        availableColors.push(color);
      }
    }

    if (availableColors.length > 0) {
      const randomIndex: number = Math.floor(Math.random() * availableColors.length);
      return availableColors[randomIndex];
    }

    const palette: string[] = NotebookFolderEntity.COLOR_PALETTE;
    const fallbackIndex: number = Math.floor(Math.random() * palette.length);
    return palette[fallbackIndex];
  }

  @Builder
  private buildFolderIcon(width: number = 34): void {
    Image($rawfile('icons/folder_icon.svg'))
      .width(width)
      .height(width)
      .objectFit(ImageFit.Contain)
  }

  @Builder
  private buildRgbSliderLine(label: string, value: number, trackColor: string, onChange: (value: number) => void): void {
    Column({ space: 6 }) {
      Row() {
        Text(label)
          .fontSize(12)
          .fontColor('#475467')
          .layoutWeight(1)

        Text(this.clampRgbChannel(value).toString())
          .fontSize(12)
          .fontColor('#667085')
      }
      .width('100%')

      Slider({
        value: value,
        min: 0,
        max: 255,
        step: 1,
        style: SliderStyle.OutSet
      })
        .showTips(false)
        .trackColor(trackColor)
        .onChange((nextValue: number) => {
          onChange(this.clampRgbChannel(nextValue));
        })
    }
    .width('100%')
  }

  @Builder
  private buildSidebarItem(section: SidebarSection, title: string): void {
    Row() {
      Text(title)
        .layoutWeight(1)
        .fontSize($r('app.float.body_text_size'))
        .fontWeight(this.currentSection === section ? FontWeight.Medium : FontWeight.Regular)
        .fontColor(this.currentSection === section ? '#2E6BFF' : $r('app.color.primary_text'))

      Text(this.getSidebarCount(section).toString())
        .fontSize($r('app.float.caption_text_size'))
        .fontColor($r('app.color.secondary_text'))
    }
    .width('100%')
    .height(44)
    .padding({ left: 12, right: 12 })
    .borderRadius(12)
    .backgroundColor(this.currentSection === section ? '#332E6BFF' : '#00000000')
    .onClick(() => {
      this.selectSection(section);
    })
  }

  @Builder
  private buildSidebarFolderItem(folder: NotebookFolder): void {
    Row({ space: 8 }) {
      this.buildFolderIcon(24)

      Text(folder.title)
        .layoutWeight(1)
        .fontSize($r('app.float.caption_text_size'))
        .fontColor(this.currentSection === SidebarSection.FOLDERS && this.selectedFolderInSidebar === folder.id ?
          '#2E6BFF' : $r('app.color.primary_text'))

      Text((this.hasSearchQuery() ? this.getSearchMatchedNotebookCountInFolder(folder.id) :
        this.getFolderNotebookList(folder.id).length).toString())
        .fontSize($r('app.float.caption_text_size'))
        .fontColor($r('app.color.secondary_text'))
    }
    .width('100%')
    .height(38)
    .padding({ left: 14, right: 10 })
    .borderRadius(10)
    .backgroundColor(this.currentSection === SidebarSection.FOLDERS && this.selectedFolderInSidebar === folder.id ?
      '#332E6BFF' : '#00000000')
    .onClick(() => {
      this.closeActionMenu();
      this.closeFolderActionMenu();
      this.closeCreateActionMenu();
      this.closeTopSortDropdown();
      this.currentSection = SidebarSection.FOLDERS;
      this.selectedFolderInSidebar = folder.id;
    })
  }

  @Builder
  private buildSidebarTagItem(tag: string): void {
    Row() {
      Text(tag)
        .layoutWeight(1)
        .fontSize($r('app.float.caption_text_size'))
        .fontColor(this.currentSection === SidebarSection.TAGS && this.selectedTag === tag ? '#2E6BFF' :
          $r('app.color.primary_text'))

      Text(this.getTagNotebookList(tag).length.toString())
        .fontSize($r('app.float.caption_text_size'))
        .fontColor($r('app.color.secondary_text'))
    }
    .width('100%')
    .height(38)
    .padding({ left: 14, right: 10 })
    .borderRadius(10)
    .backgroundColor(this.currentSection === SidebarSection.TAGS && this.selectedTag === tag ? '#332E6BFF' :
      '#00000000')
    .onClick(() => {
      this.closeActionMenu();
      this.closeFolderActionMenu();
      this.closeCreateActionMenu();
      this.closeTopSortDropdown();
      this.currentSection = SidebarSection.TAGS;
      this.selectedTag = tag;
    })
  }

  @Builder
  private buildTagChip(tag: string, mode: TagChipDisplayMode = TagChipDisplayMode.COMPACT): void {
    Text(this.formatTagChipText(tag, mode))
      .fontSize(11)
      .fontColor('#556080')
      .maxLines(1)
      .padding({ left: 7, right: 7, top: 2, bottom: 2 })
      .backgroundColor('#EEF2FF')
      .borderRadius(7)
  }

  @Builder
  private buildTagChipRow(notebook: Notebook, mode: TagChipDisplayMode = TagChipDisplayMode.COMPACT): void {
    Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start, alignItems: ItemAlign.Start }) {
      ForEach(this.getNotebookDisplayTags(notebook), (tag: string) => {
        Row() {
          this.buildTagChip(tag, mode)
        }
        .margin({ right: 5, bottom: 4 })
      }, (tag: string): string => `${notebook.id}-${tag}`)
    }
    .width('100%')
    .clip(true)
  }

  @Builder
  private buildFilterIcon(): void {
    Column({ space: 4 }) {
      Column() {}
        .width(16)
        .height(2)
        .backgroundColor('#667085')
        .borderRadius(1)
      Column() {}
        .width(11)
        .height(2)
        .backgroundColor('#667085')
        .borderRadius(1)
      Column() {}
        .width(6)
        .height(2)
        .backgroundColor('#667085')
        .borderRadius(1)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private buildViewModeIcon(): void {
    if (this.useLargeNotebookCards) {
      Row({ space: 3 }) {
        Column() {}
          .width(7)
          .height(14)
          .borderRadius(2)
          .border({ width: 2, color: '#667085' })
        Column() {}
          .width(7)
          .height(14)
          .borderRadius(2)
          .border({ width: 2, color: '#667085' })
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
    } else {
      Column({ space: 4 }) {
        Row({ space: 4 }) {
          Column() {}
            .width(5)
            .height(5)
            .borderRadius(1)
            .backgroundColor('#667085')
          Column() {}
            .width(15)
            .height(2)
            .borderRadius(1)
            .backgroundColor('#667085')
        }
        .alignItems(VerticalAlign.Center)

        Row({ space: 4 }) {
          Column() {}
            .width(5)
            .height(5)
            .borderRadius(1)
            .backgroundColor('#667085')
          Column() {}
            .width(15)
            .height(2)
            .borderRadius(1)
            .backgroundColor('#667085')
        }
        .alignItems(VerticalAlign.Center)
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
    }
  }

  @Builder
  private buildSortIcon(): void {
    Row({ space: 3 }) {
      Column({ space: 0 }) {
        Text('↑')
          .fontSize(13)
          .fontColor('#667085')
          .fontWeight(FontWeight.Medium)
        Text('↓')
          .fontSize(13)
          .fontColor('#667085')
          .fontWeight(FontWeight.Medium)
          .margin({ top: -4 })
      }
      .alignItems(HorizontalAlign.Center)

      Column({ space: 3 }) {
        Column() {}
          .width(10)
          .height(2)
          .backgroundColor('#667085')
          .borderRadius(1)
        Column() {}
          .width(7)
          .height(2)
          .backgroundColor('#667085')
          .borderRadius(1)
        Column() {}
          .width(4)
          .height(2)
          .backgroundColor('#667085')
          .borderRadius(1)
      }
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private buildWorkspaceToolButton(toolType: string): void {
    Button() {
      if (toolType === 'filter') {
        this.buildFilterIcon()
      } else if (toolType === 'view') {
        this.buildViewModeIcon()
      } else {
        this.buildSortIcon()
      }
    }
      .width(this.workspaceToolButtonSize)
      .height(this.workspaceToolButtonSize)
      .padding(0)
      .backgroundColor(toolType === 'filter' && this.isAllNotesSortFilterPanelVisible ? '#E8EEFF' : '#F4F6FB')
      .borderRadius(8)
      .border({ width: 1, color: '#DDE4F0' })
      .stateEffect(true)
      .onAreaChange((_oldValue: Area, newValue: Area) => {
        if (toolType === 'sort') {
          this.updateTopSortMenuAnchor(newValue);
        }
      })
      .onTouch((event?: TouchEvent) => {
        if (event !== undefined && toolType === 'sort') {
          if (event.type === TouchType.Down) {
            this.updateTopSortMenuAnchor(event.target.area);
          }
          event.stopPropagation();
        }
      })
      .onClick(() => {
        if (toolType === 'filter') {
          this.closeTopSortDropdown();
          this.isAllNotesSortFilterPanelVisible = !this.isAllNotesSortFilterPanelVisible;
        } else if (toolType === 'view') {
          this.closeTopSortDropdown();
          this.useLargeNotebookCards = !this.useLargeNotebookCards;
        } else {
          this.toggleTopSortDropdown();
        }
      })
  }

  @Builder
  private buildWorkspaceToolButtons(): void {
    Row({ space: 8 }) {
      this.buildWorkspaceToolButton('filter')
      this.buildWorkspaceToolButton('view')
      this.buildWorkspaceToolButton('sort')
    }
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private buildWorkspaceHeader(title: string, showTools: boolean = true): void {
    Row() {
      Text(title)
        .layoutWeight(1)
        .fontSize($r('app.float.section_title_size'))
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.primary_text'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      if (showTools) {
        this.buildWorkspaceToolButtons()
      }
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private buildSortOption(label: string, sortType: NotebookSortType): void {
    Button(label)
      .width('100%')
      .height(34)
      .fontSize(13)
      .fontColor(this.currentSortType === sortType ? '#3D63FF' : '#344054')
      .backgroundColor(this.currentSortType === sortType ? '#EAF0FF' : '#FFFFFF')
      .borderRadius(8)
      .onClick(() => {
        this.onSortTypeSelected(sortType);
      })
  }

  @Builder
  private buildNotebookItem(notebook: Notebook): void {
    Row({ space: 18 }) {
      Stack() {
        this.buildNotebookCoverPreview(notebook)
      }
      .width(76)
      .height(98)
      .borderRadius(4)
      .clip(true)
      .backgroundColor('#00FFFFFF')
      .onClick(() => {
        void this.openNotebook(notebook.id);
      })

      Column({ space: 8 }) {
        Text(`${notebook.title} (${NotebookEntity.normalizePageCount(notebook.pageCount)})`)
          .fontSize(21)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.primary_text'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')

        Text(this.formatTimestamp(notebook.updatedAt))
          .fontSize(15)
          .fontColor($r('app.color.secondary_text'))

        if (this.getNotebookDisplayTags(notebook).length > 0) {
          this.buildTagChipRow(notebook, TagChipDisplayMode.COMPACT)
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .onClick(() => {
        void this.openNotebook(notebook.id);
      })

      Row({ space: 14 }) {
        Button() {
          Text(this.isNotebookFavorite(notebook.id) ? '★' : '☆')
            .fontColor(this.isNotebookFavorite(notebook.id) ? '#F59E0B' : '#4B5563')
            .fontSize(33)
            .textAlign(TextAlign.Center)
            .width('100%')
        }
          .width(52)
          .height(52)
          .padding(0)
          .backgroundColor('#00000000')
          .borderRadius(0)
          .stateEffect(false)
          .onClick(() => {
            void this.toggleNotebookFavorite(notebook.id);
          })

        Button('⋮')
          .width(48)
          .height(52)
          .backgroundColor('#00000000')
          .fontColor('#111827')
          .fontSize(34)
          .borderRadius(0)
          .padding(0)
          .onAreaChange((_oldValue: Area, newValue: Area) => {
            this.updateActionMenuAnchor(notebook.id, newValue);
          })
          .onTouch((event?: TouchEvent) => {
            if (event !== undefined) {
              if (event.type === TouchType.Down) {
                this.updateActionMenuAnchor(notebook.id, event.target.area);
              }
              event.stopPropagation();
            }
          })
          .onClick(() => {
            this.toggleActionMenu(notebook.id);
          })
      }
      .width(120)
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .height(136)
    .padding({ left: 24, right: 20, top: 16, bottom: 16 })
    .backgroundColor($r('app.color.surface_background'))
    .borderRadius(24)
    .border({
      width: 1,
      color: $r('app.color.card_border')
    })
  }

  @Builder
  private buildNotebookCoverPreview(notebook: Notebook): void {
    Stack() {
      if (NotebookEntity.isTitleCoverImageUri(notebook.coverImageUri)) {
        Column() {
          Text(notebook.title.length > 10 ? `${notebook.title.slice(0, 10)}...` : notebook.title)
            .fontSize(10)
            .fontColor('#FFFFFF')
            .maxLines(2)
            .textAlign(TextAlign.Center)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .padding({ left: 4, right: 4 })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .backgroundColor(NotebookEntity.normalizeCoverColor(notebook.coverColor))
      } else if (typeof notebook.coverImageUri === 'string' && notebook.coverImageUri.length > 0) {
        Image(this.toDisplayImageUri(notebook.coverImageUri))
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Contain)
      } else if (this.hasNotebookCoverSnapshot(notebook)) {
        PageThumbnailCanvas({
          snapshot: this.buildNotebookCoverSnapshot(notebook),
          renderTick: this.notebookCoverRenderTick,
          onNeedSnapshot: (pageId: string): void => {
            this.requestNotebookCoverSnapshot(notebook.id);
          }
        })
          .width('100%')
          .height('100%')
      } else {
        Column() {
          Text(notebook.title.length > 10 ? `${notebook.title.slice(0, 10)}...` : notebook.title)
            .fontSize(10)
            .fontColor('#FFFFFF')
            .maxLines(2)
            .textAlign(TextAlign.Center)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .padding({ left: 4, right: 4 })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .backgroundColor(NotebookEntity.normalizeCoverColor(notebook.coverColor))
        .onAppear(() => {
          this.requestNotebookCoverSnapshot(notebook.id);
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#00FFFFFF')
    .onAppear(() => {
      this.requestNotebookCoverSnapshot(notebook.id);
    })
  }

  @Builder
  private buildRecentCoverSlot(notebook: Notebook): void {
    Stack({ alignContent: Alignment.Center }) {
      Stack() {
        this.buildNotebookCoverPreview(notebook)
      }
      .width('100%')
      .height('100%')
      .borderRadius(10)
      .clip(true)
    }
    .width('100%')
    .constraintSize({ maxWidth: this.recentCoverSlotMaxSize })
    .aspectRatio(1)
    .backgroundColor('#00FFFFFF')
  }

  @Builder
  private buildRecycleItem(notebook: Notebook): void {
    Column({ space: 10 }) {
      Text(notebook.title)
        .fontSize($r('app.float.body_text_size'))
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.primary_text'))

      Text(`删除时间：${this.formatTimestamp(typeof notebook.deletedAt === 'number' ? notebook.deletedAt : notebook.updatedAt)}`)
        .fontSize($r('app.float.caption_text_size'))
        .fontColor($r('app.color.secondary_text'))

      Row({ space: 8 }) {
        Button('恢复')
          .layoutWeight(1)
          .height($r('app.float.button_height'))
          .backgroundColor('#EEF2FF')
          .fontColor('#2E6BFF')
          .onClick(() => {
            void this.restoreNotebook(notebook.id);
          })

        Button('彻底删除')
          .layoutWeight(1)
          .height($r('app.float.button_height'))
          .backgroundColor($r('app.color.danger_surface'))
          .fontColor($r('app.color.danger_text'))
          .onClick(() => {
            void this.purgeNotebook(notebook.id);
          })
      }
      .width('100%')
    }
    .width('100%')
    .padding(12)
    .backgroundColor($r('app.color.surface_background'))
    .borderRadius(16)
    .border({
      width: 1,
      color: $r('app.color.card_border')
    })
  }

  @Builder
  private buildNotebookListSection(title: string, notebookList: Notebook[], showTools: boolean = true): void {
    Column({ space: 12 }) {
      this.buildWorkspaceHeader(title, showTools)
      if (showTools) {
        this.buildAllNotesSortFilterPanel()
      }

      if (this.filterNotebookListByWorkspaceFilter(notebookList).length === 0) {
        Text('暂无数据')
          .fontSize($r('app.float.caption_text_size'))
          .fontColor($r('app.color.secondary_text'))
      } else {
        Flex({
          wrap: FlexWrap.Wrap,
          justifyContent: this.getNotebookDisplayGridJustifyContent(),
          alignItems: ItemAlign.Start
        }) {
          ForEach(this.filterNotebookListByWorkspaceFilter(notebookList), (notebook: Notebook) => {
            Column() {
              if (this.useLargeNotebookCards) {
                this.buildLargeNotebookCard(notebook)
              } else {
                this.buildNotebookItem(notebook)
              }
            }
            .width(this.getNotebookDisplayCardWidth())
            .padding({ left: this.gridCardHorizontalInset, right: this.gridCardHorizontalInset })
            .margin({ bottom: 12 })
          }, (notebook: Notebook): string => `${this.notebookListRenderVersion}-${notebook.id}`)
        }
        .width('100%')
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private buildFolderGrid(folderList: NotebookFolder[], keyPrefix: string): void {
    Flex({ wrap: FlexWrap.Wrap, justifyContent: this.getFolderGridJustifyContent(), alignItems: ItemAlign.Start }) {
      ForEach(folderList, (folder: NotebookFolder) => {
        Column() {
          this.buildAllNotesFolderCard(folder)
        }
        .width(this.getFolderCardWidth())
        .padding({ left: this.gridCardHorizontalInset, right: this.gridCardHorizontalInset })
        .margin({ bottom: 12 })
      }, (folder: NotebookFolder): string => `${keyPrefix}-${this.folderListRenderVersion}-${folder.id}`)
    }
    .width('100%')
  }

  @Builder
  private buildNotebookGrid(notebookList: Notebook[], keyPrefix: string): void {
    Flex({
      wrap: FlexWrap.Wrap,
      justifyContent: this.getNotebookDisplayGridJustifyContent(),
      alignItems: ItemAlign.Start
    }) {
      ForEach(notebookList, (notebook: Notebook) => {
        Column() {
          if (this.useLargeNotebookCards) {
            this.buildLargeNotebookCard(notebook)
          } else {
            this.buildNotebookItem(notebook)
          }
        }
        .width(this.getNotebookDisplayCardWidth())
        .padding({ left: this.gridCardHorizontalInset, right: this.gridCardHorizontalInset })
        .margin({ bottom: 12 })
      }, (notebook: Notebook): string => `${keyPrefix}-${this.notebookListRenderVersion}-${this.searchContentRenderVersion}-${notebook.id}`)
    }
    .width('100%')
  }

  @Builder
  private buildAllNotebookCards(notebookList: Notebook[], keyPrefix: string, includeCreateCard: boolean): void {
    Flex({
      wrap: FlexWrap.Wrap,
      justifyContent: this.getNotebookDisplayGridJustifyContent(),
      alignItems: ItemAlign.Start
    }) {
      if (includeCreateCard) {
        Column() {
          this.buildCreateNotebookCard()
        }
        .width(this.getNotebookDisplayCardWidth())
        .padding({ left: this.gridCardHorizontalInset, right: this.gridCardHorizontalInset })
        .margin({ bottom: 12 })
      }

      ForEach(notebookList, (notebook: Notebook) => {
        Column() {
          if (this.useLargeNotebookCards) {
            this.buildLargeNotebookCard(notebook)
          } else {
            this.buildNotebookItem(notebook)
          }
        }
        .width(this.getNotebookDisplayCardWidth())
        .padding({ left: this.gridCardHorizontalInset, right: this.gridCardHorizontalInset })
        .margin({ bottom: 12 })
      }, (notebook: Notebook): string => `${keyPrefix}-${this.notebookListRenderVersion}-${notebook.id}`)
    }
    .width('100%')
  }

  @Builder
  private buildRecentNotebookCard(notebook: Notebook): void {
    Column({ space: 8 }) {
      Stack() {
        Row() {
          this.buildRecentCoverSlot(notebook)
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
      }
      .width('100%')
      .onAreaChange((_oldValue: Area, newValue: Area) => {
        this.updateActionMenuAnchor(notebook.id, newValue);
      })
      .onTouch((event?: TouchEvent) => {
        if (event !== undefined) {
          if (event.type === TouchType.Down) {
            this.updateActionMenuAnchor(notebook.id, event.target.area);
          }
          event.stopPropagation();
        }
      })
      .onClick(() => {
        this.toggleActionMenu(notebook.id);
      })

      Column({ space: 8 }) {
        Text(notebook.title)
          .fontSize($r('app.float.caption_text_size'))
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.primary_text'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text(this.formatTimestamp(notebook.updatedAt))
          .fontSize(11)
          .fontColor($r('app.color.secondary_text'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Row({ space: 6 }) {
          Text(`${NotebookEntity.normalizePageCount(notebook.pageCount)} 页`)
            .fontSize(11)
            .fontColor($r('app.color.secondary_text'))
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        if (this.getNotebookDisplayTags(notebook).length > 0) {
          this.buildTagChipRow(notebook, TagChipDisplayMode.ROOMY)
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .onClick(() => {
        void this.openNotebook(notebook.id);
      })
    }
    .width('100%')
    .height(this.recentNotebookCardHeight)
    .padding(10)
    .backgroundColor($r('app.color.surface_background'))
    .borderRadius(12)
    .border({ width: 1, color: $r('app.color.card_border') })
  }

  @Builder
  private buildLargeNotebookCard(notebook: Notebook): void {
    Column({ space: 8 }) {
      Stack() {
        Row() {
          this.buildRecentCoverSlot(notebook)
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
      }
      .width('100%')
      .onAreaChange((_oldValue: Area, newValue: Area) => {
        this.updateActionMenuAnchor(notebook.id, newValue);
      })
      .onTouch((event?: TouchEvent) => {
        if (event !== undefined) {
          if (event.type === TouchType.Down) {
            this.updateActionMenuAnchor(notebook.id, event.target.area);
          }
          event.stopPropagation();
        }
      })
      .onClick(() => {
        this.toggleActionMenu(notebook.id);
      })

      Column({ space: 8 }) {
        Text(notebook.title)
          .fontSize($r('app.float.caption_text_size'))
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.primary_text'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text(this.formatTimestamp(notebook.updatedAt))
          .fontSize(11)
          .fontColor($r('app.color.secondary_text'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Row({ space: 6 }) {
          Text(`${NotebookEntity.normalizePageCount(notebook.pageCount)} 页`)
            .fontSize(11)
            .fontColor($r('app.color.secondary_text'))
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        if (this.getNotebookDisplayTags(notebook).length > 0) {
          this.buildTagChipRow(notebook, TagChipDisplayMode.ROOMY)
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .onClick(() => {
        void this.openNotebook(notebook.id);
      })
    }
    .width('100%')
    .height(this.recentNotebookCardHeight)
    .padding(10)
    .backgroundColor($r('app.color.surface_background'))
    .borderRadius(12)
    .border({ width: 1, color: $r('app.color.card_border') })
  }

  @Builder
  private buildCreateNotebookListItem(): void {
    Row({ space: 18 }) {
      Column() {
        Text('+')
          .fontSize(36)
          .fontColor('#2E6BFF')
          .fontWeight(FontWeight.Medium)
      }
      .width(76)
      .height(98)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .borderRadius(4)
      .backgroundColor('#EEF2FF')

      Column({ space: 8 }) {
        Text('新建')
          .fontSize(21)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.primary_text'))
          .maxLines(1)

        Text('普通笔记 / 导入文件 / 文件夹')
          .fontSize(15)
          .fontColor($r('app.color.secondary_text'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height(136)
    .padding({ left: 24, right: 20, top: 16, bottom: 16 })
    .alignItems(VerticalAlign.Center)
    .backgroundColor($r('app.color.surface_background'))
    .borderRadius(24)
    .border({ width: 1, color: $r('app.color.card_border') })
    .onAreaChange((_oldValue: Area, newValue: Area) => {
      this.updateCreateActionMenuAnchor(newValue);
    })
    .onTouch((event?: TouchEvent) => {
      if (event !== undefined) {
        if (event.type === TouchType.Down) {
          this.updateCreateActionMenuAnchor(event.target.area);
        }
        event.stopPropagation();
      }
    })
    .onClick(() => {
      this.toggleCreateActionMenu();
    })
  }

  @Builder
  private buildCreateLargeNotebookCard(): void {
    Column({ space: 10 }) {
      Column() {
        Text('+')
          .fontSize(44)
          .fontColor('#2E6BFF')
          .fontWeight(FontWeight.Medium)
      }
      .width('100%')
      .constraintSize({ maxWidth: this.recentCoverSlotMaxSize })
      .aspectRatio(1)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .backgroundColor('#EEF2FF')
      .borderRadius(10)

      Text('新建')
        .fontSize($r('app.float.caption_text_size'))
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.primary_text'))

      Text('普通笔记 / 导入 / 文件夹')
        .fontSize(11)
        .fontColor($r('app.color.secondary_text'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .height(this.recentNotebookCardHeight)
    .padding(10)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor($r('app.color.surface_background'))
    .borderRadius(12)
    .border({ width: 1, color: $r('app.color.card_border') })
    .onAreaChange((_oldValue: Area, newValue: Area) => {
      this.updateCreateActionMenuAnchor(newValue);
    })
    .onTouch((event?: TouchEvent) => {
      if (event !== undefined) {
        if (event.type === TouchType.Down) {
          this.updateCreateActionMenuAnchor(event.target.area);
        }
        event.stopPropagation();
      }
    })
    .onClick(() => {
      this.toggleCreateActionMenu();
    })
  }

  @Builder
  private buildCreateNotebookCard(): void {
    if (this.useLargeNotebookCards) {
      this.buildCreateLargeNotebookCard()
    } else {
      this.buildCreateNotebookListItem()
    }
  }

  private toDisplayImageUri(uri: string): string {
    if (uri.length === 0) {
      return '';
    }
    if (uri.startsWith('file://') || uri.startsWith('http://') || uri.startsWith('https://')) {
      return uri;
    }
    return `file://${uri}`;
  }

  @Builder
  private buildRecentSection(): void {
    Column({ space: 12 }) {
      Row() {
        Text('最近使用')
          .layoutWeight(1)
          .fontSize($r('app.float.section_title_size'))
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.primary_text'))

        Button() {
          Row({ space: 4 }) {
            Text('全部')
              .fontSize($r('app.float.caption_text_size'))
              .fontColor('#2E6BFF')
            Text('›')
              .fontSize(16)
              .fontColor('#2E6BFF')
          }
        }
          .height(30)
          .padding({ left: 8, right: 8 })
          .backgroundColor('#00000000')
          .onClick(() => {
            this.selectSection(SidebarSection.RECENT);
          })
      }
      .width('100%')

      if (this.getRecentOpenedNotebookList().length === 0) {
        Text('暂无数据')
          .fontSize($r('app.float.caption_text_size'))
          .fontColor($r('app.color.secondary_text'))
      } else {
        Flex({ wrap: FlexWrap.Wrap, justifyContent: this.getRecentGridJustifyContent(), alignItems: ItemAlign.Start }) {
          ForEach(this.getRecentOpenedNotebookList(), (notebook: Notebook) => {
            Column() {
              this.buildRecentNotebookCard(notebook)
            }
            .width(this.getRecentCardWidth())
            .padding({ left: this.gridCardHorizontalInset, right: this.gridCardHorizontalInset })
            .margin({ bottom: 12 })
          }, (notebook: Notebook): string => `recent-six-${this.notebookListRenderVersion}-${notebook.id}`)
        }
        .width('100%')
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private buildAllNotesFilterHeader(): void {
    this.buildWorkspaceHeader('全部笔记')
  }

  @Builder
  private buildAllNotesSortFilterPanel(): void {
    if (this.isAllNotesSortFilterPanelVisible) {
      Column({ space: 10 }) {
        Row({ space: 8 }) {
          Button('标签')
            .height(30)
            .padding({ left: 10, right: 10 })
            .backgroundColor(this.allNotesSortFilterType === AllNotesSortFilterType.TAG ? '#E8EEFF' : '#F4F6FB')
            .fontColor(this.allNotesSortFilterType === AllNotesSortFilterType.TAG ? '#2E6BFF' : '#475467')
            .fontSize($r('app.float.caption_text_size'))
            .onClick(() => {
              this.allNotesSortFilterType = AllNotesSortFilterType.TAG;
            })

          Button('创建时间')
            .height(30)
            .padding({ left: 10, right: 10 })
            .backgroundColor(this.allNotesSortFilterType === AllNotesSortFilterType.CREATED_AT ? '#E8EEFF' : '#F4F6FB')
            .fontColor(this.allNotesSortFilterType === AllNotesSortFilterType.CREATED_AT ? '#2E6BFF' : '#475467')
            .fontSize($r('app.float.caption_text_size'))
            .onClick(() => {
              this.allNotesSortFilterType = AllNotesSortFilterType.CREATED_AT;
            })

          Button('修改时间')
            .height(30)
            .padding({ left: 10, right: 10 })
            .backgroundColor(this.allNotesSortFilterType === AllNotesSortFilterType.UPDATED_AT ? '#E8EEFF' : '#F4F6FB')
            .fontColor(this.allNotesSortFilterType === AllNotesSortFilterType.UPDATED_AT ? '#2E6BFF' : '#475467')
            .fontSize($r('app.float.caption_text_size'))
            .onClick(() => {
              this.allNotesSortFilterType = AllNotesSortFilterType.UPDATED_AT;
            })
        }

        if (this.allNotesSortFilterType === AllNotesSortFilterType.TAG) {
          Row({ space: 8 }) {
            Button('全部标签')
              .height(30)
              .padding({ left: 10, right: 10 })
              .backgroundColor(this.allNotesSelectedTagFilter.length === 0 ? '#E8EEFF' : '#F4F6FB')
              .fontColor(this.allNotesSelectedTagFilter.length === 0 ? '#2E6BFF' : '#475467')
              .fontSize($r('app.float.caption_text_size'))
              .onClick(() => {
                this.allNotesSelectedTagFilter = '';
              })

            ForEach(this.getAllTagList(), (tag: string) => {
              Button(tag)
                .height(30)
                .padding({ left: 10, right: 10 })
                .backgroundColor(this.allNotesSelectedTagFilter === tag ? '#E8EEFF' : '#F4F6FB')
                .fontColor(this.allNotesSelectedTagFilter === tag ? '#2E6BFF' : '#475467')
                .fontSize($r('app.float.caption_text_size'))
                .onClick(() => {
                  this.allNotesSelectedTagFilter = tag;
                })
            }, (tag: string): string => `all-notes-filter-tag-${tag}`)
          }
          .width('100%')
        }

        if (this.allNotesSortFilterType === AllNotesSortFilterType.CREATED_AT) {
          Row({ space: 8 }) {
            Button('不限')
              .height(30)
              .padding({ left: 10, right: 10 })
              .backgroundColor(this.allNotesCreatedTimeRange === AllNotesTimeRange.ALL ? '#E8EEFF' : '#F4F6FB')
              .fontColor(this.allNotesCreatedTimeRange === AllNotesTimeRange.ALL ? '#2E6BFF' : '#475467')
              .fontSize($r('app.float.caption_text_size'))
              .onClick(() => {
                this.allNotesCreatedTimeRange = AllNotesTimeRange.ALL;
              })

            Button('今天')
              .height(30)
              .padding({ left: 10, right: 10 })
              .backgroundColor(this.allNotesCreatedTimeRange === AllNotesTimeRange.TODAY ? '#E8EEFF' : '#F4F6FB')
              .fontColor(this.allNotesCreatedTimeRange === AllNotesTimeRange.TODAY ? '#2E6BFF' : '#475467')
              .fontSize($r('app.float.caption_text_size'))
              .onClick(() => {
                this.allNotesCreatedTimeRange = AllNotesTimeRange.TODAY;
              })

            Button('最近7天')
              .height(30)
              .padding({ left: 10, right: 10 })
              .backgroundColor(this.allNotesCreatedTimeRange === AllNotesTimeRange.LAST_7_DAYS ? '#E8EEFF' : '#F4F6FB')
              .fontColor(this.allNotesCreatedTimeRange === AllNotesTimeRange.LAST_7_DAYS ? '#2E6BFF' : '#475467')
              .fontSize($r('app.float.caption_text_size'))
              .onClick(() => {
                this.allNotesCreatedTimeRange = AllNotesTimeRange.LAST_7_DAYS;
              })

            Button('最近30天')
              .height(30)
              .padding({ left: 10, right: 10 })
              .backgroundColor(this.allNotesCreatedTimeRange === AllNotesTimeRange.LAST_30_DAYS ? '#E8EEFF' : '#F4F6FB')
              .fontColor(this.allNotesCreatedTimeRange === AllNotesTimeRange.LAST_30_DAYS ? '#2E6BFF' : '#475467')
              .fontSize($r('app.float.caption_text_size'))
              .onClick(() => {
                this.allNotesCreatedTimeRange = AllNotesTimeRange.LAST_30_DAYS;
              })
          }
          .width('100%')
        }

        if (this.allNotesSortFilterType === AllNotesSortFilterType.UPDATED_AT) {
          Row({ space: 8 }) {
            Button('不限')
              .height(30)
              .padding({ left: 10, right: 10 })
              .backgroundColor(this.allNotesUpdatedTimeRange === AllNotesTimeRange.ALL ? '#E8EEFF' : '#F4F6FB')
              .fontColor(this.allNotesUpdatedTimeRange === AllNotesTimeRange.ALL ? '#2E6BFF' : '#475467')
              .fontSize($r('app.float.caption_text_size'))
              .onClick(() => {
                this.allNotesUpdatedTimeRange = AllNotesTimeRange.ALL;
              })

            Button('今天')
              .height(30)
              .padding({ left: 10, right: 10 })
              .backgroundColor(this.allNotesUpdatedTimeRange === AllNotesTimeRange.TODAY ? '#E8EEFF' : '#F4F6FB')
              .fontColor(this.allNotesUpdatedTimeRange === AllNotesTimeRange.TODAY ? '#2E6BFF' : '#475467')
              .fontSize($r('app.float.caption_text_size'))
              .onClick(() => {
                this.allNotesUpdatedTimeRange = AllNotesTimeRange.TODAY;
              })

            Button('最近7天')
              .height(30)
              .padding({ left: 10, right: 10 })
              .backgroundColor(this.allNotesUpdatedTimeRange === AllNotesTimeRange.LAST_7_DAYS ? '#E8EEFF' : '#F4F6FB')
              .fontColor(this.allNotesUpdatedTimeRange === AllNotesTimeRange.LAST_7_DAYS ? '#2E6BFF' : '#475467')
              .fontSize($r('app.float.caption_text_size'))
              .onClick(() => {
                this.allNotesUpdatedTimeRange = AllNotesTimeRange.LAST_7_DAYS;
              })

            Button('最近30天')
              .height(30)
              .padding({ left: 10, right: 10 })
              .backgroundColor(this.allNotesUpdatedTimeRange === AllNotesTimeRange.LAST_30_DAYS ? '#E8EEFF' : '#F4F6FB')
              .fontColor(this.allNotesUpdatedTimeRange === AllNotesTimeRange.LAST_30_DAYS ? '#2E6BFF' : '#475467')
              .fontSize($r('app.float.caption_text_size'))
              .onClick(() => {
                this.allNotesUpdatedTimeRange = AllNotesTimeRange.LAST_30_DAYS;
              })
          }
          .width('100%')
        }
      }
      .width('100%')
      .padding(10)
      .backgroundColor('#FAFBFF')
      .borderRadius(12)
      .border({ width: 1, color: '#DDE4F0' })
    }
  }

  @Builder
  private buildAllNotesFolderCard(folder: NotebookFolder): void {
    Column({ space: 10 }) {
      Row({ space: 12 }) {
        this.buildFolderIcon(58)

        Column({ space: 6 }) {
          Text(folder.title)
            .fontSize($r('app.float.body_text_size'))
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.primary_text'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          Text(`${this.hasSearchQuery() ? this.getSearchMatchedNotebookCountInFolder(folder.id) :
            this.getFolderNotebookList(folder.id).length} 个笔记本`)
            .fontSize($r('app.float.caption_text_size'))
            .fontColor($r('app.color.secondary_text'))
        }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Text(this.formatFolderActivityTimestamp(folder.id))
        .fontSize(11)
        .fontColor($r('app.color.secondary_text'))

      Row() {
        Blank()
          .layoutWeight(1)

        Button('⋯')
          .width('100%')
          .aspectRatio(1)
          .constraintSize({ maxWidth: 52 })
          .backgroundColor('#00000000')
          .fontColor('#4B5563')
          .fontSize(22)
          .borderRadius(0)
          .stateEffect(false)
          .onAreaChange((_oldValue: Area, newValue: Area) => {
            this.updateFolderActionMenuAnchor(folder.id, newValue);
          })
          .onTouch((event?: TouchEvent) => {
            if (event !== undefined) {
              if (event.type === TouchType.Down) {
                this.updateFolderActionMenuAnchor(folder.id, event.target.area);
              }
              event.stopPropagation();
            }
          })
          .onClick(() => {
            this.toggleFolderActionMenu(folder.id);
          })
      }
      .width('100%')
      .constraintSize({ minHeight: 34 })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(12)
    .backgroundColor($r('app.color.surface_background'))
    .borderRadius(14)
    .border({ width: 1, color: $r('app.color.card_border') })
    .onClick(() => {
      this.selectSection(SidebarSection.FOLDERS);
      this.selectedFolderInSidebar = folder.id;
    })
  }

  @Builder
  private buildSearchWorkspace(): void {
    Column({ space: 16 }) {
      this.buildWorkspaceHeader(`搜索：${this.searchText.trim()}`)
      this.buildAllNotesSortFilterPanel()

      Text(this.isSearchContentLoading ? '正在搜索笔记内容...' :
        `${this.getSearchMatchedNotebookList().length} 个笔记本，${this.getSearchMatchedFolderList().length} 个文件夹`)
        .fontSize($r('app.float.caption_text_size'))
        .fontColor($r('app.color.secondary_text'))

      if (this.filterNotebookListByWorkspaceFilter(this.getSearchMatchedNotebookList()).length === 0 &&
        this.getSearchMatchedFolderList().length === 0) {
        Text(this.isSearchContentLoading ? '正在读取笔记内容...' : '没有找到匹配结果')
          .fontSize($r('app.float.caption_text_size'))
          .fontColor($r('app.color.secondary_text'))
      } else {
        if (this.getSearchMatchedFolderList().length > 0) {
          Column({ space: 10 }) {
            Text('文件夹')
              .fontSize($r('app.float.body_text_size'))
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.primary_text'))

            this.buildFolderGrid(this.getSearchMatchedFolderList(), 'search-folder')
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }

        if (this.filterNotebookListByWorkspaceFilter(this.getSearchMatchedNotebookList()).length > 0) {
          Column({ space: 10 }) {
            Text('笔记本')
              .fontSize($r('app.float.body_text_size'))
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.primary_text'))

            this.buildNotebookGrid(this.filterNotebookListByWorkspaceFilter(this.getSearchMatchedNotebookList()), 'search-notebook')
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private buildAllNotesSection(): void {
    Column({ space: 12 }) {
      this.buildAllNotesFilterHeader()
      this.buildAllNotesSortFilterPanel()

      this.buildAllNotebookCards(this.getFilteredActiveNotebookList(), 'all-notes-notebook', true)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private buildFolderWorkspace(): void {
    Column({ space: 12 }) {
      this.buildWorkspaceHeader('文件夹')
      this.buildAllNotesSortFilterPanel()

      if (this.selectedFolderInSidebar.length > 0) {
        this.buildNotebookListSection('该文件夹中的笔记', this.getFolderNotebookList(this.selectedFolderInSidebar), false)
      } else {
        if (this.folderList.length === 0) {
          Text('暂无文件夹')
            .fontSize($r('app.float.caption_text_size'))
            .fontColor($r('app.color.secondary_text'))
        } else {
          Flex({ wrap: FlexWrap.Wrap, justifyContent: this.getFolderGridJustifyContent(), alignItems: ItemAlign.Start }) {
            ForEach(this.getSortedFolderListForAllNotes(), (folder: NotebookFolder) => {
              Column() {
                this.buildAllNotesFolderCard(folder)
              }
              .width(this.getFolderCardWidth())
              .padding({ left: this.gridCardHorizontalInset, right: this.gridCardHorizontalInset })
              .margin({ bottom: 12 })
            }, (folder: NotebookFolder): string => `folder-workspace-card-${this.folderListRenderVersion}-${folder.id}`)
          }
          .width('100%')
        }
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private buildTagWorkspace(): void {
    Column({ space: 12 }) {
      this.buildWorkspaceHeader('标签')
      this.buildAllNotesSortFilterPanel()

      if (this.getAllTagList().length > 0) {
        Row({ space: 8 }) {
          Button('全部')
            .height(34)
            .backgroundColor(this.selectedTag.length === 0 ? '#332E6BFF' : '#EEF2FF')
            .fontColor(this.selectedTag.length === 0 ? '#2E6BFF' : '#475467')
            .onClick(() => {
              this.selectedTag = '';
            })

          ForEach(this.getAllTagList(), (tag: string) => {
            Button(tag)
              .height(34)
              .backgroundColor(this.selectedTag === tag ? '#332E6BFF' : '#EEF2FF')
              .fontColor(this.selectedTag === tag ? '#2E6BFF' : '#475467')
              .onClick(() => {
                this.selectedTag = tag;
              })
          }, (tag: string): string => tag)
        }
        .width('100%')
      } else {
        Text('还没有标签')
          .fontSize($r('app.float.caption_text_size'))
          .fontColor($r('app.color.secondary_text'))
      }

      if (this.selectedTag.length > 0) {
        this.buildNotebookListSection(`标签：${this.selectedTag}`, this.getTagNotebookList(this.selectedTag), false)
      } else {
        if (this.getAllTagList().length === 0) {
          // no-op: empty hint rendered above
        } else {
          ForEach(this.getAllTagList(), (tag: string) => {
            this.buildNotebookListSection(tag, this.getTagNotebookList(tag), false)
          }, (tag: string): string => tag)
        }
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private buildRecycleWorkspace(): void {
    Column({ space: 12 }) {
      this.buildWorkspaceHeader('回收站', false)

      if (this.getDeletedNotebookList().length === 0) {
        Text('回收站为空')
          .fontSize($r('app.float.caption_text_size'))
          .fontColor($r('app.color.secondary_text'))
      } else {
        Column({ space: 12 }) {
          ForEach(this.getDeletedNotebookList(), (notebook: Notebook) => {
            this.buildRecycleItem(notebook)
          }, (notebook: Notebook): string => `${this.notebookListRenderVersion}-${notebook.id}`)
        }
        .width('100%')
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private buildFolderOverviewSection(): void {
    Column({ space: 12 }) {
      Row() {
        Text('我的文件夹')
          .layoutWeight(1)
          .fontSize($r('app.float.section_title_size'))
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.primary_text'))

        Button() {
          Row({ space: 4 }) {
            Text('全部')
              .fontSize($r('app.float.caption_text_size'))
              .fontColor('#2E6BFF')
            Text('›')
              .fontSize(16)
              .fontColor('#2E6BFF')
          }
        }
          .height(30)
          .padding({ left: 8, right: 8 })
          .backgroundColor('#00000000')
          .onClick(() => {
            this.selectSection(SidebarSection.FOLDERS);
          })
      }
      .width('100%')

      if (this.folderList.length === 0) {
        Text('暂无文件夹')
          .fontSize($r('app.float.caption_text_size'))
          .fontColor($r('app.color.secondary_text'))
      } else {
        Flex({ wrap: FlexWrap.Wrap, justifyContent: this.getFolderGridJustifyContent(), alignItems: ItemAlign.Start }) {
          ForEach(this.getSortedFolderListForAllNotes(), (folder: NotebookFolder) => {
            Column() {
              this.buildAllNotesFolderCard(folder)
            }
            .width(this.getFolderCardWidth())
            .padding({ left: this.gridCardHorizontalInset, right: this.gridCardHorizontalInset })
            .margin({ bottom: 12 })
          }, (folder: NotebookFolder): string => `${this.folderListRenderVersion}-${folder.id}`)
        }
        .width('100%')
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private buildAllWorkspace(): void {
    Column({ space: 20 }) {
      this.buildAllNotesSection()
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private buildWorkspace(): void {
    if (this.hasSearchQuery()) {
      this.buildSearchWorkspace()
    } else if (this.currentSection === SidebarSection.ALL) {
      this.buildAllWorkspace()
    } else if (this.currentSection === SidebarSection.RECENT) {
      this.buildNotebookListSection('最近使用', this.getRecentOpenedNotebookList(true))
    } else if (this.currentSection === SidebarSection.FAVORITES) {
      this.buildNotebookListSection('收藏夹', this.getFavoriteNotebookList())
    } else if (this.currentSection === SidebarSection.FOLDERS) {
      this.buildFolderWorkspace()
    } else if (this.currentSection === SidebarSection.TAGS) {
      this.buildTagWorkspace()
    } else {
      this.buildRecycleWorkspace()
    }
  }

  @Builder
  private buildActionMenuOverlay(): void {
    if (this.activeActionMenuNotebookId.length > 0) {
      Column({ space: 0 }) {
        Button('重命名')
          .width('100%')
          .height(42)
          .backgroundColor('#00FFFFFF')
          .fontColor($r('app.color.primary_text'))
          .borderRadius(8)
          .onClick(() => {
            this.openRenameDialogFromActionMenu();
          })

        Button('移动...')
          .width('100%')
          .height(42)
          .backgroundColor('#00FFFFFF')
          .fontColor($r('app.color.primary_text'))
          .borderRadius(8)
          .onClick(() => {
            this.openMoveDialogFromActionMenu();
          })

        Button('导出为…')
          .width('100%')
          .height(42)
          .backgroundColor('#00FFFFFF')
          .fontColor($r('app.color.primary_text'))
          .borderRadius(8)
          .onClick(() => {
            this.openExportDialogFromActionMenu();
          })

        Divider()
          .strokeWidth(1)
          .color('#E6EAF2')
          .margin({ top: 4, bottom: 4 })

        Button('标签...')
          .width('100%')
          .height(42)
          .backgroundColor('#00FFFFFF')
          .fontColor($r('app.color.primary_text'))
          .borderRadius(8)
          .onClick(() => {
            this.openTagDialogFromActionMenu();
          })

        Button('更换封面…')
          .width('100%')
          .height(42)
          .backgroundColor('#00FFFFFF')
          .fontColor($r('app.color.primary_text'))
          .borderRadius(8)
          .onClick(() => {
            this.openNotebookCoverDialogFromActionMenu();
          })

        Divider()
          .strokeWidth(1)
          .color('#E6EAF2')
          .margin({ top: 4, bottom: 4 })

        Button('删除')
          .width('100%')
          .height(42)
          .backgroundColor('#00FFFFFF')
          .fontColor($r('app.color.danger_text'))
          .borderRadius(8)
          .onClick(() => {
            this.openDeleteDialogFromActionMenu();
          })
      }
      .width(this.actionMenuWidth)
      .padding(10)
      .backgroundColor('#D9FFFFFF')
      .borderRadius(16)
      .border({ width: 1, color: '#D8DEE9' })
      .shadow({
        radius: 14,
        color: '#2A000000',
        offsetX: 0,
        offsetY: 6
      })
      .position(this.getActiveActionMenuPosition())
      .zIndex(20)
      .onTouch((event?: TouchEvent) => {
        if (event !== undefined) {
          event.stopPropagation();
        }
      })
    }

    if (this.activeFolderActionMenuFolderId.length > 0) {
      Column({ space: 0 }) {
        Button('颜色...')
          .width('100%')
          .height(42)
          .backgroundColor('#00FFFFFF')
          .fontColor($r('app.color.primary_text'))
          .borderRadius(8)
          .onClick(() => {
            this.openFolderColorDialog(this.activeFolderActionMenuFolderId);
          })

        Button('重命名')
          .width('100%')
          .height(42)
          .backgroundColor('#00FFFFFF')
          .fontColor($r('app.color.primary_text'))
          .borderRadius(8)
          .onClick(() => {
            this.openFolderRenameDialog(this.activeFolderActionMenuFolderId);
          })

        Divider()
          .strokeWidth(1)
          .color('#E6EAF2')
          .margin({ top: 4, bottom: 4 })

        Button('删除')
          .width('100%')
          .height(42)
          .backgroundColor('#00FFFFFF')
          .fontColor($r('app.color.danger_text'))
          .borderRadius(8)
          .onClick(() => {
            this.openFolderDeleteDialog(this.activeFolderActionMenuFolderId);
          })
      }
      .width(this.folderActionMenuWidth)
      .padding(10)
      .backgroundColor('#D9FFFFFF')
      .borderRadius(16)
      .border({ width: 1, color: '#D8DEE9' })
      .shadow({
        radius: 14,
        color: '#2A000000',
        offsetX: 0,
        offsetY: 6
      })
      .position(this.getActiveFolderActionMenuPosition())
      .zIndex(20)
      .onTouch((event?: TouchEvent) => {
        if (event !== undefined) {
          event.stopPropagation();
        }
      })
    }

    if (this.isCreateActionMenuVisible) {
      Column({ space: 0 }) {
        Button('新建普通笔记')
          .width('100%')
          .height(42)
          .backgroundColor('#00FFFFFF')
          .fontColor($r('app.color.primary_text'))
          .borderRadius(8)
          .onClick(() => {
            this.openCreateDialogFromCreateMenu();
          })

        Button('导入文件')
          .width('100%')
          .height(42)
          .backgroundColor('#00FFFFFF')
          .fontColor($r('app.color.primary_text'))
          .borderRadius(8)
          .onClick(() => {
            this.importNotebookFromCreateMenu();
          })

        Divider()
          .strokeWidth(1)
          .color('#E6EAF2')
          .margin({ top: 4, bottom: 4 })

        Button('新建文件夹')
          .width('100%')
          .height(42)
          .backgroundColor('#00FFFFFF')
          .fontColor($r('app.color.primary_text'))
          .borderRadius(8)
          .onClick(() => {
            this.openFolderDialogFromCreateMenu();
          })
      }
      .width(this.folderActionMenuWidth)
      .padding(10)
      .backgroundColor('#D9FFFFFF')
      .borderRadius(16)
      .border({ width: 1, color: '#D8DEE9' })
      .shadow({
        radius: 14,
        color: '#2A000000',
        offsetX: 0,
        offsetY: 6
      })
      .position(this.getCreateActionMenuPosition())
      .zIndex(20)
      .onTouch((event?: TouchEvent) => {
        if (event !== undefined) {
          event.stopPropagation();
        }
      })
    }

    if (this.isTopSortDropdownVisible) {
      Column({ space: 4 }) {
        this.buildSortOption('首字母', NotebookSortType.TITLE_ASC)
        this.buildSortOption('最新更新', NotebookSortType.UPDATED_DESC)
        this.buildSortOption('最近创建', NotebookSortType.CREATED_DESC)
      }
      .width(this.sortMenuWidth)
      .padding(6)
      .backgroundColor('#FFFFFF')
      .borderRadius(10)
      .border({ width: 1, color: '#D8DEE9' })
      .shadow({
        radius: 12,
        color: '#22000000',
        offsetX: 0,
        offsetY: 6
      })
      .position(this.getTopSortMenuPosition())
      .zIndex(20)
      .onTouch((event?: TouchEvent) => {
        if (event !== undefined) {
          event.stopPropagation();
        }
      })
    }
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Row({ space: 0 }) {
        if (!this.isSidebarCollapsed) {
          Column({ space: 8 }) {
            this.buildSidebarItem(SidebarSection.ALL, '全部笔记')
            this.buildSidebarItem(SidebarSection.RECENT, '最近使用')
            this.buildSidebarItem(SidebarSection.FAVORITES, '收藏夹')

            Divider()
              .strokeWidth(1)
              .color('#DDE4F0')
              .margin({ top: 6, bottom: 6 })

            this.buildSidebarItem(SidebarSection.FOLDERS, '文件夹')
            if (this.currentSection === SidebarSection.FOLDERS) {
              Column({ space: 4 }) {
                ForEach(this.folderList, (folder: NotebookFolder) => {
                  this.buildSidebarFolderItem(folder)
                }, (folder: NotebookFolder): string => folder.id)
              }
              .width('100%')
            }

            this.buildSidebarItem(SidebarSection.TAGS, '标签')
            if (this.currentSection === SidebarSection.TAGS) {
              Column({ space: 4 }) {
                ForEach(this.getAllTagList(), (tag: string) => {
                  this.buildSidebarTagItem(tag)
                }, (tag: string): string => tag)
              }
              .width('100%')
            }

            this.buildSidebarItem(SidebarSection.RECYCLE, '回收站')
          }
          .width(this.getSidebarWidth())
          .height('100%')
          .padding(12)
          .backgroundColor('#F8FAFF')
          .border({ width: { right: 1 }, color: '#D8DEE9' })
        }

        Column({ space: 12 }) {
          Stack({ alignContent: Alignment.TopStart }) {
            if (this.isLoading) {
              Column({ space: 12 }) {
                LoadingProgress()
                  .width(36)
                  .height(36)

                Text('加载中...')
                  .fontSize($r('app.float.caption_text_size'))
                  .fontColor($r('app.color.secondary_text'))
              }
              .width('100%')
              .padding(32)
              .backgroundColor($r('app.color.surface_background'))
              .borderRadius($r('app.float.card_radius'))
              .border({ width: 1, color: $r('app.color.card_border') })
            } else {
              Scroll() {
                Column({ space: 12 }) {
                  this.buildWorkspace()
                }
                .width('100%')
                .alignItems(HorizontalAlign.Start)
                .padding({ bottom: 24 })
              }
              .width('100%')
              .height('100%')
              .align(Alignment.TopStart)
              .onDidScroll((_xOffset: number, yOffset: number, _scrollState: ScrollState) => {
                if (Number.isFinite(yOffset)) {
                  this.workspaceScrollOffsetY = Math.max(0, yOffset);
                }
              })
            }

            this.buildActionMenuOverlay()
          }
          .clip(true)
          .width('100%')
          .layoutWeight(1)
          .onAreaChange((_oldValue: Area, newValue: Area) => {
            this.updateWorkspaceArea(newValue);
          })
          .onTouch((event?: TouchEvent) => {
            if (event === undefined || event.type !== TouchType.Down) {
              return;
            }
            if (this.activeActionMenuNotebookId.length > 0) {
              this.closeActionMenu();
            }
            if (this.activeFolderActionMenuFolderId.length > 0) {
              this.closeFolderActionMenu();
            }
            if (this.isCreateActionMenuVisible) {
              this.closeCreateActionMenu();
            }
            if (this.isTopSortDropdownVisible) {
              this.closeTopSortDropdown();
            }
          })
        }
        .layoutWeight(1)
        .height('100%')
        .alignItems(HorizontalAlign.Start)
        .padding(16)
      }
      .width('100%')
      .height('100%')
      .onAreaChange((_oldValue: Area, newValue: Area) => {
        this.updatePanelArea(newValue);
      })

      if (this.isExportDialogVisible) {
        Column() {
          NotebookExportDialog({
            fileName: $draftExportFileName,
            outputPath: $draftExportPath,
            selectedFormat: $draftExportFormat,
            selectedScope: $draftExportScope,
            pageRange: $draftExportPageRange,
            notebookTitle: this.exportTargetNotebookTitle,
            isChoosingPath: this.isPickingExportPath,
            isExporting: this.isExportingNotebook,
            showScopeOptions: false,
            onCancel: (): void => {
              this.closeExportDialog();
            },
            onChoosePath: (): void => {
              void this.selectExportPathFromDialog();
            },
            onConfirm: (): void => {
              void this.confirmExportDialog();
            },
            onFormatChange: (format: string): void => {
              this.changeExportFormat(format);
            },
            onPageRangeChange: (range: string): void => {
              this.draftExportPageRange = range;
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

      if (this.isDeleteDialogVisible) {
        Column() {
          Column({ space: 16 }) {
            Text('确认移入回收站？')
              .fontSize($r('app.float.section_title_size'))
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.primary_text'))

            Text(`笔记本：${this.deleteTargetNotebookTitle}`)
              .fontSize($r('app.float.body_text_size'))
              .fontColor($r('app.color.primary_text'))

            Row({ space: 12 }) {
              Button('取消')
                .layoutWeight(1)
                .height($r('app.float.button_height'))
                .backgroundColor($r('app.color.app_background'))
                .fontColor($r('app.color.primary_text'))
                .onClick(() => {
                  this.closeDeleteDialog();
                })

              Button(this.isDeletingNotebook ? '处理中...' : '确认')
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
          .border({ width: 1, color: $r('app.color.card_border') })
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
            selectedColor: $draftFolderColor,
            colorPalette: NotebookFolderEntity.COLOR_PALETTE,
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

      if (this.isFolderRenameDialogVisible) {
        Column() {
          Column({ space: 16 }) {
            Column({ space: 6 }) {
              Text('重命名文件夹')
                .fontSize($r('app.float.section_title_size'))
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.primary_text'))

              Text('修改文件夹名称')
                .fontSize($r('app.float.caption_text_size'))
                .fontColor($r('app.color.secondary_text'))
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)

            TextInput({
              placeholder: '请输入文件夹名称',
              text: this.draftFolderRenameTitle
            })
              .width('100%')
              .height($r('app.float.button_height'))
              .fontSize($r('app.float.body_text_size'))
              .backgroundColor($r('app.color.app_background'))
              .borderRadius($r('app.float.card_radius'))
              .padding({ left: 16, right: 16 })
              .onChange((value: string) => {
                this.draftFolderRenameTitle = value;
              })

            Row({ space: 12 }) {
              Button('取消')
                .layoutWeight(1)
                .height($r('app.float.button_height'))
                .backgroundColor($r('app.color.app_background'))
                .fontColor($r('app.color.primary_text'))
                .onClick(() => {
                  this.closeFolderRenameDialog();
                })

              Button(this.isRenamingFolder ? '处理中...' : '确认')
                .layoutWeight(1)
                .height($r('app.float.button_height'))
                .backgroundColor($r('app.color.primary_text'))
                .fontColor($r('app.color.inverse_text'))
                .onClick(() => {
                  this.submitFolderRenameDialog();
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
          .border({ width: 1, color: $r('app.color.card_border') })
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

      if (this.isFolderColorDialogVisible) {
        Column() {
          Column({ space: 16 }) {
            Column({ space: 6 }) {
              Text('文件夹颜色')
                .fontSize($r('app.float.section_title_size'))
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.primary_text'))

              Text('RGB 颜色选择')
                .fontSize($r('app.float.caption_text_size'))
                .fontColor($r('app.color.secondary_text'))
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)

            Row({ space: 10 }) {
              Column() {}
                .width(44)
                .height(44)
                .borderRadius(8)
                .backgroundColor(this.draftFolderEditColor)
                .border({ width: 1, color: '#D0D5DD' })

              Text(this.draftFolderEditColor)
                .fontSize(12)
                .fontColor('#667085')
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)

            this.buildRgbSliderLine('R', this.folderEditColorR, '#EF4444', (value: number): void => {
              this.folderEditColorR = value;
              this.syncEditColorFromRgb();
            })
            this.buildRgbSliderLine('G', this.folderEditColorG, '#22C55E', (value: number): void => {
              this.folderEditColorG = value;
              this.syncEditColorFromRgb();
            })
            this.buildRgbSliderLine('B', this.folderEditColorB, '#3B82F6', (value: number): void => {
              this.folderEditColorB = value;
              this.syncEditColorFromRgb();
            })

            Row({ space: 12 }) {
              Button('取消')
                .layoutWeight(1)
                .height($r('app.float.button_height'))
                .backgroundColor($r('app.color.app_background'))
                .fontColor($r('app.color.primary_text'))
                .onClick(() => {
                  this.closeFolderColorDialog();
                })

              Button(this.isUpdatingFolderColor ? '处理中...' : '确认')
                .layoutWeight(1)
                .height($r('app.float.button_height'))
                .backgroundColor($r('app.color.primary_text'))
                .fontColor($r('app.color.inverse_text'))
                .onClick(() => {
                  this.submitFolderColorDialog();
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
          .border({ width: 1, color: $r('app.color.card_border') })
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

      if (this.isNotebookCoverDialogVisible) {
        Column() {
          Column({ space: 16 }) {
            Column({ space: 6 }) {
              Text('更换封面')
                .fontSize($r('app.float.section_title_size'))
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.primary_text'))

              Text(this.notebookCoverTargetTitle)
                .fontSize($r('app.float.caption_text_size'))
                .fontColor($r('app.color.secondary_text'))
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)

            Button(this.isPickingNotebookCover ? '选择中...' : '上传封面图')
              .width('100%')
              .height($r('app.float.button_height'))
              .backgroundColor('#EEF2FF')
              .fontColor('#2E6BFF')
              .enabled(!this.isPickingNotebookCover && !this.isUpdatingNotebookCover)
              .onClick(() => {
                void this.selectNotebookCoverImageFromDialog();
              })

            Divider()
              .strokeWidth(1)
              .color('#E6EAF2')

            Text('纯色标题封面')
              .fontSize($r('app.float.body_text_size'))
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.primary_text'))

            Row({ space: 10 }) {
              Column() {
                Text(this.notebookCoverTargetTitle.length > 12 ? `${this.notebookCoverTargetTitle.slice(0, 12)}...` :
                  this.notebookCoverTargetTitle)
                  .fontSize(12)
                  .fontColor('#FFFFFF')
                  .fontWeight(FontWeight.Medium)
                  .maxLines(2)
                  .textAlign(TextAlign.Center)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .padding({ left: 8, right: 8 })
              }
              .width(92)
              .height(58)
              .justifyContent(FlexAlign.Center)
              .alignItems(HorizontalAlign.Center)
              .borderRadius(10)
              .backgroundColor(this.draftNotebookColor)
              .border({ width: 1, color: '#D0D5DD' })

              Text(this.draftNotebookColor)
                .fontSize(12)
                .fontColor('#667085')
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)

            this.buildRgbSliderLine('R', this.notebookColorR, '#EF4444', (value: number): void => {
              this.notebookColorR = value;
              this.syncNotebookColorFromRgb();
            })
            this.buildRgbSliderLine('G', this.notebookColorG, '#22C55E', (value: number): void => {
              this.notebookColorG = value;
              this.syncNotebookColorFromRgb();
            })
            this.buildRgbSliderLine('B', this.notebookColorB, '#3B82F6', (value: number): void => {
              this.notebookColorB = value;
              this.syncNotebookColorFromRgb();
            })

            Row({ space: 12 }) {
              Button('取消')
                .layoutWeight(1)
                .height($r('app.float.button_height'))
                .backgroundColor($r('app.color.app_background'))
                .fontColor($r('app.color.primary_text'))
                .enabled(!this.isPickingNotebookCover && !this.isUpdatingNotebookCover)
                .onClick(() => {
                  this.closeNotebookCoverDialog();
                })

              Button(this.isUpdatingNotebookCover ? '处理中...' : '使用纯色')
                .layoutWeight(1)
                .height($r('app.float.button_height'))
                .backgroundColor($r('app.color.primary_text'))
                .fontColor($r('app.color.inverse_text'))
                .enabled(!this.isPickingNotebookCover && !this.isUpdatingNotebookCover)
                .onClick(() => {
                  void this.applyNotebookTitleCoverFromDialog();
                })
            }
            .width('100%')

            Button('使用默认缩略图封面')
              .width('100%')
              .height($r('app.float.button_height'))
              .backgroundColor('#F7F8FC')
              .fontColor($r('app.color.primary_text'))
              .enabled(!this.isPickingNotebookCover && !this.isUpdatingNotebookCover)
              .onClick(() => {
                void this.applyDefaultNotebookCoverFromDialog();
              })
          }
          .width('100%')
          .constraintSize({ maxWidth: 560 })
          .alignItems(HorizontalAlign.Start)
          .padding(24)
          .backgroundColor($r('app.color.surface_background'))
          .borderRadius($r('app.float.card_radius'))
          .border({ width: 1, color: $r('app.color.card_border') })
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

      if (this.isFolderDeleteDialogVisible) {
        Column() {
          Column({ space: 16 }) {
            Text(`确认删除文件夹“${this.folderDeleteTargetTitle}”？`)
              .fontSize($r('app.float.section_title_size'))
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.primary_text'))

            Text('文件夹内笔记本将移动到未归类。')
              .fontSize($r('app.float.caption_text_size'))
              .fontColor($r('app.color.secondary_text'))

            Row({ space: 12 }) {
              Button('取消')
                .layoutWeight(1)
                .height($r('app.float.button_height'))
                .backgroundColor($r('app.color.app_background'))
                .fontColor($r('app.color.primary_text'))
                .onClick(() => {
                  this.closeFolderDeleteDialog();
                })

              Button(this.isDeletingFolder ? '处理中...' : '确认删除')
                .layoutWeight(1)
                .height($r('app.float.button_height'))
                .backgroundColor($r('app.color.danger_text'))
                .fontColor($r('app.color.inverse_text'))
                .onClick(() => {
                  this.submitFolderDeleteDialog();
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
          .border({ width: 1, color: $r('app.color.card_border') })
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

      if (this.isTagDialogVisible) {
        Column() {
          Column({ space: 12 }) {
            Text('编辑标签')
              .fontSize($r('app.float.section_title_size'))
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.primary_text'))

            Text(`笔记本：${this.tagTargetNotebookTitle}`)
              .fontSize($r('app.float.caption_text_size'))
              .fontColor($r('app.color.secondary_text'))

            this.buildTagDialogBody()
          }
          .width('100%')
          .constraintSize({ maxWidth: 560 })
          .alignItems(HorizontalAlign.Start)
          .padding(24)
          .backgroundColor($r('app.color.surface_background'))
          .borderRadius($r('app.float.card_radius'))
          .border({ width: 1, color: $r('app.color.card_border') })
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

      if (this.importFailureMessage.length > 0) {
        Column() {
          Column({ space: 16 }) {
            Text('导入未完成')
              .fontSize($r('app.float.section_title_size'))
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.primary_text'))

            Text(this.importFailureMessage)
              .fontSize($r('app.float.body_text_size'))
              .fontColor($r('app.color.secondary_text'))

            Button('知道了')
              .width('100%')
              .height($r('app.float.button_height'))
              .backgroundColor($r('app.color.editor_accent'))
              .fontColor($r('app.color.inverse_text'))
              .onClick(() => {
                this.closeImportFailureMessage();
              })
          }
          .width('100%')
          .constraintSize({ maxWidth: 560 })
          .alignItems(HorizontalAlign.Start)
          .padding(24)
          .backgroundColor($r('app.color.surface_background'))
          .borderRadius($r('app.float.card_radius'))
          .border({ width: 1, color: $r('app.color.card_border') })
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

      if (this.exportFailureMessage.length > 0) {
        Column() {
          Column({ space: 16 }) {
            Text('导出未完成')
              .fontSize($r('app.float.section_title_size'))
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.primary_text'))

            Text(this.exportFailureMessage)
              .fontSize($r('app.float.body_text_size'))
              .fontColor($r('app.color.secondary_text'))

            Button('知道了')
              .width('100%')
              .height($r('app.float.button_height'))
              .backgroundColor($r('app.color.editor_accent'))
              .fontColor($r('app.color.inverse_text'))
              .onClick(() => {
                this.closeExportFailureMessage();
              })
          }
          .width('100%')
          .constraintSize({ maxWidth: 560 })
          .alignItems(HorizontalAlign.Start)
          .padding(24)
          .backgroundColor($r('app.color.surface_background'))
          .borderRadius($r('app.float.card_radius'))
          .border({ width: 1, color: $r('app.color.card_border') })
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
    .backgroundColor('#FCFDFF')
  }
}




