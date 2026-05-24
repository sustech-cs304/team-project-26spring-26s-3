export interface NotebookPageCanvas {
  pageId: string;
  notebookId: string;
  width: number;
  height: number;
  backgroundColor: string;
  backgroundImageUri?: string;
  createdAt: number;
  updatedAt: number;
}

export class NotebookPageCanvasEntity {
  static readonly DEFAULT_WIDTH: number = 2200;
  static readonly DEFAULT_HEIGHT: number = 1600;
  static readonly DEFAULT_BACKGROUND_COLOR: string = '#FFFFFF';

  static normalizeDimension(value: number, fallbackValue: number): number {
    if (Number.isInteger(value) && value > 0) {
      return value;
    }
    return fallbackValue;
  }

  static normalizeBackgroundColor(backgroundColor?: string): string {
    if (typeof backgroundColor === 'string' && backgroundColor.length > 0) {
      return backgroundColor;
    }
    return NotebookPageCanvasEntity.DEFAULT_BACKGROUND_COLOR;
  }

  static normalizeBackgroundImageUri(backgroundImageUri?: string): string {
    if (typeof backgroundImageUri === 'string') {
      return backgroundImageUri.trim();
    }
    return '';
  }
}
