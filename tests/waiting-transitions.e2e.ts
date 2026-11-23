import { test } from '@e2e-dev/mobile';
import { expect } from 'e2e';
import { launchMemora, openSettingsGallery, scrollToControl, tapControl } from './ui-helpers';

test('waiting text yields to streaming, stops for approval and terminal states', async ({ app, device, screen }) => {
  await launchMemora(app, device, screen);
  await tapControl(screen.getByLabel('メニュー').first());
  await tapControl(screen.getByTestId('sidebar.settings'));
  await openSettingsGallery(screen);
  const destination = screen.getByRole('button', { name: 'AI待機表示（状態遷移の確認）', exact: true });
  await scrollToControl(screen, destination);
  await tapControl(destination);
  const status = screen.getByTestId('ai.waitingStatus');
  await expect(status).toHaveCount(2);
  await expect(screen.getByLabel('考えています', { exact: true }).first()).toBeVisible();
  await expect(screen.getByText(/^\d+(\.\d+)?s$/)).not.toBeVisible();
  await expect(screen.getByRole('progressbar')).not.toBeVisible();
  const history = screen.getByLabel('実行状況 · 操作1件', { exact: true }).first();
  await tapControl(history);
  await expect(screen.getByText('記録を確認', { exact: true })).toBeVisible();
  await expect(screen.getByText('実行中', { exact: true }).first()).toBeVisible();
  await app.screenshot('waiting-tool-detail');
  await tapControl(history);
  const reduce = screen.getByRole('switch', { name: 'シマーを休止（表示検証）', exact: true });
  await reduce.check();
  await expect(reduce).toBeChecked();
  await app.screenshot('waiting-shimmer-paused');
  for (const state of ['本文受信中', '承認待ち', '完了', '失敗', 'キャンセル']) {
    await tapControl(screen.getByRole('button', { name: /^状態、/ }));
    await tapControl(screen.getByRole('button', { name: state, exact: true }));
    await expect(status).toHaveCount(state === '承認待ち' ? 2 : 1);
    if (state === '承認待ち') await expect(screen.getByText('確認を待っています', { exact: true })).toBeVisible();
    if (state === '本文受信中') await expect(screen.getByText('本文の受信が始まりました。', { exact: true })).toBeVisible();
    await app.screenshot('waiting-' + state);
  }
});
