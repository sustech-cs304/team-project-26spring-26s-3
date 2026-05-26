import common from '@ohos.app.ability.common';
import fs from '@ohos.file.fs';
import image from '@ohos.multimedia.image';
import { pdfService } from '@kit.PDFKit';

import { IdUtil } from '../../../common/utils/IdUtil';
import { EditorRepositoryImpl } from '../../../data/repositories/EditorRepositoryImpl';
import { NotebookRepositoryImpl } from '../../../data/repositories/NotebookRepositoryImpl';
import {
  CanvasElement,
  DEFAULT_STROKE_LAYER_Z_INDEX,
  PageCanvasContent
} from '../../../domain/entities/CanvasElement';
import { Notebook } from '../../../domain/entities/Notebook';
import { NotebookPage, NotebookPageTemplateType } from '../../../domain/entities/NotebookPage';
import { NotebookPageCanvas, NotebookPageCanvasEntity } from '../../../domain/entities/NotebookPageCanvas';
import { CanvasDrawContext } from '../../editor/controllers/CanvasDrawContext';
import { CanvasElementRenderer } from '../../editor/controllers/CanvasElementRenderer';
import { PageTemplateRenderer } from '../../editor/controllers/PageTemplateRenderer';
import { StrokeRenderer } from '../../editor/controllers/StrokeRenderer';
import {
  buildNotebookExportFileName,
  NotebookExportFormat,
  normalizeNotebookExportFormat
} from '../models/NotebookExportOptions';

export interface NotebookExportRequest {
  notebookId: string;
  fileName: string;
  format: string;
  outputUris: string[];
  pageIds?: string[];
}

interface CanvasPixelMapExporter {
  getPixelMap(sx: number, sy: number, sw: number, sh: number): image.PixelMap;
}

interface PreparedExportPage {
  page: NotebookPage;
  canvas: NotebookPageCanvas;
  content: PageCanvasContent;
}

interface RenderedExportPage {
  pageNumber: number;
  width: number;
  height: number;
  tempImagePath: string;
}

export interface NotebookExportResult {
  success: boolean;
  outputUris: string[];
  message: string;
}

export class NotebookExportService {
  private static readonly EXPORT_DIR: string = 'hosn/exports';
  private static readonly EXPORT_IMAGE_MAX_EDGE: number = 2400;

  constructor(
    private readonly context: common.Context,
    private readonly notebookRepository: NotebookRepositoryImpl = new NotebookRepositoryImpl(context),
    private readonly editorRepository: EditorRepositoryImpl = new EditorRepositoryImpl(context)
  ) {
  }

  async exportNotebook(request: NotebookExportRequest): Promise<NotebookExportResult> {
    const format: NotebookExportFormat = normalizeNotebookExportFormat(request.format);
    const outputUris: string[] = this.normalizeOutputUris(request.outputUris);
    if (request.notebookId.length === 0 || outputUris.length === 0) {
      return {
        success: false,
        outputUris: [],
        message: '请选择导出位置。'
      };
    }

    const notebook: Notebook | null = await this.notebookRepository.getNotebookById(request.notebookId);
    if (notebook === null) {
      return {
        success: false,
        outputUris: [],
        message: '笔记本不存在，无法导出。'
      };
    }

    const preparedPages: PreparedExportPage[] = await this.preparePages(request.notebookId, request.pageIds);
    if (preparedPages.length === 0) {
      return {
        success: false,
        outputUris: [],
        message: '没有可导出的页面。'
      };
    }

    const exportId: string = IdUtil.createId('notebook_export');
    const tempDirectory: string = `${this.context.filesDir}/${NotebookExportService.EXPORT_DIR}/${exportId}`;
    this.ensureDirectory(tempDirectory);

    try {
      if (format === 'pdf') {
        const outputUri: string = outputUris[0];
        const renderedPages: RenderedExportPage[] = await this.renderPagesToTempImages(preparedPages, tempDirectory, 'png');
        const tempPdfPath: string = `${tempDirectory}/${this.buildSafeFileName(request.fileName, format)}`;
        await this.writePdf(renderedPages, tempPdfPath);
        await this.copyFileToOutput(tempPdfPath, outputUri);
        return {
          success: true,
          outputUris: [outputUri],
          message: `已导出 ${preparedPages.length} 页 PDF。`
        };
      }

      const renderedPages: RenderedExportPage[] = await this.renderPagesToTempImages(preparedPages, tempDirectory, format);
      const targetUris: string[] = this.normalizeImageOutputUris(outputUris, renderedPages.length);
      if (targetUris.length < renderedPages.length) {
        return {
          success: false,
          outputUris: targetUris,
          message: '图片导出需要为每一页选择保存位置。'
        };
      }

      for (let index: number = 0; index < renderedPages.length; index += 1) {
        await this.copyFileToOutput(renderedPages[index].tempImagePath, targetUris[index]);
      }
      return {
        success: true,
        outputUris: targetUris,
        message: `已导出 ${renderedPages.length} 张图片。`
      };
    } catch (error) {
      return {
        success: false,
        outputUris: outputUris,
        message: `导出失败：${this.stringifyError(error)}`
      };
    }
  }

