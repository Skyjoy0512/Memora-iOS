import { afterEach, test } from '@e2e-dev/mobile';
import { expect } from 'e2e';
import { focusComposer, launchMemora, tapControl, tapTab } from './ui-helpers';

afterEach(async ({ device }) => { await device.setAppearance('light'); });

test('secondary collections have native back navigation and only the AI composer', { timeout: 180_000 }, async ({ app, device, screen }) => {
  await launchMemora(app, device, screen);
  for (const name of ['資料', '人物', 'タスク']) {
    await tapControl(screen.getByLabel('メニュー').first());
    await tapControl(screen.getByRole('button', { name, exact: true }));
    await expect(screen.getByTestId('BackButton')).toBeVisible();
    await expect(screen.getByTestId('ai.composer.input')).toBeVisible();
    await expect(screen.getByRole('button', { name: '追加メニュー', exact: true })).not.toBeVisible();
    await app.screenshot(`minimal-secondary-${name}`);
    await tapControl(screen.getByTestId('BackButton'));
    await expect(screen.getByLabel('メニュー').first()).toBeVisible();
  }

  await tapTab(screen, 'ライブラリ');
  await expect(screen.getByRole('button', { name: '追加メニュー', exact: true })).toBeVisible();
  await tapTab(screen, 'Ask AI');
  const input = await focusComposer(screen);
  const draft = '画面を切り替えても残る確認用の下書き';
  await input.fill(draft);
  await tapTab(screen, 'マーケットプレイス');
  await expect(screen.getByTestId('ai.composer.input')).not.toBeVisible();
  await tapControl(screen.getByLabel('マーケットプレイスの操作'));
  for (const name of ['コミュニティ', 'マイスキルを管理', 'マイテンプレートを管理', 'スキルを作成', 'テンプレートを作成']) {
    await expect(screen.getByRole('button', { name, exact: true })).toBeVisible();
  }
  await app.screenshot('minimal-marketplace-management-menu');
  await screen.tapAt({ x: 30, y: 740 });
  await tapTab(screen, 'Ask AI');
  await expect(input).toHaveValue(draft);
  await expect(screen.getByRole('button', { name: '追加メニュー', exact: true })).not.toBeVisible();
  await device.setAppearance('dark');
  await app.screenshot('minimal-ask-ai-dark');
});

test('catalog articles keep a single content title and toolbar management actions', { timeout: 180_000 }, async ({ app, device, screen }) => {
  await launchMemora(app, device, screen);
  await tapTab(screen, 'マーケットプレイス');
  const query = screen.getByTestId('collection.search.input');
  await query.fill('会議フォローアップ');
  await tapControl(screen.getByTestId('marketplace.catalog.skill:meeting-followup').first());
  await expect(screen.getByTestId('marketplace.detail.hero').getByText('会議フォローアップ', { exact: true })).toBeVisible();
  await expect(screen.getByTestId('marketplace.detail.useSkill')).toBeVisible();
  await tapControl(screen.getByLabel('スキルの操作'));
  await expect(screen.getByRole('button', { name: 'Markdownを共有', exact: true })).toBeVisible();
  await screen.tapAt({ x: 30, y: 740 });
  await app.screenshot('minimal-skill-detail');
  await tapControl(screen.getByRole('button', { name: '閉じる', exact: true }));

  await query.fill('動画・配信の要約');
  await tapControl(screen.getByTestId('marketplace.catalog.template:content.video').first());
  await expect(screen.getByTestId('marketplace.detail.useTemplate')).toBeVisible();
  await tapControl(screen.getByLabel('テンプレートの操作'));
  await expect(screen.getByRole('button', { name: 'これをもとに自分用を作る', exact: true })).toBeVisible();
  await screen.tapAt({ x: 30, y: 740 });
  await app.screenshot('minimal-template-detail');
  await tapControl(screen.getByRole('button', { name: '閉じる', exact: true }));

  await query.fill('Gmail');
  await tapControl(screen.getByTestId('marketplace.catalog.service:gmail').first());
  await expect(screen.getByTestId('marketplace.detail.hero').getByText('Gmail', { exact: true })).toBeVisible();
  await expect(screen.getByRole('button', { name: '接続', exact: true })).toBeVisible();
  await app.screenshot('minimal-connector-detail');
});
