import { afterEach, test } from '@e2e-dev/mobile';
import { expect } from 'e2e';
import { launchMemora, openSettingsGallery, scrollToControl, tapControl } from './ui-helpers';

afterEach(async ({ device }) => { await device.setAppearance('light'); });

test('waiting evidence uses actual status components with local display fixtures', async ({ app, device, screen }) => {
  await launchMemora(app, device, screen);
  await tapControl(screen.getByLabel('メニュー').first());
  await tapControl(screen.getByTestId('sidebar.settings'));
  await openSettingsGallery(screen);
  const destination = screen.getByRole('button', { name: 'Ask AIの経過（表示の確認）', exact: true });
  await scrollToControl(screen, destination);
  await tapControl(destination);
  await expect(screen.getByText('作業しています', { exact: true }).first()).toBeVisible();
  for (const appearance of ['light', 'dark'] as const) {
    await device.setAppearance(appearance);
    await app.screenshot(`waiting-${appearance}`);
  }
});