  buildExportFileNames(fileName: string, format: string, pageCount: number): string[] {
    const normalizedFormat: NotebookExportFormat = normalizeNotebookExportFormat(format);
    if (normalizedFormat === 'pdf') {
      return [buildNotebookExportFileName(fileName, normalizedFormat)];
    }

    const safePageCount: number = Math.max(1, pageCount);
    if (safePageCount === 1) {
      return [buildNotebookExportFileName(fileName, normalizedFormat)];
    }

    const baseName: string = this.sanitizeFileNamePart(
      this.stripExtension(buildNotebookExportFileName(fileName, normalizedFormat))
    );
    const result: string[] = [];
    for (let index: number = 0; index < safePageCount; index += 1) {
      result.push(`${baseName}-${this.formatPageNumber(index + 1)}.${normalizedFormat}`);
    }
    return result;
  }

  async getNotebookPageCount(notebookId: string, pageIds?: string[]): Promise<number> {
    if (notebookId.length === 0) {
      return 1;
    }
    const pages: NotebookPage[] = await this.notebookRepository.getNotebookPages(notebookId);
    return Math.max(1, this.filterPagesByIds(pages, pageIds).length);
  }

  private async preparePages(notebookId: string, pageIds?: string[]): Promise<PreparedExportPage[]> {
    const pages: NotebookPage[] = await this.notebookRepository.getNotebookPages(notebookId);
    const exportPages: NotebookPage[] = this.filterPagesByIds(pages, pageIds);
    const result: PreparedExportPage[] = [];
    for (const page of exportPages) {
      const canvas: NotebookPageCanvas | null = await this.notebookRepository.getNotebookPageCanvas({
        notebookId: notebookId,
        pageId: page.id
      });
      const content: PageCanvasContent = await this.editorRepository.getPageContent(page.id);
      result.push({
        page,
        canvas: canvas ?? this.buildFallbackCanvas(page),
        content: this.normalizeContent(content)
      });
    }
    return result;
  }

  private filterPagesByIds(pages: NotebookPage[], pageIds?: string[]): NotebookPage[] {
    if (pageIds === undefined || pageIds.length === 0) {
      return pages;
    }

    const requestedIds: Set<string> = new Set<string>();
    for (const pageId of pageIds) {
      const normalizedPageId: string = typeof pageId === 'string' ? pageId.trim() : '';
      if (normalizedPageId.length > 0) {
        requestedIds.add(normalizedPageId);
      }
    }
    if (requestedIds.size === 0) {
      return pages;
    }
    return pages.filter((page: NotebookPage): boolean => requestedIds.has(page.id));
  }

  private async renderPagesToTempImages(
    pages: PreparedExportPage[],
    tempDirectory: string,
    format: NotebookExportFormat
  ): Promise<RenderedExportPage[]> {
    const renderedPages: RenderedExportPage[] = [];
    for (let index: number = 0; index < pages.length; index += 1) {
      const page = pages[index];
      const renderSize = this.resolveRenderSize(page.canvas.width, page.canvas.height);
      const tempImagePath: string = `${tempDirectory}/page-${this.formatPageNumber(index + 1)}.${format}`;
      const pixelMap: image.PixelMap = this.renderPageToPixelMap(page, renderSize.width, renderSize.height);
      try {
        await this.writePixelMap(pixelMap, tempImagePath, format);
      } finally {
        try {
          await pixelMap.release();
        } catch (_releaseError) {
        }
      }

      renderedPages.push({
        pageNumber: index + 1,
        width: renderSize.width,
        height: renderSize.height,
        tempImagePath
      });
    }
    return renderedPages;
  }

