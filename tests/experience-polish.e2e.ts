import { afterEach, test } from '@e2e-dev/mobile';
import { expect } from 'e2e';
import { focusComposer, launchMemora, openSidebarSearch, scrollToControl, tapControl, tapTab } from './ui-helpers';

afterEach(async ({ device }) => { await device.setAppearance('light'); });

async function journal(device: any, screen: any) {
  await device.openLink('memora://journal');
  const open = screen.getByRole('button', { name: '開く', exact: true });
  if (await open.isVisible()) await tapControl(screen, open);
  await expect(screen.getByLabel('メニュー')).toBeVisible();
}

async function expectTouchTarget(control: any) {
  // Onboarding and sheet transitions briefly scale native accessibility frames.
  // Measure their settled size without weakening the 44-point requirement.
  await expect.poll(async () => {
    const box = await control.boundingBox();
    return !!box && box.width >= 44 && box.height >= 44;
  }).toBe(true);
}

// The journal shows its dates in Japanese; a day row is named for the date.
function dayName(date: Date) {
  return new RegExp(`^${date.getFullYear()}/${date.getMonth() + 1}/${date.getDate()}[日月火水木金土]曜日`);
}

async function openTasks(screen: any) {
  await tapControl(screen, screen.getByLabel('メニュー').first());
  await tapControl(screen, screen.getByRole('button', { name: 'タスク', exact: true }).last());
  // The drawer keeps covering the list while it slides away; a tap there
  // dismisses it instead of reaching the screen.
  await expect(screen.getByTestId('sidebar.settings')).not.toBeVisible();
  await expect(screen.getByTestId('root.tab.home')).toBeSelected();
  await expect(screen.getByRole('button', { name: 'タスクを追加', exact: true }).last()).toBeVisible();
}

test('experience: journal, library and create menu remain coherent in both appearances', async ({ app, device, screen }) => {
  await launchMemora(app, device, screen);
  for (const appearance of ['light', 'dark'] as const) {
    await device.setAppearance(appearance);
    await journal(device, screen);
    await expect(screen.getByRole('button', { name: dayName(new Date()) }).first()).toBeVisible();
    await app.screenshot(`journal-${appearance}`);
    await tapTab(screen, 'ライブラリ');
    await device.openLink('memora://projects');
    await tapControl(screen, screen.getByRole('button', { name: 'ファイル', exact: true }).first());
    await expect(screen.getByRole('button', { name: '録音する', exact: true }).first()).toBeVisible();
    await app.screenshot(`library-${appearance}`);
    await tapControl(screen, screen.getByRole('button', { name: '追加メニュー', exact: true }));
    for (const title of ['録音する', '音声を取り込む', 'ノートを追加']) {
      await expect(screen.getByRole('button', { name: title, exact: true })).toBeVisible();
    }
    await app.screenshot(`create-menu-${appearance}`);
    await journal(device, screen);
  }
});

test('experience: empty task action creates a task, completes it and keeps it after restart', async ({ app, device, screen }) => {
  await launchMemora(app, device, screen);
  await openTasks(screen);
  const add = screen.getByRole('button', { name: 'タスクを追加', exact: true }).last();
  await tapControl(screen, add);
  await screen.getByPlaceholder('すること').fill('E2E 操作を磨き込む');
  await tapControl(screen, screen.getByRole('button', { name: '追加', exact: true }));
  await expect(screen.getByRole('button', { name: /^E2E 操作を磨き込む、/ })).toBeVisible();
  const complete = screen.getByRole('button', { name: /を完了にする$/ });
  await expectTouchTarget(complete);
  await app.screenshot('tasks-active');
  await tapControl(screen, complete);
  await tapControl(screen, screen.getByRole('button', { name: '完了', exact: true }));
  await expect(screen.getByRole('button', { name: /^E2E 操作を磨き込む、/ })).toBeVisible();
  await app.restart();
  await openTasks(screen);
  await tapControl(screen, screen.getByRole('button', { name: '完了', exact: true }));
  await expect(screen.getByRole('button', { name: /^E2E 操作を磨き込む、/ })).toBeVisible();
});

