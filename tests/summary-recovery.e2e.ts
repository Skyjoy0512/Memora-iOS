import { randomUUID } from 'node:crypto';
import { chmodSync, existsSync, lstatSync, readFileSync, readdirSync, realpathSync, statSync } from 'node:fs';
import { dirname, join, resolve, sep } from 'node:path';
import { afterEach, test } from '@e2e-dev/mobile';
import { expect } from 'e2e';
import { tapControl, tapTab } from './ui-helpers';
import { sql } from './sqlite-fixture-helpers';
import { seedSummaryFixture } from './summary-fixture-helpers';

afterEach(async ({ device }) => { await device.setAppearance('light'); });

test('failed transcript saves keep the stored record and durable or in-memory draft', { timeout: 300_000 }, async ({ app, device, screen }) => {
  const { database, fixture, title, raw } = await seedSummaryFixture(app, device, screen);
  const read = () => JSON.parse(sql(database, "SELECT CAST(data AS TEXT) FROM documents WHERE key='memoraMeetings';"));
  const draftKey = `draft.meeting.${fixture.id.toUpperCase()}.transcript.${fixture.transcript[0].id.toUpperCase()}`;
  const draft = () => sql(database, `SELECT hex(data) FROM documents WHERE key='${draftKey}';`);
  const trigger = 'transcript_failure_' + randomUUID().replaceAll('-', '');
  const firstEdit = 'えーと、訂正：12万円ではなく10万円です。';
  const secondEdit = '予算の承認はまだ得られていません。';
  let installed = false;
  const inject = (rejectDraft: boolean) => {
    sql(database, `CREATE TRIGGER ${trigger} BEFORE INSERT ON documents WHEN NEW.key='memoraMeetings'${rejectDraft ? ` OR NEW.key='${draftKey}'` : ''} BEGIN SELECT RAISE(ABORT, 'isolated transcript save failure'); END;`);
    installed = true;
  };
  const recover = () => { if (installed) { sql(database, `DROP TRIGGER ${trigger};`); installed = false; } };
  const field = screen.getByRole('textbox', { name: '本文', exact: true });
  const finish = () => tapControl(screen.getByRole('button', { name: '完了', exact: true }));
  async function dismissFailure() {
    await expect(screen.getByText('データを保存できませんでした。ストレージの空き容量を確認してください。', { exact: true })).toBeVisible();
    await tapControl(screen.getByRole('button', { name: 'OK', exact: true }));
  }
  try {
    await tapControl(screen.getByRole('button', { name: '文字起こし', exact: true }));
    await screen.getByTestId('transcript.readable').uncheck();
    await tapControl(screen.getByRole('button', { name: raw, exact: true }));
    await field.fill(firstEdit);
    const original = read();
    inject(false);
    await finish();
    await dismissFailure();
    expect(read()).toEqual(original);
    await expect(screen.getByRole('button', { name: raw, exact: true })).toBeVisible();
    const storedDraft = Buffer.from(draft(), 'hex');
    expect(storedDraft[0]).toBe(1);
    expect(storedDraft.subarray(1).toString('utf8')).toBe(firstEdit);
    await app.screenshot('transcript-save-failure-keeps-original');
    // The next check is draft restoration, not startup write failure. Leaving
    // the trigger installed can present an unrelated launch-time save alert.
    recover();
    await app.restart();
    await tapTab(screen, 'ライブラリ');
    await tapControl(screen.getByRole('button', { name: new RegExp('^' + title) }).first());
    await tapControl(screen.getByRole('button', { name: '文字起こし', exact: true }));
    await tapControl(screen.getByRole('button', { name: raw, exact: true }));
    await expect(field).toHaveValue(firstEdit);
    await expect(screen.getByText('書きかけの内容を復元しました', { exact: true })).toBeVisible();
    await app.screenshot('transcript-draft-restored-after-restart');
    await finish();
    await expect.poll(() => read()[0].transcript[0].text).toBe(firstEdit);
    await expect.poll(draft).toBe('');
    const committed = read();
    inject(true);
    await tapControl(screen.getByRole('button', { name: firstEdit, exact: true }));
    await field.fill(secondEdit);
    await finish();
    await dismissFailure();
    expect(read()).toEqual(committed);
    expect(draft()).toBe('');
    await tapControl(screen.getByRole('button', { name: firstEdit, exact: true }));
    await expect(field).toHaveValue(secondEdit);
    await app.screenshot('transcript-memory-draft-when-draft-storage-also-fails');
    recover();
    await finish();
    await expect.poll(() => read()[0].transcript[0].text).toBe(secondEdit);
    await expect.poll(draft).toBe('');
    await app.restart();
    expect(read()[0].transcript[0]).toMatchObject({ text: secondEdit, speaker: '話者1', timestamp: 0 });
    expect(read()[0].summary).toBe(fixture.summary);
  } finally { recover(); }
});

test('PNG write failure keeps the preview and a retry uses the real share sheet', { timeout: 180_000 }, async ({ app, device, screen }) => {
  const { database } = await seedSummaryFixture(app, device, screen);
  const container = realpathSync(resolve(dirname(database), '../../..'));
  const folder = join(container, 'tmp');
  if (!lstatSync(folder).isDirectory() || lstatSync(folder).isSymbolicLink() || !realpathSync(folder).startsWith(container + sep)) throw new Error('Unsafe temporary directory');
  const originalMode = statSync(folder).mode & 0o777;
  if ((originalMode & 0o200) === 0) throw new Error('Fixture temp folder was already unwritable');
  const pngFiles = () => readdirSync(folder).filter(name => /^Memora-summary-[a-f0-9-]+\.png$/i.test(name));
  await tapControl(screen.getByTestId('summary.poster.open'));
  await expect(screen.getByTestId('summary.poster.image')).toBeVisible();
  const originalFiles = pngFiles();
  async function exportPNG() {
    await tapControl(screen.getByTestId('summary.poster.export'));
    await tapControl(screen.getByRole('button', { name: '共有先・保存先を選ぶ', exact: true }));
  }
  // Restrict only this positively identified, fresh test container's tmp write
  // bit. This simulates an I/O failure; it never changes user data/permissions.
  try {
    chmodSync(folder, originalMode & ~0o222);
    await exportPNG();
    await expect(screen.getByText('画像を書き出せませんでした', { exact: true })).toBeVisible();
    expect(pngFiles()).toEqual(originalFiles);
    await app.screenshot('summary-png-write-failure');
    await tapControl(screen.getByRole('button', { name: 'OK', exact: true }));
    await expect(screen.getByTestId('summary.poster.image')).toBeVisible();
  } finally { chmodSync(folder, originalMode); }
  await exportPNG();
  await expect(screen.getByRole('listitem', { name: /^(Copy|コピー)$/ }).first()).toBeVisible();
  await expect.poll(() => pngFiles().length).toBe(originalFiles.length + 1);
  const name = pngFiles().find(name => !originalFiles.includes(name));
  if (!name) throw new Error('Retry did not produce a new PNG');
  const path = join(folder, name);
  const png = readFileSync(path);
  expect(png.subarray(0, 8).toString('hex')).toBe('89504e470d0a1a0a');
  await app.screenshot('summary-png-write-retry-share-sheet');
  await tapControl(screen.getByRole('button', { name: /^(Close|閉じる)$/ }).first());
  await expect.poll(() => existsSync(path)).toBe(false);
  await expect(screen.getByTestId('summary.poster.image')).toBeVisible();
});
