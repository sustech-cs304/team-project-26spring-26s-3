import { Driver, ON } from '@kit.TestKit';
import { describe, expect, it } from '@ohos/hypium';

export default function abilityTest(): void {
  describe('HosnDeviceSmoke', () => {
    it('launches test ability and renders test page', 0, async () => {
      const driver = Driver.create();

      await driver.delayMs(1000);
      await driver.assertComponentExist(ON.text('Hosn device test ready'));

      const message = await driver.findComponent(ON.text('Hosn device test ready'));
      expect(message !== undefined).assertTrue();
    });
  });
}
