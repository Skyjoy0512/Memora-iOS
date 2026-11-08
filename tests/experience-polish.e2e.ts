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

test('experience: journal, library and create menu remain coherent in both appearances', async ({ app, device, screen }) => {
  await launchMemora(app, device, screen);
  for (const appearance of ['light', 'dark'] as const) {
    await device.setAppearance(appearance);
    await journal(device, screen);
    await expect(screen.getByText('今日のタスク')).toBeVisible();
    await app.screenshot(`journal-${appearance}`);
    await tapTab(screen, 'ライブラリ');
    await device.openLink('memora://projects');
    await tapControl(screen, screen.getByRole('button', { name: 'ファイル', exact: true }).first());
    await expect(screen.getByRole('button', { name: '録音または読み込み', exact: true }).first()).toBeVisible();
    await app.screenshot(`library-${appearance}`);
    await tapControl(screen, screen.getByRole('button', { name: '作成メニューを開く', exact: true }));
    for (const title of ['録音を開始', '音声を取り込む', 'オンライン会議']) {
      await expect(screen.getByRole('button', { name: title, exact: true })).toBeVisible();
    }
    await app.screenshot(`create-menu-${appearance}`);
    await journal(device, screen);
  }
});

test('experience: empty task action creates a task, completes it and keeps it after restart', async ({ app, device, screen }) => {
  await launchMemora(app, device, screen);
  await expectTouchTarget(screen.getByLabel('すべてのタスクを見る'));
  await tapControl(screen, screen.getByLabel('すべてのタスクを見る'));
  const add = screen.getByRole('button', { name: 'タスクを追加', exact: true }).last();
  await tapControl(screen, add);
  await screen.getByPlaceholder('すること').fill('E2E 操作を磨き込む');
  await tapControl(screen, screen.getByRole('button', { name: '追加', exact: true }));
  await expect(screen.getByRole('button', { name: /^E2E 操作を磨き込む、/ })).toBeVisible();
  const complete = screen.getByRole('button', { name: '完了にする', exact: true });
  await expectTouchTarget(complete);
  await app.screenshot('tasks-active');
  await tapControl(screen, complete);
  await tapControl(screen, screen.getByRole('button', { name: '完了', exact: true }));
  await expect(screen.getByRole('button', { name: /^E2E 操作を磨き込む、/ })).toBeVisible();
  await app.restart();
  await journal(device, screen);
  await tapControl(screen, screen.getByLabel('すべてのタスクを見る'));
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
  await expect(screen.getByText('ファイルを検索', { exact: true })).toBeVisible();
  await tapControl(screen, screen.getByRole('button', { name: 'キャンセル', exact: true }));
  await device.openLink('memora://projects');
  await tapControl(screen, screen.getByRole('button', { name: 'プロジェクトを作成', exact: true }).first());
  await screen.getByPlaceholder('例：新規アプリ').fill('E2E Search Scope');
  await tapControl(screen, screen.getByRole('button', { name: '作成', exact: true }));
  await device.openLink('memora://projects');
  await expect(screen.getByText('E2E Search Scope')).toBeVisible();
  await openSidebarSearch(screen);
  await expect(screen.getByText('プロジェクトを検索')).toBeVisible();
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
  await tapControl(screen, screen.getByRole('button', { name: 'Ask AIを開く', exact: true }));
  await expect(input).toHaveValue('次に相談する下書きを保持します');
  await expect(screen.getByLabel('新しいチャット')).toBeVisible();
});

test('experience: source-only search reports a real match instead of zero', async ({ app, device, screen }) => {
  await launchMemora(app, device, screen);
  await device.openLink('memora://projects');
  await tapControl(screen, screen.getByRole('button', { name: 'プロジェクトを作成', exact: true }).first());
  await screen.getByPlaceholder('例：新規アプリ').fill('E2E Source Count');
  await tapControl(screen, screen.getByRole('button', { name: '作成', exact: true }));
  await tapControl(screen, screen.getByRole('button', { name: 'ソース', exact: true }).first());
  await tapControl(screen, screen.getByLabel('ソースを追加').first());
  await screen.getByPlaceholder('タイトル').fill('E2ESourceCountEvidence');
  await tapControl(screen, screen.getByLabel('キーボードを閉じる'));
  const body = screen.getByLabel('メモ本文');
  await scrollToControl(screen, body);
  await tapControl(screen, body);
  await body.fill('端末内だけの検索検証メモ。');
  await tapControl(screen, screen.getByLabel('キーボードを閉じる'));
  await scrollToControl(screen, screen.getByRole('button', { name: 'メモを保存', exact: true }));
  await tapControl(screen, screen.getByRole('button', { name: 'メモを保存', exact: true }));
  await expect(body).toHaveValue('');
  await tapControl(screen, screen.getByLabel('閉じる'));
  await device.openLink('memora://projects');
  await tapControl(screen, screen.getByRole('button', { name: 'ファイル', exact: true }).first());
  await openSidebarSearch(screen);
  await expect(screen.getByText('ファイルを検索')).toBeVisible();
  await expect(screen.getByText('E2ESourceCountEvidence')).not.toBeVisible();
  await screen.getByRole('textbox').first().fill('E2ESourceCountEvidence');
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
  const dayName = (date: Date) => `${date.toLocaleString('en-US', { month: 'long' })} ${date.getDate()}, ${date.getFullYear()}`;
  await tapControl(screen, screen.getByRole('button', { name: new RegExp(dayName(yesterday)) }));
  const today = screen.getByRole('button', { name: '今日に戻る', exact: true });
  await expect(today).toBeVisible();
  await expectTouchTarget(today);
  await app.screenshot('journal-selected-day');
  await tapControl(screen, today);
  await expect(screen.getByRole('button', { name: new RegExp(dayName(new Date())), selected: true })).toBeVisible();
  await expect(today).toBeDisabled();
});

test('experience: capture actions scroll at large text and open the real preparation screen', async ({ app, device, screen }) => {
  await launchMemora(app, device, screen);
  await tapControl(screen, screen.getByRole('button', { name: '作成メニューを開く', exact: true }));
  await expect(screen.getByText('新しい記録')).toBeVisible();
  const online = screen.getByRole('button', { name: 'オンライン会議', exact: true });
  await scrollToControl(screen, online);
  await expectTouchTarget(online);
  await app.screenshot('create-menu-scrolled');
  await tapControl(screen, online);
  await expect(screen.getByText('Zoom')).toBeVisible();
  const prepare = screen.getByRole('button', { name: '録音の準備をする', exact: true });
  await scrollToControl(screen, prepare);
  await expect(prepare).toBeVisible();
  await app.screenshot('online-meeting-preparation');
  await tapControl(screen, screen.getByRole('button', { name: '閉じる', exact: true }));
  await expect(screen.getByText('今日のタスク')).toBeVisible();
});

test('experience: task, people and document screens retain their working actions', async ({ app, device, screen }) => {
  await launchMemora(app, device, screen);
  await journal(device, screen);
  await tapControl(screen, screen.getByLabel('すべてのタスクを見る'));
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
  await tapControl(screen, screen.getByRole('button', { name: 'OK', exact: true }));
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
