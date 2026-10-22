import { randomUUID } from 'node:crypto';
import { test } from '@e2e-dev/mobile';
import { expect } from 'e2e';
import { launchMemora, tapControl } from './ui-helpers';

test('source native photo and file pickers cancel without losing entered text', { timeout: 180_000 }, async ({ app, device, screen }) => {
  await launchMemora(app, device, screen);
  await tapControl(screen.getByRole('button', { name: 'プロジェクト', exact: true }));
  await tapControl(screen.getByRole('button', { name: 'プロジェクトを作成', exact: true }).first());
  await screen.getByPlaceholder('例：新規アプリ').fill('Picker-' + randomUUID().slice(0, 8));
  await tapControl(screen.getByRole('button', { name: '作成', exact: true }));
  await tapControl(screen.getByRole('button', { name: 'ソース', exact: true }));
  await tapControl(screen.getByRole('button', { name: 'ソースを追加', exact: true }).first());
  const link = screen.getByRole('textbox', { name: 'YouTube・WebのURL', exact: true });
  const draft = 'https://example.com/picker-' + randomUUID();
  await link.fill(draft);
  const closeKeyboard = screen.getByRole('button', { name: 'キーボードを閉じる', exact: true });
  if (await closeKeyboard.isVisible()) await tapControl(closeKeyboard);
  await expect(screen.getByRole('keyboard')).not.toBeVisible();
  const cancel = screen.getByRole('button', { name: /^(Cancel|キャンセル)$/ }).first();
  await tapControl(screen.getByRole('button', { name: '写真を選択', exact: true }));
  // The temporary loading sheet also has Cancel, but the real picker replaces
  // it at a different position. Wait for the actual picker before tapping.
  await expect(screen.getByRole('tab', { name: '写真', exact: true })).toBeVisible();
  await expect(cancel).toBeVisible();
  await app.screenshot('source-native-photo-picker');
  await tapControl(cancel);
  await expect(link).toHaveValue(draft);
  await expect(screen.getByRole('button', { name: 'リンクを保存', exact: true })).toBeEnabled();
  await tapControl(screen.getByRole('button', { name: 'ファイルを選択', exact: true }));
  await expect(screen.getByTestId('FullDocumentManagerViewControllerNavigationBar')).toBeVisible();
  await expect(cancel).toBeVisible();
  await app.screenshot('source-native-file-picker');
  await tapControl(cancel);
  await expect(link).toHaveValue(draft);
  await expect(screen.getByText('保存しました。', { exact: true })).not.toBeVisible();
  await app.screenshot('source-picker-cancel-retains-input');
  await tapControl(screen.getByRole('button', { name: '閉じる', exact: true }));
  await expect(screen.getByText('リンク・ファイル・メモを追加すると、AIの参照候補になります。', { exact: true })).toBeVisible();
});
