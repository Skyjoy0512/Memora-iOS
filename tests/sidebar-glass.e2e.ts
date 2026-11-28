import { afterEach, test } from '@e2e-dev/mobile';
import { expect } from 'e2e';
import { focusComposer, launchMemora, tapControl as tap, tapTab } from './ui-helpers';

afterEach(async ({ device }) => {
  await device.setAppearance('light');
});

test('sidebar glass: supplied logo sits above auxiliary destinations in both appearances', async ({ app, device, screen }) => {
  await launchMemora(app, device, screen);
  for (const appearance of ['light', 'dark'] as const) {
    await device.setAppearance(appearance);
    await tap(screen, screen.getByLabel('メニュー').first());
    const logo = screen.getByTestId('sidebar.logo');
    const marketplace = screen.getByRole('button', { name: 'マーケットプレイス', exact: true });
    await expect(logo).toBeVisible();
    await expect(marketplace).toBeVisible();
    const mark = await logo.boundingBox();
    const row = await marketplace.boundingBox();
    expect(mark).not.toBeNull();
    expect(row).not.toBeNull();
    expect(mark!.width).toBeCloseTo(120, 0);
    expect(mark!.height).toBeCloseTo(120 * 65 / 346, 0);
    expect(mark!.y + mark!.height).toBeLessThan(row!.y);
    const search = screen.getByTestId('sidebar.search');
    await expect(search).toHaveText('ファイルを検索');
    const scope = await search.boundingBox();
    expect(scope!.height).toBeGreaterThanOrEqual(44);
    expect(scope!.y + scope!.height).toBeLessThanOrEqual(row!.y);
    await expect(screen.getByTestId('sidebar.settings')).toBeVisible();
    await app.screenshot(`sidebar-logo-${appearance}`);
    await tap(screen, marketplace);
    await tap(screen, screen.getByTestId('marketplace.close'));
    await expect(screen.getByTestId('root.tab.files')).toBeSelected();
  }
});

test('sidebar glass: create menu keeps the capture choices working', async ({ app, device, screen }) => {
  await launchMemora(app, device, screen);
  for (const appearance of ['light', 'dark'] as const) {
    await device.setAppearance(appearance);
    await tap(screen, screen.getByLabel('追加メニュー'));
    for (const name of ['録音する', '音声を取り込む', 'ノートを追加']) {
      await expect(screen.getByRole('button', { name, exact: true })).toBeVisible();
    }
    await app.screenshot(`capture-glass-${appearance}`);
    await tap(screen, screen.getByRole('button', { name: 'ノートを追加', exact: true }));
    await expect(screen.getByRole('textbox', { name: 'タイトル', exact: true })).toBeVisible();
    await tap(screen, screen.getByRole('button', { name: '閉じる', exact: true }));
    await expect(screen.getByLabel('追加メニュー')).toBeVisible();
  }
  await tapTab(screen, 'ジャーナル');
  await tap(screen, screen.getByLabel('追加メニュー'));
  await tap(screen, screen.getByRole('button', { name: 'ノートを追加', exact: true }));
  await expect(screen.getByRole('textbox', { name: 'タイトル', exact: true })).toBeVisible();
  await tap(screen, screen.getByRole('button', { name: '閉じる', exact: true }));
  await tapTab(screen, 'ライブラリ');
  await expect(screen.getByTestId('ai.composer.input')).toBeVisible();
});

test('sidebar glass: attachment glass keeps the composer mounted and preserves its draft', async ({ app, device, screen }) => {
  await launchMemora(app, device, screen);
  const input = screen.getByTestId('ai.composer.input');
  const before = await input.boundingBox();
  await tap(screen, screen.getByLabel('添付を追加'));
  const lastAction = screen.getByRole('button', { name: 'ファイルを選択…', exact: true });
  await expect(lastAction).toBeVisible();
  await expect(input).toBeVisible();
  const field = await input.boundingBox();
  expect(field!.y).toBeCloseTo(before!.y, 0);
  expect(field!.width).toBeCloseTo(before!.width, 0);
  await app.screenshot('attachment-composer-library');
  await tap(screen, screen.getByRole('button', { name: 'コネクタ…', exact: true }));
  await expect(screen.getByText('Gmail', { exact: true }).first()).toBeVisible();
  await tap(screen, screen.getByLabel('閉じる', { exact: true }).first());
  await expect(screen.getByLabel('添付を追加')).toBeVisible();
  await tapTab(screen, 'Ask AI');
  await focusComposer(screen);
  await input.fill('Keep this input.');
  await device.setAppearance('dark');
  await tap(screen, screen.getByLabel('添付を追加'));
  await expect(lastAction).toBeVisible();
  await expect(input).toHaveValue('Keep this input.');
  await app.screenshot('attachment-composer-draft-dark');
  await tap(screen, screen.getByRole('button', { name: 'プラグイン・スキル・ソース', exact: true }));
  await expect(screen.getByLabel('候補を閉じる')).toBeVisible();
  await expect(screen.getByRole('keyboard')).toBeVisible();
  await expect(input).toHaveValue(/Keep this input\./);
  await input.fill('');
});
