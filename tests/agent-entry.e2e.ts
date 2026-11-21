import { afterEach, test } from '@e2e-dev/mobile';
import { expect } from 'e2e';
import { focusComposer, launchMemora, tapControl, tapTab } from './ui-helpers';

afterEach(async ({ device }) => { await device.setAppearance('light'); });

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

test('agent entry: recorder hub exposes direct pairing and honest generic import', async ({ app, device, screen }) => {
  await launchMemora(app, device, screen);
  await tapControl(screen.getByTestId('recorder.toolbarStatus'));
  await expect(screen.getByTestId('recorder.omi')).toBeVisible();
  await expect(screen.getByTestId('recorder.plaud')).not.toBeVisible();
  await expect(screen.getByTestId('recorder.other')).toBeVisible();
  await expect(screen.getByText(/OmiはBluetoothで直接接続できます/)).not.toBeVisible();
  await app.screenshot('agent-recorder-hub');
  await tapControl(screen.getByTestId('recorder.omi'));
  const search = screen.getByRole('button', { name: 'Omiを探す', exact: true });
  await expect(search).toBeVisible();
  const searchBox = await search.boundingBox();
  if (!searchBox) throw new Error('Omi search button has no frame');
  expect(searchBox.height).toBeGreaterThanOrEqual(44);
  await app.screenshot('recorder-omi-centered-label');
  await tapControl(screen.getByRole('button', { name: '完了', exact: true }));
  await tapControl(screen, screen.getByTestId('recorder.other'));
  await expect(screen.getByTestId('recorder.importAudio')).toBeVisible();
  await expect(screen.getByText(/PLAUD、ICレコーダー、ボイスメモから音声を書き出し/)).toBeVisible();
  await expect(screen.getByText('Bluetooth直接接続', { exact: true })).toBeVisible();
  await expect(screen.getByText('Bluetooth直接接続、未対応', { exact: true })).toBeVisible();
  await app.screenshot('agent-recorder-generic-import');
  await tapControl(screen, screen.getByTestId('recorder.importAudio'));
  const cancel = screen.getByRole('button', { name: /^(キャンセル|Cancel)$/ });
  await expect(cancel).toBeVisible();
  await tapControl(screen, cancel);
  await expect(screen.getByTestId('recorder.importAudio')).toBeEnabled();
  await expect(screen.getByTestId('recorder.importSuccess')).not.toBeVisible();
});
