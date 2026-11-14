import { afterEach, test } from '@e2e-dev/mobile';
import { expect } from 'e2e';
import { launchMemora, tapControl, tapTab } from './ui-helpers';

afterEach(async ({ device }) => { await device.setAppearance('light'); });

test('GitHub and Linear have read-only setup with no empty-token connection', { timeout: 180_000 }, async ({ app, device, screen }) => {
  await launchMemora(app, device, screen);
  await tapTab(screen, 'マーケットプレイス');
  const query = screen.getByTestId('collection.search.input');
  for (const [id, name] of [['github', 'GitHub'], ['linear', 'Linear']]) {
    await query.fill(name);
    await tapControl(screen.getByTestId('marketplace.catalog.service:' + id).first());
    await expect(screen.getByText('読み取り専用', { exact: true })).toBeVisible();
    await expect(screen.getByTestId('connector.requirement')).toBeVisible();
    await tapControl(screen.getByRole('button', { name: '接続', exact: true }));
    await tapControl(screen.getByTestId('connector.preset.add'));
    await expect(screen.getByTestId('connector.token')).toBeVisible();
    await expect(screen.getByRole('switch', { name: 'ブラウザーでサインイン（OAuth）', exact: true })).not.toBeVisible();
    await expect(screen.getByRole('button', { name: '保存', exact: true })).toBeDisabled();
    await expect(screen.getByTestId('connector.check')).toBeDisabled();
    await app.screenshot(id + '-read-only-token-setup');
    await device.setAppearance('dark');
    await app.screenshot(id + '-read-only-token-setup-dark');
    await device.setAppearance('light');
    await tapControl(screen.getByRole('button', { name: 'キャンセル', exact: true }));
    await tapControl(screen.getByTestId('BackButton'));
    await tapControl(screen.getByRole('button', { name: '閉じる', exact: true }));
  }
});
