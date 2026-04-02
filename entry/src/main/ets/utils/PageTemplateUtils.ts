import { PageTemplate } from '../models/NotePage';

export const DEFAULT_PAGE_TEMPLATE: PageTemplate = 'ruled';
export const PAGE_TEMPLATE_OPTIONS: PageTemplate[] = ['blank', 'ruled', 'grid', 'dot'];

export function normalizePageTemplate(value: string | undefined | null): PageTemplate {
  return value === 'blank' || value === 'ruled' || value === 'grid' || value === 'dot'
    ? value
    : DEFAULT_PAGE_TEMPLATE;
}

export function getPageTemplateLabel(template: PageTemplate): string {
  switch (template) {
    case 'blank':
      return 'Blank';
    case 'grid':
      return 'Grid';
    case 'dot':
      return 'Dots';
    case 'ruled':
    default:
      return 'Lines';
  }
}
