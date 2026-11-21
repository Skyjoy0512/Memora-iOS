import { test } from '@e2e-dev/mobile';
import { expect } from 'e2e';
import { launchMemora, scrollToControl, tapControl } from './ui-helpers';

const longTitle = '表示検証：定例ミーティングの決済サイクル変更・集計基準の統一・接客対応と次回リリースの確認事項';

async function verifyRowLayout(screen: any) {
  const row = screen.getByRole('button', { name: new RegExp(`^${longTitle}、`) });
  await expect(row).toBeVisible();
  const title = row.getByText(longTitle, { exact: true });
  const metadata = row.getByText(/ · 録音 · 43:54$/);
  const summary = row.getByText('次期リリースは、録音開始の速さと会議後の行動につながる体験を優先する方針で合意しました。', { exact: true });
  const rowBox = await row.boundingBox();
  const titleBox = await title.boundingBox();
  const metadataBox = await metadata.boundingBox();
  const summaryBox = await summary.boundingBox();
  if (!rowBox || !titleBox || !metadataBox || !summaryBox) throw new Error('Record content has no frame');
  // The full-width native row includes the standard 20pt content inset.
  expect(titleBox.x).toBeCloseTo(rowBox.x + 20, 0);
  expect(metadataBox.x).toBeCloseTo(titleBox.x, 0);
  expect(summaryBox.x).toBeCloseTo(titleBox.x, 0);
  expect(titleBox.y + titleBox.height).toBeLessThanOrEqual(metadataBox.y);
  expect(metadataBox.y + metadataBox.height).toBeLessThanOrEqual(summaryBox.y);
  expect(summaryBox.y + summaryBox.height).toBeLessThanOrEqual(rowBox.y + rowBox.height + 1);
  return { rowBox, titleBox };
}

test('Library selection keeps wrapped text inside its rows through repeated mode changes', { timeout: 240_000 }, async ({ app, device, screen }) => {
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

  const record = screen.getByRole('button', { name: /^リリース方針レビュー、/ });
  await scrollToControl(screen, record);
  await record.longPress({ duration: 800 });
  await tapControl(screen.getByRole('button', { name: '名前を変更', exact: true }));
  await screen.getByPlaceholder('会議名').fill(longTitle);
  await tapControl(screen.getByRole('button', { name: '保存', exact: true }));
  const before = await verifyRowLayout(screen);

  for (let pass = 0; pass < 3; pass++) {
    await tapControl(screen.getByLabel('表示と並べ替え', { exact: true }));
    await tapControl(screen.getByRole('button', { name: '選択', exact: true }));
    await expect(screen.getByTestId(/^root\.tab\./)).toHaveCount(0);
    await expect(screen.getByTestId('ai.composer.input')).not.toBeVisible();
    const selected = await verifyRowLayout(screen);
    expect(selected.titleBox.width).toBeCloseTo(before.titleBox.width, 0);
    const row = screen.getByRole('button', { name: new RegExp(`^${longTitle}、`) });
    await tapControl(row);
    await expect(screen.getByText('1件を選択', { exact: true }).first()).toBeVisible();
    await verifyRowLayout(screen);
    const adjacent = screen.getByRole('button', { name: /^顧客インタビュー音声、/ });
    await tapControl(adjacent);
    await expect(screen.getByText('2件を選択', { exact: true }).first()).toBeVisible();
    const multiple = await verifyRowLayout(screen);
    const adjacentBox = await adjacent.boundingBox();
    if (!adjacentBox) throw new Error('Adjacent record has no frame');
    expect(adjacentBox.y + adjacentBox.height).toBeLessThanOrEqual(multiple.rowBox.y + 1);
    const share = screen.getByRole('button', { name: '共有', exact: true });
    const remove = screen.getByRole('button', { name: '削除', exact: true });
    await expect(share).toBeEnabled();
    await expect(remove).toBeEnabled();
    const shareBox = await share.boundingBox();
    const removeBox = await remove.boundingBox();
    if (!shareBox || !removeBox) throw new Error('Selection actions have no frame');
    expect(shareBox.y).toBeCloseTo(removeBox.y, 0);
    expect(shareBox.height).toBeGreaterThanOrEqual(44);
    await app.screenshot(`library-selection-${pass}`);
    await tapControl(screen.getByRole('button', { name: 'キャンセル', exact: true }));
    await expect(screen.getByTestId('root.tab.files')).toBeSelected();
    await verifyRowLayout(screen);
  }

  await tapControl(screen.getByLabel('表示と並べ替え', { exact: true }));
  await tapControl(screen.getByRole('button', { name: '表示', exact: true }));
  await tapControl(screen.getByRole('button', { name: 'コンパクト', exact: true }));
  const compact = screen.getByRole('button', { name: new RegExp(`^${longTitle}、`) });
  await expect(compact).toBeVisible();
  await expect(compact.getByText(/次期リリースは/)).not.toBeVisible();
  const compactBox = await compact.boundingBox();
  if (!compactBox) throw new Error('Compact record has no frame');
  expect(compactBox.height).toBeLessThan(before.rowBox.height);
  expect(compactBox.height).toBeGreaterThanOrEqual(44);
  await app.screenshot('library-compact');
});
