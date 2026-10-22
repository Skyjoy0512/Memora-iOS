import { test } from '@e2e-dev/mobile';
import { expect } from 'e2e';
import { launchMemora, openSettingsGallery, scrollToControl, tapControl } from './ui-helpers';

// The existing Debug diagnostic invokes the production dispatcher/approval/SQLite
// path. It has no model/API call, and removes only its own saved UUIDs on exit.
async function openOperationCheck(app: any, device: any, screen: any) {
  await launchMemora(app, device, screen);
  await tapControl(screen, screen.getByLabel('メニュー').first());
  await tapControl(screen, screen.getByTestId('sidebar.settings'));
  await openSettingsGallery(screen);
  const destination = screen.getByRole('button', { name: 'タスク候補（承認と保存の検証）', exact: true });
  await scrollToControl(screen, destination);
  await tapControl(screen, destination);
  await tapControl(screen, screen.getByRole('button', { name: '承認と保存を検証', exact: true }));
  await expect(screen.getByText('タスクを2件追加', { exact: true })).toBeVisible();
}

test('local agent approval edits and selects a candidate before a real SQLite save', async ({ app, device, screen }) => {
  await openOperationCheck(app, device, screen);
  await tapControl(screen, screen.getByRole('button', { name: /QA .* 見積書を確認を編集/ }));
  await screen.getByPlaceholder('タイトル').fill('Reviewed local task');
  await tapControl(screen, screen.getByLabel('候補に反映', { exact: true }));
  // Selection is persistent state, represented by the existing button Toggle.
  await tapControl(screen, screen.getByRole('button', { name: /QA .* 次回の未決事項を整理$/, exact: true }));
  await expect(screen.getByText('タスクを1件追加', { exact: true })).toBeVisible();
  await app.screenshot('agent-before-approval');
  await tapControl(screen, screen.getByRole('button', { name: '追加', exact: true }));
  await expect(screen.getByText(/SQLite再読込一致: 1件/)).toBeVisible();
  await expect(screen.getByText(/同一依頼の再実行を拒否しました/)).toBeVisible();
  await expect(screen.getByText('Reviewed local task', { exact: true })).toBeVisible();
  await app.screenshot('agent-saved-from-edited-proposal');
});

test('local agent decline and stop resolve the approval without saving', async ({ app, device, screen }) => {
  await openOperationCheck(app, device, screen);
  await tapControl(screen, screen.getByRole('button', { name: 'やめる', exact: true }));
  await expect(screen.getByText(/利用者が承認しなかったため/)).toBeVisible();
  await expect(screen.getByRole('button', { name: '承認と保存を検証', exact: true })).toBeEnabled();
  await expect(screen.getByText(/SQLite再読込一致/)).not.toBeVisible();
  await tapControl(screen, screen.getByRole('button', { name: '承認と保存を検証', exact: true }));
  await expect(screen.getByText('タスクを2件追加', { exact: true })).toBeVisible();
  await tapControl(screen, screen.getByRole('button', { name: '検証を停止', exact: true }));
  await expect(screen.getByRole('button', { name: '承認と保存を検証', exact: true })).toBeEnabled();
  await expect(screen.getByRole('button', { name: '追加', exact: true })).not.toBeVisible();
  await expect(screen.getByText(/SQLite再読込一致/)).not.toBeVisible();
  await app.screenshot('agent-stopped-without-save');
});