test('experience: search states clear their real query and hide the underlying project list', async ({ app, device, screen }) => {
  await launchMemora(app, device, screen);
  await openSidebarSearch(screen);
  const query = screen.getByRole('textbox').first();
  await query.fill('存在しない記録xyz');
  await tapControl(screen, screen.getByRole('button', { name: '検索をやり直す', exact: true }));
  await expect(query).not.toHaveValue('存在しない記録xyz');
  await expect(screen.getByText('記録や参考資料のタイトル・本文から探せます。', { exact: true })).toBeVisible();
  await tapControl(screen, screen.getByRole('button', { name: 'キャンセル', exact: true }));
  await device.openLink('memora://projects');
  await tapControl(screen, screen.getByRole('button', { name: 'プロジェクトを作成', exact: true }).first());
  await screen.getByPlaceholder('例：新規アプリ').fill('E2E Search Scope');
  await tapControl(screen, screen.getByRole('button', { name: '作成', exact: true }));
  await device.openLink('memora://projects');
  await expect(screen.getByText('E2E Search Scope')).toBeVisible();
  await openSidebarSearch(screen);
  await expect(screen.getByText('プロジェクト名や、共有した人の名前から探せます。', { exact: true })).toBeVisible();
  await expect(screen.getByText('E2E Search Scope')).not.toBeVisible();
  await query.fill('存在しないプロジェクトxyz');
  await expect(screen.getByText('見つかりませんでした')).toBeVisible();
  await app.screenshot('project-search-empty');
  await tapControl(screen, screen.getByRole('button', { name: '検索をやり直す', exact: true }));
  await expect(query).not.toHaveValue('存在しないプロジェクトxyz');
  await tapControl(screen, screen.getByRole('button', { name: 'キャンセル', exact: true }));
  await expect(screen.getByText('E2E Search Scope')).toBeVisible();
});

test('experience: document action returns to Ask AI without clearing the draft', async ({ app, device, screen }) => {
  await launchMemora(app, device, screen);
  await device.openLink('memora://ask-ai');
  const input = await focusComposer(screen);
  await input.fill('次に相談する下書きを保持します');
  await journal(device, screen);
  await tapControl(screen, screen.getByLabel('メニュー'));
  await tapControl(screen, screen.getByRole('button', { name: '資料', exact: true }));
  await tapControl(screen, screen.getByRole('button', { name: 'AIで資料を作る', exact: true }));
  await expect(input).toHaveValue('次に相談する下書きを保持します');
  await expect(screen.getByLabel('新しいチャット')).toBeVisible();
});

test('experience: source-only search reports a real match instead of zero', async ({ app, device, screen }) => {
  await launchMemora(app, device, screen);
  await device.openLink('memora://projects');
  await tapControl(screen, screen.getByRole('button', { name: 'プロジェクトを作成', exact: true }).first());
  await screen.getByPlaceholder('例：新規アプリ').fill('E2E Source Count');
  await tapControl(screen, screen.getByRole('button', { name: '作成', exact: true }));
  await tapControl(screen, screen.getByRole('button', { name: '参考資料', exact: true }).first());
  await tapControl(screen, screen.getByLabel('参考資料を追加').first());
  await screen.getByRole('textbox', { name: 'タイトル', exact: true }).fill('E2ESourceCountEvidence');
  const body = screen.getByTestId('source.content');
  await scrollToControl(screen, body);
  await tapControl(screen, body);
  await body.fill('端末内だけの検索検証メモ。');
  await scrollToControl(screen, screen.getByTestId('source.add'));
  await tapControl(screen.getByTestId('source.add'));
  await expect(body).not.toBeVisible();
  await device.openLink('memora://projects');
  await tapControl(screen, screen.getByRole('button', { name: 'ファイル', exact: true }).first());
  await openSidebarSearch(screen);
  const fileSearch = screen.getByTestId('collection.search.input');
  await expect(fileSearch).toBeVisible();
  await expect(screen.getByText('E2ESourceCountEvidence')).not.toBeVisible();
  await fileSearch.fill('E2ESourceCountEvidence');
  await expect(screen.getByText('E2ESourceCountEvidence')).toBeVisible();
  const count = screen.getByLabel('1件の検索結果');
  await scrollToControl(screen, count);
  await expect(count).toBeVisible();
  await app.screenshot('source-search-count');
});

