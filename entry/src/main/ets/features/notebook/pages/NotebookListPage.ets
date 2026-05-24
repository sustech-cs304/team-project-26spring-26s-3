import { NotebookListPanel } from '../components/NotebookListPanel';

@Entry
@Component
struct NotebookListPage {
  build() {
    Column() {
      NotebookListPanel()
    }
    .width('100%')
    .height('100%')
  }
}
