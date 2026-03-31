import common from '@ohos.app.ability.common';
import { CanvasEditor } from '../components/CanvasEditor';
import { PageThumbnail } from '../components/PageThumbnail';
import { NotePage } from '../models/NotePage';
import { Notebook } from '../models/Notebook';
import { NotePageRepository } from '../services/NotePageRepository';
import { NotebookRepository } from '../services/NotebookRepository';
import { StrokeRepository } from '../services/StrokeRepository';
import { formatError } from '../utils/ErrorUtils';

interface NotebookRouteParams {
  notebookId?: string;
}

@Entry
@Component
struct NotebookDetail {
  @State private notebook: Notebook | null = null;
  @State private pages: NotePage[] = [];
  @State private selectedPageId: string = '';
  @State private errorMessage: string = '';
  @State private isLoading: boolean = true;
  @Watch('handleRefreshSignalChange') @StorageLink('page_thumbnail_refresh_signal') private pageThumbnailRefreshSignal: string = '';

  private notebookRepository?: NotebookRepository;
  private pageRepository?: NotePageRepository;
  private strokeRepository?: StrokeRepository;
  private notebookId: string = '';

  async aboutToAppear(): Promise<void> {
    this.notebookId = this.readNotebookId();
    await this.loadData();
  }

  build() {
    Column({ space: 16 }) {
      this.buildTopBar()

      if (this.errorMessage.length > 0) {
        Text(this.errorMessage)
          .width('100%')
          .fontSize(13)
          .fontColor('#B91C1C')
          .textAlign(TextAlign.Start)
      }

      if (this.isLoading) {
        this.buildLoading()
      } else if (!this.notebook) {
        this.buildMissingNotebook()
      } else {
        Row({ space: 16 }) {
          this.buildPageListPanel()
          this.buildPagePreviewPanel()
        }
        .layoutWeight(1)
        .width('100%')
        .alignItems(VerticalAlign.Top)
      }
    }
    .width('100%')
    .height('100%')
    .padding({ left: 24, right: 24, top: 24, bottom: 24 })
    .backgroundColor('#F8FAFC')
  }

  @Builder
  private buildTopBar(): void {
    Row() {
      Button('Back')
        .backgroundColor('#E2E8F0')
        .fontColor('#334155')
        .borderRadius(12)
        .onClick(() => {
          this.getUIContext().getRouter().back();
        })

      Blank()

      Column({ space: 4 }) {
        Text(this.notebook?.title ?? 'Notebook')
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor('#0F172A')
          .textAlign(TextAlign.End)

        Text('Pages, thumbnails, and handwriting canvas MVP')
          .fontSize(13)
          .fontColor('#64748B')
      }
      .alignItems(HorizontalAlign.End)
    }
    .width('100%')
  }

  @Builder
  private buildLoading(): void {
    Column({ space: 12 }) {
      LoadingProgress()
        .width(32)
        .height(32)
        .color('#1D4ED8')

      Text('Loading notebook...')
        .fontSize(14)
        .fontColor('#64748B')
    }
    .justifyContent(FlexAlign.Center)
    .layoutWeight(1)
    .width('100%')
  }

  @Builder
  private buildMissingNotebook(): void {
    Column({ space: 12 }) {
      Text('Notebook not found')
        .fontSize(24)
        .fontWeight(FontWeight.Medium)
        .fontColor('#0F172A')

      Text('The notebook may have been deleted or the route parameter is missing.')
        .fontSize(14)
        .fontColor('#64748B')
        .textAlign(TextAlign.Center)
        .lineHeight(22)
    }
    .justifyContent(FlexAlign.Center)
    .layoutWeight(1)
    .width('100%')
    .padding(24)
    .backgroundColor('#FFFFFF')
    .borderRadius(20)
  }

