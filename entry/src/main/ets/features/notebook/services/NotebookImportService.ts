import common from '@ohos.app.ability.common';
import picker from '@ohos.file.picker';
import fs from '@ohos.file.fs';
import zlib from '@ohos.zlib';
import image from '@ohos.multimedia.image';
import { pdfService } from '@kit.PDFKit';

import { IdUtil } from '../../../common/utils/IdUtil';
import { TimeUtil } from '../../../common/utils/TimeUtil';
import { StorageKeys } from '../../../common/constants/StorageKeys';
import { Notebook, NotebookEntity } from '../../../domain/entities/Notebook';
import { NotebookPage, NotebookPageEntity } from '../../../domain/entities/NotebookPage';
import { NotebookPageCanvas, NotebookPageCanvasEntity } from '../../../domain/entities/NotebookPageCanvas';
import { CanvasElement, PageCanvasContent, TRANSPARENT_ELEMENT_BACKGROUND_COLOR } from '../../../domain/entities/CanvasElement';
import { FileDataSource } from '../../../data/sources/local/FileDataSource';
import { ImageAssetDataSource, ImportedImageAsset } from '../../../data/sources/local/ImageAssetDataSource';
import { PreferencesDataSource } from '../../../data/sources/local/PreferencesDataSource';
import { EditorRepositoryImpl } from '../../../data/repositories/EditorRepositoryImpl';

interface RawMap {
  [key: string]: unknown;
}

interface ImportFileProfile {
  uri: string;
  fileName: string;
  extension: string;
  lowerExtension: string;
  baseName: string;
  mimeType: string;
}

interface ImportResult {
  notebookId: string;
  notebookTitle: string;
  openedPageId: string;
}

interface ImportBackgroundPageSpec {
  width: number;
  height: number;
  imageUri?: string;
}

interface ImportOfficeTextSpec {
  content: string;
  x: number;
  y: number;
  width: number;
  height: number;
  fontSize: number;
}

interface ImportOfficePageSpec {
  width: number;
  height: number;
  textList: ImportOfficeTextSpec[];
}

export class NotebookImportService {
  private static readonly NOTEBOOK_LIST_PATH: string = 'notebooks/notebook-list.json';
  private static readonly PAGE_DIR: string = 'notebooks/pages';
  private static readonly CANVAS_DIR: string = 'notebooks/canvases';
  private static readonly IMPORT_DIR: string = 'notebooks/imports';
  private static readonly IMPORT_PAGE_IMAGE_DIR: string = 'hosn/editor_assets/import_page_images';
  private static readonly DEFAULT_DOCUMENT_PAGE_WIDTH: number = 1240;
  private static readonly DEFAULT_DOCUMENT_PAGE_HEIGHT: number = 1754;
  private static readonly PDF_RENDER_SCALE: number = 2;
  private static readonly PDF_RENDER_MAX_EDGE: number = 2400;
  private static readonly XML_TEXT_TRIM_LIMIT: number = 220000;
  private static readonly DOCX_TEXT_CHUNK_LIMIT: number = 3400;
  private lastFailureMessage: string = '';

  constructor(
    private readonly context: common.Context,
    private readonly fileDataSource: FileDataSource = new FileDataSource(context),
    private readonly preferencesDataSource: PreferencesDataSource = new PreferencesDataSource(context),
    private readonly editorRepository: EditorRepositoryImpl = new EditorRepositoryImpl(context)
  ) {
  }

  async importFromPicker(): Promise<ImportResult | null> {
    this.lastFailureMessage = '';
    const selectedUri: string = await this.pickFile();
    if (selectedUri.length === 0) {
      return null;
    }

    return await this.importFromUri(selectedUri);
  }

  async importFromUri(sourceUri: string): Promise<ImportResult | null> {
    this.lastFailureMessage = '';
    const profile: ImportFileProfile = this.buildImportFileProfile(sourceUri);
    if (profile.fileName.length === 0) {
      return null;
    }

    if (this.isImageFile(profile)) {
      return await this.importAsVisualNotebook(profile, sourceUri);
    }

    if (this.isPdfFile(profile)) {
      return await this.importPdfAsBackgroundNotebook(profile, sourceUri);
    }

    if (this.isOfficeLikeFile(profile)) {
      return await this.importAsEditableNotebook(profile, sourceUri);
    }

    const textContent: string = await this.readBestEffortText(sourceUri);
    if (textContent.length > 0) {
      return await this.importAsTextNotebook(profile, textContent, sourceUri);
    }

    return await this.importAsAttachmentNotebook(profile, sourceUri);
  }

  getLastFailureMessage(): string {
    return this.lastFailureMessage;
  }

  private async pickFile(): Promise<string> {
    try {
      const options = new picker.DocumentSelectOptions();
      options.maxSelectNumber = 1;
      options.defaultFilePathUri = '';
      options.fileSuffixFilters = [
        'Image|jpg,jpeg,png,webp,bmp,gif',
        'Office|doc,docx,ppt,pptx',
        'Text|txt,md,rtf,csv,log',
        'PDF|pdf',
        'All|*'
      ];
      const pickerInstance = new picker.DocumentViewPicker(this.context);
      const result = await pickerInstance.select(options);
      if (result.length === 0) {
        return '';
      }
      return result[0];
    } catch (_error) {
      return '';
    }
  }

  private async importAsVisualNotebook(profile: ImportFileProfile, sourceUri: string): Promise<ImportResult | null> {
    const importedAsset: ImportedImageAsset = await this.importImageAsset(sourceUri);
    const notebook: Notebook = await this.ensureNotebookCreated(profile.baseName, importedAsset.uri);
    const pageId: string = await this.ensureNotebookBackgroundPage(notebook.id, importedAsset, sourceUri, profile.lowerExtension);
    await this.persistImportSource(notebook.id, profile, importedAsset.uri);
    return {
      notebookId: notebook.id,
      notebookTitle: notebook.title,
      openedPageId: pageId
    };
  }

