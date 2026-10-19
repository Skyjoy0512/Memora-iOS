import { test } from '@e2e-dev/mobile';
import { expect } from 'e2e';
import { launchMemora, tapControl, tapTab } from './ui-helpers';

// Fast checks that launch the app and read the screen. No model calls.
test('onboarding completion survives a normal restart', async ({ app, device, screen }) => {
  await launchMemora(app, device, screen);
  await app.restart();
  await expect(screen.getByText('今日のタスク')).toBeVisible();
  await expect(screen.getByRole('button', { name: 'スキップ', exact: true })).not.toBeVisible();
});

test('the app opens on the journal', async ({ app, device, screen }) => {
  await launchMemora(app, device, screen);
  await expect(screen.getByText('今日のタスク')).toBeVisible();
  await expect(screen.getByText('記録を追加').first()).toBeVisible();
});

test('the tabs switch between journal, library and Ask AI', async ({ app, device, screen }) => {
  await launchMemora(app, device, screen);
  await tapTab(screen, 'ライブラリ');
  await expect(screen.getByRole('button', { name: 'ファイル', exact: true, selected: true })).toBeVisible();
  await tapTab(screen, 'Ask AI');
  await expect(screen.getByLabel('新しいチャット')).toBeVisible();
  await tapTab(screen, 'ジャーナル');
  await expect(screen.getByText('今日のタスク')).toBeVisible();
});

test('the side menu lists the main destinations', async ({ app, device, screen }) => {
  await launchMemora(app, device, screen);
  await screen.getByLabel('メニュー').tap();
  await expect(screen.getByText('資料')).toBeVisible();
  await expect(screen.getByText('人物')).toBeVisible();
  await expect(screen.getByText('プロジェクト')).toBeVisible();
  await expect(screen.getByText('設定')).toBeVisible();
});

test('Settings opens from the side menu', async ({ app, device, screen }) => {
  await launchMemora(app, device, screen);
  await screen.getByLabel('メニュー').tap();
  await screen.getByText('設定').tap();
  await expect(screen.getByText('アカウント')).toBeVisible();
  await expect(screen.getByText('プラン').first()).toBeVisible();
});

test('the journal add-record action opens the capture sheet', async ({ app, device, screen }) => {
  await launchMemora(app, device, screen);
  await screen.getByText('記録を追加').first().tap();
  await expect(screen.getByText('ライフログを追加')).toBeVisible();
  await device.back();
  await expect(screen.getByText('今日のタスク')).toBeVisible();
});

test('the tasks list opens from the journal', async ({ app, device, screen }) => {
  await launchMemora(app, device, screen);
  await screen.getByLabel('すべてのタスクを見る').first().tap();
  await expect(screen.getByText('タスクはありません')).toBeVisible();
  await expect(screen.getByText('未完了')).toBeVisible();
});

/// Scrolls the current screen up until the text is on it, so a long list can be
/// reached without a model call.
async function scrollToText(screen: any, text: string) {
  for (let i = 0; i < 10; i++) {
    if (await screen.getByText(text).first().isVisible()) return;
    await screen.swipe({ from: { x: 215, y: 700 }, to: { x: 215, y: 300 }, duration: 500 });
  }
  throw new Error(`could not scroll to ${text}`);
}

test('the structured answer example renders the comparison table and Row', async ({ app, device, screen }) => {
  await launchMemora(app, device, screen);
  await screen.getByLabel('メニュー').tap();
  await screen.getByText('設定').tap();
  await scrollToText(screen, '状態と復旧UIを確認');
  await tapControl(screen, screen.getByRole('button', { name: '状態と復旧UIを確認', exact: true }));
  await screen.getByText('構造化回答（表示の確認）').tap();
  await expect(screen.getByText('選択肢の比較')).toBeVisible();
  await expect(screen.getByText('候補').first()).toBeVisible();
  await scrollToText(screen, '午前の件数');
  await expect(screen.getByText('午後の件数')).toBeVisible();
});

test('the structured answer example replays its streaming state', async ({ app, device, screen }) => {
  await launchMemora(app, device, screen);
  await screen.getByLabel('メニュー').tap();
  await screen.getByText('設定').tap();
  await scrollToText(screen, '状態と復旧UIを確認');
  await tapControl(screen, screen.getByRole('button', { name: '状態と復旧UIを確認', exact: true }));
  await screen.getByText('構造化回答（表示の確認）').tap();
  await screen.getByText('ストリーミングを確認').tap();
  await expect(screen.getByText('表示を停止')).toBeVisible();
});

test('the source list and progress fixture renders', async ({ app, device, screen }) => {
  await launchMemora(app, device, screen);
  await screen.getByLabel('メニュー').tap();
  await screen.getByText('設定').tap();
  await scrollToText(screen, '状態と復旧UIを確認');
  await tapControl(screen, screen.getByRole('button', { name: '状態と復旧UIを確認', exact: true }));
  await scrollToText(screen, '資料・進捗の表示確認');
  await tapControl(screen, screen.getByRole('button', { name: '資料・進捗の表示確認', exact: true }));
  await expect(screen.getByText('根拠一覧（通常）')).toBeVisible();
  await expect(screen.getByText('WeeklySync 定例（9/29）').first()).toBeVisible();
  await scrollToText(screen, '進捗（一部完了・内訳あり）');
  await expect(screen.getByText('4件中1件が完了')).toBeVisible();
});
