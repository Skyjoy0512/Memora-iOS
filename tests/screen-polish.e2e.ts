import { afterEach, test } from '@e2e-dev/mobile';
import { expect } from 'e2e';
import { launchMemora, openSettingsGallery, scrollToControl, tapControl, tapTab } from './ui-helpers';

afterEach(async ({ device }) => { await device.setAppearance('light'); });

test('screen polish: Library is the default and leads Journal in the tab bar', async ({ app, device, screen }) => {
  await launchMemora(app, device, screen);
  await expect(screen.getByRole('button', { name: 'ファイル', exact: true, selected: true })).toBeVisible();
  const library = screen.getByRole('tab', { name: 'ライブラリ', exact: true });
  const journal = screen.getByRole('tab', { name: 'ジャーナル', exact: true });
  await expect(library).toBeVisible();
  await expect(journal).toBeVisible();
  const libraryBox = await library.boundingBox();
  const journalBox = await journal.boundingBox();
  if (!libraryBox || !journalBox) throw new Error('root destinations have no frame');
  expect(libraryBox.x).toBeLessThan(journalBox.x);
  await app.screenshot('library-first-tab-bar');
  await tapControl(screen, journal);
  await expect(journal).toBeSelected();
  await app.restart();
  await expect(screen.getByRole('button', { name: 'ファイル', exact: true, selected: true })).toBeVisible();
});

test('screen polish: Settings opens after the drawer closes on every main destination', { timeout: 180_000 }, async ({ app, device, screen }) => {
  await launchMemora(app, device, screen);
  for (const destination of ['ジャーナル', 'Ask AI', 'ライブラリ', 'マーケットプレイス']) {
    await tapTab(screen, destination);
    await tapControl(screen, screen.getByLabel('メニュー').first());
    await tapControl(screen, screen.getByRole('button', { name: '設定', exact: true }).last());
    await expect(screen.getByTestId('settings.profile').first()).toBeVisible();
    await app.screenshot(`settings-from-${destination}`);
    await tapControl(screen, screen.getByRole('button', { name: '閉じる', exact: true }));
    await expect(screen.getByLabel('メニュー').first()).toBeVisible();
  }
});

test('screen polish: onboarding remains readable and can finish without recording', async ({ app, device, screen }) => {
  await device.installApp(undefined, { reinstall: true });
  await app.restart();
  await expect(screen.getByRole('button', { name: 'スキップ', exact: true })).toBeVisible();
  await app.screenshot('onboarding-light');
  await device.setAppearance('dark');
  await app.screenshot('onboarding-dark');
  const start = screen.getByRole('button', { name: 'このiPhoneで始める', exact: true });
  for (let page = 0; page < 5 && !(await start.isVisible()); page++) {
    await tapControl(screen, screen.getByRole('button', { name: '次へ', exact: true }));
  }
  await expect(start).toBeVisible();
  await app.screenshot('onboarding-last-page');
  await tapControl(screen, start);
  await expect(screen.getByLabel('メニュー').first()).toBeVisible();
  await expect(screen.getByText('録音画面を閉じる', { exact: true })).not.toBeVisible();
});

test('screen polish: account and plan retain honest states and usable controls', { timeout: 180_000 }, async ({ app, device, screen }) => {
  await launchMemora(app, device, screen);
  for (const appearance of ['light', 'dark'] as const) {
    await device.setAppearance(appearance);
    await tapControl(screen, screen.getByLabel('メニュー').first());
    await expect(screen.getByRole('button', { name: 'サインイン', exact: true })).not.toBeVisible();
    await tapControl(screen, screen.getByRole('button', { name: '設定', exact: true }).last());
    await tapControl(screen, screen.getByTestId('settings.category.account').first());
    await tapControl(screen, screen.getByRole('button', { name: /^サインイン \/ 新規登録/ }));
    await expect(screen.getByText(/サインインはまだ/)).toBeVisible();
    await app.screenshot(`account-${appearance}`);
    await tapControl(screen, screen.getByLabel('あとで').first());
    await tapControl(screen, screen.getByTestId('BackButton'));
    await tapControl(screen, screen.getByRole('button', { name: '閉じる', exact: true }).last());
    await tapControl(screen, screen.getByLabel('メニュー').first());
    await tapControl(screen, screen.getByRole('button', { name: 'Memora Plus、プランと利用状況', exact: true }));
    await expect(screen.getByText('プラン', { exact: true }).first()).toBeVisible();
    await app.screenshot(`plan-${appearance}`);
    const restore = screen.getByRole('button', { name: '購入を復元', exact: true });
    await scrollToControl(screen, restore);
    await tapControl(screen, restore);
    await expect(screen.getByText('購入はまだ接続されていません', { exact: true })).toBeVisible();
    await tapControl(screen, screen.getByRole('button', { name: 'OK', exact: true }));
    await tapControl(screen, screen.getByRole('button', { name: '閉じる', exact: true }));
  }
});

test('screen polish: the task editor still saves to the local store', async ({ app, device, screen }) => {
  await launchMemora(app, device, screen);
  await tapTab(screen, 'ジャーナル');
  await tapControl(screen, screen.getByLabel('すべてのタスクを見る'));
  await tapControl(screen, screen.getByRole('button', { name: 'タスクを追加', exact: true }).last());
  await screen.getByPlaceholder('すること').fill('UI screen audit task');
  await tapControl(screen, screen.getByRole('button', { name: '追加', exact: true }));
  const task = screen.getByRole('button', { name: /^UI screen audit task、/ });
  await expect(task).toBeVisible();
  await app.screenshot('task-editor-saved');
  await app.restart();
  await tapTab(screen, 'ジャーナル');
  await tapControl(screen, screen.getByLabel('すべてのタスクを見る'));
  await expect(task).toBeVisible();
});

test('screen polish: secondary lists and presentation fixtures remain navigable', { timeout: 180_000 }, async ({ app, device, screen }) => {
  await launchMemora(app, device, screen);
  await tapControl(screen, screen.getByLabel('メニュー').first());
  await tapControl(screen, screen.getByRole('button', { name: '設定', exact: true }).last());
  await expect(screen.getByTestId('settings.profile').first()).toBeVisible();
  await openSettingsGallery(screen);
  for (const [link, title] of [
    ['デザインと保存の検証', 'デザインと保存の検証'],
    ['Ask AI 2.0（表示の確認）', 'Ask AI 2.0の表示確認'],
    ['Loading・本文表示を確認', '表示の検証'],
    ['資料・メールの出典表示を確認', '出典表示'],
    ['回答アクション（操作の確認）', '回答アクションの確認'],
    ['構造化回答（表示の確認）', '構造化回答の表示確認'],
  ]) {
    const row = screen.getByRole('button', { name: link, exact: true });
    await scrollToControl(screen, row);
    await tapControl(screen, row);
    await expect(screen.getByText(title, { exact: true }).first()).toBeVisible();
    await app.screenshot(`fixture-${title}`);
    await tapControl(screen, screen.getByTestId('BackButton').first());
    await expect(screen.getByText('状態と復旧', { exact: true }).first()).toBeVisible();
  }
});
