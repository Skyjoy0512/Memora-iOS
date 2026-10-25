import { execFileSync } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import { existsSync, mkdirSync, readFileSync, readdirSync, realpathSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { afterEach, test } from '@e2e-dev/mobile';
import { expect } from 'e2e';
import { tapControl, tapTab, scrollToControl, openSummaryPoster, replaceEditorWithPaste } from './ui-helpers';
import { sql } from './sqlite-fixture-helpers';
import { seedSummaryFixture } from './summary-fixture-helpers';

afterEach(async ({ device }) => { await device.setAppearance('light'); });

// Only a fresh dedicated E2E simulator, positively identified by a UI-created
// UUID memo, receives this explicit fixture. The preview's records are untouched.
test('summary PNG, full-text reading and reversible transcript survive restart', { timeout: 360_000 }, async ({ app, device, screen }) => {
  const { database, identity, fixture, title, summary, raw, marker } = await seedSummaryFixture(app, device, screen);
  await expect(screen.getByTestId('summary.poster.inline')).toBeVisible();
  await app.screenshot('summary-entry-light');
  await openSummaryPoster(screen);
  await expect(screen.getByTestId('summary.poster.image')).toBeVisible({ timeout: 60_000 });
  await app.screenshot('summary-poster-light');
  await tapControl(screen.getByRole('tab', { name: '全文', exact: true }));
  await expect(screen.getByText('予算は10万円ではなく12万円。承認された場合だけ来週実施する。', { exact: true })).toBeVisible();
  await app.screenshot('summary-poster-full-text');
  await tapControl(screen.getByRole('tab', { name: '画像', exact: true }));
  await tapControl(screen.getByTestId('summary.poster.export'));
  await expect(screen.getByRole('button', { name: '共有先・保存先を選ぶ', exact: true })).toBeVisible();
  await tapControl(screen.getByRole('button', { name: '共有先・保存先を選ぶ', exact: true }));
  const container = resolve(dirname(database), '../../..');
  const folder = join(container, 'tmp');
  const pngFiles = () => readdirSync(folder).filter(name => /^Memora-summary-[a-f0-9-]+\.png$/i.test(name));
  await expect.poll(() => pngFiles().length).toBe(1);
  const pngPath = join(folder, pngFiles()[0]);
  const png = readFileSync(pngPath);
  expect(png.subarray(0, 8).toString('hex')).toBe('89504e470d0a1a0a');
  expect(png.readUInt32BE(16)).toBe(1440);
  const fullPosterHeight = png.readUInt32BE(20);
  expect(fullPosterHeight).toBeGreaterThan(0);
  expect(fullPosterHeight).toBeLessThan(2400);
  const artifacts = join('.e2e', 'regression', 'summary-poster-artifacts');
  mkdirSync(artifacts, { recursive: true });
  writeFileSync(join(artifacts, marker + '.png'), png, { flag: 'wx' });
  await expect(screen.getByRole('listitem', { name: /^(Copy|コピー)$/ }).first()).toBeVisible();
  await app.screenshot('summary-png-share-sheet');
  await tapControl(screen.getByRole('button', { name: /^(Close|閉じる)$/ }).first());
  await expect.poll(() => existsSync(pngPath)).toBe(false);
  await device.setAppearance('dark');
  await tapControl(screen.getByRole('button', { name: '拡大して読む', exact: true }));
  await tapControl(screen.getByRole('button', { name: '全体を表示', exact: true }));
  await expect(screen.getByTestId('summary.poster.image')).toBeVisible();
  await app.screenshot('summary-poster-dark');
  await tapControl(screen.getByRole('button', { name: '完了', exact: true }));
  await tapControl(screen.getByRole('button', { name: '文字起こし', exact: true }));
  const readable = screen.getByTestId('transcript.readable');
  await expect(readable).toBeChecked();
  await expect(screen.getByRole('button', { name: '予算は10万円ではなく12万円です。', exact: true })).toBeVisible();
  await app.screenshot('transcript-readable-dark');
  await readable.uncheck();
  await expect(screen.getByRole('button', { name: raw, exact: true })).toBeVisible();
  await app.screenshot('transcript-original-dark');
  await app.restart();
  await tapTab(screen, 'ライブラリ');
  await tapControl(screen.getByRole('button', { name: new RegExp('^' + title) }).first());
  await tapControl(screen.getByRole('button', { name: '文字起こし', exact: true }));
  await expect(readable).toBeChecked({ checked: false });
  await expect(screen.getByRole('button', { name: raw, exact: true })).toBeVisible();
  const restored = JSON.parse(sql(database, "SELECT CAST(data AS TEXT) FROM documents WHERE key='memoraMeetings';"));
  expect(restored[0].summary).toBe(summary);
  expect(restored[0].transcript[0].text).toBe(raw);
  await readable.check();
  await tapControl(screen.getByRole('button', { name: '予算は10万円ではなく12万円です。', exact: true }));
  await expect(screen.getByRole('textbox', { name: '本文', exact: true })).toHaveValue(raw);
  await tapControl(screen.getByRole('button', { name: '完了', exact: true }));
  await expect(screen.getByRole('textbox', { name: '本文', exact: true })).not.toBeVisible();
  await tapControl(screen.getByRole('button', { name: 'サマリー', exact: true }));
  const overview = '予算は10万円ではなく12万円。承認された場合だけ来週実施する。';
  const edited = '予算は12万円。承認待ちのため本番切替はしない。';
  await scrollToControl(screen, screen.getByRole('button', { name: overview, exact: true }));
  await tapControl(screen.getByRole('button', { name: overview, exact: true }));
  const summaryEditor = screen.getByRole('textbox', { name: '本文', exact: true });
  await expect(summaryEditor).toHaveValue(overview);
  await expect(summaryEditor).toBeFocused();
  await replaceEditorWithPaste(screen, device, summaryEditor, edited);
  await expect(summaryEditor).toHaveValue(edited);
  await tapControl(screen.getByRole('button', { name: '完了', exact: true }));
  await expect.poll(() => JSON.parse(sql(database, "SELECT CAST(data AS TEXT) FROM documents WHERE key='memoraMeetings';"))[0].summary.includes(edited)).toBe(true);
  await openSummaryPoster(screen);
  await expect(screen.getByTestId('summary.poster.image')).toBeVisible();
  await tapControl(screen.getByRole('tab', { name: '全文', exact: true }));
  await expect(screen.getByText(edited, { exact: true })).toBeVisible();
  await app.screenshot('summary-edited-reflected-in-poster');
  // The UUID-marker-validated DB must belong to this exact CoreSimulator, not
  // the user's preview. Restore the original OS setting even on an assertion failure.
  const match = database.match(/\/CoreSimulator\/Devices\/([a-f0-9-]{36})\/data\/Containers\/Data\/Application\//i);
  if (!match) throw new Error('Cannot identify the isolated simulator for Dynamic Type');
  const simulatorID = match[1];
  const reported = execFileSync('xcrun', ['simctl', 'get_app_container', simulatorID, identity.bundleId!, 'data'], { encoding: 'utf8' }).trim();
  expect(realpathSync(reported)).toBe(realpathSync(container));
  const contentSize = (...args: string[]) => execFileSync('xcrun', ['simctl', 'ui', simulatorID, 'content_size', ...args], { encoding: 'utf8' }).trim();
  const previousSize = contentSize();
  if (!/^(extra-small|small|medium|large|extra-large|extra-extra-large|extra-extra-extra-large|accessibility-medium|accessibility-large|accessibility-extra-large|accessibility-extra-extra-large|accessibility-extra-extra-extra-large)$/.test(previousSize)) throw new Error('Unknown content size; refusing to alter it');
  try {
    contentSize('accessibility-extra-extra-extra-large');
    await screen.scrollUntilVisible(screen.getByText(edited, { exact: true }));
    await expect(screen.getByText(edited, { exact: true })).toBeVisible();
    await expect(screen.getByRole('button', { name: '完了', exact: true })).toBeVisible();
    await app.screenshot('summary-full-text-largest-dynamic-type');
  } finally { contentSize(previousSize); }
  await device.closeApp();
  const legacyRecords = JSON.parse(sql(database, "SELECT CAST(data AS TEXT) FROM documents WHERE key='memoraMeetings';"));
  expect(legacyRecords).toHaveLength(1);
  expect(legacyRecords[0].id.toLowerCase()).toBe(fixture.id.toLowerCase());
  legacyRecords[0].summary = '## メモ\n**日程**: 2026/10/24\n**議題**: 条件付きで比較するが、本番切替はまだ承認されていない。';
  const versionID = randomUUID();
  legacyRecords[0].activeSummaryVersionID = versionID;
  legacyRecords[0].summaryVersions = [{ id: versionID, sourceRecordID: fixture.id,
    templateID: 'market.regular', summaryLength: 'standard', displayOrder: 'importance',
    sections: [{ id: randomUUID(), title: 'メモ', content: legacyRecords[0].summary.split('\n').slice(1).join('\n'), order: 0, sourceReferences: [] }],
    generatedAt: fixture.createdAt, modelInfo: 'UI regression fixture; no AI generation', schemaVersion: 1,
    markdown: legacyRecords[0].summary, keyPoints: [], decisions: [], openQuestions: [] }];
  const legacyBytes = Buffer.from(JSON.stringify(legacyRecords), 'utf8').toString('hex');
  sql(database, `UPDATE documents SET data=X'${legacyBytes}' WHERE key='memoraMeetings' AND instr(lower(CAST(data AS TEXT)), '${fixture.id.toLowerCase()}')>0;`);
  await app.restart();
  await tapTab(screen, 'ライブラリ');
  await tapControl(screen.getByRole('button', { name: new RegExp('^' + title) }).first());
  // A known market template and nonempty parsed section would previously
  // expose the redundant index. Positively verify that context before absence.
  await scrollToControl(screen, screen.getByText('定例会議 · 標準', { exact: true }));
  await expect(screen.getByText('定例会議 · 標準', { exact: true })).toBeVisible();
  await expect(screen.getByText('要約履歴（1）', { exact: true })).toBeVisible();
  await expect(screen.getByText('要約の項目と原文', { exact: true })).not.toBeVisible();
  await app.screenshot('summary-template-without-redundant-source-index');
  await openSummaryPoster(screen);
  await expect(screen.getByTestId('summary.poster.image')).toBeVisible();
  await tapControl(screen.getByRole('button', { name: '拡大して読む', exact: true }));
  await tapControl(screen.getByRole('button', { name: '全体を表示', exact: true }));
  await app.screenshot('summary-legacy-literal-excerpt-no-inferred-decision');
  await tapControl(screen.getByTestId('summary.poster.export'));
  await tapControl(screen.getByRole('button', { name: '共有先・保存先を選ぶ', exact: true }));
  await expect.poll(() => pngFiles().length).toBe(1);
  const sparsePath = join(folder, pngFiles()[0]);
  const sparse = readFileSync(sparsePath);
  expect(sparse.subarray(0, 8).toString('hex')).toBe('89504e470d0a1a0a');
  expect(sparse.readUInt32BE(16)).toBe(1440);
  expect(sparse.readUInt32BE(20)).toBeGreaterThan(0);
  expect(sparse.readUInt32BE(20)).toBeLessThan(fullPosterHeight);
  writeFileSync(join(artifacts, marker + '-sparse.png'), sparse, { flag: 'wx' });
  await tapControl(screen.getByRole('button', { name: /^(Close|閉じる)$/ }).first());
  await expect.poll(() => existsSync(sparsePath)).toBe(false);
  const finalRecord = JSON.parse(sql(database, "SELECT CAST(data AS TEXT) FROM documents WHERE key='memoraMeetings';"))[0];
  expect(finalRecord.summaryVersions).toHaveLength(1);
  expect(finalRecord.summaryVersions[0].markdown).toBe(legacyRecords[0].summary);
  expect(finalRecord.transcript[0].text).toBe(raw);
});
