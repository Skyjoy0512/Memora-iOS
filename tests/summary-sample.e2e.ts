import { randomUUID } from 'node:crypto';
import { afterEach, test } from '@e2e-dev/mobile';
import { expect } from 'e2e';
import { seedSummaryFixture } from './summary-fixture-helpers';
import { sql } from './sqlite-fixture-helpers';
import { tapControl, tapTab, scrollToControl } from './ui-helpers';

afterEach(async ({ device }) => { await device.setAppearance('light'); });

test('summary sample is additive, recoverable and displays its image without a tap', { timeout: 360_000 }, async ({ app, device, screen }) => {
  const { database, fixture } = await seedSummaryFixture(app, device, screen);
  const records = () => JSON.parse(sql(database, "SELECT CAST(data AS TEXT) FROM documents WHERE key='memoraMeetings';"));
  const sampleID = '77777777-7777-7777-7777-777777777777';
  const title = '発売準備ミーティング（サンプル）';
  async function settings() {
    await tapControl(screen.getByRole('button', { name: /^(Back|戻る|前に戻る|ライブラリ)$/ }).first());
    await tapControl(screen.getByLabel('メニュー').first());
    await tapControl(screen.getByTestId('sidebar.settings'));
    const diagnostics = screen.getByTestId('settings.category.diagnostics');
    await scrollToControl(screen, diagnostics);
    await tapControl(diagnostics);
  }
  await settings();
  const trigger = 'sample_failure_' + randomUUID().replaceAll('-', '');
  sql(database, `CREATE TRIGGER ${trigger} BEFORE INSERT ON documents WHEN NEW.key='memoraMeetings' BEGIN SELECT RAISE(ABORT, 'isolated sample save failure'); END;`);
  try {
    await tapControl(screen.getByTestId('summary.sample.open'));
    await expect(screen.getByTestId('summary.sample.failure')).toBeVisible();
    expect(records()).toEqual([fixture]);
    await expect(screen.getByTestId('summary.sample.open')).toBeVisible();
  } finally { sql(database, `DROP TRIGGER ${trigger};`); }
  await tapControl(screen.getByTestId('summary.sample.open'));
  // During the native push, Library and detail can both expose this title.
  await expect(screen.getByText(title, { exact: true, visible: true }).last()).toBeVisible();
  await expect(screen.getByText('表示用の架空データです。実際の音声・AI処理の結果ではありません。', { exact: true })).toBeVisible();
  await expect(screen.getByTestId('summary.poster.inline')).toBeVisible();
  await app.screenshot('inline-summary-sample-light');
  expect(records()).toHaveLength(2);
  expect(records().find((record: any) => record.id.toLowerCase() === fixture.id.toLowerCase())).toMatchObject({
    ...fixture, id: fixture.id.toUpperCase(),
    transcript: fixture.transcript.map((segment: any) => ({ ...segment, id: segment.id.toUpperCase() })),
  });
  let sample = records().find((record: any) => record.id.toLowerCase() === sampleID);
  expect(sample.audioURL).toBeUndefined();
  expect(sample.summary).toContain('  - 理由：');
  const reason = screen.getByRole('button', { name: '理由：初回テストでは、設定項目の多さが録音開始を妨げていた。', exact: true });
  await scrollToControl(screen, reason);
  await expect(reason).toBeVisible();
  await app.screenshot('summary-branch-hierarchy-light');
  await device.setAppearance('dark');
  await app.screenshot('summary-branch-hierarchy-dark');
  const editedReason = '理由：検証前のため、効果はまだ確定していない。';
  await tapControl(reason);
  await screen.getByRole('textbox', { name: '本文', exact: true }).fill(editedReason);
  await tapControl(screen.getByRole('button', { name: '完了', exact: true }));
  await expect.poll(() => records().find((record: any) => record.id.toLowerCase() === sampleID).summary.includes('  - ' + editedReason)).toBe(true);
  sample = records().find((record: any) => record.id.toLowerCase() === sampleID);
  await settings();
  await tapControl(screen.getByTestId('summary.sample.open'));
  await expect(screen.getByTestId('summary.poster.inline')).toBeVisible();
  expect(records()).toHaveLength(2);
  expect(records().find((record: any) => record.id.toLowerCase() === sampleID)).toEqual(sample);
  await app.screenshot('inline-summary-sample-dark');
  await app.restart();
  expect(records()).toHaveLength(2);
  expect(records().find((record: any) => record.id.toLowerCase() === sampleID)).toEqual(sample);
  await tapTab(screen, 'ライブラリ');
  await tapControl(screen.getByRole('button', { name: 'サンプルを削除', exact: true }));
  await tapControl(screen.getByRole('button', { name: '削除', exact: true }));
  await expect.poll(() => records().length).toBe(1);
  expect(records()[0].id.toLowerCase()).toBe(fixture.id.toLowerCase());
  expect(records()[0].summary).toBe(fixture.summary);
});
