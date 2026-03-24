import { BackupExtensionAbility, BundleVersion } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;
const TAG = 'CanvasNotebookBackup';

export default class EntryBackupAbility extends BackupExtensionAbility {
  async onBackup(): Promise<void> {
    hilog.info(DOMAIN, TAG, 'onBackup');
    await Promise.resolve();
  }

  async onRestore(bundleVersion: BundleVersion): Promise<void> {
    hilog.info(DOMAIN, TAG, 'onRestore %{public}s', JSON.stringify(bundleVersion));
    await Promise.resolve();
  }
}
