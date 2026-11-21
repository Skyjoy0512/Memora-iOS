import { test } from '@e2e-dev/mobile';
import { expect } from 'e2e';
import { launchMemora, openSidebarSearch, tapControl, tapTab } from './ui-helpers';

/// Wait for the shared native-frame readiness gate before touching a control.
async function tapStable(locator: any) {
  await tapControl(locator);
}

/// Adds one memo from the journal's add sheet.
async function addMemo(screen: any, title: string) {
  const create = screen.getByLabel('記録を追加').first();
  await scrollTo(screen, create);
  await tapStable(create);
  // An empty day opens the sheet directly; an existing timeline opens a menu.
  const memo = screen.getByRole('button', { name: 'メモを追加', exact: true });
  try { await expect(memo).toBeVisible({ timeout: 1_500 }); await tapStable(memo); } catch {}
  await expect(screen.getByText('ライフログを追加', { exact: true })).toBeVisible();
  await screen.getByPlaceholder('メモのタイトル').fill(title);
  const add = screen.getByRole('button', { name: '追加' });
  await expect(add).toBeEnabled();
  await tapStable(add);
  await expect(screen.getByText('ライフログを追加', { exact: true })).not.toBeVisible();
  await expect(screen.getByRole('keyboard')).not.toBeVisible();
  await expect(screen.getByText(title).first()).toBeVisible({ timeout: 30_000 });
}

/// Taps an add control again if the first touch landed while the previous
/// sheet was still dismissing, then waits for the add sheet.
async function openAddSheet(screen: any, locator: any) {
  await tapStable(locator);
  await tapStable(screen.getByRole('button', { name: 'メモを追加', exact: true }));
  await expect(screen.getByText('ライフログを追加')).toBeVisible({ timeout: 8000 });
}

/// Creates a fresh project and lands on its workspace.
async function createProject(screen: any, device: any) {
  await tapTab(screen, 'ライブラリ');
  const back = screen.getByTestId('BackButton');
  if (await back.isVisible()) await tapControl(screen, back);
  await tapControl(screen, screen.getByRole('button', { name: 'プロジェクト', exact: true }));
  await tapStable(screen.getByRole('button', { name: 'プロジェクトを作成' }).first());
  await screen.getByPlaceholder('例：新規アプリ').fill('E2E Workspace');
  await tapStable(screen.getByRole('button', { name: '作成' }));
  await expect(screen.getByLabel(/表示切り替え$/).first()).toBeVisible();
}

/// The workspace switcher is a native menu, not inline tabs.
async function selectWorkspaceTab(screen: any, title: string) {
  await tapControl(screen, screen.getByLabel(/表示切り替え$/).first());
  await tapControl(screen, screen.getByRole('button', { name: title, exact: true }).last());
  await expect(screen.getByLabel(new RegExp(title + '、表示切り替え$'))).toBeVisible();
}

/// Searches both scroll directions so large text and restored offsets work.
async function scrollTo(screen: any, locator: any) {
  for (const towardBottom of [true, false]) {
    for (let i = 0; i < 12; i++) {
      if (await locator.isVisible()) {
        const box = await locator.boundingBox();
        const composer = screen.getByTestId('ai.composer.input');
        const isForm = await screen.getByText('ライフログを追加', { exact: true }).isVisible();
        const composerBox = !isForm && await composer.isVisible() ? await composer.boundingBox() : null;
        // Native AX visibility includes rows underneath the floating composer.
        // A real touch must be above it and below the navigation bar.
        const bottom = composerBox ? composerBox.y - 24 : Number.POSITIVE_INFINITY;
        if (box && box.y >= 140 && box.y + box.height <= bottom) return;
        if (box && box.y < 140 && towardBottom) break;
      }
      await screen.swipe({ from: { x: 215, y: towardBottom ? 700 : 300 }, to: { x: 215, y: towardBottom ? 300 : 700 }, duration: 500 });
    }
  }
  throw new Error('could not scroll to the target');
}

