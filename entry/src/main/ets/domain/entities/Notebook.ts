export interface Notebook {
  id: string;
  title: string;
  folderId: string;
  createdAt: number;
  updatedAt: number;
  coverColor?: string;
  coverImageUri?: string;
  pageCount?: number;
  isFavorite?: boolean;
  tags?: string[];
  isDeleted?: boolean;
  deletedAt?: number;
  lastOpenedAt?: number;
}

export interface NotebookSummary {
  id: string;
  title: string;
  folderId: string;
  updatedAt: number;
}

export class NotebookEntity {
  static readonly DEFAULT_TITLE: string = 'Untitled Notebook';
  static readonly DEFAULT_COVER_COLOR: string = '#7C9BFF';
  static readonly COVER_COLOR_PALETTE: string[] = [
    '#7C9BFF',
    '#64C1FF',
    '#6EDFB4',
    '#F8C36B',
    '#F79AA2',
    '#C7A2FF',
    '#9FD3C7',
    '#FFB37A',
    '#7DD3FC',
    '#86EFAC',
    '#FDBA74',
    '#FCA5A5'
  ];

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

  static normalizeCoverColor(color?: string): string {
    if (typeof color !== 'string') {
      return NotebookEntity.DEFAULT_COVER_COLOR;
    }
    const normalizedColor: string = color.trim().toUpperCase();
    if (/^#[0-9A-F]{6}$/.test(normalizedColor)) {
      return normalizedColor;
    }
    return NotebookEntity.DEFAULT_COVER_COLOR;
  }

  static normalizeCoverImageUri(uri?: string): string {
    if (typeof uri !== 'string') {
      return '';
    }
    return uri.trim();
  }

  static normalizePageCount(pageCount?: number): number {
    if (typeof pageCount !== 'number' || !Number.isFinite(pageCount) || pageCount <= 0) {
      return 1;
    }
    return Math.floor(pageCount);
  }
}
