import { afterEach, test } from '@e2e-dev/mobile';
import { expect } from 'e2e';
import { launchMemora, tapControl, tapTab } from './ui-helpers';

afterEach(async ({ device }) => { await device.setAppearance('light'); });

async function openCollection(screen: any, name: string) {
  await tapControl(screen, screen.getByLabel('メニュー').first());
  // The sidebar appends a count once a collection has saved records.
  await tapControl(screen, screen.getByRole('button', { name: new RegExp(`^${name}(?:、|$)`) }));
}

async function makeReview(app: any, device: any, screen: any) {
  await launchMemora(app, device, screen);
  // A journal memo is what the weekly review counts; a note source is not.
  await tapTab(screen, 'ジャーナル');
  await tapControl(screen.getByRole('button', { name: '記録を追加', exact: true }).first());
  const memoChoice = screen.getByRole('button', { name: 'メモを追加', exact: true });
  if (await memoChoice.isVisible()) await tapControl(memoChoice);
  await screen.getByPlaceholder('メモのタイトル').fill('Research meeting');
  await screen.getByPlaceholder('ひとことや背景').fill('Discuss research direction.');
  await tapControl(screen.getByRole('button', { name: '追加', exact: true }));
  await openCollection(screen, '資料');
  await tapControl(screen, screen.getByLabel('資料の操作'));
  await tapControl(screen, screen.getByRole('button', { name: '今週の週報を作る', exact: true }));
  await expect(screen.getByRole('button', { name: /Research meeting/ }).last()).toBeVisible();
}

test('collection polish: people search keeps notes, detail navigation and cancellation', { timeout: 180_000 }, async ({ app, device, screen }) => {
  await launchMemora(app, device, screen);
  await openCollection(screen, '人物');
  await tapControl(screen, screen.getByRole('button', { name: '人を追加', exact: true }));
  await screen.getByPlaceholder('名前').fill('Mori');
  await tapControl(screen, screen.getByRole('button', { name: '追加', exact: true }));
  await screen.getByPlaceholder('名前').fill('Sato');
  await tapControl(screen, screen.getByRole('button', { name: '追加', exact: true }));
  await tapControl(screen, screen.getByRole('button', { name: '完了', exact: true }));
  await tapControl(screen, screen.getByRole('button', { name: /^Mori、/ }));
  await tapControl(screen, screen.getByLabel('その他'));
  await tapControl(screen, screen.getByRole('button', { name: '編集', exact: true }));
  await screen.getByPlaceholder('メモ').fill('Design team');
  await tapControl(screen, screen.getByRole('button', { name: '保存', exact: true }));
  await expect(screen.getByPlaceholder('メモ')).not.toBeVisible();
  await tapControl(screen, screen.getByRole('button', { name: '人物', exact: true }));
  await tapControl(screen, screen.getByLabel('人物を検索'));
  await expect(screen.getByText(/名前やメモ/).first()).toBeVisible();
  await expect(screen.getByTestId('ai.composer.input')).not.toBeVisible();
  await expect(screen.getByRole('button', { name: /^Mori、/ })).not.toBeVisible();
  const query = screen.getByPlaceholder('名前・メモを検索');
  await query.fill('mori design');
  const mori = screen.getByRole('button', { name: /^Mori、/ });
  await expect(mori).toBeVisible();
  await expect(screen.getByRole('button', { name: /^Sato、/ })).not.toBeVisible();
  await app.screenshot('people-search-light');
  await tapControl(screen, mori);
  await expect(screen.getByText('Design team', { exact: true }).last()).toBeVisible();
  await expect(screen.getByTestId('ai.composer.input')).toBeVisible();
  await tapControl(screen, screen.getByRole('button', { name: '人物', exact: true }));
  await expect(query).toHaveValue('mori design');
  await expect(screen.getByTestId('ai.composer.input')).not.toBeVisible();
  await tapControl(screen, screen.getByLabel('検索語を消去'));
  await query.fill('zz-no-person');
  await device.setAppearance('dark');
  await expect(screen.getByText(/見つかりません/).first()).toBeVisible();
  await app.screenshot('people-search-empty-dark');
  await tapControl(screen, screen.getByRole('button', { name: 'キャンセル', exact: true }));
  await expect(screen.getByRole('button', { name: /^Mori、/ })).toBeVisible();
  await expect(screen.getByRole('button', { name: /^Sato、/ })).toBeVisible();
  await expect(screen.getByTestId('ai.composer.input')).toBeVisible();
});

