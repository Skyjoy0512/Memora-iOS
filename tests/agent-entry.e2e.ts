import { afterEach, test } from '@e2e-dev/mobile';
import { expect } from 'e2e';
import { focusComposer, launchMemora, openSettingsGallery, requireRootMenu, tapControl, tapTab } from './ui-helpers';

afterEach(async ({ device }) => { await device.setAppearance('light'); });

test('agent entry: the task suggestion sends immediately and leaves an empty composer', { timeout: 120_000 }, async ({ app, device, screen }) => {
  await launchMemora(app, device, screen);
  await tapTab(screen, 'Ask AI');
  await tapControl(screen.getByTestId('ai.suggestion.tasks'));
  await expect(screen.getByText(/参照できる記録から決定事項と次にやることを整理/).first()).toBeVisible();
  await app.screenshot('ask-ai-task-suggestion-sent');
  await expect(screen.getByTestId('ai.agentSuggestions')).not.toBeVisible();
  await expect(screen.getByTestId('ai.composer.input')).toHaveValue('Memoraに話しかける');
  await expect(screen.getByLabel('新しいチャット')).toBeEnabled();
});

test('agent entry: suggestions stage an editable request without sending', async ({ app, device, screen }) => {
  await launchMemora(app, device, screen);
  await tapTab(screen, 'Ask AI');
  await expect(screen.getByTestId('ai.agentSuggestions')).toBeVisible();
  await expect(screen.getByTestId(/^ai.suggestion\./)).toHaveCount(3);
  await app.screenshot('agent-suggestions-light');
  await device.setAppearance('dark');
  await app.screenshot('agent-suggestions-dark');
  await tapControl(screen, screen.getByTestId('ai.suggestion.mail'));
  const input = screen.getByTestId('ai.composer.input');
  await expect(input).toHaveValue(/宛先は推測せず/);
  const stagedDraft = await input.inputValue();
  await expect(screen.getByRole('button', { name: '送信', exact: true })).toBeVisible();
  await expect(screen.getByLabel('新しいチャット')).toBeDisabled();
  await app.screenshot('agent-suggestion-draft');
  await app.restart();
  await requireRootMenu(app, screen);
  await tapTab(screen, 'Ask AI');
  await expect(input).toHaveValue(/宛先は推測せず/);
  await expect(screen.getByLabel('新しいチャット')).toBeDisabled();
  await expect(screen.getByTestId('ai.agentSuggestions')).not.toBeVisible();
  await expect(input).toHaveValue(stagedDraft);
  await expect(screen.getByLabel('新しいチャット')).toBeDisabled();
});

test('agent entry: chat attachment sheet preserves the draft, keyboard and attachment routes', async ({ app, device, screen }) => {
  await launchMemora(app, device, screen);
  await tapTab(screen, 'Ask AI');
  const input = await focusComposer(screen);
  await input.fill('添付メニューを開いても残す下書き');
  await tapControl(screen, screen.getByTestId('ai.composer.add'));
  for (const name of ['カメラ', '写真', 'ファイル', '最近の写真を表示']) {
    await expect(screen.getByRole('button', { name, exact: true })).toBeVisible();
  }
  await expect(screen.getByRole('switch', { name: 'Webで検索', exact: true })).toBeVisible();
  await app.screenshot('agent-native-attachment-menu');
  await tapControl(screen, screen.getByRole('button', { name: '閉じる', exact: true }).last());
  await expect(input).toBeFocused();
  await expect(input).toHaveValue('添付メニューを開いても残す下書き');
  await expect(screen.getByLabel('新しいチャット')).toBeDisabled();
  await input.pressSequentially(' @');
  await expect(screen.getByLabel('候補を閉じる')).toBeVisible();
});