  private renderPageToPixelMap(page: PreparedExportPage, width: number, height: number): image.PixelMap {
    const offscreenCanvas = new OffscreenCanvas(width, height);
    const context = offscreenCanvas.getContext('2d') as Object as CanvasDrawContext;
    context.clearRect(0, 0, width, height);

    const scale: number = Math.min(width / page.canvas.width, height / page.canvas.height);
    const scaledWidth: number = page.canvas.width * scale;
    const scaledHeight: number = page.canvas.height * scale;
    const offsetX: number = (width - scaledWidth) / 2;
    const offsetY: number = (height - scaledHeight) / 2;

    context.fillStyle = page.canvas.backgroundColor;
    context.globalAlpha = 1;
    context.fillRect(0, 0, width, height);

    context.save();
    context.translate(offsetX, offsetY);
    context.scale(scale, scale);
    const didDrawBackgroundImage: boolean = this.drawBackgroundImage(
      context,
      page.canvas.backgroundImageUri ?? '',
      page.canvas.width,
      page.canvas.height
    );
    PageTemplateRenderer.drawTemplateBackground(
      context,
      this.normalizeTemplateType(page.page.templateType),
      page.canvas.width,
      page.canvas.height,
      page.canvas.backgroundColor,
      undefined,
      !didDrawBackgroundImage
    );
    this.drawContent(context, page.content);
    context.restore();

    const pixelSource = context as Object as CanvasPixelMapExporter;
    return pixelSource.getPixelMap(0, 0, width, height);
  }

  private drawContent(context: CanvasDrawContext, content: PageCanvasContent): void {
    const strokeLayerZIndex: number = this.normalizeStrokeLayerZIndex(content.strokeLayerZIndex);
    CanvasElementRenderer.drawElements(
      context,
      content.elements.filter((element: CanvasElement): boolean => element.zIndex < strokeLayerZIndex)
    );
    for (const stroke of content.strokes) {
      StrokeRenderer.drawStroke(context, stroke);
    }
    CanvasElementRenderer.drawElements(
      context,
      content.elements.filter((element: CanvasElement): boolean => element.zIndex >= strokeLayerZIndex)
    );
  }

  private drawBackgroundImage(
    context: CanvasDrawContext,
    backgroundImageUri: string,
    width: number,
    height: number
  ): boolean {
    const candidates: string[] = this.buildImageSourceCandidates(backgroundImageUri);
    for (const candidate of candidates) {
      let imageBitmap: ImageBitmap | undefined = undefined;
      try {
        imageBitmap = new ImageBitmap(candidate);
        context.drawImage(imageBitmap, 0, 0, width, height);
        return true;
      } catch (_error) {
      } finally {
        if (imageBitmap !== undefined) {
          try {
            imageBitmap.close();
          } catch (_closeError) {
          }
        }
      }
    }
    return false;
  }