test('the workspace tabs switch between chat, records and references', async ({ app, device, screen }) => {
  await launchMemora(app, device, screen);
  await createProject(screen, device);

  await expect(screen.getByText('チャットを始める', { exact: true })).toBeVisible();
  await selectWorkspaceTab(screen, '記録');
  await expect(screen.getByRole('button', { name: '録音を追加', exact: true }).first()).toBeVisible();
  await app.screenshot('workspace-empty-files');
  await selectWorkspaceTab(screen, '参考資料');
  await expect(screen.getByRole('button', { name: '参考資料を追加', exact: true }).first()).toBeVisible();
  await app.screenshot('workspace-empty-sources');
  await selectWorkspaceTab(screen, 'チャット');
  await expect(screen.getByRole('button', { name: '新しいチャット', exact: true }).first()).toBeVisible();
});

test('the week strip selects a day and updates the timeline', async ({ app, device, screen }) => {
  await launchMemora(app, device, screen);
  await tapTab(screen, 'ジャーナル');

  const title = `E2E day ${Date.now()}`;
  await addMemo(screen, title);

  const yesterday = new Date();
  yesterday.setDate(yesterday.getDate() - 1);
  const yesterdayName = `^${yesterday.getFullYear()}/${yesterday.getMonth() + 1}/${yesterday.getDate()}[日月火水木金土]曜日、`;
  await tapStable(screen.getByRole('button', { name: new RegExp(yesterdayName) }));

  await expect(screen.getByRole('button', { name: new RegExp(yesterdayName), selected: true })).toBeVisible();
  await expect(screen.getByText(title)).not.toBeVisible();

  const today = new Date();
  const todayName = `^${today.getFullYear()}/${today.getMonth() + 1}/${today.getDate()}[日月火水木金土]曜日、`;
  await tapStable(screen.getByRole('button', { name: new RegExp(todayName) }));
  const record = screen.getByText(title).first();
  await scrollTo(screen, record);
  await expect(record).toBeVisible();
});

test('the inline plus buttons add a record', async ({ app, device, screen }) => {
  await launchMemora(app, device, screen);
  await tapTab(screen, 'ジャーナル');

  await screen.getByText('記録を追加').first().tap();
  await screen.getByPlaceholder('メモのタイトル').fill('E2E inline');
  const add = screen.getByRole('button', { name: '追加' });
  await expect(add).toBeEnabled();
  await tapStable(add);

  const between = screen.getByLabel('この間に記録を追加').first();
  await scrollTo(screen, between);
  await openAddSheet(screen, between);
  await screen.getByText('キャンセル').tap();

  const end = screen.getByRole('pop-up-button', { name: '記録を追加' }).last();
  await scrollTo(screen, end);
  await openAddSheet(screen, end);
  await screen.getByText('キャンセル').tap();
});

