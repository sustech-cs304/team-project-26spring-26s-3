import common from '@ohos.app.ability.common';
import { Notebook } from '../models/Notebook';
import { NotebookRepository } from '../services/NotebookRepository';
import { formatError } from '../utils/ErrorUtils';

@Entry
@Component
struct Index {
  @State private notebooks: Notebook[] = [];
  @State private newNotebookTitle: string = '';
  @State private editingNotebookId: string = '';
  @State private editingTitle: string = '';
  @State private isLoading: boolean = true;
  @State private errorMessage: string = '';

  private repository?: NotebookRepository;

  async aboutToAppear(): Promise<void> {
    if (!this.repository) {
      this.repository = new NotebookRepository(this.getHostContext());
    }
    await this.loadNotebooks();
  }

  build() {
    Column({ space: 16 }) {
      this.buildHeader()
      this.buildCreatePanel()
      this.buildContent()
    }
    .width('100%')
    .height('100%')
    .padding({ left: 24, right: 24, top: 24, bottom: 24 })
    .backgroundColor('#F8FAFC')
  }

  @Builder
  private buildHeader(): void {
    Column({ space: 8 }) {
      Text('Canvas Notebook')
        .fontSize(30)
        .fontWeight(FontWeight.Bold)
        .fontColor('#111827')
        .width('100%')
        .textAlign(TextAlign.Start)

      Text('Notebook management MVP')
        .fontSize(16)
        .fontColor('#475569')
        .width('100%')
        .textAlign(TextAlign.Start)

      Text('This page already reads and writes notebook data through Preferences.')
        .fontSize(13)
        .fontColor('#64748B')
        .width('100%')
        .textAlign(TextAlign.Start)
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }

  @Builder
  private buildCreatePanel(): void {
    Column({ space: 12 }) {
      Text('Create Notebook')
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor('#0F172A')
        .width('100%')
        .textAlign(TextAlign.Start)

      Row({ space: 12 }) {
        TextInput({ placeholder: 'Enter notebook title', text: this.newNotebookTitle })
          .layoutWeight(1)
          .height(52)
          .fontSize(15)
          .backgroundColor('#FFFFFF')
          .borderRadius(14)
          .onChange((value: string) => {
            this.newNotebookTitle = value;
          })

        Button('Add')
          .height(52)
          .padding({ left: 20, right: 20 })
          .backgroundColor('#1D4ED8')
          .fontColor('#FFFFFF')
          .borderRadius(14)
          .onClick(() => {
            void this.createNotebook();
          })
      }
      .width('100%')

      if (this.errorMessage.length > 0) {
        Text(this.errorMessage)
          .fontSize(13)
          .fontColor('#B91C1C')
          .width('100%')
          .textAlign(TextAlign.Start)
      }
    }
    .width('100%')
    .padding(18)
    .backgroundColor('#E0F2FE')
    .borderRadius(20)
  }

  @Builder
  private buildContent(): void {
    if (this.isLoading) {
      Column({ space: 12 }) {
        LoadingProgress()
          .width(32)
          .height(32)
          .color('#1D4ED8')

        Text('Loading notebooks...')
          .fontSize(14)
          .fontColor('#64748B')
      }
      .justifyContent(FlexAlign.Center)
      .width('100%')
      .layoutWeight(1)
    } else if (this.notebooks.length === 0) {
      Column({ space: 12 }) {
        Text('No notebooks yet')
          .fontSize(22)
          .fontWeight(FontWeight.Medium)
          .fontColor('#0F172A')

        Text('Create the first notebook above. Page and canvas features will be connected in the next step.')
          .fontSize(14)
          .fontColor('#64748B')
          .textAlign(TextAlign.Center)
          .lineHeight(22)
      }
      .justifyContent(FlexAlign.Center)
      .width('100%')
      .layoutWeight(1)
      .padding(24)
      .backgroundColor('#FFFFFF')
      .borderRadius(20)
    } else {
      List({ space: 12 }) {
        ForEach(this.notebooks, (item: Notebook) => {
          ListItem() {
            this.buildNotebookCard(item)
          }
        }, (item: Notebook) => item.id)
      }
      .layoutWeight(1)
      .width('100%')
      .divider({ strokeWidth: 0 })
      .scrollBar(BarState.Off)
    }
  }

  @Builder
  private buildNotebookCard(item: Notebook): void {
    Column({ space: 14 }) {
      if (this.editingNotebookId === item.id) {
        TextInput({ placeholder: 'Notebook title', text: this.editingTitle })
          .width('100%')
          .height(48)
          .fontSize(16)
          .backgroundColor('#F8FAFC')
          .borderRadius(12)
          .onChange((value: string) => {
            this.editingTitle = value;
          })
      } else {
        Text(item.title)
          .fontSize(21)
          .fontWeight(FontWeight.Medium)
          .fontColor('#0F172A')
          .width('100%')
          .textAlign(TextAlign.Start)
      }

      Row({ space: 10 }) {
        this.buildMetaChip(`${item.pageIds.length} pages`, '#E2E8F0', '#334155')
        this.buildMetaChip(`Updated ${this.formatDate(item.updatedAt)}`, '#DBEAFE', '#1E3A8A')
      }
      .width('100%')

      if (this.editingNotebookId === item.id) {
        Row({ space: 10 }) {
          Button('Save')
            .padding({ left: 18, right: 18 })
            .backgroundColor('#0F766E')
            .fontColor('#FFFFFF')
            .borderRadius(12)
            .onClick(() => {
              void this.saveRename(item.id);
            })

          Button('Cancel')
            .padding({ left: 18, right: 18 })
            .backgroundColor('#E2E8F0')
            .fontColor('#334155')
            .borderRadius(12)
            .onClick(() => {
              this.cancelRename();
            })
        }
      } else {
        Row({ space: 10 }) {
          Button('Open')
            .padding({ left: 18, right: 18 })
            .backgroundColor('#1D4ED8')
            .fontColor('#FFFFFF')
            .borderRadius(12)
            .onClick(() => {
              void this.openNotebook(item.id);
            })

          Button('Rename')
            .padding({ left: 18, right: 18 })
            .backgroundColor('#E2E8F0')
            .fontColor('#334155')
            .borderRadius(12)
            .onClick(() => {
              this.startRename(item);
            })

          Button('Delete')
            .padding({ left: 18, right: 18 })
            .backgroundColor('#FEE2E2')
            .fontColor('#B91C1C')
            .borderRadius(12)
            .onClick(() => {
              void this.deleteNotebook(item.id);
            })
        }
      }
    }
    .width('100%')
    .padding(18)
    .backgroundColor('#FFFFFF')
    .borderRadius(20)
  }

  @Builder
  private buildMetaChip(label: string, backgroundColor: string, fontColor: string): void {
    Text(label)
      .fontSize(12)
      .fontColor(fontColor)
      .padding({ left: 10, right: 10, top: 6, bottom: 6 })
      .backgroundColor(backgroundColor)
      .borderRadius(999)
  }

  private async loadNotebooks(): Promise<void> {
    this.isLoading = true;
    this.errorMessage = '';
    try {
      this.notebooks = await this.getRepository().list();
    } catch (error) {
      this.errorMessage = `Failed to load notebooks: ${this.stringifyError(error)}`;
    } finally {
      this.isLoading = false;
    }
  }

  private async createNotebook(): Promise<void> {
    this.errorMessage = '';
    try {
      await this.getRepository().create(this.newNotebookTitle);
      this.newNotebookTitle = '';
      await this.loadNotebooks();
    } catch (error) {
      this.errorMessage = `Failed to create notebook: ${this.stringifyError(error)}`;
    }
  }

  private startRename(item: Notebook): void {
    this.editingNotebookId = item.id;
    this.editingTitle = item.title;
  }

  private cancelRename(): void {
    this.editingNotebookId = '';
    this.editingTitle = '';
  }

  private async saveRename(id: string): Promise<void> {
    this.errorMessage = '';
    try {
      await this.getRepository().rename(id, this.editingTitle);
      this.cancelRename();
      await this.loadNotebooks();
    } catch (error) {
      this.errorMessage = `Failed to rename notebook: ${this.stringifyError(error)}`;
    }
  }

  private async deleteNotebook(id: string): Promise<void> {
    this.errorMessage = '';
    try {
      await this.getRepository().delete(id);
      if (this.editingNotebookId === id) {
        this.cancelRename();
      }
      await this.loadNotebooks();
    } catch (error) {
      this.errorMessage = `Failed to delete notebook: ${this.stringifyError(error)}`;
    }
  }

  private async openNotebook(id: string): Promise<void> {
    this.errorMessage = '';
    try {
      await this.getUIContext().getRouter().pushUrl({
        url: 'pages/NotebookDetail',
        params: {
          notebookId: id
        }
      });
    } catch (error) {
      this.errorMessage = `Failed to open notebook: ${this.stringifyError(error)}`;
    }
  }

  private getRepository(): NotebookRepository {
    if (!this.repository) {
      this.repository = new NotebookRepository(this.getHostContext());
    }
    return this.repository;
  }

  private getHostContext(): common.Context | undefined {
    const hostContext = this.getUIContext().getHostContext();
    return hostContext as common.Context | undefined;
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
}