  private async importPdfAsBackgroundNotebook(profile: ImportFileProfile, sourceUri: string): Promise<ImportResult | null> {
    const pageSpecs: ImportBackgroundPageSpec[] = await this.buildPdfBackgroundPageSpecs(profile, sourceUri);
    if (pageSpecs.length > 0) {
      return await this.importAsBackgroundNotebook(profile, pageSpecs, sourceUri);
    }
    this.lastFailureMessage = 'PDF 导入失败：无法把文件渲染成页面图片。请确认 PDF 未加密，或重新导出为标准 PDF 后再试。';
    return null;
  }

  private async importAsEditableNotebook(profile: ImportFileProfile, sourceUri: string): Promise<ImportResult | null> {
    if (profile.lowerExtension === '.doc' || profile.lowerExtension === '.ppt' || profile.lowerExtension === '.pptx') {
      return await this.importAsAttachmentNotebook(profile, sourceUri);
    }

    const officePageSpecs: ImportOfficePageSpec[] = await this.buildOfficePageSpecs(profile, sourceUri);
    if (officePageSpecs.length > 0) {
      return await this.importAsOfficeNotebook(profile, officePageSpecs, sourceUri);
    }

    const extractedText: string = await this.extractOfficeText(profile, sourceUri);
    if (extractedText.length > 0) {
      return await this.importAsTextNotebook(profile, extractedText, sourceUri);
    }

    this.lastFailureMessage = `Office 导入失败：${profile.fileName} 可能已加密、损坏，或不是有效的 docx 文件。若需要完全保留版式，请先导出为 PDF 再导入。`;
    return null;
  }

  private async importAsOfficeNotebook(
    profile: ImportFileProfile,
    pageSpecs: ImportOfficePageSpec[],
    sourceUri: string
  ): Promise<ImportResult | null> {
    const notebook: Notebook = await this.ensureNotebookCreated(profile.baseName, '');
    const openedPageId: string = await this.writeNotebookOfficePages(notebook.id, pageSpecs, profile, sourceUri);
    await this.updateNotebookPageCount(notebook.id, pageSpecs.length);
    await this.persistImportSource(notebook.id, profile, sourceUri);
    return {
      notebookId: notebook.id,
      notebookTitle: notebook.title,
      openedPageId: openedPageId
    };
  }

  private async importAsBackgroundNotebook(
    profile: ImportFileProfile,
    pageSpecs: ImportBackgroundPageSpec[],
    sourceUri: string
  ): Promise<ImportResult | null> {
    const notebook: Notebook = await this.ensureNotebookCreated(profile.baseName, '');
    const openedPageId: string = await this.writeNotebookBackgroundPages(notebook.id, pageSpecs, profile, sourceUri);
    await this.updateNotebookPageCount(notebook.id, pageSpecs.length);
    await this.persistImportSource(notebook.id, profile, sourceUri);
    return {
      notebookId: notebook.id,
      notebookTitle: notebook.title,
      openedPageId: openedPageId
    };
  }

  private async importAsTextNotebook(profile: ImportFileProfile, textContent: string, sourceUri: string): Promise<ImportResult | null> {
    const notebook: Notebook = await this.ensureNotebookCreated(profile.baseName, '');
    const pageId: string = await this.writeNotebookTextPage(notebook.id, textContent, profile, sourceUri);
    await this.persistImportSource(notebook.id, profile, sourceUri);
    return {
      notebookId: notebook.id,
      notebookTitle: notebook.title,
      openedPageId: pageId
    };
  }

  private async importAsAttachmentNotebook(profile: ImportFileProfile, sourceUri: string): Promise<ImportResult | null> {
    const notebook: Notebook = await this.ensureNotebookCreated(profile.baseName, '');
    const pageId: string = await this.writeNotebookAttachmentPage(notebook.id, profile, sourceUri);
    await this.persistImportSource(notebook.id, profile, sourceUri);
    return {
      notebookId: notebook.id,
      notebookTitle: notebook.title,
      openedPageId: pageId
    };
  }

  private async ensureNotebookCreated(title: string, coverImageUri: string): Promise<Notebook> {
    const notebookList: Notebook[] = await this.readNotebookList();
    const currentTime: number = TimeUtil.now();
    const notebookTitle: string = NotebookEntity.createUniqueTitle(title, this.collectNotebookTitleList(notebookList));
    const usedCoverColorList: string[] = [];
    for (const existingNotebook of notebookList) {
      const normalizedColor: string = NotebookEntity.normalizeCoverColor(existingNotebook.coverColor);
      if (!usedCoverColorList.includes(normalizedColor)) {
        usedCoverColorList.push(normalizedColor);
      }
    }

    let coverColor: string = NotebookEntity.DEFAULT_COVER_COLOR;
    for (const color of NotebookEntity.COVER_COLOR_PALETTE) {
      if (!usedCoverColorList.includes(color)) {
        coverColor = color;
        break;
      }
    }

    const notebook: Notebook = {
      id: IdUtil.createNotebookId(),
      title: notebookTitle,
      folderId: '',
      createdAt: currentTime,
      updatedAt: currentTime,
      coverColor: coverColor,
      coverImageUri: NotebookEntity.normalizeCoverImageUri(this.normalizeLocalUri(coverImageUri)),
      pageCount: 1,
      isFavorite: false,
      tags: [],
      isDeleted: false,
      deletedAt: 0,
      lastOpenedAt: 0
    };

    notebookList.push(notebook);
    await this.writeNotebookList(notebookList);
    return notebook;
  }