  @Builder
  private buildPageListPanel(): void {
    Column({ space: 14 }) {
      Row() {
        Text('Pages')
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .fontColor('#0F172A')

        Blank()

        Button('New Page')
          .backgroundColor('#1D4ED8')
          .fontColor('#FFFFFF')
          .borderRadius(12)
          .onClick(() => {
            void this.createPage();
          })
      }
      .width('100%')

      if (this.pages.length === 0) {
        Column({ space: 10 }) {
          Text('No pages yet')
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .fontColor('#0F172A')

          Text('Create the first page for this notebook.')
            .fontSize(14)
            .fontColor('#64748B')
        }
        .justifyContent(FlexAlign.Center)
        .width('100%')
        .layoutWeight(1)
        .padding(16)
        .backgroundColor('#FFFFFF')
        .borderRadius(18)
      } else {
        List({ space: 10 }) {
          ForEach(this.pages, (item: NotePage) => {
            ListItem() {
              this.buildPageRow(item)
            }
          }, (item: NotePage) => item.id)
        }
        .layoutWeight(1)
        .width('100%')
        .divider({ strokeWidth: 0 })
        .scrollBar(BarState.Off)
      }
    }
    .layoutWeight(1)
    .height('100%')
    .padding(18)
    .backgroundColor('#E0F2FE')
    .borderRadius(22)
  }

  @Builder
  private buildPageRow(item: NotePage): void {
    Row({ space: 12 }) {
      PageThumbnail({
        pageId: item.id,
        pageUpdatedAt: item.updatedAt,
        strokeCount: item.strokeIds.length
      })

      Column({ space: 6 }) {
        Text(`Page ${item.index + 1}`)
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor('#0F172A')
          .width('100%')
          .textAlign(TextAlign.Start)

        Text(`${item.strokeIds.length} stroke(s)`)
          .fontSize(12)
          .fontColor('#334155')
          .width('100%')
          .textAlign(TextAlign.Start)

        Text(`Updated ${this.formatDate(item.updatedAt)}`)
          .fontSize(12)
          .fontColor('#64748B')
          .width('100%')
          .textAlign(TextAlign.Start)
      }
      .layoutWeight(1)

      Column({ space: 8 }) {
        Button('Delete')
          .backgroundColor('#FEE2E2')
          .fontColor('#B91C1C')
          .borderRadius(12)
          .onClick(() => {
            void this.deletePage(item.id);
          })
      }
    }
    .width('100%')
    .padding(14)
    .backgroundColor(this.selectedPageId === item.id ? '#DBEAFE' : '#FFFFFF')
    .borderRadius(18)
    .border({
      width: this.selectedPageId === item.id ? 2 : 1,
      color: this.selectedPageId === item.id ? '#1D4ED8' : '#D7E0EA'
    })
    .onClick(() => {
      void this.selectPage(item.id);
    })
  }

  @Builder
  private buildPagePreviewPanel(): void {
    Column({ space: 18 }) {
      Text('Editor')
        .fontSize(20)
        .fontWeight(FontWeight.Medium)
        .fontColor('#0F172A')
        .width('100%')
        .textAlign(TextAlign.Start)

      if (this.getSelectedPage()) {
        CanvasEditor({
          notebookId: this.notebookId,
          pageId: this.getSelectedPage()!.id,
          pageIndex: this.getSelectedPage()!.index,
          pageUpdatedAt: this.getSelectedPage()!.updatedAt
        })
        .width('100%')
        .layoutWeight(1)
      } else {
        Column({ space: 10 }) {
          Text('No page selected')
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .fontColor('#0F172A')

          Text('Select a page on the left to open its handwriting canvas.')
            .fontSize(14)
            .fontColor('#64748B')
            .lineHeight(22)
            .textAlign(TextAlign.Center)
        }
        .justifyContent(FlexAlign.Center)
        .layoutWeight(1)
        .width('100%')
      }
    }
    .layoutWeight(1)
    .height('100%')
    .padding(18)
    .backgroundColor('#FFFFFF')
    .borderRadius(22)
  }

  private getSelectedPage(): NotePage | undefined {
    return this.pages.find((item: NotePage) => item.id === this.selectedPageId);
  }

  private async loadData(): Promise<void> {
    this.isLoading = true;
    this.errorMessage = '';
    try {
      this.notebook = await this.getNotebookRepository().getById(this.notebookId) ?? null;
      this.pages = await this.getPageRepository().listByNotebook(this.notebookId);
      this.selectedPageId = this.pages.length > 0 ? this.pages[0].id : '';
    } catch (error) {
      this.errorMessage = `Failed to load notebook detail: ${this.stringifyError(error)}`;
    } finally {
      this.isLoading = false;
    }
  }