test('journal insertion proposes the selected day and the time between events', { timeout: 180_000 }, async ({ app, device, screen }) => {
  await launchMemora(app, device, screen);
  await tapTab(screen, 'ジャーナル');
  const day = new Date();
  day.setDate(day.getDate() - 1);
  const dayName = new RegExp(`^${day.getFullYear()}/${day.getMonth() + 1}/${day.getDate()}[日月火水木金土]曜日、`);
  const value = (time: string) => new RegExp(`^${time}, ${day.getFullYear()}/0?${day.getMonth() + 1}/0?${day.getDate()}$`);
  await tapStable(screen.getByRole('button', { name: dayName }));
  await addMemo(screen, 'Insertion 09:00');
  const tail = screen.getByRole('pop-up-button', { name: '記録を追加', exact: true }).last();
  await scrollTo(screen, tail);
  await openAddSheet(screen, tail);
  const recordedPicker = screen.getByRole('listitem').filter({ hasText: '記録した時刻' }).getByRole('button', { name: 'Date and Time Picker', exact: true });
  const eventPicker = screen.getByRole('listitem').filter({ hasText: '開始' }).getByRole('button', { name: 'Date and Time Picker', exact: true });
  const eventKind = screen.getByRole('button', { name: 'イベント', exact: true });
  await scrollTo(screen, recordedPicker);
  await expect(recordedPicker).toHaveValue(value('0?9:30'));
  await scrollTo(screen, eventKind);
  await tapStable(eventKind);
  await scrollTo(screen, eventPicker);
  await expect(eventPicker).toHaveValue(value('0?9:30'));
  await scrollTo(screen, screen.getByPlaceholder('イベント名'));
  await screen.getByPlaceholder('イベント名').fill('Insertion 09:30');
  await tapStable(screen.getByRole('button', { name: '追加', exact: true }));
  const middle = screen.getByRole('pop-up-button', { name: 'この間に記録を追加', exact: true }).first();
  await scrollTo(screen, middle);
  // Inspect the button, not its same-labelled child Text (14pt at normal size).
  // Keep the 44pt contract while the native sheet finishes dismissing.
  await expect.poll(async () => {
    const box = await middle.boundingBox();
    return !!box && box.width >= 44 && box.height >= 44;
  }).toBe(true);
  const middleBox = await middle.boundingBox();
  if (!middleBox) throw new Error('journal insertion has no frame');
  expect(middleBox.width).toBeGreaterThanOrEqual(44);
  expect(middleBox.height).toBeGreaterThanOrEqual(44);
  await openAddSheet(screen, middle);
  await scrollTo(screen, recordedPicker);
  await expect(recordedPicker).toHaveValue(value('0?9:15'));
  await scrollTo(screen, eventKind);
  await tapStable(eventKind);
  await scrollTo(screen, eventPicker);
  await expect(eventPicker).toHaveValue(value('0?9:15'));
  await app.screenshot('journal-proposed-between-events');
  await scrollTo(screen, screen.getByPlaceholder('イベント名'));
  await screen.getByPlaceholder('イベント名').fill('Insertion 09:15');
  await tapStable(screen.getByRole('button', { name: '追加', exact: true }));
  await scrollTo(screen, screen.getByRole('button', { name: dayName, selected: true }));
  await expect(screen.getByRole('button', { name: dayName, selected: true })).toBeVisible();
  await app.restart();
  await tapTab(screen, 'ジャーナル');
  await tapStable(screen.getByRole('button', { name: dayName }));
  const restored = screen.getByText('Insertion 09:15', { exact: true }).first();
  await scrollTo(screen, restored);
  await expect(restored).toBeVisible();
  await app.screenshot('journal-inserted-event-restored');
});

test('journal editing and confirmed deletion persist after restart', { timeout: 180_000 }, async ({ app, device, screen }) => {
  await launchMemora(app, device, screen);
  await tapTab(screen, 'ジャーナル');
  await addMemo(screen, 'Journal CRUD');
  await openSidebarSearch(screen);
  await screen.getByPlaceholder('ジャーナルを検索').fill('Journal CRUD');
  await tapStable(screen.getByText('Journal CRUD', { exact: true }).first());
  await tapStable(screen.getByLabel('その他'));
  await tapStable(screen.getByText('編集', { exact: true }));
  await screen.getByRole('textbox').first().fill('Journal CRUD edited');
  await screen.getByPlaceholder('本文').fill('Edited journal detail');
  await tapStable(screen.getByRole('button', { name: '保存', exact: true }));
  await expect(screen.getByText('Edited journal detail', { exact: true }).last()).toBeVisible();
  await app.restart();
  await tapTab(screen, 'ジャーナル');
  await openSidebarSearch(screen);
  await screen.getByPlaceholder('ジャーナルを検索').fill('Journal CRUD edited');
  await tapStable(screen.getByText('Journal CRUD edited', { exact: true }).first());
  await expect(screen.getByText('Edited journal detail', { exact: true }).last()).toBeVisible();
  await tapStable(screen.getByLabel('その他'));
  await tapStable(screen.getByRole('button', { name: '削除', exact: true }));
  const confirmation = screen.getByRole('group', { name: 'この記録を削除しますか？', exact: true });
  await expect(confirmation).toBeVisible();
  // A compact confirmation popover cancels through its outside dismiss region,
  // not the covered search toolbar's unrelated Cancel button.
  const confirmationBox = await confirmation.boundingBox();
  if (!confirmationBox) throw new Error('delete confirmation has no frame');
  await screen.tapAt({ x: 20, y: confirmationBox.y - 20 });
  await expect(confirmation).not.toBeVisible();
  await expect(screen.getByText('Edited journal detail', { exact: true }).last()).toBeVisible();
  await tapStable(screen.getByLabel('その他'));
  await tapStable(screen.getByRole('button', { name: '削除', exact: true }));
  await expect(confirmation).toBeVisible();
  await tapStable(screen.getByRole('button', { name: '削除', exact: true }));
  await expect(screen.getByText('見つかりませんでした', { exact: true })).toBeVisible();
  await app.restart();
  await tapTab(screen, 'ジャーナル');
  await openSidebarSearch(screen);
  await screen.getByPlaceholder('ジャーナルを検索').fill('Journal CRUD edited');
  await expect(screen.getByText('見つかりませんでした', { exact: true })).toBeVisible();
  await app.screenshot('journal-confirmed-delete-restored');
});

