export interface Notebook {
  id: string;
  title: string;
  folderId: string;
  createdAt: number;
  updatedAt: number;
}

export interface NotebookSummary {
  id: string;
  title: string;
  folderId: string;
  updatedAt: number;
}

export class NotebookEntity {
  static readonly DEFAULT_TITLE: string = 'Untitled Notebook';

  static normalizeTitle(title: string): string {
    const normalizedTitle: string = title.trim();
    if (normalizedTitle.length > 0) {
      return normalizedTitle;
    }
    return NotebookEntity.DEFAULT_TITLE;
  }

  static normalizeFolderId(folderId?: string): string {
    if (typeof folderId === 'string') {
      return folderId.trim();
    }

    return '';
  }
}