test('experience: selected day returns to today through a real 44-point action', async ({ app, device, screen }) => {
  await launchMemora(app, device, screen);
  await journal(device, screen);
  const yesterday = new Date();
  yesterday.setDate(yesterday.getDate() - 1);
  await tapControl(screen, screen.getByRole('button', { name: dayName(yesterday) }));
  const today = screen.getByRole('button', { name: '今日に戻る', exact: true });
  await expect(today).toBeVisible();
  await expectTouchTarget(today);
  await app.screenshot('journal-selected-day');
  await tapControl(screen, today);
  await expect(screen.getByRole('button', { name: dayName(new Date()), selected: true })).toBeVisible();
  await expect(today).not.toBeVisible();
});

test('experience: capture menu offers its enabled entries without a header', async ({ app, device, screen }) => {
  await launchMemora(app, device, screen);
  await tapControl(screen, screen.getByRole('button', { name: '追加メニュー', exact: true }));
  // Online meeting capture is compiled off (FeatureFlags.isOnlineMeetingCaptureEnabled),
  // and the sheet deliberately has no title or close header.
  for (const title of ['録音する', '音声を取り込む', 'ノートを追加']) {
    const item = screen.getByRole('button', { name: title, exact: true });
    await expect(item).toBeVisible();
    await expectTouchTarget(item);
  }
  await expect(screen.getByText('新しい記録')).not.toBeVisible();
  await app.screenshot('create-menu');
});

test('experience: task, people and document screens retain their working actions', async ({ app, device, screen }) => {
  await launchMemora(app, device, screen);
  await openTasks(screen);
  await expect(screen.getByText('タスクはありません')).toBeVisible();
  await app.screenshot('tasks-empty');
  await journal(device, screen);
  await tapControl(screen, screen.getByLabel('メニュー'));
  await tapControl(screen, screen.getByRole('button', { name: '人物', exact: true }));
  await expect(screen.getByRole('button', { name: '人を追加', exact: true })).toBeVisible();
  await app.screenshot('people-empty');
  await journal(device, screen);
  await tapControl(screen, screen.getByLabel('メニュー'));
  await tapControl(screen, screen.getByRole('button', { name: '資料', exact: true }));
  await expect(screen.getByText('資料はまだありません')).toBeVisible();
  await app.screenshot('documents-empty');
  await tapControl(screen, screen.getByLabel('資料の操作'));
  await tapControl(screen, screen.getByRole('button', { name: '今週の週報を作る', exact: true }));
  await expect(screen.getByText('今週はまだ記録がありません')).toBeVisible();
  await tapControl(screen, screen.getByRole('button', { name: '閉じる', exact: true }).last());
});

test('experience: journal creation keeps the selected date across restart and the system memo link opens the shared editor', async ({ app, device, screen }) => {
  await launchMemora(app, device, screen);
  await journal(device, screen);
  const yesterday = new Date();
  yesterday.setDate(yesterday.getDate() - 1);
  const dayName = `^${yesterday.getFullYear()}/${yesterday.getMonth() + 1}/${yesterday.getDate()}[日月火水木金土]曜日、`;
  const previousDay = screen.getByRole('button', { name: new RegExp(dayName) });
  await tapControl(screen, previousDay);
  await tapControl(screen, screen.getByRole('button', { name: '記録を追加', exact: true }).first());
  const memo = screen.getByRole('button', { name: 'メモを追加', exact: true });
  try { await expect(memo).toBeVisible({ timeout: 1_500 }); await tapControl(screen, memo); } catch {}
  await screen.getByPlaceholder('メモのタイトル').fill('E2E 昨日の記録');
  await tapControl(screen, screen.getByRole('button', { name: '追加', exact: true }));
  const saved = screen.getByText('E2E 昨日の記録').first();
  await scrollToControl(screen, saved);
  await expect(saved).toBeVisible();
  await app.screenshot('journal-selected-day-saved');
  await app.restart();
  await journal(device, screen);
  await tapControl(screen, previousDay);
  await scrollToControl(screen, saved);
  await expect(saved).toBeVisible();

  await device.openLink('memora://new-memo');
  const memoTitle = screen.getByRole('textbox', { name: 'タイトル', exact: true });
  await expect(memoTitle).toBeVisible();
  await memoTitle.fill('E2E 外部から今日のメモ');
  await tapControl(screen, screen.getByRole('button', { name: '閉じる', exact: true }));
  await journal(device, screen);
  await expect(saved).toBeVisible();
});