test('journal search replaces the recap and restores the timeline without losing records', async ({ app, device, screen }) => {
  await launchMemora(app, device, screen);
  await tapTab(screen, 'ジャーナル');
  await addMemo(screen, 'JournalSearchEvidence');
  await openSidebarSearch(screen);
  const query = screen.getByRole('textbox').first();
  await query.fill('JournalSearchEvidence');
  await expect(screen.getByText('JournalSearchEvidence', { exact: true }).first()).toBeVisible();
  await expect(screen.getByRole('button', { name: '今日に戻る', exact: true })).not.toBeVisible();
  await expect(screen.getByTestId('ai.composer.input')).not.toBeVisible();
  await app.screenshot('journal-search-results');
  await query.fill('NoJournalSearchMatch');
  await expect(screen.getByText('見つかりませんでした', { exact: true })).toBeVisible();
  await tapControl(screen.getByRole('button', { name: '検索語を消去', exact: true }));
  await expect(query).not.toHaveValue('NoJournalSearchMatch');
  await expect(screen.getByText('記録を検索', { exact: true })).toBeVisible();
  await tapControl(screen.getByRole('button', { name: 'キャンセル', exact: true }));
  await expect(screen.getByRole('button', { name: '今日に戻る', exact: true })).toBeVisible();
  const restored = screen.getByText('JournalSearchEvidence', { exact: true }).first();
  await scrollTo(screen, restored);
  await expect(restored).toBeVisible();
  await app.screenshot('journal-search-returned-timeline');
});

test('the journal and workspace stay legible in dark appearance', async ({ app, device, screen }) => {
  await launchMemora(app, device, screen);
  await tapTab(screen, 'ジャーナル');
  await device.setAppearance('dark');
  try {
    await expect(screen.getByText('今日の記録はありません')).toBeVisible();
    await app.screenshot('journal-dark');
    await createProject(screen, device);
    await selectWorkspaceTab(screen, '記録');
    await expect(screen.getByRole('button', { name: '録音を追加', exact: true }).first()).toBeVisible();
    await app.screenshot('workspace-empty-files-dark');
    await selectWorkspaceTab(screen, '参考資料');
    await expect(screen.getByRole('button', { name: '参考資料を追加', exact: true }).first()).toBeVisible();
    await app.screenshot('workspace-empty-sources-dark');
  } finally {
    await device.setAppearance('light');
  }
});

