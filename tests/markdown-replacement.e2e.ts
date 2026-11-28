import { afterEach, test } from '@e2e-dev/mobile';
import { expect } from 'e2e';
import { seedSummaryFixture } from './summary-fixture-helpers';
import { replaceEditorWithPaste, restartToLibrary, selectAllEditorText, scrollToControl, tapControl, tapTab } from './ui-helpers';
import { readMeetings, sql } from './sqlite-fixture-helpers';

afterEach(async ({ device }) => { await device.setAppearance('light'); });

// Deterministic replacement via the UI driver. This does not simulate a real
// Japanese keyboard's marked-text composition or conversion candidate window.
test('Japanese replacement, Unicode paste and navigation keep exact committed text', { timeout: 240_000 }, async ({ app, device, screen }) => {
  const { database, title, raw } = await seedSummaryFixture(app, device, screen);
  const original = '予算は10万円ではなく12万円。承認された場合だけ来週実施する。';
  const paragraph = screen.getByRole('button', { name: original, exact: true });
  await scrollToControl(screen, paragraph);
  await tapControl(paragraph);
  const editor = screen.getByRole('textbox', { name: '本文', exact: true });
  await expect(editor).toHaveValue(original);
  for (const value of ['日本語の置換を確認します。', '確定後の編集。👨‍👩‍👧‍👦・😀・e\u0301',
    Array.from({ length: 12 }, (_, index) => `第${index + 1}段落：原文を保持し、承認前には公開しない。`).join('\n')]) {
    await replaceEditorWithPaste(screen, device, editor, value);
    await expect(editor).toHaveValue(value);
  }
  const final = '最終版：古い文字を残さない。👨‍👩‍👧‍👦 e\u0301';
  await replaceEditorWithPaste(screen, device, editor, final);
  await expect(editor).toHaveValue(final);
  await app.screenshot('replacement-before-navigation-light');
  await tapControl(screen.getByTestId('BackButton'));
  const records = () => readMeetings(database)!;
  await expect.poll(() => records()[0].summary.includes(final)).toBe(true);
  expect(records()[0].summary.includes(original)).toBe(false);
  expect(records()[0].summary.includes('第1段落')).toBe(false);
  expect(records()[0].transcript[0].text).toBe(raw);
  expect(records()[0].summary.includes('| 予算案を確認 | 承認が前提 | 佐藤 | 来週 |')).toBe(true);
  await restartToLibrary(app, screen);
  await tapControl(screen.getByRole('button', { name: new RegExp('^' + title) }).first());
  const restored = screen.getByRole('button', { name: final, exact: true });
  await scrollToControl(screen, restored);
  await tapControl(restored);
  await expect(editor).toHaveValue(final);
  await tapControl(screen.getByRole('button', { name: '太字', exact: true }));
  await tapControl(screen.getByRole('button', { name: '斜体', exact: true }));
  await expect(editor).toHaveValue(final);
  await tapControl(screen.getByRole('button', { name: '完了', exact: true }));
  await device.setAppearance('dark');
  await scrollToControl(screen, restored);
  await expect(restored).toBeVisible();
  await app.screenshot('replacement-restored-dark');
  expect(records()[0].summary.includes(final)).toBe(true);
  expect(records()[0].transcript[0].text).toBe(raw);
});

test('formatting, list and table edits change only their own source lines', { timeout: 300_000 }, async ({ app, device, screen }) => {
  const { database, title, summary, raw } = await seedSummaryFixture(app, device, screen);
  const original = '予算は10万円ではなく12万円。承認された場合だけ来週実施する。';
  const paragraph = screen.getByRole('button', { name: original, exact: true });
  const editor = screen.getByRole('textbox', { name: '本文', exact: true });
  const records = () => readMeetings(database)!;
  const finish = () => tapControl(screen.getByRole('button', { name: '完了', exact: true }));
  await scrollToControl(screen, paragraph);
  await tapControl(paragraph);
  await expect(editor).toHaveValue(original);
  await selectAllEditorText(screen, editor);
  await tapControl(screen.getByRole('button', { name: '太字', exact: true }));
  await tapControl(screen.getByRole('button', { name: '斜体', exact: true }));
  await expect(editor).toHaveValue(original);
  await finish();
  let expected = summary.replace(original, `***${original}***`);
  await expect.poll(() => records()[0].summary).toBe(expected);

  const item = screen.getByRole('button', { name: '検証環境で比較する', exact: true });
  await scrollToControl(screen, item);
  await tapControl(item);
  await replaceEditorWithPaste(screen, device, editor, '検証環境のみで比較する');
  await finish();
  expected = expected.replace('検証環境で比較する', '検証環境のみで比較する');
  await expect.poll(() => records()[0].summary).toBe(expected);

  const cell = screen.getByRole('button', { name: '承認が前提', exact: true });
  await scrollToControl(screen, cell);
  await tapControl(cell);
  await replaceEditorWithPaste(screen, device, editor, '条件付き承認：公開前に再確認');
  await finish();
  expected = expected.replace('承認が前提', '条件付き承認：公開前に再確認');
  await expect.poll(() => records()[0].summary).toBe(expected);
  expect(records()[0].transcript[0].text).toBe(raw);
  await restartToLibrary(app, screen);
  await tapControl(screen.getByRole('button', { name: new RegExp('^' + title) }).first());
  const restored = screen.getByRole('button', { name: '条件付き承認：公開前に再確認', exact: true });
  await scrollToControl(screen, restored);
  await expect(restored).toBeVisible();
  expect(records()[0].summary).toBe(expected);
  await app.screenshot('formatted-list-table-restored');
});
