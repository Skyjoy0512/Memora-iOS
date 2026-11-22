import { test } from '@e2e-dev/mobile';
import { expect } from 'e2e';
import { launchMemora, scrollToControl, selectLibrarySection, tapControl } from './ui-helpers';

const longTitle = '表示検証：定例ミーティングの決済サイクル変更・集計基準の統一・接客対応と次回リリースの確認事項';

async function verifyRowLayout(screen: any, showsPreview = true) {
  const row = screen.getByRole('button', { name: new RegExp(`^${longTitle}、`) });
  await expect(row).toBeVisible();
  const title = row.getByText(longTitle, { exact: true });
  const metadata = row.getByText(/ · 録音 · 43:54$/);
  const summary = row.getByText('次期リリースは、録音開始の速さと会議後の行動につながる体験を優先する方針で合意しました。', { exact: true });
  const rowBox = await row.boundingBox();
  const titleBox = await title.boundingBox();
  const metadataBox = await metadata.boundingBox();
  if (!rowBox || !titleBox || !metadataBox) throw new Error('Record content has no frame');
  // The full-width native row includes the standard 20pt content inset.
  expect(titleBox.x).toBeCloseTo(rowBox.x + 20, 0);
  expect(metadataBox.x).toBeCloseTo(titleBox.x, 0);
  expect(titleBox.y + titleBox.height).toBeLessThanOrEqual(metadataBox.y);
  const rowBottom = rowBox.y + rowBox.height;
  if (showsPreview) {
    const summaryBox = await summary.boundingBox();
    if (!summaryBox) throw new Error('Record preview has no frame');
    expect(summaryBox.x).toBeCloseTo(titleBox.x, 0);
    expect(metadataBox.y + metadataBox.height).toBeLessThanOrEqual(summaryBox.y);
    expect(summaryBox.y + summaryBox.height).toBeLessThanOrEqual(rowBottom + 1);
  } else {
    await expect(summary).not.toBeVisible();
    expect(metadataBox.y + metadataBox.height).toBeLessThanOrEqual(rowBottom + 1);
  }

  const previousBox = await screen.getByRole('button', { name: /^顧客インタビュー音声、/ }).boundingBox();
  const nextBox = await screen.getByRole('button', { name: /^佐藤さん 1on1、/ }).boundingBox();
  if (!previousBox || !nextBox) throw new Error('Neighboring record has no frame');
  expect(previousBox.y + previousBox.height).toBeLessThanOrEqual(rowBox.y + 1);
  expect(rowBottom).toBeLessThanOrEqual(nextBox.y + 1);
  return { rowBox, titleBox, metadataBox };
}

function expectUnchangedLayout(before: Awaited<ReturnType<typeof verifyRowLayout>>, after: typeof before) {
  expect(after.rowBox.y).toBeCloseTo(before.rowBox.y, 0);
  expect(after.rowBox.height).toBeCloseTo(before.rowBox.height, 0);
  expect(after.titleBox.width).toBeCloseTo(before.titleBox.width, 0);
  expect(after.metadataBox.width).toBeCloseTo(before.metadataBox.width, 0);
  expect(after.metadataBox.height).toBeCloseTo(before.metadataBox.height, 0);
}

async function swipeToSelect(screen: any, box: { x: number; y: number; width: number; height: number },
  fullSwipe: boolean) {
  const y = box.y + box.height / 2;
  await screen.swipe({
    from: { x: Math.round(box.x + box.width * 0.12), y: Math.round(y) },
    to: { x: Math.round(box.x + box.width * (fullSwipe ? 0.94 : 0.44)), y: Math.round(y) },
    duration: fullSwipe ? 350 : 550,
  });
  if (!fullSwipe) await tapControl(screen.getByRole('button', { name: '選択', exact: true }));
  await expect(screen.getByText('1件を選択', { exact: true }).first()).toBeVisible();
}