  private async createPage(): Promise<void> {
    this.errorMessage = '';
    try {
      const page = await this.getPageRepository().create(this.notebookId, this.pages.length);
      const nextPageIds = [...this.pages.map((item: NotePage) => item.id), page.id];
      this.notebook = await this.getNotebookRepository().syncPageIds(this.notebookId, nextPageIds) ?? null;
      await this.loadData();
      this.selectedPageId = page.id;
    } catch (error) {
      this.errorMessage = `Failed to create page: ${this.stringifyError(error)}`;
    }
  }

  private async selectPage(pageId: string): Promise<void> {
    this.selectedPageId = pageId;
    try {
      this.pages = await this.getPageRepository().listByNotebook(this.notebookId);
    } catch (_error) {
      // Keep the previous list if the light refresh fails.
    }
  }

  private async deletePage(pageId: string): Promise<void> {
    this.errorMessage = '';
    try {
      await this.getStrokeRepository().deleteByPage(pageId);
      await this.getPageRepository().delete(this.notebookId, pageId);
      const nextPageIds = this.pages
        .filter((item: NotePage) => item.id !== pageId)
        .sort((left: NotePage, right: NotePage) => left.index - right.index)
        .map((item: NotePage) => item.id);
      this.notebook = await this.getNotebookRepository().syncPageIds(this.notebookId, nextPageIds) ?? null;
      await this.loadData();
    } catch (error) {
      this.errorMessage = `Failed to delete page: ${this.stringifyError(error)}`;
    }
  }

  private getNotebookRepository(): NotebookRepository {
    if (!this.notebookRepository) {
      this.notebookRepository = new NotebookRepository(this.getHostContext());
    }
    return this.notebookRepository;
  }

  private getPageRepository(): NotePageRepository {
    if (!this.pageRepository) {
      this.pageRepository = new NotePageRepository(this.getHostContext());
    }
    return this.pageRepository;
  }

  private getStrokeRepository(): StrokeRepository {
    if (!this.strokeRepository) {
      this.strokeRepository = new StrokeRepository(this.getHostContext());
    }
    return this.strokeRepository;
  }

  private getHostContext(): common.Context | undefined {
    const hostContext = this.getUIContext().getHostContext();
    return hostContext as common.Context | undefined;
  }

  private readNotebookId(): string {
    const params = this.getUIContext().getRouter().getParams() as NotebookRouteParams;
    if (!params || typeof params.notebookId !== 'string' || params.notebookId.length === 0) {
      throw new Error('Notebook route parameter is missing.');
    }
    return params.notebookId;
  }

  private formatDate(timestamp: number): string {
    const date = new Date(timestamp);
    const year = date.getFullYear();
    const month = `${date.getMonth() + 1}`.padStart(2, '0');
    const day = `${date.getDate()}`.padStart(2, '0');
    const hour = `${date.getHours()}`.padStart(2, '0');
    const minute = `${date.getMinutes()}`.padStart(2, '0');
    return `${year}-${month}-${day} ${hour}:${minute}`;
  }

  private stringifyError(error: Object): string {
    return formatError(error);
  }

  private handleRefreshSignalChange(): void {
    if (this.pageThumbnailRefreshSignal.length === 0) {
      return;
    }
    void this.refreshPageMetadata();
  }

  private async refreshPageMetadata(): Promise<void> {
    if (this.notebookId.length === 0 || this.isLoading) {
      return;
    }

    try {
      const nextPages = await this.getPageRepository().listByNotebook(this.notebookId);
      if (!this.isSamePageSnapshot(this.pages, nextPages)) {
        this.pages = nextPages;
        if (this.selectedPageId.length === 0 && nextPages.length > 0) {
          this.selectedPageId = nextPages[0].id;
        }
      }
    } catch (_error) {
      // Ignore background refresh failures and keep the current UI state.
    }
  }

  private isSamePageSnapshot(left: NotePage[], right: NotePage[]): boolean {
    if (left.length !== right.length) {
      return false;
    }

    for (let index = 0; index < left.length; index += 1) {
      if (
        left[index].id !== right[index].id ||
        left[index].index !== right[index].index ||
        left[index].updatedAt !== right[index].updatedAt ||
        left[index].strokeIds.length !== right[index].strokeIds.length
      ) {
        return false;
      }
    }

    return true;
  }
}
