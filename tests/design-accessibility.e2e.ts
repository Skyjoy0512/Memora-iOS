import { test } from '@e2e-dev/mobile';
import { expect } from 'e2e';
import { focusComposer, launchMemora, tapControl } from './ui-helpers';

// Also run with the dedicated simulator's system text size set to Accessibility
// XXXL using agent-device settings. No fixed font override is injected in-app.
test('design: mention controls remain below navigation and above native input', async ({ app, device, screen }) => {
  await launchMemora(app, device, screen);
  await device.openLink('memora://ask-ai');
  const confirmation = screen.getByRole('button', { name: '開く', exact: true });
  if (await confirmation.isVisible()) await confirmation.tap();
  const input = await focusComposer(screen);
  await input.fill('@file');
  const close = screen.getByLabel('候補を閉じる');
  await expect(close).toBeVisible();
  await expect(screen.getByRole('button', { name: 'ファイル・記録の検索、利用可能', exact: true })).toBeVisible();
  const closeBox = await close.boundingBox();
  const inputBox = await input.boundingBox();
  if (!closeBox || !inputBox) throw new Error('mention layout has no frames');
  expect(closeBox.y).toBeGreaterThan(108);
  expect(closeBox.y + closeBox.height).toBeLessThan(inputBox.y);
  expect(closeBox.width).toBeGreaterThanOrEqual(44);
  expect(closeBox.height).toBeGreaterThanOrEqual(44);
  await app.screenshot('mention-layout');
  await tapControl(screen, close);
  await expect(close).not.toBeVisible();
  await expect(screen.getByRole('keyboard')).toBeVisible();
  await input.fill('');
});