test('collection polish: documents menu keeps existing actions and search empty state', async ({ app, device, screen }) => {
  await launchMemora(app, device, screen);
  await openCollection(screen, '資料');
  await expect(screen.getByText('資料はまだありません')).toBeVisible();
  await app.screenshot('documents-empty-light');
  await tapControl(screen, screen.getByLabel('資料の操作'));
  for (const name of ['メール下書き', '会社テンプレート', '今週の週報を作る']) {
    await expect(screen.getByRole('button', { name, exact: true })).toBeVisible();
  }
  await tapControl(screen, screen.getByRole('button', { name: '今週の週報を作る', exact: true }));
  await expect(screen.getByText('今週はまだ記録がありません')).toBeVisible();
  await tapControl(screen, screen.getByRole('button', { name: '閉じる', exact: true }).last());
  await tapControl(screen, screen.getByLabel('資料を検索').first());
  await expect(screen.getByText(/タイトル・本文/).first()).toBeVisible();
  await expect(screen.getByTestId('ai.composer.input')).not.toBeVisible();
  await screen.getByPlaceholder('タイトル・本文を検索').fill('missing');
  await expect(screen.getByText(/見つかりません/).first()).toBeVisible();
  await app.screenshot('documents-search-empty');
  await tapControl(screen, screen.getByRole('button', { name: 'キャンセル', exact: true }));
  await expect(screen.getByLabel('資料の操作')).toBeVisible();
});

test('collection polish: compact document menu opens mail drafts and company templates', async ({ app, device, screen }) => {
  await launchMemora(app, device, screen);
  await openCollection(screen, '資料');
  await tapControl(screen, screen.getByLabel('資料の操作'));
  await tapControl(screen, screen.getByRole('button', { name: 'メール下書き', exact: true }));
  await expect(screen.getByText('下書きはありません', { exact: true })).toBeVisible();
  await tapControl(screen, screen.getByRole('button', { name: '資料', exact: true }));
  await tapControl(screen, screen.getByLabel('資料の操作'));
  await tapControl(screen, screen.getByRole('button', { name: '会社テンプレート', exact: true }));
  await expect(screen.getByRole('button', { name: 'DOCX・PPTXを登録', exact: true })).toBeVisible();
  await tapControl(screen, screen.getByRole('button', { name: '資料', exact: true }));
  await expect(screen.getByLabel('資料の操作')).toBeVisible();
});

test('collection polish: document edits confirm discard, save and restore after restart', { timeout: 180_000 }, async ({ app, device, screen }) => {
  await makeReview(app, device, screen);
  await tapControl(screen, screen.getByLabel('その他'));
  await tapControl(screen, screen.getByRole('button', { name: '編集', exact: true }));
  await expect(screen.getByRole('button', { name: '保存', exact: true })).toBeDisabled();
  const originalBody = await screen.getByLabel('資料の本文').inputValue();
  await screen.getByPlaceholder('タイトル').fill('Research brief');
  await expect(screen.getByRole('button', { name: '保存', exact: true })).toBeEnabled();
  await tapControl(screen, screen.getByRole('button', { name: '完了', exact: true }));
  await expect(screen.getByRole('keyboard')).not.toBeVisible();
  await tapControl(screen, screen.getByRole('button', { name: 'キャンセル', exact: true }));
  // The system draws the destructive action only; tapping outside keeps editing.
  await expect(screen.getByText('変更を破棄しますか？', { exact: true })).toBeVisible();
  await app.screenshot('document-discard-confirmation');
  await screen.tapAt({ x: 200, y: 160 });
  await expect(screen.getByText('変更を破棄しますか？', { exact: true })).not.toBeVisible();
  await expect(screen.getByPlaceholder('タイトル')).toHaveValue('Research brief');
  await expect(screen.getByLabel('資料の本文')).toHaveValue(originalBody);
  await tapControl(screen, screen.getByRole('button', { name: 'キャンセル', exact: true }));
  await tapControl(screen, screen.getByRole('button', { name: '変更を破棄', exact: true }));
  await tapControl(screen, screen.getByLabel('その他'));
  await tapControl(screen, screen.getByRole('button', { name: '編集', exact: true }));
  await expect(screen.getByPlaceholder('タイトル')).not.toHaveValue('Research brief');
  await screen.getByPlaceholder('タイトル').fill('Research brief');
  await tapControl(screen, screen.getByRole('button', { name: '保存', exact: true }));
  await app.restart();
  await openCollection(screen, '資料');
  await tapControl(screen, screen.getByLabel('資料を検索').first());
  const query = screen.getByPlaceholder('タイトル・本文を検索');
  await query.fill('brief direction');
  const result = screen.getByRole('button', { name: /^Research brief、/ });
  await expect(result).toBeVisible();
  await app.screenshot('documents-search-result');
  await tapControl(screen, result);
  await tapControl(screen, screen.getByLabel('その他'));
  await tapControl(screen, screen.getByRole('button', { name: '編集', exact: true }));
  await expect(screen.getByLabel('資料の本文')).toHaveValue(originalBody);
  await tapControl(screen, screen.getByRole('button', { name: 'キャンセル', exact: true }));
});
