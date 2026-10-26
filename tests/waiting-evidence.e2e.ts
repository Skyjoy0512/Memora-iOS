import { afterEach, test } from '@e2e-dev/mobile';
import { expect } from 'e2e';
import { execFileSync } from 'node:child_process';
import { launchMemora, openSettingsGallery, scrollToControl, tapControl } from './ui-helpers';

afterEach(async ({ device }) => { await device.setAppearance('light'); });

test('waiting evidence uses actual status components with local display fixtures', { timeout: 240_000 }, async ({ app, device, screen }) => {
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
  if (process.env.MEMORA_WAITING_PROFILE_ROOT) {
    await device.setAppearance('light');
    const devices = JSON.parse(execFileSync('xcrun', ['simctl', 'list', 'devices', 'available', '--json'], { encoding: 'utf8' }));
    const targets = Object.values(devices.devices).flat().filter((value: any) =>
      value.name === 'iPhone 18 Pro Max' && value.state === 'Booted') as any[];
    if (targets.length !== 1) throw new Error('Select one isolated profiling simulator');
    const appPath = process.env.MEMORA_E2E_APP_PATH ??
      '/Users/ken/Library/Bitrig/Users/23515/Builds/a8e58691-1b31-4bb3-8c2f-f9dec163a2ea/DerivedData/Build/Products/Debug-iphonesimulator/Memora.app';
    console.log(execFileSync('python3', ['tools/checks/capture-simulator-profile.py',
      '--simulator', targets[0].udid, '--app', appPath, '--configuration', 'Debug',
      '--seconds', '15', '--output-dir', process.env.MEMORA_WAITING_PROFILE_ROOT],
      { encoding: 'utf8', timeout: 90_000 }));
  }
});
