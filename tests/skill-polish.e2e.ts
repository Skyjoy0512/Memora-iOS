import { afterEach, test } from '@e2e-dev/mobile';
import { expect } from 'e2e';
import { launchMemora, openSidebarSearch, tapControl, tapTab } from './ui-helpers';

afterEach(async ({ device }) => { await device.setAppearance('light'); });

test('skill polish: explain validation and protect an unsaved edit', async ({ app, device, screen }) => {
  await launchMemora(app, device, screen);
  await tapTab(screen, 'ツール');
  await tapControl(screen, screen.getByLabel('ツールを追加'));
  await tapControl(screen, screen.getByRole('button', { name: 'スキルを作成', exact: true }));
  await expect(screen.getByRole('button', { name: '保存', exact: true })).toBeDisabled();
  await expect(screen.getByTestId('skill.validation')).toHaveText(/スキル名/);
  await screen.getByPlaceholder('スキル名').fill('Working draft');
  await expect(screen.getByTestId('skill.validation')).toHaveText(/いつ使うか/);
  // Long-input boundaries are covered by SkillEditingPolishChecks. Keep the
  // native editing scenario focused on guidance, keyboard and discard behavior.
  await screen.getByPlaceholder('いつ使うか・何をするか').fill('Use before a meeting.');
  await expect(screen.getByTestId('skill.validation')).toHaveText(/作業手順/);
  await expect(screen.getByRole('button', { name: '保存', exact: true })).toBeDisabled();
  await tapControl(screen, screen.getByRole('button', { name: '完了', exact: true }));
  await expect(screen.getByRole('keyboard')).not.toBeVisible();
  await app.screenshot('skill-required-fields-light');
  await device.setAppearance('dark');
  await app.screenshot('skill-required-fields-dark');
  await tapControl(screen, screen.getByRole('button', { name: 'キャンセル', exact: true }));
  await expect(screen.getByRole('button', { name: '変更を破棄', exact: true })).toBeVisible();
  await app.screenshot('skill-discard-confirmation');
  await tapControl(screen, screen.getByRole('button', { name: '編集を続ける', exact: true }));
  await expect(screen.getByPlaceholder('スキル名')).toHaveValue('Working draft');
  await tapControl(screen, screen.getByRole('button', { name: 'キャンセル', exact: true }));
  await tapControl(screen, screen.getByRole('button', { name: '変更を破棄', exact: true }));
  await expect(screen.getByLabel('ツールを追加')).toBeVisible();
  await expect(screen.getByText('Working draft', { exact: true })).not.toBeVisible();
  await tapControl(screen, screen.getByLabel('ツールを追加'));
  await tapControl(screen, screen.getByRole('button', { name: 'スキルを作成', exact: true }));
  await tapControl(screen, screen.getByRole('button', { name: 'キャンセル', exact: true }));
  await expect(screen.getByLabel('ツールを追加')).toBeVisible();
  await expect(screen.getByRole('button', { name: '変更を破棄', exact: true })).not.toBeVisible();
});

test('skill polish: search Tools, open an article and clear the search', async ({ app, device, screen }) => {
  await launchMemora(app, device, screen);
  await tapTab(screen, 'ツール');
  await openSidebarSearch(screen);
  const search = screen.getByPlaceholder('ツールを検索');
  await search.fill('project');
  const article = screen.getByRole('button', { name: /プロジェクトの要点整理/ });
  await expect(article).toBeVisible();
  await app.screenshot('tools-search-skill');
  await tapControl(screen, article);
  await expect(screen.getByText('目的とシナリオ', { exact: true })).toBeVisible();
  await tapControl(screen, screen.getByLabel('1つ前に戻る'));
  await tapControl(screen, screen.getByLabel('検索語を消去'));
  await search.fill('zz-no-such-tool');
  await expect(screen.getByTestId('tools.empty').first()).toBeVisible();
  await app.screenshot('tools-search-empty');
  await tapControl(screen, screen.getByRole('tab', { name: 'テンプレート', exact: true }));
  await expect(screen.getByTestId('tools.empty').first()).toBeVisible();
  await tapControl(screen, screen.getByLabel('検索語を消去'));
  await search.fill('面接');
  await expect(screen.getByRole('button', { name: /採用面接/ }).last()).toBeVisible();
  await app.screenshot('tools-search-template');
  await tapControl(screen, screen.getByLabel('検索語を消去'));
  await search.fill('Notion');
  await tapControl(screen, screen.getByRole('tab', { name: 'コネクタ', exact: true }));
  await expect(screen.getByRole('button', { name: 'Notion', exact: true })).toBeVisible();
  await expect(screen.getByRole('button', { name: 'Gmail', exact: true })).not.toBeVisible();
  await device.setAppearance('dark');
  await app.screenshot('tools-search-connector-dark');
  await tapControl(screen, screen.getByRole('button', { name: 'キャンセル', exact: true }));
  await expect(screen.getByLabel('ツールを追加')).toBeVisible();
  await expect(screen.getByRole('button', { name: 'Gmail', exact: true })).toBeVisible();
});