  private async ensureNotebookBackgroundPage(
    notebookId: string,
    importedAsset: ImportedImageAsset,
    sourceUri: string,
    sourceType: string
  ): Promise<string> {
    const currentTime: number = TimeUtil.now();
    const notebookPage: NotebookPage = {
      id: IdUtil.createNotebookPageId(),
      notebookId: notebookId,
      order: 0,
      createdAt: currentTime,
      updatedAt: currentTime,
      templateType: NotebookPageEntity.DEFAULT_TEMPLATE_TYPE,
      sourceFileUri: sourceUri,
      sourceFileType: sourceType
    };

    await this.writePageList(notebookId, [notebookPage]);
    await this.writeCanvas({
      pageId: notebookPage.id,
      notebookId: notebookId,
      width: importedAsset.originalWidth,
      height: importedAsset.originalHeight,
      backgroundColor: NotebookPageCanvasEntity.DEFAULT_BACKGROUND_COLOR,
      backgroundImageUri: importedAsset.uri,
      createdAt: currentTime,
      updatedAt: currentTime
    });
    await this.writePageContent(notebookPage.id, {
      version: 2,
      strokes: [],
      elements: []
    });
    return notebookPage.id;
  }

  private async writeNotebookTextPage(
    notebookId: string,
    textContent: string,
    profile: ImportFileProfile,
    sourceUri: string
  ): Promise<string> {
    const currentTime: number = TimeUtil.now();
    const pageId: string = IdUtil.createNotebookPageId();
    const notebookPage: NotebookPage = {
      id: pageId,
      notebookId: notebookId,
      order: 0,
      createdAt: currentTime,
      updatedAt: currentTime,
      templateType: NotebookPageEntity.DEFAULT_TEMPLATE_TYPE,
      sourceFileUri: sourceUri,
      sourceFileType: profile.lowerExtension
    };

    await this.writePageList(notebookId, [notebookPage]);
    await this.writeCanvas({
      pageId: pageId,
      notebookId: notebookId,
      width: NotebookPageCanvasEntity.DEFAULT_WIDTH,
      height: NotebookPageCanvasEntity.DEFAULT_HEIGHT,
      backgroundColor: NotebookPageCanvasEntity.DEFAULT_BACKGROUND_COLOR,
      backgroundImageUri: '',
      createdAt: currentTime,
      updatedAt: currentTime
    });

    const element: CanvasElement = this.buildImportTextElement(
      pageId,
      textContent.trim().length > 0 ? textContent.trim() : profile.fileName,
      currentTime
    );

    await this.writePageContent(pageId, {
      version: 2,
      strokes: [],
      elements: [element]
    });
    return pageId;
  }

  private async writeNotebookBackgroundPages(
    notebookId: string,
    pageSpecs: ImportBackgroundPageSpec[],
    profile: ImportFileProfile,
    sourceUri: string
  ): Promise<string> {
    const createdPageList: NotebookPage[] = [];
    const firstPageId: string = IdUtil.createNotebookPageId();
    let openedPageId: string = firstPageId;

    for (let index: number = 0; index < pageSpecs.length; index += 1) {
      const currentTime: number = TimeUtil.now();
      const pageId: string = index === 0 ? firstPageId : IdUtil.createNotebookPageId();
      createdPageList.push({
        id: pageId,
        notebookId: notebookId,
        order: index,
        createdAt: currentTime,
        updatedAt: currentTime,
        templateType: NotebookPageEntity.DEFAULT_TEMPLATE_TYPE,
        sourceFileUri: sourceUri,
        sourceFileType: profile.lowerExtension
      });
      if (index === 0) {
        openedPageId = pageId;
      }
    }

    await this.writePageList(notebookId, createdPageList);

    for (let index: number = 0; index < createdPageList.length; index += 1) {
      const page: NotebookPage = createdPageList[index];
      const pageSpec: ImportBackgroundPageSpec = pageSpecs[index];
      const backgroundPath: string = this.resolvePageBackgroundImagePath(pageSpec);
      if (backgroundPath.length === 0) {
        continue;
      }
      await this.writeCanvas({
        pageId: page.id,
        notebookId: notebookId,
        width: this.normalizeImportDimension(pageSpec.width, NotebookImportService.DEFAULT_DOCUMENT_PAGE_WIDTH),
        height: this.normalizeImportDimension(pageSpec.height, NotebookImportService.DEFAULT_DOCUMENT_PAGE_HEIGHT),
        backgroundColor: NotebookPageCanvasEntity.DEFAULT_BACKGROUND_COLOR,
        backgroundImageUri: backgroundPath,
        createdAt: page.createdAt,
        updatedAt: page.updatedAt
      });
      await this.writePageContent(page.id, {
        version: 2,
        strokes: [],
        elements: []
      });
    }

    return openedPageId;
  }

  private async writeNotebookOfficePages(
    notebookId: string,
    pageSpecs: ImportOfficePageSpec[],
    profile: ImportFileProfile,
    sourceUri: string
  ): Promise<string> {
    const createdPageList: NotebookPage[] = [];
    const firstPageId: string = IdUtil.createNotebookPageId();
    let openedPageId: string = firstPageId;

    for (let index: number = 0; index < pageSpecs.length; index += 1) {
      const currentTime: number = TimeUtil.now();
      const pageId: string = index === 0 ? firstPageId : IdUtil.createNotebookPageId();
      createdPageList.push({
        id: pageId,
        notebookId: notebookId,
        order: index,
        createdAt: currentTime,
        updatedAt: currentTime,
        templateType: NotebookPageEntity.DEFAULT_TEMPLATE_TYPE,
        sourceFileUri: sourceUri,
        sourceFileType: profile.lowerExtension
      });
      if (index === 0) {
        openedPageId = pageId;
      }
    }

    await this.writePageList(notebookId, createdPageList);

    for (let index: number = 0; index < createdPageList.length; index += 1) {
      const page: NotebookPage = createdPageList[index];
      const pageSpec: ImportOfficePageSpec = pageSpecs[index];
      await this.writeCanvas({
        pageId: page.id,
        notebookId: notebookId,
        width: this.normalizeImportDimension(pageSpec.width, NotebookPageCanvasEntity.DEFAULT_WIDTH),
        height: this.normalizeImportDimension(pageSpec.height, NotebookPageCanvasEntity.DEFAULT_HEIGHT),
        backgroundColor: NotebookPageCanvasEntity.DEFAULT_BACKGROUND_COLOR,
        backgroundImageUri: '',
        createdAt: page.createdAt,
        updatedAt: page.updatedAt
      });
      await this.writePageContent(page.id, {
        version: 2,
        strokes: [],
        elements: this.buildOfficeTextElements(page.id, pageSpec, page.createdAt)
      });
    }

    return openedPageId;
  }

