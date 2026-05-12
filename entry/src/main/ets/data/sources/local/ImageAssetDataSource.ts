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
    try {
      await fs.copyFile(sourceUri, targetPath);
      return;
    } catch (_directCopyError) {
    }

    let sourceFile: fs.File | undefined = undefined;
    try {
      sourceFile = fs.openSync(sourceUri, fs.OpenMode.READ_ONLY);
      await fs.copyFile(sourceFile.fd, targetPath);
    } finally {
      if (sourceFile !== undefined) {
        try {
          fs.closeSync(sourceFile);
        } catch (_closeError) {
        }
      }
    }
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
}
