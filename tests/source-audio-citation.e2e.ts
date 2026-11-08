import { test } from '@e2e-dev/mobile';
import { expect } from 'e2e';
import { launchMemora, openSettingsGallery, scrollToControl, tapControl } from './ui-helpers';

// The existing Debug check writes a real timed transcript source and runs the
// production search, citation-target and SQLite paths. No model or network runs.
test('timed audio source keeps its citation at the recorded moment', async ({ app, device, screen }) => {
  await launchMemora(app, device, screen);
  await tapControl(screen.getByRole('button', { name: 'メニュー', exact: true }).first());
  await tapControl(screen.getByTestId('sidebar.settings'));
  await openSettingsGallery(screen);
  const destination = screen.getByRole('button', { name: '音声・字幕の引用位置（検証）', exact: true });
  await scrollToControl(screen, destination);
  await tapControl(destination);
  await tapControl(screen.getByRole('button', { name: '音声・字幕の引用を検証', exact: true }));
  await expect(screen.getByText('時刻12.5秒の引用・検索・引用リンク・SQLite一致を確認。外部送信はオフです。', { exact: true })).toBeVisible({ timeout: 60_000 });
  await app.screenshot('audio-source-citation-moment');
  const cleanup = screen.getByRole('button', { name: '検証データを削除', exact: true });
  await scrollToControl(screen, cleanup);
  await tapControl(cleanup);
  await expect(screen.getByText('検証データを削除しました。', { exact: true })).toBeVisible();
});