  private async writeNotebookAttachmentPage(notebookId: string, profile: ImportFileProfile, sourceUri: string): Promise<string> {
    const currentTime: number = TimeUtil.now();
    const pageId: string = IdUtil.createNotebookPageId();
    const notebookPage: NotebookPage = {
      id: pageId,
      notebookId: notebookId,
      order: 0,
      createdAt: currentTime,
      updatedAt: currentTime,
      templateType: NotebookPageEntity.DEFAULT_TEMPLATE_TYPE,
      sourceFileUri: sourceUri,
      sourceFileType: profile.lowerExtension
    };

    await this.writePageList(notebookId, [notebookPage]);
    await this.writeCanvas({
      pageId: pageId,
      notebookId: notebookId,
      width: NotebookPageCanvasEntity.DEFAULT_WIDTH,
      height: NotebookPageCanvasEntity.DEFAULT_HEIGHT,
      backgroundColor: NotebookPageCanvasEntity.DEFAULT_BACKGROUND_COLOR,
      backgroundImageUri: '',
      createdAt: currentTime,
      updatedAt: currentTime
    });

    await this.writePageContent(pageId, {
      version: 2,
      strokes: [],
      elements: [
        {
          id: IdUtil.createId('import_file'),
          pageId: pageId,
          type: 'text',
          x: 96,
          y: 96,
          width: Math.max(280, NotebookPageCanvasEntity.DEFAULT_WIDTH - 192),
          height: 160,
          rotation: 0,
          zIndex: 1,
          createdAt: currentTime,
          updatedAt: currentTime,
          content: `Imported file: ${profile.fileName}`,
          color: '#111827',
          fontSize: 18,
          backgroundColor: TRANSPARENT_ELEMENT_BACKGROUND_COLOR
        }
      ]
    });
    return pageId;
  }

  private async buildPdfBackgroundPageSpecs(
    profile: ImportFileProfile,
    sourceUri: string
  ): Promise<ImportBackgroundPageSpec[]> {
    return await this.renderPdfToPageImages(profile, sourceUri);
  }

  private async renderPdfToPageImages(
    profile: ImportFileProfile,
    sourceUri: string
  ): Promise<ImportBackgroundPageSpec[]> {
    const sourcePath: string = await this.copyImportSourceToSandbox(profile, sourceUri);
    if (sourcePath.length === 0) {
      return [];
    }

    let pdfDocument: pdfService.PdfDocument | undefined = undefined;
    try {
      pdfDocument = new pdfService.PdfDocument();
      const loadResult: pdfService.ParseResult = pdfDocument.loadDocument(sourcePath);
      if (loadResult !== pdfService.ParseResult.PARSE_SUCCESS) {
        return [];
      }

      const pageCount: number = Math.max(0, pdfDocument.getPageCount());
      if (pageCount === 0) {
        return [];
      }

      const pageImageDir: string = `${this.context.filesDir}/${NotebookImportService.IMPORT_PAGE_IMAGE_DIR}/${IdUtil.createId('pdf')}`;
      try {
        fs.mkdirSync(pageImageDir, true);
      } catch (_mkdirError) {
      }

      const result: ImportBackgroundPageSpec[] = [];
      for (let index: number = 0; index < pageCount; index += 1) {
        const pageImagePath: string = `${pageImageDir}/page-${this.formatPageNumber(index + 1)}.png`;
        const pageSpec: ImportBackgroundPageSpec | null = await this.renderPdfPageToPng(pdfDocument, index, pageImagePath);
        if (pageSpec !== null) {
          result.push(pageSpec);
        }
      }
      return result;
    } catch (_error) {
      return [];
    } finally {
      if (pdfDocument !== undefined && typeof pdfDocument.releaseDocument === 'function') {
        try {
          pdfDocument.releaseDocument();
        } catch (_releaseError) {
        }
      }
    }
  }

  private async renderPdfPageToPng(
    pdfDocument: pdfService.PdfDocument,
    pageIndex: number,
    pageImagePath: string
  ): Promise<ImportBackgroundPageSpec | null> {
    let pixelMap: image.PixelMap | undefined = undefined;
    try {
      const page: pdfService.PdfPage = pdfDocument.getPage(pageIndex);
      pixelMap = this.createPdfPagePixelMap(page);
      const imageInfo: image.ImageInfo = await pixelMap.getImageInfo();
      await this.writePixelMapAsPng(pixelMap, pageImagePath);
      return {
        width: Math.max(1, imageInfo.size.width),
        height: Math.max(1, imageInfo.size.height),
        imageUri: pageImagePath
      };
    } catch (_error) {
      return null;
    } finally {
      if (pixelMap !== undefined) {
        try {
          await pixelMap.release();
        } catch (_releaseError) {
        }
      }
    }
  }

  private createPdfPagePixelMap(page: pdfService.PdfPage): image.PixelMap {
    try {
      return page.getPagePixelMap();
    } catch (_pageRenderError) {
    }

    try {
      const pageWidth: number = Math.max(1, page.getWidth());
      const pageHeight: number = Math.max(1, page.getHeight());
      const bitmapSize = this.resolvePdfBitmapSize(pageWidth, pageHeight);
      const matrix: pdfService.PdfMatrix = new pdfService.PdfMatrix();
      matrix.x = 0;
      matrix.y = 0;
      matrix.width = pageWidth;
      matrix.height = pageHeight;
      matrix.rotate = 0;

      const options: pdfService.PixelOptions = new pdfService.PixelOptions();
      options.isGray = false;
      options.drawAnnotations = true;
      options.isTransparent = false;
      return page.getAreaPixelMapWithOptions(matrix, bitmapSize.width, bitmapSize.height, options);
    } catch (_areaRenderError) {
      return page.getPagePixelMap();
    }
  }

