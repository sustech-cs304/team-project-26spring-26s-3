import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { Hypium } from '@ohos/hypium';
import testsuite from '../test/List.test';

const TEST_TAG: string = 'HosnOhosTest';
const ON_DESTROY_ERROR: number = -2;

export default class TestAbility extends UIAbility {
  private abilityDelegator: abilityDelegatorRegistry.AbilityDelegator = abilityDelegatorRegistry.getAbilityDelegator();

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(0x0000, TEST_TAG, 'TestAbility onCreate. want=%{public}s', JSON.stringify(want) ?? '');
    hilog.info(0x0000, TEST_TAG, 'TestAbility launchParam=%{public}s', JSON.stringify(launchParam) ?? '');

    const abilityDelegatorArguments = abilityDelegatorRegistry.getArguments();
    Hypium.hypiumTest(this.abilityDelegator, abilityDelegatorArguments, testsuite);
  }

  onDestroy(): void {
    hilog.info(0x0000, TEST_TAG, 'TestAbility onDestroy.');
    this.abilityDelegator.finishTest('TestAbility destroyed unexpectedly.', ON_DESTROY_ERROR, () => {});
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(0x0000, TEST_TAG, 'TestAbility onWindowStageCreate.');
    windowStage.loadContent('testability/pages/Index', (error) => {
      if (error.code) {
        hilog.error(0x0000, TEST_TAG, 'Load test page failed: %{public}s', JSON.stringify(error) ?? '');
        return;
      }

      hilog.info(0x0000, TEST_TAG, 'Test page loaded.');
    });
  }
}
