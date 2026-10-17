import { test } from '@e2e-dev/mobile';
import { expect } from 'e2e';

// Local fixtures and deterministic locators only: no agent/model or provider calls.
async function scrollToText(screen: any, text: string) {
  for (let attempt = 0; attempt < 12; attempt++) {
    if (await screen.getByText(text).first().isVisible()) return;
    await screen.swipe({ from: { x: 215, y: 700 }, to: { x: 215, y: 250 } });
  }
  throw new Error(`could not scroll to ${text}`);
}

async function openGallery(app: any, device: any, screen: any) {
  await device.installApp();
  await app.open();
  await screen.getByLabel('メニュー').tap();
  await screen.getByText('設定').tap();
  await scrollToText(screen, '状態と復旧UIを確認');
  await screen.getByText('状態と復旧UIを確認').first().tap();
}

test('answer actions open selectable text and hide an unavailable retry', async ({ app, device, screen }) => {
  await openGallery(app, device, screen);
  await scrollToText(screen, '回答アクション（操作の確認）');
  await screen.getByText('回答アクション（操作の確認）').tap();
  await screen.getByLabel('回答のその他の操作').tap();
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
