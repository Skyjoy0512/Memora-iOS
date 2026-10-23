import { afterEach, test } from '@e2e-dev/mobile';
import { expect } from 'e2e';
import { launchMemora, openSidebarSearch, tapControl, tapTab } from './ui-helpers';

afterEach(async ({ device }) => { await device.setAppearance('light'); });

test('native header: recorder status opens the real hub and search lives in the sidebar', async ({ app, device, screen }) => {
  await launchMemora(app, device, screen);
  const status = screen.getByTestId('recorder.toolbarStatus');
  await expect(status).toBeVisible();
  await expect(screen.getByText('未接続', { exact: true })).toBeVisible();
  await expect(screen.getByRole('button', { name: '検索', exact: true })).not.toBeVisible();
  await app.screenshot('native-library-header-light');
  await device.setAppearance('dark');
  await app.screenshot('native-library-header-dark');
  await tapControl(screen, status);
  await expect(screen.getByTestId('recorder.omi')).toBeVisible();
  await expect(screen.getByTestId('recorder.other')).toBeVisible();
  await tapControl(screen, screen.getByRole('button', { name: '完了', exact: true }));
  await expect(status).toBeVisible();
  await openSidebarSearch(screen);
  await expect(screen.getByText('ファイルを検索', { exact: true })).toBeVisible();
  await expect(screen.getByTestId('ai.composer.input')).not.toBeVisible();
  await expect(screen.getByLabel('新規作成')).not.toBeVisible();
  await app.screenshot('native-library-sidebar-search');
  await tapControl(screen, screen.getByRole('button', { name: 'キャンセル', exact: true }));
  await expect(status).toBeVisible();
});

test('native header: journal sidebar search preserves its destination and flat content', async ({ app, device, screen }) => {
  await launchMemora(app, device, screen);
  await tapTab(screen, 'ジャーナル');
  await expect(screen.getByTestId('recorder.toolbarStatus')).toBeVisible();
  await openSidebarSearch(screen);
  const query = screen.getByPlaceholder('ジャーナルを検索');
  await expect(query).toBeVisible();
  await query.fill('存在しない記録の検索');
  await expect(screen.getByTestId('ai.composer.input')).not.toBeVisible();
  await app.screenshot('native-journal-sidebar-search');
  await tapControl(screen, screen.getByRole('button', { name: 'キャンセル', exact: true }));
  await expect(screen.getByTestId('recorder.toolbarStatus')).toBeVisible();
  await expect(screen.getByLabel('新規作成')).toBeVisible();
});

test('native header: Ask AI sidebar search retains the existing chat actions', async ({ app, device, screen }) => {
  await launchMemora(app, device, screen);
  await tapTab(screen, 'Ask AI');
  await openSidebarSearch(screen);
  await expect(screen.getByText('会話を検索', { exact: true })).toBeVisible();
  // Native search replaces the sheet toolbar while editing. Leave search
  // mode before using the sheet's real Done action.
  const closeSearch = screen.getByRole('button', { name: 'close', exact: true });
  if (await closeSearch.isVisible()) await tapControl(screen, closeSearch);
  await tapControl(screen, screen.getByRole('button', { name: '完了', exact: true }));
  await expect(screen.getByLabel('Memora、履歴と検索')).toBeVisible();
  await expect(screen.getByLabel('新しいチャット')).toBeDisabled();
});

test('native header: empty Library capture action retains its native dialog route', async ({ app, device, screen }) => {
  await launchMemora(app, device, screen);
  await tapControl(screen, screen.getByRole('button', { name: '録音または読み込み', exact: true }));
  await expect(screen.getByRole('button', { name: '録音を開始', exact: true })).toBeVisible();
  await tapControl(screen, screen.getByRole('button', { name: 'メモを作成', exact: true }));
  await expect(screen.getByPlaceholder('メモのタイトル')).toBeVisible();
  await tapControl(screen, screen.getByRole('button', { name: 'キャンセル', exact: true }));
  await expect(screen.getByTestId('recorder.toolbarStatus')).toBeVisible();
});
