import { existsSync, mkdirSync, readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { afterEach, test } from '@e2e-dev/mobile';
import { expect } from 'e2e';
import { seedSummaryFixture } from './summary-fixture-helpers';
import { sql } from './sqlite-fixture-helpers';
import { tapControl, tapTab, scrollToControl, openSummaryPoster } from './ui-helpers';

afterEach(async ({ device }) => { await device.setAppearance('light'); });

test('summary decisions remain editable without transcript confirmation links', { timeout: 240_000 }, async ({ app, device, screen }) => {
  const { database, title, fixture, raw, summary } = await seedSummaryFixture(app, device, screen);
  const read = () => JSON.parse(sql(database, "SELECT CAST(data AS TEXT) FROM documents WHERE key='memoraMeetings';"));
  // This UUID-marked, fresh test database is owned by the fixture helper.
  // One exact source match and one unmatched decision used to show both labels.
  await device.closeApp();
  const records = read();
  expect(records).toHaveLength(1);
  expect(records[0].id.toLowerCase()).toBe(fixture.id.toLowerCase());
  // Match TranscriptSegment's existing canonical encoding, so a legacy default
  // added on the next save is not mistaken for a changed speaker assignment.
  for (const segment of records[0].transcript) {
    expect(segment.speakerIsCertain).toBe(true);
    expect(segment.identificationStatus ?? 'manual').toBe('manual');
    segment.identificationStatus = 'manual';
  }
  const normalizedTranscript = (segments: any[]) => segments.map(segment => ({ ...segment, id: segment.id.toLowerCase() }));
  const originalTranscript = normalizedTranscript(records[0].transcript);
  const unmatched = '次回の確認日は未定です。';
  records[0].decisions = [raw, unmatched];
  const bytes = Buffer.from(JSON.stringify(records), 'utf8').toString('hex');
  sql(database, `UPDATE documents SET data=X'${bytes}' WHERE key='memoraMeetings';`);
  await app.restart();
  await tapTab(screen, 'ライブラリ');
  await tapControl(screen.getByRole('button', { name: new RegExp('^' + title) }).first());
  await scrollToControl(screen, screen.getByRole('button', { name: '決まったこと', exact: true }));
  await tapControl(screen.getByRole('button', { name: '決まったこと', exact: true }));
  const first = screen.getByRole('button', { name: raw, exact: true });
  await scrollToControl(screen, first);
  await expect(first).toBeVisible();
  await expect(screen.getByRole('button', { name: unmatched, exact: true })).toBeVisible();
  await expect(screen.getByRole('button', { name: /^(文字起こしを確認|一致する発言：)/ })).toHaveCount(0);
  await app.screenshot('summary-decisions-without-transcript-links');
  await tapControl(first);
  const field = screen.getByRole('textbox', { name: '本文', exact: true });
  await expect(field).toHaveValue([raw, unmatched].join('\n'));
  await expect(field).toBeFocused();
  const edited = '予算の承認はまだ得られていません。';
  await field.fill([edited, unmatched].join('\n'));
  await tapControl(screen.getByRole('button', { name: '完了', exact: true }));
  await expect.poll(() => read()[0].decisions).toEqual([edited, unmatched]);
  expect(read()[0].summary).toBe(summary);
  expect(normalizedTranscript(read()[0].transcript)).toEqual(originalTranscript);
  await app.restart();
  await tapTab(screen, 'ライブラリ');
  await tapControl(screen.getByRole('button', { name: new RegExp('^' + title) }).first());
  await scrollToControl(screen, screen.getByRole('button', { name: edited, exact: true }));
  await expect(screen.getByRole('button', { name: edited, exact: true })).toBeVisible();
  await expect(screen.getByRole('button', { name: /^(文字起こしを確認|一致する発言：)/ })).toHaveCount(0);
  const transcript = screen.getByRole('button', { name: '文字起こし', exact: true });
  await scrollToControl(screen, transcript, { minimumY: 90, maximumY: 750 });
  await tapControl(transcript);
  await screen.getByTestId('transcript.readable').uncheck();
  await expect(screen.getByRole('button', { name: raw, exact: true })).toBeVisible();
  expect(normalizedTranscript(read()[0].transcript)).toEqual(originalTranscript);
  await app.screenshot('original-transcript-still-available');
});

test('long summary images stay bounded while preserving the complete saved summary', { timeout: 180_000 }, async ({ app, device, screen }) => {
  const sentence = '正式な承認がなければ、本番には反映しません。';
  const long = sentence.repeat(20);
  const summary = `## 会議の概要\n${long}\n## 決定事項\n- 検証：${long}\n- 再確認：${long}\n- 公開前の確認\n## アクションアイテム\n- 条件確認：${long}\n- 対象確認：${long}\n- 日時確認\n## 未決事項\n- 承認日：${long}\n- 担当者：${long}\n- 確認先`;
  const { database, marker } = await seedSummaryFixture(app, device, screen, {
    summary, raw: sentence, segmentID: '81818181-8181-4181-8181-818181818181', timestamp: 0,
  });
  await expect(screen.getByTestId('summary.poster.inline')).toBeVisible();
  await openSummaryPoster(screen);
  await expect(screen.getByTestId('summary.poster.image')).toBeVisible();
  await app.screenshot('bounded-long-summary-image-light');
  await device.setAppearance('dark');
  await app.screenshot('bounded-long-summary-image-dark');
  await tapControl(screen.getByTestId('summary.poster.export'));
  await tapControl(screen.getByRole('button', { name: '共有先・保存先を選ぶ', exact: true }));
  const folder = join(resolve(dirname(database), '../../..'), 'tmp');
  const files = () => readdirSync(folder).filter(name => /^Memora-summary-[a-f0-9-]+\.png$/i.test(name));
  await expect.poll(() => files().length).toBe(1);
  const path = join(folder, files()[0]);
  const png = readFileSync(path);
  expect(png.subarray(0, 8).toString('hex')).toBe('89504e470d0a1a0a');
  expect(png.readUInt32BE(16)).toBe(1440);
  expect(png.readUInt32BE(20)).toBeGreaterThan(1221);
  expect(png.readUInt32BE(20)).toBeLessThanOrEqual(2400);
  const artifacts = join('.e2e', 'regression', 'summary-poster-artifacts');
  mkdirSync(artifacts, { recursive: true });
  writeFileSync(join(artifacts, marker + '-long.png'), png, { flag: 'wx' });
  await tapControl(screen.getByRole('button', { name: /^(Close|閉じる)$/ }).first());
  await expect.poll(() => existsSync(path)).toBe(false);
  await tapControl(screen.getByRole('tab', { name: '全文', exact: true }));
  await expect(screen.getByRole('tab', { name: '全文', exact: true })).toBeVisible();
  expect(JSON.parse(sql(database, "SELECT CAST(data AS TEXT) FROM documents WHERE key='memoraMeetings';"))[0].summary).toBe(summary);
});
