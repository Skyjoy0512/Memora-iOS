import { test } from '@e2e-dev/mobile';
import { expect } from 'e2e';
import { launchMemora, openSettingsGallery, scrollToControl, tapControl } from './ui-helpers';

// Uses a bundled HTML fixture in the app; no external site is contacted.
test('web article text keeps its search and citation path', async ({ app, device, screen }) => {
  await launchMemora(app, device, screen);
  await tapControl(screen.getByRole('button', { name: 'メニュー', exact: true }).first());
  await tapControl(screen.getByTestId('sidebar.settings'));
  await openSettingsGallery(screen);
  const destination = screen.getByRole('button', { name: 'Web本文の引用（検証）', exact: true });
  await scrollToControl(screen, destination);
  await tapControl(destination);
  await tapControl(screen.getByRole('button', { name: 'Web本文の引用を検証', exact: true }));
  await expect(screen.getByText('Web本文の抽出・検索・引用・引用リンク・SQLite一致を確認。外部通信はオフです。', { exact: true })).toBeVisible({ timeout: 60_000 });
  await app.screenshot('web-source-citation');
  const cleanup = screen.getByRole('button', { name: '検証データを削除', exact: true });
  await scrollToControl(screen, cleanup);
  await tapControl(cleanup);
  await expect(screen.getByText('検証データを削除しました。', { exact: true })).toBeVisible();
});
