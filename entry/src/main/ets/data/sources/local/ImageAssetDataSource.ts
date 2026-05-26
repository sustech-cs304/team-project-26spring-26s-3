import common from '@ohos.app.ability.common';
import fs from '@ohos.file.fs';
import image from '@ohos.multimedia.image';

import { createId } from '../../../common/utils/IdUtil';

export interface ImportedImageAsset {
  uri: string;
  originalWidth: number;
  originalHeight: number;
}

export class ImageAssetDataSource {
  private static readonly ASSET_DIR_NAME: string = 'hosn/editor_assets/images';

  constructor(private readonly context: common.Context) {}

  async importImage(sourceUri: string): Promise<ImportedImageAsset> {
    if (sourceUri.length === 0) {
      throw new Error('Image uri is empty.');
    }

    const assetDirectory = `${this.context.filesDir}/${ImageAssetDataSource.ASSET_DIR_NAME}`;
    this.ensureDirectory(assetDirectory);
    const targetPath = `${assetDirectory}/${this.buildAssetFileName(sourceUri)}`;
    await this.copySourceToSandbox(sourceUri, targetPath);
    const imageSize = await this.getImageSize(targetPath);

    return {
      uri: targetPath,
      originalWidth: imageSize.width,
      originalHeight: imageSize.height
    };
  }

  private async copySourceToSandbox(sourceUri: string, targetPath: string): Promise<void> {
    const sourceCandidates = this.buildPathCandidates(sourceUri);
    for (const candidateSource of sourceCandidates) {
      try {
        await fs.copyFile(candidateSource, targetPath);
        return;
      } catch (_directCopyError) {
      }

      let sourceFile: fs.File | undefined = undefined;
      try {
        sourceFile = fs.openSync(candidateSource, fs.OpenMode.READ_ONLY);
        await fs.copyFile(sourceFile.fd, targetPath);
        return;
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

    throw new Error('Unable to copy image source.');
  }

  private async getImageSize(imagePath: string): Promise<{ width: number; height: number }> {
    const imageSource = image.createImageSource(imagePath);
    try {
      const imageInfo = await imageSource.getImageInfo();
      return {
        width: Math.max(1, imageInfo.size.width),
        height: Math.max(1, imageInfo.size.height)
      };
    } finally {
      try {
        await imageSource.release();
      } catch (_releaseError) {
      }
    }
  }

  private ensureDirectory(directoryPath: string): void {
    try {
      fs.mkdirSync(directoryPath, true);
    } catch (_error) {
    }
  }

  private buildAssetFileName(sourceUri: string): string {
    const extension = this.resolveImageExtension(sourceUri);
    return `${createId('image_asset')}${extension}`;
  }

  private resolveImageExtension(sourceUri: string): string {
    const normalizedUri = sourceUri.split('?')[0].split('#')[0].toLowerCase();
    const dotIndex = normalizedUri.lastIndexOf('.');
    if (dotIndex < 0 || dotIndex >= normalizedUri.length - 1) {
      return '.jpg';
    }

    const extension = normalizedUri.substring(dotIndex);
    switch (extension) {
      case '.jpg':
      case '.jpeg':
      case '.png':
      case '.webp':
      case '.gif':
      case '.bmp':
        return extension;
      default:
        return '.jpg';
    }
  }

  private buildPathCandidates(path: string): string[] {
    const candidates: string[] = [];
    this.appendPathCandidate(candidates, path);

    const decodedPath: string = this.decodeUriSegment(path);
    if (decodedPath !== path) {
      this.appendPathCandidate(candidates, decodedPath);
    }

    if (path.startsWith('file://')) {
      const rawLocalPath: string = path.substring('file://'.length);
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

    if (decodedPath.startsWith('file://')) {
      const decodedSchemePath: string = decodedPath.substring('file://'.length);
      this.appendPathCandidate(candidates, decodedSchemePath);
      if (!decodedSchemePath.startsWith('/')) {
        this.appendPathCandidate(candidates, `/${decodedSchemePath}`);
      }
    }

    return candidates;
  }

  private appendPathCandidate(candidates: string[], path: string): void {
    if (path.length === 0 || candidates.includes(path)) {
      return;
    }
    candidates.push(path);
  }

  private decodeUriSegment(text: string): string {
    try {
      return decodeURIComponent(text);
    } catch (_error) {
      return text;
    }
  }
}
