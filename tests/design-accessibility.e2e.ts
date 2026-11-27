import { afterEach, test } from '@e2e-dev/mobile';
import { expect } from 'e2e';
import { focusComposer, launchMemora, openSidebarSearch, tapControl, tapTab } from './ui-helpers';

afterEach(async ({ device }) => { await device.setAppearance('light'); });

// Also run with the dedicated simulator's system text size set to Accessibility
// XXXL using agent-device settings. No fixed font override is injected in-app.
test('design: mention controls remain below navigation and above native input', async ({ app, device, screen }) => {
  await launchMemora(app, device, screen);
  await tapTab(screen, 'Ask AI');
  const input = await focusComposer(screen);
  await input.pressSequentially('@file');
  await expect(input).toHaveValue('@file');
  const close = screen.getByLabel('候補を閉じる');
  await expect(close).toBeVisible();
  await expect(screen.getByRole('button', { name: 'ファイル・記録の検索、利用可能', exact: true })).toBeVisible();
  const settledLayout = async () => {
    const closeBox = await close.boundingBox();
    const inputBox = await input.boundingBox();
    if (closeBox && inputBox && closeBox.y > 108 && closeBox.y + closeBox.height < inputBox.y
        && closeBox.width >= 44 && closeBox.height >= 44) return 'clear';
    return JSON.stringify({ closeBox, inputBox });
  };
  await expect.poll(settledLayout).toBe('clear');
  await app.screenshot('mention-layout');
  // The same layout holds in dark appearance.
  await device.setAppearance('dark');
  await expect.poll(settledLayout).toBe('clear');
  await app.screenshot('mention-layout-dark');
  await device.setAppearance('light');
  await tapControl(screen, close);
  await expect(close).not.toBeVisible();
  // With a hardware keyboard attached the soft keyboard has no node; the field
  // staying focused is the behaviour that matters.
  await expect(input).toBeFocused();
  await input.fill('');
});

test('design: toolbar search clears without dismissing input and cancels back to tabs', async ({ app, device, screen }) => {
  await launchMemora(app, device, screen);
  await openSidebarSearch(screen);
  const input = screen.getByRole('textbox').first();
  await expect(input).toBeFocused();
  await input.fill('DesignSearch');
  const clear = screen.getByLabel('検索語を消去');
  await expect(clear).toBeVisible();
  const box = await clear.boundingBox();
  if (!box) throw new Error('search clear has no frame');
  expect(box.width).toBeGreaterThanOrEqual(44);
  expect(box.height).toBeGreaterThanOrEqual(44);
  await tapControl(screen, clear);
  // XCTest exposes an empty native field's placeholder as its AX value.
  await expect(input).not.toHaveValue('DesignSearch');
  await expect(clear).not.toBeVisible();
  await expect(input).toBeFocused();
  await app.screenshot('search-clear');
  await tapControl(screen, screen.getByRole('button', { name: 'キャンセル', exact: true }));
  await expect(screen.getByRole('keyboard')).not.toBeVisible();
  await tapTab(screen, 'ライブラリ');
});
