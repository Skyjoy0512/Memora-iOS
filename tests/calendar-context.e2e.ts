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
    await tapControl(screen, screen.getByRole('button', { name: 'コネクタ', exact: true }));
    await tapControl(screen, screen.getByRole('button', { name: 'この端末のカレンダーを追加・接続', exact: true }));
    await tapControl(screen, screen.getByText('アクセスと利用設定', { exact: true }).first());
    await expect(screen.getByText('Google Calendarへの直接OAuth接続ではありません。', { exact: false })).toBeVisible();
  }
  await openCalendar();
  const enabled = screen.getByRole('switch', { name: 'Ask AIで使う', exact: true });
  await scrollToControl(screen, enabled);
  await expect(enabled).toBeChecked();
  // The footer asks to connect; the EventKit prompt only appears after a tap.
  const permission = screen.getByRole('button', { name: '接続', exact: true }).last();
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