test('editing a record saves it to the new date', async ({ app, device, screen }) => {
  await launchMemora(app, device, screen);
  await tapTab(screen, 'ジャーナル');
  const title = `E2E edit ${Date.now()}`;
  await addMemo(screen, title);

  await openSidebarSearch(screen);
  await screen.getByPlaceholder('ジャーナルを検索').fill(title);
  const preview = screen.getByText(title).first();
  await expect(preview).toBeVisible();
  await tapStable(preview);
  await expect(screen.getByLabel('その他')).toBeVisible();

  await tapStable(screen.getByLabel('その他'));
  await tapStable(screen.getByText('編集'));

  await tapStable(screen.getByRole('button', { name: 'Sheet Grabber' }));
  const today = new Date();
  const todayLabel = `${today.getFullYear()}/${String(today.getMonth() + 1).padStart(2, '0')}/${String(today.getDate()).padStart(2, '0')}`;
  await tapStable(screen.getByRole('button', { name: todayLabel }));

  const target = new Date();
  target.setDate(target.getDate() - 1);
  if (target.getMonth() !== today.getMonth()) target.setDate(today.getDate() + 1);
  const targetName = `(?:${target.toLocaleString('en-US', { month: 'long' })} ${target.getDate()}|${target.getMonth() + 1}月${target.getDate()}日)`;
  await tapStable(screen.getByRole('listitem', { name: new RegExp(targetName) }));
  // The compact system picker remains open after a date selection. Dismiss it
  // explicitly; a touch on Save while it is open only closes the popover.
  await tapStable(screen.getByText('記録を編集', { exact: true }));
  await expect(screen.getByRole('listitem', { name: new RegExp(targetName) })).not.toBeVisible();
  await tapStable(screen.getByRole('button', { name: '保存' }));
  const targetLabel = `${target.getMonth() + 1}月${target.getDate()}日`;
  await expect(screen.getByText(new RegExp(targetLabel)).first()).toBeVisible();
});

test('a source added in the workspace stays in the references tab', async ({ app, device, screen }) => {
  await launchMemora(app, device, screen);
  await createProject(screen, device);

  await selectWorkspaceTab(screen, '参考資料');
  await tapStable(screen.getByRole('button', { name: '参考資料を追加', exact: true }).first());
  const title = 'E2E source ' + Date.now();
  await screen.getByRole('textbox', { name: 'タイトル', exact: true }).fill(title);
  const body = screen.getByRole('textbox', { name: 'ノート本文', exact: true });
  await tapControl(screen, body);
  await body.pressSequentially('端末内にだけ保存する参考資料の本文です。');
  const closeKeyboard = screen.getByRole('button', { name: 'キーボードを閉じる', exact: true });
  if (await closeKeyboard.isVisible()) await tapControl(screen, closeKeyboard);
  await tapStable(screen.getByRole('button', { name: '保存', exact: true }));
  await expect(screen.getByText(title).first()).toBeVisible({ timeout: 60_000 });

  await selectWorkspaceTab(screen, 'チャット');
  await selectWorkspaceTab(screen, '参考資料');
  await expect(screen.getByText(title).first()).toBeVisible();
});

test('the project list filters all, mine and shared', async ({ app, device, screen }) => {
  await launchMemora(app, device, screen);
  await tapTab(screen, 'ライブラリ');
  await tapControl(screen, screen.getByRole('button', { name: 'プロジェクト', exact: true }));

  await tapControl(screen.getByRole('button', { name: 'プロジェクトを検索', exact: true }));
  await expect(screen.getByTestId('collection.search.input')).toBeFocused();
  await tapControl(screen.getByTestId('collection.search.cancel'));

  const options = screen.getByLabel('プロジェクトの表示オプション');
  await tapControl(screen, options);
  await tapControl(screen, screen.getByRole('button', { name: '自分', exact: true }).last());
  await tapControl(screen, options);
  await tapControl(screen, screen.getByRole('button', { name: '共有', exact: true }).last());
  await expect(screen.getByText('共有されたプロジェクトはありません')).toBeVisible();
  await tapControl(screen, options);
  await tapControl(screen, screen.getByRole('button', { name: 'すべて', exact: true }).last());
  await expect(screen.getByRole('button', { name: 'プロジェクトを作成' }).first()).toBeVisible();
});

test('the records tab offers recording and moving existing files', async ({ app, device, screen }) => {
  await launchMemora(app, device, screen);
  await createProject(screen, device);

  await selectWorkspaceTab(screen, '記録');
  await expect(screen.getByRole('button', { name: '録音を追加', exact: true }).first()).toBeVisible();
  await tapControl(screen, screen.getByRole('button', { name: 'その他', exact: true }));
  await tapControl(screen, screen.getByRole('button', { name: '既存記録を移動', exact: true }));
  await expect(screen.getByText('既存ファイルを移動', { exact: true }).first()).toBeVisible();
  await tapControl(screen, screen.getByRole('button', { name: 'キャンセル', exact: true }));
  await expect(screen.getByLabel(/記録、表示切り替え$/).first()).toBeVisible();
});