test('agent entry: recorder hub distinguishes Omi pairing from PLAUD and other audio imports', { timeout: 120_000 }, async ({ app, device, screen }) => {
  await launchMemora(app, device, screen);
  await tapControl(screen.getByTestId('recorder.toolbarStatus'));
  await expect(screen.getByTestId('recorder.omi')).toBeVisible();
  await expect(screen.getByTestId('recorder.plaud')).toBeVisible();
  await expect(screen.getByTestId('recorder.other')).toBeVisible();
  await expect(screen.getByText('Bluetoothで接続', { exact: true })).toBeVisible();
  await expect(screen.getByText('書き出した音声を取り込む', { exact: true })).toBeVisible();
  await app.screenshot('agent-recorder-hub');
  await tapControl(screen.getByTestId('recorder.omi'));
  const search = screen.getByRole('button', { name: 'Omiを探す', exact: true });
  await expect(search).toBeVisible();
  const searchBox = await search.boundingBox();
  if (!searchBox) throw new Error('Omi search button has no frame');
  expect(searchBox.height).toBeGreaterThanOrEqual(44);
  await app.screenshot('recorder-omi-centered-label');
  await tapControl(search);
  await expect(screen.getByText(/この環境ではOmiを検索できません/)).toBeVisible();
  await app.screenshot('omi-simulator-unavailable');
  await tapControl(screen.getByRole('button', { name: '閉じる', exact: true }));
  await tapControl(screen.getByTestId('recorder.plaud'));
  await expect(screen.getByText(/PLAUDアプリで録音を開き/)).toBeVisible();
  await device.setAppearance('dark');
  await app.screenshot('plaud-import-dark');
  await tapControl(screen.getByTestId('BackButton'));
  await tapControl(screen, screen.getByTestId('recorder.other'));
  await expect(screen.getByTestId('recorder.importAudio')).toBeVisible();
  await expect(screen.getByText(/レコーダーやボイスメモから音声を「ファイル」に保存/)).toBeVisible();
  await app.screenshot('agent-recorder-generic-import');
  await tapControl(screen, screen.getByTestId('recorder.importAudio'));
  const cancel = screen.getByRole('button', { name: /^(キャンセル|Cancel)$/ });
  await expect(cancel).toBeVisible();
  await tapControl(screen, cancel);
  await expect(screen.getByTestId('recorder.importAudio')).toBeEnabled();
  await expect(screen.getByTestId('recorder.importSuccess')).not.toBeVisible();
});

test('agent entry: recorder search times out, retries and stops without leaving pairing', { timeout: 150_000 }, async ({ app, device, screen }) => {
  await launchMemora(app, device, screen);
  await tapControl(screen.getByLabel('メニュー').first());
  await tapControl(screen.getByTestId('sidebar.settings'));
  await openSettingsGallery(screen);
  await tapControl(screen.getByRole('button', { name: '外部レコーダーの状態（表示確認）', exact: true }));
  await tapControl(screen.getByRole('button', { name: '候補なしの検索', exact: true }));
  await expect(screen.getByRole('button', { name: '検索を中止', exact: true })).toBeVisible();
  const noDevices = screen.getByText('Omiが見つかりませんでした', { exact: true });
  await expect(noDevices).toBeVisible({ timeout: 22_000 });
  await app.screenshot('omi-scan-empty');
  await tapControl(screen.getByRole('button', { name: 'もう一度探す', exact: true }));
  await tapControl(screen.getByRole('button', { name: '検索を中止', exact: true }));
  await expect(screen.getByRole('button', { name: 'Omiを探す', exact: true })).toBeVisible();
  await expect(noDevices).not.toBeVisible();
  const close = screen.getByRole('button', { name: '閉じる', exact: true });
  await tapControl(close);
  await tapControl(screen.getByRole('button', { name: '接続中', exact: true }));
  await tapControl(screen.getByRole('button', { name: '接続を中止', exact: true }));
  await expect(screen.getByRole('button', { name: 'Omiを探す', exact: true })).toBeVisible();
  await tapControl(close);
  await tapControl(screen.getByRole('button', { name: 'アクセス未許可', exact: true }));
  await expect(screen.getByRole('button', { name: '設定を開く', exact: true })).toBeVisible();
  await tapControl(close);
  await tapControl(screen.getByRole('button', { name: 'Bluetoothオフ', exact: true }));
  await expect(screen.getByText('Bluetoothがオフです', { exact: true })).toBeVisible();
  await expect(screen.getByRole('button', { name: 'もう一度探す', exact: true })).toBeVisible();
});
