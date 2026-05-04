export enum NotebookPageTemplateType {
  BLANK = 'blank',
  LINED = 'lined',
  GRID = 'grid',
  DOTTED = 'dotted'
}

export interface NotebookPage {
  id: string;
  notebookId: string;
  order: number;
  createdAt: number;
  updatedAt: number;
  templateType: NotebookPageTemplateType;
}

export class NotebookPageEntity {
  static readonly DEFAULT_TEMPLATE_TYPE: NotebookPageTemplateType = NotebookPageTemplateType.BLANK;

  static normalizeOrder(order: number, fallbackOrder: number): number {
    if (Number.isInteger(order) && order >= 0) {
      return order;
    }
    return fallbackOrder;
  }

  static normalizeTemplateType(templateType?: string): NotebookPageTemplateType {
    if (templateType === NotebookPageTemplateType.BLANK) {
      return NotebookPageTemplateType.BLANK;
    }
    if (templateType === NotebookPageTemplateType.LINED) {
      return NotebookPageTemplateType.LINED;
    }
    if (templateType === NotebookPageTemplateType.GRID) {
      return NotebookPageTemplateType.GRID;
    }
    if (templateType === NotebookPageTemplateType.DOTTED) {
      return NotebookPageTemplateType.DOTTED;
    }
    return NotebookPageEntity.DEFAULT_TEMPLATE_TYPE;
  }
}
