import { randomUUID } from 'node:crypto';
import { test } from '@e2e-dev/mobile';
import { expect } from 'e2e';
import { launchMemora, selectLibrarySection, tapControl, tapTab } from './ui-helpers';

// Uses the on-device model only. No provider key or network request is made.
// If the model cannot run, the app must say so instead of inventing an answer.
test('a saved note is answered from its text with an openable citation and survives restart', { timeout: 300_000 }, async ({ app, device, screen }) => {
  await launchMemora(app, device, screen);
  const marker = 'SourceAsk-' + randomUUID().slice(0, 8);
  const title = '予算メモ ' + marker;
  const bodyText = 'この会議の予算は1200万円、担当は佐藤、期限は12月20日です。';
  async function openReferences() {
      await tapControl(screen.getByRole('button', { name: '参考資料', exact: true }).last());
  }
  await selectLibrarySection(screen, 'プロジェクト');
  await tapControl(screen.getByRole('button', { name: 'プロジェクトを作成', exact: true }).first());
  await screen.getByPlaceholder('例：新規アプリ').fill(marker);
  await tapControl(screen.getByRole('button', { name: '作成', exact: true }));
  await openReferences();
  await tapControl(screen.getByRole('button', { name: '参考資料を追加', exact: true }).first());
  const titleField = screen.getByRole('textbox', { name: 'タイトル', exact: true });
  await titleField.fill(title);
  const closeKeyboard = screen.getByRole('button', { name: 'キーボードを閉じる', exact: true });
  if (await closeKeyboard.isVisible()) await tapControl(closeKeyboard);
  await expect(screen.getByRole('keyboard')).not.toBeVisible();
  const body = screen.getByRole('textbox', { name: 'ノート本文', exact: true });
  await tapControl(screen, body);
  await expect(body).toBeFocused();
  await body.pressSequentially(bodyText);
  if (await closeKeyboard.isVisible()) await tapControl(closeKeyboard);
  await expect(screen.getByRole('keyboard')).not.toBeVisible();
  await tapControl(screen.getByRole('button', { name: '保存', exact: true }));
  await expect(screen.getByRole('button', { name: new RegExp('^' + title + '、メモ') }).first()).toBeVisible({ timeout: 60_000 });
  await tapControl(screen.getByRole('button', { name: new RegExp('^' + title + '、メモ') }).first());
  await expect(screen.getByText(bodyText, { exact: true })).toBeVisible({ timeout: 60_000 });
  let sheetOpen = false;
  for (let attempt = 0; attempt < 3 && !sheetOpen; attempt++) {
    await tapControl(screen.getByTestId('source.askAI'));
    try {
      await expect(screen.getByText('この資料について質問', { exact: true }).first()).toBeVisible({ timeout: 3_000 });
      sheetOpen = true;
    } catch {}
  }
  expect(sheetOpen).toBe(true);
  const composer = screen.getByTestId('ai.composer.input');
  await tapControl(screen, composer);
  await expect(composer).toBeFocused();
  await composer.pressSequentially('予算はいくらですか？');
  await expect(composer).toHaveValue('予算はいくらですか？');
  await tapControl(screen.getByRole('button', { name: '送信', exact: true }));
  // On-device generation can take a while; the answer must be grounded in the
  // note, not a generic reply.
  await expect(screen.getByText(/1,?200/).first()).toBeVisible({ timeout: 120_000 });
  const citation = screen.getByRole('button', { name: new RegExp('^' + title) }).last();
  await expect(citation).toBeVisible({ timeout: 30_000 });
  await app.screenshot('source-ask-ai-answer');
  await tapControl(citation);
  await expect(screen.getByText(bodyText, { exact: true })).toBeVisible({ timeout: 30_000 });
  await app.screenshot('source-ask-ai-citation');
  await app.restart();
  await tapTab(screen, 'ライブラリ');
  await selectLibrarySection(screen, 'プロジェクト');
  await tapControl(screen.getByText(marker, { exact: true }).first());
  await openReferences();
  await tapControl(screen.getByRole('button', { name: new RegExp('^' + title + '、メモ') }).first());
  const restoredBody = screen.getByText(bodyText, { exact: true });
  if (!(await restoredBody.isVisible())) await tapControl(screen.getByLabel('原文').first());
  await expect(restoredBody).toBeVisible({ timeout: 60_000 });
  await app.screenshot('source-ask-ai-restored');
});
