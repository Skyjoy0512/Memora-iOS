import { test } from '@e2e-dev/mobile';
import { expect } from 'e2e';
import { launchMemora, tapControl, openSettingsGallery } from './ui-helpers';

// Local fixtures and deterministic locators only: no agent/model or provider calls.
async function scrollToText(screen: any, text: string) {
  for (let attempt = 0; attempt < 12; attempt++) {
    if (await screen.getByText(text).first().isVisible()) return;
    await screen.swipe({ from: { x: 215, y: 700 }, to: { x: 215, y: 300 }, duration: 500 });
  }
  throw new Error(`could not scroll to ${text}`);
}

async function openGallery(app: any, device: any, screen: any) {
  await launchMemora(app, device, screen);
  await tapControl(screen, screen.getByLabel('メニュー').first());
  await tapControl(screen, screen.getByTestId('sidebar.settings'));
  await openSettingsGallery(screen);
  await expect(screen.getByText('デザインと保存の検証')).toBeVisible();
}

test('answer actions open selectable text and hide an unavailable retry', async ({ app, device, screen }) => {
  await openGallery(app, device, screen);
  await scrollToText(screen, '回答アクション（操作の確認）');
  await screen.getByText('回答アクション（操作の確認）').tap();
  await tapControl(screen.getByLabel('回答のその他の操作'));
  await tapControl(screen.getByRole('button', { name: '読み上げ', exact: true }));
  await expect(screen.getByRole('button', { name: '読み上げを停止', exact: true })).toBeVisible();
  await tapControl(screen.getByRole('button', { name: '読み上げを停止', exact: true }));
  await tapControl(screen.getByLabel('回答のその他の操作'));
  await expect(screen.getByText('もう一度回答')).toBeVisible();
  await screen.getByText('テキストを選択…').tap();
  await expect(screen.getByText('テキストを選択').first()).toBeVisible();
  await expect(screen.getByText(/費用と担当は未確認/).first()).toBeVisible();
  await screen.getByRole('button', '完了').tap();
  await screen.getByRole('switch', '再試行可能として表示').uncheck();
  await expect(screen.getByRole('switch', '再試行可能として表示')).toBeChecked({ checked: false });
  await screen.getByLabel('回答のその他の操作').tap();
  await expect(screen.getByText('回答を資料に保存')).toBeVisible();
  await expect(screen.getByText('もう一度回答')).not.toBeVisible();
});

test('a long composer draft can expand and collapse without submitting', async ({ app, device, screen }) => {
  await openGallery(app, device, screen);
  await screen.getByText('コンポーザー（操作の確認）').tap();
  await screen.getByText('長文の架空ドラフトを入れる').tap();
  const draft = Array.from({ length: 10 }, (_, i) => `確認事項${i + 1}: 読者、構成、費用、次回の相談で確認したい内容を整理します。`).join('\n');
  await screen.getByLabel('入力欄を広げる').tap();
  await expect(screen.getByLabel('入力欄を小さくする')).toBeVisible();
  await expect(screen.getByRole('textbox').first()).toHaveValue(draft);
  await screen.getByLabel('入力欄を小さくする').tap();
  await expect(screen.getByLabel('入力欄を広げる')).toBeVisible();
  await expect(screen.getByRole('textbox').first()).toHaveValue(draft);
  await screen.getByLabel('送信').tap();
  await expect(screen.getByRole('textbox').first()).toHaveValue(draft);
});

test('reusable skills: review an answer, save the procedure and reuse it after restart', { timeout: 180_000 }, async ({ app, device, screen }) => {
  await openGallery(app, device, screen);
  await scrollToText(screen, '回答アクション（操作の確認）');
  await tapControl(screen, screen.getByText('回答アクション（操作の確認）'));
  await tapControl(screen, screen.getByLabel('回答のその他の操作'));
  await tapControl(screen, screen.getByRole('button', { name: '回答からスキルを作成', exact: true }));
  const procedure = '次回の相談では、提案の読者と判断してほしい点を確認します。\n\n費用と担当は未確認です。合意した内容と分けて記載してください。';
  await expect(screen.getByLabel('スキルの手順')).toHaveValue(procedure);
  await expect(screen.getByRole('button', { name: '保存', exact: true })).toBeDisabled();
  await screen.getByPlaceholder('スキル名').fill('Reusable meeting brief');
  await screen.getByPlaceholder('いつ使うか・何をするか').fill('Use when preparing a meeting brief.');
  await app.screenshot('reusable-skill-reviewed');
  await tapControl(screen, screen.getByRole('button', { name: '保存', exact: true }));
  await expect(screen.getByText('回答アクションの確認', { exact: true }).first()).toBeVisible();
  await app.restart();
  await tapControl(screen, screen.getByLabel('メニュー').first());
  await tapControl(screen, screen.getByRole('button', { name: 'マーケットプレイス', exact: true }));
  await screen.getByTestId('collection.search.input').fill('Reusable meeting brief');
  await tapControl(screen, screen.getByRole('button', { name: /^Reusable meeting brief、/ }).first());
  // The pushed article follows the still-mounted list row in the native tree.
  await expect(screen.getByText('Use when preparing a meeting brief.', { exact: true }).last()).toBeVisible();
  await app.screenshot('reusable-skill-persisted');
  await tapControl(screen, screen.getByLabel('スキルの操作'));
  await tapControl(screen, screen.getByRole('button', { name: '編集', exact: true }));
  await expect(screen.getByLabel('スキルの手順')).toHaveValue(procedure);
  await tapControl(screen, screen.getByRole('button', { name: 'キャンセル', exact: true }));
  await tapControl(screen, screen.getByRole('button', { name: 'チャットで使用', exact: true }));
  await expect(screen.getByTestId('ai.composer.input')).toHaveValue(/\[@Reusable meeting brief\]/);
  await expect(screen.getByRole('button', { name: '送信', exact: true })).toBeVisible();
  // Selection is staged only; do not send to an AI provider or execute tools.
});
