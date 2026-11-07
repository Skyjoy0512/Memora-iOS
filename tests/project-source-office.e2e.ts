import { test } from '@e2e-dev/mobile';
import { expect } from 'e2e';
import { launchMemora, openSettingsGallery, scrollToControl, tapControl } from './ui-helpers';

// The existing, explicitly labelled Debug fixture creates real local packages
// and invokes production import/extraction/file/SQLite paths. No provider runs.
test('Office source import preserves partial coverage and reopens extracted text', async ({ app, device, screen }) => {
  await launchMemora(app, device, screen);
  await tapControl(screen.getByRole('button', { name: 'メニュー', exact: true }).first());
  await tapControl(screen.getByTestId('sidebar.settings'));
  await openSettingsGallery(screen);
  const destination = screen.getByRole('button', { name: 'Officeソース（取込と保存の検証）', exact: true });
  await scrollToControl(screen, destination);
  await tapControl(destination);
  await tapControl(screen.getByRole('button', { name: 'Officeソースの取込を検証', exact: true }));
  await expect(screen.getByText('3形式の取込・本文再読込・添付解析が成功。SQLite再読込一致: 3件。外部送信はオフです。', { exact: true })).toBeVisible({ timeout: 60_000 });
  const word = screen.getByRole('button', { name: /^QA-Word-/ }).first();
  await scrollToControl(screen, word);
  await tapControl(word);
  await expect(screen.getByText(/^文書 · 取得：/)).toBeVisible();
  await expect(screen.getByText('MEMORA OFFICE FIXTURE', { exact: true })).toBeVisible();
  await app.screenshot('office-source-partial-coverage');
  await tapControl(screen.getByRole('button', { name: '閉じる', exact: true }).first());
  const cleanup = screen.getByRole('button', { name: '検証データを削除', exact: true });
  await scrollToControl(screen, cleanup);
  await tapControl(cleanup);
  await expect(screen.getByText('検証データを削除しました。', { exact: true })).toBeVisible();
  await expect(screen.getByRole('button', { name: /^QA-Word-/ })).not.toBeVisible();
});
