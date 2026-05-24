export interface NotebookFolder {
  id: string;
  title: string;
  color: string;
  createdAt: number;
  updatedAt: number;
}

export class NotebookFolderEntity {
  static readonly DEFAULT_TITLE: string = 'Untitled Folder';
  static readonly DEFAULT_COLOR: string = '#7C9BFF';
  static readonly COLOR_PALETTE: string[] = [
    '#7C9BFF',
    '#64C1FF',
    '#6EDFB4',
    '#F8C36B',
    '#F79AA2',
    '#C7A2FF',
    '#9FD3C7',
    '#FFB37A'
  ];

  static normalizeTitle(title: string): string {
    const normalizedTitle: string = title.trim();
    if (normalizedTitle.length > 0) {
      return normalizedTitle;
    }

    return NotebookFolderEntity.DEFAULT_TITLE;
  }

  static normalizeColor(color: string): string {
    if (typeof color !== 'string') {
      return NotebookFolderEntity.DEFAULT_COLOR;
    }

    const normalizedColor: string = color.trim().toUpperCase();
    if (/^#[0-9A-F]{6}$/.test(normalizedColor)) {
      return normalizedColor;
    }

    return NotebookFolderEntity.DEFAULT_COLOR;
  }

  static pickColorBySeed(seed: string): string {
    const source: string = typeof seed === 'string' && seed.length > 0 ? seed : 'folder';
    let hash: number = 0;
    for (let index: number = 0; index < source.length; index += 1) {
      hash = ((hash << 5) - hash) + source.charCodeAt(index);
      hash |= 0;
    }
    const palette: string[] = NotebookFolderEntity.COLOR_PALETTE;
    const resolvedIndex: number = Math.abs(hash) % palette.length;
    return palette[resolvedIndex];
  }
}
