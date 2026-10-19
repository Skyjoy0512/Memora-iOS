import { test } from '@e2e-dev/mobile';
import { expect } from 'e2e';
import { launchMemora, tapControl, tapTab } from './ui-helpers';

/// Taps once, retrying a control that was still moving after the previous
/// action, which the mobile engine refuses rather than misplacing the touch.
async function tapStable(locator: any) {
  for (let attempt = 0; attempt < 3; attempt++) {
    try {
      await locator.tap();
      return;
    } catch (error) {
      if (attempt === 2) throw error;
    }
  }
}

/// Adds one memo from the journal's add sheet.
async function addMemo(screen: any, title: string) {
  await screen.getByText('記録を追加').first().tap();
  await screen.getByPlaceholder('メモのタイトル').fill(title);
  const add = screen.getByRole('button', { name: '追加' });
  await expect(add).toBeEnabled();
  await tapStable(add);
}

/// Taps an add control again if the first touch landed while the previous
/// sheet was still dismissing, then waits for the add sheet.
async function openAddSheet(screen: any, locator: any) {
  await tapStable(locator);
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
  await expect(screen.getByRole('button', { name: 'チャット', selected: true })).toBeVisible();
}

/// Scrolls the current screen up until the locator is on it.
async function scrollTo(screen: any, locator: any) {
  for (let i = 0; i < 8; i++) {
    if (await locator.isVisible()) return;
    await screen.swipe({ from: { x: 215, y: 700 }, to: { x: 215, y: 300 }, duration: 500 });
  }
  throw new Error('could not scroll to the target');
}

test('the workspace tabs read chat, files, sources and switch in place', async ({ app, device, screen }) => {
  await launchMemora(app, device, screen);
  await createProject(screen, device);

  const chat = screen.getByRole('button', { name: 'チャット', selected: true });
  const files = screen.getByRole('button', { name: 'ファイル' });
  const sources = screen.getByRole('button', { name: 'ソース' });
  await expect(chat).toBeVisible();
  await expect(files).toBeVisible();
  await expect(sources).toBeVisible();

  const chatBox = await chat.boundingBox();
  const filesBox = await files.boundingBox();
  const sourcesBox = await sources.boundingBox();
  if (!chatBox || !filesBox || !sourcesBox) throw new Error('workspace tabs have no frame');
  expect(chatBox.x).toBeLessThan(filesBox.x);
  expect(filesBox.x).toBeLessThan(sourcesBox.x);

  await files.tap();
  await expect(screen.getByLabel('ファイルを追加').first()).toBeVisible();
  await sources.tap();
  await expect(screen.getByLabel('ソースを追加').first()).toBeVisible();
  await tapStable(screen.getByRole('button', { name: 'チャット' }));
  await expect(screen.getByRole('button', { name: 'チャット', selected: true })).toBeVisible();
  await expect(screen.getByLabel('新しいチャット').first()).toBeVisible();
});

test('the week strip selects a day and updates the timeline', async ({ app, device, screen }) => {
  await launchMemora(app, device, screen);

  const title = `E2E day ${Date.now()}`;
  await addMemo(screen, title);

  const yesterday = new Date();
  yesterday.setDate(yesterday.getDate() - 1);
  const yesterdayName = `${yesterday.toLocaleString('en-US', { month: 'long' })} ${yesterday.getDate()}, ${yesterday.getFullYear()}`;
  await tapStable(screen.getByRole('button', { name: new RegExp(yesterdayName) }));

  await expect(screen.getByRole('button', { name: new RegExp(yesterdayName), selected: true })).toBeVisible();
  await expect(screen.getByText(title)).not.toBeVisible();

  const today = new Date();
  const todayName = `${today.toLocaleString('en-US', { month: 'long' })} ${today.getDate()}, ${today.getFullYear()}`;
  await tapStable(screen.getByRole('button', { name: new RegExp(todayName) }));
  const record = screen.getByText(title).first();
  await scrollTo(screen, record);
  await expect(record).toBeVisible();
});

test('the inline plus buttons add a record', async ({ app, device, screen }) => {
  await launchMemora(app, device, screen);

  await screen.getByText('記録を追加').first().tap();
  await screen.getByPlaceholder('メモのタイトル').fill('E2E inline');
  const add = screen.getByRole('button', { name: '追加' });
  await expect(add).toBeEnabled();
  await tapStable(add);

  const between = screen.getByLabel('この間に記録を追加').first();
  await scrollTo(screen, between);
  await openAddSheet(screen, between);
  await screen.getByText('キャンセル').tap();

  const end = screen.getByRole('button', { name: '記録を追加' }).last();
  await scrollTo(screen, end);
  await openAddSheet(screen, end);
  await screen.getByText('キャンセル').tap();
});

