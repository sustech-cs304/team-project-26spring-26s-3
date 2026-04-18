export enum NotebookPageTemplateType {
  BLANK = 'blank'
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
    return NotebookPageEntity.DEFAULT_TEMPLATE_TYPE;
  }
}
