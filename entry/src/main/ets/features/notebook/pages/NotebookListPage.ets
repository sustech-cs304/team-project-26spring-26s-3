import { NotebookListPanel } from '../components/NotebookListPanel';

@Entry
@Component
struct NotebookListPage {
  @State private useLargeNotebookCards: boolean = true;

  build() {
    Column() {
      NotebookListPanel({
        useLargeNotebookCards: $useLargeNotebookCards
      })
    }
    .width('100%')
    .height('100%')
  }
}