test('the journal and workspace stay legible in dark appearance', async ({ app, device, screen }) => {
  await launchMemora(app, device, screen);
  await device.setAppearance('dark');
  try {
    await expect(screen.getByText('今日のタスク')).toBeVisible();
    await createProject(screen, device);
    await expect(screen.getByRole('button', { name: 'ソース' })).toBeVisible();
  } finally {
    await device.setAppearance('light');
  }
});

test('editing a record saves it to the new date', async ({ app, device, screen }) => {
  await launchMemora(app, device, screen);
  const title = `E2E edit ${Date.now()}`;
  await addMemo(screen, title);

  await tapStable(screen.getByLabel('検索'));
  await screen.getByPlaceholder('ジャーナルを検索').fill(title);
  const preview = screen.getByText(title).first();
  await expect(preview).toBeVisible();
  await tapStable(preview);
  await expect(screen.getByLabel('その他')).toBeVisible();

  await tapStable(screen.getByLabel('その他'));
  await tapStable(screen.getByText('編集'));

  await tapStable(screen.getByRole('button', { name: 'Sheet Grabber' }));
  const today = new Date();
  const todayLabel = `${today.toLocaleString('en-US', { month: 'short' })} ${today.getDate()}, ${today.getFullYear()}`;
  await tapStable(screen.getByRole('button', { name: todayLabel }));

  const target = new Date();
  target.setDate(target.getDate() - 1);
  if (target.getMonth() !== today.getMonth()) target.setDate(today.getDate() + 1);
  const targetName = `${target.toLocaleString('en-US', { month: 'long' })} ${target.getDate()}`;
  await tapStable(screen.getByRole('listitem', { name: new RegExp(targetName) }));

  await tapStable(screen.getByRole('button', { name: '保存' }));
  const targetLabel = `${target.toLocaleString('en-US', { month: 'short' })} ${target.getDate()}, ${target.getFullYear()}`;
  await expect(screen.getByText(new RegExp(targetLabel)).first()).toBeVisible();
});

test('a source added in the workspace stays in the sources tab', async ({ app, device, screen }) => {
  await launchMemora(app, device, screen);
  await createProject(screen);

  await tapStable(screen.getByRole('button', { name: 'ソース' }));
  await tapStable(screen.getByLabel('ソースを追加').first());
  await screen.getByPlaceholder('YouTube・WebのURL').fill('https://example.com/e2e-source');
  const save = screen.getByRole('button', { name: 'リンクを保存' });
  await expect(save).toBeEnabled();
  await tapStable(save);
  await tapStable(screen.getByLabel('閉じる'));

  const row = screen.getByText('example.com').first();
  await expect(row).toBeVisible();

  await tapStable(screen.getByRole('button', { name: 'チャット' }));
  await tapStable(screen.getByRole('button', { name: 'ソース' }));
  await expect(screen.getByText('example.com').first()).toBeVisible();
});

test('the project list filters all, mine and shared', async ({ app, device, screen }) => {
  await launchMemora(app, device, screen);
  await tapTab(screen, 'ライブラリ');
  await tapControl(screen, screen.getByRole('button', { name: 'プロジェクト', exact: true }));

  await expect(screen.getByRole('button', { name: 'すべて', selected: true })).toBeVisible();
  await tapStable(screen.getByRole('button', { name: '自分' }));
  await expect(screen.getByRole('button', { name: '自分', selected: true })).toBeVisible();
  await tapStable(screen.getByRole('button', { name: '共有' }));
  await expect(screen.getByRole('button', { name: '共有', selected: true })).toBeVisible();
  await expect(screen.getByText('共有されたプロジェクトはありません')).toBeVisible();
  await tapStable(screen.getByRole('button', { name: 'すべて' }));
  await expect(screen.getByRole('button', { name: 'すべて', selected: true })).toBeVisible();
});

test('the files tab offers recording and existing-file actions', async ({ app, device, screen }) => {
  await launchMemora(app, device, screen);
  await createProject(screen);

  await tapStable(screen.getByRole('button', { name: 'ファイル' }));
  await tapStable(screen.getByRole('button', { name: 'ファイルを追加' }).first());
  await expect(screen.getByRole('button', { name: '録音を追加' }).first()).toBeVisible();
  await expect(screen.getByRole('button', { name: '既存ファイルを移動' }).first()).toBeVisible();
  await tapStable(screen.getByText('既存ファイルを移動'));

  await expect(screen.getByText('既存ファイルを移動').first()).toBeVisible();
  await tapStable(screen.getByText('キャンセル'));
  await expect(screen.getByRole('button', { name: 'ファイル', selected: true })).toBeVisible();
});
