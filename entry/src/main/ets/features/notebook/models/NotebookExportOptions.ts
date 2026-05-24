export type NotebookExportFormat = 'pdf' | 'png' | 'jpg' | 'webp';

export interface NotebookExportFormatOption {
  format: NotebookExportFormat;
  label: string;
  caption: string;
}

export const NOTEBOOK_EXPORT_FORMAT_OPTIONS: NotebookExportFormatOption[] = [
  { format: 'pdf', label: 'PDF', caption: '整本笔记' },
  { format: 'png', label: 'PNG', caption: '逐页图片' },
  { format: 'jpg', label: 'JPG', caption: '逐页图片' },
  { format: 'webp', label: 'WEBP', caption: '压缩图片' }
];

const NOTEBOOK_EXPORT_EXTENSIONS: string[] = ['.pdf', '.png', '.jpg', '.jpeg', '.webp'];

export function normalizeNotebookExportFormat(format: string): NotebookExportFormat {
  if (format === 'png' || format === 'jpg' || format === 'webp') {
    return format;
  }
  return 'pdf';
}

export function stripNotebookExportExtension(fileName: string): string {
  const trimmedName: string = fileName.trim();
  const lowerName: string = trimmedName.toLowerCase();
  for (const extension of NOTEBOOK_EXPORT_EXTENSIONS) {
    if (lowerName.endsWith(extension)) {
      return trimmedName.substring(0, trimmedName.length - extension.length).trim();
    }
  }
  return trimmedName;
}

export function createNotebookExportBaseName(title: string): string {
  const fallbackName: string = 'Untitled Notebook';
  const normalizedTitle: string = title.replace(/[\\/:*?"<>|]/g, '_').trim();
  if (normalizedTitle.length === 0) {
    return fallbackName;
  }
  return normalizedTitle.length > 80 ? normalizedTitle.substring(0, 80) : normalizedTitle;
}

export function buildNotebookExportFileName(fileName: string, format: string): string {
  const normalizedFormat: NotebookExportFormat = normalizeNotebookExportFormat(format);
  const cleanName: string = stripNotebookExportExtension(fileName);
  const baseName: string = cleanName.length > 0 ? cleanName : createNotebookExportBaseName('');
  return `${baseName}.${normalizedFormat}`;
}

export function buildNotebookExportSuffixChoice(format: string): string {
  const normalizedFormat: NotebookExportFormat = normalizeNotebookExportFormat(format);
  switch (normalizedFormat) {
    case 'png':
      return 'PNG Image|.png';
    case 'jpg':
      return 'JPEG Image|.jpg';
    case 'webp':
      return 'WEBP Image|.webp';
    case 'pdf':
    default:
      return 'PDF Document|.pdf';
  }
}