async function loadSampleFiles(app: any, device: any, screen: any) {
  // launchMemora reinstalls only the dedicated test simulator's app.
  await launchMemora(app, device, screen);
  await tapControl(screen.getByLabel('メニュー').first());
  await tapControl(screen.getByTestId('sidebar.settings'));
  const diagnostics = screen.getByTestId('settings.category.diagnostics');
  await scrollToControl(screen, diagnostics);
  await tapControl(diagnostics);
  const reset = screen.getByRole('button', { name: 'デモデータに置き換える', exact: true });
  await scrollToControl(screen, reset);
  await tapControl(reset);
  await tapControl(screen.getByRole('button', { name: '置き換える', exact: true }));
  await tapControl(screen.getByTestId('BackButton'));
  await tapControl(screen.getByRole('button', { name: '閉じる', exact: true }));
}

test('Library selection keeps wrapped text inside its rows through repeated mode changes', { timeout: 240_000 }, async ({ app, device, screen }) => {
  await loadSampleFiles(app, device, screen);
  const record = screen.getByRole('button', { name: /^リリース方針レビュー、/ });
  // Wait for the settings sheet to leave before the first Library gesture.
  await expect(record).toBeVisible({ timeout: 15_000 });
  await record.longPress({ duration: 800 });
  await tapControl(screen.getByRole('button', { name: '名前を変更', exact: true }));
  const name = screen.getByPlaceholder('会議名');
  await name.fill(longTitle, { timeout: 30_000 });
  await expect(name).toHaveValue(longTitle);
  await tapControl(screen.getByRole('button', { name: '保存', exact: true }));
  const renamed = screen.getByRole('button', { name: new RegExp(`^${longTitle}、`) });
  await scrollToControl(screen, renamed, { minimumY: 160, maximumY: 680 });
  const before = await verifyRowLayout(screen);
  await app.screenshot('library-preview-before-selection');

  for (const entry of ['partial-swipe', 'full-swipe', 'menu'] as const) {
    await scrollToControl(screen, renamed, { minimumY: 160, maximumY: 680 });
    const initial = await verifyRowLayout(screen);
    if (entry === 'menu') {
      await tapControl(screen.getByLabel('表示と並べ替え', { exact: true }));
      await tapControl(screen.getByRole('button', { name: '選択', exact: true }));
      await tapControl(renamed);
    } else {
      await swipeToSelect(screen, initial.rowBox, entry === 'full-swipe');
    }
    await expect(screen.getByTestId(/^root\.tab\./)).toHaveCount(0);
    await expect(screen.getByTestId('ai.composer.input')).not.toBeVisible();
    await expect(screen.getByRole('button', { name: 'ファイルを検索', exact: true })).toBeDisabled();
    await expect(screen.getByText('1件を選択', { exact: true }).first()).toBeVisible();
    await expect(renamed).toBeSelected();
    const selected = await verifyRowLayout(screen);
    expectUnchangedLayout(initial, selected);
    await app.screenshot(`library-preview-${entry}-selected`);
    const adjacent = screen.getByRole('button', { name: /^顧客インタビュー音声、/ });
    await tapControl(adjacent);
    await expect(screen.getByText('2件を選択', { exact: true }).first()).toBeVisible();
    expectUnchangedLayout(initial, await verifyRowLayout(screen));
    const share = screen.getByRole('button', { name: '共有', exact: true });
    const remove = screen.getByRole('button', { name: '削除', exact: true });
    await expect(share).toBeEnabled();
    await expect(remove).toBeEnabled();
    const shareBox = await share.boundingBox();
    const removeBox = await remove.boundingBox();
    if (!shareBox || !removeBox) throw new Error('Selection actions have no frame');
    expect(shareBox.y).toBeCloseTo(removeBox.y, 0);
    expect(shareBox.height).toBeGreaterThanOrEqual(44);
    await tapControl(screen.getByRole('button', { name: 'キャンセル', exact: true }));
    await expect(screen.getByTestId('root.tab.files')).toBeSelected();
    expectUnchangedLayout(initial, await verifyRowLayout(screen));
  }

  await tapControl(screen.getByLabel('表示と並べ替え', { exact: true }));
  await tapControl(screen.getByRole('button', { name: '表示', exact: true }));
  await tapControl(screen.getByRole('button', { name: 'コンパクト', exact: true }));
  await scrollToControl(screen, renamed, { minimumY: 160, maximumY: 680 });
  const compact = await verifyRowLayout(screen, false);
  expect(compact.rowBox.height).toBeLessThan(before.rowBox.height);
  expect(compact.rowBox.height).toBeGreaterThanOrEqual(44);
  for (const fullSwipe of [true, false]) {
    const initial = await verifyRowLayout(screen, false);
    await swipeToSelect(screen, initial.rowBox, fullSwipe);
    await expect(renamed).toBeSelected();
    expectUnchangedLayout(initial, await verifyRowLayout(screen, false));
    await app.screenshot(`library-compact-${fullSwipe ? 'full' : 'partial'}-swipe-selected`);
    await tapControl(screen.getByRole('button', { name: 'キャンセル', exact: true }));
    expectUnchangedLayout(initial, await verifyRowLayout(screen, false));
  }
});

