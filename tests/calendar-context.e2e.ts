import { afterEach, test } from '@e2e-dev/mobile';
import { expect } from 'e2e';
import { launchMemora, scrollToControl, tapControl, tapTab } from './ui-helpers';

afterEach(async ({ device }) => { await device.setAppearance('light'); });

// Only the Ask AI preference changes. Never tap the EventKit permission action
// or read real calendar events in this dedicated, freshly installed simulator.
test('calendar context: disabled AI use persists and re-enabling does not grant device access', { timeout: 180_000 }, async ({ app, device, screen }) => {
  await launchMemora(app, device, screen);
  async function openCalendar() {
    await tapTab(screen, 'ツール');
    await tapControl(screen, screen.getByRole('tab', { name: 'コネクタ', exact: true }));
    await tapControl(screen, screen.getByRole('button', { name: 'この端末のカレンダー', exact: true }));
    await expect(screen.getByText('Google Calendarへの直接OAuth接続ではありません。', { exact: false })).toBeVisible();
  }
  await openCalendar();
  const enabled = screen.getByRole('switch', { name: 'Ask AIで利用する', exact: true });
  await scrollToControl(screen, enabled);
  await expect(enabled).toBeChecked();
  const permission = screen.getByRole('button', { name: 'カレンダーへのアクセスを許可', exact: true });
  await expect(permission).toBeVisible();
  await app.screenshot('calendar-unconfigured-light');
  await enabled.uncheck();
  await expect(enabled).toBeChecked({ checked: false });
  await app.restart();
  await openCalendar();
  await scrollToControl(screen, enabled);
  await expect(enabled).toBeChecked({ checked: false });
  await enabled.check();
  await expect(enabled).toBeChecked();
  await expect(permission).toBeVisible();
  await device.setAppearance('dark');
  await app.screenshot('calendar-reenabled-still-unconfigured-dark');
});