  private resolvePdfBitmapSize(pageWidth: number, pageHeight: number): { width: number; height: number } {
    const scaledWidth: number = Math.max(1, Math.round(pageWidth * NotebookImportService.PDF_RENDER_SCALE));
    const scaledHeight: number = Math.max(1, Math.round(pageHeight * NotebookImportService.PDF_RENDER_SCALE));
    const maxEdge: number = Math.max(scaledWidth, scaledHeight);
    if (maxEdge <= NotebookImportService.PDF_RENDER_MAX_EDGE) {
      return {
        width: scaledWidth,
        height: scaledHeight
      };
    }

    const scale: number = NotebookImportService.PDF_RENDER_MAX_EDGE / maxEdge;
    return {
      width: Math.max(1, Math.round(scaledWidth * scale)),
      height: Math.max(1, Math.round(scaledHeight * scale))
    };
  }

  private async writePixelMapAsPng(pixelMap: image.PixelMap, targetPath: string): Promise<void> {
    let targetFile: fs.File | undefined = undefined;
    const packer: image.ImagePacker = image.createImagePacker();
    try {
      targetFile = fs.openSync(targetPath, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      const packingOption: image.PackingOption = {
        format: 'image/png',
        quality: 100
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

  private async importImageAsset(sourceUri: string): Promise<ImportedImageAsset> {
    try {
      return await new ImageAssetDataSource(this.context).importImage(sourceUri);
    } catch (_error) {
      return {
        uri: sourceUri,
        originalWidth: 1,
        originalHeight: 1
      };
    }
  }

  private async copyImportSourceToSandbox(profile: ImportFileProfile, sourceUri: string): Promise<string> {
    const importDir: string = `${this.context.filesDir}/${NotebookImportService.IMPORT_DIR}/sources`;
    try {
      fs.mkdirSync(importDir, true);
    } catch (_error) {
    }

    const targetPath: string = `${importDir}/${IdUtil.createId('source')}${profile.lowerExtension}`;
    const sourceCandidates: string[] = this.buildPathCandidates(sourceUri);
    for (const candidateSource of sourceCandidates) {
      try {
        await fs.copyFile(candidateSource, targetPath);
        return targetPath;
      } catch (_copyError) {
      }

      let sourceFile: fs.File | undefined = undefined;
      try {
        sourceFile = fs.openSync(candidateSource, fs.OpenMode.READ_ONLY);
        await fs.copyFile(sourceFile.fd, targetPath);
        return targetPath;
      } catch (_fdCopyError) {
      } finally {
        if (sourceFile !== undefined) {
          try {
            fs.closeSync(sourceFile);
          } catch (_closeError) {
          }
        }
      }
    }

    return '';
  }

  private normalizeLocalUri(path: string): string {
    if (path.length === 0) {
      return '';
    }
    if (path.startsWith('file://')) {
      return path;
    }
    return `file://${path}`;
  }

  private buildImportTextElement(pageId: string, content: string, timestamp: number): CanvasElement {
    return {
      id: IdUtil.createId('import_text'),
      pageId: pageId,
      type: 'text',
      x: 96,
      y: 96,
      width: Math.max(280, NotebookPageCanvasEntity.DEFAULT_WIDTH - 192),
      height: Math.max(180, NotebookPageCanvasEntity.DEFAULT_HEIGHT - 192),
      rotation: 0,
      zIndex: 1,
      createdAt: timestamp,
      updatedAt: timestamp,
      content: content,
      color: '#111827',
      fontSize: 18,
      backgroundColor: TRANSPARENT_ELEMENT_BACKGROUND_COLOR
    };
  }

  private buildOfficeTextElements(pageId: string, pageSpec: ImportOfficePageSpec, timestamp: number): CanvasElement[] {
    const elements: CanvasElement[] = [];
    let zIndex: number = 1;
    for (const textSpec of pageSpec.textList) {
      elements.push({
        id: IdUtil.createId('office_text'),
        pageId: pageId,
        type: 'text',
        x: textSpec.x,
        y: textSpec.y,
        width: textSpec.width,
        height: textSpec.height,
        rotation: 0,
        zIndex: zIndex,
        createdAt: timestamp,
        updatedAt: timestamp,
        content: textSpec.content,
        color: '#111827',
        fontSize: textSpec.fontSize,
        backgroundColor: TRANSPARENT_ELEMENT_BACKGROUND_COLOR
      });
      zIndex += 1;
    }

    return elements;
  }

  private async buildOfficePageSpecs(profile: ImportFileProfile, sourceUri: string): Promise<ImportOfficePageSpec[]> {
    if (profile.lowerExtension !== '.docx') {
      return [];
    }

    const unpackDir: string = await this.unpackOfficeSource(profile, sourceUri);
    if (unpackDir.length === 0) {
      return [];
    }

    return await this.buildDocxPageSpecs(unpackDir);
  }

  private async unpackOfficeSource(profile: ImportFileProfile, sourceUri: string): Promise<string> {
    const sourcePath: string = await this.copyImportSourceToSandbox(profile, sourceUri);
    if (sourcePath.length === 0) {
      return '';
    }

    const unpackDir: string = `${this.context.filesDir}/${NotebookImportService.IMPORT_DIR}/${IdUtil.createId('office')}`;
    try {
      fs.mkdirSync(unpackDir, true);
    } catch (_mkdirError) {
    }

    try {
      await zlib.decompressFile(sourcePath, unpackDir);
      return unpackDir;
    } catch (_decompressError) {
    }

    try {
      await zlib.unzipFile(sourcePath, unpackDir, {});
      return unpackDir;
    } catch (_unzipError) {
      return '';
    }
  }

  private async buildDocxPageSpecs(unpackDir: string): Promise<ImportOfficePageSpec[]> {
    const textContent: string = await this.extractDocxTextFromUnpack(unpackDir);
    if (textContent.length === 0) {
      return [];
    }

    const chunks: string[] = this.splitTextIntoChunks(textContent, NotebookImportService.DOCX_TEXT_CHUNK_LIMIT);
    const pageSpecs: ImportOfficePageSpec[] = [];
    for (const chunk of chunks) {
      pageSpecs.push({
        width: NotebookImportService.DEFAULT_DOCUMENT_PAGE_WIDTH,
        height: NotebookImportService.DEFAULT_DOCUMENT_PAGE_HEIGHT,
        textList: [{
          content: chunk,
          x: 96,
          y: 96,
          width: NotebookImportService.DEFAULT_DOCUMENT_PAGE_WIDTH - 192,
          height: NotebookImportService.DEFAULT_DOCUMENT_PAGE_HEIGHT - 192,
          fontSize: 18
        }]
      });
    }
    return pageSpecs;
  }

  private async extractOfficeText(profile: ImportFileProfile, sourceUri: string): Promise<string> {
    if (profile.lowerExtension !== '.docx') {
      return '';
    }

    const unpackDir: string = await this.unpackOfficeSource(profile, sourceUri);
    if (unpackDir.length === 0) {
      return '';
    }

    return await this.extractDocxTextFromUnpack(unpackDir);
  }

  private async buildOfficeTextCandidateFiles(unpackDir: string, lowerExtension: string): Promise<string[]> {
    const candidateFiles: string[] = [];
    if (lowerExtension !== '.docx') {
      return candidateFiles;
    }

    this.appendCandidate(candidateFiles, `${unpackDir}/word/document.xml`);
    this.appendCandidate(candidateFiles, `${unpackDir}/word/footnotes.xml`);
    this.appendCandidate(candidateFiles, `${unpackDir}/word/endnotes.xml`);
    return candidateFiles;
  }

  private async extractDocxTextFromUnpack(unpackDir: string): Promise<string> {
    const candidateFiles: string[] = await this.buildOfficeTextCandidateFiles(unpackDir, '.docx');
    const texts: string[] = [];
    for (const filePath of candidateFiles) {
      const rawXml: string = await this.readTextFromPath(filePath);
      if (rawXml.length === 0) {
        continue;
      }
      const extractedText: string = this.extractVisibleTextFromXml(rawXml);
      if (extractedText.length > 0) {
        texts.push(extractedText);
      }
    }
    return this.trimImportText(texts.join('\n\n'));
  }

  private splitTextIntoChunks(text: string, chunkLimit: number): string[] {
    const result: string[] = [];
    const paragraphs: string[] = text.split('\n');
    let currentChunk: string = '';
    for (const paragraph of paragraphs) {
      const normalizedParagraph: string = paragraph.trim();
      if (normalizedParagraph.length === 0) {
        continue;
      }

      if (currentChunk.length > 0 && currentChunk.length + normalizedParagraph.length + 2 > chunkLimit) {
        result.push(currentChunk);
        currentChunk = '';
      }

      if (normalizedParagraph.length > chunkLimit) {
        if (currentChunk.length > 0) {
          result.push(currentChunk);
          currentChunk = '';
        }
        let offset: number = 0;
        while (offset < normalizedParagraph.length) {
          result.push(normalizedParagraph.substring(offset, Math.min(normalizedParagraph.length, offset + chunkLimit)));
          offset += chunkLimit;
        }
        continue;
      }

      currentChunk = currentChunk.length === 0 ? normalizedParagraph : `${currentChunk}\n\n${normalizedParagraph}`;
    }

    if (currentChunk.length > 0) {
      result.push(currentChunk);
    }
    return result;
  }

  private extractVisibleTextFromXml(rawXml: string): string {
    if (rawXml.length === 0) {
      return '';
    }

    const text: string = rawXml
      .replace(/<\/w:p>/g, '\n')
      .replace(/<\/a:p>/g, '\n')
      .replace(/<w:tab\/>/g, '\t')
      .replace(/<a:tab\/>/g, '\t')
      .replace(/<w:br\/>/g, '\n')
      .replace(/<a:br\/>/g, '\n')
      .replace(/<[^>]+>/g, ' ')
      .replace(/&lt;/g, '<')
      .replace(/&gt;/g, '>')
      .replace(/&amp;/g, '&')
      .replace(/&quot;/g, '"')
      .replace(/&apos;/g, "'")
      .replace(/&#39;/g, "'")
      .replace(/[ \t\r\f\v]+/g, ' ')
      .replace(/\n[ \t]+/g, '\n')
      .replace(/[ \t]+\n/g, '\n')
      .replace(/\n{3,}/g, '\n\n')
      .trim();

    return this.trimImportText(text);
  }

  private trimImportText(text: string): string {
    if (text.length <= NotebookImportService.XML_TEXT_TRIM_LIMIT) {
      return text;
    }
    return text.substring(0, NotebookImportService.XML_TEXT_TRIM_LIMIT);
  }

  private async readTextFromPath(path: string): Promise<string> {
    const pathCandidates: string[] = this.buildPathCandidates(path);
    for (const candidatePath of pathCandidates) {
      try {
        return fs.readTextSync(candidatePath);
      } catch (_error) {
      }
    }
    return '';
  }

  private normalizeImportDimension(value: number, fallbackValue: number): number {
    if (Number.isFinite(value) && value > 0) {
      return Math.max(320, Math.min(4096, Math.floor(value)));
    }
    return fallbackValue;
  }

  private buildPathCandidates(path: string): string[] {
    const candidates: string[] = [];
    this.appendCandidate(candidates, path);

    const decodedPath: string = this.decodeUriSegment(path);
    if (decodedPath !== path) {
      this.appendCandidate(candidates, decodedPath);
    }

    if (path.startsWith('file://')) {
      const rawLocalPath: string = path.substring('file://'.length);
      this.appendCandidate(candidates, rawLocalPath);
      if (!rawLocalPath.startsWith('/')) {
        this.appendCandidate(candidates, `/${rawLocalPath}`);
      }
      const decodedLocalPath: string = this.decodeUriSegment(rawLocalPath);
      if (decodedLocalPath !== rawLocalPath) {
        this.appendCandidate(candidates, decodedLocalPath);
        if (!decodedLocalPath.startsWith('/')) {
          this.appendCandidate(candidates, `/${decodedLocalPath}`);
        }
      }
    }

    if (decodedPath.startsWith('file://')) {
      const decodedSchemePath: string = decodedPath.substring('file://'.length);
      this.appendCandidate(candidates, decodedSchemePath);
      if (!decodedSchemePath.startsWith('/')) {
        this.appendCandidate(candidates, `/${decodedSchemePath}`);
      }
    }

    return candidates;
  }

  private appendCandidate(candidates: string[], path: string): void {
    if (path.length === 0) {
      return;
    }
    if (!candidates.includes(path)) {
      candidates.push(path);
    }
  }

  private decodeUriSegment(text: string): string {
    try {
      return decodeURIComponent(text);
    } catch (_error) {
      return text;
    }
  }

  private resolvePageBackgroundImagePath(pageSpec: ImportBackgroundPageSpec): string {
    if (typeof pageSpec.imageUri === 'string' && pageSpec.imageUri.trim().length > 0) {
      return pageSpec.imageUri.trim();
    }
    return '';
  }

  private buildImportFileProfile(uri: string): ImportFileProfile {
    const normalized = uri.split('?')[0].split('#')[0];
    const rawFileName = this.resolveFileName(normalized);
    const decodedFileName = this.decodeUriSegment(rawFileName);
    const fileName = decodedFileName.length > 0 ? decodedFileName : rawFileName;
    const extensionIndex = fileName.lastIndexOf('.');
    const extension = extensionIndex >= 0 ? fileName.substring(extensionIndex) : '';
    const baseName = extensionIndex >= 0 ? fileName.substring(0, extensionIndex) : fileName;
    return {
      uri,
      fileName,
      extension,
      lowerExtension: extension.toLowerCase(),
      baseName: NotebookEntity.normalizeTitle(baseName.length > 0 ? baseName : 'Imported Notebook'),
      mimeType: this.resolveMimeType(extension.toLowerCase())
    };
  }

  private resolveFileName(path: string): string {
    const slashIndex = Math.max(path.lastIndexOf('/'), path.lastIndexOf('\\'));
    if (slashIndex >= 0 && slashIndex < path.length - 1) {
      return path.substring(slashIndex + 1);
    }
    return path;
  }

  private resolveMimeType(extension: string): string {
    switch (extension) {
      case '.jpg':
      case '.jpeg':
        return 'image/jpeg';
      case '.png':
        return 'image/png';
      case '.webp':
        return 'image/webp';
      case '.gif':
        return 'image/gif';
      case '.bmp':
        return 'image/bmp';
      case '.pdf':
        return 'application/pdf';
      case '.doc':
        return 'application/msword';
      case '.docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case '.ppt':
        return 'application/vnd.ms-powerpoint';
      case '.pptx':
        return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
      default:
        return 'application/octet-stream';
    }
  }

  private isImageFile(profile: ImportFileProfile): boolean {
    return ['.jpg', '.jpeg', '.png', '.webp', '.gif', '.bmp'].includes(profile.lowerExtension);
  }

  private isPdfFile(profile: ImportFileProfile): boolean {
    return profile.lowerExtension === '.pdf';
  }

  private isOfficeLikeFile(profile: ImportFileProfile): boolean {
    return ['.doc', '.docx', '.ppt', '.pptx'].includes(profile.lowerExtension);
  }

  private async readBestEffortText(sourceUri: string): Promise<string> {
    const text = await this.readTextFromPath(sourceUri);
    if (text.length > 0) {
      return text;
    }
    return '';
  }

  private async persistImportSource(notebookId: string, profile: ImportFileProfile, importedUri: string): Promise<void> {
    const sourcePath = `${NotebookImportService.IMPORT_DIR}/${notebookId}.json`;
    const payload = {
      notebookId: notebookId,
      sourceUri: profile.uri,
      importedUri: importedUri,
      fileName: profile.fileName,
      extension: profile.lowerExtension,
      mimeType: profile.mimeType,
      importedAt: TimeUtil.now()
    };
    await this.fileDataSource.writeText(sourcePath, JSON.stringify(payload));
  }

  private async updateNotebookPageCount(notebookId: string, pageCount: number): Promise<void> {
    const notebookList: Notebook[] = await this.readNotebookList();
    let hasUpdated: boolean = false;
    for (let index: number = 0; index < notebookList.length; index += 1) {
      const notebook: Notebook = notebookList[index];
      if (notebook.id !== notebookId) {
        continue;
      }
      notebookList[index] = {
        id: notebook.id,
        title: notebook.title,
        folderId: notebook.folderId,
        createdAt: notebook.createdAt,
        updatedAt: TimeUtil.now(),
        coverColor: NotebookEntity.normalizeCoverColor(notebook.coverColor),
        coverImageUri: NotebookEntity.normalizeCoverImageUri(notebook.coverImageUri),
        pageCount: NotebookEntity.normalizePageCount(pageCount),
        isFavorite: notebook.isFavorite === true,
        tags: Array.isArray(notebook.tags) ? notebook.tags.slice() : [],
        isDeleted: notebook.isDeleted === true,
        deletedAt: typeof notebook.deletedAt === 'number' ? notebook.deletedAt : 0,
        lastOpenedAt: typeof notebook.lastOpenedAt === 'number' ? notebook.lastOpenedAt : 0
      };
      hasUpdated = true;
      break;
    }

    if (hasUpdated) {
      await this.writeNotebookList(notebookList);
    }
  }

  private async readNotebookList(): Promise<Notebook[]> {
    const preferenceContent: string = await this.preferencesDataSource.getString(StorageKeys.NOTEBOOK_LIST, '');
    const notebookListFromPreferences: Notebook[] = this.parseNotebookList(preferenceContent);
    if (notebookListFromPreferences.length > 0 || preferenceContent.length > 0) {
      return notebookListFromPreferences;
    }

    const fileContent: string = await this.fileDataSource.readText(NotebookImportService.NOTEBOOK_LIST_PATH, '[]');
    const notebookListFromFile: Notebook[] = this.parseNotebookList(fileContent);
    if (fileContent.length > 0) {
      await this.preferencesDataSource.putString(StorageKeys.NOTEBOOK_LIST, fileContent);
    }
    return notebookListFromFile;
  }

  private async writeNotebookList(notebookList: Notebook[]): Promise<void> {
    const content: string = JSON.stringify(notebookList);
    await this.preferencesDataSource.putString(StorageKeys.NOTEBOOK_LIST, content);
    await this.fileDataSource.writeText(NotebookImportService.NOTEBOOK_LIST_PATH, content);
  }

  private async writePageList(notebookId: string, pageList: NotebookPage[]): Promise<void> {
    await this.fileDataSource.writeText(`${NotebookImportService.PAGE_DIR}/${notebookId}.json`, JSON.stringify(pageList));
  }

  private async writeCanvas(canvas: NotebookPageCanvas): Promise<void> {
    await this.fileDataSource.writeText(`${NotebookImportService.CANVAS_DIR}/${canvas.pageId}.json`, JSON.stringify(canvas));
  }

  private async writePageContent(pageId: string, content: PageCanvasContent): Promise<void> {
    await this.editorRepository.savePageContent(pageId, content);
  }

  private parseNotebookList(content: string): Notebook[] {
    try {
      const parsed = JSON.parse(content);
      if (!Array.isArray(parsed)) {
        return [];
      }
      const result: Notebook[] = [];
      const usedTitleList: string[] = [];
      for (const item of parsed) {
        const notebook = this.parseNotebook(item);
        if (notebook !== null) {
          const uniqueTitle: string = NotebookEntity.createUniqueTitle(notebook.title, usedTitleList);
          result.push({
            id: notebook.id,
            title: uniqueTitle,
            folderId: notebook.folderId,
            createdAt: notebook.createdAt,
            updatedAt: notebook.updatedAt,
            coverColor: NotebookEntity.normalizeCoverColor(notebook.coverColor),
            coverImageUri: NotebookEntity.normalizeCoverImageUri(notebook.coverImageUri),
            pageCount: NotebookEntity.normalizePageCount(notebook.pageCount),
            isFavorite: notebook.isFavorite === true,
            tags: Array.isArray(notebook.tags) ? notebook.tags.slice() : [],
            isDeleted: notebook.isDeleted === true,
            deletedAt: typeof notebook.deletedAt === 'number' ? notebook.deletedAt : 0,
            lastOpenedAt: typeof notebook.lastOpenedAt === 'number' ? notebook.lastOpenedAt : 0
          });
          usedTitleList.push(uniqueTitle);
        }
      }
      return result;
    } catch (_error) {
      return [];
    }
  }

  private parseNotebook(value: unknown): Notebook | null {
    const map = this.asMap(value);
    if (map === null) {
      return null;
    }
    const now = TimeUtil.now();
    const tags = this.parseStringArray(map.tags);
    return {
      id: this.parseId(map.id, IdUtil.createNotebookId()),
      title: NotebookEntity.normalizeTitle(this.parseString(map.title)),
      folderId: NotebookEntity.normalizeFolderId(this.parseString(map.folderId)),
      createdAt: this.parseTimestamp(map.createdAt, now),
      updatedAt: this.parseTimestamp(map.updatedAt, now),
      coverColor: NotebookEntity.normalizeCoverColor(this.parseString(map.coverColor)),
      coverImageUri: NotebookEntity.normalizeCoverImageUri(this.parseString(map.coverImageUri)),
      pageCount: NotebookEntity.normalizePageCount(this.parseNumber(map.pageCount, 1)),
      isFavorite: this.parseBoolean(map.isFavorite),
      tags: tags,
      isDeleted: this.parseBoolean(map.isDeleted),
      deletedAt: this.parseTimestamp(map.deletedAt, 0),
      lastOpenedAt: this.parseTimestamp(map.lastOpenedAt, 0)
    };
  }

  private parseId(value: unknown, fallback: string): string {
    const id = this.parseString(value);
    return id.length > 0 ? id : fallback;
  }

  private parseString(value: unknown): string {
    return typeof value === 'string' ? value.trim() : '';
  }

  private parseNumber(value: unknown, fallback: number): number {
    return typeof value === 'number' && Number.isFinite(value) ? value : fallback;
  }

  private parseBoolean(value: unknown): boolean {
    return value === true;
  }

  private parseTimestamp(value: unknown, fallback: number): number {
    const timestamp = this.parseNumber(value, fallback);
    return TimeUtil.isValidTimestamp(timestamp) ? timestamp : fallback;
  }

  private parseStringArray(value: unknown): string[] {
    if (!Array.isArray(value)) {
      return [];
    }
    const result: string[] = [];
    for (const item of value) {
      const text = this.parseString(item);
      if (text.length > 0 && !result.includes(text)) {
        result.push(text);
      }
    }
    return result;
  }

  private collectNotebookTitleList(notebookList: Notebook[]): string[] {
    const titleList: string[] = [];
    for (const notebook of notebookList) {
      titleList.push(notebook.title);
    }
    return titleList;
  }

  private asMap(value: unknown): RawMap | null {
    if (value === null || typeof value !== 'object' || Array.isArray(value)) {
      return null;
    }
    return value as RawMap;
  }
}