test('Library search preserves its results through selection, cancel and bulk move', { timeout: 180_000 }, async ({ app, device, screen }) => {
  await loadSampleFiles(app, device, screen);
  const first = screen.getByRole('button', { name: /^リリース方針レビュー、/ });
  const second = screen.getByRole('button', { name: /^デザインレビュー、/ });
  const other = screen.getByRole('button', { name: /^顧客インタビュー音声、/ });
  await expect(first).toBeVisible();
  await tapControl(screen.getByRole('button', { name: 'ファイルを検索', exact: true }));
  const query = screen.getByTestId('collection.search.input');
  await query.fill('レビュー');
  await expect(query).toHaveValue('レビュー');
  await expect(first).toBeVisible();
  await expect(other).not.toBeVisible();

  const cancel = screen.getByTestId('collection.search.cancel');
  for (const fullSwipe of [false, true]) {
    const box = await first.boundingBox();
    if (!box) throw new Error('Search result has no frame');
    await swipeToSelect(screen, box, fullSwipe);
    await expect(first).toBeSelected();
    await expect(query).toBeDisabled();
    await expect(query).toHaveValue('レビュー');
    await expect(screen.getByRole('keyboard')).not.toBeVisible();
    await expect(screen.getByTestId(/^root\.tab\./)).toHaveCount(0);
    await expect(other).not.toBeVisible();
    const selected = await first.boundingBox();
    if (!selected) throw new Error('Selected search result has no frame');
    expect(selected.y).toBeCloseTo(box.y, 0);
    if (!fullSwipe) {
      await tapControl(cancel);
      await expect(query).toBeEnabled();
      await expect(query).toHaveValue('レビュー');
    }
  }

  await tapControl(second);
  await expect(screen.getByText('2件を選択', { exact: true }).first()).toBeVisible();
  await app.screenshot('library-search-selection');
  await tapControl(screen.getByRole('button', { name: '移動', exact: true }));
  await expect(screen.getByText('2件の所属先を変更します。', { exact: true })).toBeVisible();
  await tapControl(screen.getByRole('button', { name: '法人提案', exact: true }));
  await expect(query).toBeEnabled();
  await expect(query).toHaveValue('レビュー');
  await expect(first).toBeVisible();
  await expect(second).toBeVisible();
  await expect(other).not.toBeVisible();

  await tapControl(cancel);
  await expect(screen.getByTestId('root.tab.files')).toBeSelected();
  await selectLibrarySection(screen, 'プロジェクト');
  await tapControl(screen.getByRole('button', { name: /^法人提案/ }).first());
  await expect(first).toBeVisible();
  await expect(second).toBeVisible();
  await expect(other).not.toBeVisible();
});
