import { test } from '@e2e-dev/mobile';
import { expect } from 'e2e';
import { focusComposer, launchMemora, scrollToControl, tapControl, tapTab } from './ui-helpers';

test('minimal polish: sidebar switching keeps the conversation and settles on one canvas', async ({ app, device, screen }) => {
  await launchMemora(app, device, screen);
  await tapTab(screen, 'Ask AI');
  const input = await focusComposer(screen);
  const draft = 'Keep this draft while switching between Tools and the other destinations';
  await input.fill(draft);
  await screen.tapAt({ x: 220, y: 260 });
  await expect(screen.getByRole('keyboard')).not.toBeVisible();
  for (const destination of ['ツール', 'ライブラリ', 'ジャーナル', 'ツール', 'Ask AI']) {
    await tapTab(screen, destination);
    await expect.poll(async () => {
      const box = await screen.getByLabel('メニュー').first().boundingBox();
      return !!box && box.width >= 20;
    }).toBe(true);
    if (destination === 'ツール') {
      await expect(screen.getByTestId('ai.composer.input')).not.toBeVisible();
    }
  }
  await expect(input).toHaveValue(draft);
  await expect(screen.getByRole('keyboard')).not.toBeVisible();
  await app.screenshot('sidebar-switch-draft-retained');
});

test('minimal polish: Tools menus, article actions and connectors stay usable', async ({ app, device, screen }) => {
  await launchMemora(app, device, screen);
  await tapTab(screen, 'ツール');
  const add = screen.getByLabel('マーケットプレイスの操作');
  await tapControl(screen, add);
  await tapControl(screen, screen.getByRole('button', { name: 'スキルを作成', exact: true }));
  await expect(screen.getByPlaceholder('スキル名')).toBeVisible();
  await tapControl(screen, screen.getByRole('button', { name: 'キャンセル', exact: true }));
  await expect(add).toBeVisible();
  const search = screen.getByTestId('collection.search.input');
  await search.fill('プロジェクトの要点整理');
  await search.press('Enter');
  const article = screen.getByRole('button', { name: /プロジェクトの要点整理/ }).first();
  await expect(article).toBeVisible();
  await tapControl(screen, article);
  await expect(screen.getByText('詳しい手順', { exact: true })).toBeVisible();
  const use = screen.getByRole('button', { name: 'チャットで使用', exact: true });
  const box = await use.boundingBox();
  expect(box?.height).toBeGreaterThanOrEqual(44);
  expect(box?.height).toBeLessThanOrEqual(60);
  await app.screenshot('minimal-skill-article');
  await tapControl(screen, screen.getByLabel('スキルの操作'));
  await expect(screen.getByRole('button', { name: 'Markdownを共有', exact: true })).toBeVisible();
  await screen.tapAt({ x: 160, y: 200 });
  await tapControl(screen, screen.getByRole('button', { name: '閉じる', exact: true }));
  await tapControl(screen.getByTestId('collection.search.cancel'));
  await tapControl(screen, screen.getByRole('button', { name: 'コネクタ', exact: true }));
  await app.screenshot('minimal-connectors');
  await tapControl(screen, screen.getByRole('button', { name: 'Gmailを追加・接続', exact: true }));
  await tapControl(screen, screen.getByText('アクセスと利用設定', { exact: true }).first());
  await expect(screen.getByText('読み取り専用。取得した内容は選択中のAIに渡されます。', { exact: true })).toBeVisible();
});
