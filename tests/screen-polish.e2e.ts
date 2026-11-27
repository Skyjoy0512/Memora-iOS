import { afterEach, test } from '@e2e-dev/mobile';
import { expect } from 'e2e';
import { launchMemora, openSettingsGallery, requireRootMenu, scrollToControl, tapControl, tapTab } from './ui-helpers';

afterEach(async ({ device }) => { await device.setAppearance('light'); });

test('screen polish: Library is the default and leads Journal in the tab bar', async ({ app, device, screen }) => {
  await launchMemora(app, device, screen);
  await expect(screen.getByRole('button', { name: 'ファイル', exact: true, selected: true })).toBeVisible();
  const library = screen.getByTestId('root.tab.files');
  const journal = screen.getByTestId('root.tab.home');
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
  const next = screen.getByTestId('onboarding.next');
  const start = screen.getByTestId('onboarding.local');
  await expect(screen.getByTestId('onboarding.primary')).not.toBeVisible();
  await tapControl(next);
  await expect(screen.getByText('あとから読み返す', { exact: true })).toBeVisible();
  await expect(start).not.toBeVisible();
  await tapControl(screen.getByRole('button', { name: '前へ', exact: true }));
  await expect(screen.getByText('会話を録音する', { exact: true })).toBeVisible();
  await tapControl(next);
  await tapControl(next);
  await expect(screen.getByText('タスクにつなげる', { exact: true })).toBeVisible();
  await expect(next).not.toBeVisible();
  await expect(start).toBeVisible();
  await app.screenshot('onboarding-last-page');
  await tapControl(screen, start);
  await requireRootMenu(app, screen);
  await expect(screen.getByText('録音画面を閉じる', { exact: true })).not.toBeVisible();
});

test('screen polish: onboarding stays open after microphone denial and can show a sample', { timeout: 120_000 }, async ({ app, device, screen }) => {
  await device.installApp(undefined, { reinstall: true });
  await device.setPermission('microphone', 'deny');
  await app.restart();
  const next = screen.getByTestId('onboarding.next');
  await tapControl(next);
  await expect(screen.getByText('あとから読み返す', { exact: true })).toBeVisible();
  await tapControl(next);
  await tapControl(screen.getByTestId('onboarding.primary'));
  await expect(screen.getByText('マイクへのアクセスが必要です', { exact: true }).first()).toBeVisible();
  await tapControl(screen.getByRole('button', { name: 'キャンセル', exact: true }));
  await expect(screen.getByText('タスクにつなげる', { exact: true })).toBeVisible();
  await app.screenshot('onboarding-after-microphone-denial');
  await tapControl(screen.getByTestId('onboarding.sample'));
  await expect(screen.getByText('発売準備ミーティング（サンプル）', { exact: true }).first()).toBeVisible();
  await expect(next).not.toBeVisible();
});

test('screen polish: onboarding completes when a recording starts', { timeout: 120_000 }, async ({ app, device, screen }) => {
  await device.installApp(undefined, { reinstall: true });
  await device.setPermission('microphone', 'grant');
  await app.restart();
  const next = screen.getByTestId('onboarding.next');
  await tapControl(next);
  await expect(screen.getByText('あとから読み返す', { exact: true })).toBeVisible();
  await tapControl(next);
  await tapControl(screen.getByTestId('onboarding.primary'));
  await expect(screen.getByRole('button', { name: '終了して保存', exact: true })).toBeVisible();
  await tapControl(screen.getByRole('button', { name: '終了して保存', exact: true }));
  await expect(screen.getByLabel('メニュー').first()).toBeVisible();
  await expect(next).not.toBeVisible();
});

test('screen polish: account and plan retain honest states and usable controls', { timeout: 180_000 }, async ({ app, device, screen }) => {
  await launchMemora(app, device, screen);
  await tapControl(screen.getByLabel('メニュー').first());
  await expect(screen.getByRole('button', { name: 'サインイン', exact: true })).not.toBeVisible();
  await tapControl(screen.getByTestId('sidebar.settings'));
  await tapControl(screen.getByTestId('settings.category.account'));
  await tapControl(screen.getByRole('button', { name: /^サインイン \/ 新規登録/ }));
  await expect(screen.getByText(/ログインせず、このiPhoneで使えます。/)).toBeVisible();
  await app.screenshot('account-local');
  await tapControl(screen.getByTestId('auth.continueLocal'));
  await tapControl(screen.getByTestId('BackButton'));
  await tapControl(screen.getByTestId('settings.category.plan'));

  const plan = screen.getByRole('button', { name: /^プラン、/ });
  await tapControl(plan);
  await expect(screen.getByText(/購入・復元は準備中/)).toBeVisible();
  const light = screen.getByTestId('plan.option.light');
  const pro = screen.getByTestId('plan.option.pro');
  await scrollToControl(screen, light);
  await expect(light).not.toBeSelected();
  await expect(pro).not.toBeSelected();
  await app.screenshot('plans-comparison-light');
  const save = screen.getByTestId('plan.chooseLocal');
  await scrollToControl(screen, save);
  await expect(save).toBeDisabled();
  await screen.swipe({ from: { x: 210, y: 260 }, to: { x: 210, y: 650 }, duration: 450 });
  await tapControl(light);
  await expect(light).toBeSelected();
  await device.setAppearance('dark');
  await app.screenshot('plans-comparison-dark');
  await scrollToControl(screen, save);
  await tapControl(save);
  await expect(screen.getByText('この端末の設定を更新しました。', { exact: true }).first()).toBeVisible();
  await expect(save).toBeDisabled();
  await tapControl(screen.getByRole('button', { name: '閉じる', exact: true }).last());
  await expect(plan).toHaveText(/ライト/);
  await tapControl(screen.getByRole('button', { name: /^AIクレジット、未接続/ }));
  await expect(screen.getByText('利用状況、未接続', { exact: true })).toBeVisible();
  await app.screenshot('credits-disconnected');
  await tapControl(screen.getByTestId('BackButton'));
  await tapControl(plan);
  await scrollToControl(screen, light);
  await expect(light).toBeSelected();
  const license = screen.getByRole('button', { name: '法人ライセンスコードを入力', exact: true });
  await scrollToControl(screen, license);
  await tapControl(license);
  const code = screen.getByRole('textbox', { name: 'ライセンスコード', exact: true });
  await expect(screen.getByRole('button', { name: '有効にする', exact: true })).toBeDisabled();
  await code.fill('invalid-code');
  await tapControl(screen.getByRole('button', { name: '有効にする', exact: true }));
  await expect(screen.getByText(/コードの形式が正しくありません/)).toBeVisible();
});

test('screen polish: the task editor still saves to the local store', async ({ app, device, screen }) => {
  await launchMemora(app, device, screen);
  await tapControl(screen, screen.getByLabel('メニュー').first());
  await tapControl(screen, screen.getByRole('button', { name: 'タスク', exact: true }).last());
  await tapControl(screen, screen.getByRole('button', { name: 'タスクを追加', exact: true }).last());
  await screen.getByPlaceholder('すること').fill('UI screen audit task');
  await tapControl(screen, screen.getByRole('button', { name: '追加', exact: true }));
  const task = screen.getByRole('button', { name: /^UI screen audit task、/ });
  await expect(task).toBeVisible();
  await app.screenshot('task-editor-saved');
  await app.restart();
  await tapControl(screen, screen.getByLabel('メニュー').first());
  await tapControl(screen, screen.getByRole('button', { name: 'タスク', exact: true }).last());
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
