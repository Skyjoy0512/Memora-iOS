import { afterEach, test } from '@e2e-dev/mobile';
import { expect } from 'e2e';
import { focusComposer, launchMemora, tapControl, tapTab } from './ui-helpers';

afterEach(async ({ device }) => { await device.setAppearance('light'); });

async function dismissFromEmptyCanvas(screen: any) {
  // Tap the quiet gap above the new action suggestions, not an action row.
  await screen.tapAt({ x: 220, y: 130 });
  await expect(screen.getByRole('keyboard')).not.toBeVisible();
}

test('chat surface: capture composer and sidebar in both appearances', async ({ app, device, screen }) => {
  await launchMemora(app, device, screen);
  for (const appearance of ['light', 'dark'] as const) {
    await device.setAppearance(appearance);
    await tapTab(screen, 'Ask AI');
    await expect(screen.getByLabel('新しいチャット')).toBeDisabled();
    await app.screenshot(`chat-empty-${appearance}`);
    const input = await focusComposer(screen);
    const draft = '次の会議の準備を手伝ってください。\n決定事項と確認したい点を整理します。';
    await input.fill(draft);
    await expect(input).toHaveValue(draft);
    await expect(screen.getByRole('button', { name: '送信', exact: true })).toBeVisible();
    await app.screenshot(`chat-draft-${appearance}`);
    // Exercise the actual soft-keyboard path: bulk XCTest clearing can leave
    // a suffix behind when a large multiline native field reflows.
    const deleteKey = screen.getByRole('keyboard').getByTestId('delete');
    for (const character of Array.from(draft)) {
      await deleteKey.tap();
    }
    await expect(screen.getByRole('button', { name: '送信', exact: true })).not.toBeVisible();
    await expect(screen.getByRole('button', { name: '音声で入力', exact: true })).toBeVisible();
    await dismissFromEmptyCanvas(screen);
    await tapControl(screen, screen.getByLabel('メニュー'));
    await expect(screen.getByLabel('ワークスペース', { exact: true })).not.toBeVisible();
    await expect(screen.getByRole('button', { name: 'Memora Plus、プランと利用状況', exact: true })).toBeVisible();
    await app.screenshot(`chat-sidebar-${appearance}`);
    const settings = screen.getByRole('button', { name: '設定', exact: true }).last();
    await expect.poll(async () => {
      const box = await settings.boundingBox();
      return !!box && box.width >= 44 && box.height >= 44;
    }).toBe(true);
    const target = await settings.boundingBox();
    if (!target) throw new Error('settings has no frame');
    // Deliberately hit outside the 20pt glyph but inside its circular 44pt label.
    await screen.tapAt({ x: target.x + target.width / 2 + 16, y: target.y + target.height / 2 });
    await expect(screen.getByTestId('settings.profile').first()).toBeVisible();
    await tapControl(screen, screen.getByRole('button', { name: '閉じる', exact: true }));
  }
});

test('chat surface: stacked controls keep draft navigation available after dismissing the keyboard', async ({ app, device, screen }) => {
  await launchMemora(app, device, screen);
  await tapTab(screen, 'Ask AI');
  const input = screen.getByTestId('ai.composer.input');
  const attach = screen.getByLabel('添付を追加');
  await expect.poll(async () => {
    const field = await input.boundingBox();
    const control = await attach.boundingBox();
    return !!field && !!control && control.y >= field.y + field.height - 2;
  }).toBe(true);
  const focused = await focusComposer(screen);
  await focused.fill('画面を行き来しても残しておく相談の下書き');
  await dismissFromEmptyCanvas(screen);
  await expect(screen.getByLabel('メニュー').first()).toBeVisible();
  await app.screenshot('chat-draft-keyboard-dismissed');
  await tapTab(screen, 'ジャーナル');
  await tapTab(screen, 'Ask AI');
  await expect(input).toHaveValue('画面を行き来しても残しておく相談の下書き');
  await app.restart();
  await tapTab(screen, 'Ask AI');
  await expect(input).toHaveValue('画面を行き来しても残しておく相談の下書き');
});

test('chat surface: flat title menu keeps history and search reachable', async ({ app, device, screen }) => {
  await launchMemora(app, device, screen);
  await tapTab(screen, 'Ask AI');
  await tapControl(screen, screen.getByRole('button', { name: '履歴', exact: true }));
  await expect(screen.getByText('質問履歴', { exact: true }).first()).toBeVisible();
  await tapControl(screen, screen.getByRole('button', { name: '完了', exact: true }));
  await tapControl(screen, screen.getByLabel('Memora、検索'));
  await tapControl(screen, screen.getByRole('button', { name: '検索', exact: true }));
  await expect(screen.getByText('会話を検索', { exact: true })).toBeVisible();
  const search = screen.getByRole('textbox', { name: '会議、発言、決定、タスク', exact: true });
  await search.pressSequentially('NoMatch9');
  await expect(screen.getByRole('textbox', { visible: true }).first()).toHaveValue('NoMatch9');
  const ask = screen.getByRole('button', { name: '検索語をMemoraに聞く', exact: true });
  const empty = screen.getByText('見つかりませんでした', { exact: true });
  await expect(empty).toBeVisible();
  await expect(ask).toBeVisible();
  const askFrame = await ask.boundingBox();
  const emptyFrame = await empty.boundingBox();
  if (!askFrame || !emptyFrame) throw new Error('Search actions have no frames');
  expect(askFrame.y + askFrame.height).toBeLessThanOrEqual(emptyFrame.y);
  const closeSearch = screen.getByRole('button', { name: 'close', exact: true });
  if (await closeSearch.isVisible()) await tapControl(closeSearch);
  await tapControl(screen, screen.getByRole('button', { name: '完了', exact: true }));
  await expect(screen.getByLabel('新しいチャット')).toBeVisible();
});
