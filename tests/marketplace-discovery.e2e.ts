import { test } from '@e2e-dev/mobile';
import { expect } from 'e2e';
import { launchMemora, tapControl, tapTab } from './ui-helpers';

test('purpose catalogs preserve search and stage a learning skill without sending', { timeout: 180_000 }, async ({ app, device, screen }) => {
  await launchMemora(app, device, screen);
  await tapTab(screen, 'マーケットプレイス');
  await expect(screen.getByText('マイツール', { exact: true })).toBeVisible();
  const query = screen.getByTestId('collection.search.input');
  await query.fill('復習クイズ');
  await tapControl(screen.getByRole('button', { name: 'コネクタ', exact: true }));
  await expect(query).toHaveValue('復習クイズ');
  await expect(screen.getByTestId('marketplace.catalog.skill:study-quiz').first()).not.toBeVisible();
  await expect(screen.getByText('検索範囲：コネクタ', { exact: true })).toBeVisible();
  await tapControl(screen.getByRole('button', { name: 'すべてのカテゴリで検索', exact: true }));
  await expect(query).toHaveValue('復習クイズ');
  await expect(screen.getByTestId('marketplace.catalog.skill:study-quiz').first()).toBeVisible();
  await tapControl(screen.getByRole('button', { name: 'スキル', exact: true }));
  await expect(query).toHaveValue('復習クイズ');
  await tapControl(screen.getByTestId('marketplace.catalog.skill:study-quiz').first());
  await expect(screen.getByText('できあがるもの', { exact: true })).toBeVisible();
  await expect(screen.getByText('この講義の記録から復習クイズを5問作って', { exact: true })).toBeVisible();
  await app.screenshot('learning-skill-detail');
  await tapControl(screen.getByTestId('marketplace.detail.useSkill'));
  await expect(screen.getByTestId('ai.composer.input')).toHaveValue('[@復習クイズ] ');
  await expect(screen.getByTestId('ai.waitingStatus')).not.toBeVisible();
});
