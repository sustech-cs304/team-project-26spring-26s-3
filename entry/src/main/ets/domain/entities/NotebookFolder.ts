export interface NotebookFolder {
  id: string;
  title: string;
  createdAt: number;
  updatedAt: number;
}

export class NotebookFolderEntity {
  static readonly DEFAULT_TITLE: string = 'Untitled Folder';

  static normalizeTitle(title: string): string {
    const normalizedTitle: string = title.trim();
    if (normalizedTitle.length > 0) {
      return normalizedTitle;
    }

    return NotebookFolderEntity.DEFAULT_TITLE;
  }
}
