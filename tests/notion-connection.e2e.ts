import { test } from '@e2e-dev/mobile';
import { expect } from 'e2e';
import { launchMemora, scrollToControl, tapControl, tapTab } from './ui-helpers';

test('unconfigured Notion keeps native parent editing durable without claiming a connection', { timeout: 180_000 }, async ({ app, device, screen }) => {
  await launchMemora(app, device, screen);
  async function openSettings() {
    await tapTab(screen, 'ツール');
    await tapControl(screen.getByRole('button', { name: 'コネクタ', exact: true }));
    await tapControl(screen.getByRole('button', { name: 'Notionを追加・接続', exact: true }));
    const setup = screen.getByRole('button', { name: '接続', exact: true }).last();
    await scrollToControl(screen, setup);
    await tapControl(setup);
  }
  try {
    for (const appearance of ['light', 'dark'] as const) {
      await device.setAppearance(appearance);
      await openSettings();
      const parent = screen.getByPlaceholder('ページID または データベースID');
      await expect(parent).toBeVisible();
      // The iOS accessibility value of an empty native field is its placeholder.
      await expect(parent).toHaveValue('ページID または データベースID');
      await expect(screen.getByPlaceholder('インテグレーショントークン')).toBeVisible();
      await expect(screen.getByRole('button', { name: 'トークンを保存', exact: true })).toBeDisabled();
      await expect(screen.getByRole('button', { name: 'トークンを削除', exact: true })).not.toBeVisible();
      await expect(screen.getByText('未設定', { exact: true })).toBeVisible();
      await app.screenshot('notion-unconfigured-' + appearance);
      // Not a credential or real destination. Never save a token or send a page.
      await parent.fill('local-fixture-parent');
      await expect(parent).toHaveValue('local-fixture-parent');
      await app.restart();
      await openSettings();
      await expect(parent).toHaveValue('local-fixture-parent');
      await expect(screen.getByText('未設定', { exact: true })).toBeVisible();
      await parent.clear();
      await expect(parent).not.toHaveValue('local-fixture-parent');
      await expect(parent).toHaveValue('ページID または データベースID');
      await app.restart();
      await expect(screen.getByLabel('メニュー').first()).toBeVisible();
    }
  } finally { await device.setAppearance('light'); }
});
