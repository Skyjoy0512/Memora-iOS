import { test } from '@e2e-dev/mobile';
import { expect } from 'e2e';

// No model calls: these only launch the app and check what is on screen.
test('the app opens on the journal', async ({ app, device, screen }) => {
  await device.installApp();
  await app.open();
  await expect(screen.getByText('今日のタスク')).toBeVisible();
});

test('the side menu opens Settings', async ({ app, device, screen }) => {
  await device.installApp();
  await app.open();
  await screen.getByLabel('メニュー').tap();
  await expect(screen.getByText('個人')).toBeVisible();
});

// Model-backed: the agent navigates to the structured-answer example and the
// assertion checks the comparison table it renders.
test('the agent opens the structured answer example', async ({ agent, app, device, screen }) => {
  await device.installApp();
  await app.open();
  await agent.act('open the side menu and open Settings');
  await agent.act('scroll to the プロトタイプ section and open 状態と復旧UIを確認');
  await agent.act('open 構造化回答（表示の確認）');
  await agent.assert('a comparison table with the columns 候補, 移動, 過ごし方 is showing');
});

test('the agent opens the source list and progress fixture', async ({ agent, app, device, screen }) => {
  await device.installApp();
  await app.open();
  await agent.act('open the side menu and open Settings');
  await agent.act('scroll to the プロトタイプ section and open 状態と復旧UIを確認');
  await agent.act('open 資料・進捗の表示確認');
  await agent.assert('a source list shows 会議・引用 metadata and a task progress bar with 4件中1件が完了 is showing');
});
