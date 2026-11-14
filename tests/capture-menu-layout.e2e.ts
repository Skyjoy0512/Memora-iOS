import { test } from '@e2e-dev/mobile';
import { expect } from 'e2e';
import { launchMemora, openSettingsGallery, tapControl } from './ui-helpers';

test('attachment menu retains the composer and capture sheet only shows four actions', { timeout: 150_000 }, async ({ app, device, screen }) => {
  await launchMemora(app, device, screen);
  const composer = screen.getByTestId('ai.composer.input');
  await expect(composer).toBeVisible();
  const before = await composer.boundingBox();
  await tapControl(screen.getByLabel('添付を追加').first());
  await expect(screen.getByRole('button', { name: 'ファイルを選択…', exact: true })).toBeVisible();
  await expect(composer).toBeVisible();
  const during = await composer.boundingBox();
  if (!before || !during) throw new Error('Composer has no frame');
  expect(during.width).toBeCloseTo(before.width, 0);
  expect(during.y).toBeCloseTo(before.y, 0);
  await app.screenshot('attachment-menu-retains-composer');
  await screen.tapAt({ x: 220, y: 95 });
  await expect(screen.getByRole('button', { name: 'ファイルを選択…', exact: true })).not.toBeVisible();
  await tapControl(screen.getByRole('button', { name: '追加メニュー', exact: true }));
  for (const name of ['録音する', '音声を取り込む', 'オンライン会議を録音', 'ノートを追加']) {
    await expect(screen.getByRole('button', { name, exact: true })).toBeVisible();
  }
  for (const name of ['カメラ', '写真', 'ファイル', 'リンク', '閉じる']) {
    await expect(screen.getByRole('button', { name, exact: true })).not.toBeVisible();
  }
  await app.screenshot('capture-sheet-four-actions');
  await tapControl(screen.getByRole('button', { name: 'ノートを追加', exact: true }));
  await expect(screen.getByRole('textbox', { name: 'タイトル', exact: true })).toBeVisible();
  await tapControl(screen.getByRole('button', { name: '閉じる', exact: true }));
  await expect(composer).toBeVisible();
  await composer.fill('添付メニューを開いても残す下書き');
  await tapControl(screen.getByLabel('添付を追加').first());
  await expect(screen.getByRole('button', { name: 'ファイルを選択…', exact: true })).toBeVisible();
  await expect(composer).toHaveValue('添付メニューを開いても残す下書き');
  await app.screenshot('attachment-menu-retains-editing-composer');
  await screen.tapAt({ x: 220, y: 95 });
  await expect(composer).toHaveValue('添付メニューを開いても残す下書き');
});

test('calendar day tile can be reviewed without Calendar access or saved events', { timeout: 90_000 }, async ({ app, device, screen }) => {
  await launchMemora(app, device, screen);
  await tapControl(screen.getByLabel('メニュー').first());
  await tapControl(screen.getByTestId('sidebar.settings'));
  await openSettingsGallery(screen);
  await tapControl(screen.getByRole('button', { name: 'デザインと保存の検証', exact: true }));
  await expect(screen.getByTestId('design.review.upcoming').first()).toBeVisible();
  await expect(screen.getByText('20', { exact: true })).toBeVisible();
  await expect(screen.getByText('11月20日(金) 10:00', { exact: true })).toBeVisible();
  await app.screenshot('calendar-day-only-tile');
});
