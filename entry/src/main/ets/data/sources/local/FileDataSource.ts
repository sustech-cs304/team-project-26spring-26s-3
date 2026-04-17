import common from '@ohos.app.ability.common';
import fs from '@ohos.file.fs';

export class FileDataSource {
  private static readonly ROOT_DIR_NAME: string = 'hosn';

  constructor(private readonly context: common.Context) {
  }

  async readText(relativePath: string, defaultValue: string = ''): Promise<string> {
    const absolutePath: string = this.buildAbsolutePath(relativePath);
    try {
      if (!this.exists(absolutePath)) {
        return defaultValue;
      }
      return fs.readTextSync(absolutePath);
    } catch (_error) {
      return defaultValue;
    }
  }

  async writeText(relativePath: string, content: string): Promise<void> {
    const absolutePath: string = this.buildAbsolutePath(relativePath);
    let file: fs.File | undefined = undefined;

    try {
      this.ensureParentDirectory(absolutePath);
      const openMode: number = fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC;
      file = fs.openSync(absolutePath, openMode);
      fs.writeSync(file.fd, content);
    } catch (_error) {
    } finally {
      if (file !== undefined) {
        try {
          fs.closeSync(file);
        } catch (_closeError) {
        }
      }
    }
  }

  async delete(relativePath: string): Promise<void> {
    const absolutePath: string = this.buildAbsolutePath(relativePath);
    try {
      if (this.exists(absolutePath)) {
        fs.unlinkSync(absolutePath);
      }
    } catch (_error) {
    }
  }

  private buildAbsolutePath(relativePath: string): string {
    return `${this.context.filesDir}/${FileDataSource.ROOT_DIR_NAME}/${relativePath}`;
  }

  private ensureParentDirectory(filePath: string): void {
    const separatorIndex: number = filePath.lastIndexOf('/');
    if (separatorIndex <= 0) {
      return;
    }

    const directoryPath: string = filePath.substring(0, separatorIndex);
    try {
      fs.mkdirSync(directoryPath, true);
    } catch (_error) {
    }
  }

  private exists(path: string): boolean {
    try {
      return fs.accessSync(path);
    } catch (_error) {
      return false;
    }
  }
}
