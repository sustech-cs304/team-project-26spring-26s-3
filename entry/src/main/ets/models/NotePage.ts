export type PageTemplate = 'blank' | 'ruled' | 'grid' | 'dot';

export interface NotePage {
  id: string;
  notebookId: string;
  index: number;
  createdAt: number;
  updatedAt: number;
  strokeIds: string[];
  template: PageTemplate;
}
