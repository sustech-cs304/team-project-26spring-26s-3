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
  lastEditedPageId?: string;
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
  static readonly TITLE_COVER_IMAGE_URI: string = 'hosn://cover/title';
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

  static createUniqueTitle(title: string, existingTitles: string[]): string {
    const baseTitle: string = NotebookEntity.normalizeTitle(title);
    const existingTitleKeyList: string[] = [];
    for (const existingTitle of existingTitles) {
      const existingTitleKey: string = NotebookEntity.normalizeTitleKey(existingTitle);
      if (!existingTitleKeyList.includes(existingTitleKey)) {
        existingTitleKeyList.push(existingTitleKey);
      }
    }

    if (!existingTitleKeyList.includes(NotebookEntity.normalizeTitleKey(baseTitle))) {
      return baseTitle;
    }

    const suffixLimit: number = existingTitleKeyList.length + 2;
    for (let suffix: number = 2; suffix <= suffixLimit; suffix += 1) {
      const candidateTitle: string = `${baseTitle} (${suffix})`;
      if (!existingTitleKeyList.includes(NotebookEntity.normalizeTitleKey(candidateTitle))) {
        return candidateTitle;
      }
    }

    return `${baseTitle} (${suffixLimit + 1})`;
  }

  static normalizeTitleKey(title: string): string {
    return NotebookEntity.normalizeTitle(title).replace(/\s+/g, ' ').toLowerCase();
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

  static isTitleCoverImageUri(uri?: string): boolean {
    return NotebookEntity.normalizeCoverImageUri(uri) === NotebookEntity.TITLE_COVER_IMAGE_URI;
  }

  static normalizeLastEditedPageId(pageId?: string): string {
    if (typeof pageId !== 'string') {
      return '';
    }
    return pageId.trim();
  }

  static normalizePageCount(pageCount?: number): number {
    if (typeof pageCount !== 'number' || !Number.isFinite(pageCount) || pageCount <= 0) {
      return 1;
    }
    return Math.floor(pageCount);
  }
}