  private async writePixelMap(pixelMap: image.PixelMap, targetPath: string, format: NotebookExportFormat): Promise<void> {
    let targetFile: fs.File | undefined = undefined;
    const packer: image.ImagePacker = image.createImagePacker();
    try {
      targetFile = fs.openSync(targetPath, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      const packingOption: image.PackingOption = {
        format: this.getImageMimeType(format),
        quality: this.getImageQuality(format)
      };
      await packer.packToFile(pixelMap, targetFile.fd, packingOption);
    } finally {
      if (targetFile !== undefined) {
        try {
          fs.closeSync(targetFile);
        } catch (_closeError) {
        }
      }
      try {
        await packer.release();
      } catch (_releaseError) {
      }
    }
  }

  private async writePdf(renderedPages: RenderedExportPage[], targetPath: string): Promise<void> {
    if (renderedPages.length === 0) {
      throw new Error('没有可写入 PDF 的页面。');
    }

    let pdfDocument: pdfService.PdfDocument | undefined = undefined;
    try {
      pdfDocument = new pdfService.PdfDocument();
      const firstPage: RenderedExportPage = renderedPages[0];
      if (!pdfDocument.createDocument(firstPage.width, firstPage.height)) {
        throw new Error('PDF 文档创建失败。');
      }

      for (let index: number = 0; index < renderedPages.length; index += 1) {
        const renderedPage: RenderedExportPage = renderedPages[index];
        const pdfPage: pdfService.PdfPage = index === 0
          ? pdfDocument.getPage(0)
          : pdfDocument.insertBlankPage(index, renderedPage.width, renderedPage.height);
        try {
          pdfPage.addImageObject(renderedPage.tempImagePath, 0, 0, renderedPage.width, renderedPage.height);
        } finally {
          try {
            pdfPage.release();
          } catch (_releasePageError) {
          }
        }
      }

      if (!pdfDocument.saveDocument(targetPath)) {
        throw new Error('PDF 文件写入失败。');
      }
    } finally {
      if (pdfDocument !== undefined) {
        try {
          pdfDocument.releaseDocument();
        } catch (_releaseDocumentError) {
        }
      }
    }
  }

  private async copyFileToOutput(sourcePath: string, outputUri: string): Promise<void> {
    const candidates: string[] = this.buildOutputPathCandidates(outputUri);
    for (const candidate of candidates) {
      try {
        await fs.copyFile(sourcePath, candidate);
        return;
      } catch (_copyError) {
      }

      let targetFile: fs.File | undefined = undefined;
      try {
        targetFile = fs.openSync(candidate, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
        await fs.copyFile(sourcePath, targetFile.fd);
        return;
      } catch (_fdCopyError) {
      } finally {
        if (targetFile !== undefined) {
          try {
            fs.closeSync(targetFile);
          } catch (_closeError) {
          }
        }
      }
    }

    throw new Error('无法写入选择的保存位置。');
  }

  private resolveRenderSize(canvasWidth: number, canvasHeight: number): { width: number; height: number } {
    const sourceWidth: number = Math.max(1, Math.round(canvasWidth));
    const sourceHeight: number = Math.max(1, Math.round(canvasHeight));
    const maxEdge: number = Math.max(sourceWidth, sourceHeight);
    if (maxEdge <= NotebookExportService.EXPORT_IMAGE_MAX_EDGE) {
      return {
        width: sourceWidth,
        height: sourceHeight
      };
    }

    const scale: number = NotebookExportService.EXPORT_IMAGE_MAX_EDGE / maxEdge;
    return {
      width: Math.max(1, Math.round(sourceWidth * scale)),
      height: Math.max(1, Math.round(sourceHeight * scale))
    };
  }

  private normalizeImageOutputUris(outputUris: string[], pageCount: number): string[] {
    if (pageCount <= 1) {
      return outputUris.length > 0 ? [outputUris[0]] : [];
    }
    return outputUris.slice(0, pageCount);
  }

  private normalizeOutputUris(outputUris: string[]): string[] {
    const result: string[] = [];
    for (const outputUri of outputUris) {
      const normalizedUri: string = typeof outputUri === 'string' ? outputUri.trim() : '';
      if (normalizedUri.length > 0 && !result.includes(normalizedUri)) {
        result.push(normalizedUri);
      }
    }
    return result;
  }

  private normalizeContent(content: PageCanvasContent): PageCanvasContent {
    return {
      version: content.version,
      strokes: Array.isArray(content.strokes) ? content.strokes : [],
      elements: Array.isArray(content.elements) ? content.elements : [],
      strokeLayerZIndex: this.normalizeStrokeLayerZIndex(content.strokeLayerZIndex)
    };
  }

  private buildFallbackCanvas(page: NotebookPage): NotebookPageCanvas {
    return {
      pageId: page.id,
      notebookId: page.notebookId,
      width: NotebookPageCanvasEntity.DEFAULT_WIDTH,
      height: NotebookPageCanvasEntity.DEFAULT_HEIGHT,
      backgroundColor: NotebookPageCanvasEntity.DEFAULT_BACKGROUND_COLOR,
      backgroundImageUri: '',
      createdAt: page.createdAt,
      updatedAt: page.updatedAt
    };
  }

  private buildImageSourceCandidates(uri: string): string[] {
    const normalizedUri: string = this.resolveImageUri(uri);
    const candidates: string[] = [];
    this.appendPathCandidate(candidates, normalizedUri);
    const decodedUri: string = this.decodeUriSegment(normalizedUri);
    if (decodedUri !== normalizedUri) {
      this.appendPathCandidate(candidates, decodedUri);
    }

    if (normalizedUri.startsWith('file://')) {
      const rawLocalPath: string = normalizedUri.substring('file://'.length);
      this.appendPathCandidate(candidates, rawLocalPath);
      if (!rawLocalPath.startsWith('/')) {
        this.appendPathCandidate(candidates, `/${rawLocalPath}`);
      }
      const decodedLocalPath: string = this.decodeUriSegment(rawLocalPath);
      if (decodedLocalPath !== rawLocalPath) {
        this.appendPathCandidate(candidates, decodedLocalPath);
        if (!decodedLocalPath.startsWith('/')) {
          this.appendPathCandidate(candidates, `/${decodedLocalPath}`);
        }
      }
    }

    if (decodedUri.startsWith('file://')) {
      const decodedSchemePath: string = decodedUri.substring('file://'.length);
      this.appendPathCandidate(candidates, decodedSchemePath);
      if (!decodedSchemePath.startsWith('/')) {
        this.appendPathCandidate(candidates, `/${decodedSchemePath}`);
      }
    }

    return candidates;
  }

  private buildOutputPathCandidates(uri: string): string[] {
    const candidates: string[] = [];
    this.appendPathCandidate(candidates, uri);
    const decodedUri: string = this.decodeUriSegment(uri);
    if (decodedUri !== uri) {
      this.appendPathCandidate(candidates, decodedUri);
    }
    if (uri.startsWith('file://')) {
      const rawLocalPath: string = uri.substring('file://'.length);
      this.appendPathCandidate(candidates, rawLocalPath);
      if (!rawLocalPath.startsWith('/')) {
        this.appendPathCandidate(candidates, `/${rawLocalPath}`);
      }
      const decodedLocalPath: string = this.decodeUriSegment(rawLocalPath);
      if (decodedLocalPath !== rawLocalPath) {
        this.appendPathCandidate(candidates, decodedLocalPath);
        if (!decodedLocalPath.startsWith('/')) {
          this.appendPathCandidate(candidates, `/${decodedLocalPath}`);
        }
      }
    }
    if (!uri.startsWith('file://') && !uri.startsWith('datashare://')) {
      this.appendPathCandidate(candidates, `file://${uri}`);
    }
    return candidates;
  }

  private resolveImageUri(uri: string): string {
    const normalizedUri: string = typeof uri === 'string' ? uri.trim() : '';
    if (normalizedUri.length === 0) {
      return '';
    }
    if (normalizedUri.startsWith('file://') || normalizedUri.startsWith('http://') ||
      normalizedUri.startsWith('https://')) {
      return normalizedUri;
    }
    return `file://${normalizedUri}`;
  }

  private appendPathCandidate(candidates: string[], candidate: string): void {
    if (candidate.length === 0 || candidates.includes(candidate)) {
      return;
    }
    candidates.push(candidate);
  }

  private getImageMimeType(format: NotebookExportFormat): string {
    switch (format) {
      case 'jpg':
        return 'image/jpeg';
      case 'webp':
        return 'image/webp';
      case 'png':
      case 'pdf':
      default:
        return 'image/png';
    }
  }

  private getImageQuality(format: NotebookExportFormat): number {
    if (format === 'jpg') {
      return 96;
    }
    if (format === 'webp') {
      return 90;
    }
    return 100;
  }

  private buildSafeFileName(fileName: string, format: NotebookExportFormat): string {
    return this.sanitizeFileNamePart(buildNotebookExportFileName(fileName, format));
  }

  private sanitizeFileNamePart(fileName: string): string {
    const sanitized: string = fileName.replace(/[\\/:*?"<>|]/g, '_').trim();
    return sanitized.length > 0 ? sanitized : 'Untitled Notebook';
  }

  private stripExtension(fileName: string): string {
    const dotIndex: number = fileName.lastIndexOf('.');
    if (dotIndex <= 0) {
      return fileName;
    }
    return fileName.substring(0, dotIndex);
  }

  private formatPageNumber(pageNumber: number): string {
    if (pageNumber < 10) {
      return `000${pageNumber}`;
    }
    if (pageNumber < 100) {
      return `00${pageNumber}`;
    }
    if (pageNumber < 1000) {
      return `0${pageNumber}`;
    }
    return `${pageNumber}`;
  }

  private normalizeTemplateType(templateType: NotebookPageTemplateType): NotebookPageTemplateType {
    switch (templateType) {
      case NotebookPageTemplateType.LINED:
      case NotebookPageTemplateType.GRID:
      case NotebookPageTemplateType.DOTTED:
      case NotebookPageTemplateType.BLANK:
        return templateType;
      default:
        return NotebookPageTemplateType.BLANK;
    }
  }

  private normalizeStrokeLayerZIndex(strokeLayerZIndex: number): number {
    return Number.isFinite(strokeLayerZIndex) ? strokeLayerZIndex : DEFAULT_STROKE_LAYER_Z_INDEX;
  }

  private ensureDirectory(directoryPath: string): void {
    try {
      fs.mkdirSync(directoryPath, true);
    } catch (_error) {
    }
  }

  private decodeUriSegment(text: string): string {
    try {
      return decodeURIComponent(text);
    } catch (_error) {
      return text;
    }
  }

  private stringifyError(error: Object): string {
    if (error instanceof Error) {
      return error.message.length > 0 ? error.message : error.name;
    }
    if (typeof error === 'string') {
      return error;
    }
    try {
      return JSON.stringify(error);
    } catch (_stringifyError) {
      return '未知错误';
    }
  }
}
