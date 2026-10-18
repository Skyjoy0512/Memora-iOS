import { test } from '@e2e-dev/mobile';
import { expect } from 'e2e';

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

/// Creates a fresh project and lands on its workspace.
async function createProject(screen: any, device: any) {
  await screen.getByText('ライブラリ').tap();
  await screen.getByText('プロジェクト').tap();
  await screen.getByRole('button', { name: 'プロジェクトを作成' }).tap();
  await screen.getByPlaceholder('例：新規アプリ').fill('E2E Workspace');
  await tapStable(screen.getByRole('button', { name: '作成' }));
  await expect(screen.getByRole('button', { name: 'チャット', selected: true })).toBeVisible();
}

/// Scrolls the current screen up until the locator is on it.
async function scrollTo(screen: any, locator: any) {
  for (let i = 0; i < 8; i++) {
    if (await locator.isVisible()) return;
    await screen.swipe({ from: { x: 215, y: 700 }, to: { x: 215, y: 250 } });
  }
  throw new Error('could not scroll to the target');
}

test('the workspace tabs read chat, files, sources and switch in place', async ({ app, device, screen }) => {
  await device.installApp();
  await app.open();
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
  await expect(screen.getByLabel('ファイルを追加')).toBeVisible();
  await sources.tap();
  await expect(screen.getByLabel('ソースを追加')).toBeVisible();
  await tapStable(screen.getByRole('button', { name: 'チャット' }));
  await expect(screen.getByRole('button', { name: 'チャット', selected: true })).toBeVisible();
  await expect(screen.getByLabel('新しいチャット')).toBeVisible();
});

test('the week strip selects a day and updates the timeline', async ({ app, device, screen }) => {
  await device.installApp();
  await app.open();

  const yesterday = new Date();
  yesterday.setDate(yesterday.getDate() - 1);
  const month = yesterday.toLocaleString('en-US', { month: 'long' });
  const dayButton = screen.getByRole('button', {
    name: new RegExp(`${month} ${yesterday.getDate()}, ${yesterday.getFullYear()}`),
  });
  await expect(dayButton).toBeVisible();
  await dayButton.tap();

  await expect(screen.getByText(/の記録はありません/)).toBeVisible();
  await expect(screen.getByRole('button', {
    name: new RegExp(`${month} ${yesterday.getDate()}, ${yesterday.getFullYear()}`),
    selected: true,
  })).toBeVisible();
});

test('the inline plus buttons add a record', async ({ app, device, screen }) => {
  await device.installApp();
  await app.open();

  await screen.getByText('記録を追加').first().tap();
  await screen.getByPlaceholder('メモのタイトル').fill('E2E inline');
  const add = screen.getByRole('button', { name: '追加' });
  await expect(add).toBeEnabled();
  await tapStable(add);

  const between = screen.getByLabel('この間に記録を追加');
  await scrollTo(screen, between);
  await between.tap();
  await expect(screen.getByText('ライフログを追加')).toBeVisible();
  await screen.getByText('キャンセル').tap();

  const end = screen.getByRole('button', { name: '記録を追加' }).last();
  await scrollTo(screen, end);
  await end.tap();
  await expect(screen.getByText('ライフログを追加')).toBeVisible();
  await screen.getByText('キャンセル').tap();
});

test('the journal and workspace stay legible in dark appearance', async ({ app, device, screen }) => {
  await device.installApp();
  await device.setAppearance('dark');
  try {
    await app.open();
    await expect(screen.getByText('今日のタスク')).toBeVisible();
    await createProject(screen, device);
    await expect(screen.getByRole('button', { name: 'ソース' })).toBeVisible();
  } finally {
    await device.setAppearance('light');
  }
});
