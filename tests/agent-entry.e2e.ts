import { afterEach, test } from '@e2e-dev/mobile';
import { expect } from 'e2e';
import { focusComposer, launchMemora, tapControl, tapTab } from './ui-helpers';

afterEach(async ({ device }) => { await device.setAppearance('light'); });

test('agent entry: suggestions stage an editable request without sending', async ({ app, device, screen }) => {
  await launchMemora(app, device, screen);
  await tapTab(screen, 'Ask AI');
  await expect(screen.getByText('あなたのAIエージェント', { exact: true })).toBeVisible();
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
  await expect(screen.getByTestId('ai.suggestion.tasks')).toBeDisabled();
  await expect(input).toHaveValue(stagedDraft);
  await expect(screen.getByLabel('新しいチャット')).toBeDisabled();
});

test('agent entry: native attachment menu preserves draft and all existing routes', async ({ app, device, screen }) => {
  await launchMemora(app, device, screen);
  await tapTab(screen, 'Ask AI');
  const input = await focusComposer(screen);
  await input.fill('添付メニューを開いても残す下書き');
  await tapControl(screen, screen.getByLabel('添付を追加'));
  for (const name of ['写真を選択…', '音声を選択…', 'ファイルを選択…', 'プラグイン・スキル・ソース', '連携サービス…']) {
    await expect(screen.getByText(name, { exact: true })).toBeVisible();
  }
  await app.screenshot('agent-native-attachment-menu');
  await tapControl(screen, screen.getByText('連携サービス…', { exact: true }));
  await expect(screen.getByText('連携', { exact: true }).first()).toBeVisible();
  await tapControl(screen, screen.getByRole('button', { name: '閉じる', exact: true }).last());
  await expect(input).toHaveValue('添付メニューを開いても残す下書き');
  await expect(screen.getByLabel('新しいチャット')).toBeDisabled();
});

test('agent entry: recorder hub exposes direct pairing and honest generic import', async ({ app, device, screen }) => {
  await launchMemora(app, device, screen);
  await tapControl(screen, screen.getByLabel('メニュー').first());
  await expect(screen.getByRole('button', { name: 'サインイン', exact: true })).not.toBeVisible();
  await app.screenshot('agent-sidebar-no-sign-in');
  await tapControl(screen, screen.getByRole('button', { name: /外部レコーダー/ }));
  await expect(screen.getByTestId('recorder.omi')).toBeVisible();
  await expect(screen.getByTestId('recorder.plaud')).toBeVisible();
  await expect(screen.getByTestId('recorder.other')).toBeVisible();
  await app.screenshot('agent-recorder-hub');
  await tapControl(screen, screen.getByTestId('recorder.other'));
  await expect(screen.getByTestId('recorder.importAudio')).toBeVisible();
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
