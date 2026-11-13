import { test } from '@e2e-dev/mobile';
import { expect } from 'e2e';
import { seedSummaryFixture } from './summary-fixture-helpers';
import { launchMemora, openSettingsGallery, scrollToControl, tapControl } from './ui-helpers';

test('record detail keeps a full-width Ask AI field while creation returns on the list', { timeout: 180_000 }, async ({ app, device, screen }) => {
  await seedSummaryFixture(app, device, screen);
  const composer = screen.getByTestId('ai.composer.input');
  const capture = screen.getByRole('button', { name: '追加メニュー', exact: true });
  await expect(composer).toBeVisible();
  await expect(capture).not.toBeVisible();
  const detailBox = await composer.boundingBox();
  if (!detailBox) throw new Error('Detail composer has no frame');
  await app.screenshot('detail-only-ask-ai');
  const paragraph = screen.getByRole('button', { name: '予算は10万円ではなく12万円。承認された場合だけ来週実施する。', exact: true });
  await scrollToControl(screen, paragraph);
  await tapControl(paragraph);
  await expect(screen.getByRole('textbox', { name: '本文', exact: true })).toHaveValue('予算は10万円ではなく12万円。承認された場合だけ来週実施する。');
  await tapControl(screen.getByRole('button', { name: '完了', exact: true }));
  await expect(composer).toBeVisible();
  await expect(capture).not.toBeVisible();
  await tapControl(screen.getByTestId('BackButton'));
  await expect(capture).toBeVisible();
  await expect(composer).toBeVisible();
  const listBox = await composer.boundingBox();
  if (!listBox) throw new Error('List composer has no frame');
  expect(detailBox.width).toBeGreaterThan(listBox.width + 40);
});

test('synthetic streaming settles without losing Markdown text or structure', { timeout: 150_000 }, async ({ app, device, screen }) => {
  await launchMemora(app, device, screen);
  await tapControl(screen.getByLabel('メニュー').first());
  await tapControl(screen.getByTestId('sidebar.settings'));
  await openSettingsGallery(screen);
  await tapControl(screen.getByRole('button', { name: 'Loading・本文表示を確認', exact: true }));
  await tapControl(screen.getByRole('button', { name: '本文の生成を確認', exact: true }));
  await expect(screen.getByRole('button', { name: '生成を停止', exact: true })).toBeVisible();
  await expect(screen.getByRole('button', { name: '生成を停止', exact: true })).not.toBeVisible({ timeout: 35_000 });
  const lastHeading = screen.getByText('検証段落12', { exact: true }).first();
  await scrollToControl(screen, lastHeading);
  await expect(lastHeading).toBeVisible();
  await expect(screen.getByText('日本語の長文とスクロール位置を確認するための架空の段落です。既存の文章は再リビールしません。', { exact: true }).last()).toBeVisible();
  await app.screenshot('streaming-text-settled');
});
